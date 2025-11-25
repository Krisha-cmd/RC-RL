#!/usr/bin/env python3
"""
Send images over UART (COM4) one at a time, waiting for a response
before sending the next. Responses are saved as processed images and
CSV log entries.

Protocol (configurable):
1. Default (length header): Host sends a 0x5A start byte + 4-byte little-endian
   payload length, then raw image bytes. Device responds with 0xA5 + 4-byte
   length + processed bytes.
2. Sentinel mode: Host just streams raw bytes; device sends processed bytes
   terminated by a sentinel token (default b"/0/0").

You can choose mode with --mode length or --mode sentinel.
If mode=length and device does not provide a length header, script will timeout.
If mode=sentinel, script reads until sentinel appears, excluding sentinel.

Image serialization:
- For typical 24-bit RGB images, bytes = PIL Image converted to RGB then .tobytes().
- The hardware design expects a stream of bytes; adapt preprocessing if needed
  (e.g., resize to 128x128). Use --in-width/--in-height to enforce resize.

Output image reconstruction:
- If --out-width/--out-height provided and output is grayscale, we attempt to
  reconstruct an 8-bit image from received bytes. Otherwise we just store raw bytes
  in an image with original size (or fallback raw dump if sizes mismatch).

CSV log per input image: <image_base>.csv with columns:
  id,input_name,bytes_sent,bytes_received,duration_s,output_image_path,mode,success,timestamp

Requirements: pyserial, Pillow
Install: pip install -r requirements.txt
"""
from __future__ import annotations
from types import SimpleNamespace
import csv
import logging
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import serial  # pyserial
except ImportError:
    serial = None
try:
    from PIL import Image
except ImportError:
    Image = None

DEFAULT_BAUD = 115200
DEFAULT_PORT = "COM4"
SENTINEL_DEFAULT = b"/0/0"  # adjustable
START_BYTE = 0x5A
RESP_BYTE = 0xA5

logger = logging.getLogger("uart_image_sender")

class UartImageSender:
    def __init__(self, port: str, baud: int, timeout: float):
        if serial is None:
            raise RuntimeError("pyserial not installed. Run: pip install pyserial")
        self.ser = serial.Serial(port=port, baudrate=baud, timeout=timeout)
        logger.info("Opened %s @ %d baud", port, baud)

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
            logger.info("Closed serial port")

    def send_with_length(self, payload: bytes, read_timeout: float, expected_len: Optional[int] = None) -> bytes:
        """
        Send payload with length header. If remote responds with RESP_BYTE header, use that
        length. If not (Verilog may stream raw bytes), fall back to reading `expected_len`
        bytes (if provided) or whatever arrives before timeout.
        """
        length = len(payload)
        header = bytes([START_BYTE]) + length.to_bytes(4, "little")
        self.ser.write(header + payload)
        self.ser.flush()
        logger.debug("Sent header+payload (%d bytes)", length)
        # Wait for response header (or fallback to raw)
        start_time = time.time()
        self.ser.timeout = read_timeout
        hdr = self.ser.read(5)
        # If we got a proper header from device, use its length
        if len(hdr) >= 5 and hdr[0] == RESP_BYTE:
            resp_len = int.from_bytes(hdr[1:5], "little")
            data = bytearray()
            while len(data) < resp_len:
                chunk = self.ser.read(resp_len - len(data))
                if not chunk:
                    raise TimeoutError("Timed out receiving response payload")
                data.extend(chunk)
            logger.debug("Received response (%d bytes)", resp_len)
            logger.info("Transfer complete in %.3fs", time.time() - start_time)
            return bytes(data)

        # Fallback: device did not send RESP header (common when FPGA streams raw bytes)
        # Treat any bytes already read (hdr) as part of the payload and continue
        data = bytearray()
        if hdr:
            data.extend(hdr)

        # If expected_len provided, read until that many bytes collected
        if expected_len is not None and expected_len > 0:
            # we've already got len(data) bytes; continue until expected_len
            while len(data) < expected_len:
                chunk = self.ser.read(expected_len - len(data))
                if not chunk:
                    # timeout occurred
                    break
                data.extend(chunk)
            logger.debug("Fallback: collected %d bytes (expected %d)", len(data), expected_len)
            logger.info("Transfer (fallback) complete in %.3fs", time.time() - start_time)
            return bytes(data)

        # No expected length: read until timeout and return whatever arrived
        while True:
            chunk = self.ser.read(1024)
            if not chunk:
                break
            data.extend(chunk)
        logger.debug("Fallback: collected %d bytes (no expected length)", len(data))
        logger.info("Transfer (fallback) complete in %.3fs", time.time() - start_time)
        return bytes(data)

    def send_with_sentinel(self, payload: bytes, sentinel: bytes, read_timeout: float) -> bytes:
        self.ser.write(payload)
        self.ser.flush()
        logger.debug("Sent payload (%d bytes) sentinel mode", len(payload))
        start_time = time.time()
        self.ser.timeout = read_timeout
        data = bytearray()
        window = bytearray()
        while True:
            b = self.ser.read(1)
            if not b:
                raise TimeoutError("Timed out waiting for sentinel in response")
            data.extend(b)
            window.extend(b)
            if len(window) > len(sentinel):
                # keep window length bounded
                del window[0:len(window) - len(sentinel)]
            if bytes(window) == sentinel:
                data = data[:-len(sentinel)]  # remove sentinel
                break
        logger.debug("Received response (%d bytes before sentinel)", len(data))
        logger.info("Transfer complete in %.3fs", time.time() - start_time)
        return bytes(data)


def load_image_bytes(path: Path, in_width: Optional[int], in_height: Optional[int]) -> bytes:
    if Image is None:
        raise RuntimeError("Pillow not installed. Run: pip install Pillow")
    img = Image.open(path).convert("RGB")
    if in_width and in_height:
        img = img.resize((in_width, in_height), Image.Resampling.LANCZOS)
    return img.tobytes()


def reconstruct_output_image(data: bytes, out_path: Path, out_width: Optional[int], out_height: Optional[int], original_ext: str) -> None:
    if Image is None:
        # dump raw bytes if Pillow missing
        out_path.write_bytes(data)
        return
    if out_width and out_height:
        expected = out_width * out_height
        # Assume grayscale single byte per pixel
        if len(data) == expected:
            img = Image.frombytes("L", (out_width, out_height), data)
            img.save(out_path)
            return
    # Fallback: try original RGB size guess if length matches
    # Not robust; user may adapt.
    out_path.write_bytes(data)


def write_csv(csv_path: Path, row: dict) -> None:
    write_header = not csv_path.exists()
    with csv_path.open("a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=row.keys())
        if write_header:
            w.writeheader()
        w.writerow(row)


def process_folder(args):
    input_dir = Path(args.input_dir)
    out_img_dir = Path(args.output_dir)
    out_csv_dir = Path(args.output_csv_dir)
    out_img_dir.mkdir(parents=True, exist_ok=True)
    out_csv_dir.mkdir(parents=True, exist_ok=True)

    images = sorted([p for p in input_dir.iterdir() if p.is_file() and p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.bmp', '.tiff'}])
    if not images:
        logger.error("No images found in %s", input_dir)
        return 1

    sender = UartImageSender(args.port, args.baud, args.timeout)
    start_global = time.time()
    success_count = 0
    try:
        for idx, img_path in enumerate(images, start=1):
            t0 = time.time()
            try:
                payload = load_image_bytes(img_path, args.in_width, args.in_height)
                if args.mode == 'length':
                    expected = None
                    if getattr(args, 'out_width', None) and getattr(args, 'out_height', None):
                        expected = int(args.out_width) * int(args.out_height)
                    resp = sender.send_with_length(payload, args.read_timeout, expected_len=expected)
                else:
                    resp = sender.send_with_sentinel(payload, args.sentinel, args.read_timeout)
                # Prepare output naming
                base = img_path.stem
                out_img_name = f"{base}_{idx}{img_path.suffix}" if img_path.suffix else f"{base}_{idx}.bin"
                out_img_path = out_img_dir / out_img_name
                reconstruct_output_image(resp, out_img_path, args.out_width, args.out_height, img_path.suffix)
                csv_path = out_csv_dir / f"{base}.csv"
                write_csv(csv_path, {
                    'id': idx,
                    'input_name': img_path.name,
                    'bytes_sent': len(payload),
                    'bytes_received': len(resp),
                    'duration_s': round(time.time() - t0, 6),
                    'output_image_path': str(out_img_path),
                    'mode': args.mode,
                    'success': True,
                    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')
                })
                success_count += 1
                logger.info("Processed %s -> %s", img_path.name, out_img_name)
            except Exception as e:
                # Attempt to read any bytes that may have been received from device
                bytes_received = 0
                try:
                    if hasattr(sender, 'ser') and sender.ser is not None:
                        # read whatever is currently available in the input buffer
                        avail = 0
                        try:
                            avail = sender.ser.in_waiting
                        except Exception:
                            avail = 0
                        if avail > 0:
                            _buf = sender.ser.read(avail)
                            bytes_received = len(_buf)
                except Exception:
                    bytes_received = 0

                csv_path = out_csv_dir / f"{img_path.stem}.csv"
                write_csv(csv_path, {
                    'id': idx,
                    'input_name': img_path.name,
                    'bytes_sent': len(payload) if 'payload' in locals() else 0,
                    'bytes_received': bytes_received,
                    'duration_s': round(time.time() - t0, 6),
                    'output_image_path': '',
                    'mode': args.mode,
                    'success': False,
                    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S')
                })
                logger.error("Failed %s: %s (bytes_received=%d)", img_path.name, e, bytes_received)
                if args.stop_on_error:
                    break
        logger.info("Completed %d/%d images in %.2fs", success_count, len(images), time.time() - start_global)
    finally:
        sender.close()
    return 0 if success_count == len(images) else 2


# Configuration: hardcoded paths and UART/settings
# Edit these variables below to match your environment.
def get_hardcoded_args():
    return SimpleNamespace(
        input_dir='input',            # folder containing input images
        output_dir='output',
        output_csv_dir='output_csv',
        port=DEFAULT_PORT,
        baud=DEFAULT_BAUD,
        timeout=2.0,
        read_timeout=10.0,
        mode='length',                 # 'length' or 'sentinel'
        sentinel=SENTINEL_DEFAULT,
        in_width=128,                  # resize inputs to this (or None)
        in_height=128,
        out_width=64,                  # expected output image size for reconstruction
        out_height=64,
        stop_on_error=False,
        log_level='INFO'
    )


def main(argv=None):
    args = get_hardcoded_args()
    logging.basicConfig(level=getattr(logging, args.log_level), format='[%(levelname)s] %(message)s')
    return process_folder(args)

if __name__ == '__main__':
    sys.exit(main())
