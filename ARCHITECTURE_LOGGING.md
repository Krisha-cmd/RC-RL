# Performance Logging System - Architecture Summary

## Complete Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          FPGA (top_pipeline_with_grayscale)              │
│                                                                           │
│  ┌─────────┐    ┌──────────┐    ┌─────────┐    ┌──────────┐             │
│  │  UART   │───>│  FIFO1   │───>│ Pixel   │───>│ Resizer  │             │
│  │   RX    │    │  8192B   │    │Assembler│    │ 128→64   │             │
│  └─────────┘    └──────────┘    └─────────┘    └──────────┘             │
│       │                                               │                  │
│       │ First byte triggers logger enable             v                  │
│       │                                         ┌──────────┐             │
│       └────────────────────────────────────────>│  Pixel   │             │
│                                                 │ Splitter │             │
│                                                 └──────────┘             │
│                                                       │                  │
│                                                       v                  │
│  ┌─────────┐    ┌──────────┐    ┌─────────┐    ┌──────────┐             │
│  │  UART   │<───│  FIFO3   │<───│Box Blur │<───│  FIFO2   │             │
│  │   TX    │    │  4096B   │    │ 2-tap   │    │  8192B   │             │
│  └─────────┘    └──────────┘    └─────────┘    └──────────┘             │
│       ^                                ^                                 │
│       │                                │                                 │
│       │                          ┌──────────┐                            │
│       │                          │   Diff   │                            │
│       │                          │   Amp    │                            │
│       │                          │ (Gain=3) │                            │
│       │                          └──────────┘                            │
│       │                                ^                                 │
│       │                                │                                 │
│       │                          ┌──────────┐    ┌──────────┐            │
│       │                          │Grayscale │<───│  Pixel   │            │
│       │                          │Converter │    │Assembler2│            │
│       │                          └──────────┘    └──────────┘            │
│       │                                                                  │
│  ┌────┴─────────┐                                                        │
│  │TX Multiplexer│                                                        │
│  │ Image | Logs │                                                        │
│  └────┬─────────┘                                                        │
│       │                                                                  │
│       │ After 4,096 bytes, switch to logger                             │
│       │                                                                  │
│  ┌────┴──────────────────────────────────────────────────────┐          │
│  │              Performance Logger                             │          │
│  │  ┌──────────────────────────────────────────────────────┐  │          │
│  │  │ Log Entry (32 bits, every 100 cycles):               │  │          │
│  │  │  [31:28] core_busy     (resizer|gray|diffamp|blur)   │  │          │
│  │  │  [27:19] fifo_loads    (fifo1|fifo2|fifo3)           │  │          │
│  │  │  [18:3]  dividers      (core0|1|2|3)                 │  │          │
│  │  │  [2:0]   reserved                                     │  │          │
│  │  └──────────────────────────────────────────────────────┘  │          │
│  │                                                             │          │
│  │  Storage: 512 entries × 4 bytes = 2,048 bytes BRAM         │          │
│  │                                                             │          │
│  │  States: IDLE → LOGGING → TX_HEADER → TX_DATA →            │          │
│  │          TX_FOOTER → DONE                                   │          │
│  └─────────────────────────────────────────────────────────────┘          │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────┐          │
│  │              Clock Agent (Currently Disabled)                │          │
│  │  Divider outputs: core0_divider, core1_divider,            │          │
│  │                   core2_divider, core3_divider              │          │
│  │  Current state: All = 0 (full speed, 100MHz)               │          │
│  │  Future: RL-based dynamic clock management                 │          │
│  └─────────────────────────────────────────────────────────────┘          │
└───────────────────────────────────────────────────────────────────────────┘

                                    ││
                                    ││ UART @ 115200 baud
                                    ││ COM4
                                    ▼▼

┌───────────────────────────────────────────────────────────────────────────┐
│                        PC (send_and_receive_with_perf_logs.py)            │
│                                                                           │
│  Phase 1: Send Image                                                     │
│  ┌────────────────────────────────────────┐                              │
│  │ Send 128×128 RGB (49,152 bytes)        │                              │
│  │ Chunked transmission (1024 bytes/chunk)│                              │
│  └────────────────────────────────────────┘                              │
│                                                                           │
│  Phase 2: Receive Image                                                  │
│  ┌────────────────────────────────────────┐                              │
│  │ Receive 64×64 Grayscale (4,096 bytes)  │                              │
│  │ Save as PNG image                       │                              │
│  │ Log timeline to CSV                     │                              │
│  └────────────────────────────────────────┘                              │
│                                                                           │
│  Phase 3: Receive Performance Logs (NEW!)                                │
│  ┌────────────────────────────────────────────────────────────┐          │
│  │ Protocol:                                                   │          │
│  │   1. Wait for "LOG:" header (4 bytes)                      │          │
│  │   2. Read entry count (2 bytes, big-endian)                │          │
│  │   3. Read N × 4-byte entries                               │          │
│  │   4. Validate "END\n" footer (4 bytes)                     │          │
│  │                                                             │          │
│  │ Parse each 32-bit entry:                                   │          │
│  │   - Extract core busy states (4 bits)                      │          │
│  │   - Extract FIFO loads (3×3 bits)                          │          │
│  │   - Extract clock dividers (4×4 bits)                      │          │
│  │                                                             │          │
│  │ Output: CSV with headers                                   │          │
│  │   entry_index, core0_busy, core1_busy, core2_busy,        │          │
│  │   core3_busy, fifo1_load, fifo2_load, fifo3_load,         │          │
│  │   core0_divider, core1_divider, core2_divider,            │          │
│  │   core3_divider                                            │          │
│  └────────────────────────────────────────────────────────────┘          │
│                                                                           │
│  Output Files:                                                            │
│  ✓ images_received_<timestamp>.png   ← Processed image                   │
│  ✓ images_perf_log_<timestamp>.csv   ← Performance metrics (NEW!)        │
│  ✓ images_recv_log_<timestamp>.csv   ← Reception log                     │
│  ✓ images_received_<timestamp>.bin   ← Raw bytes                         │
└───────────────────────────────────────────────────────────────────────────┘
```

## Timing Diagram

```
Time →
┌────────┬──────────────────────────────────────┬─────────────┬──────────┐
│        │         Image Processing              │   Logger TX │  Ready   │
│  RX    │  Resizer → Gray → DiffAmp → Blur     │   Protocol  │  Next    │
├────────┼──────────────────────────────────────┼─────────────┼──────────┤
│ Byte 0 │ Logger.enabled ← 1                   │             │          │
│ ...    │ Log every 100 cycles                 │             │          │
│ Byte N │ Processing...                        │             │          │
├────────┼──────────────────────────────────────┼─────────────┼──────────┤
│        │ TX Byte 0                            │             │          │
│        │ TX Byte 1                            │             │          │
│        │ ...                                  │             │          │
│        │ TX Byte 4095                         │             │          │
├────────┼──────────────────────────────────────┼─────────────┼──────────┤
│        │ tx_byte_count = 4096                 │             │          │
│        │ Logger.enabled ← 0                   │             │          │
│        │ Logger.transmit ← 1                  │             │          │
├────────┼──────────────────────────────────────┼─────────────┼──────────┤
│        │                                      │ "LOG:"      │          │
│        │                                      │ Count (2B)  │          │
│        │                                      │ Entry 0     │          │
│        │                                      │ Entry 1     │          │
│        │                                      │ ...         │          │
│        │                                      │ Entry N     │          │
│        │                                      │ "END\n"     │          │
├────────┼──────────────────────────────────────┼─────────────┼──────────┤
│        │                                      │             │ Reset    │
│        │                                      │             │ for next │
└────────┴──────────────────────────────────────┴─────────────┴──────────┘
```

## Control Signal Flow

```
Logger Control FSM:

┌──────────────────────────────────────────────────────────────┐
│  rx_byte_valid && !logger_enabled                            │
│         ↓                                                    │
│  logger_enabled_reg ← 1                                      │
│  (Start logging)                                             │
└──────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  Every 100 clock cycles:                                     │
│    - Sample core_busy_signals                                │
│    - Sample fifo1/2/3_load_bucket                            │
│    - Sample core0/1/2/3_divider                              │
│    - Write to BRAM log[log_count]                            │
│    - log_count++                                             │
└──────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  tx_byte_count >= 4096                                       │
│         ↓                                                    │
│  image_processing_done ← 1                                   │
│  logger_enabled_reg ← 0                                      │
│  (Stop logging)                                              │
└──────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  image_processing_done && !logger_trigger_sent               │
│         ↓                                                    │
│  logger_transmit_reg ← 1 (one cycle pulse)                   │
│  logger_trigger_sent ← 1                                     │
└──────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  Logger FSM:                                                 │
│    TX_HEADER: Send "LOG:"                                    │
│    TX_DATA:   Send count + entries                           │
│    TX_FOOTER: Send "END\n"                                   │
│    DONE:      Assert logs_transmitted                        │
└──────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  logger_logs_transmitted                                     │
│         ↓                                                    │
│  Reset all state for next image                              │
│  tx_mux_state ← 0 (return to image mode)                     │
└──────────────────────────────────────────────────────────────┘
```

## Key Features

### ✅ No Configuration Needed
- Fully automatic operation
- No manual triggering required
- Self-contained state machine

### ✅ No Data Corruption
- TX multiplexing ensures clean separation
- Image data priority
- Protocol validation (header/footer)

### ✅ Cycle-Accurate Logging
- 100-cycle precision
- Up to 512 samples
- Captures entire pipeline progression

### ✅ Easy Analysis
- CSV output format
- Standard headers
- Import to Excel/Python/Matlab

### ✅ Future-Ready
- RL integration placeholder
- Clock divider monitoring ready
- Expandable log format (reserved bits)

## Metrics Captured

| Metric | Range | Description |
|--------|-------|-------------|
| core0_busy | 0-1 | Resizer active state |
| core1_busy | 0-1 | Grayscale converter active |
| core2_busy | 0-1 | Difference amplifier active |
| core3_busy | 0-1 | Box blur active |
| fifo1_load | 0-7 | Input buffer fullness |
| fifo2_load | 0-7 | Middle buffer fullness |
| fifo3_load | 0-7 | Output buffer fullness |
| core0_divider | 0-15 | Resizer clock divider |
| core1_divider | 0-15 | Grayscale clock divider |
| core2_divider | 0-15 | Diff amp clock divider |
| core3_divider | 0-15 | Blur clock divider |

## Sample CSV Output

```csv
entry_index,core0_busy,core1_busy,core2_busy,core3_busy,fifo1_load,fifo2_load,fifo3_load,core0_divider,core1_divider,core2_divider,core3_divider
0,1,0,0,0,7,0,0,0,0,0,0
1,1,1,0,0,7,2,0,0,0,0,0
2,1,1,1,0,6,4,0,0,0,0,0
3,1,1,1,1,5,5,1,0,0,0,0
4,1,1,1,1,4,6,2,0,0,0,0
...
510,0,0,0,1,0,0,6,0,0,0,0
511,0,0,0,1,0,0,7,0,0,0,0
```

This shows the pipeline filling up (cores activating sequentially) and emptying out (cores finishing in order).
