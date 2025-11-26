`timescale 1ns / 1ps
// top_pipeline.v
// Simple single-clock top that connects: RX -> assembler -> resizer -> splitter -> assembler -> grayscale -> TX
// Uses BRAM FIFOs between stages, CE pulses from clock_module_simple (RL agent compatible),
// and a logger that periodically records FIFO loads and core states and can be transmitted after the image.

module top_pipeline #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS    = 3,
    parameter integer IN_WIDTH    = 128,
    parameter integer IN_HEIGHT   = 128,
    parameter integer FIFO1_DEPTH = 4096,
    parameter integer FIFO2_DEPTH = 4096,
    parameter integer FIFO3_DEPTH = 4096,
    parameter integer LOGGER_INTERVAL = 50,
    parameter integer LOGGER_DEPTH = 1024
)(
    input  wire clk,
    input  wire rst,          // active-high
    input  wire uart_rx,
    output wire uart_tx,

    // LEDs for basic visibility
    output wire led_rx_activity,
    output wire led_tx_activity,
    output wire led_resizer_busy,
    output wire led_gray_busy
);

    // local utility
    function integer clog2; input integer v; integer i; begin i=v-1; clog2=0; while(i>0) begin clog2=clog2+1; i=i>>1; end end endfunction

    localparam ADDR_W_FIFO1 = clog2(FIFO1_DEPTH);
    localparam ADDR_W_FIFO2 = clog2(FIFO2_DEPTH);
    localparam ADDR_W_FIFO3 = clog2(FIFO3_DEPTH);

    // --------------------------------------------------
    // UART RX / TX
    // --------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_byte_valid;

    rx rx_inst (
        .clk(clk), .rst(rst), .rx(uart_rx), .rx_byte(rx_byte), .rx_byte_valid(rx_byte_valid)
    );

    reg tx_start_reg;
    reg [7:0] tx_data_reg;
    wire tx_busy;

    tx #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(115200)) tx_inst (
        .clk(clk), .rst(rst), .tx(uart_tx), .tx_start(tx_start_reg), .tx_data(tx_data_reg), .tx_busy(tx_busy)
    );

    // LED pulse stretchers (simple)
    localparam integer LED_PULSE_CYCLES = 500000; // ~5ms
    reg [22:0] rx_led_cnt, tx_led_cnt, resizer_led_cnt, gray_led_cnt;
    reg led_rx_r, led_tx_r, led_resizer_r, led_gray_r;

    // update RX LED
    always @(posedge clk) begin
        if (rst) begin rx_led_cnt <= 0; led_rx_r <= 1'b0; end
        else if (rx_byte_valid) begin rx_led_cnt <= LED_PULSE_CYCLES; led_rx_r <= 1'b1; end
        else if (rx_led_cnt != 0) begin rx_led_cnt <= rx_led_cnt - 1; led_rx_r <= 1'b1; end
        else led_rx_r <= 1'b0;
    end

    // update TX LED (use tx_start or tx_busy edge)
    reg tx_busy_prev;
    always @(posedge clk) begin
        if (rst) begin tx_led_cnt<=0; led_tx_r<=1'b0; tx_busy_prev<=1'b0; end
        else begin
            if (tx_start_reg || (tx_busy && !tx_busy_prev)) tx_led_cnt <= LED_PULSE_CYCLES;
            else if (tx_led_cnt != 0) tx_led_cnt <= tx_led_cnt - 1;
            led_tx_r <= (tx_led_cnt != 0);
            tx_busy_prev <= tx_busy;
        end
    end

    assign led_rx_activity = led_rx_r;
    assign led_tx_activity = led_tx_r;

    // --------------------------------------------------
    // FIFO1: RX bytes -> assembler1
    // --------------------------------------------------
    wire fifo1_wr_ready;
    wire fifo1_rd_valid;
    wire [7:0] fifo1_rd_data;
    wire [2:0] fifo1_load_bucket;
    wire  fifo1_rd_ready_reg;

    bram_fifo #(.DEPTH(FIFO1_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO1)) fifo1 (
        .wr_clk(clk), .wr_rst(rst), .wr_valid(rx_byte_valid), .wr_ready(fifo1_wr_ready), .wr_data(rx_byte),
        .rd_clk(clk), .rd_rst(rst), .rd_valid(fifo1_rd_valid), .rd_ready(fifo1_rd_ready_reg), .rd_data(fifo1_rd_data),
        .wr_count_sync(), .rd_count_sync(), .load_bucket(fifo1_load_bucket)
    );

    // assembler1: bytes -> pixel1
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel1;
    wire pixel1_valid;
    wire pixel1_ready;

    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler1 (
        .clk(clk), .rst(rst), .bram_rd_valid(fifo1_rd_valid), .bram_rd_ready(fifo1_rd_ready_reg), .bram_rd_data(fifo1_rd_data),
        .pixel_out(pixel1), .pixel_valid(pixel1_valid), .pixel_ready(pixel1_ready)
    );

    assign pixel1_ready = 1'b1;

    // --------------------------------------------------
    // RL agent + clock module to generate CE pulses
    // --------------------------------------------------
    wire rl_valid;
    wire [1:0] rl_core_mask;
    wire [7:0] rl_freq_code;
    wire ce_resizer, ce_grayscale;
    wire [7:0] divider_resizer, divider_grayscale;

    rl_agent_simple #(.INTERVAL(2000000)) rl_agent_inst (.clk(clk), .rst(rst), .rl_valid(rl_valid), .core_mask(rl_core_mask), .freq_code(rl_freq_code));
    clock_module_simple clock_module_inst (.clk(clk), .rst(rst), .rl_valid(rl_valid), .core_mask(rl_core_mask), .freq_code(rl_freq_code), .ce_resizer(ce_resizer), .ce_grayscale(ce_grayscale), .divider_resizer(divider_resizer), .divider_grayscale(divider_grayscale));

    // --------------------------------------------------
    // Resizer: read when pixel1_valid & ce_resizer
    // --------------------------------------------------
    wire [CHANNELS*PIXEL_WIDTH-1:0] res_out_pixel;
    wire res_valid;
    wire res_frame_done;
    wire resizer_state;

    wire resizer_read = pixel1_valid & pixel1_ready & ce_resizer;

    resizer_core #(.IN_WIDTH(IN_WIDTH), .IN_HEIGHT(IN_HEIGHT), .OUT_WIDTH(IN_WIDTH/2), .OUT_HEIGHT(IN_HEIGHT/2), .PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) resizer_inst (
        .clk(clk), .rst(rst), .data_in(pixel1), .read_signal(resizer_read), .data_out(res_out_pixel), .write_signal(res_valid), .frame_done(res_frame_done), .state(resizer_state)
    );

    // resizer LED
    always @(posedge clk) begin
        if (rst) begin resizer_led_cnt<=0; led_resizer_r<=1'b0; end
        else if (resizer_state) resizer_led_cnt<=LED_PULSE_CYCLES;
        else if (resizer_led_cnt!=0) resizer_led_cnt<=resizer_led_cnt-1;
        led_resizer_r <= (resizer_led_cnt!=0);
    end
    assign led_resizer_busy = led_resizer_r;

    // --------------------------------------------------
    // Splitter -> FIFO2
    // --------------------------------------------------
    wire splitter_wr_valid;
    wire [7:0] splitter_wr_data;
    wire splitter_wr_ready;

    pixel_splitter #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) splitter_inst (
        .clk(clk), .rst(rst), .pixel_in(res_out_pixel), .pixel_in_valid(res_valid), .pixel_in_ready(), .bram_wr_valid(splitter_wr_valid), .bram_wr_ready(splitter_wr_ready), .bram_wr_data(splitter_wr_data)
    );

    wire fifo2_rd_valid;
    wire [7:0] fifo2_rd_data;
    wire fifo2_rd_ready_reg;
    wire fifo2_wr_ready;
    wire [2:0] fifo2_load_bucket;

    bram_fifo #(.DEPTH(FIFO2_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO2)) fifo2 (
        .wr_clk(clk), .wr_rst(rst), .wr_valid(splitter_wr_valid), .wr_ready(splitter_wr_ready), .wr_data(splitter_wr_data),
        .rd_clk(clk), .rd_rst(rst), .rd_valid(fifo2_rd_valid), .rd_ready(fifo2_rd_ready_reg), .rd_data(fifo2_rd_data),
        .wr_count_sync(), .rd_count_sync(), .load_bucket(fifo2_load_bucket)
    );

    assign splitter_wr_ready = fifo2_wr_ready;

    // assembler2: bytes -> pixel2
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel2;
    wire pixel2_valid;
    wire pixel2_ready;

    pixel_assembler #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) assembler2 (
        .clk(clk), .rst(rst), .bram_rd_valid(fifo2_rd_valid), .bram_rd_ready(fifo2_rd_ready_reg), .bram_rd_data(fifo2_rd_data), .pixel_out(pixel2), .pixel_valid(pixel2_valid), .pixel_ready(pixel2_ready)
    );
    assign pixel2_ready = 1'b1;

    // --------------------------------------------------
    // Grayscale: read when pixel2_valid & ce_grayscale
    // --------------------------------------------------
    wire [7:0] gray_byte;
    wire       gray_valid;
    wire       gray_state_wire;

    wire gray_read = pixel2_valid & pixel2_ready & ce_grayscale;

    grayscale_core #(.IMG_WIDTH(IN_WIDTH/2), .IMG_HEIGHT(IN_HEIGHT/2), .PIXEL_WIDTH(PIXEL_WIDTH)) grayscale_inst (
        .clk(clk), .rst(rst), .data_in(pixel2), .read_signal(gray_read), .data_out(gray_byte), .write_signal(gray_valid), .state(gray_state_wire)
    );

    // grayscale LED
    always @(posedge clk) begin
        if (rst) begin gray_led_cnt<=0; led_gray_r<=1'b0; end
        else if (gray_state_wire) gray_led_cnt<=LED_PULSE_CYCLES;
        else if (gray_led_cnt!=0) gray_led_cnt<=gray_led_cnt-1;
        led_gray_r <= (gray_led_cnt!=0);
    end
    assign led_gray_busy = led_gray_r;

    // --------------------------------------------------
    // FIFO3: gray -> TX
    // --------------------------------------------------
    wire fifo3_wr_ready;
    wire fifo3_rd_valid;
    wire [7:0] fifo3_rd_data;
    wire [2:0] fifo3_load_bucket;
    reg fifo3_rd_ready_reg;

    bram_fifo #(.DEPTH(FIFO3_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO3)) fifo3 (
        .wr_clk(clk), .wr_rst(rst), .wr_valid(gray_valid), .wr_ready(fifo3_wr_ready), .wr_data(gray_byte),
        .rd_clk(clk), .rd_rst(rst), .rd_valid(fifo3_rd_valid), .rd_ready(fifo3_rd_ready_reg), .rd_data(fifo3_rd_data),
        .wr_count_sync(), .rd_count_sync(), .load_bucket(fifo3_load_bucket)
    );

    // --------------------------------------------------
    // Logger: periodically sample FIFO loads and core states
    // --------------------------------------------------
    wire logger_rd_valid;
    wire [15:0] logger_rd_data;
    wire logger_rd_done;
    reg logger_start = 1'b1; // logging enabled by default
    reg logger_stop = 1'b0;
    reg logger_rd_en_reg;

    logger_simple #(.INTERVAL_CYCLES(LOGGER_INTERVAL), .ENTRY_WIDTH(16), .LOGGER_DEPTH(LOGGER_DEPTH)) logger_inst (
        .clk(clk), .rst(rst), .fifo1_load_bucket(fifo1_load_bucket), .fifo2_load_bucket(fifo2_load_bucket), .resizer_state(resizer_state), .gray_state(gray_state_wire), .divider_resizer(divider_resizer), .divider_grayscale(divider_grayscale), .start_logging(logger_start), .stop_logging(logger_stop), .rd_en(logger_rd_en_reg), .rd_valid(logger_rd_valid), .rd_data(logger_rd_data), .rd_done(logger_rd_done)
    );

    // --------------------------------------------------
    // TX FSM: stream FIFO3, then send marker and then logger contents
    // --------------------------------------------------
    localparam T_IDLE = 3'd0, T_STREAM = 3'd1, T_MARK = 3'd2, T_LOG = 3'd3;
    reg [2:0] tstate;
    reg [7:0] fifo3_latched; reg fifo3_latched_valid;
    reg [15:0] logger_latched; reg logger_latched_valid;
    // self-test via UART: send "TEST\n" when host sends 'T'
    reg selftest_req;
    reg [2:0] self_idx;

    always @(posedge clk) begin
        if (rst) begin
            tstate <= T_IDLE;
            tx_start_reg <= 1'b0;
            tx_data_reg <= 8'h00;
            fifo3_rd_ready_reg <= 1'b0;
            fifo3_latched <= 8'h00;
            fifo3_latched_valid <= 1'b0;
            logger_rd_en_reg <= 1'b0;
            logger_latched_valid <= 1'b0;
            selftest_req <= 1'b0;
            self_idx <= 3'd0;
        end else begin
            tx_start_reg <= 1'b0;
            // assert FIFO3 read-ready when data present and we don't have latched byte
            fifo3_rd_ready_reg <= (fifo3_rd_valid && !fifo3_latched_valid);

            // capture self-test request from RX (press 'T' to trigger)
            if (rx_byte_valid && rx_byte == 8'h54) begin
                selftest_req <= 1'b1;
            end

            // If self-test requested, take priority and send "TEST\n"
            if (selftest_req) begin
                if (!tx_busy) begin
                    case (self_idx)
                        3'd0: begin tx_data_reg <= 8'h54; tx_start_reg <= 1'b1; self_idx <= 3'd1; end // 'T'
                        3'd1: begin tx_data_reg <= 8'h45; tx_start_reg <= 1'b1; self_idx <= 3'd2; end // 'E'
                        3'd2: begin tx_data_reg <= 8'h53; tx_start_reg <= 1'b1; self_idx <= 3'd3; end // 'S'
                        3'd3: begin tx_data_reg <= 8'h54; tx_start_reg <= 1'b1; self_idx <= 3'd4; end // 'T'
                        3'd4: begin tx_data_reg <= 8'h0A; tx_start_reg <= 1'b1; self_idx <= 3'd0; selftest_req <= 1'b0; end // '\n'
                        default: begin selftest_req <= 1'b0; end
                    endcase
                end
            end else begin

            case (tstate)
                T_IDLE: begin
                    if (fifo3_rd_valid) tstate <= T_STREAM;
                end
                T_STREAM: begin
                    if (fifo3_rd_valid && !fifo3_latched_valid) begin
                        fifo3_latched <= fifo3_rd_data; fifo3_latched_valid <= 1'b1;
                    end
                    if (fifo3_latched_valid && !tx_busy) begin
                        tx_data_reg <= fifo3_latched; tx_start_reg <= 1'b1; fifo3_latched_valid <= 1'b0;
                    end
                    if (!fifo3_rd_valid && !fifo3_latched_valid) begin
                        tstate <= T_MARK;
                    end
                end
                T_MARK: begin
                    // send a short marker "/L" then move to logger send
                    if (!tx_busy) begin tx_data_reg <= 8'h2F; tx_start_reg <= 1'b1; tstate <= T_LOG; end
                end
                T_LOG: begin
                    // if logger empty, finish
                    if (logger_rd_done && !logger_latched_valid) begin
                        tstate <= T_IDLE;
                    end else begin
                        // request next logger word if none latched
                        if (!logger_latched_valid && !logger_rd_en_reg && !logger_rd_done) begin
                            logger_rd_en_reg <= 1'b1;
                        end
                        // capture logger read (logger presents rd_valid same cycle as rd_en)
                        if (logger_rd_valid) begin
                            logger_latched <= logger_rd_data; logger_latched_valid <= 1'b1; logger_rd_en_reg <= 1'b0;
                        end
                        // send lower byte first when available
                        if (logger_latched_valid && !tx_busy) begin
                            tx_data_reg <= logger_latched[7:0]; tx_start_reg <= 1'b1; logger_latched <= {8'h00, logger_latched[15:8]}; logger_latched_valid <= 1'b0;
                        end
                    end
                end
                default: tstate <= T_IDLE;
            endcase
        end
    end
end
endmodule
