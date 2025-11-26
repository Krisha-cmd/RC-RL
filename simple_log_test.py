#!/usr/bin/env python3
import serial
import time
from PIL import Image
import numpy as np

def send_image(ser):
    """Send a 128x128 RGB image (49152 bytes)"""
    img_array = np.random.randint(0, 256, (128, 128, 3), dtype=np.uint8)
    img_bytes = img_array.tobytes()
    print(f"Sending {len(img_bytes)} bytes (128x128 RGB)...")
    ser.write(img_bytes)
    ser.flush()
    print("Image sent!")

def main():
    port = 'COM4'
    baudrate = 115200
    
    with serial.Serial(port, baudrate, timeout=0.1) as ser:
        print("=== SIMPLE LOG TEST ===")
        
        # Send image
        send_image(ser)
        
        # Collect all data for 5 seconds
        print("Collecting data for 5 seconds...")
        all_data = bytearray()
        start_time = time.time()
        
        while (time.time() - start_time) < 5:
            if ser.in_waiting > 0:
                all_data.extend(ser.read(ser.in_waiting))
            time.sleep(0.01)
        
        print(f"\\nTotal received: {len(all_data)} bytes")
        
        # Expected image bytes
        expected_image = 4096
        
        if len(all_data) >= expected_image:
            print(f"Image data: {expected_image} bytes")
            extra_bytes = len(all_data) - expected_image
            print(f"Extra data: {extra_bytes} bytes")
            
            # Show the boundary area
            print("\\n--- Boundary Analysis ---")
            start_pos = max(0, expected_image - 10)
            end_pos = min(len(all_data), expected_image + 30)
            
            print(f"Bytes {start_pos}-{end_pos-1}:")
            for i in range(start_pos, end_pos):
                if i < len(all_data):
                    byte_val = all_data[i]
                    marker = ""
                    if i == expected_image:
                        marker = " <-- IMAGE END"
                    elif i == expected_image - 1:
                        marker = " <-- LAST IMAGE"
                    
                    # Try to show as ASCII if printable
                    ascii_char = chr(byte_val) if 32 <= byte_val <= 126 else '.'
                    print(f"  [{i:4d}] 0x{byte_val:02X} '{ascii_char}'{marker}")
            
            # Look for LOG pattern specifically 
            extra_data = all_data[expected_image:]
            print(f"\\n--- Extra Data Analysis ---")
            print(f"Extra bytes as hex: {' '.join(f'{b:02X}' for b in extra_data[:20])}...")
            
            # Look for LOG: pattern
            log_pos = extra_data.find(b'LOG:')
            if log_pos >= 0:
                print(f"\\nFound LOG: at position {log_pos} in extra data")
                print(f"Total position in stream: {expected_image + log_pos}")
                
                if log_pos + 6 < len(extra_data):
                    # Extract count
                    count_bytes = extra_data[log_pos+4:log_pos+6]
                    count = int.from_bytes(count_bytes, 'big')
                    print(f"Log count: {count}")
                    
                    # Show first few log entries if any
                    if count > 0 and log_pos + 6 + 4 < len(extra_data):
                        entry_bytes = extra_data[log_pos+6:log_pos+10]
                        entry_val = int.from_bytes(entry_bytes, 'big')
                        print(f"First entry: 0x{entry_val:08X}")
                        if entry_val == 0xDEADBEEF:
                            print("  -> This is the DEFAULT test entry!")
            else:
                print("\\nNo LOG: pattern found in extra data")
        
        else:
            print(f"Only got {len(all_data)} bytes (expected at least {expected_image})")

if __name__ == "__main__":
    main()