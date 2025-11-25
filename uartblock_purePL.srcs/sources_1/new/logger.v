`timescale 1ns / 1ps

module logger #(
    parameter integer INTERVAL_CYCLES = 20,
    parameter integer ENTRY_WIDTH     = 16,
    parameter integer LOGGER_DEPTH    = 12288,
    parameter integer ADDR_WIDTH      = $clog2(LOGGER_DEPTH)
)(
    input  wire clk,
    input  wire rst_n,

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

    assign rd_done = (rd_ptr == wr_ptr);

    // WRITE SIDE
    always @(posedge clk or posedge rst_n) begin
        if (rst_n==1'b1) begin
            wr_ptr <= 0;
            cycle_cnt <= 0;
            logging_active <= 0;
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

                    // PACK ENTRY
                    mem[wr_ptr] <= {
                        fifo1_load_bucket,     // 15:13
                        fifo2_load_bucket,     // 12:10
                        resizer_state,         // 9
                        gray_state,            // 8
                        divider_resizer[3:0]   // 7:4  log low bits
                    };
                    // If you want grayscale divider also:
                    // replace last 4 bits with something else, or expand to 24 bits

                    wr_ptr <= wr_ptr + 1;
                end
            end
        end
    end

    // READ SIDE
    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            rd_data <= 0;
            rd_valid <= 0;
        end else begin
            rd_valid <= 0;

            if (rd_en && (rd_ptr != wr_ptr)) begin
                rd_data <= mem[rd_ptr];
                rd_ptr  <= rd_ptr + 1;
                rd_valid <= 1;
            end
        end
    end

endmodule
