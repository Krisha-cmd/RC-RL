`timescale 1ns / 1ps



module clock_module_simple (
    input  wire clk,
    input  wire rst,
    input  wire rl_valid,
    input  wire [1:0] core_mask,
    input  wire [7:0] freq_code,
    output reg ce_resizer,
    output reg ce_grayscale,
    output reg [7:0] divider_resizer,
    output reg [7:0] divider_grayscale
);
    reg [31:0] cnt_resizer, cnt_gray;

    function [7:0] map_code_to_div;
        input [7:0] code;
        begin
            map_code_to_div = (code % 250) + 1; 
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            divider_resizer <= 8'd10;
            divider_grayscale <= 8'd20;
            cnt_resizer <= 32'h0;
            cnt_gray <= 32'h0;
            ce_resizer <= 1'b0;
            ce_grayscale <= 1'b0;
        end else begin
            ce_resizer <= 1'b0;
            ce_grayscale <= 1'b0;

            if (rl_valid) begin
                if (core_mask[0]) divider_resizer <= map_code_to_div(freq_code);
                if (core_mask[1]) divider_grayscale <= map_code_to_div(freq_code);
            end

            if (cnt_resizer >= divider_resizer - 1) begin
                cnt_resizer <= 32'h0;
                ce_resizer <= 1'b1;
            end else begin
                cnt_resizer <= cnt_resizer + 1;
            end

            if (cnt_gray >= divider_grayscale - 1) begin
                cnt_gray <= 32'h0;
                ce_grayscale <= 1'b1;
            end else begin
                cnt_gray <= cnt_gray + 1;
            end
        end
    end
endmodule
