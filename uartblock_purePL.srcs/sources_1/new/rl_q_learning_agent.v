`timescale 1ns / 1ps





module rl_q_learning_agent #(
    parameter integer NUM_CORES = 4,
    parameter integer STATE_BITS = 9,        
    parameter integer ACTION_BITS = 16,      
    parameter integer Q_TABLE_SIZE = 512,    
    parameter integer Q_VALUE_WIDTH = 16,    
    parameter integer LEARNING_RATE = 8,     
    parameter integer DISCOUNT_FACTOR = 230, 
    parameter integer EPSILON = 26,          
    parameter integer UPDATE_INTERVAL = 1000 
)(
    input  wire clk,
    input  wire rst,
    input  wire enable,                      
    
    
    input  wire [2:0] fifo1_load,
    input  wire [2:0] fifo2_load,
    input  wire [2:0] fifo3_load,
    
    
    input  wire [3:0] current_core0_div,
    input  wire [3:0] current_core1_div,
    input  wire [3:0] current_core2_div,
    input  wire [3:0] current_core3_div,
    
    
    output reg [3:0] rl_core0_div,
    output reg [3:0] rl_core1_div,
    output reg [3:0] rl_core2_div,
    output reg [3:0] rl_core3_div,
    output reg rl_update_valid,              
    
    
    input  wire core_stall,                  
    input  wire throughput_good,             
    
    
    output reg [15:0] total_updates,
    output reg [15:0] exploration_count,
    output reg [15:0] exploitation_count,
    output reg signed [15:0] avg_reward,
    output reg [STATE_BITS-1:0] current_state_out,
    output reg [ACTION_BITS-1:0] current_action_out
);

    
    
    reg signed [Q_VALUE_WIDTH-1:0] q_table [0:Q_TABLE_SIZE-1];
    reg [ACTION_BITS-1:0] action_table [0:Q_TABLE_SIZE-1];
    
    
    wire [STATE_BITS-1:0] current_state = {fifo1_load, fifo2_load, fifo3_load};
    
    
    wire [ACTION_BITS-1:0] current_action = {current_core0_div, current_core1_div, 
                                              current_core2_div, current_core3_div};
    
    
    localparam STATE_IDLE        = 3'd0;
    localparam STATE_OBSERVE     = 3'd1;
    localparam STATE_SELECT      = 3'd2;
    localparam STATE_EXECUTE     = 3'd3;
    localparam STATE_REWARD      = 3'd4;
    localparam STATE_UPDATE      = 3'd5;
    
    reg [2:0] rl_state;
    reg [15:0] cycle_counter;
    
    
    reg [STATE_BITS-1:0] prev_state;
    reg [ACTION_BITS-1:0] prev_action;
    reg signed [Q_VALUE_WIDTH-1:0] prev_q_value;
    
    
    reg signed [Q_VALUE_WIDTH-1:0] td_error;
    reg signed [Q_VALUE_WIDTH-1:0] update_delta;
    
    
    reg signed [Q_VALUE_WIDTH-1:0] reward;
    
    
    reg [7:0] rand_lfsr;
    wire [7:0] rand_next = {rand_lfsr[6:0], rand_lfsr[7] ^ rand_lfsr[5] ^ rand_lfsr[4] ^ rand_lfsr[3]};
    
    
    reg [ACTION_BITS-1:0] selected_action;
    reg explore_flag;
    
    
    reg signed [31:0] reward_accumulator;
    
    integer i;
    
    
    initial begin
        for (i = 0; i < Q_TABLE_SIZE; i = i + 1) begin
            q_table[i] = 0;
            action_table[i] = 16'h0000;  
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            rl_state <= STATE_IDLE;
            cycle_counter <= 0;
            rand_lfsr <= 8'hA5;  
            rl_update_valid <= 0;
            total_updates <= 0;
            exploration_count <= 0;
            exploitation_count <= 0;
            avg_reward <= 0;
            reward_accumulator <= 0;
            prev_state <= 0;
            prev_action <= 16'h0000;
            prev_q_value <= 0;
            rl_core0_div <= 4'd0;  
            rl_core1_div <= 4'd0;
            rl_core2_div <= 4'd0;
            rl_core3_div <= 4'd0;
            current_state_out <= 0;
            current_action_out <= 0;
        end else if (!enable) begin
            
            rl_update_valid <= 0;
            rl_state <= STATE_IDLE;
            rl_core0_div <= 4'd0;  
            rl_core1_div <= 4'd0;
            rl_core2_div <= 4'd0;
            rl_core3_div <= 4'd0;
        end else begin
            
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
                    
                    prev_state <= current_state;
                    prev_action <= current_action;
                    prev_q_value <= q_table[current_state];
                    current_state_out <= current_state;
                    rl_state <= STATE_REWARD;
                end
                
                STATE_REWARD: begin
                    
                    
                    if (throughput_good && !core_stall) begin
                        reward <= 16'sd100;  
                    end else if (throughput_good && core_stall) begin
                        reward <= 16'sd0;    
                    end else if (!throughput_good && !core_stall) begin
                        reward <= -16'sd50;  
                    end else begin
                        reward <= -16'sd100; 
                    end
                    
                    reward_accumulator <= reward_accumulator + reward;
                    rl_state <= STATE_UPDATE;
                end
                
                STATE_UPDATE: begin
                    
                    
                    
                    
                    if (total_updates > 0) begin
                        
                        td_error = reward - prev_q_value;
                        
                        update_delta = (td_error * LEARNING_RATE) >>> 8;
                        
                        
                        q_table[prev_state] <= prev_q_value + update_delta;
                        action_table[prev_state] <= prev_action;
                    end
                    
                    total_updates <= total_updates + 1;
                    
                    
                    if (total_updates > 0) begin
                        avg_reward <= reward_accumulator / total_updates;
                    end
                    
                    rl_state <= STATE_SELECT;
                end
                
                STATE_SELECT: begin
                    
                    
                    if (rand_lfsr < EPSILON) begin
                        
                        explore_flag <= 1;
                        exploration_count <= exploration_count + 1;
                        
                        
                        
                        selected_action <= {
                            3'b000, rand_lfsr[0],               
                            3'b000, rand_next[0],               
                            3'b000, rand_lfsr[1],               
                            3'b000, rand_next[1]                
                        };
                    end else begin
                        
                        explore_flag <= 0;
                        exploitation_count <= exploitation_count + 1;
                        selected_action <= action_table[current_state];
                    end
                    
                    current_action_out <= selected_action;
                    rl_state <= STATE_EXECUTE;
                end
                
                STATE_EXECUTE: begin
                    
                    
                    if (fifo1_load >= 3'd2 || fifo2_load >= 3'd2 || fifo3_load >= 3'd2) begin
                        
                        rl_core0_div <= 4'd0;
                        rl_core1_div <= 4'd0;
                        rl_core2_div <= 4'd0;
                        rl_core3_div <= 4'd0;
                    end else if (core_stall) begin
                        
                        rl_core0_div <= 4'd0;
                        rl_core1_div <= 4'd0;
                        rl_core2_div <= 4'd0;
                        rl_core3_div <= 4'd0;
                    end else begin
                        
                        
                        rl_core0_div <= (selected_action[15:12] > 4'd1) ? 4'd1 : selected_action[15:12];
                        rl_core1_div <= (selected_action[11:8] > 4'd1) ? 4'd1 : selected_action[11:8];
                        rl_core2_div <= (selected_action[7:4] > 4'd1) ? 4'd1 : selected_action[7:4];
                        rl_core3_div <= (selected_action[3:0] > 4'd1) ? 4'd1 : selected_action[3:0];
                    end
                    rl_update_valid <= 1;
                    
                    rl_state <= STATE_IDLE;
                end
                
                default: rl_state <= STATE_IDLE;
            endcase
        end
    end

endmodule
