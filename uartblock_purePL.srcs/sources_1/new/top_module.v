`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 11/10/2025
// Module Name: top_module
// Description: Top-level wrapper for UART -> BRAM image receiver.
// Keeps readback signals internal so no extra top-level I/Os are required
// (useful for quick testing / bitstream generation).
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Top-level wrapper for UART -> BRAM image receiver.
// Keeps readback signals internal so no extra top-level I/Os are required
//////////////////////////////////////////////////////////////////////////////////

module top_module #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200,
    parameter integer IMG_WIDTH  = 64,
    parameter integer IMG_HEIGHT = 48,
    parameter integer PIXEL_WIDTH = 8,
    parameter integer IMG_SIZE = IMG_WIDTH * IMG_HEIGHT,
    parameter integer ADDR_WIDTH = $clog2((IMG_SIZE==1)?2:IMG_SIZE)
)(
    input  wire                     clk,         // ZedBoard PL 100 MHz clock (Y9)
    input  wire                     uart_rx,     // PMOD JA1 -> package pin Y11
    output wire                     frame_done_debug // stretched LED visible (LD0 -> T22)
);

    // -------------------------------------------------------------------------
    // Internal signals and ties
    // -------------------------------------------------------------------------
    // Tie reset high (inactive) because removed from top-level ports.
    wire rst_n = 1'b1;

    // Keep read_addr/read_pixel/frame_done_pulse internal for now.
    // read_addr tied to 0 (unused external read); read_pixel driven by BRAM.
    wire [ADDR_WIDTH-1:0] read_addr = {ADDR_WIDTH{1'b0}};
    wire [PIXEL_WIDTH-1:0] read_pixel;
    wire                  frame_done_pulse;

    // Data path signals
    wire [PIXEL_WIDTH-1:0] rx_byte;
    wire                   rx_byte_valid;
    wire [ADDR_WIDTH-1:0]  write_addr;

    // -------------------------------------------------------------------------
    // UART receiver instance
    // -------------------------------------------------------------------------
    uart_receiver_module #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid)
    );

    // -------------------------------------------------------------------------
    // BRAM controller instance (write path: UART -> BRAM)
    // -------------------------------------------------------------------------
    bram_controller_module #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_ctrl_inst (
        .clk(clk),
        .rst_n(rst_n),
        .write_data(rx_byte),
        .write_valid(rx_byte_valid),
        .read_addr(read_addr),         // internal (currently tied to zero)
        .read_data(read_pixel),        // internal read data
        .frame_done(frame_done_pulse), // one-clock internal pulse when frame completes
        .write_addr(write_addr)
    );

    // -------------------------------------------------------------------------
    // Pulse stretcher: make the 1-clock frame_done visible on an LED
    // -------------------------------------------------------------------------
    pulse_stretcher #(.WIDTH(24)) stretcher_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pulse_in(frame_done_pulse),
        .stretched_out(frame_done_debug)
    );

endmodule
