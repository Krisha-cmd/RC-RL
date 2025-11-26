#!/usr/bin/env python3
"""
Complete receiver - handles logs at ANY position in data stream
Extracts LOG:...END\n section and uses remaining bytes for image
Now expecting: IMAGE (4096 bytes) + LOGS (variable size)
"""
import serial
import time
import numpy as np
from PIL import Image
import csv

PORT = 'COM4'
BAUD = 115200

def send_image(ser):
    img_array = np.random.randint(0, 256, (128, 128, 3), dtype=np.uint8)
    img_bytes = img_array.tobytes()
    print(f"Sending {len(img_bytes)} bytes (128x128 RGB)...")
    ser.write(img_bytes)
    ser.flush()
    print("✓ Sent\n")

def decode_log_entry(entry_val):
    """Decode 32-bit performance log entry"""
    return {
        'raw': entry_val,
        'core_busy': (entry_val >> 28) & 0xF,
        'fifo1_load': (entry_val >> 25) & 0x7,
        'fifo2_load': (entry_val >> 22) & 0x7,
        'fifo3_load': (entry_val >> 19) & 0x7,
        'core0_div': (entry_val >> 15) & 0xF,
        'core1_div': (entry_val >> 11) & 0xF,
        'core2_div': (entry_val >> 7) & 0xF,
        'core3_div': (entry_val >> 3) & 0xF,
    }

def parse_logs(data, start_pos=0):
    """Parse log data starting at given position"""
    # Look for LOG:
    log_pos = data.find(b'LOG:', start_pos)
    if log_pos < 0:
        return None, "No LOG: header"
    
    if log_pos + 6 > len(data):
        return None, "Incomplete header"
    
    # Get count
    count = int.from_bytes(data[log_pos+4:log_pos+6], 'big')
    expected_size = 4 + 2 + (count * 4) + 4
    
    # Parse entries
    entries = []
    entry_start = log_pos + 6
    for i in range(count):
        pos = entry_start + (i * 4)
        if pos + 4 <= len(data):
            val = int.from_bytes(data[pos:pos+4], 'big')
            entries.append(decode_log_entry(val))
    
    # Find END
    end_pos = data.find(b'END\n', log_pos)
    
    return {
        'log_start': log_pos,
        'log_end': log_pos + expected_size if end_pos < 0 else end_pos + 4,
        'count': count,
        'entries': entries,
        'has_end': end_pos >= 0,
        'expected_size': expected_size
    }, None

def main():
    print("=" * 70)
    print("FPGA Image + Performance Logger Receiver")
    print("Expected: Image (4096 bytes) + Logs (LOG:...END\\n)")
    print("=" * 70)
    
    with serial.Serial(PORT, BAUD, timeout=0.1) as ser:
        send_image(ser)
        
        # Collect data - STOP at exactly 4096 bytes (expected image size)
        IMAGE_SIZE = 4096
        print("Receiving image data...")
        all_data = bytearray()
        start = time.time()
        last_recv = start
        
        while (time.time() - start) < 30:
            if ser.in_waiting > 0:
                new_data = ser.read(ser.in_waiting)
                all_data.extend(new_data)
                last_recv = time.time()
                print(f"  [{time.time()-start:5.2f}s] +{len(new_data):4d} bytes (total: {len(all_data)})")
                
                # Stop when we have the expected image size
                if len(all_data) >= IMAGE_SIZE:
                    print(f"\n✓ Received {IMAGE_SIZE} bytes (image complete)")
                    break
            
            if (time.time() - last_recv) > 5 and len(all_data) > 0:
                print("\n⚠ Timeout before receiving full image")
                break
            time.sleep(0.01)
        
        print(f"\n{'='*70}")
        print(f"IMAGE RECEIVED: {len(all_data)} bytes")
        print(f"{'='*70}\n")
        
        # Save image first (first 4096 bytes)
        print("--- Image Data ---")
        if len(all_data) >= IMAGE_SIZE:
            image_data = all_data[:IMAGE_SIZE]
            print(f"  Using first {IMAGE_SIZE} bytes as image")
            
            img_array = np.frombuffer(bytes(image_data), dtype=np.uint8).reshape((64, 64))
            img = Image.fromarray(img_array, mode='L')
            img.save('received_image.png')
            print(f"  ✓ Saved received_image.png")
        else:
            print(f"  ✗ Insufficient data: {len(all_data)} < {IMAGE_SIZE}")
            if len(all_data) > 0:
                img_data = bytes(all_data) + b'\x00' * (IMAGE_SIZE - len(all_data))
                img_array = np.frombuffer(img_data, dtype=np.uint8).reshape((64, 64))
                img = Image.fromarray(img_array, mode='L')
                img.save('received_image.png')
                print(f"  ⚠ Saved partial image ({len(all_data)} bytes, padded)")
        
        # Now try to receive performance logs separately
        print(f"\n--- Performance Logs ---")
        print("Waiting for logs (timeout: 5s)...")
        
        log_data = bytearray()
        log_start_time = time.time()
        log_timeout = 5.0
        
        while (time.time() - log_start_time) < log_timeout:
            if ser.in_waiting > 0:
                new_log_data = ser.read(ser.in_waiting)
                log_data.extend(new_log_data)
                print(f"  Received {len(new_log_data)} log bytes (total: {len(log_data)})")
                
                # Check if we have complete log (LOG: ... END\n)
                if b'LOG:' in log_data and b'END\n' in log_data:
                    print("  ✓ Log markers found")
                    break
            time.sleep(0.01)
        
        if len(log_data) > 0:
            print(f"\n  Total log data: {len(log_data)} bytes")
            
            # Look for LOG: header
            log_start = log_data.find(b'LOG:')
            if log_start >= 0:
                print(f"  ✓ LOG: found at position {log_start}")
                
                # Find END\n footer
                end_pos = log_data.find(b'END\n', log_start)
                if end_pos >= 0:
                    log_end = end_pos + 4
                    print(f"  ✓ END found at position {end_pos}")
                    
                    # Parse log data
                    if log_start + 6 <= len(log_data):
                        count = int.from_bytes(log_data[log_start+4:log_start+6], 'big')
                        print(f"  Entry count: {count}")
                        
                        # Parse entries
                        entries = []
                        entry_start = log_start + 6
                        for i in range(count):
                            pos = entry_start + (i * 4)
                            if pos + 4 <= len(log_data):
                                val = int.from_bytes(log_data[pos:pos+4], 'big')
                                entries.append(decode_log_entry(val))
                        
                        print(f"  Entries parsed: {len(entries)}")
                        
                        # Show first few entries
                        if entries:
                            print(f"\n  First 5 entries:")
                            for i, e in enumerate(entries[:5]):
                                if e['raw'] == 0xDEADBEEF:
                                    print(f"    [{i}] 0xDEADBEEF - DEFAULT")
                                else:
                                    print(f"    [{i}] Busy:{e['core_busy']:04b} "
                                          f"FIFOs:[{e['fifo1_load']},{e['fifo2_load']},{e['fifo3_load']}] "
                                          f"Divs:[{e['core0_div']},{e['core1_div']},{e['core2_div']},{e['core3_div']}]")
                            
                            # Save CSV
                            with open('performance_logs.csv', 'w', newline='') as f:
                                writer = csv.DictWriter(f, fieldnames=[
                                    'entry', 'raw_hex', 'core_busy', 'fifo1', 'fifo2', 'fifo3',
                                    'div0', 'div1', 'div2', 'div3'
                                ])
                                writer.writeheader()
                                for i, e in enumerate(entries):
                                    writer.writerow({
                                        'entry': i,
                                        'raw_hex': f"0x{e['raw']:08X}",
                                        'core_busy': f"{e['core_busy']:04b}",
                                        'fifo1': e['fifo1_load'],
                                        'fifo2': e['fifo2_load'],
                                        'fifo3': e['fifo3_load'],
                                        'div0': e['core0_div'],
                                        'div1': e['core1_div'],
                                        'div2': e['core2_div'],
                                        'div3': e['core3_div'],
                                    })
                            print(f"  ✓ Saved performance_logs.csv")
                    else:
                        print(f"  ✗ Incomplete log header")
                else:
                    print(f"  ⚠ LOG: found but no END footer")
            else:
                print(f"  ✗ No LOG: header found")
                print(f"  First 50 bytes: {' '.join(f'{b:02X}' for b in log_data[:50])}")
        else:
            print("  No log data received")
        
        print(f"\n{'='*70}")
        print("COMPLETE")
        print(f"{'='*70}")

if __name__ == "__main__":
    main()
