`timescale 1ns / 1ps
module pixel_assembler #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS = 3
)(
    input  wire clk,
    input  wire rst,
    
    input  wire bram_rd_valid,    
    output reg  bram_rd_ready,    
    input  wire [7:0] bram_rd_data,
    
    output reg  [CHANNELS*PIXEL_WIDTH-1:0] pixel_out,
    output reg  pixel_valid,
    input  wire pixel_ready       
);
    reg [2:0] state;
    reg [7:0] b0, b1, b2;

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            state <= 0;
            bram_rd_ready <= 0;
            pixel_out <= 0;
            pixel_valid <= 0;
            b0 <= 0; b1 <= 0; b2 <= 0;
        end else begin
            pixel_valid <= 0;
            bram_rd_ready <= 0;
            case (state)
                3'd0: begin
                    
                    if (bram_rd_valid) begin
                        bram_rd_ready <= 1'b1;
                        state <= 3'd1;
                    end
                end
                3'd1: begin
                    
                    state <= 3'd2;
                end
                3'd2: begin
                    
                    b0 <= bram_rd_data;
                    
                    if (bram_rd_valid) begin
                        bram_rd_ready <= 1'b1;
                        state <= 3'd3;
                    end else begin
                        state <= 3'd2;
                    end
                end
                3'd3: begin
                    
                    state <= 3'd4;
                end
                3'd4: begin
                    
                    b1 <= bram_rd_data;
                    
                    if (bram_rd_valid) begin
                        bram_rd_ready <= 1'b1;
                        state <= 3'd5;
                    end else begin
                        state <= 3'd4;
                    end
                end
                3'd5: begin
                    
                    state <= 3'd6;
                end
                3'd6: begin
                    
                    b2 <= bram_rd_data;
                    if (pixel_ready) begin
                        pixel_out <= {b0, b1, bram_rd_data}; 
                        pixel_valid <= 1'b1;
                        state <= 3'd0;
                    end else begin
                        
                        pixel_out <= {b0, b1, bram_rd_data};
                        state <= 3'd6;
                    end
                end
                default: state <= 3'd0;
            endcase
        end
    end
endmodule
