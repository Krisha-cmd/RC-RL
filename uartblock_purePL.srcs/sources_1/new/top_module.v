`timescale 1ns / 1ps











`timescale 1ns / 1ps





module top_module #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200,
    parameter integer IMG_WIDTH  = 64,
    parameter integer IMG_HEIGHT = 48,
    parameter integer PIXEL_WIDTH = 8,
    parameter integer IMG_SIZE = IMG_WIDTH * IMG_HEIGHT,
    parameter integer ADDR_WIDTH = $clog2((IMG_SIZE==1)?2:IMG_SIZE)
)(
    input  wire                     clk,         
    input  wire                     uart_rx,     
    output wire                     frame_done_debug 
);

    
    
    
    
    wire rst = 1'b1;

    
    
    wire [ADDR_WIDTH-1:0] read_addr = {ADDR_WIDTH{1'b0}};
    wire [PIXEL_WIDTH-1:0] read_pixel;
    wire                  frame_done_pulse;

    
    wire [PIXEL_WIDTH-1:0] rx_byte;
    wire                   rx_byte_valid;
    wire [ADDR_WIDTH-1:0]  write_addr;

    
    
    
    uart_receiver_module #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid)
    );

    
    
    
    bram_controller_module #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_ctrl_inst (
        .clk(clk),
        .rst(rst),
        .write_data(rx_byte),
        .write_valid(rx_byte_valid),
        .read_addr(read_addr),         
        .read_data(read_pixel),        
        .frame_done(frame_done_pulse), 
        .write_addr(write_addr)
    );

    
    
    
    pulse_stretcher #(.WIDTH(24)) stretcher_inst (
        .clk(clk),
        .rst(rst),
        .pulse_in(frame_done_pulse),
        .stretched_out(frame_done_debug)
    );

endmodule
