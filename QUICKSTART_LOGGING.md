# Quick Start Guide - Performance Logging

## What Changed?

### Verilog Modules
1. **clock_agent.v** - Now exposes divider values for logging
2. **top_pipeline_with_grayscale.v** - Integrated performance logger with automatic control
3. **performance_logger.v** - New module that logs metrics every 100 cycles

### Python Script
- **send_and_receive_with_perf_logs.py** - New script that receives both image and logs

## How It Works

### Automatic Operation Flow
```
1. Start sending image bytes → Logger enables automatically
2. Image processing occurs → Logger records every 100 cycles
3. Send 4,096 bytes complete → Logger stops automatically
4. Logger transmits via UART → Python receives and parses
5. System ready for next image → Process repeats
```

### No Manual Control Needed!
The logger is fully automated:
- ✅ Starts when first RX byte arrives
- ✅ Logs during processing
- ✅ Stops when TX completes
- ✅ Transmits logs automatically
- ✅ Resets for next image

## Running the System

### Step 1: Program FPGA
```bash
# Open Vivado, synthesize and program:
# - top_pipeline_with_grayscale.v (updated)
# - performance_logger.v (new)
# - clock_agent.v (updated)
```

### Step 2: Run Python Script
```bash
cd c:\Users\iamri\Documents\Subham_UART\uartblock_purePL
python send_and_receive_with_perf_logs.py
```

### Step 3: Check Outputs
```
output/
  images_received_<timestamp>.png   ← Processed image (64x64 grayscale)
  images_perf_log_<timestamp>.csv   ← Performance metrics! ← NEW!
  images_recv_log_<timestamp>.csv   ← Reception timeline
  images_received_<timestamp>.bin   ← Raw bytes
```

## CSV Format

### Performance Log CSV
```csv
entry_index,core0_busy,core1_busy,core2_busy,core3_busy,fifo1_load,fifo2_load,fifo3_load,core0_divider,core1_divider,core2_divider,core3_divider
0,1,0,0,0,5,2,0,0,0,0,0
1,1,1,0,0,6,3,1,0,0,0,0
2,1,1,1,0,7,5,2,0,0,0,0
...
```

### What Each Column Means
- **entry_index**: Sequential sample number (0-511)
- **core0_busy**: Resizer active (1=yes, 0=no)
- **core1_busy**: Grayscale converter active
- **core2_busy**: Difference amplifier (contrast) active
- **core3_busy**: Box blur (smoothing) active
- **fifo1_load**: Input buffer fullness (0-7 scale)
- **fifo2_load**: Middle buffer fullness (0-7 scale)
- **fifo3_load**: Output buffer fullness (0-7 scale)
- **core0_divider**: Resizer clock divider (0=full speed, currently all 0)
- **core1_divider**: Grayscale clock divider
- **core2_divider**: Diff amp clock divider
- **core3_divider**: Blur clock divider

## Expected Results

### Current State (All Full Speed)
- All dividers = 0
- All cores run at 100MHz
- No bytes lost
- 4,096/4,096 bytes received

### Log Samples
- Up to 512 entries captured
- Sampled every 100 clock cycles
- Shows pipeline progression
- FIFO levels vary throughout processing

## Troubleshooting

### No Logs Received
- Check FPGA is programmed with updated design
- Verify image reception works first (4,096 bytes)
- Increase timeout in Python script if needed
- Check UART connection (COM4 @ 115200)

### Invalid Log Header
- Reset FPGA
- Clear serial buffers
- Run script again

### Incomplete Logs
- Check log entry count in protocol
- Verify footer "END\n" received
- May indicate UART transmission error

### Image Still Works But No Logs
- TX multiplexing may not be switching
- Check `tx_byte_count` reaches 4,096
- Verify `logger_transmit_logs` signal asserts
- Check logger FSM state transitions

## Signal Mapping Reference

### Core Indices
- Core 0 = Resizer
- Core 1 = Grayscale converter
- Core 2 = Difference amplifier (contrast)
- Core 3 = Box blur (smoothing)

### FIFO Mapping
- FIFO1 = Input (8192 bytes, RGB from UART)
- FIFO2 = Middle (8192 bytes, resized RGB)
- FIFO3 = Output (4096 bytes, grayscale processed)

### Load Scale (0-7)
```
0 = Empty (0%)
1 = 12.5%
2 = 25%
3 = 37.5%
4 = 50%
5 = 62.5%
6 = 75%
7 = 87.5%+
```

## Next Steps

1. **Test the system**: Program FPGA and run Python script
2. **Analyze logs**: Open CSV in Excel/Python to visualize
3. **Verify metrics**: Check if core busy states make sense
4. **Optimize**: Use data to inform future RL clock management

## Future: RL Integration

When RL agent is enabled:
- Clock dividers will vary (not all 0)
- Logs will show optimization in action
- Can compare performance before/after RL
- CSV provides training data for RL

## Files Summary

### Must Program to FPGA
- ✅ top_pipeline_with_grayscale.v
- ✅ performance_logger.v
- ✅ clock_agent.v
- ✅ All existing cores (resizer, grayscale, diff_amp, blur)
- ✅ All existing modules (uart_rx, uart_tx, bram_fifo, etc.)

### Run on PC
- ✅ send_and_receive_with_perf_logs.py

### Reference Documentation
- 📄 README_PERFORMANCE_LOGGING.md (detailed technical doc)
- 📄 This file (quick start guide)
