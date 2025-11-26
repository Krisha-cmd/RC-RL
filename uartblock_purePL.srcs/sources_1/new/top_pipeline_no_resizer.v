`timescale 1ns / 1ps
// top_pipeline_no_resizer.v
// Pipeline: RX -> assembler1 -> splitter -> FIFO2 -> grayscale -> FIFO3 -> TX
// No resizer stage; uses original image resolution but still sends grayscale (if present).

module top_pipeline_no_resizer #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS    = 3,
    parameter integer IN_WIDTH    = 128,
    parameter integer IN_HEIGHT   = 128,
    parameter integer FIFO1_DEPTH = 8192,
    parameter integer FIFO2_DEPTH = 8192
)(
    input  wire clk,
    input  wire rst,
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_rx_activity,
    output wire led_tx_activity
);

    function integer clog2; input integer v; integer i; begin i=v-1; clog2=0; while(i>0) begin clog2=clog2+1; i=i>>1; end end endfunction
    localparam ADDR_W_FIFO1 = clog2(FIFO1_DEPTH);
    localparam ADDR_W_FIFO2 = clog2(FIFO2_DEPTH);

    // UART
    wire [7:0] rx_byte; wire rx_byte_valid;
    rx rx_inst (.clk(clk), .rst(rst), .rx(uart_rx), .rx_byte(rx_byte), .rx_byte_valid(rx_byte_valid));

    reg tx_start_reg; reg [7:0] tx_data_reg; wire tx_busy;
    tx #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(115200)) tx_inst (.clk(clk), .rst(rst), .tx(uart_tx), .tx_start(tx_start_reg), .tx_data(tx_data_reg), .tx_busy(tx_busy));

    // LED pulses
    localparam integer LED_PULSE_CYCLES = 500000;
    reg [22:0] rx_led_cnt, tx_led_cnt; reg led_rx_r, led_tx_r; reg tx_busy_prev;
    always @(posedge clk) begin if (rst) begin rx_led_cnt<=0; led_rx_r<=1'b0; end else if (rx_byte_valid) begin rx_led_cnt<=LED_PULSE_CYCLES; led_rx_r<=1'b1; end else if (rx_led_cnt!=0) begin rx_led_cnt<=rx_led_cnt-1; led_rx_r<=1'b1; end else led_rx_r<=1'b0; end
    always @(posedge clk) begin if (rst) begin tx_led_cnt<=0; led_tx_r<=1'b0; tx_busy_prev<=1'b0; end else begin if (tx_start_reg || (tx_busy && !tx_busy_prev)) tx_led_cnt<=LED_PULSE_CYCLES; else if (tx_led_cnt!=0) tx_led_cnt<=tx_led_cnt-1; led_tx_r<=(tx_led_cnt!=0); tx_busy_prev<=tx_busy; end end
    assign led_rx_activity = led_rx_r; assign led_tx_activity = led_tx_r;

    // FIFO1
    wire fifo1_wr_ready; wire fifo1_rd_valid; wire [7:0] fifo1_rd_data; wire fifo1_rd_ready_reg; wire [2:0] fifo1_load_bucket;
    bram_fifo #(.DEPTH(FIFO1_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO1)) fifo1 (.wr_clk(clk), .wr_rst(rst), .wr_valid(rx_byte_valid), .wr_ready(fifo1_wr_ready), .wr_data(rx_byte), .rd_clk(clk), .rd_rst(rst), .rd_valid(fifo1_rd_valid), .rd_ready(fifo1_rd_ready_reg), .rd_data(fifo1_rd_data), .wr_count_sync(), .rd_count_sync(), .load_bucket(fifo1_load_bucket));

    // Assembler1 -> Splitter (no resizer)
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel1; wire pixel1_valid; wire pixel1_ready;
    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler1 (.clk(clk), .rst(rst), .bram_rd_valid(fifo1_rd_valid), .bram_rd_ready(fifo1_rd_ready_reg), .bram_rd_data(fifo1_rd_data), .pixel_out(pixel1), .pixel_valid(pixel1_valid), .pixel_ready(pixel1_ready));
    assign pixel1_ready = 1'b1;

    wire splitter_wr_valid; wire [7:0] splitter_wr_data; wire splitter_wr_ready;
    pixel_splitter #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) splitter_inst (.clk(clk), .rst(rst), .pixel_in(pixel1), .pixel_in_valid(pixel1_valid), .pixel_in_ready(), .bram_wr_valid(splitter_wr_valid), .bram_wr_ready(splitter_wr_ready), .bram_wr_data(splitter_wr_data));

    // FIFO2 holds bytes for grayscale core
    wire fifo2_rd_valid; wire [7:0] fifo2_rd_data; wire fifo2_rd_ready_reg; wire [2:0] fifo2_load_bucket; wire fifo2_wr_ready;
    bram_fifo #(.DEPTH(FIFO2_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO2)) fifo2 (.wr_clk(clk), .wr_rst(rst), .wr_valid(splitter_wr_valid), .wr_ready(splitter_wr_ready), .wr_data(splitter_wr_data), .rd_clk(clk), .rd_rst(rst), .rd_valid(fifo2_rd_valid), .rd_ready(fifo2_rd_ready_reg), .rd_data(fifo2_rd_data), .wr_count_sync(), .rd_count_sync(), .load_bucket(fifo2_load_bucket));
    assign splitter_wr_ready = fifo2_wr_ready;

    // Assembler2 consumes bytes from FIFO2 and presents pixels to grayscale
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel2; wire pixel2_valid; wire pixel2_ready; reg asm2_rd_ready_reg;
    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler2 (.clk(clk), .rst(rst), .bram_rd_valid(fifo2_rd_valid), .bram_rd_ready(fifo2_rd_ready_reg), .bram_rd_data(fifo2_rd_data), .pixel_out(pixel2), .pixel_valid(pixel2_valid), .pixel_ready(pixel2_ready));
    assign pixel2_ready = 1'b1;

    // Grayscale core converts pixel2 -> gray byte and writes to FIFO3 (we'll reuse FIFO2 as FIFO3 here by streaming directly to TX for simplicity)
    wire gray_write; wire [7:0] gray_byte; wire gray_busy;
    grayscale_core #(.PIXEL_WIDTH(PIXEL_WIDTH)) gray_inst (.clk(clk), .rst(rst), .read_signal(pixel2_valid & pixel2_ready), .data_in(pixel2), .data_out(gray_byte), .write_signal(gray_write), .busy(gray_busy));

    // TX streaming: latch gray_byte when written, send over UART
    reg gray_latched_valid; reg [7:0] gray_latched;
    always @(posedge clk) begin
        if (rst) begin tx_start_reg<=1'b0; tx_data_reg<=8'h00; gray_latched_valid<=1'b0; gray_latched<=8'h00; end else begin
            tx_start_reg<=1'b0;
            if (pixel2_valid && pixel2_ready) begin gray_latched <= gray_byte; gray_latched_valid <= 1'b1; end
            if (gray_latched_valid && !tx_busy) begin tx_data_reg <= gray_latched; tx_start_reg<=1'b1; gray_latched_valid<=1'b0; end
        end
    end

endmodule
