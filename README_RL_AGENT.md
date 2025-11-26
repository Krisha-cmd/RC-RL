# RL Q-Learning Agent for FPGA Clock Control

## Overview

This implements a hardware Q-learning reinforcement learning agent that dynamically controls the clock frequencies of image processing cores based on FIFO buffer loads. The agent learns optimal policies to maximize throughput while minimizing stalls.

## Architecture

### Components

1. **rl_q_learning_agent.v**: Q-learning RL agent module
   - 512-entry Q-table (9-bit state space: 3 FIFOs × 3 bits each)
   - Epsilon-greedy exploration (10% random actions)
   - Learning rate: α ≈ 0.03125
   - Discount factor: γ ≈ 0.898
   - Updates every 1000 clock cycles

2. **clock_agent.v**: Clock divider controller (modified)
   - Accepts RL agent commands or runs at full speed
   - Provides performance feedback to RL agent
   - Implements clock dividers (1-15) for each core

3. **top_pipeline_with_grayscale.v**: Main integration
   - Parameter `RL_AGENT_ENABLE` to enable/disable RL

## State Space

**9 bits total:**
- FIFO1 load: 3 bits (0-7)
- FIFO2 load: 3 bits (0-7)
- FIFO3 load: 3 bits (0-7)

Total states: 2^9 = 512

## Action Space

**16 bits total (4 cores × 4 bits each):**
- Core 0 (resizer) divider: 4 bits (1-15, where 1=full speed, 15=slowest)
- Core 1 (grayscale) divider: 4 bits
- Core 2 (diff_amp) divider: 4 bits
- Core 3 (blur) divider: 4 bits

## Reward Function

```verilog
if (throughput_good && !core_stall)
    reward = +100   // Excellent performance
else if (throughput_good && core_stall)
    reward = 0      // Neutral (some idle but acceptable)
else if (!throughput_good && !core_stall)
    reward = -50    // Bad (too slow, underutilizing)
else
    reward = -100   // Very bad (stall detected)
```

### Performance Metrics

- `throughput_good`: All FIFOs in range [2,5] (balanced flow)
- `core_stall`: Any FIFO ≥ 7 (bottleneck detected)

## Enabling/Disabling the RL Agent

### Method 1: Compile-Time Parameter (Current Implementation)

In `top_pipeline_with_grayscale.v`, set:

```verilog
parameter integer RL_AGENT_ENABLE = 1;  // 1 = enabled, 0 = disabled (full speed)
```

**When RL_AGENT_ENABLE = 0:**
- All cores run at full speed
- No clock dividers applied
- Guaranteed no data loss
- Maximum power consumption

**When RL_AGENT_ENABLE = 1:**
- RL agent controls clock dividers
- Learns optimal frequencies over time
- May be slower initially (exploration phase)
- Reduces power consumption after learning

### Method 2: Runtime Control (Future Enhancement)

To add runtime control, modify the module to accept an input:

```verilog
module top_pipeline_with_grayscale #(
    ...
)(
    input  wire clk,
    input  wire rst,
    input  wire rl_enable_in,  // Add this input
    ...
);

// Then use rl_enable_in instead of parameter
```

## Logging RL Metrics

The RL agent exposes these statistics:

```verilog
output reg [15:0] total_updates       // Total Q-table updates
output reg [15:0] exploration_count   // Random actions taken
output reg [15:0] exploitation_count  // Best actions taken
output reg signed [15:0] avg_reward   // Average reward
output reg [8:0] current_state_out    // Current state
output reg [15:0] current_action_out  // Current action
```

### Integrating with Performance Logger

To log RL metrics, modify `performance_logger.v` to include RL fields:

```verilog
// Add inputs
input wire [15:0] rl_total_updates,
input wire signed [15:0] rl_avg_reward,

// Expand log entry to 64 bits
// [63:48] rl_total_updates
// [47:32] rl_avg_reward
// [31:0] existing fields
```

## Q-Learning Algorithm

The agent implements standard Q-learning:

```
Q(s,a) ← Q(s,a) + α[r - Q(s,a)]
```

Where:
- s = current state (FIFO loads)
- a = action (clock dividers)
- r = reward (performance)
- α = learning rate (0.03125)

**Exploration vs Exploitation:**
- 10% of the time: random action (explore)
- 90% of the time: best known action from Q-table (exploit)

## Expected Behavior

### Phase 1: Exploration (First ~500 images)
- Random actions cause variable performance
- Q-table is being populated
- May see occasional stalls or slow throughput
- Average reward will be negative initially

### Phase 2: Learning (500-2000 images)
- Agent starts finding good policies
- Performance improves
- Average reward increases
- Fewer stalls

### Phase 3: Convergence (After ~2000 images)
- Optimal or near-optimal policy learned
- Consistent good performance
- Average reward stable at high value
- Minimal exploration (mostly exploitation)

## Safety Features

1. **Fallback to Full Speed**: If RL disabled, all cores run at maximum speed
2. **No Data Loss**: Clock dividers slow cores but don't skip data
3. **Bounded Actions**: Dividers limited to 1-15 range
4. **Reset on Rst**: Q-table preserved across images, cleared on reset

## Testing the RL Agent

### 1. Disable RL First (Baseline)

```verilog
parameter integer RL_AGENT_ENABLE = 0;
```

- Synthesize and test
- Verify all 4096 bytes received correctly
- Record baseline throughput

### 2. Enable RL

```verilog
parameter integer RL_AGENT_ENABLE = 1;
```

- Synthesize and test
- Send multiple images (100+)
- Monitor performance logs to see learning progress

### 3. Analyze Results

Check CSV logs for:
- `core0_divider`, `core1_divider`, etc. changing over time
- Relationship between FIFO loads and divider values
- Improvement in average reward

## Python Script to Monitor RL Learning

```python
import pandas as pd
import matplotlib.pyplot as plt

# Load performance logs
df = pd.read_csv('output/images_perflog_*.csv')

# Plot dividers over time
fig, axes = plt.subplots(2, 2, figsize=(12, 8))
axes[0,0].plot(df['core0_div'])
axes[0,0].set_title('Core 0 (Resizer) Divider')
axes[0,1].plot(df['core1_div'])
axes[0,1].set_title('Core 1 (Grayscale) Divider')
axes[1,0].plot(df['core2_div'])
axes[1,0].set_title('Core 2 (Diff Amp) Divider')
axes[1,1].plot(df['core3_div'])
axes[1,1].set_title('Core 3 (Blur) Divider')
plt.tight_layout()
plt.show()

# Analyze FIFO loads vs dividers
print("Correlation between FIFO loads and dividers:")
print(df[['fifo1', 'fifo2', 'fifo3', 'core0_div', 'core1_div', 'core2_div', 'core3_div']].corr())
```

## Tuning Parameters

### Learning Rate (α)
- **Higher** (e.g., 16/256 = 0.0625): Faster learning, less stable
- **Lower** (e.g., 4/256 = 0.015625): Slower learning, more stable
- Current: 8/256 ≈ 0.03125

### Exploration Rate (ε)
- **Higher** (e.g., 51/256 = 20%): More exploration, slower convergence
- **Lower** (e.g., 13/256 = 5%): Less exploration, faster convergence
- Current: 26/256 ≈ 10%

### Update Interval
- **Shorter** (e.g., 500): More frequent updates, higher overhead
- **Longer** (e.g., 2000): Less frequent updates, lower overhead
- Current: 1000 cycles

## Troubleshooting

**Problem: Data loss or corrupted images**
- **Solution**: Disable RL agent (set `RL_AGENT_ENABLE = 0`)
- **Cause**: RL agent may have learned poor policy

**Problem: No improvement in learning**
- **Solution**: Increase exploration rate or reset Q-table
- **Cause**: Stuck in local optimum

**Problem: Performance worse than baseline**
- **Solution**: Increase learning duration (more images)
- **Cause**: Still in exploration phase

## Future Enhancements

1. **Runtime Enable/Disable**: Add input pin to toggle RL at runtime
2. **Larger Q-table**: Increase state space granularity
3. **Deep Q-Learning**: Replace table with neural network
4. **Multi-objective Rewards**: Balance throughput, power, and latency
5. **Transfer Learning**: Save/load Q-table across power cycles

## Files Modified

- `rl_q_learning_agent.v` (NEW)
- `clock_agent.v` (MODIFIED - added RL integration)
- `top_pipeline_with_grayscale.v` (MODIFIED - added RL agent instance)

## Synthesis Notes

- Q-table requires 512 × 16 bits = 8192 bits = 1 KB BRAM
- Action table requires 512 × 16 bits = 8192 bits = 1 KB BRAM
- Total additional resources: ~2 KB BRAM, minimal LUTs
- No timing impact (runs at same 100 MHz clock)
