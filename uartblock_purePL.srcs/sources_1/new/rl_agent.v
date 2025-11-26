`timescale 1ns / 1ps
// rl_agent.v
// Simple FSM that issues frequency commands every INTERVAL cycles.
// Can issue single-core updates or multi-core updates using core_mask.

module rl_agent #(
    parameter integer INTERVAL = 20  // trigger every N cycles
)(
    input  wire clk,
    input  wire rst,

    // output command (pulse of 1 cycle)
    output reg        rl_valid,
    output reg [1:0]  core_mask,   // bit0=resizer, bit1=grayscale
    output reg [7:0]  freq_code    // divider to program
);

    reg [31:0] cycle_counter;
    reg [1:0]  state;

    localparam S_IDLE  = 2'd0;
    localparam S_SEND1 = 2'd1;
    localparam S_SEND2 = 2'd2;

    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            cycle_counter <= 32'd0;
            rl_valid <= 1'b0;
            core_mask <= 2'b00;
            freq_code <= 8'd1;
            state <= S_IDLE;
        end else begin
            // default deassert
            rl_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (cycle_counter >= INTERVAL - 1) begin
                        cycle_counter <= 32'd0;
                        state <= S_SEND1;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                S_SEND1: begin
                    // Example behaviour: alternate simple policies
                    // Here we set resizer to divide by 4 (1/4 rate)
                    rl_valid <= 1'b1;
                    core_mask <= 2'b01;    // only resizer
                    freq_code <= 8'd4;
                    state <= S_SEND2;
                end

                S_SEND2: begin
                    // Second command: set both cores to divide-by-2
                    rl_valid <= 1'b1;
                    core_mask <= 2'b11;    // both cores
                    freq_code <= 8'd2;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
