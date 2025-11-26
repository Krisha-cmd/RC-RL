`timescale 1ns / 1ps



















module bram_controller_module #(
    parameter integer IMG_WIDTH   = 64,
    parameter integer IMG_HEIGHT  = 48,
    parameter integer PIXEL_WIDTH = 8,
    parameter integer IMG_SIZE = IMG_WIDTH * IMG_HEIGHT,
    parameter integer ADDR_WIDTH = $clog2((IMG_SIZE==1)?2:IMG_SIZE)
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [PIXEL_WIDTH-1:0]  write_data,
    input  wire                    write_valid,
    input  wire [ADDR_WIDTH-1:0]   read_addr,
    output reg  [PIXEL_WIDTH-1:0]  read_data,
    output reg                     frame_done,
    output reg [ADDR_WIDTH-1:0]    write_addr
);

    
    (* ram_style = "block" *) reg [PIXEL_WIDTH-1:0] mem [0:IMG_SIZE-1];
    reg [ADDR_WIDTH-1:0] write_ptr;

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            write_ptr <= {ADDR_WIDTH{1'b0}};
            frame_done <= 1'b0;
            write_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            frame_done <= 1'b0;
            if (write_valid) begin
                mem[write_ptr] <= write_data;
                if (write_ptr == IMG_SIZE - 1) begin
                    write_ptr <= {ADDR_WIDTH{1'b0}};
                    frame_done <= 1'b1;
                end else begin
                    write_ptr <= write_ptr + 1'b1;
                end
            end
            write_addr <= write_ptr;
        end
    end

    
    always @(posedge clk) begin
        read_data <= mem[read_addr];
    end

endmodule


