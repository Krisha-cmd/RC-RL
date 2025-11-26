`timescale 1ns / 1ps
// top_simple.v
// Simple single-clock top: RX -> assembler1 -> resizer -> splitter -> FIFO2 -> assembler2 -> grayscale -> FIFO3 -> TX
// No RL agent, no logger. All modules operate in same clock domain with valid/ready handshakes.

module top_simple #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS    = 3,
    parameter integer IN_WIDTH    = 128,
    parameter integer IN_HEIGHT   = 128,
    parameter integer OUT_WIDTH   = IN_WIDTH / 2,
    parameter integer OUT_HEIGHT  = IN_HEIGHT / 2,
    parameter integer FIFO1_DEPTH = 4096,
    parameter integer FIFO2_DEPTH = 4096,
    parameter integer FIFO3_DEPTH = 4096
)(
    input  wire clk,
    input  wire rst,
    input  wire uart_rx,
    output wire uart_tx,

    // simple LEDs
    output wire led_rx_activity,
    output wire led_tx_activity
);

    // small compile-time clog2
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            clog2 = 0;
            while (v > 0) begin
                clog2 = clog2 + 1;
                v = v >> 1;
            end
        end
    endfunction

    localparam integer ADDR_W_FIFO1 = clog2(FIFO1_DEPTH);
    localparam integer ADDR_W_FIFO2 = clog2(FIFO2_DEPTH);
    localparam integer ADDR_W_FIFO3 = clog2(FIFO3_DEPTH);

    // ------------------------------------------------------------------
    // UART RX/ TX
    // ------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_byte_valid;

    rx rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid)
    );

    reg tx_start_reg;
    reg [7:0] tx_data_reg;
    wire tx_busy;

    tx #(
        .CLOCK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) tx_inst (
        .clk(clk),
        .rst(rst),
        .tx(uart_tx),
        .tx_start(tx_start_reg),
        .tx_data(tx_data_reg),
        .tx_busy(tx_busy)
    );

    // ------------------------------------------------------------------
    // LED pulse stretchers
    // ------------------------------------------------------------------
    localparam integer LED_PULSE_CYCLES = 500000; // ~5ms at 100MHz
    reg [22:0] rx_led_cnt;
    reg [22:0] tx_led_cnt;
    reg led_rx_r;
    reg led_tx_r;

    always @(posedge clk) begin
        if (rst) begin
            rx_led_cnt <= 0;
            led_rx_r <= 1'b0;
        end else begin
            if (rx_byte_valid)
                rx_led_cnt <= LED_PULSE_CYCLES;
            else if (rx_led_cnt != 0)
                rx_led_cnt <= rx_led_cnt - 1;
            led_rx_r <= (rx_led_cnt != 0);
        end
    end

    // capture tx activity (pulse on tx_start or rising tx_busy)
    reg tx_busy_prev;
    always @(posedge clk) begin
        if (rst) begin
            tx_led_cnt <= 0;
            led_tx_r <= 1'b0;
            tx_busy_prev <= 1'b0;
        end else begin
            if (tx_start_reg || (tx_busy && !tx_busy_prev))
                tx_led_cnt <= LED_PULSE_CYCLES;
            else if (tx_led_cnt != 0)
                tx_led_cnt <= tx_led_cnt - 1;
            led_tx_r <= (tx_led_cnt != 0);
            tx_busy_prev <= tx_busy;
        end
    end

    assign led_rx_activity = led_rx_r;
    assign led_tx_activity = led_tx_r;

    // ------------------------------------------------------------------
    // FIFO1: RX bytes -> assembler1
    // ------------------------------------------------------------------
    wire fifo1_wr_ready;
    wire fifo1_rd_valid;
    wire [7:0] fifo1_rd_data;
    wire [2:0] fifo1_load_bucket;
    wire fifo1_rd_ready;

    bram_fifo #(.DEPTH(FIFO1_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO1)) fifo1 (
        .wr_clk(clk),
        .wr_rst(rst),
        .wr_valid(rx_byte_valid),
        .wr_ready(fifo1_wr_ready),
        .wr_data(rx_byte),

        .rd_clk(clk),
        .rd_rst(rst),
        .rd_valid(fifo1_rd_valid),
        .rd_ready(fifo1_rd_ready),
        .rd_data(fifo1_rd_data),

        .wr_count_sync(), .rd_count_sync(),
        .load_bucket(fifo1_load_bucket)
    );

    // assembler1: bytes -> pixel
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel1;
    wire pixel1_valid;
    wire pixel1_ready;

    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler1 (
        .clk(clk),
        .rst(rst),
        .bram_rd_valid(fifo1_rd_valid),
        .bram_rd_ready(fifo1_rd_ready),
        .bram_rd_data(fifo1_rd_data),
        .pixel_out(pixel1),
        .pixel_valid(pixel1_valid),
        .pixel_ready(pixel1_ready)
    );

    assign pixel1_ready = 1'b1; // always ready

    // ------------------------------------------------------------------
    // Resizer (read when pixel available)
    // ------------------------------------------------------------------
    wire [CHANNELS*PIXEL_WIDTH-1:0] res_out_pixel;
    wire res_valid;
    wire res_frame_done;

    wire resizer_read_pulse = pixel1_valid & pixel1_ready;

    resizer_core #(
        .IN_WIDTH(IN_WIDTH),
        .IN_HEIGHT(IN_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .CHANNELS(CHANNELS)
    ) resizer_inst (
        .clk(clk),
        .rst(rst),
        .data_in(pixel1),
        .read_signal(resizer_read_pulse),
        .data_out(res_out_pixel),
        .write_signal(res_valid),
        .frame_done(res_frame_done),
        .state() // unused
    );

    // ------------------------------------------------------------------
    // Pixel Splitter -> FIFO2
    // ------------------------------------------------------------------
    wire splitter_wr_valid;
    wire [7:0] splitter_wr_data;
    wire splitter_wr_ready;

    pixel_splitter #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) splitter_inst (
        .clk(clk),
        .rst(rst),
        .pixel_in(res_out_pixel),
        .pixel_in_valid(res_valid),
        .pixel_in_ready(),
        .bram_wr_valid(splitter_wr_valid),
        .bram_wr_ready(splitter_wr_ready),
        .bram_wr_data(splitter_wr_data)
    );

    wire fifo2_wr_ready;
    wire fifo2_rd_valid;
    wire [7:0] fifo2_rd_data;
    wire [2:0] fifo2_load_bucket;
    wire fifo2_rd_ready;

    bram_fifo #(.DEPTH(FIFO2_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO2)) fifo2 (
        .wr_clk(clk),
        .wr_rst(rst),
        .wr_valid(splitter_wr_valid),
        .wr_ready(fifo2_wr_ready),
        .wr_data(splitter_wr_data),

        .rd_clk(clk),
        .rd_rst(rst),
        .rd_valid(fifo2_rd_valid),
        .rd_ready(fifo2_rd_ready),
        .rd_data(fifo2_rd_data),

        .wr_count_sync(), .rd_count_sync(),
        .load_bucket(fifo2_load_bucket)
    );

    assign splitter_wr_ready = fifo2_wr_ready;

    // assembler2: bytes -> pixel2
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel2;
    wire pixel2_valid;
    wire pixel2_ready;

    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler2 (
        .clk(clk),
        .rst(rst),
        .bram_rd_valid(fifo2_rd_valid),
        .bram_rd_ready(fifo2_rd_ready),
        .bram_rd_data(fifo2_rd_data),
        .pixel_out(pixel2),
        .pixel_valid(pixel2_valid),
        .pixel_ready(pixel2_ready)
    );

    assign pixel2_ready = 1'b1;

    // ------------------------------------------------------------------
    // Grayscale core
    // ------------------------------------------------------------------
    wire gray_read_pulse = pixel2_valid & pixel2_ready;
    wire [7:0] gray_byte;
    wire gray_valid;

    grayscale_core #(
        .IMG_WIDTH(OUT_WIDTH),
        .IMG_HEIGHT(OUT_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) grayscale_inst (
        .clk(clk),
        .rst(rst),
        .data_in(pixel2),
        .read_signal(gray_read_pulse),
        .data_out(gray_byte),
        .write_signal(gray_valid),
        .state() // unused
    );

    // ------------------------------------------------------------------
    // FIFO3: grayscale -> TX
    // ------------------------------------------------------------------
    wire fifo3_wr_ready;
    wire fifo3_rd_valid;
    wire [7:0] fifo3_rd_data;
    wire [2:0] fifo3_load_bucket;
    reg fifo3_rd_ready_reg;

    bram_fifo #(.DEPTH(FIFO3_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO3)) fifo3 (
        .wr_clk(clk),
        .wr_rst(rst),
        .wr_valid(gray_valid),
        .wr_ready(fifo3_wr_ready),
        .wr_data(gray_byte),

        .rd_clk(clk),
        .rd_rst(rst),
        .rd_valid(fifo3_rd_valid),
        .rd_ready(fifo3_rd_ready_reg),
        .rd_data(fifo3_rd_data),

        .wr_count_sync(), .rd_count_sync(),
        .load_bucket(fifo3_load_bucket)
    );

    // ------------------------------------------------------------------
    // Simple TX FSM: stream FIFO3 bytes, then send sentinel "/0/0"
    // ------------------------------------------------------------------
    localparam S_IDLE   = 2'd0;
    localparam S_STREAM = 2'd1;
    localparam S_MARK0  = 2'd2;
    localparam S_MARK1  = 2'd3;

    reg [1:0] state;
    reg [7:0] fifo_latched;
    reg fifo_latched_valid;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            tx_start_reg <= 1'b0;
            tx_data_reg <= 8'h00;
            fifo3_rd_ready_reg <= 1'b0;
            fifo_latched <= 8'h00;
            fifo_latched_valid <= 1'b0;
        end else begin
            // default
            tx_start_reg <= 1'b0;
            // drive rd_ready when FIFO has data and we don't have it latched
            fifo3_rd_ready_reg <= (fifo3_rd_valid && !fifo_latched_valid);

            case (state)
                S_IDLE: begin
                    if (fifo3_rd_valid) begin
                        state <= S_STREAM;
                    end
                end
                S_STREAM: begin
                    if (fifo3_rd_valid && !fifo_latched_valid) begin
                        fifo_latched <= fifo3_rd_data;
                        fifo_latched_valid <= 1'b1;
                    end
                    if (fifo_latched_valid && !tx_busy) begin
                        tx_data_reg <= fifo_latched;
                        tx_start_reg <= 1'b1;
                        fifo_latched_valid <= 1'b0;
                    end
                    if (!fifo3_rd_valid && !fifo_latched_valid) begin
                        state <= S_MARK0;
                    end
                end
                S_MARK0: if (!tx_busy) begin tx_data_reg <= 8'h2F; tx_start_reg <= 1'b1; state <= S_MARK1; end
                S_MARK1: if (!tx_busy) begin tx_data_reg <= 8'h30; tx_start_reg <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
