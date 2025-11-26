# Top Pipeline with Grayscale Module

## Overview

`top_pipeline_with_grayscale.v` is the main top-level module that orchestrates the complete image processing pipeline on an FPGA. It receives RGB images via UART, processes them through multiple stages, and transmits the result back via UART.

## Pipeline Architecture

```
UART RX → FIFO1 → Assembler1 → Resizer → Splitter → FIFO2 → Assembler2 → Grayscale → DiffAmp → Blur → FIFO3 → UART TX
```

### Input/Output Specifications

| Parameter | Value |
|-----------|-------|
| Input Image | 128×128 RGB (49,152 bytes) |
| Output Image | 64×64 Grayscale (4,096 bytes) |
| Clock Frequency | 100 MHz |
| UART Baud Rate | 115,200 bps |

## Module Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PIXEL_WIDTH` | 8 | Bits per color channel |
| `CHANNELS` | 3 | Number of color channels (RGB) |
| `IN_WIDTH` | 128 | Input image width |
| `IN_HEIGHT` | 128 | Input image height |
| `FIFO1_DEPTH` | 8192 | Input FIFO depth |
| `FIFO2_DEPTH` | 8192 | Intermediate FIFO depth |
| `FIFO3_DEPTH` | 4096 | Output FIFO depth |
| `DIFF_AMP_GAIN` | 3 | Contrast enhancement gain |

## Port Descriptions

### Inputs
- `clk`: System clock (100 MHz)
- `rst`: Active-high reset
- `rl_enable`: Enable RL agent for dynamic clock control
- `uart_rx`: UART receive line

### Outputs
- `uart_tx`: UART transmit line
- `led_rx_activity`: LED indicator for RX activity
- `led_tx_activity`: LED indicator for TX activity
- `led_resizer_busy`: LED indicator for resizer activity
- `led_gray_busy`: LED indicator for grayscale activity
- `led_diffamp_busy`: LED indicator for difference amplifier activity
- `led_blur_busy`: LED indicator for blur activity

## Submodule Instances

1. **rl_q_learning_agent**: Q-Learning RL agent for dynamic clock control
2. **clock_agent**: Clock enable generator based on RL decisions
3. **rx**: UART receiver
4. **tx**: UART transmitter
5. **performance_logger**: Logs system state for analysis
6. **bram_fifo (×3)**: Input, intermediate, and output FIFOs
7. **pixel_assembler (×2)**: Converts bytes to RGB pixels
8. **pixel_splitter**: Converts RGB pixels to bytes
9. **resizer_core**: 2× downscale (128→64)
10. **grayscale_core**: RGB to grayscale conversion
11. **difference_amplifier**: Contrast enhancement
12. **box_blur_1d**: 1D smoothing filter

## Data Flow

1. **RX Stage**: UART bytes arrive and are stored in FIFO1
2. **Assembly Stage**: 3 bytes are assembled into 24-bit RGB pixels
3. **Resize Stage**: 2×2 pixel blocks are decimated to single pixels
4. **Split Stage**: RGB pixels are split back to bytes for FIFO2
5. **Re-assembly Stage**: Bytes are assembled back to RGB pixels
6. **Grayscale Stage**: RGB converted using weighted average
7. **Enhancement Stage**: Contrast enhancement via difference amplifier
8. **Blur Stage**: 1D box blur for smoothing
9. **TX Stage**: Processed bytes transmitted via UART

## RL Agent Integration

The module integrates an RL-based dynamic clock control system:
- **Enable Pin**: `rl_enable` controls whether RL is active
- **FIFO Monitoring**: All three FIFOs report load levels (0-7)
- **Clock Enables**: Four processing cores receive individual clock enables
- **Safety Overrides**: Multiple safety mechanisms prevent data loss

## Performance Logging

After each image is processed, the performance logger transmits:
- Core busy states
- FIFO load levels
- Clock divider values
- RL enabled state

Log format: `LOG:` + 2-byte count + 32-bit entries + `END\n`

## LED Indicators

All LEDs use a pulse-stretcher (500,000 cycles) for visibility:
- RX LED: Pulses on each received byte
- TX LED: Pulses on each transmitted byte
- Processing LEDs: Show core activity

## Usage

1. Program FPGA with bitstream
2. Connect UART (115200 baud, 8N1)
3. Set `rl_enable` switch (0=full speed, 1=RL controlled)
4. Send 49,152 bytes (128×128×3)
5. Receive 4,096 bytes (64×64) + performance logs
