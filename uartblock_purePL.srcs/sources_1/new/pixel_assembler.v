`timescale 1ns / 1ps
module pixel_assembler #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS = 3
)(
    input  wire clk,
    input  wire rst,
    // BRAM FIFO read interface (consumer side)
    input  wire bram_rd_valid,    // from bram_fifo
    output reg  bram_rd_ready,    // assert to pop a byte
    input  wire [7:0] bram_rd_data,
    // Downstream pixel interface (resizer)
    output reg  [CHANNELS*PIXEL_WIDTH-1:0] pixel_out,
    output reg  pixel_valid,
    input  wire pixel_ready       // downstream ready to accept pixel
);
    reg [1:0] state;
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
                2'd0: begin
                    // start if a byte is available
                    if (bram_rd_valid) begin
                        bram_rd_ready <= 1'b1; // consume byte0 this cycle
                        state <= 2'd1;
                    end
                end
                2'd1: begin
                    // in next cycle bram_rd_data holds byte0
                    b0 <= bram_rd_data;
                    // request byte1
                    if (bram_rd_valid) begin
                        bram_rd_ready <= 1'b1;
                        state <= 2'd2;
                    end else state <= 2'd1;
                end
                2'd2: begin
                    b1 <= bram_rd_data;
                    if (bram_rd_valid) begin
                        bram_rd_ready <= 1'b1;
                        state <= 2'd3;
                    end else state <= 2'd2;
                end
                2'd3: begin
                    b2 <= bram_rd_data;
                    // assembled pixel; only output if downstream ready
                    if (pixel_ready) begin
                        pixel_out <= {b0, b1, bram_rd_data}; // {R,G,B}
                        pixel_valid <= 1'b1;
                        state <= 2'd0;
                    end else begin
                        // hold assembled bytes until downstream ready;
                        // do not consume further bytes (we already consumed all 3)
                        // We'll present pixel_valid next cycle when pixel_ready.
                        pixel_out <= {b0, b1, bram_rd_data};
                        state <= 2'd3;
                    end
                end
            endcase
        end
    end
endmodule
