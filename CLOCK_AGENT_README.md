# Dynamic Clock Management System

## Overview
This system implements a **Clock Agent** that dynamically adjusts the effective clock frequency for each processing core in the pipeline by controlling clock enable signals. This allows cores to operate at different speeds based on their workload and FIFO buffer states.

## Architecture

### Clock Agent (`clock_agent.v`)
- **Purpose**: Central controller that decides clock dividers for each core
- **Update Interval**: Makes decisions every 100 clock cycles (configurable)
- **Cores Managed**: 
  - Core 0: Resizer
  - Core 1: Grayscale
  - Core 2: Difference Amplifier
  - Core 3: Box Blur

### How It Works

#### Clock Enable Generation
```
divider = 0  →  clk_en = 1111... (full speed, always enabled)
divider = 1  →  clk_en = 1010... (half speed, enabled every other cycle)
divider = 2  →  clk_en = 10010010... (1/3 speed)
divider = 3  →  clk_en = 100010001... (1/4 speed)
```

#### FSM States
1. **MONITOR** - Tracks core activity and FIFO loads for UPDATE_INTERVAL cycles
2. **ANALYZE** - Processes collected metrics (placeholder for RL)
3. **DECIDE** - Determines new divider values using heuristics (will be replaced by RL)
4. **RL_UPDATE** - Placeholder for RL agent override
5. **APPLY** - Applies new divider settings and resets tracking

### Current Heuristic Policy (Placeholder)

**Resizer (Core 0):**
- Full speed if FIFO1 load ≥ 6 (input buffer filling up)
- Slow to 1/3 speed if FIFO1 load ≤ 2 and mostly idle
- Otherwise maintain current speed

**Grayscale (Core 1):**
- Full speed if FIFO2 load ≥ 6
- Half speed if FIFO2 load ≤ 2
- Otherwise maintain current speed

**Difference Amplifier (Core 2):**
- Full speed if FIFO3 load ≥ 6
- Half speed otherwise (this core is typically fast enough)

**Box Blur (Core 3):**
- Full speed if FIFO3 load ≥ 7 (output buffer nearly full)
- Quarter speed if FIFO3 load ≤ 3
- Half speed otherwise

## Safety Guarantees

### No Byte Skipping
1. **Clock Enable Gating**: Cores only process data when `clk_en = 1`
2. **State Preservation**: When `clk_en = 0`, all core registers hold their values
3. **Handshake Protocol**: `write_signal` only asserts when `clk_en = 1`, so downstream modules wait automatically
4. **FIFO Buffering**: Large FIFOs (4096-8192 depth) buffer data between stages

### Guaranteed Correctness
- **Synchronous Operation**: All cores use the same clock, only enable signals differ
- **No Partial Operations**: Cores complete their current operation before being disabled
- **Pipeline Integrity**: FIFOs decouple stages, preventing data loss during speed changes

## Metrics Tracked

### Per Core (every interval)
- `core_active_cycles[i]`: Cycles where core was busy
- `core_idle_cycles[i]`: Cycles where core was idle
- Current divider value

### Global
- `total_decisions`: Number of policy updates made
- `clock_cycles_saved`: Cumulative cycles where cores were disabled (power savings)

### FIFO Load (0-7 scale)
- `fifo1_load`: Input FIFO fullness
- `fifo2_load`: Intermediate FIFO fullness
- `fifo3_load`: Output FIFO fullness

## Integration with RL Agent (Future)

### State Vector for RL Agent
The RL agent will observe:
```
state = [
    core_active_cycles[0:3],    // 4 values
    core_idle_cycles[0:3],       // 4 values
    fifo1_load,                  // 1 value (0-7)
    fifo2_load,                  // 1 value (0-7)
    fifo3_load,                  // 1 value (0-7)
    current_dividers[0:3]        // 4 values (0-15)
]
Total: 17 values
```

### Action Space
```
action = [divider_0, divider_1, divider_2, divider_3]
Each divider: 0-15 (16 discrete values per core)
Total action space: 16^4 = 65,536 combinations
```

### Reward Function (Example)
```
reward = throughput_weight * bytes_transmitted
         - power_weight * total_clocks_enabled
         - latency_penalty * max_fifo_load
```

### Where to Integrate RL
Replace the **STATE_DECIDE** and **STATE_RL_UPDATE** logic in `clock_agent.v`:

```verilog
STATE_RL_UPDATE: begin
    // Read state vector
    // Call RL inference (Q-network or policy network)
    // Get action (new divider values)
    new_dividers[0] <= rl_action[3:0];
    new_dividers[1] <= rl_action[7:4];
    new_dividers[2] <= rl_action[11:8];
    new_dividers[3] <= rl_action[15:12];
    state <= STATE_APPLY;
end
```

## Testing Strategy

### Verification Steps
1. **Monitor with divider=0 (baseline)**: All cores full speed, verify correct output
2. **Fixed dividers test**: Set each core to divider=1, verify output still correct
3. **Heuristic policy test**: Enable agent, verify no byte loss over multiple frames
4. **Stress test**: Send continuous frames, verify throughput and no corruption

### Expected Behavior
- **Correct Output**: Image should be identical regardless of divider settings
- **Throughput**: May decrease with higher dividers, but no errors
- **Power Savings**: `clock_cycles_saved` should increase over time
- **Adaptive**: FIFO loads should stabilize as agent balances speeds

## Parameters

### Tunable Parameters
```verilog
UPDATE_INTERVAL = 100     // How often to update policy (clock cycles)
MAX_DIV_BITS = 4          // Maximum divider = 2^4 = 16
DIFF_AMP_GAIN = 3         // Contrast enhancement gain
```

### Performance Knobs
- Lower UPDATE_INTERVAL → More responsive but more overhead
- Higher UPDATE_INTERVAL → Less responsive but more stable
- Larger MAX_DIV_BITS → More granular speed control

## Current Status
✅ Clock agent implemented with FSM placeholder  
✅ All cores support clock enable  
✅ Heuristic policy functional  
✅ Safety guarantees in place  
⏳ RL agent integration pending  
⏳ Hardware testing pending

## Next Steps for RL Integration
1. Implement state vector extraction module
2. Design reward calculation logic
3. Integrate RL inference engine (FPGA neural network or external processor)
4. Train RL agent in simulation
5. Deploy and validate on hardware
