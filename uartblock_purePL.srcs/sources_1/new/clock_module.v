`timescale 1ns/1ps

module clock_module (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        rl_valid,
    input  wire [1:0]  core_mask,
    input  wire [7:0]  freq_code,

    output reg         ce_resizer,
    output reg         ce_grayscale,

    // expose divider values for logging
    output reg [7:0]   divider_resizer,
    output reg [7:0]   divider_gray
);

    reg [7:0] cnt_resizer = 0;
    reg [7:0] cnt_gray    = 0;

    always @(posedge clk or posedge rst_n) begin
        if (rst_n==1'b1) begin
            divider_resizer <= 8'd1;
            divider_gray    <= 8'd1;
            cnt_resizer <= 0;
            cnt_gray <= 0;
            ce_resizer <= 0;
            ce_grayscale <= 0;
        end else begin
            if (rl_valid) begin
                if (core_mask[0] && freq_code!=0)
                    divider_resizer <= freq_code;

                if (core_mask[1] && freq_code!=0)
                    divider_gray <= freq_code;
            end

            // RESIZER CE
            if (cnt_resizer == divider_resizer-1) begin
                ce_resizer <= 1;
                cnt_resizer <= 0;
            end else begin
                ce_resizer <= 0;
                cnt_resizer <= cnt_resizer + 1;
            end

            // GRAYSCALE CE
            if (cnt_gray == divider_gray-1) begin
                ce_grayscale <= 1;
                cnt_gray <= 0;
            end else begin
                ce_grayscale <= 0;
                cnt_gray <= cnt_gray + 1;
            end
        end
    end
endmodule
