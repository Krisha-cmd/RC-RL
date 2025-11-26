`timescale 1ns / 1ps

// Stage 1: Resizer Core (2x downscale, nearest neighbour)
// PURE COMPUTE MODULE (stall-capable)

module resizer_core #(
    parameter integer IN_WIDTH      = 128,
    parameter integer IN_HEIGHT     = 128,
    parameter integer OUT_WIDTH     = 64,
    parameter integer OUT_HEIGHT    = 64,
    parameter integer PIXEL_WIDTH   = 8,
    parameter integer CHANNELS      = 3
)(
    input  wire                             clk,
    input  wire                             rst,

    input  wire [CHANNELS*PIXEL_WIDTH-1:0]  data_in,
    input  wire                             read_signal,   // pulse: consume 1 pixel

    output reg  [CHANNELS*PIXEL_WIDTH-1:0]  data_out,      // resized pixel out
    output reg                              write_signal,  // output valid
    output reg                              frame_done,    // frame completed
    output reg                              state          // activity flag (busy=1)
);

    // Bits needed to represent pixel coordinates
    localparam integer IN_W_BITS = $clog2(IN_WIDTH);
    localparam integer IN_H_BITS = $clog2(IN_HEIGHT);

    reg [IN_W_BITS-1:0] x;
    reg [IN_H_BITS-1:0] y;

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            x            <= 0;
            y            <= 0;
            data_out     <= 0;
            write_signal <= 0;
            frame_done   <= 0;
            state        <= 0;
        end else begin
            // defaults each cycle
            write_signal <= 0;
            frame_done   <= 0;
            state        <= 0;

            if (read_signal) begin
                state <= 1;  // ACTIVE this cycle

                // -----------------------------
                // Output pixel only when x,y even
                // -----------------------------
                if ((x[0] == 1'b0) && (y[0] == 1'b0) &&
                    (x < 2*OUT_WIDTH) &&
                    (y < 2*OUT_HEIGHT)) begin
                    data_out     <= data_in;
                    write_signal <= 1;   // 1-cycle valid pulse
                end

                // -----------------------------
                // Increment pixel coordinate
                // -----------------------------
                if (x == IN_WIDTH - 1) begin
                    x <= 0;

                    if (y == IN_HEIGHT - 1) begin
                        y <= 0;
                        frame_done <= 1;   // signal end-of-frame
                    end else begin
                        y <= y + 1;
                    end

                end else begin
                    x <= x + 1;
                end
            end
        end
    end

endmodule
