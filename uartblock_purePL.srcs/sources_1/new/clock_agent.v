`timescale 1ns / 1ps





module clock_agent #(
    parameter integer NUM_CORES = 4,           
    parameter integer UPDATE_INTERVAL = 100,   
    parameter integer MAX_DIV_BITS = 4         
)(
    input  wire clk,
    input  wire rst,
    
    
    input  wire rl_enable,                     
    input  wire [MAX_DIV_BITS-1:0] rl_core0_div,
    input  wire [MAX_DIV_BITS-1:0] rl_core1_div,
    input  wire [MAX_DIV_BITS-1:0] rl_core2_div,
    input  wire [MAX_DIV_BITS-1:0] rl_core3_div,
    input  wire rl_update_valid,
    
    
    input  wire [NUM_CORES-1:0] core_busy,
    
    
    input  wire [2:0] fifo1_load,
    input  wire [2:0] fifo2_load,
    input  wire [2:0] fifo3_load,
    
    
    output reg  [NUM_CORES-1:0] core_clk_en,
    
    
    output wire [MAX_DIV_BITS-1:0] core0_divider,
    output wire [MAX_DIV_BITS-1:0] core1_divider,
    output wire [MAX_DIV_BITS-1:0] core2_divider,
    output wire [MAX_DIV_BITS-1:0] core3_divider,
    
    
    output reg core_stall,
    output reg throughput_good,
    
    
    output reg  [31:0] total_decisions,
    output reg  [31:0] clock_cycles_saved
);

    
    assign core0_divider = core_dividers[0];
    assign core1_divider = core_dividers[1];
    assign core2_divider = core_dividers[2];
    assign core3_divider = core_dividers[3];

    
    localparam CORE_RESIZER  = 0;
    localparam CORE_GRAY     = 1;
    localparam CORE_DIFFAMP  = 2;
    localparam CORE_BLUR     = 3;

    
    localparam STATE_MONITOR    = 3'd0;
    localparam STATE_ANALYZE    = 3'd1;
    localparam STATE_DECIDE     = 3'd2;
    localparam STATE_APPLY      = 3'd3;
    localparam STATE_RL_UPDATE  = 3'd4;  
    
    reg [2:0] state;
    reg [15:0] interval_counter;
    
    
    reg [MAX_DIV_BITS-1:0] core_dividers [0:NUM_CORES-1];
    reg [MAX_DIV_BITS-1:0] div_counters [0:NUM_CORES-1];
    
    
    reg [15:0] core_active_cycles [0:NUM_CORES-1];
    reg [15:0] core_idle_cycles [0:NUM_CORES-1];
    
    
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
                core_dividers[i] <= 0;  
                div_counters[i] <= 0;
                core_active_cycles[i] <= 0;
                core_idle_cycles[i] <= 0;
                new_dividers[i] <= 0;
            end
        end else begin
            
            if (rl_enable && rl_update_valid) begin
                
                core_dividers[0] <= rl_core0_div;
                core_dividers[1] <= rl_core1_div;
                core_dividers[2] <= rl_core2_div;
                core_dividers[3] <= rl_core3_div;
                total_decisions <= total_decisions + 1;
                
                
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    div_counters[i] <= 0;
                end
            end
            
            
            
            core_stall <= (fifo1_load >= 7) || (fifo2_load >= 7) || (fifo3_load >= 7);
            
            
            throughput_good <= (fifo1_load >= 2 && fifo1_load <= 5) &&
                               (fifo2_load >= 2 && fifo2_load <= 5) &&
                               (fifo3_load >= 2 && fifo3_load <= 5);
            
            
            
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (!rl_enable) begin
                    
                    core_clk_en[i] <= 1'b1;
                    core_dividers[i] <= 0;
                end else if (core_stall || (fifo1_load >= 3) || (fifo2_load >= 3) || (fifo3_load >= 3)) begin
                    
                    
                    core_clk_en[i] <= 1'b1;
                    core_dividers[i] <= 0;
                end else if (core_dividers[i] == 0) begin
                    
                    core_clk_en[i] <= 1'b1;
                end else if (core_dividers[i] > 1) begin
                    
                    core_clk_en[i] <= 1'b1;
                    core_dividers[i] <= 0;
                end else begin
                    
                    if (div_counters[i] >= core_dividers[i]) begin
                        div_counters[i] <= 0;
                        core_clk_en[i] <= 1'b1;
                    end else begin
                        div_counters[i] <= div_counters[i] + 1;
                        core_clk_en[i] <= 1'b0;
                        clock_cycles_saved <= clock_cycles_saved + 1;
                    end
                end
            end
            
            
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (core_busy[i]) begin
                    core_active_cycles[i] <= core_active_cycles[i] + 1;
                end else begin
                    core_idle_cycles[i] <= core_idle_cycles[i] + 1;
                end
            end
        end
    end
endmodule
