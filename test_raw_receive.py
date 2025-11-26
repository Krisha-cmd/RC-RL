#!/usr/bin/env python3
"""
test_raw_receive.py

Simple diagnostic script to monitor exactly what bytes are being received
Sends 128x128 RGB image and shows progressive byte count.
"""
import serial
import time
from datetime import datetime
from PIL import Image

PORT = 'COM4'
BAUD = 115200
TIMEOUT = 15.0  # Total timeout in seconds
INFILE = 'input/images.png'

def send_image(ser, img_path):
    """Send 128x128 RGB image"""
    img = Image.open(img_path).convert('RGB')
    if img.width != 128 or img.height != 128:
        img = img.resize((128, 128), Image.LANCZOS)
    
    payload = img.tobytes()
    print(f"Sending {len(payload)} bytes (128x128 RGB)...\n")
    
    # Send in chunks
    CHUNK = 1024
    sent = 0
    while sent < len(payload):
        chunk = payload[sent:sent+CHUNK]
        ser.write(chunk)
        ser.flush()
        sent += len(chunk)
        time.sleep(0.001)  # Small delay
    
    print(f"Sent complete!\n")

print(f"Opening serial port {PORT} @ {BAUD}")
print(f"Monitoring for {TIMEOUT} seconds...")
print("Expected: 4096 bytes (64x64 grayscale) + optional logs\n")

ser = serial.Serial(PORT, BAUD, timeout=0.1)
time.sleep(0.1)
ser.reset_input_buffer()
ser.reset_output_buffer()

# Send image first
send_image(ser, INFILE)

received_bytes = bytearray()
last_recv_time = time.time()
start_time = time.time()
last_count = 0

print("Time(s) | Total Bytes | New Bytes | Last 10 Bytes (hex)")
print("-" * 70)

try:
    while True:
        # Check timeout
        if (time.time() - start_time) > TIMEOUT:
            print("\nTimeout reached")
            break
        
        # Read available data
        data = ser.read(1024)
        
        if data:
            received_bytes.extend(data)
            last_recv_time = time.time()
            elapsed = last_recv_time - start_time
            new_count = len(received_bytes)
            new_bytes = new_count - last_count
            
            # Show last 10 bytes as hex
            last_10 = received_bytes[-10:] if len(received_bytes) >= 10 else received_bytes
            hex_str = ' '.join([f'{b:02X}' for b in last_10])
            
            print(f"{elapsed:6.2f}  | {new_count:11d} | {new_bytes:9d} | {hex_str}")
            last_count = new_count
        else:
            # No data received
            if len(received_bytes) > 0 and (time.time() - last_recv_time) > 2.0:
                print(f"\nNo new data for 2 seconds. Stopping...")
                break
        
        time.sleep(0.01)

except KeyboardInterrupt:
    print("\n\nStopped by user")

ser.close()

print("\n" + "=" * 70)
print(f"Total bytes received: {len(received_bytes)}")
print(f"Time elapsed: {time.time() - start_time:.2f}s")

# Look for specific patterns
if len(received_bytes) > 0:
    print("\n--- Data Analysis ---")
    
    # Check for "LOG:" header
    log_idx = received_bytes.find(b'LOG:')
    if log_idx >= 0:
        print(f"✓ Found 'LOG:' header at byte {log_idx}")
        if log_idx + 6 <= len(received_bytes):
            count_bytes = received_bytes[log_idx+4:log_idx+6]
            count = int.from_bytes(count_bytes, byteorder='big')
            print(f"  Log entry count: {count}")
    else:
        print("✗ 'LOG:' header not found")
    
    # Check for "END\n" footer
    end_idx = received_bytes.find(b'END\n')
    if end_idx >= 0:
        print(f"✓ Found 'END\\n' footer at byte {end_idx}")
    else:
        print("✗ 'END\\n' footer not found")
    
    # Look for deadbeef pattern
    deadbeef_pattern = bytes([0xDE, 0xAD, 0xBE, 0xEF])
    deadbeef_idx = received_bytes.find(deadbeef_pattern)
    if deadbeef_idx >= 0:
        print(f"✓ Found DEADBEEF pattern at byte {deadbeef_idx}")
    else:
        print("✗ DEADBEEF pattern not found")
    
    # Show first and last 20 bytes
    print("\nFirst 20 bytes (hex):")
    first_20 = received_bytes[:20]
    print(' '.join([f'{b:02X}' for b in first_20]))
    
    print("\nLast 20 bytes (hex):")
    last_20 = received_bytes[-20:]
    print(' '.join([f'{b:02X}' for b in last_20]))
    
    # Check if we got exactly 4094 or 4096
    if len(received_bytes) == 4094:
        print("\n⚠ WARNING: Received exactly 4094 bytes (missing 2 bytes for image)")
    elif len(received_bytes) == 4096:
        print("\n✓ Received exactly 4096 bytes (complete image)")
    elif len(received_bytes) > 4096:
        print(f"\n✓ Received {len(received_bytes) - 4096} extra bytes after image (likely logs!)")

print("\n" + "=" * 70)
print("Test complete. Send image from FPGA to see data flow.")
