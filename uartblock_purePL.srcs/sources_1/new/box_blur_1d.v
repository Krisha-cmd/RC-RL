`timescale 1ns / 1ps





module box_blur_1d #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer IMG_WIDTH   = 64
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clk_en,        

    input  wire [PIXEL_WIDTH-1:0]   data_in,
    input  wire                     read_signal,

    output reg  [PIXEL_WIDTH-1:0]   data_out,
    output reg                      write_signal,
    output reg                      state  
);

    
    reg [PIXEL_WIDTH-1:0] prev;
    reg [PIXEL_WIDTH-1:0] curr;
    reg [PIXEL_WIDTH-1:0] next;
    
    
    reg [15:0] pixel_count;
    reg [1:0] startup_state;  
    
    
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
        end else if (clk_en) begin
            write_signal <= 1'b0;
            state        <= 1'b0;

            if (read_signal) begin
                state <= 1'b1;
                
                
                prev <= curr;
                curr <= next;
                next <= data_in;
                
                pixel_count <= pixel_count + 1;
                
                case (startup_state)
                    2'd0: begin
                        
                        startup_state <= 2'd1;
                    end
                    2'd1: begin
                        
                        startup_state <= 2'd2;
                    end
                    2'd2: begin
                        
                        startup_state <= 2'd3;
                        
                        sum = {2'b0, curr} + {2'b0, next};
                        data_out <= sum[8:1];  
                        write_signal <= 1'b1;
                    end
                    2'd3: begin
                        
                        sum = {2'b0, curr} + {2'b0, next};
                        data_out <= sum[8:1];  
                        write_signal <= 1'b1;
                        
                        
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
