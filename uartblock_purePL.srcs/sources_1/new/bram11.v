`timescale 1ns / 1ps


module bram_11 #(
    parameter integer DEPTH = 4096,
    parameter integer ADDR_WIDTH = 12
)(

    
    input  wire                  clk_a,
    input  wire [ADDR_WIDTH-1:0] porta_write_address,
    input  wire porta_write_enabled,
    input  wire porta_enabled,
    input  wire [7:0] porta_data_in,
    
    input  wire                  clk_b,
    input  wire [ADDR_WIDTH-1:0] portb_read_address,
    input  wire portb_enabled,
    output reg  [7:0] portb_data_out
);
    
    reg [7:0] mem [0:DEPTH-1];
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 8'h00;
    end

    
    always @(posedge clk_a) begin
        if (porta_write_enabled & porta_enabled)
            mem[porta_write_address] <= porta_data_in;
    end

    
    always @(posedge clk_b) begin
        if (portb_enabled)
            portb_data_out <= mem[portb_read_address];
        else
            portb_data_out <= 8'h00;
    end
endmodule
