# Performance Logging System - Test Plan

## Pre-Test Checklist

### Hardware Setup
- [ ] ZedBoard connected via USB
- [ ] COM port identified (should be COM4)
- [ ] Power on, FPGA ready to program

### Software Setup
- [ ] Vivado installed and working
- [ ] Python 3 installed
- [ ] Dependencies installed: `pip install pyserial pillow`
- [ ] Input image exists: `input/images.png`

## Test Procedure

### Test 1: Compile and Program FPGA

#### Step 1.1: Open Project
```
1. Open Vivado
2. Load project: uartblock_purePL.xpr
3. Wait for project to fully load
```

#### Step 1.2: Verify Updated Files
Check these files are in the project and updated:
- [ ] `top_pipeline_with_grayscale.v` - Has logger instantiation
- [ ] `performance_logger.v` - New module exists
- [ ] `clock_agent.v` - Has divider outputs

#### Step 1.3: Synthesize
```
1. Click "Run Synthesis"
2. Wait for completion (may take several minutes)
3. Check for errors - should be 0 errors
4. Warnings are OK if no critical path failures
```

Expected result: ✅ Synthesis Successful

#### Step 1.4: Implementation
```
1. Click "Run Implementation"
2. Wait for completion (may take 10-20 minutes)
3. Check timing report
```

Expected result: ✅ Implementation Successful

#### Step 1.5: Generate Bitstream
```
1. Click "Generate Bitstream"
2. Wait for completion
3. Check for top_processing.bit file
```

Expected result: ✅ Bitstream Generated

#### Step 1.6: Program FPGA
```
1. Connect ZedBoard via JTAG
2. Power on board
3. Open Hardware Manager
4. Auto-connect to device
5. Program with top_processing.bit
```

Expected result: ✅ Programming Successful

---

### Test 2: Baseline Test (Image Only)

#### Step 2.1: Run Old Script First
```bash
cd c:\Users\iamri\Documents\Subham_UART\uartblock_purePL
python send_and_receive_64x64_gray.py
```

Expected output:
```
Opening serial port COM4 @ 115200
Sending 49152 bytes (128x128 RGB)
Expecting 4096 bytes (64x64 Grayscale)
Sent 49152 bytes in X.XXXs
Reconstructed image saved to output/images_received_<timestamp>.png
```

#### Step 2.2: Verify Image Reception
- [ ] Check output folder for new PNG
- [ ] Open image - should be 64×64 grayscale
- [ ] Image should look reasonable (not corrupted)
- [ ] Check CSV log - should show 4096 bytes received

Expected result: ✅ Image Processing Works

---

### Test 3: Performance Logging Test

#### Step 3.1: Run New Script
```bash
python send_and_receive_with_perf_logs.py
```

Expected output:
```
Opening serial port COM4 @ 115200
Sending 49152 bytes (128x128 RGB)
Expecting 4096 bytes (64x64 Grayscale)
Sent 49152 bytes in X.XXXs
Reconstructed image saved to output/images_received_<timestamp>.png
Raw received bytes logged to output/images_received_<timestamp>.bin
Receive log (CSV) written to output/images_recv_log_<timestamp>.csv

--- Performance Log Reception ---
Waiting for performance logs...
Log header received
Expecting N log entries
Received N log entries successfully
Performance logs saved to output/images_perf_log_<timestamp>.csv

All operations complete!
```

#### Step 3.2: Verify All Outputs Created
Check output folder for 4 new files:
- [ ] `images_received_<timestamp>.png` - Processed image
- [ ] `images_received_<timestamp>.bin` - Raw bytes (4,096 bytes)
- [ ] `images_recv_log_<timestamp>.csv` - Reception timeline
- [ ] `images_perf_log_<timestamp>.csv` - **Performance metrics (NEW!)**

#### Step 3.3: Validate Performance CSV

Open `images_perf_log_<timestamp>.csv` in Excel or text editor.

**Check Structure:**
- [ ] Has header row with 12 columns
- [ ] Columns: entry_index, core0_busy, core1_busy, core2_busy, core3_busy, fifo1_load, fifo2_load, fifo3_load, core0_divider, core1_divider, core2_divider, core3_divider
- [ ] Multiple data rows (1 to 512 entries)

**Check Values:**
- [ ] entry_index increments: 0, 1, 2, 3, ...
- [ ] core_busy values are 0 or 1
- [ ] fifo_load values are 0-7
- [ ] divider values are currently all 0 (full speed)

**Sample validation:**
```csv
entry_index,core0_busy,core1_busy,core2_busy,core3_busy,fifo1_load,fifo2_load,fifo3_load,core0_divider,core1_divider,core2_divider,core3_divider
0,1,0,0,0,5,0,0,0,0,0,0
1,1,1,0,0,6,2,0,0,0,0,0
2,1,1,1,0,7,4,1,0,0,0,0
```

Expected result: ✅ Valid CSV with metrics

---

### Test 4: Data Validation

#### Step 4.1: Verify Image Integrity
```bash
# Compare with baseline test
# Both should produce identical images
```

- [ ] New script image matches old script image
- [ ] Still 64×64 grayscale
- [ ] No visual corruption
- [ ] Still receiving exactly 4,096 bytes

Expected result: ✅ No Degradation

#### Step 4.2: Verify Log Consistency
Run script multiple times:
```bash
python send_and_receive_with_perf_logs.py
python send_and_receive_with_perf_logs.py
python send_and_receive_with_perf_logs.py
```

- [ ] Each run produces new CSV
- [ ] Entry counts may vary but should be consistent
- [ ] Values should show similar patterns
- [ ] No script crashes or hangs

Expected result: ✅ Repeatable Results

#### Step 4.3: Analyze Log Patterns

Expected patterns in CSV:
- **Early entries**: Core0 (resizer) busy, FIFO1 high, others low
- **Mid entries**: All cores busy, FIFOs balanced
- **Late entries**: Later cores (blur) busy, FIFO3 high

Open CSV in Excel and create graphs:
1. Plot all core_busy over time → Should show sequential activation
2. Plot FIFO loads → Should show wave pattern as data flows
3. Check dividers → All should be 0 (current state)

Expected result: ✅ Logical Patterns

---

### Test 5: Error Handling

#### Test 5.1: Timeout Test
1. Don't program FPGA (or disconnect)
2. Run Python script
3. Should timeout gracefully

Expected: Error message, no crash

#### Test 5.2: Partial Data Test
1. Stop script mid-transmission (Ctrl+C)
2. Should save partial data
3. Should show warning about padding

Expected: Graceful degradation

#### Test 5.3: Multiple Runs
1. Run script 10 times in a row
2. All should succeed
3. Check all CSVs created

Expected: No errors, all files present

---

## Success Criteria

### ✅ All Tests Pass
- [x] FPGA programs successfully
- [x] Image processing works (4,096 bytes)
- [x] Performance logs received
- [x] CSV format correct
- [x] Values make sense
- [x] Repeatable results

### ✅ Performance Unchanged
- [x] Still receiving all 4,096 bytes
- [x] No byte loss
- [x] Same image quality
- [x] Similar transmission time

### ✅ New Functionality
- [x] Log protocol works
- [x] CSV parsing successful
- [x] Metrics captured correctly
- [x] Multiple log entries

## Troubleshooting Guide

### Issue: "Failed to open serial port"
**Solution:**
- Check COM port (Device Manager)
- Try different COM number in script
- Install USB-UART drivers

### Issue: "Only X of 4096 bytes received"
**Solution:**
- This indicates byte loss - should NOT happen
- Check if clock agent is enabled (should be disabled)
- Verify all cores have clk_en=1
- Re-program FPGA with correct bitstream

### Issue: "Timeout waiting for log header"
**Solution:**
- Image processing may not be completing
- Check TX byte count logic
- Verify logger_transmit_logs signal
- Increase timeout in Python script

### Issue: "Invalid log header"
**Solution:**
- Serial buffer contamination
- Reset FPGA
- Clear serial buffers in script
- Run again

### Issue: "Wrong number of log entries"
**Solution:**
- Check if logging started correctly
- Verify 100-cycle interval
- Check BRAM write logic
- May be expected if processing was short

### Issue: "All dividers are 0"
**Solution:**
- This is CORRECT for current implementation
- Clock agent dynamic logic is disabled
- All cores run full speed
- Future: Will vary when RL enabled

### Issue: "CSV format wrong"
**Solution:**
- Check Python parse_log_entry function
- Verify bit field extraction
- Check struct.unpack byte order
- Validate against Verilog packing

## Performance Metrics

### Baseline (Before Logging)
- Image TX: ~4.3 seconds @ 115200 baud
- Image RX: ~0.4 seconds
- Total: ~5 seconds
- Bytes: 4,096/4,096 ✅

### With Logging (Expected)
- Image TX: ~4.3 seconds (unchanged)
- Image RX: ~0.4 seconds (unchanged)
- Log TX: ~0.18 seconds (2,058 bytes max)
- Total: ~5.2 seconds
- Bytes: 4,096/4,096 + logs ✅

### Overhead
- Additional time: ~180ms (log transmission)
- Additional data: ~2KB (max 512 entries)
- Impact: Minimal (<4% increase)

## Sign-Off Checklist

Before considering the system complete:
- [ ] All 5 test sections passed
- [ ] CSV format validated
- [ ] No byte loss in image data
- [ ] Logs show expected patterns
- [ ] Multiple runs successful
- [ ] Documentation complete
- [ ] Code committed to repository

## Next Steps After Testing

1. **Data Analysis**
   - Import CSVs to analysis tool
   - Visualize pipeline behavior
   - Identify bottlenecks

2. **Optimization**
   - Use log data to inform RL training
   - Identify optimal clock divider values
   - Measure power savings potential

3. **RL Integration**
   - Re-enable clock_agent dynamic logic
   - Train RL model with logged data
   - Compare performance before/after

4. **Production Deployment**
   - Create final bitstream
   - Document operational procedures
   - Set up monitoring dashboard

---

## Test Log Template

```
Date: _______________
Tester: _______________

Test 1: FPGA Programming
[ ] Synthesis: PASS / FAIL
[ ] Implementation: PASS / FAIL  
[ ] Bitstream: PASS / FAIL
[ ] Programming: PASS / FAIL
Notes: ________________________________

Test 2: Baseline
[ ] Image received: ____ / 4096 bytes
[ ] Quality: PASS / FAIL
Notes: ________________________________

Test 3: Performance Logging
[ ] Script run: PASS / FAIL
[ ] CSV created: PASS / FAIL
[ ] Entry count: ____
Notes: ________________________________

Test 4: Validation
[ ] Image integrity: PASS / FAIL
[ ] Log patterns: PASS / FAIL
Notes: ________________________________

Test 5: Error Handling
[ ] Timeout test: PASS / FAIL
[ ] Multiple runs: PASS / FAIL
Notes: ________________________________

Overall Result: PASS / FAIL
Signature: _______________
```
