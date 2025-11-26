`timescale 1ns / 1ps

// Q-Learning RL Agent for Dynamic Clock Control
// Learns optimal clock divider values based on FIFO loads to maximize throughput
// Uses simple Q-table with epsilon-greedy exploration

module rl_q_learning_agent #(
    parameter integer NUM_CORES = 4,
    parameter integer STATE_BITS = 9,        // 3 FIFOs × 3 bits each = 9 bits
    parameter integer ACTION_BITS = 16,      // 4 cores × 4 bits each = 16 bits
    parameter integer Q_TABLE_SIZE = 512,    // 2^9 states
    parameter integer Q_VALUE_WIDTH = 16,    // 16-bit Q-values (signed)
    parameter integer LEARNING_RATE = 8,     // Learning rate = 8/256 ≈ 0.03125
    parameter integer DISCOUNT_FACTOR = 230, // Gamma = 230/256 ≈ 0.898
    parameter integer EPSILON = 26,          // Epsilon = 26/256 ≈ 0.1 (10% exploration)
    parameter integer UPDATE_INTERVAL = 1000 // Update Q-table every N cycles
)(
    input  wire clk,
    input  wire rst,
    input  wire enable,                      // Enable/disable RL agent
    
    // State inputs (FIFO loads)
    input  wire [2:0] fifo1_load,
    input  wire [2:0] fifo2_load,
    input  wire [2:0] fifo3_load,
    
    // Current clock dividers (from clock agent)
    input  wire [3:0] current_core0_div,
    input  wire [3:0] current_core1_div,
    input  wire [3:0] current_core2_div,
    input  wire [3:0] current_core3_div,
    
    // Outputs to clock agent
    output reg [3:0] rl_core0_div,
    output reg [3:0] rl_core1_div,
    output reg [3:0] rl_core2_div,
    output reg [3:0] rl_core3_div,
    output reg rl_update_valid,              // Signal when RL has new values
    
    // Performance feedback
    input  wire core_stall,                  // Any core is stalled/waiting
    input  wire throughput_good,             // System throughput is good
    
    // Logging outputs
    output reg [15:0] total_updates,
    output reg [15:0] exploration_count,
    output reg [15:0] exploitation_count,
    output reg signed [15:0] avg_reward,
    output reg [STATE_BITS-1:0] current_state_out,
    output reg [ACTION_BITS-1:0] current_action_out
);

    // Q-table: stores Q-values for each state-action pair
    // For simplicity, we store the best action and its Q-value per state
    reg signed [Q_VALUE_WIDTH-1:0] q_table [0:Q_TABLE_SIZE-1];
    reg [ACTION_BITS-1:0] action_table [0:Q_TABLE_SIZE-1];
    
    // State representation
    wire [STATE_BITS-1:0] current_state = {fifo1_load, fifo2_load, fifo3_load};
    
    // Action representation (clock dividers for all cores)
    wire [ACTION_BITS-1:0] current_action = {current_core0_div, current_core1_div, 
                                              current_core2_div, current_core3_div};
    
    // RL agent state machine
    localparam STATE_IDLE        = 3'd0;
    localparam STATE_OBSERVE     = 3'd1;
    localparam STATE_SELECT      = 3'd2;
    localparam STATE_EXECUTE     = 3'd3;
    localparam STATE_REWARD      = 3'd4;
    localparam STATE_UPDATE      = 3'd5;
    
    reg [2:0] rl_state;
    reg [15:0] cycle_counter;
    
    // Previous state and action for Q-learning update
    reg [STATE_BITS-1:0] prev_state;
    reg [ACTION_BITS-1:0] prev_action;
    reg signed [Q_VALUE_WIDTH-1:0] prev_q_value;
    
    // TD learning variables (must be declared at module level for Verilog-2001)
    reg signed [Q_VALUE_WIDTH-1:0] td_error;
    reg signed [Q_VALUE_WIDTH-1:0] update_delta;
    
    // Reward calculation
    reg signed [Q_VALUE_WIDTH-1:0] reward;
    
    // Random number generator for epsilon-greedy
    reg [7:0] rand_lfsr;
    wire [7:0] rand_next = {rand_lfsr[6:0], rand_lfsr[7] ^ rand_lfsr[5] ^ rand_lfsr[4] ^ rand_lfsr[3]};
    
    // Action generation
    reg [ACTION_BITS-1:0] selected_action;
    reg explore_flag;
    
    // Statistics
    reg signed [31:0] reward_accumulator;
    
    integer i;
    
    // Initialize Q-table with safe defaults
    initial begin
        for (i = 0; i < Q_TABLE_SIZE; i = i + 1) begin
            q_table[i] = 0;
            action_table[i] = 16'h0000;  // Default: all cores at divider=0 (FULL SPEED - safest)
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            rl_state <= STATE_IDLE;
            cycle_counter <= 0;
            rand_lfsr <= 8'hA5;  // Seed
            rl_update_valid <= 0;
            total_updates <= 0;
            exploration_count <= 0;
            exploitation_count <= 0;
            avg_reward <= 0;
            reward_accumulator <= 0;
            prev_state <= 0;
            prev_action <= 16'h0000;
            prev_q_value <= 0;
            rl_core0_div <= 4'd0;  // FULL SPEED on reset (safest)
            rl_core1_div <= 4'd0;
            rl_core2_div <= 4'd0;
            rl_core3_div <= 4'd0;
            current_state_out <= 0;
            current_action_out <= 0;
        end else if (!enable) begin
            // When disabled, force FULL SPEED for safety
            rl_update_valid <= 0;
            rl_state <= STATE_IDLE;
            rl_core0_div <= 4'd0;  // Full speed
            rl_core1_div <= 4'd0;
            rl_core2_div <= 4'd0;
            rl_core3_div <= 4'd0;
        end else begin
            // Update random number generator
            rand_lfsr <= rand_next;
            
            case (rl_state)
                STATE_IDLE: begin
                    rl_update_valid <= 0;
                    cycle_counter <= cycle_counter + 1;
                    
                    if (cycle_counter >= UPDATE_INTERVAL) begin
                        cycle_counter <= 0;
                        rl_state <= STATE_OBSERVE;
                    end
                end
                
                STATE_OBSERVE: begin
                    // Capture current state
                    prev_state <= current_state;
                    prev_action <= current_action;
                    prev_q_value <= q_table[current_state];
                    current_state_out <= current_state;
                    rl_state <= STATE_REWARD;
                end
                
                STATE_REWARD: begin
                    // Calculate reward based on system performance
                    // Positive reward for good throughput, negative for stalls
                    if (throughput_good && !core_stall) begin
                        reward <= 16'sd100;  // Good performance
                    end else if (throughput_good && core_stall) begin
                        reward <= 16'sd0;    // Neutral (some cores idle but ok)
                    end else if (!throughput_good && !core_stall) begin
                        reward <= -16'sd50;  // Bad (low throughput, no stall - too slow)
                    end else begin
                        reward <= -16'sd100; // Very bad (stall detected)
                    end
                    
                    reward_accumulator <= reward_accumulator + reward;
                    rl_state <= STATE_UPDATE;
                end
                
                STATE_UPDATE: begin
                    // Q-learning update: Q(s,a) = Q(s,a) + α[r + γ*max(Q(s',a')) - Q(s,a)]
                    // Simplified: Q(s,a) = Q(s,a) + α[r - Q(s,a)]
                    // (assuming next state max Q is similar to current)
                    
                    if (total_updates > 0) begin
                        // TD error = reward - prev_q_value
                        td_error = reward - prev_q_value;
                        // update_delta = (LEARNING_RATE * td_error) / 256
                        update_delta = (td_error * LEARNING_RATE) >>> 8;
                        
                        // Update Q-table
                        q_table[prev_state] <= prev_q_value + update_delta;
                        action_table[prev_state] <= prev_action;
                    end
                    
                    total_updates <= total_updates + 1;
                    
                    // Calculate average reward
                    if (total_updates > 0) begin
                        avg_reward <= reward_accumulator / total_updates;
                    end
                    
                    rl_state <= STATE_SELECT;
                end
                
                STATE_SELECT: begin
                    // Epsilon-greedy action selection
                    if (rand_lfsr < EPSILON) begin
                        // Explore: random action with SAFE dividers (0-2 only!)
                        explore_flag <= 1;
                        exploration_count <= exploration_count + 1;
                        
                        // Generate SAFE random dividers (0-2 only, never slow cores too much)
                        selected_action <= {
                            rand_lfsr[1:0],                     // core0: 0-3 (limit to safe values)
                            rand_next[1:0],                     // core1: 0-3
                            rand_lfsr[3:2],                     // core2: 0-3
                            rand_next[3:2]                      // core3: 0-3
                        };
                    end else begin
                        // Exploit: use best known action from Q-table
                        explore_flag <= 0;
                        exploitation_count <= exploitation_count + 1;
                        selected_action <= action_table[current_state];
                    end
                    
                    current_action_out <= selected_action;
                    rl_state <= STATE_EXECUTE;
                end
                
                STATE_EXECUTE: begin
                    // SAFETY CHECK: If any FIFO is filling up (high bits set), force full speed
                    if (fifo1_load[2] || fifo2_load[2] || fifo3_load[2]) begin
                        // FIFO more than 50% full - EMERGENCY: run at full speed
                        rl_core0_div <= 4'd0;
                        rl_core1_div <= 4'd0;
                        rl_core2_div <= 4'd0;
                        rl_core3_div <= 4'd0;
                    end else if (core_stall) begin
                        // System is stalling - run at full speed
                        rl_core0_div <= 4'd0;
                        rl_core1_div <= 4'd0;
                        rl_core2_div <= 4'd0;
                        rl_core3_div <= 4'd0;
                    end else begin
                        // Safe to apply RL action, but limit to safe values (max divider = 3)
                        rl_core0_div <= (selected_action[15:12] > 4'd3) ? 4'd3 : selected_action[15:12];
                        rl_core1_div <= (selected_action[11:8] > 4'd3) ? 4'd3 : selected_action[11:8];
                        rl_core2_div <= (selected_action[7:4] > 4'd3) ? 4'd3 : selected_action[7:4];
                        rl_core3_div <= (selected_action[3:0] > 4'd3) ? 4'd3 : selected_action[3:0];
                    end
                    rl_update_valid <= 1;
                    
                    rl_state <= STATE_IDLE;
                end
                
                default: rl_state <= STATE_IDLE;
            endcase
        end
    end

endmodule
