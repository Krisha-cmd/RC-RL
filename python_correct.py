#!/usr/bin/env python3
"""
send_and_receive_with_perf_logs.py

Send an image's raw bytes over a serial link while simultaneously
listening for returned bytes, logging them, and reconstructing
an output image when complete. After image reception, receives
performance logs from the FPGA and saves them to CSV.

This variant expects:
- 64x64 Grayscale output (64*64*1 = 4,096 bytes)
- Performance logs after image completion
- Pipeline: 128x128 RGB input -> resizer -> grayscale -> 64x64 grayscale output

Log Protocol:
- Header: "LOG:" (4 bytes)
- Count: 2 bytes (big-endian, number of log entries)
- Data: N entries × 4 bytes each
- Footer: "END\n" (4 bytes)

Log Entry Format (32 bits):
- [31:28] core_busy (4 bits): resizer, grayscale, diffamp, blur
- [27:25] fifo3_load (3 bits)
- [24:22] fifo2_load (3 bits)
- [21:19] fifo1_load (3 bits)
- [18:15] core3_divider (4 bits)
- [14:11] core2_divider (4 bits)
- [10:7]  core1_divider (4 bits)
- [6:3]   core0_divider (4 bits)
- [2:0]   reserved (3 bits)
"""
import argparse
import os
import sys
import threading
import time
import struct
from datetime import datetime

try:
    import serial
except Exception as e:
    print("Missing dependency: pyserial. Install with: pip install pyserial")
    raise

try:
    from PIL import Image
except Exception as e:
    print("Missing dependency: Pillow. Install with: pip install pillow")
    raise


def read_image_bytes(path, width, height, grayscale=False):
    img = Image.open(path).convert('RGB')
    # If image size differs from requested, resize using a high-quality filter
    if img.width != width or img.height != height:
        img = img.resize((width, height), Image.LANCZOS)
    data = img.tobytes()
    if grayscale:
        # convert RGB -> single byte gray per pixel using luma
        out = bytearray()
        for i in range(0, len(data), 3):
            r = data[i]; g = data[i+1]; b = data[i+2]
            y = (0.299*r + 0.587*g + 0.114*b)
            out.append(int(y) & 0xFF)
        return bytes(out)
    return data


def send_thread_fn(ser, payload, send_header, width, height):
    # Optional header: b'IMG' + width(2) + height(2) + size(4)
    if send_header:
        header = b'IMG' + struct.pack('>HHI', width, height, len(payload))
        ser.write(header)
        ser.flush()
        time.sleep(0.01)

    # Send in chunks to avoid OS/driver buffering surprises
    CHUNK = 1024
    sent = 0
    start = time.time()
    while sent < len(payload):
        chunk = payload[sent:sent+CHUNK]
        ser.write(chunk)
        ser.flush()
        sent += len(chunk)
        # tiny pause to avoid overwhelming a small UART receiver
        time.sleep(0.0005)
    return time.time() - start


def receiver_thread_fn(ser, out_bin_path, log_csv_path, expected_bytes, grayscale, stop_event, done_event, timeout_idle):
    """Read from serial until expected size is received or idle timeout reached.
    Appends bytes to out_bin_path and writes periodic CSV log entries (timestamp, total_bytes).
    """
    buf = bytearray()
    last_recv_time = time.time()
    with open(out_bin_path, 'wb') as fout, open(log_csv_path, 'w', newline='') as flog:
        flog.write('timestamp,bytes_received\n')
        while not stop_event.is_set():
            try:
                data = ser.read(4096)
            except Exception as e:
                print('Serial read error:', e)
                break
            if data:
                fout.write(data)
                fout.flush()
                buf.extend(data)
                last_recv_time = time.time()
                flog.write(f"{datetime.utcnow().isoformat()}Z,{len(buf)}\n")
            else:
                # no data read
                if expected_bytes and len(buf) >= expected_bytes:
                    break
                # idle timeout
                if (time.time() - last_recv_time) > timeout_idle and len(buf) > 0:
                    # Assume transmission finished
                    break
            if expected_bytes and len(buf) >= expected_bytes:
                break
        # final flush
        fout.flush()
    # mark done and provide buffer length
    done_event.set()
    return len(buf)


def parse_log_entry(entry_bytes):
    """Parse a 32-bit log entry into individual fields.
    
    Returns dict with:
    - core0_busy, core1_busy, core2_busy, core3_busy (bool)
    - fifo1_load, fifo2_load, fifo3_load (int)
    - core0_divider, core1_divider, core2_divider, core3_divider (int)
    """
    # Big-endian 32-bit unsigned
    value = struct.unpack('>I', entry_bytes)[0]
    
    # Extract fields
    core_busy = (value >> 28) & 0xF
    fifo3_load = (value >> 25) & 0x7
    fifo2_load = (value >> 22) & 0x7
    fifo1_load = (value >> 19) & 0x7
    core3_divider = (value >> 15) & 0xF
    core2_divider = (value >> 11) & 0xF
    core1_divider = (value >> 7) & 0xF
    core0_divider = (value >> 3) & 0xF
    
    return {
        'core0_busy': bool(core_busy & 0x1),
        'core1_busy': bool(core_busy & 0x2),
        'core2_busy': bool(core_busy & 0x4),
        'core3_busy': bool(core_busy & 0x8),
        'fifo1_load': fifo1_load,
        'fifo2_load': fifo2_load,
        'fifo3_load': fifo3_load,
        'core0_divider': core0_divider,
        'core1_divider': core1_divider,
        'core2_divider': core2_divider,
        'core3_divider': core3_divider
    }


def receive_performance_logs(ser, perf_csv_path, timeout=5.0):
    """Receive performance logs after image transmission.
    
    Expected protocol:
    - "LOG:" header (4 bytes)
    - Count (2 bytes, big-endian)
    - N × 4-byte entries
    - "END\n" footer (4 bytes)
    """
    print("Waiting for performance logs...")
    
    # Wait for "LOG:" header
    start_time = time.time()
    header = bytearray()
    while len(header) < 4:
        if time.time() - start_time > timeout:
            print("Timeout waiting for log header")
            return False
        data = ser.read(1)
        if data:
            header.extend(data)
    
    if header != b'LOG:':
        print(f"Invalid log header: {header}")
        return False
    
    print("Log header received")
    
    # Read entry count (2 bytes)
    count_bytes = ser.read(2)
    if len(count_bytes) != 2:
        print("Failed to read entry count")
        return False
    
    entry_count = struct.unpack('>H', count_bytes)[0]
    print(f"Expecting {entry_count} log entries")
    
    # Read log entries
    entries = []
    for i in range(entry_count):
        entry_bytes = ser.read(4)
        if len(entry_bytes) != 4:
            print(f"Failed to read entry {i}")
            return False
        entries.append(parse_log_entry(entry_bytes))
    
    # Read footer
    footer = ser.read(4)
    if footer != b'END\n':
        print(f"Invalid log footer: {footer}")
        return False
    
    print(f"Received {len(entries)} log entries successfully")
    
    # Write to CSV
    with open(perf_csv_path, 'w', newline='') as fcsv:
        # Write header
        fcsv.write('entry_index,core0_busy,core1_busy,core2_busy,core3_busy,')
        fcsv.write('fifo1_load,fifo2_load,fifo3_load,')
        fcsv.write('core0_divider,core1_divider,core2_divider,core3_divider\n')
        
        # Write data
        for i, entry in enumerate(entries):
            fcsv.write(f"{i},")
            fcsv.write(f"{int(entry['core0_busy'])},")
            fcsv.write(f"{int(entry['core1_busy'])},")
            fcsv.write(f"{int(entry['core2_busy'])},")
            fcsv.write(f"{int(entry['core3_busy'])},")
            fcsv.write(f"{entry['fifo1_load']},")
            fcsv.write(f"{entry['fifo2_load']},")
            fcsv.write(f"{entry['fifo3_load']},")
            fcsv.write(f"{entry['core0_divider']},")
            fcsv.write(f"{entry['core1_divider']},")
            fcsv.write(f"{entry['core2_divider']},")
            fcsv.write(f"{entry['core3_divider']}\n")
    
    print(f"Performance logs saved to {perf_csv_path}")
    return True


def reconstruct_image(bin_path, out_image_path, width, height, grayscale=False):
    with open(bin_path, 'rb') as f:
        data = f.read()
    if grayscale:
        mode = 'L'
        expected = width * height
        if len(data) < expected:
            # pad with zeros to expected length so we can still create an image
            sys.stdout.write(f"Warning: only {len(data)} of {expected} grayscale bytes received — padding with zeros.\n")
            data = data + bytes(expected - len(data))
        img = Image.frombytes(mode, (width, height), data[:expected])
    else:
        mode = 'RGB'
        expected = width * height * 3
        if len(data) < expected:
            sys.stdout.write(f"Warning: only {len(data)} of {expected} RGB bytes received — padding with zeros.\n")
            data = data + bytes(expected - len(data))
        img = Image.frombytes(mode, (width, height), data[:expected])
    img.save(out_image_path)


def main():
    # Hardcoded configuration - edit these values as needed
    PORT = 'COM4'
    BAUD = 115200
    INFILE = 'input/images.png'  # path relative to repo root
    OUT_DIR = 'output'
    WIDTH = 128
    HEIGHT = 128
    GRAYSCALE = False
    SEND_HEADER = False
    TIMEOUT_IDLE = 2.0
    
    # Expected output dimensions (64x64 Grayscale)
    OUT_WIDTH = 64
    OUT_HEIGHT = 64
    OUT_GRAYSCALE = True  # Grayscale output

    # Validate input file exists
    if not os.path.exists(INFILE):
        print('Hardcoded input file not found:', INFILE)
        sys.exit(2)
    os.makedirs(OUT_DIR, exist_ok=True)

    width = WIDTH
    height = HEIGHT
    grayscale = bool(GRAYSCALE)

    payload = read_image_bytes(INFILE, width, height, grayscale=grayscale)
    # We send 128x128 RGB payload (width*height*3) and expect 64x64 Grayscale (64*64*1) back
    expected = OUT_WIDTH * OUT_HEIGHT * 1

    basename = os.path.splitext(os.path.basename(INFILE))[0]
    timestamp = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    out_bin = os.path.join(OUT_DIR, f"{basename}_received_{timestamp}.bin")
    out_img = os.path.join(OUT_DIR, f"{basename}_received_{timestamp}.png")
    log_csv = os.path.join(OUT_DIR, f"{basename}_recv_log_{timestamp}.csv")
    perf_csv = os.path.join(OUT_DIR, f"{basename}_perf_log_{timestamp}.csv")

    print(f"Opening serial port {PORT} @ {BAUD}")
    print(f"Sending {len(payload)} bytes (128x128 RGB)")
    print(f"Expecting {expected} bytes (64x64 Grayscale)")
    
    ser = serial.Serial(PORT, BAUD, timeout=0.05)
    time.sleep(0.05)
    # flush any residual
    ser.reset_input_buffer(); ser.reset_output_buffer()

    stop_event = threading.Event()
    done_event = threading.Event()

    recv_thread = threading.Thread(target=receiver_thread_fn, args=(ser, out_bin, log_csv, expected, OUT_GRAYSCALE, stop_event, done_event, TIMEOUT_IDLE), daemon=True)
    recv_thread.start()

    send_start = time.time()
    try:
        send_dur = send_thread_fn(ser, payload, SEND_HEADER, width, height)
        print(f"Sent {len(payload)} bytes in {send_dur:.3f}s")
    except Exception as e:
        print('Send error:', e)
        stop_event.set()

    # Wait up to 10 seconds after send for the receiver to collect data
    wait_deadline = time.time() + 10.0
    while not done_event.is_set() and time.time() < wait_deadline:
        time.sleep(0.05)

    # signal stop and give the reader a moment to flush
    stop_event.set()
    time.sleep(0.05)

    # Reconstruct image from whatever was received (pad if incomplete)
    try:
        reconstruct_image(out_bin, out_img, OUT_WIDTH, OUT_HEIGHT, grayscale=OUT_GRAYSCALE)
        print('Reconstructed image saved to', out_img)
    except Exception as e:
        print('Could not reconstruct image:', e)

    print('Raw received bytes logged to', out_bin)
    print('Receive log (CSV) written to', log_csv)
    
    # Now receive performance logs
    print("\n--- Performance Log Reception ---")
    try:
        success = receive_performance_logs(ser, perf_csv, timeout=5.0)
        if not success:
            print("Failed to receive performance logs")
    except Exception as e:
        print(f"Error receiving performance logs: {e}")
    
    ser.close()
    print("\nAll operations complete!")


if __name__ == '__main__':
    main()
