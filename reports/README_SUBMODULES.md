# Submodule Documentation

## 1. UART Receiver (`rx.v`)

### Purpose
Receives serial data at 115,200 baud and outputs parallel bytes.

### Key Features
- 8N1 format (8 data bits, no parity, 1 stop bit)
- Oversampling for noise immunity (samples at mid-bit)
- Synchronizer for metastability prevention

### Ports
| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | 100 MHz system clock |
| `rst` | Input | 1 | Synchronous reset |
| `rx` | Input | 1 | Serial input line |
| `rx_byte` | Output | 8 | Received byte |
| `rx_byte_valid` | Output | 1 | Byte ready pulse |

---

## 2. UART Transmitter (`tx.v`)

### Purpose
Transmits parallel bytes as serial data at 115,200 baud.

### Key Features
- 8N1 format
- Busy flag for flow control
- Shift register based transmission

### Ports
| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | 100 MHz system clock |
| `rst` | Input | 1 | Synchronous reset |
| `tx_start` | Input | 1 | Start transmission pulse |
| `tx_data` | Input | 8 | Byte to transmit |
| `tx` | Output | 1 | Serial output line |
| `tx_busy` | Output | 1 | Transmission in progress |

---

## 3. BRAM FIFO (`bram_fifo.v`)

### Purpose
Asynchronous FIFO using Block RAM for data buffering.

### Key Features
- Gray-coded pointers for CDC safety
- Configurable depth (power of 2)
- Load bucket output (0-7) for RL agent

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEPTH` | 4096 | FIFO depth |
| `ADDR_WIDTH` | 12 | Address bits |

### Load Bucket Calculation
```
load_bucket = wr_count[MSB:MSB-2]  // Top 3 bits of count
```
- 0 = Empty
- 7 = Full

---

## 4. Pixel Assembler (`pixel_assembler.v`)

### Purpose
Converts 3 sequential bytes into a 24-bit RGB pixel.

### Operation
1. Reads byte 0 (Red) from FIFO
2. Waits for BRAM latency
3. Reads byte 1 (Green)
4. Waits for BRAM latency
5. Reads byte 2 (Blue)
6. Outputs {R, G, B} as 24-bit pixel

### Timing
- 6 clock cycles per pixel minimum
- Handles FIFO empty conditions gracefully

---

## 5. Pixel Splitter (`pixel_splitter.v`)

### Purpose
Converts a 24-bit RGB pixel into 3 sequential bytes.

### Operation
1. Accepts 24-bit pixel
2. Outputs byte 0 (R)
3. Outputs byte 1 (G)
4. Outputs byte 2 (B)
5. Ready for next pixel

---

## 6. Resizer Core (`resizer_core.v`)

### Purpose
Performs 2× nearest-neighbor downscaling (128×128 → 64×64).

### Algorithm
- Outputs pixel only when both x and y coordinates are even
- Discards 3 out of every 4 pixels

### Clock Enable
- Supports clock gating via `clk_en` input
- Pauses processing when clock disabled

### Outputs
| Signal | Description |
|--------|-------------|
| `data_out` | Downscaled pixel |
| `write_signal` | Output valid pulse |
| `frame_done` | End of frame indicator |
| `state` | Busy indicator |

---

## 7. Grayscale Core (`grayscale_core.v`)

### Purpose
Converts RGB pixels to grayscale using luminance formula.

### Algorithm
```
gray = (77×R + 150×G + 29×B) >> 8
```
Coefficients approximate: 0.299R + 0.587G + 0.114B

### Performance
- Single-cycle latency (when clock enabled)
- Combinational multiply with registered output

---

## 8. Difference Amplifier (`difference_amplifier.v`)

### Purpose
Enhances contrast by amplifying deviations from mid-gray.

### Algorithm
```
output = 128 + GAIN × (input - 128)
output = clamp(output, 0, 255)
```

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `GAIN` | 2 | Amplification factor (1-4 recommended) |

### Effect
- Pixels near 128 remain near 128
- Dark pixels get darker
- Bright pixels get brighter
- Increases perceived contrast

---

## 9. Box Blur 1D (`box_blur_1d.v`)

### Purpose
Applies a simple smoothing filter to reduce noise.

### Algorithm
```
output = (current + next) / 2
```
Uses a 2-tap moving average for lighter blur effect.

### Startup Behavior
- First 2 pixels fill the window
- Output begins on pixel 3
- Resets at frame boundaries

---

## 10. Clock Agent (`clock_agent.v`)

### Purpose
Generates clock enable signals for processing cores based on RL decisions.

### Key Features
- Accepts divider values from RL agent
- Generates per-core clock enables
- Implements safety overrides

### Safety Mechanisms
1. **RL Disabled**: Force full speed
2. **FIFO Threshold**: If any FIFO ≥ 3/8, force full speed
3. **Max Divider**: Hard limit divider to 1 (max half speed)

### Clock Division
```
divider = 0: Always enabled (full speed)
divider = 1: Enable every other cycle (half speed)
divider > 1: Forced to 0 (safety)
```

---

## 11. Performance Logger (`performance_logger.v`)

### Purpose
Records system state at regular intervals for analysis.

### Log Entry Format (32 bits)
| Bits | Field |
|------|-------|
| [31:28] | core_busy[3:0] |
| [27:25] | fifo1_load[2:0] |
| [24:22] | fifo2_load[2:0] |
| [21:19] | fifo3_load[2:0] |
| [18:15] | core0_divider[3:0] |
| [14:11] | core1_divider[3:0] |
| [10:7] | core2_divider[3:0] |
| [6:3] | core3_divider[3:0] |
| [2] | rl_enabled |
| [1:0] | reserved |

### Transmission Protocol
1. Header: `LOG:` (4 bytes)
2. Entry count: 2 bytes (big-endian)
3. Log entries: 4 bytes each
4. Footer: `END\n` (4 bytes)

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `LOG_INTERVAL` | 100 | Cycles between samples |
| `MAX_LOG_ENTRIES` | 512 | Maximum log buffer size |
