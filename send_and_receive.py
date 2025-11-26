#!/usr/bin/env python3
"""
Lightweight sender/receiver for the UART image pipeline.
Sends raw RGB bytes for each image in `input/` (resized to IN_WIDTH x IN_HEIGHT)
and reads back processed grayscale bytes until sentinel b"/0/0" is received.
Writes outputs into `output/` with same base name.

Requirements: pyserial, Pillow
Install: pip install -r requirements.txt
"""
from __future__ import annotations
import sys
import time
import logging
from pathlib import Path
from types import SimpleNamespace

try:
    import serial
except ImportError:
    serial = None
try:
    from PIL import Image
except ImportError:
    Image = None

logger = logging.getLogger('send_and_receive')
SENTINEL = b"/0/0"
DEFAULT_PORT = 'COM4'
DEFAULT_BAUD = 115200

class SimpleSender:
    def __init__(self, port: str, baud: int, timeout: float = 2.0):
        if serial is None:
            raise RuntimeError('pyserial not installed. Run: pip install pyserial')
        self.ser = serial.Serial(port=port, baudrate=baud, timeout=timeout)
        logger.info('Opened %s @ %d', port, baud)

    def close(self):
        try:
            if self.ser and self.ser.is_open:
                self.ser.close()
        except Exception:
            pass

    def send_and_receive_sentinel(self, payload: bytes, read_timeout: float = 10.0) -> bytes:
        # Write payload, then read until sentinel appears
        self.ser.write(payload)
        self.ser.flush()
        logger.debug('Sent %d bytes', len(payload))
        end_time = time.time() + read_timeout
        window = bytearray()
        out = bytearray()
        # ensure non-blocking small reads by using the configured timeout
        while time.time() < end_time:
            b = self.ser.read(1)
            if not b:
                # no data this cycle
                continue
            out.extend(b)
            window.extend(b)
            if len(window) > len(SENTINEL):
                del window[0:len(window)-len(SENTINEL)]
            if bytes(window) == SENTINEL:
                # strip sentinel and return
                return bytes(out[:-len(SENTINEL)])
        raise TimeoutError('Timed out waiting for sentinel')


def load_image_bytes(path: Path, in_w: int, in_h: int) -> bytes:
    if Image is None:
        raise RuntimeError('Pillow not installed. Run: pip install Pillow')
    img = Image.open(path).convert('RGB')
    # Force resize to the required dimensions
    if (img.width != in_w) or (img.height != in_h):
        img = img.resize((in_w, in_h), Image.Resampling.LANCZOS)
    data = img.tobytes()
    # Sanity check: RGB bytes per pixel
    if len(data) != in_w * in_h * 3:
        raise RuntimeError(f'Unexpected image byte length {len(data)} for {path}; expected {in_w*in_h*3}')
    return data


def save_grayscale_bytes(data: bytes, out_path: Path, out_w: int, out_h: int):
    if Image is None:
        out_path.write_bytes(data)
        return
    expected = out_w * out_h
    if len(data) == expected:
        img = Image.frombytes('L', (out_w, out_h), data)
        img.save(out_path)
    else:
        # don't try to interpret, save raw
        out_path.write_bytes(data)


def main(argv=None):
    # Enforce 128x128 input dimensions
    IN_W = 128
    IN_H = 128
    args = SimpleNamespace(
        input_dir='input',
        output_dir='output',
        port=DEFAULT_PORT,
        baud=DEFAULT_BAUD,
        in_width=IN_W,
        in_height=IN_H,
        out_width=IN_W // 2,
        out_height=IN_H // 2,
        read_timeout=10.0,
        log_level='INFO'
    )

    logging.basicConfig(level=getattr(logging, args.log_level), format='[%(levelname)s] %(message)s')
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    images = sorted([p for p in input_dir.iterdir() if p.is_file() and p.suffix.lower() in {'.png','.jpg','.jpeg','.bmp'}])
    if not images:
        logger.error('No images in %s', input_dir)
        return 1

    sender = SimpleSender(args.port, args.baud, timeout=0.1)
    try:
        for idx, p in enumerate(images, start=1):
            logger.info('Sending %s', p.name)
            payload = load_image_bytes(p, args.in_width, args.in_height)
            # Validate payload length: must be IN_W * IN_H * 3 (RGB)
            expected_len = args.in_width * args.in_height * 3
            if len(payload) != expected_len:
                logger.error('Image payload size mismatch for %s: %d != expected %d', p.name, len(payload), expected_len)
                continue
            try:
                data = sender.send_and_receive_sentinel(payload, read_timeout=args.read_timeout)
            except TimeoutError as e:
                logger.error('Timeout while waiting for response for %s', p.name)
                continue
            out_name = f'{p.stem}_out{p.suffix}'
            out_path = output_dir / out_name
            save_grayscale_bytes(data, out_path, args.out_width, args.out_height)
            logger.info('Saved received data to %s (%d bytes)', out_path, len(data))
    finally:
        sender.close()
    return 0

if __name__ == '__main__':
    sys.exit(main())
