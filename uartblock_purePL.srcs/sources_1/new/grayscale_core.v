`timescale 1ns / 1ps

module grayscale_core #(
    parameter integer IMG_WIDTH    = 64,
    parameter integer IMG_HEIGHT   = 64,
    parameter integer PIXEL_WIDTH  = 8
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clk_en,        // clock enable from agent

    input  wire [3*PIXEL_WIDTH-1:0] data_in,    
    input  wire                     read_signal,

    output reg  [PIXEL_WIDTH-1:0]   data_out,
    output reg                      write_signal,
    output reg                      state         // 1 when busy, else 0
);

    // Extract channels
    wire [7:0] r = data_in[3*PIXEL_WIDTH-1 : 2*PIXEL_WIDTH];
    wire [7:0] g = data_in[2*PIXEL_WIDTH-1 : 1*PIXEL_WIDTH];
    wire [7:0] b = data_in[1*PIXEL_WIDTH-1 : 0];

    // gray = (77R + 150G + 29B) >> 8
    wire [15:0] gray_mult = 16'd77  * r +
                            16'd150 * g +
                            16'd29  * b;

    wire [7:0] gray = gray_mult[15:8];

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            data_out     <= 8'd0;
            write_signal <= 1'b0;
            state        <= 1'b0;
        end else if (clk_en) begin
            write_signal <= 1'b0;    
            state        <= 1'b0;    // default: idle

            if (read_signal) begin
                state        <= 1'b1;    // ACTIVE for 1 cycle
                data_out     <= gray;
                write_signal <= 1'b1;    
            end
        end
    end

endmodule
