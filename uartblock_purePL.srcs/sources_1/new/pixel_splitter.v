`timescale 1ns / 1ps
module pixel_splitter #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS = 3
)(
    input  wire clk,
    input  wire rst_n,
    // Resizer output
    input  wire [CHANNELS*PIXEL_WIDTH-1:0] pixel_in,
    input  wire pixel_in_valid,
    output reg  pixel_in_ready,
    // BRAM FIFO write interface (producer)
    output reg  bram_wr_valid,
    input  wire bram_wr_ready,
    output reg  [7:0] bram_wr_data
);
    reg [1:0] state;
    reg [CHANNELS*PIXEL_WIDTH-1:0] pixel_reg;

    always @(posedge clk or posedge rst_n) begin
        if (rst_n==1'b1) begin
            state <= 0;
            bram_wr_valid <= 0;
            bram_wr_data <= 0;
            pixel_in_ready <= 0;
            pixel_reg <= 0;
        end else begin
            // default
            pixel_in_ready <= 0;
            bram_wr_valid <= 0;

            case (state)
                2'd0: begin
                    if (pixel_in_valid) begin
                        pixel_reg <= pixel_in;
                        // try to write first byte if FIFO ready
                        bram_wr_data <= pixel_in[23:16];
                        if (bram_wr_ready) begin
                            bram_wr_valid <= 1'b1;
                            state <= 2'd1;
                            pixel_in_ready <= 1'b1; // accept pixel
                        end else begin
                            // wait for FIFO ready
                            state <= 2'd0;
                        end
                    end
                end
                2'd1: begin
                    // write byte1
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
