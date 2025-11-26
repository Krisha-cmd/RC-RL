`timescale 1ns / 1ps
// logger_simple.v
// Small synchronous logger that collects periodic 16-bit entries and supports synchronous reads

module logger_simple #(
    parameter integer INTERVAL_CYCLES = 20,
    parameter integer ENTRY_WIDTH     = 16,
    parameter integer LOGGER_DEPTH    = 4096
)(
    input  wire clk,
    input  wire rst,
    input  wire [2:0] fifo1_load_bucket,
    input  wire [2:0] fifo2_load_bucket,
    input  wire resizer_state,
    input  wire gray_state,
    input  wire [7:0] divider_resizer,
    input  wire [7:0] divider_grayscale,
    input  wire start_logging,
    input  wire stop_logging,
    input  wire rd_en,
    output reg rd_valid,
    output reg [ENTRY_WIDTH-1:0] rd_data,
    output wire rd_done
);
    function integer clog2_local; input integer value; integer v; begin v = value - 1; clog2_local = 0; while (v > 0) begin clog2_local = clog2_local + 1; v = v >> 1; end end endfunction
    localparam integer ADDR_WIDTH = clog2_local(LOGGER_DEPTH);

    reg [ENTRY_WIDTH-1:0] mem [0:LOGGER_DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [15:0] cycle_cnt;
    reg logging_active;

    assign rd_done = (rd_ptr == wr_ptr);

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            cycle_cnt <= 16'h0;
            logging_active <= 1'b0;
        end else begin
            if (start_logging) logging_active <= 1'b1;
            if (stop_logging)  logging_active <= 1'b0;

            if (!logging_active) cycle_cnt <= 16'h0;
            else begin
                if (cycle_cnt < INTERVAL_CYCLES - 1) cycle_cnt <= cycle_cnt + 1;
                else begin
                    cycle_cnt <= 16'h0;
                    mem[wr_ptr] <= { fifo1_load_bucket, fifo2_load_bucket, resizer_state, gray_state, divider_resizer };
                    wr_ptr <= wr_ptr + 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            rd_data <= {ENTRY_WIDTH{1'b0}};
            rd_valid <= 1'b0;
        end else begin
            rd_valid <= 1'b0;
            if (rd_en && (rd_ptr != wr_ptr)) begin
                rd_data <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                rd_valid <= 1'b1;
            end
        end
    end

endmodule
