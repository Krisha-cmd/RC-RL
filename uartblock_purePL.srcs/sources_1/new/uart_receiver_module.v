
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/10/2025 12:29:15 PM
// Design Name: 
// Module Name: uart_receiver_module
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// UART RX (8N1), 16x oversample receiver.
// Parameters: CLOCK_FREQ (Hz), BAUD_RATE (bps).
// Instantiation in top uses CLOCK_FREQ = 100_000_000 for ZedBoard.

module uart_receiver_module #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200
)(
    input  wire        clk,        // system clock (100 MHz recommended)
    input  wire        rst_n,      // active low reset
    input  wire        rx,         // serial input (UART TX from adapter -> this rx)
    output reg  [7:0]  rx_byte,    // received byte
    output reg         rx_byte_valid // 1-clock pulse when rx_byte is valid
);

    localparam integer OVERSAMPLE = 16;
    // sample divider: CLOCK_FREQ / (BAUD_RATE * OVERSAMPLE)
    localparam integer SAMPLE_CLK_DIV = (CLOCK_FREQ + (BAUD_RATE*OVERSAMPLE)/2) / (BAUD_RATE*OVERSAMPLE);

    // state machine
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [4:0] sample_cnt; // enough for OVERSAMPLE up to 16
    reg [2:0] bit_index;
    reg [7:0] shift_reg;
    reg rx_sync0, rx_sync1;

    // clock divider
    reg [31:0] clk_div_cnt;
    wire sample_tick = (clk_div_cnt == 0);

    // Sync rx to clock domain
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
        end
    end

    // clock divider for oversample ticks
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_cnt <= 0;
        end else begin
            if (clk_div_cnt == 0)
                clk_div_cnt <= SAMPLE_CLK_DIV - 1;
            else
                clk_div_cnt <= clk_div_cnt - 1;
        end
    end

    // FSM: sample at OVERSAMPLE ticks.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            sample_cnt <= 0;
            bit_index <= 0;
            shift_reg <= 8'd0;
            rx_byte <= 8'd0;
            rx_byte_valid <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;
            if (sample_tick) begin
                case (state)
                    IDLE: begin
                        if (rx_sync1 == 1'b0) begin // start bit candidate
                            state <= START;
                            sample_cnt <= 0;
                        end
                    end
                    START: begin
                        sample_cnt <= sample_cnt + 1;
                        // sample in middle of start bit
                        if (sample_cnt == (OVERSAMPLE/2 - 1)) begin
                            if (rx_sync1 == 1'b0) begin
                                state <= DATA;
                                sample_cnt <= 0;
                                bit_index <= 0;
                                shift_reg <= 8'd0;
                            end else begin
                                state <= IDLE;
                            end
                        end
                    end
                    DATA: begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == OVERSAMPLE - 1) begin
                            sample_cnt <= 0;
                            shift_reg[bit_index] <= rx_sync1; // LSB first
                            if (bit_index == 7) begin
                                state <= STOP;
                            end else begin
                                bit_index <= bit_index + 1;
                            end
                        end
                    end
                    STOP: begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == (OVERSAMPLE - 1)) begin
                            rx_byte <= shift_reg;
                            rx_byte_valid <= 1'b1;
                            state <= IDLE;
                            sample_cnt <= 0;
                        end
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
