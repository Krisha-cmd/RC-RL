`timescale 1ns / 1ps

// Clock Agent - Dynamic clock divider controller for each processing core
// Monitors core activity and adjusts clock enables to optimize throughput
// Uses FSM placeholder for future RL agent integration

module clock_agent #(
    parameter integer NUM_CORES = 4,           // resizer, grayscale, diff_amp, blur
    parameter integer UPDATE_INTERVAL = 100,   // Update decisions every N clocks
    parameter integer MAX_DIV_BITS = 4         // Max divider = 2^4 = 16
)(
    input  wire clk,
    input  wire rst,
    
    // RL Agent Control
    input  wire rl_enable,                     // Enable RL agent control
    input  wire [MAX_DIV_BITS-1:0] rl_core0_div,
    input  wire [MAX_DIV_BITS-1:0] rl_core1_div,
    input  wire [MAX_DIV_BITS-1:0] rl_core2_div,
    input  wire [MAX_DIV_BITS-1:0] rl_core3_div,
    input  wire rl_update_valid,
    
    // Core activity signals (1 = busy, 0 = idle)
    input  wire [NUM_CORES-1:0] core_busy,
    
    // FIFO load indicators (0-7, higher = more full)
    input  wire [2:0] fifo1_load,
    input  wire [2:0] fifo2_load,
    input  wire [2:0] fifo3_load,
    
    // Clock enable outputs for each core
    output reg  [NUM_CORES-1:0] core_clk_en,
    
    // Clock divider values for logging (0 = full speed, 1-15 = divided)
    output wire [MAX_DIV_BITS-1:0] core0_divider,
    output wire [MAX_DIV_BITS-1:0] core1_divider,
    output wire [MAX_DIV_BITS-1:0] core2_divider,
    output wire [MAX_DIV_BITS-1:0] core3_divider,
    
    // Performance feedback to RL agent
    output reg core_stall,
    output reg throughput_good,
    
    // Statistics outputs
    output reg  [31:0] total_decisions,
    output reg  [31:0] clock_cycles_saved
);

    // Expose divider values for logging
    assign core0_divider = core_dividers[0];
    assign core1_divider = core_dividers[1];
    assign core2_divider = core_dividers[2];
    assign core3_divider = core_dividers[3];

    // Core indices
    localparam CORE_RESIZER  = 0;
    localparam CORE_GRAY     = 1;
    localparam CORE_DIFFAMP  = 2;
    localparam CORE_BLUR     = 3;

    // FSM States
    localparam STATE_MONITOR    = 3'd0;
    localparam STATE_ANALYZE    = 3'd1;
    localparam STATE_DECIDE     = 3'd2;
    localparam STATE_APPLY      = 3'd3;
    localparam STATE_RL_UPDATE  = 3'd4;  // Placeholder for RL agent
    
    reg [2:0] state;
    reg [15:0] interval_counter;
    
    // Clock divider counters for each core (internal only)
    reg [MAX_DIV_BITS-1:0] core_dividers [0:NUM_CORES-1];
    reg [MAX_DIV_BITS-1:0] div_counters [0:NUM_CORES-1];
    
    // Activity tracking
    reg [15:0] core_active_cycles [0:NUM_CORES-1];
    reg [15:0] core_idle_cycles [0:NUM_CORES-1];
    
    // Decision variables (FSM placeholder - will be replaced by RL agent)
    reg [MAX_DIV_BITS-1:0] new_dividers [0:NUM_CORES-1];
    
    integer i;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= STATE_MONITOR;
            interval_counter <= 0;
            total_decisions <= 0;
            clock_cycles_saved <= 0;
            core_stall <= 0;
            throughput_good <= 1;
            
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                core_clk_en[i] <= 1'b1;
                core_dividers[i] <= 0;  // Default: no division (always enabled)
                div_counters[i] <= 0;
                core_active_cycles[i] <= 0;
                core_idle_cycles[i] <= 0;
                new_dividers[i] <= 0;
            end
        end else begin
            // RL Agent Integration
            if (rl_enable && rl_update_valid) begin
                // Apply RL agent decisions
            
            // Track activity for statistics
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_busy[i]) begin
                    core_active_cycles[i] <= core_active_cycles[i] + 1;
                end else begin
                    core_idle_cycles[i] <= core_idle_cycles[i] + 1;
                end
            end          new_dividers[CORE_DIFFAMP] <= 0;  // Full speed
                    end else begin
                        new_dividers[CORE_DIFFAMP] <= 1;  // Half speed (safe)
                    end
                    
                    // Blur: Can be slowest as it's at the end
                    if (fifo3_load >= 7) begin
                        new_dividers[CORE_BLUR] <= 0;  // Full speed to drain FIFO
                    end else if (fifo3_load <= 3) begin
                        new_dividers[CORE_BLUR] <= 3;  // Quarter speed
                    end else begin
                        new_dividers[CORE_BLUR] <= 1;  // Half speed
                    end
                    
                    state <= STATE_RL_UPDATE;
                end
                
                STATE_RL_UPDATE: begin
                    // PLACEHOLDER: RL agent will override decisions here
                    // For now, just pass through the heuristic decisions
                    // Future: RL agent reads state, computes Q-values, selects actions
                    state <= STATE_APPLY;
                end
                
                STATE_APPLY: begin
                    // Apply new divider settings
                    for (i = 0; i < NUM_CORES; i = i + 1) begin
                        core_dividers[i] <= new_dividers[i];
                        div_counters[i] <= 0;  // Reset counters when changing dividers
                    end
                    
                    // Reset activity tracking for next interval
                    for (i = 0; i < NUM_CORES; i = i + 1) begin
                        core_active_cycles[i] <= 0;
                        core_idle_cycles[i] <= 0;
                    end
                    
                    total_decisions <= total_decisions + 1;
                    state <= STATE_MONITOR;
                
                default: state <= STATE_MONITOR;
            endcase
            */
        end
    end
endmodule
