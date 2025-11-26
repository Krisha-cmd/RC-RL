# Project Complexity and Challenges Report

## FPGA Image Processing Pipeline with RL-Based Dynamic Clock Control

---

## Executive Summary

This project implements a complete image processing pipeline on an FPGA with an innovative Q-Learning Reinforcement Learning agent for dynamic clock management. The system processes 128×128 RGB images, performing resizing, grayscale conversion, contrast enhancement, and blur operations, outputting 64×64 grayscale images via UART.

---

## 1. Overall System Complexity

### 1.1 Architectural Complexity

| Metric | Value | Complexity Level |
|--------|-------|------------------|
| Total Verilog Modules | 15+ | High |
| Lines of Verilog Code | ~3,000 | Medium-High |
| Clock Domains | 1 (single, 100 MHz) | Low |
| State Machines | 8+ | High |
| FIFO Instances | 3 | Medium |
| Processing Cores | 4 | Medium |

### 1.2 Data Flow Complexity

```
                    ┌─────────────────────────────────────────────────────────────────────┐
                    │                     TOP PIPELINE MODULE                              │
                    │  ┌─────┐   ┌───────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐     │
 UART RX ──────────▶│  │FIFO1│──▶│ASSEM1 │──▶│ RESIZER │──▶│SPLITTER │──▶│  FIFO2  │     │
 (49,152 bytes)     │  │8192 │   │ 3→24b │   │ 128→64  │   │ 24→3×8b │   │  8192   │     │
                    │  └─────┘   └───────┘   └─────────┘   └─────────┘   └────┬────┘     │
                    │                                                          │          │
                    │  ┌───────┐   ┌─────────┐   ┌─────────┐   ┌───────┐      │          │
                    │  │ASSEM2 │◀──│  FIFO2  │◀──────────────────────────────┘          │
                    │  │ 3→24b │   │  cont.  │                                           │
                    │  └───┬───┘   └─────────┘                                           │
                    │      │                                                              │
                    │      ▼                                                              │
                    │  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────┐                │
                    │  │GRAYSCALE│──▶│ DIFFAMP │──▶│  BLUR   │──▶│FIFO3│──▶ UART TX    │
                    │  │ RGB→Y   │   │ contrast│   │ smooth  │   │4096 │   (4,096 bytes)│
                    │  └─────────┘   └─────────┘   └─────────┘   └─────┘                │
                    │                                                                     │
                    │  ┌────────────────────────────────────────────────────────────┐   │
                    │  │                    CONTROL SUBSYSTEM                        │   │
                    │  │  ┌────────────┐    ┌─────────────┐    ┌──────────────────┐ │   │
                    │  │  │ RL Q-LEARN │───▶│ CLOCK AGENT │───▶│ clk_en[3:0]      │ │   │
                    │  │  │   AGENT    │    │             │    │ (to all cores)    │ │   │
                    │  │  └────────────┘    └─────────────┘    └──────────────────┘ │   │
                    │  │         ▲                                                   │   │
                    │  │         │  FIFO load feedback                              │   │
                    │  │  ┌──────┴───────────────────────────────────────────────┐  │   │
                    │  │  │           PERFORMANCE LOGGER                          │  │   │
                    │  │  │  (captures state, transmits via UART after image)     │  │   │
                    │  │  └───────────────────────────────────────────────────────┘  │   │
                    │  └────────────────────────────────────────────────────────────┘   │
                    └─────────────────────────────────────────────────────────────────────┘
```

### 1.3 Module Interdependencies

| Module | Dependencies | Dependents |
|--------|--------------|------------|
| `rx` | None | FIFO1 |
| `bram_fifo` | bram_11 | Multiple |
| `pixel_assembler` | FIFO | resizer, grayscale |
| `resizer_core` | clock_agent | pixel_splitter |
| `grayscale_core` | clock_agent | difference_amplifier |
| `difference_amplifier` | clock_agent | box_blur_1d |
| `box_blur_1d` | clock_agent | FIFO3 |
| `rl_q_learning_agent` | FIFO loads | clock_agent |
| `clock_agent` | RL agent | All cores |
| `performance_logger` | All signals | tx |
| `tx` | logger, FIFO3 | None |

---

## 2. Technical Challenges Encountered

### 2.1 UART Timing and Synchronization

**Challenge:** Ensuring reliable byte-by-byte transmission at 115,200 baud with 100 MHz clock.

**Complexity Factors:**
- Baud rate division: 100,000,000 / 115,200 = 868.05 cycles/bit
- Fractional division error accumulates over long transmissions
- Start bit detection requires mid-bit sampling

**Solution:**
- 16-bit counter for precise timing
- Oversampling in receiver
- Double-flop synchronizer for metastability

### 2.2 FIFO Design with Gray-Coded Pointers

**Challenge:** Designing a safe asynchronous FIFO even in single-clock domain.

**Complexity Factors:**
- Binary-to-Gray and Gray-to-Binary conversions
- Pointer synchronization across domains
- Full/empty detection without race conditions

**Solution:**
```verilog
function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
    bin2gray = (b >> 1) ^ b;
endfunction

function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
    integer i;
    reg [ADDR_WIDTH:0] b;
    begin
        b = 0;
        for (i = ADDR_WIDTH; i >= 0; i = i - 1)
            b = b ^ (g >> i);
        gray2bin = b;
    end
endfunction
```

### 2.3 Pixel Assembly with BRAM Latency

**Challenge:** Handling 1-cycle BRAM read latency in streaming pipeline.

**Complexity Factors:**
- BRAM output appears one cycle after address
- Must coordinate with FIFO valid/ready handshaking
- Three bytes must be assembled atomically

**Solution:**
- 7-state FSM to handle latency
- Wait states between byte reads
- Registered output for clean timing

### 2.4 RL Agent Data Corruption

**Challenge:** RL agent causing image corruption by throttling cores too aggressively.

**Root Causes Identified:**
1. Default divider too slow (5 → 1/6 speed)
2. Exploration sampling too aggressive (0-15 range)
3. No safety override for FIFO pressure
4. Q-table learning unstable actions

**Progressive Solutions:**

| Version | Change | Result |
|---------|--------|--------|
| v1.0 | Initial with divider=5 | Data loss |
| v1.1 | Changed default to 0 | Still corruption |
| v1.2 | Limited exploration 0-1 | Better |
| v1.3 | FIFO threshold override | Stable |

### 2.5 TX/Logger Handover

**Challenge:** Switching UART TX from image data to logger output without corruption.

**Complexity Factors:**
- TX module has internal state
- Logger must wait for TX idle
- Race condition possible

**Solution:**
```verilog
reg [7:0] mux_switch_delay;  // 100-cycle delay for clean handover

always @(posedge clk) begin
    if (image_processing_done && !tx_mux_state && !tx_busy) begin
        if (mux_switch_delay < 8'd100) begin
            mux_switch_delay <= mux_switch_delay + 1;
        end else begin
            tx_mux_state <= 1'b1;  // Switch to logger
        end
    end
end
```

### 2.6 Performance Logger TX Timing

**Challenge:** Verilog character literals synthesizing incorrectly.

**Issue:**
```verilog
tx_data <= "L";  // May not synthesize to 0x4C on all tools
```

**Solution:**
```verilog
tx_data <= 8'h4C;  // Explicit hex value for 'L'
tx_data <= 8'h4F;  // 'O'
tx_data <= 8'h47;  // 'G'
tx_data <= 8'h3A;  // ':'
```

---

## 3. Design Decisions and Trade-offs

### 3.1 Single Clock Domain

**Decision:** Use single 100 MHz clock throughout.

**Trade-off:**
- ✅ Simplified design, no CDC issues
- ✅ Deterministic timing
- ❌ Cannot optimize power per module
- ❌ All modules run at same frequency

### 3.2 FIFO Sizing

**Decision:** Large FIFOs (8192, 8192, 4096) to absorb timing variations.

**Trade-off:**
- ✅ Handles bursty input
- ✅ Tolerates RL agent decisions
- ❌ Higher BRAM usage
- ❌ Increased latency

### 3.3 RL Agent Safety Priority

**Decision:** Prioritize data integrity over power savings.

**Trade-off:**
- ✅ Reliable image processing
- ✅ No data corruption
- ❌ Limited power optimization
- ❌ RL agent rarely slows cores

### 3.4 Streaming vs. Frame-Buffered

**Decision:** Streaming pipeline without frame buffer.

**Trade-off:**
- ✅ Lower memory requirements
- ✅ Lower latency
- ❌ Cannot handle variable-rate input
- ❌ No random access to pixels

---

## 4. Resource Utilization

### 4.1 Estimated FPGA Resources

| Resource | Estimated Usage | Notes |
|----------|-----------------|-------|
| LUTs | ~3,000 | Logic and arithmetic |
| FFs | ~1,500 | State machines and registers |
| BRAM | 20+ blocks | FIFOs and Q-tables |
| DSP | 3-4 | Grayscale multiply, RL math |
| IOs | 8-10 | UART, LEDs, switches |

### 4.2 Memory Distribution

| Component | Size (bits) | BRAM Blocks |
|-----------|-------------|-------------|
| FIFO1 | 8192 × 8 | 4 |
| FIFO2 | 8192 × 8 | 4 |
| FIFO3 | 4096 × 8 | 2 |
| Q-table | 512 × 16 | 1 |
| Action table | 512 × 16 | 1 |
| Logger memory | 512 × 32 | 2 |
| **Total** | | **~14 blocks** |

---

## 5. Testing and Validation

### 5.1 Test Methodology

1. **Simulation:** Behavioral simulation with test images
2. **Hardware:** Live testing with UART communication
3. **Comparison:** RL on vs. RL off for corruption analysis

### 5.2 Known Issues and Status

| Issue | Status | Resolution |
|-------|--------|------------|
| Data loss with aggressive RL | ✅ Fixed | Safety overrides |
| Image corruption | ✅ Fixed | FIFO thresholds |
| Logger not transmitting | ✅ Fixed | TX handover delay |
| Verilog char literals | ✅ Fixed | Hex values |

---

## 6. Future Enhancements

### 6.1 Short-Term

1. Add CRC for data integrity verification
2. Implement flow control (RTS/CTS)
3. Add frame synchronization markers

### 6.2 Medium-Term

1. Multi-image batch processing
2. Configurable image dimensions
3. Additional filter options

### 6.3 Long-Term

1. Deep Q-Network (DQN) implementation
2. Actual power measurement feedback
3. Adaptive safety thresholds

---

## 7. Conclusion

This project demonstrates the complexity of integrating reinforcement learning with real-time FPGA image processing. The primary challenge was balancing the RL agent's optimization objectives with the strict timing requirements of the streaming pipeline. Through iterative refinement and the addition of multiple safety mechanisms, the system achieved stable operation while maintaining the RL infrastructure for future enhancement.

**Key Takeaways:**
1. Real-time systems require conservative initial parameters
2. Observable state (FIFO levels) is crucial for control decisions
3. Safety mechanisms should be layered and redundant
4. Thorough testing at each development stage prevents cascading issues
