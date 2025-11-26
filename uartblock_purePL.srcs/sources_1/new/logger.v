`timescale 1ns / 1ps

module logger #(
    parameter integer INTERVAL_CYCLES = 20,
    parameter integer ENTRY_WIDTH     = 16,
    parameter integer LOGGER_DEPTH    = 12288,
    // Default active flag: if 1 then logger starts active after reset
    parameter integer DEFAULT_ACTIVE  = 1,
    parameter integer ADDR_WIDTH      = $clog2(LOGGER_DEPTH)
)(
    input  wire clk,
    input  wire rst,

    // signals to sample
    input  wire [2:0] fifo1_load_bucket,
    input  wire [2:0] fifo2_load_bucket,
    input  wire       resizer_state,
    input  wire       gray_state,

    // clock "frequency" info from clock_module
    input  wire [7:0] divider_resizer,     // log this instead of sampled clock
    input  wire [7:0] divider_grayscale,

    // control
    input  wire       start_logging,
    input  wire       stop_logging,

    // read interface
    input  wire       rd_clk,
    input  wire       rd_en,
    output reg        rd_valid,
    output reg [15:0] rd_data,
    output wire       rd_done
);

    reg [ENTRY_WIDTH-1:0] mem [0:LOGGER_DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    reg [15:0] cycle_cnt;
    reg logging_active;
    // read-side strobe extension so consumer can reliably sample rd_valid
    reg rd_valid_hold;

    assign rd_done = (rd_ptr == wr_ptr);

    // WRITE SIDE
    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            wr_ptr <= 0;
            cycle_cnt <= 0;
            // initialize logging_active according to DEFAULT_ACTIVE
            logging_active <= (DEFAULT_ACTIVE != 0) ? 1'b1 : 1'b0;
        end else begin

            if (start_logging)
                logging_active <= 1;

            if (stop_logging)
                logging_active <= 0;

            if (!logging_active) begin
                cycle_cnt <= 0;
            end else begin
                if (cycle_cnt < INTERVAL_CYCLES-1)
                    cycle_cnt <= cycle_cnt + 1;
                else begin
                    cycle_cnt <= 0;

                    // PACK ENTRY (16 bits):
                    // [15:13] fifo1_load_bucket
                    // [12:10] fifo2_load_bucket
                    // [9]     resizer_state
                    // [8]     gray_state
                    // [7:4]   divider_resizer[3:0]
                    // [3:0]   divider_grayscale[3:0]
                    mem[wr_ptr] <= {
                        fifo1_load_bucket,     // 15:13
                        fifo2_load_bucket,     // 12:10
                        resizer_state,         // 9
                        gray_state,            // 8
                        divider_resizer[3:0],  // 7:4
                        divider_grayscale[3:0] // 3:0
                    };
                    // If you want grayscale divider also:
                    // replace last 4 bits with something else, or expand to 24 bits

                    wr_ptr <= wr_ptr + 1;
                end
            end
        end
    end

    // READ SIDE
    // Ensure rd_valid is asserted in the same cycle as rd_en when data is
    // available, and also hold it for one additional cycle so synchronous
    // consumers which sample slightly later can still observe it.
    always @(posedge rd_clk or posedge rst) begin
        if (rst==1'b1) begin
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            rd_data <= 16'h0;
            rd_valid <= 1'b0;
            rd_valid_hold <= 1'b0;
        end else begin
            // default clear rd_valid; we'll set it below if read occurs or hold active
            rd_valid <= 1'b0;

            if (rd_en && (rd_ptr != wr_ptr)) begin
                // present data this cycle (synchronous read)
                rd_data <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                rd_valid <= 1'b1;
                rd_valid_hold <= 1'b1; // request one-cycle hold
            end else if (rd_valid_hold) begin
                // hold rd_valid for one extra cycle
                rd_valid <= 1'b1;
                rd_valid_hold <= 1'b0;
            end else begin
                rd_valid <= 1'b0;
            end
        end
    end

endmodule
