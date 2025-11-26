`timescale 1ns / 1ps

module boxblur_core #(
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

    reg [PIXEL_WIDTH-1:0] line1 [0:IMG_WIDTH-1];
    reg [PIXEL_WIDTH-1:0] line2 [0:IMG_WIDTH-1];

    reg [PIXEL_WIDTH-1:0] w00, w01, w02;
    reg [PIXEL_WIDTH-1:0] w10, w11, w12;
    reg [PIXEL_WIDTH-1:0] w20, w21, w22;

    reg [W_BITS-1:0] x;
    reg [W_BITS-1:0] y;

    integer i;
    integer sum;   // moved here (legal)

    // Clear line buffers
    initial begin
        for (i = 0; i < IMG_WIDTH; i = i + 1)
            line1[i] = 0;
        for (i = 0; i < IMG_WIDTH; i = i + 1)
            line2[i] = 0;
    end

    always @(posedge clk1 or posedge rst) begin
        if (rst==1'b1) begin
            x <= 0;
            y <= 0;

            {w00,w01,w02,w10,w11,w12,w20,w21,w22} <= 0;

            data_out    <= 0;
            valid       <= 0;
            write       <= 0;
            inc_endptr2 <= 0;

        end else begin
            // default outputs
            valid       <= 0;
            write       <= 0;
            inc_endptr2 <= 0;

            if (read) begin

                // ---------------------------------------------------
                // Line Buffers (previous row shift)
                // ---------------------------------------------------
                line2[x] <= line1[x];
                line1[x] <= data;

                // ---------------------------------------------------
                // Shift 3x3 window left
                // ---------------------------------------------------
                w00 <= w01;  w01 <= w02;
                w10 <= w11;  w11 <= w12;
                w20 <= w21;  w21 <= w22;

                // ---------------------------------------------------
                // Insert new rightmost column
                // ---------------------------------------------------
                w02 <= line2[x];
                w12 <= line1[x];
                w22 <= data;

                // ---------------------------------------------------
                // Compute blur (only valid after first two rows)
                // ---------------------------------------------------
                if ((x > 1) && (y > 1)) begin
                    sum =
                        w00 + w01 + w02 +
                        w10 + w11 + w12 +
                        w20 + w21 + w22;

                    data_out <= sum / 9;
                end else begin
                    data_out <= 0;
                end

                valid       <= 1;
                write       <= 1;
                inc_endptr2 <= 1;

                // ---------------------------------------------------
                // Update coordinates
                // ---------------------------------------------------
                if (x == IMG_WIDTH-1) begin
                    x <= 0;
                    if (y == IMG_HEIGHT-1)
                        y <= 0;
                    else
                        y <= y + 1;
                end else begin
                    x <= x + 1;
                end
            end
        end
    end
endmodule
