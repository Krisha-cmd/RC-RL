# Black Box Module Reference

## FPGA Image Processing Pipeline - IC-Style Pin Diagrams

This document presents each internal module of `top_pipeline_with_grayscale.v` as a black box with clearly defined input/output pins, similar to IC datasheets.

---

## Table of Contents

1. [Top Module Overview](#1-top-module-overview)
2. [rx - UART Receiver](#2-rx---uart-receiver)
3. [tx - UART Transmitter](#3-tx---uart-transmitter)
4. [bram_fifo - FIFO Buffer](#4-bram_fifo---fifo-buffer)
5. [pixel_assembler - Byte to Pixel](#5-pixel_assembler---byte-to-pixel)
6. [pixel_splitter - Pixel to Bytes](#6-pixel_splitter---pixel-to-bytes)
7. [resizer_core - Image Downscaler](#7-resizer_core---image-downscaler)
8. [grayscale_core - RGB to Grayscale](#8-grayscale_core---rgb-to-grayscale)
9. [difference_amplifier - Contrast Enhancement](#9-difference_amplifier---contrast-enhancement)
10. [box_blur_1d - Smoothing Filter](#10-box_blur_1d---smoothing-filter)
11. [rl_q_learning_agent - RL Controller](#11-rl_q_learning_agent---rl-controller)
12. [clock_agent - Clock Enable Generator](#12-clock_agent---clock-enable-generator)
13. [performance_logger - System Monitor](#13-performance_logger---system-monitor)

---

## 1. Top Module Overview

```
                            ┌─────────────────────────────────────────────┐
                            │                                             │
                            │      top_pipeline_with_grayscale            │
                            │                                             │
          ──────────────────┤  clk                         uart_tx  ├─────────────────►
          ──────────────────┤  rst                                  │
          ──────────────────┤  rl_enable               led_rx_activity  ├─────────────►
          ──────────────────┤  uart_rx               led_tx_activity  ├─────────────►
                            │                      led_resizer_busy  ├─────────────►
                            │                         led_gray_busy  ├─────────────►
                            │                       led_diffamp_busy  ├─────────────►
                            │                         led_blur_busy  ├─────────────►
                            │                                             │
                            └─────────────────────────────────────────────┘
```

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `PIXEL_WIDTH` | 8 | Bits per color channel |
| `CHANNELS` | 3 | Number of color channels (RGB) |
| `IN_WIDTH` | 128 | Input image width |
| `IN_HEIGHT` | 128 | Input image height |
| `FIFO1_DEPTH` | 8192 | Input FIFO depth |
| `FIFO2_DEPTH` | 8192 | Intermediate FIFO depth |
| `FIFO3_DEPTH` | 4096 | Output FIFO depth |
| `DIFF_AMP_GAIN` | 3 | Contrast amplification factor |

---

## 2. rx - UART Receiver

Receives serial data and outputs parallel bytes.

```
                     ┌───────────────────────────┐
                     │                           │
                     │           rx              │
                     │                           │
                     │   ┌───────────────────┐   │
       clk ─────────►│ 1 │                   │   │
                     │   │   UART RECEIVER   │   │
       rst ─────────►│ 2 │                   │   │
                     │   │   115200 baud     │   │
       rx  ─────────►│ 3 │   8N1 format      │ 4 ├───────► rx_byte[7:0]
                     │   │                   │   │
                     │   │                   │ 5 ├───────► rx_byte_valid
                     │   └───────────────────┘   │
                     │                           │
                     └───────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock (100 MHz) |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | rx | UART serial input |
| 4 | OUT | 8 | rx_byte | Received parallel byte |
| 5 | OUT | 1 | rx_byte_valid | High for 1 cycle when byte ready |

### Timing
- Baud Rate: 115,200 bps
- Clocks per bit: 868 (100 MHz / 115200)
- Latency: 10 bit periods (~87 µs per byte)

---

## 3. tx - UART Transmitter

Transmits parallel bytes as serial data.

```
                     ┌───────────────────────────┐
                     │                           │
                     │           tx              │
                     │                           │
                     │   ┌───────────────────┐   │
       clk ─────────►│ 1 │                   │   │
                     │   │   UART TRANSMITTER│   │
       rst ─────────►│ 2 │                   │   │
                     │   │   115200 baud     │ 6 ├───────► tx
 tx_start ─────────►│ 3 │   8N1 format      │   │
                     │   │                   │ 7 ├───────► tx_busy
 tx_data[7:0] ─────►│ 4 │                   │   │
                     │   └───────────────────┘   │
                     │                           │
                     └───────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock (100 MHz) |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | tx_start | Pulse to begin transmission |
| 4 | IN | 8 | tx_data | Byte to transmit |
| 6 | OUT | 1 | tx | UART serial output |
| 7 | OUT | 1 | tx_busy | High during transmission |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `CLOCK_FREQ` | 100000000 | System clock frequency |
| `BAUD_RATE` | 115200 | Serial baud rate |

---

## 4. bram_fifo - FIFO Buffer

Asynchronous FIFO using Block RAM with Gray-coded pointers.

```
                         ┌─────────────────────────────────┐
                         │                                 │
                         │          bram_fifo              │
                         │                                 │
                         │   ┌───────────────────────┐     │
         wr_clk ────────►│ 1 │                       │     │
                         │   │                       │ 10  ├────► rd_valid
         wr_rst ────────►│ 2 │                       │     │
                         │   │     BLOCK RAM         │ 11  ├────► rd_data[7:0]
       wr_valid ────────►│ 3 │                       │     │
                         │   │     FIFO BUFFER       │ 12  │◄──── rd_ready
        wr_data ────────►│ 4 │                       │     │
            [7:0]        │   │     Gray-coded        │     │
                         │   │     pointers          │ 13  ├────► wr_count_sync
       wr_ready ◄───────│ 5 │                       │     │      [ADDR_WIDTH:0]
                         │   │                       │     │
         rd_clk ────────►│ 6 │                       │ 14  ├────► rd_count_sync
                         │   │                       │     │      [ADDR_WIDTH:0]
         rd_rst ────────►│ 7 │                       │     │
                         │   │                       │ 15  ├────► load_bucket[2:0]
                         │   └───────────────────────┘     │
                         │                                 │
                         └─────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | wr_clk | Write clock |
| 2 | IN | 1 | wr_rst | Write reset |
| 3 | IN | 1 | wr_valid | Write data valid |
| 4 | IN | 8 | wr_data | Write data |
| 5 | OUT | 1 | wr_ready | FIFO can accept data |
| 6 | IN | 1 | rd_clk | Read clock |
| 7 | IN | 1 | rd_rst | Read reset |
| 10 | OUT | 1 | rd_valid | Read data available |
| 11 | OUT | 8 | rd_data | Read data |
| 12 | IN | 1 | rd_ready | Consumer ready to read |
| 13 | OUT | ADDR+1 | wr_count_sync | Write-side fill count |
| 14 | OUT | ADDR+1 | rd_count_sync | Read-side fill count |
| 15 | OUT | 3 | load_bucket | Fill level (0-7 buckets) |

### Parameters
| Parameter | Description |
|-----------|-------------|
| `DEPTH` | FIFO depth in bytes |
| `ADDR_WIDTH` | Address width (log2 of depth) |

### Instances in Design
| Instance | DEPTH | Purpose |
|----------|-------|---------|
| fifo1 | 8192 | Input buffer (RX → Resizer) |
| fifo2 | 8192 | Intermediate (Resizer → Grayscale) |
| fifo3 | 4096 | Output buffer (Blur → TX) |

---

## 5. pixel_assembler - Byte to Pixel

Assembles 3 consecutive bytes into a 24-bit RGB pixel.

```
                      ┌──────────────────────────────┐
                      │                              │
                      │      pixel_assembler         │
                      │                              │
                      │   ┌──────────────────────┐   │
        clk ─────────►│ 1 │                      │   │
                      │   │   BYTE → PIXEL       │ 6 ├─────► pixel_out[23:0]
        rst ─────────►│ 2 │                      │   │       (R, G, B)
                      │   │   Assembles 3 bytes  │   │
 bram_rd_valid ──────►│ 3 │   into 24-bit pixel  │ 7 ├─────► pixel_valid
                      │   │                      │   │
 bram_rd_ready ◄─────│ 4 │   7-state FSM        │   │
                      │   │                      │   │
 bram_rd_data ───────►│ 5 │                      │ 8 │◄───── pixel_ready
       [7:0]          │   └──────────────────────┘   │
                      │                              │
                      └──────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | bram_rd_valid | Input byte valid |
| 4 | OUT | 1 | bram_rd_ready | Ready to accept byte |
| 5 | IN | 8 | bram_rd_data | Input byte |
| 6 | OUT | 24 | pixel_out | Assembled RGB pixel |
| 7 | OUT | 1 | pixel_valid | Pixel output valid |
| 8 | IN | 1 | pixel_ready | Downstream ready |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `PIXEL_WIDTH` | 8 | Bits per channel |
| `CHANNELS` | 3 | Number of channels |

---

## 6. pixel_splitter - Pixel to Bytes

Splits a 24-bit RGB pixel into 3 consecutive bytes.

```
                      ┌──────────────────────────────┐
                      │                              │
                      │       pixel_splitter         │
                      │                              │
                      │   ┌──────────────────────┐   │
        clk ─────────►│ 1 │                      │   │
                      │   │   PIXEL → BYTES      │ 6 ├─────► bram_wr_valid
        rst ─────────►│ 2 │                      │   │
                      │   │   Splits 24-bit      │   │
  pixel_in ──────────►│ 3 │   pixel into 3 bytes │ 7 │◄───── bram_wr_ready
     [23:0]           │   │                      │   │
                      │   │   3-state FSM        │   │
 pixel_in_valid ─────►│ 4 │                      │ 8 ├─────► bram_wr_data[7:0]
                      │   │                      │   │
 pixel_in_ready ◄────│ 5 │                      │   │
                      │   └──────────────────────┘   │
                      │                              │
                      └──────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 24 | pixel_in | RGB pixel input |
| 4 | IN | 1 | pixel_in_valid | Input pixel valid |
| 5 | OUT | 1 | pixel_in_ready | Ready for next pixel |
| 6 | OUT | 1 | bram_wr_valid | Output byte valid |
| 7 | IN | 1 | bram_wr_ready | Downstream ready |
| 8 | OUT | 8 | bram_wr_data | Output byte |

---

## 7. resizer_core - Image Downscaler

Downscales image by 2x in both dimensions using 2×2 averaging.

```
                       ┌─────────────────────────────────┐
                       │                                 │
                       │        resizer_core             │
                       │                                 │
                       │   ┌─────────────────────────┐   │
         clk ─────────►│ 1 │                         │   │
                       │   │   IMAGE RESIZER         │   │
         rst ─────────►│ 2 │                         │ 7 ├────► data_out[23:0]
                       │   │   128×128 → 64×64       │   │
      clk_en ─────────►│ 3 │                         │   │
                       │   │   2×2 box average       │ 8 ├────► write_signal
     data_in ─────────►│ 4 │                         │   │
      [23:0]           │   │   Line buffer for       │   │
                       │   │   previous row          │ 9 ├────► frame_done
 read_signal ─────────►│ 5 │                         │   │
                       │   │                         │   │
                       │   │                         │ 10├────► state
                       │   └─────────────────────────┘   │
                       │                                 │
                       └─────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | clk_en | Clock enable from RL agent |
| 4 | IN | 24 | data_in | Input RGB pixel |
| 5 | IN | 1 | read_signal | Input data valid |
| 7 | OUT | 24 | data_out | Output resized RGB pixel |
| 8 | OUT | 1 | write_signal | Output valid |
| 9 | OUT | 1 | frame_done | High when frame complete |
| 10 | OUT | 1 | state | Processing state (busy) |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `IN_WIDTH` | 128 | Input width |
| `IN_HEIGHT` | 128 | Input height |
| `OUT_WIDTH` | 64 | Output width |
| `OUT_HEIGHT` | 64 | Output height |
| `PIXEL_WIDTH` | 8 | Bits per channel |
| `CHANNELS` | 3 | Number of channels |

---

## 8. grayscale_core - RGB to Grayscale

Converts RGB pixel to grayscale using luminance formula.

```
                       ┌─────────────────────────────────┐
                       │                                 │
                       │       grayscale_core            │
                       │                                 │
                       │   ┌─────────────────────────┐   │
         clk ─────────►│ 1 │                         │   │
                       │   │   RGB → GRAYSCALE       │   │
         rst ─────────►│ 2 │                         │ 6 ├────► data_out[7:0]
                       │   │                         │   │
      clk_en ─────────►│ 3 │   Y = 0.299R +         │   │
                       │   │       0.587G +         │ 7 ├────► write_signal
     data_in ─────────►│ 4 │       0.114B           │   │
      [23:0]           │   │                         │   │
                       │   │   Fixed-point mult     │ 8 ├────► state
 read_signal ─────────►│ 5 │                         │   │
                       │   └─────────────────────────┘   │
                       │                                 │
                       └─────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | clk_en | Clock enable from RL agent |
| 4 | IN | 24 | data_in | Input RGB pixel {R, G, B} |
| 5 | IN | 1 | read_signal | Input valid |
| 6 | OUT | 8 | data_out | Grayscale output |
| 7 | OUT | 1 | write_signal | Output valid |
| 8 | OUT | 1 | state | Processing state (busy) |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `PIXEL_WIDTH` | 8 | Bits per channel |

### Algorithm
```
Y = (77×R + 150×G + 29×B) >> 8
```

---

## 9. difference_amplifier - Contrast Enhancement

Amplifies pixel differences from mid-gray to enhance contrast.

```
                       ┌─────────────────────────────────┐
                       │                                 │
                       │    difference_amplifier         │
                       │                                 │
                       │   ┌─────────────────────────┐   │
         clk ─────────►│ 1 │                         │   │
                       │   │   CONTRAST AMPLIFIER    │   │
         rst ─────────►│ 2 │                         │ 6 ├────► data_out[7:0]
                       │   │                         │   │
      clk_en ─────────►│ 3 │   out = 128 + GAIN×    │   │
                       │   │         (in - 128)     │ 7 ├────► write_signal
     data_in ─────────►│ 4 │                         │   │
       [7:0]           │   │   Saturates to 0-255   │   │
                       │   │                         │ 8 ├────► state
 read_signal ─────────►│ 5 │                         │   │
                       │   └─────────────────────────┘   │
                       │                                 │
                       └─────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | clk_en | Clock enable from RL agent |
| 4 | IN | 8 | data_in | Grayscale input |
| 5 | IN | 1 | read_signal | Input valid |
| 6 | OUT | 8 | data_out | Contrast-enhanced output |
| 7 | OUT | 1 | write_signal | Output valid |
| 8 | OUT | 1 | state | Processing state (busy) |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `PIXEL_WIDTH` | 8 | Bits per pixel |
| `GAIN` | 3 | Amplification factor |

---

## 10. box_blur_1d - Smoothing Filter

Applies 1D box blur (3-tap moving average) for smoothing.

```
                       ┌─────────────────────────────────┐
                       │                                 │
                       │         box_blur_1d             │
                       │                                 │
                       │   ┌─────────────────────────┐   │
         clk ─────────►│ 1 │                         │   │
                       │   │   1D BOX BLUR FILTER    │   │
         rst ─────────►│ 2 │                         │ 6 ├────► data_out[7:0]
                       │   │                         │   │
      clk_en ─────────►│ 3 │   out = (p[-1] + p[0]  │   │
                       │   │          + p[+1]) / 3  │ 7 ├────► write_signal
     data_in ─────────►│ 4 │                         │   │
       [7:0]           │   │   3-tap shift register │   │
                       │   │                         │ 8 ├────► state
 read_signal ─────────►│ 5 │                         │   │
                       │   └─────────────────────────┘   │
                       │                                 │
                       └─────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | clk_en | Clock enable from RL agent |
| 4 | IN | 8 | data_in | Grayscale input |
| 5 | IN | 1 | read_signal | Input valid |
| 6 | OUT | 8 | data_out | Blurred output |
| 7 | OUT | 1 | write_signal | Output valid |
| 8 | OUT | 1 | state | Processing state (busy) |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `PIXEL_WIDTH` | 8 | Bits per pixel |
| `IMG_WIDTH` | 64 | Image width (for row handling) |

---

## 11. rl_q_learning_agent - RL Controller

Q-Learning agent that learns optimal clock divider settings.

```
     ┌─────────────────────────────────────────────────────────────────────────┐
     │                                                                         │
     │                       rl_q_learning_agent                               │
     │                                                                         │
     │   ┌───────────────────────────────────────────────────────────────┐     │
     │   │                                                               │     │
     │   │              Q-LEARNING REINFORCEMENT AGENT                   │     │
     │   │                                                               │     │
     │   │   ┌─────────┐   ┌─────────┐   ┌─────────────────────────┐    │     │
     │   │   │ Q-TABLE │   │ ACTION  │   │ EPSILON-GREEDY          │    │     │
     │   │   │ 512×16  │   │ TABLE   │   │ EXPLORATION             │    │     │
     │   │   │         │   │ 512×16  │   │                         │    │     │
     │   │   └─────────┘   └─────────┘   └─────────────────────────┘    │     │
     │   │                                                               │     │
     │   └───────────────────────────────────────────────────────────────┘     │
     │                                                                         │
     │   INPUTS                                            OUTPUTS             │
     │   ──────                                            ───────             │
clk ─┼─► 1                                                                     │
     │                                                  12 ─┼─► rl_core0_div[3:0]
rst ─┼─► 2                                                                     │
     │                                                  13 ─┼─► rl_core1_div[3:0]
enable─► 3                                                                     │
     │                                                  14 ─┼─► rl_core2_div[3:0]
     │   ┌─ STATE INPUTS ─┐                                                    │
     │   │                │                             15 ─┼─► rl_core3_div[3:0]
fifo1_load[2:0] ─► 4      │                                                    │
     │   │                │                             16 ─┼─► rl_update_valid
fifo2_load[2:0] ─► 5      │                                                    │
     │   │                │                                                    │
fifo3_load[2:0] ─► 6      │                             ┌─ STATISTICS ─┐       │
     │   └────────────────┘                             │              │       │
     │                                               17 ─┼─► total_updates[15:0]
     │   ┌─ CURRENT DIVIDERS ─┐                         │              │       │
     │   │                    │                      18 ─┼─► exploration_count[15:0]
current_core0_div ─► 7        │                         │              │       │
     │   │                    │                      19 ─┼─► exploitation_count[15:0]
current_core1_div ─► 8        │                         │              │       │
     │   │                    │                      20 ─┼─► avg_reward[15:0]
current_core2_div ─► 9        │                         │              │       │
     │   │                    │                      21 ─┼─► current_state_out[8:0]
current_core3_div ─► 10       │                         │              │       │
     │   └────────────────────┘                      22 ─┼─► current_action_out[15:0]
     │                                                  └──────────────┘       │
core_stall ─► 11                                                               │
     │                                                                         │
throughput_good ─► (from clock_agent)                                          │
     │                                                                         │
     └─────────────────────────────────────────────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | enable | RL agent enable |
| 4 | IN | 3 | fifo1_load | FIFO1 fill bucket (0-7) |
| 5 | IN | 3 | fifo2_load | FIFO2 fill bucket (0-7) |
| 6 | IN | 3 | fifo3_load | FIFO3 fill bucket (0-7) |
| 7-10 | IN | 4 | current_core[0-3]_div | Current divider settings |
| 11 | IN | 1 | core_stall | Pipeline stall indicator |
| 12-15 | OUT | 4 | rl_core[0-3]_div | Recommended divider settings |
| 16 | OUT | 1 | rl_update_valid | New action available |
| 17-22 | OUT | varies | statistics | Debug/monitoring outputs |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CORES` | 4 | Number of processing cores |
| `STATE_BITS` | 9 | State space (3×3 FIFO loads) |
| `Q_TABLE_SIZE` | 512 | Number of Q-values |
| `LEARNING_RATE` | 8 | α (scaled 0-255) |
| `DISCOUNT_FACTOR` | 230 | γ (scaled 0-255) |
| `EPSILON` | 26 | ε exploration rate (~10%) |
| `UPDATE_INTERVAL` | 1000 | Cycles between updates |

---

## 12. clock_agent - Clock Enable Generator

Generates clock enables for each core based on RL recommendations.

```
     ┌─────────────────────────────────────────────────────────────────────────┐
     │                                                                         │
     │                          clock_agent                                    │
     │                                                                         │
     │   ┌───────────────────────────────────────────────────────────────┐     │
     │   │                                                               │     │
     │   │              CLOCK ENABLE GENERATOR                           │     │
     │   │                                                               │     │
     │   │   ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐    │     │
     │   │   │  DIVIDER    │   │  SAFETY     │   │  ENABLE         │    │     │
     │   │   │  COUNTERS   │   │  OVERRIDE   │   │  OUTPUT         │    │     │
     │   │   │  (4 cores)  │   │  LOGIC      │   │  GENERATION     │    │     │
     │   │   └─────────────┘   └─────────────┘   └─────────────────┘    │     │
     │   │                                                               │     │
     │   └───────────────────────────────────────────────────────────────┘     │
     │                                                                         │
     │   INPUTS                                            OUTPUTS             │
     │   ──────                                            ───────             │
clk ─┼─► 1                                                                     │
     │                                                  12 ─┼─► core_clk_en[3:0]
rst ─┼─► 2                                                                     │
     │                                                  13 ─┼─► core0_divider[3:0]
rl_enable ─► 3                                                                 │
     │                                                  14 ─┼─► core1_divider[3:0]
     │   ┌─ RL INPUTS ─┐                                                       │
     │   │             │                                15 ─┼─► core2_divider[3:0]
rl_core0_div ─► 4      │                                                       │
     │   │             │                                16 ─┼─► core3_divider[3:0]
rl_core1_div ─► 5      │                                                       │
     │   │             │                                17 ─┼─► core_stall
rl_core2_div ─► 6      │                                                       │
     │   │             │                                18 ─┼─► throughput_good
rl_core3_div ─► 7      │                                                       │
     │   │             │                                19 ─┼─► total_decisions[15:0]
rl_update_valid ─► 8   │                                                       │
     │   └─────────────┘                                20 ─┼─► clock_cycles_saved[31:0]
     │                                                                         │
core_busy[3:0] ─► 9                                                            │
     │                                                                         │
fifo1_load[2:0] ─► 10                                                          │
fifo2_load[2:0] ─► 10                                                          │
fifo3_load[2:0] ─► 11                                                          │
     │                                                                         │
     └─────────────────────────────────────────────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | rl_enable | Use RL recommendations |
| 4-7 | IN | 4 | rl_core[0-3]_div | RL recommended dividers |
| 8 | IN | 1 | rl_update_valid | New RL action available |
| 9 | IN | 4 | core_busy | Core busy signals |
| 10-11 | IN | 3 | fifo[1-3]_load | FIFO fill levels |
| 12 | OUT | 4 | core_clk_en | Clock enables |
| 13-16 | OUT | 4 | core[0-3]_divider | Active divider settings |
| 17 | OUT | 1 | core_stall | Stall indicator |
| 18 | OUT | 1 | throughput_good | Throughput OK indicator |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CORES` | 4 | Number of cores |
| `UPDATE_INTERVAL` | 100 | Cycles between updates |
| `MAX_DIV_BITS` | 4 | Divider bit width |

### Safety Features
- **FIFO Override:** Forces full speed (div=0) when any FIFO ≥ 2/8 full
- **Max Divider Limit:** Caps divider at 1 (½ speed minimum)

---

## 13. performance_logger - System Monitor

Logs system state and transmits via UART after image processing.

```
     ┌─────────────────────────────────────────────────────────────────────────┐
     │                                                                         │
     │                      performance_logger                                 │
     │                                                                         │
     │   ┌───────────────────────────────────────────────────────────────┐     │
     │   │                                                               │     │
     │   │              SYSTEM STATE LOGGER                              │     │
     │   │                                                               │     │
     │   │   ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐    │     │
     │   │   │ LOG MEMORY  │   │ STATE       │   │ UART TX         │    │     │
     │   │   │ 512 × 32bit │   │ MACHINE     │   │ INTERFACE       │    │     │
     │   │   │             │   │             │   │                 │    │     │
     │   │   └─────────────┘   └─────────────┘   └─────────────────┘    │     │
     │   │                                                               │     │
     │   └───────────────────────────────────────────────────────────────┘     │
     │                                                                         │
     │   INPUTS                                            OUTPUTS             │
     │   ──────                                            ───────             │
clk ─┼─► 1                                                                     │
     │                                                  12 ─┼─► tx_start
rst ─┼─► 2                                                                     │
     │                                                  13 ─┼─► tx_data[7:0]
     │   ┌─ CONTROL ─┐                                                         │
     │   │           │                                  14 ─┼─► logs_transmitted
logging_enabled ─► 3 │                                                         │
     │   │           │                                                         │
transmit_logs ─► 4   │                                                         │
     │   └───────────┘                                                         │
     │                                                                         │
     │   ┌─ MONITORED SIGNALS ─┐                                               │
     │   │                     │                                               │
core_busy[3:0] ─► 5            │                                               │
     │   │                     │                                               │
fifo1_load[2:0] ─► 6           │                                               │
     │   │                     │                                               │
fifo2_load[2:0] ─► 7           │                                               │
     │   │                     │                                               │
fifo3_load[2:0] ─► 8           │                                               │
     │   │                     │                                               │
core0_divider[3:0] ─► 9        │                                               │
core1_divider[3:0] ─► 9        │                                               │
core2_divider[3:0] ─► 9        │                                               │
core3_divider[3:0] ─► 9        │                                               │
     │   │                     │                                               │
rl_enabled ─► 10               │                                               │
     │   │                     │                                               │
tx_busy ─► 11  (feedback)      │                                               │
     │   └─────────────────────┘                                               │
     │                                                                         │
     └─────────────────────────────────────────────────────────────────────────┘
```

### Pin Description
| Pin | Direction | Width | Name | Description |
|-----|-----------|-------|------|-------------|
| 1 | IN | 1 | clk | System clock |
| 2 | IN | 1 | rst | Active-high reset |
| 3 | IN | 1 | logging_enabled | Enable state logging |
| 4 | IN | 1 | transmit_logs | Trigger log transmission |
| 5 | IN | 4 | core_busy | Core busy states |
| 6-8 | IN | 3 | fifo[1-3]_load | FIFO fill levels |
| 9 | IN | 4×4 | core[0-3]_divider | Divider settings |
| 10 | IN | 1 | rl_enabled | RL agent active |
| 11 | IN | 1 | tx_busy | TX busy (feedback) |
| 12 | OUT | 1 | tx_start | Start TX byte |
| 13 | OUT | 8 | tx_data | TX byte data |
| 14 | OUT | 1 | logs_transmitted | Transmission complete |

### Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CORES` | 4 | Number of cores |
| `LOG_INTERVAL` | 100 | Cycles between log entries |
| `MAX_LOG_ENTRIES` | 512 | Log memory depth |

### Log Entry Format (32 bits)
```
┌────────────────────────────────────────────────────────────────┐
│ 31-28 │ 27-24 │ 23-20 │ 19-16 │ 15-12 │ 11-8 │ 7-4 │ 3-0     │
├───────┼───────┼───────┼───────┼───────┼──────┼─────┼─────────┤
│ div0  │ div1  │ div2  │ div3  │ f1    │ f2   │ f3  │ busy/rl │
└────────────────────────────────────────────────────────────────┘
```

### TX Protocol
```
"LOG:" + [2-byte count] + [32-bit entries × count] + "END\n"
```

---

## Complete System Interconnect

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                     │
│                              UART RX                    UART TX                     │
│                                 │                          ▲                        │
│                                 ▼                          │                        │
│  ┌───────┐              ┌───────────┐              ┌───────────┐                   │
│  │  rx   │──────────────│   FIFO1   │              │    tx     │◄──┬──────────────│
│  │       │   8-bit      │   8192    │              │           │   │              │
│  └───────┘   bytes      └─────┬─────┘              └───────────┘   │              │
│                               │                          ▲         │              │
│                               ▼                          │         │              │
│                    ┌────────────────────┐                │    ┌────┴─────┐        │
│                    │  pixel_assembler   │                │    │   MUX    │        │
│                    │      (3→24)        │                │    │ img/log  │        │
│                    └────────┬───────────┘                │    └────┬─────┘        │
│                             │ 24-bit                     │         │              │
│                             ▼                            │         │              │
│  ┌──────────────────────────────────────┐               │    ┌────┴─────────┐    │
│  │           resizer_core               │               │    │ performance  │    │
│  │          128×128 → 64×64             │               │    │   _logger    │    │
│  │             clk_en[0]                │               │    └──────────────┘    │
│  └──────────────┬───────────────────────┘               │         ▲              │
│                 │ 24-bit                                │         │ monitor      │
│                 ▼                                       │         │ signals      │
│      ┌────────────────────┐                            │         │              │
│      │   pixel_splitter   │                            │    ┌────┴─────┐        │
│      │      (24→3)        │                            │    │  clock   │        │
│      └────────┬───────────┘                            │    │  _agent  │◄───────│
│               │ 8-bit                                  │    └────┬─────┘        │
│               ▼                                        │         │              │
│        ┌───────────┐                                   │         │ clk_en       │
│        │   FIFO2   │                                   │         ▼              │
│        │   8192    │                                   │  ┌──────────────┐      │
│        └─────┬─────┘                                   │  │rl_q_learning │      │
│              │                                         │  │   _agent     │      │
│              ▼                                         │  └──────────────┘      │
│   ┌────────────────────┐                              │         ▲              │
│   │  pixel_assembler   │                              │         │ fifo loads   │
│   │      (3→24)        │                              │         │              │
│   └────────┬───────────┘                              │         │              │
│            │ 24-bit                                   │         │              │
│            ▼                                          │         │              │
│  ┌──────────────────────────────────────┐            │         │              │
│  │           grayscale_core             │            │         │              │
│  │            RGB → Y                   │────────────┼─────────┘              │
│  │             clk_en[1]                │            │                        │
│  └──────────────┬───────────────────────┘            │                        │
│                 │ 8-bit                              │                        │
│                 ▼                                    │                        │
│  ┌──────────────────────────────────────┐            │                        │
│  │        difference_amplifier          │            │                        │
│  │           Contrast ×3                │────────────┘                        │
│  │             clk_en[2]                │                                     │
│  └──────────────┬───────────────────────┘                                     │
│                 │ 8-bit                                                       │
│                 ▼                                                             │
│  ┌──────────────────────────────────────┐                                     │
│  │           box_blur_1d                │                                     │
│  │           Smoothing                  │                                     │
│  │             clk_en[3]                │                                     │
│  └──────────────┬───────────────────────┘                                     │
│                 │ 8-bit                                                       │
│                 ▼                                                             │
│           ┌───────────┐                                                       │
│           │   FIFO3   │───────────────────────────────────────────────────────│
│           │   4096    │                                                       │
│           └───────────┘                                                       │
│                                                                                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Reference Table

| Module | Type | Inputs | Outputs | Clock Enable |
|--------|------|--------|---------|--------------|
| rx | Communication | 1 serial | 8-bit + valid | No |
| tx | Communication | 8-bit + start | 1 serial | No |
| bram_fifo | Storage | 8-bit + valid | 8-bit + valid | No |
| pixel_assembler | Data Convert | 8-bit × 3 | 24-bit | No |
| pixel_splitter | Data Convert | 24-bit | 8-bit × 3 | No |
| resizer_core | Processing | 24-bit | 24-bit | **Yes** |
| grayscale_core | Processing | 24-bit | 8-bit | **Yes** |
| difference_amplifier | Processing | 8-bit | 8-bit | **Yes** |
| box_blur_1d | Processing | 8-bit | 8-bit | **Yes** |
| rl_q_learning_agent | Control | FIFO loads | Dividers | No |
| clock_agent | Control | Dividers | clk_en[3:0] | No |
| performance_logger | Monitoring | All signals | TX data | No |

---

*Document generated from `top_pipeline_with_grayscale.v`*
