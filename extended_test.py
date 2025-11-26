#!/usr/bin/env python3
import serial
import time
from PIL import Image
import numpy as np

def main():
    port = 'COM4'
    baudrate = 115200
    
    with serial.Serial(port, baudrate, timeout=0.1) as ser:
        print("=== EXTENDED LOG TEST ===")
        
        # Send image
        img_array = np.random.randint(0, 256, (128, 128, 3), dtype=np.uint8)
        img_bytes = img_array.tobytes()
        print(f"Sending {len(img_bytes)} bytes...")
        ser.write(img_bytes)
        ser.flush()
        
        # Collect data with extended timeout
        print("Waiting for response (30 second timeout)...")
        all_data = bytearray()
        start_time = time.time()
        last_receive_time = start_time
        
        while (time.time() - start_time) < 30:
            if ser.in_waiting > 0:
                new_data = ser.read(ser.in_waiting)
                all_data.extend(new_data)
                last_receive_time = time.time()
                print(f"[{time.time()-start_time:6.2f}s] Received {len(new_data)} bytes, total: {len(all_data)}")
            
            # Stop if no new data for 5 seconds
            if (time.time() - last_receive_time) > 5 and len(all_data) > 0:
                print("No new data for 5 seconds. Stopping...")
                break
            
            time.sleep(0.01)
        
        print(f"\\nFinal: {len(all_data)} bytes received")
        
        # Analyze the data
        # FPGA sends 4094 image bytes (not 4096)
        IMAGE_BYTES = 4094
        
        if len(all_data) >= IMAGE_BYTES:
            extra_bytes = len(all_data) - IMAGE_BYTES
            print(f"Image: {IMAGE_BYTES} bytes, Extra: {extra_bytes} bytes")
            
            # Save the received image
            try:
                img_data = all_data[:IMAGE_BYTES]
                # Pad to 4096 to make 64x64 square
                img_data_padded = bytes(img_data) + b'\\x00\\x00'
                img_array = np.frombuffer(img_data_padded, dtype=np.uint8).reshape((64, 64))
                img = Image.fromarray(img_array, mode='L')
                img.save("received_image.png")
                print("✓ Saved received_image.png")
            except Exception as e:
                print(f"Image save error: {e}")
            
            # Analyze log data
            if extra_bytes > 0:
                extra_data = all_data[IMAGE_BYTES:]
                print(f"\\n--- Log Data Analysis ---")
                print(f"Extra bytes (first 50): {' '.join(f'{b:02X}' for b in extra_data[:50])}")
                
                # Look for LOG:
                log_pos = extra_data.find(b'LOG:')
                if log_pos >= 0:
                    print(f"Found LOG: at position {log_pos} in extra data")
                    if log_pos + 6 <= len(extra_data):
                        count_bytes = extra_data[log_pos+4:log_pos+6]
                        count = int.from_bytes(count_bytes, 'big')
                        print(f"Entry count: {count}")
                        
                        expected_log_size = 4 + 2 + (count * 4) + 4  # LOG: + count + entries + END\\n
                        print(f"Expected log size: {expected_log_size} bytes")
                        print(f"Actual extra size: {extra_bytes} bytes")
                        
                        if extra_bytes >= expected_log_size:
                            print("✓ Complete log received")
                        else:
                            missing = expected_log_size - extra_bytes
                            print(f"✗ Missing {missing} bytes from log")
                        
                        # Check for END
                        end_pos = extra_data.find(b'END\\n')
                        if end_pos >= 0:
                            print(f"✓ Found END at position {end_pos}")
                        else:
                            print("✗ No END found")
                        
                        # Show first few entries
                        if count > 0 and log_pos + 6 + 4 <= len(extra_data):
                            print("\\nFirst few log entries:")
                            entries_start = log_pos + 6
                            for i in range(min(5, count)):
                                if entries_start + (i*4) + 4 <= len(extra_data):
                                    entry_bytes = extra_data[entries_start + (i*4):entries_start + (i*4) + 4]
                                    entry_val = int.from_bytes(entry_bytes, 'big')
                                    print(f"  Entry {i}: 0x{entry_val:08X}")
                                    if entry_val == 0xDEADBEEF:
                                        print(f"    -> DEFAULT TEST ENTRY")
                                    else:
                                        # Decode the entry
                                        core_busy = (entry_val >> 28) & 0xF
                                        fifo1_load = (entry_val >> 25) & 0x7
                                        fifo2_load = (entry_val >> 22) & 0x7
                                        fifo3_load = (entry_val >> 19) & 0x7
                                        core0_div = (entry_val >> 15) & 0xF
                                        core1_div = (entry_val >> 11) & 0xF
                                        core2_div = (entry_val >> 7) & 0xF
                                        core3_div = (entry_val >> 3) & 0xF
                                        print(f"    Core busy: {core_busy:04b}, FIFOs: [{fifo1_load},{fifo2_load},{fifo3_load}], Dividers: [{core0_div},{core1_div},{core2_div},{core3_div}]")
                else:
                    print("✗ No LOG: header found in extra data")
                    print("\\nAttempting to parse as raw log data (assuming LOG: header might be at the start)...")
                    # Maybe the LOG: is at position 0
                    if extra_data[:4] == b'LOG:':
                        print("✓ LOG: found at start of extra data!")
                    else:
                        # Show what we have instead
                        print(f"First 4 bytes: {extra_data[:4]}")
                        print(f"As ASCII: {''.join(chr(b) if 32 <= b <= 126 else '.' for b in extra_data[:20])}")

if __name__ == "__main__":
    main()