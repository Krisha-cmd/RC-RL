#!/usr/bin/env python3
"""
Complete FPGA Image Processing + Performance Logger Receiver

Workflow:
1. Send 128x128 RGB image to FPGA
2. Receive ALL data from FPGA (no early stopping)
3. Extract image from first 4096 bytes (64x64 grayscale)
4. Extract performance logs from remaining data (LOG:...END\n)
5. Save both image and logs

Hardcoded configuration - edit values below as needed
"""
import serial
import time
import numpy as np
from PIL import Image
import csv
import os
from datetime import datetime

# ==================== HARDCODED CONFIGURATION ====================
PORT = 'COM4'
BAUD = 115200
INPUT_IMAGE = 'input/test_cyan_yellow.png'  # Input image path
OUTPUT_DIR = 'output'

# Input image dimensions (what we send to FPGA)
SEND_WIDTH = 128
SEND_HEIGHT = 128
SEND_RGB = True  # Send RGB image

# Expected output from FPGA
RECEIVE_WIDTH = 64
RECEIVE_HEIGHT = 64
RECEIVE_GRAYSCALE = True  # Receive grayscale image

# Reception timeout
IDLE_TIMEOUT = 5.0  # Stop receiving if no data for 5 seconds
MAX_TIMEOUT = 30.0  # Maximum total time to wait

# Expected sizes
IMAGE_SIZE = RECEIVE_WIDTH * RECEIVE_HEIGHT * (1 if RECEIVE_GRAYSCALE else 3)
# ==================================================================


def decode_log_entry(entry_val):
    """Decode 32-bit performance log entry.
    
    Format (32 bits):
    [31:28] core_busy (4 bits - one per core: resizer, gray, diffamp, blur)
    [27:25] fifo1_load (3 bits - 0-7 scale)
    [24:22] fifo2_load (3 bits - 0-7 scale)
    [21:19] fifo3_load (3 bits - 0-7 scale)
    [18:15] core0_divider (4 bits - resizer, 0=full speed)
    [14:11] core1_divider (4 bits - grayscale)
    [10:7]  core2_divider (4 bits - diffamp)
    [6:3]   core3_divider (4 bits - blur)
    [2]     rl_enabled (1 bit - 1=RL agent active)
    [1:0]   reserved
    """
    return {
        'raw': entry_val,
        'core_busy': (entry_val >> 28) & 0xF,
        'core0_busy': (entry_val >> 31) & 0x1,  # resizer
        'core1_busy': (entry_val >> 30) & 0x1,  # grayscale
        'core2_busy': (entry_val >> 29) & 0x1,  # diffamp
        'core3_busy': (entry_val >> 28) & 0x1,  # blur
        'fifo1_load': (entry_val >> 25) & 0x7,
        'fifo2_load': (entry_val >> 22) & 0x7,
        'fifo3_load': (entry_val >> 19) & 0x7,
        'core0_div': (entry_val >> 15) & 0xF,
        'core1_div': (entry_val >> 11) & 0xF,
        'core2_div': (entry_val >> 7) & 0xF,
        'core3_div': (entry_val >> 3) & 0xF,
        'rl_enabled': (entry_val >> 2) & 0x1,
    }


def load_and_resize_image(img_path, width, height, as_rgb=True):
    """Load image, resize to specified dimensions, and convert to bytes.
    
    Args:
        img_path: Path to input image
        width: Target width
        height: Target height
        as_rgb: If True, return RGB bytes; if False, return grayscale
    
    Returns:
        bytearray of image data
    """
    img = Image.open(img_path)
    img = img.resize((width, height), Image.Resampling.LANCZOS)
    
    if as_rgb:
        img = img.convert('RGB')
        img_array = np.array(img, dtype=np.uint8)
    else:
        img = img.convert('L')
        img_array = np.array(img, dtype=np.uint8)
    
    return bytearray(img_array.tobytes())


def send_image(ser, img_bytes):
    """Send image bytes to FPGA via UART."""
    print(f"Sending {len(img_bytes)} bytes to FPGA...")
    
    # Send in chunks for reliability
    CHUNK_SIZE = 1024
    sent = 0
    start_time = time.time()
    
    while sent < len(img_bytes):
        chunk = img_bytes[sent:sent+CHUNK_SIZE]
        ser.write(chunk)
        sent += len(chunk)
        print(f"  Sent {sent}/{len(img_bytes)} bytes ({100*sent//len(img_bytes)}%)")
        time.sleep(0.01)  # Small delay between chunks
    
    ser.flush()
    duration = time.time() - start_time
    print(f"✓ Sent {len(img_bytes)} bytes in {duration:.3f}s\n")


def receive_all_data(ser, idle_timeout, max_timeout):
    """Receive all data from FPGA until idle timeout or max timeout.
    
    Args:
        ser: Serial port object
        idle_timeout: Stop if no data received for this many seconds
        max_timeout: Maximum total time to wait
    
    Returns:
        bytearray of all received data
    """
    print("Receiving data from FPGA...")
    all_data = bytearray()
    start_time = time.time()
    last_recv_time = start_time
    recv_count = 0
    
    while True:
        elapsed = time.time() - start_time
        idle_time = time.time() - last_recv_time
        
        # Check timeouts
        if elapsed > max_timeout:
            print(f"\n⚠ Max timeout ({max_timeout}s) reached")
            break
        
        if idle_time > idle_timeout and len(all_data) > 0:
            print(f"\n✓ Idle timeout ({idle_timeout}s) - reception complete")
            break
        
        # Try to read data
        if ser.in_waiting > 0:
            new_data = ser.read(ser.in_waiting)
            all_data.extend(new_data)
            last_recv_time = time.time()
            recv_count += 1
            print(f"  [{elapsed:5.2f}s] +{len(new_data):4d} bytes (total: {len(all_data):5d}) [recv #{recv_count}]")
            
            # Show data pattern every 1000 bytes
            if len(all_data) % 1000 < len(new_data):
                sample_start = max(0, len(all_data) - 20)
                sample = all_data[sample_start:sample_start+20]
                print(f"    Last 20 bytes: {' '.join(f'{b:02X}' for b in sample)}")
        
        time.sleep(0.01)
    
    print(f"\nTotal received: {len(all_data)} bytes in {recv_count} chunks\n")
    return all_data


def extract_image(data, width, height, grayscale=True):
    """Extract and save image from first bytes of data.
    
    Args:
        data: bytearray containing image data at start
        width: Image width
        height: Image height
        grayscale: True if grayscale, False if RGB
    
    Returns:
        PIL Image object, or None if insufficient data
    """
    expected_size = width * height * (1 if grayscale else 3)
    
    if len(data) < expected_size:
        print(f"⚠ Insufficient data for image: {len(data)} < {expected_size}")
        if len(data) == 0:
            return None
        # Pad with zeros
        image_data = bytes(data) + b'\x00' * (expected_size - len(data))
    else:
        image_data = bytes(data[:expected_size])
    
    try:
        if grayscale:
            img_array = np.frombuffer(image_data, dtype=np.uint8).reshape((height, width))
            img = Image.fromarray(img_array, mode='L')
        else:
            img_array = np.frombuffer(image_data, dtype=np.uint8).reshape((height, width, 3))
            img = Image.fromarray(img_array, mode='RGB')
        return img
    except Exception as e:
        print(f"✗ Error creating image: {e}")
        return None


def extract_performance_logs(data, start_offset=0):
    """Extract performance logs from data starting at offset.
    
    Looks for LOG:...END\n protocol in data.
    
    Args:
        data: bytearray to search
        start_offset: Start searching from this position
    
    Returns:
        List of decoded log entries, or empty list if not found
    """
    # Search for LOG: header
    log_start = data.find(b'LOG:', start_offset)
    if log_start < 0:
        print("✗ No LOG: header found in data")
        if len(data) > start_offset:
            print(f"  First 50 bytes after image: {' '.join(f'{b:02X}' for b in data[start_offset:start_offset+50])}")
        return []
    
    print(f"✓ LOG: header found at position {log_start}")
    
    # Check if we have enough data for count
    if log_start + 6 > len(data):
        print("✗ Incomplete log header (missing count)")
        return []
    
    # Read entry count (2 bytes, big-endian)
    count = int.from_bytes(data[log_start+4:log_start+6], 'big')
    print(f"  Entry count: {count}")
    
    # Find END\n footer
    end_pos = data.find(b'END\n', log_start)
    if end_pos >= 0:
        print(f"✓ END\\n footer found at position {end_pos}")
    else:
        print("⚠ END\\n footer not found (parsing available entries)")
    
    # Parse entries
    entries = []
    entry_start = log_start + 6
    for i in range(count):
        pos = entry_start + (i * 4)
        if pos + 4 > len(data):
            print(f"⚠ Entry {i} incomplete (only {len(data)-pos} bytes available)")
            break
        
        val = int.from_bytes(data[pos:pos+4], 'big')
        entries.append(decode_log_entry(val))
    
    print(f"✓ Parsed {len(entries)} log entries")
    return entries


def save_performance_logs_csv(entries, csv_path):
    """Save performance log entries to CSV file.
    
    Args:
        entries: List of decoded log entry dictionaries
        csv_path: Path to output CSV file
    """
    if not entries:
        print("No log entries to save")
        return
    
    with open(csv_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'entry', 'raw_hex', 'rl_enabled', 'core_busy', 
            'fifo1_load', 'fifo2_load', 'fifo3_load',
            'core0_div', 'core1_div', 'core2_div', 'core3_div'
        ])
        writer.writeheader()
        
        for i, e in enumerate(entries):
            writer.writerow({
                'entry': i,
                'raw_hex': f"0x{e['raw']:08X}",
                'rl_enabled': e.get('rl_enabled', 0),
                'core_busy': f"{e['core_busy']:04b}",
                'fifo1_load': e['fifo1_load'],
                'fifo2_load': e['fifo2_load'],
                'fifo3_load': e['fifo3_load'],
                'core0_div': e['core0_div'],
                'core1_div': e['core1_div'],
                'core2_div': e['core2_div'],
                'core3_div': e['core3_div'],
            })
    
    print(f"✓ Saved {len(entries)} entries to {csv_path}")


def print_log_summary(entries):
    """Print summary of log entries with analysis."""
    if not entries:
        return
    
    # Check RL state
    rl_states = [e.get('rl_enabled', 0) for e in entries]
    rl_enabled = sum(rl_states) > len(rl_states) / 2
    
    print(f"\n{'='*60}")
    print(f"  PERFORMANCE LOG ANALYSIS ({'RL ENABLED' if rl_enabled else 'RL DISABLED'})")
    print(f"{'='*60}")
    print(f"  Total entries: {len(entries)}")
    
    # Calculate averages
    n = len(entries)
    avg_fifo1 = sum(e['fifo1_load'] for e in entries) / n
    avg_fifo2 = sum(e['fifo2_load'] for e in entries) / n
    avg_fifo3 = sum(e['fifo3_load'] for e in entries) / n
    avg_core0 = sum(e['core0_div'] for e in entries) / n
    avg_core1 = sum(e['core1_div'] for e in entries) / n
    avg_core2 = sum(e['core2_div'] for e in entries) / n
    avg_core3 = sum(e['core3_div'] for e in entries) / n
    
    print(f"\n  FIFO Load Averages (0-7 scale, lower = healthier):")
    print(f"    FIFO1 (input->resizer):  {avg_fifo1:.2f}")
    print(f"    FIFO2 (resizer->gray):   {avg_fifo2:.2f}")
    print(f"    FIFO3 (blur->output):    {avg_fifo3:.2f}")
    
    print(f"\n  Core Divider Averages (0=full speed, higher=slower):")
    print(f"    Core0 (resizer):   {avg_core0:.2f}")
    print(f"    Core1 (grayscale): {avg_core1:.2f}")
    print(f"    Core2 (diffamp):   {avg_core2:.2f}")
    print(f"    Core3 (blur):      {avg_core3:.2f}")
    
    # Count divider > 0
    nonzero_div = sum(1 for e in entries if any([e['core0_div'], e['core1_div'], e['core2_div'], e['core3_div']]))
    print(f"\n  Entries with any divider > 0: {nonzero_div}/{n} ({100*nonzero_div/n:.1f}%)")
    
    print(f"\n  First 5 entries:")
    for i, e in enumerate(entries[:5]):
        rl_flag = "RL" if e.get('rl_enabled', 0) else "--"
        print(f"    [{i:3d}] [{rl_flag}] FIFO:[{e['fifo1_load']},{e['fifo2_load']},{e['fifo3_load']}] "
              f"Div:[{e['core0_div']},{e['core1_div']},{e['core2_div']},{e['core3_div']}]")
    
    print(f"{'='*60}\n")


def main():
    print("=" * 70)
    print("FPGA Image Processing + Performance Logger - Complete Receiver")
    print("=" * 70)
    print(f"Configuration:")
    print(f"  Input:  {SEND_WIDTH}x{SEND_HEIGHT} {'RGB' if SEND_RGB else 'Grayscale'}")
    print(f"  Output: {RECEIVE_WIDTH}x{RECEIVE_HEIGHT} {'Grayscale' if RECEIVE_GRAYSCALE else 'RGB'}")
    print(f"  Expected image size: {IMAGE_SIZE} bytes")
    print("=" * 70 + "\n")
    
    # Validate input file
    if not os.path.exists(INPUT_IMAGE):
        print(f"✗ Input image not found: {INPUT_IMAGE}")
        return
    
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Generate output filenames with timestamp
    timestamp = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    basename = os.path.splitext(os.path.basename(INPUT_IMAGE))[0]
    output_image_path = os.path.join(OUTPUT_DIR, f"{basename}_received_{timestamp}.png")
    output_log_csv = os.path.join(OUTPUT_DIR, f"{basename}_perflog_{timestamp}.csv")
    output_raw_bin = os.path.join(OUTPUT_DIR, f"{basename}_raw_{timestamp}.bin")
    
    # Open serial port
    print(f"Opening serial port {PORT} @ {BAUD} baud...")
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    time.sleep(0.1)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    print("✓ Serial port ready\n")
    
    try:
        # Load and send image
        print("--- STEP 1: Send Image ---")
        img_bytes = load_and_resize_image(INPUT_IMAGE, SEND_WIDTH, SEND_HEIGHT, as_rgb=SEND_RGB)
        send_image(ser, img_bytes)
        
        # Receive all data
        print("--- STEP 2: Receive All Data ---")
        all_data = receive_all_data(ser, IDLE_TIMEOUT, MAX_TIMEOUT)
        
        # Save raw data
        with open(output_raw_bin, 'wb') as f:
            f.write(all_data)
        print(f"✓ Saved raw data to {output_raw_bin}\n")
        
        # Extract and save image
        print("--- STEP 3: Extract Image ---")
        print(f"Using first {IMAGE_SIZE} bytes for image...")
        img = extract_image(all_data, RECEIVE_WIDTH, RECEIVE_HEIGHT, grayscale=RECEIVE_GRAYSCALE)
        if img:
            img.save(output_image_path)
            print(f"✓ Saved image to {output_image_path}\n")
        else:
            print("✗ Failed to create image\n")
        
        # Extract and save performance logs
        print("--- STEP 4: Extract Performance Logs ---")
        print(f"Searching for logs after byte {IMAGE_SIZE}...")
        entries = extract_performance_logs(all_data, start_offset=IMAGE_SIZE)
        
        if entries:
            print_log_summary(entries)
            save_performance_logs_csv(entries, output_log_csv)
        else:
            print("No performance logs found")
        
        print("\n" + "=" * 70)
        print("COMPLETE")
        print("=" * 70)
        print(f"Image:  {output_image_path}")
        print(f"Logs:   {output_log_csv}")
        print(f"Raw:    {output_raw_bin}")
        print("=" * 70)
        
    finally:
        ser.close()
        print("\nSerial port closed")


if __name__ == "__main__":
    main()
