`timescale 1ns / 1ps




module rl_agent #(
    parameter integer INTERVAL = 20  
)(
    input  wire clk,
    input  wire rst,

    
    output reg        rl_valid,
    output reg [1:0]  core_mask,   
    output reg [7:0]  freq_code    
);

    reg [31:0] cycle_counter;
    reg [1:0]  state;

    localparam S_IDLE  = 2'd0;
    localparam S_SEND1 = 2'd1;
    localparam S_SEND2 = 2'd2;

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            cycle_counter <= 32'd0;
            rl_valid <= 1'b0;
            core_mask <= 2'b00;
            freq_code <= 8'd1;
            state <= S_IDLE;
        end else begin
            
            rl_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (cycle_counter >= INTERVAL - 1) begin
                        cycle_counter <= 32'd0;
                        state <= S_SEND1;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                S_SEND1: begin
                    
                    
                    rl_valid <= 1'b1;
                    core_mask <= 2'b01;    
                    freq_code <= 8'd4;
                    state <= S_SEND2;
                end

                S_SEND2: begin
                    
                    rl_valid <= 1'b1;
                    core_mask <= 2'b11;    
                    freq_code <= 8'd2;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
