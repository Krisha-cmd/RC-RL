`timescale 1ns / 1ps

module tx #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200
)(
    input  wire clk,
    input  wire rst,

    output reg  tx,               
    input  wire tx_start,         
    input  wire [7:0] tx_data,

    output wire tx_busy           
);

    localparam integer BAUD_DIV = CLOCK_FREQ / BAUD_RATE;

    
    reg busy_reg;
    assign tx_busy = busy_reg;

    
    reg [9:0] shift_reg;

    reg [15:0] baud_cnt;
    reg [3:0]  bit_idx;

    
    
    
    initial begin
        tx        = 1'b1;                 
        shift_reg = 10'b1111111111;
        busy_reg  = 1'b0;
        baud_cnt  = 0;
        bit_idx   = 0;
    end

    
    
    
    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            tx        <= 1'b1;
            busy_reg  <= 1'b0;
            shift_reg <= 10'b1111111111;
            baud_cnt  <= 0;
            bit_idx   <= 0;
        end 
        else begin

            if (!busy_reg) begin
                
                
                
                if (tx_start) begin
                    
                    
                    
                    
                    shift_reg <= {1'b1, tx_data, 1'b0};

                    busy_reg  <= 1'b1;
                    bit_idx   <= 0;
                    baud_cnt  <= BAUD_DIV - 1;
                end
            end 
            else begin
                
                
                
                if (baud_cnt == 0) begin

                    tx <= shift_reg[0];            
                    shift_reg <= {1'b1, shift_reg[9:1]};   

                    bit_idx <= bit_idx + 1;

                    if (bit_idx == 9)
                        busy_reg <= 1'b0;          

                    baud_cnt <= BAUD_DIV - 1;

                end 
                else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end

        end
    end

endmodule
