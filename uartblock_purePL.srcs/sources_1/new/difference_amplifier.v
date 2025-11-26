`timescale 1ns / 1ps

// Difference Amplifier - amplifies differences from a reference value (128 for grayscale)
// Enhances contrast by amplifying deviations from mid-gray
// output = 128 + gain * (input - 128), clamped to [0, 255]

module difference_amplifier #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer GAIN = 2  // Amplification factor (1-4 recommended)
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clk_en,        // clock enable from agent

    input  wire [PIXEL_WIDTH-1:0]   data_in,
    input  wire                     read_signal,

    output reg  [PIXEL_WIDTH-1:0]   data_out,
    output reg                      write_signal,
    output reg                      state  // 1 when busy, else 0
);

    localparam signed [8:0] REFERENCE = 9'd128;
    
    // Internal computation registers
    reg signed [9:0] diff;
    reg signed [10:0] amplified;
    reg signed [9:0] result;
    
    always @(posedge clk or posedge rst) begin
        if (rst == 1'b1) begin
            data_out     <= 8'd0;
            write_signal <= 1'b0;
            state        <= 1'b0;
            diff         <= 10'd0;
            amplified    <= 11'd0;
            result       <= 10'd0;
        end else if (clk_en) begin
            write_signal <= 1'b0;
            state        <= 1'b0;

            if (read_signal) begin
                state <= 1'b1;
                
                // Compute difference from reference
                diff = {1'b0, data_in} - REFERENCE;
                amplified = diff * GAIN;
                result = REFERENCE + amplified;
                
                // Clamp to [0, 255]
                if (result[9] == 1'b1 && result[8] == 1'b1) begin
                    // Negative overflow
                    data_out <= 8'd0;
                end else if (result[9:8] != 2'b00) begin
                    // Positive overflow
                    data_out <= 8'd255;
                end else begin
                    data_out <= result[7:0];
                end
                
                write_signal <= 1'b1;
            end
        end
    end

endmodule
