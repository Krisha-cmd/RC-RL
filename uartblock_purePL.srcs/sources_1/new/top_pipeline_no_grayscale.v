`timescale 1ns / 1ps





module top_pipeline_no_grayscale #(
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
    output wire led_tx_activity,
    output wire led_resizer_busy,
    output wire led_gray_busy
);

    function integer clog2; input integer v; integer i; begin i=v-1; clog2=0; while(i>0) begin clog2=clog2+1; i=i>>1; end end endfunction
    localparam ADDR_W_FIFO1 = clog2(FIFO1_DEPTH);
    localparam ADDR_W_FIFO2 = clog2(FIFO2_DEPTH);

    
    wire [7:0] rx_byte; wire rx_byte_valid;
    rx rx_inst (.clk(clk), .rst(rst), .rx(uart_rx), .rx_byte(rx_byte), .rx_byte_valid(rx_byte_valid));

    reg tx_start_reg; reg [7:0] tx_data_reg; wire tx_busy;
    tx #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(115200)) tx_inst (.clk(clk), .rst(rst), .tx(uart_tx), .tx_start(tx_start_reg), .tx_data(tx_data_reg), .tx_busy(tx_busy));

    
    localparam integer LED_PULSE_CYCLES = 500000;
    reg [22:0] rx_led_cnt, tx_led_cnt, resizer_led_cnt, gray_led_cnt;
    reg led_rx_r, led_tx_r, led_resizer_r, led_gray_r; reg tx_busy_prev;
    always @(posedge clk) begin if (rst) begin rx_led_cnt<=0; led_rx_r<=1'b0; end else if (rx_byte_valid) begin rx_led_cnt<=LED_PULSE_CYCLES; led_rx_r<=1'b1; end else if (rx_led_cnt!=0) begin rx_led_cnt<=rx_led_cnt-1; led_rx_r<=1'b1; end else led_rx_r<=1'b0; end
    always @(posedge clk) begin if (rst) begin tx_led_cnt<=0; led_tx_r<=1'b0; tx_busy_prev<=1'b0; end else begin if (tx_start_reg || (tx_busy && !tx_busy_prev)) tx_led_cnt<=LED_PULSE_CYCLES; else if (tx_led_cnt!=0) tx_led_cnt<=tx_led_cnt-1; led_tx_r<=(tx_led_cnt!=0); tx_busy_prev<=tx_busy; end end
    assign led_rx_activity = led_rx_r; assign led_tx_activity = led_tx_r;

    
    wire fifo1_wr_ready; wire fifo1_rd_valid; wire [7:0] fifo1_rd_data; wire [2:0] fifo1_load_bucket; wire fifo1_rd_ready;
    bram_fifo #(.DEPTH(FIFO1_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO1)) fifo1 (.wr_clk(clk), .wr_rst(rst), .wr_valid(rx_byte_valid), .wr_ready(fifo1_wr_ready), .wr_data(rx_byte), .rd_clk(clk), .rd_rst(rst), .rd_valid(fifo1_rd_valid), .rd_ready(fifo1_rd_ready), .rd_data(fifo1_rd_data), .wr_count_sync(), .rd_count_sync(), .load_bucket(fifo1_load_bucket));

    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel1; wire pixel1_valid; wire pixel1_ready;
    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler1 (.clk(clk), .rst(rst), .bram_rd_valid(fifo1_rd_valid), .bram_rd_ready(fifo1_rd_ready), .bram_rd_data(fifo1_rd_data), .pixel_out(pixel1), .pixel_valid(pixel1_valid), .pixel_ready(pixel1_ready));
    assign pixel1_ready = 1'b1;

    
    wire [CHANNELS*PIXEL_WIDTH-1:0] res_out_pixel; wire res_valid; wire res_frame_done; wire resizer_state;
    wire resizer_read;
    assign resizer_read = pixel1_valid & pixel1_ready;
    resizer_core #(.IN_WIDTH(IN_WIDTH), .IN_HEIGHT(IN_HEIGHT), .OUT_WIDTH(IN_WIDTH/2), .OUT_HEIGHT(IN_HEIGHT/2), .PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) resizer_inst (.clk(clk), .rst(rst), .data_in(pixel1), .read_signal(resizer_read), .data_out(res_out_pixel), .write_signal(res_valid), .frame_done(res_frame_done), .state(resizer_state));
    always @(posedge clk) begin if (rst) begin resizer_led_cnt<=0; led_resizer_r<=1'b0; end else if (resizer_state) resizer_led_cnt<=LED_PULSE_CYCLES; else if (resizer_led_cnt!=0) resizer_led_cnt<=resizer_led_cnt-1; led_resizer_r <= (resizer_led_cnt!=0); end
    assign led_resizer_busy = led_resizer_r; assign led_gray_busy = 1'b0;

    
    wire splitter_wr_valid;
    wire [7:0] splitter_wr_data;
    wire splitter_wr_ready;
    wire fifo2_rd_valid;
    wire [7:0] fifo2_rd_data;
    wire fifo2_rd_ready;
    wire fifo2_wr_ready;
    wire [2:0] fifo2_load_bucket;
    
    pixel_splitter #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .CHANNELS(CHANNELS)
    ) splitter_inst (
        .clk(clk),
        .rst(rst),
        .pixel_in(res_out_pixel),
        .pixel_in_valid(res_valid),
        .pixel_in_ready(),
        .bram_wr_valid(splitter_wr_valid),
        .bram_wr_ready(splitter_wr_ready),
        .bram_wr_data(splitter_wr_data)
    );
    
    bram_fifo #(
        .DEPTH(FIFO2_DEPTH),
        .ADDR_WIDTH(ADDR_W_FIFO2)
    ) fifo2 (
        .wr_clk(clk),
        .wr_rst(rst),
        .wr_valid(splitter_wr_valid),
        .wr_ready(splitter_wr_ready),
        .wr_data(splitter_wr_data),
        .rd_clk(clk),
        .rd_rst(rst),
        .rd_valid(fifo2_rd_valid),
        .rd_ready(fifo2_rd_ready),
        .rd_data(fifo2_rd_data),
        .wr_count_sync(),
        .rd_count_sync(),
        .load_bucket(fifo2_load_bucket)
    );
    
    assign splitter_wr_ready = fifo2_wr_ready;

    
    reg [7:0] tx_byte_latch;
    reg tx_byte_valid;
    reg tx_state;
    
    always @(posedge clk) begin
        if (rst) begin
            tx_start_reg <= 1'b0;
            tx_data_reg <= 8'h00;
            tx_byte_latch <= 8'h00;
            tx_byte_valid <= 1'b0;
            tx_state <= 1'b0;
        end else begin
            tx_start_reg <= 1'b0;
            
            case (tx_state)
                1'b0: begin
                    
                    if (fifo2_rd_valid) begin
                        tx_byte_latch <= fifo2_rd_data;
                        tx_byte_valid <= 1'b1;
                        tx_state <= 1'b1;
                    end
                end
                1'b1: begin
                    
                    if (!tx_busy && tx_byte_valid) begin
                        tx_data_reg <= tx_byte_latch;
                        tx_start_reg <= 1'b1;
                        tx_byte_valid <= 1'b0;
                        tx_state <= 1'b0;
                    end
                end
            endcase
        end
    end
    
    
    assign fifo2_rd_ready = (tx_state == 1'b0) && fifo2_rd_valid;

endmodule