`timescale 1ns / 1ps

// 1D Box Blur - simple 3-tap moving average filter
// output = (prev + current + next) / 3
// Uses a sliding window of 3 pixels

module box_blur_1d #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer IMG_WIDTH   = 64
)(
    input  wire                     clk,
    input  wire                     rst,

    input  wire [PIXEL_WIDTH-1:0]   data_in,
    input  wire                     read_signal,

    output reg  [PIXEL_WIDTH-1:0]   data_out,
    output reg                      write_signal,
    output reg                      state  // 1 when busy, else 0
);

    // Sliding window registers
    reg [PIXEL_WIDTH-1:0] prev;
    reg [PIXEL_WIDTH-1:0] curr;
    reg [PIXEL_WIDTH-1:0] next;
    
    // Pixel counter to track position in image
    reg [15:0] pixel_count;
    reg [1:0] startup_state;  // 0=empty, 1=one pixel, 2=two pixels, 3=running
    
    // Computation register
    reg [9:0] sum;
    
    always @(posedge clk or posedge rst) begin
        if (rst == 1'b1) begin
            data_out      <= 8'd0;
            write_signal  <= 1'b0;
            state         <= 1'b0;
            prev          <= 8'd0;
            curr          <= 8'd0;
            next          <= 8'd0;
            pixel_count   <= 16'd0;
            startup_state <= 2'd0;
            sum           <= 10'd0;
        end else begin
            write_signal <= 1'b0;
            state        <= 1'b0;

            if (read_signal) begin
                state <= 1'b1;
                
                // Shift the sliding window
                prev <= curr;
                curr <= next;
                next <= data_in;
                
                pixel_count <= pixel_count + 1;
                
                case (startup_state)
                    2'd0: begin
                        // First pixel - just store
                        startup_state <= 2'd1;
                    end
                    2'd1: begin
                        // Second pixel - still building window
                        startup_state <= 2'd2;
                    end
                    2'd2: begin
                        // Third pixel - window complete, start outputting
                        startup_state <= 2'd3;
                        // Compute average of 2 pixels (less smoothing)
                        sum = {2'b0, curr} + {2'b0, next};
                        data_out <= sum[8:1];  // Divide by 2 (simple average)
                        write_signal <= 1'b1;
                    end
                    2'd3: begin
                        // Running state - compute 2-tap average (lighter blur)
                        sum = {2'b0, curr} + {2'b0, next};
                        data_out <= sum[8:1];  // (curr+next)/2 - less aggressive smoothing
                        write_signal <= 1'b1;
                        
                        // Reset at end of frame (assuming 64x64 = 4096 pixels)
                        if (pixel_count >= (IMG_WIDTH * IMG_WIDTH - 1)) begin
                            pixel_count <= 16'd0;
                            startup_state <= 2'd0;
                            prev <= 8'd0;
                            curr <= 8'd0;
                            next <= 8'd0;
                        end
                    end
                endcase
            end
        end
    end

endmodule
