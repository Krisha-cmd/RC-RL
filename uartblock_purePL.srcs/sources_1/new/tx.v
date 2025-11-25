`timescale 1ns / 1ps

module tx #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200
)(
    input  wire clk,
    input  wire rst_n,

    output reg  tx,               // UART TX line
    input  wire tx_start,         // 1-cycle pulse to send byte
    input  wire [7:0] tx_data,

    output wire tx_busy           // <-- ADDED: used by top_processing
);

    localparam integer BAUD_DIV = CLOCK_FREQ / BAUD_RATE;

    // busy flag
    reg busy_reg;
    assign tx_busy = busy_reg;

    // shift register: {stop, data[7:0], start}
    reg [9:0] shift_reg;

    reg [15:0] baud_cnt;
    reg [3:0]  bit_idx;

    // ----------------------------------------------
    // Initialization
    // ----------------------------------------------
    initial begin
        tx        = 1'b1;                 // idle HIGH
        shift_reg = 10'b1111111111;
        busy_reg  = 1'b0;
        baud_cnt  = 0;
        bit_idx   = 0;
    end

    // ----------------------------------------------
    // UART transmitter logic
    // ----------------------------------------------
    always @(posedge clk or posedge rst_n) begin
        if (rst_n==1'b1) begin
            tx        <= 1'b1;
            busy_reg  <= 1'b0;
            shift_reg <= 10'b1111111111;
            baud_cnt  <= 0;
            bit_idx   <= 0;
        end 
        else begin

            if (!busy_reg) begin
                // ----------------------------------------------------
                // Idle state: wait for tx_start pulse
                // ----------------------------------------------------
                if (tx_start) begin
                    // Build TX frame:
                    //   start bit (0)
                    //   8 data bits (LSB first)
                    //   stop bit  (1)
                    shift_reg <= {1'b1, tx_data, 1'b0};

                    busy_reg  <= 1'b1;
                    bit_idx   <= 0;
                    baud_cnt  <= BAUD_DIV - 1;
                end
            end 
            else begin
                // ----------------------------------------------------
                // Transmitting bits
                // ----------------------------------------------------
                if (baud_cnt == 0) begin

                    tx <= shift_reg[0];            // output LSB
                    shift_reg <= {1'b1, shift_reg[9:1]};   // shift right

                    bit_idx <= bit_idx + 1;

                    if (bit_idx == 9)
                        busy_reg <= 1'b0;          // all 10 bits sent

                    baud_cnt <= BAUD_DIV - 1;

                end 
                else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end

        end
    end

endmodule
