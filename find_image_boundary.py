#!/usr/bin/env python3
"""
Find the actual boundary between image and log data
"""
import serial
import time
import numpy as np
from PIL import Image

PORT = 'COM4'
BAUD = 115200

def send_image(ser):
    """Send test image"""
    img_array = np.random.randint(0, 256, (128, 128, 3), dtype=np.uint8)
    img_bytes = img_array.tobytes()
    print(f"Sending {len(img_bytes)} bytes...")
    ser.write(img_bytes)
    ser.flush()
    print("Sent!")

def test_image_size(data, size):
    """Test if a given size produces a valid-looking image"""
    if len(data) < size:
        return False, "Insufficient data"
    
    try:
        # Try to create image
        img_data = data[:size]
        
        # Pad if needed to make square
        target_size = 4096  # 64x64
        if size < target_size:
            img_data = bytes(img_data) + b'\x00' * (target_size - size)
        
        img_array = np.frombuffer(img_data[:target_size], dtype=np.uint8).reshape((64, 64))
        
        # Check if image looks reasonable (some variation, not all same value)
        std_dev = np.std(img_array)
        mean_val = np.mean(img_array)
        
        return True, f"std={std_dev:.1f}, mean={mean_val:.1f}"
    except Exception as e:
        return False, str(e)

def main():
    with serial.Serial(PORT, BAUD, timeout=0.1) as ser:
        send_image(ser)
        
        # Collect all data
        print("Collecting data...")
        all_data = bytearray()
        start = time.time()
        last_recv = start
        
        while (time.time() - start) < 30:
            if ser.in_waiting > 0:
                all_data.extend(ser.read(ser.in_waiting))
                last_recv = time.time()
            if (time.time() - last_recv) > 5 and len(all_data) > 0:
                break
            time.sleep(0.01)
        
        print(f"\nTotal: {len(all_data)} bytes\n")
        
        # Search for LOG: pattern
        log_positions = []
        for i in range(len(all_data) - 3):
            if all_data[i:i+4] == b'LOG:':
                log_positions.append(i)
        
        if log_positions:
            print(f"Found LOG: at positions: {log_positions}")
            for pos in log_positions:
                print(f"\n--- LOG: at byte {pos} ---")
                print(f"Context: ...{all_data[max(0,pos-10):pos+20].hex()}...")
        else:
            print("✗ No LOG: header found anywhere in data")
        
        # Test different image sizes
        print("\n--- Testing different image sizes ---")
        for size in [4090, 4092, 4094, 4096, 4098, 4100]:
            valid, info = test_image_size(all_data, size)
            marker = "✓" if valid else "✗"
            print(f"{marker} {size:4d} bytes: {info}")
            
            if valid and size <= len(all_data):
                # Check what comes after
                if size + 4 <= len(all_data):
                    next_bytes = all_data[size:size+20]
                    next_hex = ' '.join(f'{b:02X}' for b in next_bytes)
                    next_ascii = ''.join(chr(b) if 32 <= b <= 126 else '.' for b in next_bytes)
                    print(f"       Next 20 bytes: {next_hex}")
                    print(f"       As ASCII: [{next_ascii}]")
        
        # Try to find where reasonable image data ends
        print("\n--- Looking for image data patterns ---")
        
        # Save attempts with different sizes
        for size in [4094, 4096]:
            if size <= len(all_data):
                try:
                    img_data = all_data[:size]
                    if size < 4096:
                        img_data = bytes(img_data) + b'\x00' * (4096 - size)
                    
                    img_array = np.frombuffer(img_data[:4096], dtype=np.uint8).reshape((64, 64))
                    img = Image.fromarray(img_array, mode='L')
                    filename = f"test_{size}.png"
                    img.save(filename)
                    print(f"Saved {filename}")
                except Exception as e:
                    print(f"Failed at {size}: {e}")

if __name__ == "__main__":
    main()
