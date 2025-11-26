#!/usr/bin/env python3
"""
Complete image and performance log receiver for FPGA UART
- Receives 4094-byte grayscale image (64x64 minus 2 bytes)
- Receives performance logs with format: LOG: + count(2B) + entries(4B each) + END\n
- Saves image as PNG
- Decodes and displays performance log entries
"""

import serial
import time
from PIL import Image
import numpy as np
import csv

# Configuration
PORT = 'COM4'
BAUD = 115200
TIMEOUT = 30
IMAGE_BYTES = 4094  # FPGA sends 4094 bytes for 64x64 image

def send_image(ser, width=128, height=128):
    """Send a test image to FPGA"""
    img_array = np.random.randint(0, 256, (height, width, 3), dtype=np.uint8)
    img_bytes = img_array.tobytes()
    print(f"Sending {len(img_bytes)} bytes ({width}x{height} RGB)...")
    ser.write(img_bytes)
    ser.flush()
    print("✓ Image sent")

def save_image(data, filename="received_image.png"):
    """Save received grayscale image"""
    if len(data) < IMAGE_BYTES:
        print(f"✗ Insufficient data: {len(data)} < {IMAGE_BYTES}")
        return False
    
    try:
        # Extract image data (4094 bytes)
        img_data = data[:IMAGE_BYTES]
        # Pad to 4096 for 64x64 reshape
        img_padded = bytes(img_data) + b'\x00\x00'
        img_array = np.frombuffer(img_padded, dtype=np.uint8).reshape((64, 64))
        
        # Save as PNG
        img = Image.fromarray(img_array, mode='L')
        img.save(filename)
        print(f"✓ Image saved: {filename}")
        return True
    except Exception as e:
        print(f"✗ Image save failed: {e}")
        return False

def decode_log_entry(entry_val):
    """Decode a 32-bit performance log entry"""
    return {
        'raw': entry_val,
        'core_busy': (entry_val >> 28) & 0xF,
        'fifo1_load': (entry_val >> 25) & 0x7,
        'fifo2_load': (entry_val >> 22) & 0x7,
        'fifo3_load': (entry_val >> 19) & 0x7,
        'core0_divider': (entry_val >> 15) & 0xF,
        'core1_divider': (entry_val >> 11) & 0xF,
        'core2_divider': (entry_val >> 7) & 0xF,
        'core3_divider': (entry_val >> 3) & 0xF,
    }

def parse_logs(data):
    """Parse performance log data"""
    # Look for LOG: header
    log_start = data.find(b'LOG:')
    if log_start < 0:
        return None, "No LOG: header found"
    
    if log_start + 6 > len(data):
        return None, "Incomplete log header"
    
    # Extract count (2 bytes, big-endian)
    count_bytes = data[log_start+4:log_start+6]
    count = int.from_bytes(count_bytes, 'big')
    
    # Calculate expected size
    expected_size = 4 + 2 + (count * 4) + 4  # LOG: + count + entries + END\n
    actual_size = len(data) - log_start
    
    # Extract entries
    entries = []
    entry_start = log_start + 6
    for i in range(count):
        entry_pos = entry_start + (i * 4)
        if entry_pos + 4 <= len(data):
            entry_bytes = data[entry_pos:entry_pos+4]
            entry_val = int.from_bytes(entry_bytes, 'big')
            entries.append(decode_log_entry(entry_val))
        else:
            break
    
    # Check for END footer
    end_pos = data.find(b'END\n', log_start)
    has_end = end_pos >= 0
    
    return {
        'count': count,
        'entries': entries,
        'expected_size': expected_size,
        'actual_size': actual_size,
        'complete': actual_size >= expected_size and has_end,
        'has_end': has_end
    }, None

def save_logs_csv(entries, filename="performance_logs.csv"):
    """Save decoded log entries to CSV"""
    if not entries:
        print("No entries to save")
        return False
    
    try:
        with open(filename, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=[
                'entry_num', 'raw_hex', 'core_busy_bits', 
                'fifo1_load', 'fifo2_load', 'fifo3_load',
                'core0_div', 'core1_div', 'core2_div', 'core3_div'
            ])
            writer.writeheader()
            
            for i, entry in enumerate(entries):
                writer.writerow({
                    'entry_num': i,
                    'raw_hex': f"0x{entry['raw']:08X}",
                    'core_busy_bits': f"{entry['core_busy']:04b}",
                    'fifo1_load': entry['fifo1_load'],
                    'fifo2_load': entry['fifo2_load'],
                    'fifo3_load': entry['fifo3_load'],
                    'core0_div': entry['core0_divider'],
                    'core1_div': entry['core1_divider'],
                    'core2_div': entry['core2_divider'],
                    'core3_div': entry['core3_divider'],
                })
        
        print(f"✓ Logs saved: {filename}")
        return True
    except Exception as e:
        print(f"✗ CSV save failed: {e}")
        return False

def main():
    print("=" * 70)
    print("FPGA Image Processing + Performance Logger Test")
    print("=" * 70)
    
    with serial.Serial(PORT, BAUD, timeout=0.1) as ser:
        # Send test image
        send_image(ser)
        
        # Collect response
        print(f"\nWaiting for response (timeout: {TIMEOUT}s)...")
        all_data = bytearray()
        start_time = time.time()
        last_receive = start_time
        
        while (time.time() - start_time) < TIMEOUT:
            if ser.in_waiting > 0:
                new_data = ser.read(ser.in_waiting)
                all_data.extend(new_data)
                last_receive = time.time()
                elapsed = time.time() - start_time
                print(f"  [{elapsed:5.2f}s] +{len(new_data):4d} bytes (total: {len(all_data)})")
            
            # Stop if idle for 5 seconds
            if (time.time() - last_receive) > 5 and len(all_data) > 0:
                print("\n✓ Reception complete (5s idle)")
                break
            
            time.sleep(0.01)
        
        # Process received data
        print("\n" + "=" * 70)
        print(f"TOTAL RECEIVED: {len(all_data)} bytes")
        print("=" * 70)
        
        if len(all_data) < IMAGE_BYTES:
            print(f"✗ Insufficient data (need at least {IMAGE_BYTES} bytes)")
            return
        
        # Save image
        print("\n--- Image Processing ---")
        save_image(all_data)
        
        # Parse logs
        extra_bytes = len(all_data) - IMAGE_BYTES
        print(f"\n--- Performance Logs ---")
        print(f"Extra data: {extra_bytes} bytes")
        
        if extra_bytes > 0:
            log_data = all_data[IMAGE_BYTES:]
            result, error = parse_logs(log_data)
            
            if error:
                print(f"✗ {error}")
                print(f"First 100 bytes: {' '.join(f'{b:02X}' for b in log_data[:100])}")
            else:
                print(f"✓ Log header found")
                print(f"  Entry count: {result['count']}")
                print(f"  Entries received: {len(result['entries'])}")
                print(f"  Expected size: {result['expected_size']} bytes")
                print(f"  Actual size: {result['actual_size']} bytes")
                print(f"  Has END footer: {'✓' if result['has_end'] else '✗'}")
                print(f"  Status: {'✓ COMPLETE' if result['complete'] else '✗ INCOMPLETE'}")
                
                if result['entries']:
                    # Show sample entries
                    print(f"\n--- Sample Log Entries (first 5) ---")
                    for i, entry in enumerate(result['entries'][:5]):
                        if entry['raw'] == 0xDEADBEEF:
                            print(f"  [{i:3d}] 0xDEADBEEF - DEFAULT TEST ENTRY")
                        else:
                            print(f"  [{i:3d}] Cores:{entry['core_busy']:04b} "
                                  f"FIFOs:[{entry['fifo1_load']},{entry['fifo2_load']},{entry['fifo3_load']}] "
                                  f"Divs:[{entry['core0_divider']},{entry['core1_divider']},"
                                  f"{entry['core2_divider']},{entry['core3_divider']}]")
                    
                    if len(result['entries']) > 5:
                        print(f"  ... ({len(result['entries'])-5} more entries)")
                    
                    # Save to CSV
                    save_logs_csv(result['entries'])
        else:
            print("No extra data (logs not received)")
        
        print("\n" + "=" * 70)
        print("TEST COMPLETE")
        print("=" * 70)

if __name__ == "__main__":
    main()
