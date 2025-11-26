
`timescale 1ns / 1ps
// Stage 3: Sobel Core
// 64x64 8-bit grayscale input -> 64x64 8-bit edge magnitude.
// Uses 3x3 Sobel kernel, stride 1, image size preserved.
// Internally uses two line buffers and a 3x3 window (9*8 FFs).
module sobel_core #(
    parameter integer IMG_WIDTH   = 64,
    parameter integer IMG_HEIGHT  = 64,
    parameter integer PIXEL_WIDTH = 8
)(
    input  wire                   clk1,
    input  wire                   rst,
    input  wire [PIXEL_WIDTH-1:0] data,
    input  wire                   read,
    output reg  [PIXEL_WIDTH-1:0] data_out,
    output reg                    valid,
    output reg                    write,
    output reg                    inc_endptr2
);
    localparam integer W_BITS = $clog2(IMG_WIDTH);

    // line buffers for previous 2 rows
    reg [PIXEL_WIDTH-1:0] line1 [0:IMG_WIDTH-1];
    reg [PIXEL_WIDTH-1:0] line2 [0:IMG_WIDTH-1];

    // 3x3 window: 9*8-bit FFs
    reg [PIXEL_WIDTH-1:0] w00, w01, w02;
    reg [PIXEL_WIDTH-1:0] w10, w11, w12;
    reg [PIXEL_WIDTH-1:0] w20, w21, w22;

    reg [W_BITS-1:0] x;
    reg [W_BITS-1:0] y;

    integer i;

    // reset line buffers
    initial begin
        for (i = 0; i < IMG_WIDTH; i = i + 1) begin
            line1[i] = 0;
            line2[i] = 0;
        end
    end

    function [7:0] sat8;
        input signed [15:0] v;
        begin
            if (v > 16'sd255)      sat8 = 8'hFF;
            else if (v < 16'sd0)   sat8 = 8'h00;
            else                   sat8 = v[7:0];
        end
    endfunction

    always @(posedge clk1 or posedge rst) begin
        if (rst==1'b1) begin
            x           <= 0;
            y           <= 0;
            {w00,w01,w02,w10,w11,w12,w20,w21,w22} <= 0;
            data_out    <= 0;
            valid       <= 1'b0;
            write       <= 1'b0;
            inc_endptr2 <= 1'b0;
        end else begin
            valid       <= 1'b0;
            write       <= 1'b0;
            inc_endptr2 <= 1'b0;

            if (read) begin
                // update line buffers
                line2[x] <= line1[x];
                line1[x] <= data;

                // shift window left
                w00 <= w01; w01 <= w02;
                w10 <= w11; w11 <= w12;
                w20 <= w21; w21 <= w22;

                // new rightmost column from line buffers/current pixel
                w02 <= line2[x]; // top row
                w12 <= line1[x]; // middle row (after update above)
                w22 <= data;     // bottom row

                // update coordinates
                if (x == IMG_WIDTH-1) begin
                    x <= 0;
                    if (y == IMG_HEIGHT-1) begin
                        y <= 0;
                    end else begin
                        y <= y + 1'b1;
                    end
                end else begin
                    x <= x + 1'b1;
                end

                // produce output once we have a full 3x3 neighbourhood
                if ((x > 1) && (y > 1)) begin
                    // Sobel Gx and Gy
                    // Gx = -w00 + w02 - 2*w10 + 2*w12 - w20 + w22
                    // Gy =  w00 + 2*w01 + w02 - w20 - 2*w21 - w22
                    // use signed arithmetic
                    integer gx, gy;
                    integer mag;
                    gx = -$signed({1'b0,w00}) + $signed({1'b0,w02})
                       - ( $signed({1'b0,w10}) <<< 1 )
                       + ( $signed({1'b0,w12}) <<< 1 )
                       - $signed({1'b0,w20}) + $signed({1'b0,w22});
                    gy =  $signed({1'b0,w00}) + ( $signed({1'b0,w01}) <<< 1 ) + $signed({1'b0,w02})
                       - $signed({1'b0,w20}) - ( $signed({1'b0,w21}) <<< 1 ) - $signed({1'b0,w22});
                    // magnitude approximation: |gx| + |gy|
                    if (gx < 0) gx = -gx;
                    if (gy < 0) gy = -gy;
                    mag = gx + gy;
                    data_out    <= sat8(mag[15:0]);
                    valid       <= 1'b1;
                    write       <= 1'b1;
                    inc_endptr2 <= 1'b1;
                end else begin
                    // border: output 0 but keep stride=1
                    data_out    <= 0;
                    valid       <= 1'b1;
                    write       <= 1'b1;
                    inc_endptr2 <= 1'b1;
                end
            end
        end
    end
endmodule
