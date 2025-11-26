# Q-Learning RL Agent for Dynamic Clock Control

## Comprehensive Technical Report

### Executive Summary

This document describes the design, implementation, and iterative refinement of a Q-Learning Reinforcement Learning agent (`rl_q_learning_agent.v`) for dynamic clock control in an FPGA-based image processing pipeline. The agent learns optimal clock divider values to balance power consumption with throughput requirements.

---

## 1. Architecture Overview

### 1.1 Purpose

The RL agent dynamically controls clock enable signals for four processing cores:
1. **Resizer** - 2× image downscaling
2. **Grayscale** - RGB to grayscale conversion
3. **Difference Amplifier** - Contrast enhancement
4. **Box Blur** - Smoothing filter

### 1.2 Learning Algorithm

The agent implements **Q-Learning** with the following characteristics:

| Component | Implementation |
|-----------|----------------|
| State Space | 512 states (3 FIFOs × 8 load levels each) |
| Action Space | 16-bit action (4 cores × 4-bit divider each) |
| Exploration | ε-greedy (10% exploration rate) |
| Learning Rate | α = 8/256 ≈ 0.03125 |
| Discount Factor | γ = 230/256 ≈ 0.898 |

### 1.3 State Representation

```
current_state[8:0] = {fifo1_load[2:0], fifo2_load[2:0], fifo3_load[2:0]}
```

Each FIFO reports a 3-bit load level (0-7):
- 0 = Empty
- 7 = Full
- Intermediate values represent relative fullness

### 1.4 Action Representation

```
action[15:0] = {core0_div[3:0], core1_div[3:0], core2_div[3:0], core3_div[3:0]}
```

Each divider value controls clock frequency:
- 0 = Full speed (clock always enabled)
- 1 = Half speed (clock enabled every other cycle)
- N = 1/(N+1) speed (clock enabled every N+1 cycles)

---

## 2. Implementation Details

### 2.1 Q-Table Storage

```verilog
reg signed [Q_VALUE_WIDTH-1:0] q_table [0:Q_TABLE_SIZE-1];  // Q-values
reg [ACTION_BITS-1:0] action_table [0:Q_TABLE_SIZE-1];       // Best actions
```

- 512 states × 16-bit Q-values = 8,192 bits
- 512 states × 16-bit actions = 8,192 bits
- Total: 16,384 bits (2 KB) of BRAM

### 2.2 State Machine

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   ┌──────┐     ┌─────────┐     ┌────────┐     ┌────────┐      │
│   │ IDLE │────▶│ OBSERVE │────▶│ REWARD │────▶│ UPDATE │      │
│   └──────┘     └─────────┘     └────────┘     └────────┘      │
│       ▲                                            │           │
│       │                                            ▼           │
│       │        ┌─────────┐     ┌─────────┐                    │
│       └────────│ EXECUTE │◀────│ SELECT  │◀───────────────────│
│                └─────────┘     └─────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Reward Function

| Condition | Reward | Rationale |
|-----------|--------|-----------|
| Good throughput, no stall | +100 | Optimal performance |
| Good throughput, with stall | 0 | Acceptable (idle core) |
| Bad throughput, no stall | -50 | Too slow |
| Bad throughput, with stall | -100 | Critical bottleneck |

### 2.4 Random Number Generator

8-bit LFSR (Linear Feedback Shift Register):
```verilog
wire [7:0] rand_next = {rand_lfsr[6:0], rand_lfsr[7] ^ rand_lfsr[5] ^ rand_lfsr[4] ^ rand_lfsr[3]};
```

---

## 3. Evolution and Safety Improvements

### 3.1 Initial Implementation (v1.0)

**Design:**
- Full action space: dividers 0-15 for each core
- Conservative exploration: dividers 0-3 during exploration
- Default divider: 5 (significant slowdown)

**Issues Encountered:**
- ❌ **Data Loss**: Starting with divider=5 was too slow
- ❌ **Image Corruption**: Bytes were being dropped during processing
- ❌ **FIFO Overflow**: Processing couldn't keep up with input rate

**Root Cause:** The initial divider value of 5 meant cores ran at 1/6 speed, causing input to arrive faster than processing could handle.

---

### 3.2 First Safety Revision (v1.1)

**Changes Made:**
```verilog
// Changed default from divider=5 to divider=0
action_table[i] = 16'h0000;  // Full speed default
rl_core0_div <= 4'd0;        // Full speed on reset
```

**Result:**
- ✅ Byte count now correct (4096 bytes)
- ❌ Image still corrupted (wrong pixel values)

**Analysis:** Even with full-speed defaults, the RL agent was learning to slow down cores during operation, causing timing issues.

---

### 3.3 Ultra-Safe Revision (v1.2)

**Changes Made:**

1. **Limited Exploration Range:**
```verilog
// Only explore with dividers 0-1 (full or half speed)
selected_action <= {
    3'b000, rand_lfsr[0],  // core0: 0-1 only
    3'b000, rand_next[0],  // core1: 0-1 only
    3'b000, rand_lfsr[1],  // core2: 0-1 only
    3'b000, rand_next[1]   // core3: 0-1 only
};
```

2. **FIFO Threshold Safety:**
```verilog
// Force full speed if ANY FIFO has load >= 2
if (fifo1_load >= 3'd2 || fifo2_load >= 3'd2 || fifo3_load >= 3'd2) begin
    rl_core0_div <= 4'd0;
    rl_core1_div <= 4'd0;
    rl_core2_div <= 4'd0;
    rl_core3_div <= 4'd0;
end
```

3. **Hard Divider Limit:**
```verilog
// Never allow divider > 1 (max half speed)
rl_core0_div <= (selected_action[15:12] > 4'd1) ? 4'd1 : selected_action[15:12];
```

**Result:**
- ✅ Most images processed correctly
- ⚠️ Occasional corruption still observed

---

### 3.4 Current Implementation (v1.3)

The current version maintains all safety features from v1.2 with the following characteristics:

**Safety Hierarchy:**
1. **Level 1 (Highest Priority):** If RL disabled → Full speed
2. **Level 2:** If core stall detected → Full speed
3. **Level 3:** If any FIFO ≥ 25% full → Full speed
4. **Level 4:** Hard limit divider to 1 maximum
5. **Level 5:** Only explore dividers 0-1

**Effective Behavior:**
- Agent can only slow cores to half speed
- Any FIFO pressure triggers full speed
- Learning continues but conservatively

---

## 4. Module Interface

### 4.1 Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_CORES` | 4 | Number of processing cores |
| `STATE_BITS` | 9 | Bits for state encoding (3×3) |
| `ACTION_BITS` | 16 | Bits for action encoding (4×4) |
| `Q_TABLE_SIZE` | 512 | Number of states (2^9) |
| `Q_VALUE_WIDTH` | 16 | Q-value bit width (signed) |
| `LEARNING_RATE` | 8 | α×256 learning rate |
| `DISCOUNT_FACTOR` | 230 | γ×256 discount factor |
| `EPSILON` | 26 | ε×256 exploration rate |
| `UPDATE_INTERVAL` | 1000 | Cycles between updates |

### 4.2 Input Ports

| Port | Width | Description |
|------|-------|-------------|
| `clk` | 1 | System clock |
| `rst` | 1 | Synchronous reset |
| `enable` | 1 | RL agent enable |
| `fifo1_load` | 3 | FIFO 1 load level (0-7) |
| `fifo2_load` | 3 | FIFO 2 load level (0-7) |
| `fifo3_load` | 3 | FIFO 3 load level (0-7) |
| `current_core*_div` | 4 | Current divider feedback |
| `core_stall` | 1 | Stall condition flag |
| `throughput_good` | 1 | Throughput quality flag |

### 4.3 Output Ports

| Port | Width | Description |
|------|-------|-------------|
| `rl_core*_div` | 4 | Divider output per core |
| `rl_update_valid` | 1 | New values ready |
| `total_updates` | 16 | Total Q-table updates |
| `exploration_count` | 16 | Exploration decisions |
| `exploitation_count` | 16 | Exploitation decisions |
| `avg_reward` | 16 | Running average reward |
| `current_state_out` | 9 | Current state (debug) |
| `current_action_out` | 16 | Current action (debug) |

---

## 5. Integration Guide

### 5.1 Connecting to Clock Agent

```verilog
rl_q_learning_agent #(
    .NUM_CORES(4),
    .UPDATE_INTERVAL(1000)
) rl_agent_inst (
    .clk(clk),
    .rst(rst),
    .enable(rl_enable),              // External switch
    .fifo1_load(fifo1_load_bucket),  // From FIFO
    .fifo2_load(fifo2_load_bucket),
    .fifo3_load(fifo3_load_bucket),
    .current_core0_div(core0_divider),
    .current_core1_div(core1_divider),
    .current_core2_div(core2_divider),
    .current_core3_div(core3_divider),
    .rl_core0_div(rl_core0_div),     // To clock agent
    .rl_core1_div(rl_core1_div),
    .rl_core2_div(rl_core2_div),
    .rl_core3_div(rl_core3_div),
    .rl_update_valid(rl_update_valid),
    .core_stall(core_stall),         // From clock agent
    .throughput_good(throughput_good),
    ...
);
```

### 5.2 Enable/Disable Control

```verilog
// rl_enable = 0: All cores run at full speed (safest)
// rl_enable = 1: RL agent controls clock dividers
```

---

## 6. Performance Analysis

### 6.1 Resource Utilization

| Resource | Usage | Notes |
|----------|-------|-------|
| BRAM | 2 × 512 × 16 bits | Q-table + Action table |
| LUTs | ~500 | State machine + arithmetic |
| FFs | ~200 | Registers and counters |
| DSP | 1 | Q-value multiplication |

### 6.2 Timing

| Operation | Cycles |
|-----------|--------|
| State observation | 1 |
| Reward calculation | 1 |
| Q-table update | 1 |
| Action selection | 1 |
| Action execution | 1 |
| **Total per update** | **5** |
| Update interval | 1000 |

### 6.3 Learning Convergence

With current safety limits:
- Agent learns which states allow slowdown
- Converges to mostly divider=0 actions
- Power savings limited but stability improved

---

## 7. Lessons Learned

### 7.1 Key Insights

1. **Safety First:** In real-time systems, data integrity must take precedence over optimization goals.

2. **Gradual Relaxation:** Start with aggressive safety limits, then relax gradually as system behavior is understood.

3. **Observable State:** FIFO levels provide excellent observable state for throughput management.

4. **Feedback Loops:** The RL agent creating its own training data can lead to unstable learning if not carefully managed.

### 7.2 Future Improvements

1. **Adaptive Safety:** Dynamically adjust safety thresholds based on error rates
2. **Multi-Image Learning:** Train across multiple images to learn general patterns
3. **Online Model Selection:** Switch between learned policies based on input characteristics
4. **Power Measurement:** Add actual power consumption to reward function

---

## 8. Conclusion

The RL Q-Learning agent represents an innovative approach to dynamic clock control in FPGA image processing. While the current implementation prioritizes data integrity over power savings, it provides a foundation for more sophisticated adaptive control systems. The iterative development process highlighted the challenges of applying RL to real-time embedded systems and the importance of comprehensive safety mechanisms.
