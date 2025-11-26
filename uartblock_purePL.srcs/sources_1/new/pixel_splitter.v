`timescale 1ns / 1ps
module pixel_splitter #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS = 3
)(
    input  wire clk,
    input  wire rst,
    
    input  wire [CHANNELS*PIXEL_WIDTH-1:0] pixel_in,
    input  wire pixel_in_valid,
    output reg  pixel_in_ready,
    
    output reg  bram_wr_valid,
    input  wire bram_wr_ready,
    output reg  [7:0] bram_wr_data
);
    reg [1:0] state;
    reg [CHANNELS*PIXEL_WIDTH-1:0] pixel_reg;

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            state <= 0;
            bram_wr_valid <= 0;
            bram_wr_data <= 0;
            pixel_in_ready <= 0;
            pixel_reg <= 0;
        end else begin
            
            pixel_in_ready <= 0;
            bram_wr_valid <= 0;

            case (state)
                2'd0: begin
                    if (pixel_in_valid) begin
                        pixel_reg <= pixel_in;
                        
                        bram_wr_data <= pixel_in[23:16];
                        if (bram_wr_ready) begin
                            bram_wr_valid <= 1'b1;
                            state <= 2'd1;
                            pixel_in_ready <= 1'b1; 
                        end else begin
                            
                            state <= 2'd0;
                        end
                    end
                end
                2'd1: begin
                    
                    bram_wr_data <= pixel_reg[15:8];
                    if (bram_wr_ready) begin
                        bram_wr_valid <= 1'b1;
                        state <= 2'd2;
                    end else state <= 2'd1;
                end
                2'd2: begin
                    bram_wr_data <= pixel_reg[7:0];
                    if (bram_wr_ready) begin
                        bram_wr_valid <= 1'b1;
                        state <= 2'd0;
                    end else state <= 2'd2;
                end
            endcase
        end
    end
endmodule
