`timescale 1ns / 1ps



module rl_agent_simple #(
    parameter integer INTERVAL = 2000000
)(
    input  wire clk,
    input  wire rst,            
    output reg  rl_valid,
    output reg [1:0] core_mask,
    output reg [7:0] freq_code
);
    reg [31:0] cnt;
    always @(posedge clk) begin
        if (rst) begin
            cnt <= 32'h0;
            rl_valid <= 1'b0;
            core_mask <= 2'b01;
            freq_code <= 8'd4;
        end else begin
            rl_valid <= 1'b0;
            if (cnt >= INTERVAL - 1) begin
                cnt <= 32'h0;
                rl_valid <= 1'b1;
                if (core_mask == 2'b01) core_mask <= 2'b10;
                else core_mask <= 2'b01;
                freq_code <= freq_code + 1;
            end else begin
                cnt <= cnt + 1;
            end
        end
    end
endmodule
