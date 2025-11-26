`timescale 1ns / 1ps
// top_processing_2001.v
// Verilog-2001 compatible single-clock top for ZedBoard (Y9).
// - all domains use one clock (clk)
// - reset is active HIGH (rst)
// - RL agent + clock_module included as small submodules
// - logger included
// NOTE: Map the physical 100MHz oscillator to 'clk' in XDC.

module top_processing #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS    = 3,
    parameter integer IN_WIDTH    = 128,
    parameter integer IN_HEIGHT   = 128,
    parameter integer IN_PIXELS   = IN_WIDTH * IN_HEIGHT,
    parameter integer IN_BYTES    = IN_PIXELS * CHANNELS,
    parameter integer OUT_WIDTH   = IN_WIDTH / 2,
    parameter integer OUT_HEIGHT  = IN_HEIGHT / 2,
//    parameter integer OUT_PIXELS  = OUT_WIDTH * OUT_HEIGHT,
//    parameter integer OUT_BYTES   = OUT_PIXELS * CHANNELS,
    // FIFO depths (power of two recommended)
    parameter integer FIFO1_DEPTH = 4096,
    parameter integer FIFO2_DEPTH = 4096,
    parameter integer FIFO3_DEPTH = 4096,
    // logger
    parameter integer LOGGER_INTERVAL = 20,
    parameter integer LOGGER_DEPTH    = 4096,
    // If set to 1, logger records continuously (useful for debugging)
    parameter integer LOG_ALWAYS      = 1
)(
    input  wire clk,          // map this to Y9 on ZedBoard (100MHz)
    input  wire rst,          
    input  wire uart_rx,
    output wire uart_tx,

    // debugging outputs you can map to LEDs
    output wire led_rx_activity,
    output wire led_tx_activity,
    output wire led_resizer_busy,
    output wire led_gray_busy
);

    // ------------------------------------------------------------------------
    // small utility: compile-time clog2 (Verilog-2001 style)
    // ------------------------------------------------------------------------
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

    // compute address widths using clog2
    localparam integer ADDR_W_FIFO1 = clog2(FIFO1_DEPTH);
    localparam integer ADDR_W_FIFO2 = clog2(FIFO2_DEPTH);
    localparam integer ADDR_W_FIFO3 = clog2(FIFO3_DEPTH);

    // ------------------------------------------------------------------------
    // UART rx/tx (single clock domain)
    // ------------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_byte_valid;

    rx rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid)
    );

    // TX instance (exposes tx_busy)
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

    // LEDs reflect current activity/state
    // LED pulse stretchers so short pulses are visible on LEDs
    localparam integer LED_PULSE_CYCLES = 500000; // ~5ms at 100MHz
    reg [22:0] rx_led_cnt;
    reg [22:0] tx_led_cnt;
    reg led_rx_r;
    reg led_tx_r;
    reg tx_busy_prev;
    reg [22:0] resizer_led_cnt;
    reg [22:0] gray_led_cnt;
    reg led_resizer_r;
    reg led_gray_r;

    // stretch RX pulse
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

    // stretch TX activity: trigger on tx_start pulse or rising edge of tx_busy
    always @(posedge clk) begin
        if (rst) begin
            tx_led_cnt <= 0;
            led_tx_r <= 1'b0;
            tx_busy_prev <= 1'b0;
        end else begin
            // force LED off when FSM idle and transmitter idle
            if ((tx_state == S_IDLE) && (!tx_busy)) begin
                tx_led_cnt <= 0;
                led_tx_r <= 1'b0;
                tx_busy_prev <= tx_busy;
            end else begin
                // detect rising edge of tx_busy or any tx_start pulse
                if (tx_start_reg || (tx_busy && !tx_busy_prev)) begin
                    tx_led_cnt <= LED_PULSE_CYCLES;
                end else if (tx_led_cnt != 0) begin
                    tx_led_cnt <= tx_led_cnt - 1;
                end
                led_tx_r <= (tx_led_cnt != 0);
                tx_busy_prev <= tx_busy;
            end
        end
    end

    assign led_rx_activity = led_rx_r;
    assign led_tx_activity = led_tx_r;
        // stretch resizer and grayscale 'state' signals for visibility
        always @(posedge clk) begin
            if (rst) begin
                resizer_led_cnt <= 0;
                gray_led_cnt <= 0;
                led_resizer_r <= 1'b0;
                led_gray_r <= 1'b0;
            end else begin
                if (resizer_state)
                    resizer_led_cnt <= LED_PULSE_CYCLES;
                else if (resizer_led_cnt != 0)
                    resizer_led_cnt <= resizer_led_cnt - 1;
                // show only stretched activity (avoid direct CE/state OR to prevent
                // blinking when CE pulses without actual work)
                led_resizer_r <= (resizer_led_cnt != 0);

                if (gray_state_wire) // grayscale core state
                    gray_led_cnt <= LED_PULSE_CYCLES;
                else if (gray_led_cnt != 0)
                    gray_led_cnt <= gray_led_cnt - 1;
                led_gray_r <= (gray_led_cnt != 0);
            end
        end

        assign led_resizer_busy = led_resizer_r;
        assign led_gray_busy = led_gray_r;

    // ------------------------------------------------------------------------
    // FIFO1: RX bytes -> assembler1 (single-clock BRAM FIFO)
    // ------------------------------------------------------------------------
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
        .rd_ready(fifo1_rd_ready),                // connected to assembler1 below via fifo1_rd_ready
        .rd_data(fifo1_rd_data),

        .wr_count_sync(), .rd_count_sync(),
        .load_bucket(fifo1_load_bucket)
    );

    // ------------------------------------------------------------------------
    // assembler1 (bytes -> PIXEL) (single-clock)
    // ------------------------------------------------------------------------
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

    // No RL/clock gating; simple valid-driven flow

    // ------------------------------------------------------------------------
    // Resizer (single clock) – read when input pixel is valid
    // ------------------------------------------------------------------------
    wire [CHANNELS*PIXEL_WIDTH-1:0] res_out_pixel;
    wire                            res_valid;
    wire                            res_frame_done;
    wire                            resizer_state;
    wire                            gray_state_wire;

    // RL / clock wires (allow RL agent to change core pacing)
    wire rl_valid;
    wire [1:0] rl_core_mask;
    wire [7:0] rl_freq_code;
    wire ce_resizer;
    wire ce_grayscale;
    wire [7:0] divider_resizer_wire;
    wire [7:0] divider_grayscale_wire;

    // assembler1 always ready
    assign pixel1_ready = 1'b1;

    // read pulse when pixel available and when resizer CE allows it
    wire resizer_read_pulse = pixel1_valid & pixel1_ready & ce_resizer;

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
        .state(resizer_state)
    );

    // (led_resizer_busy driven below from stretcher)

    // ------------------------------------------------------------------------
    // Pixel Splitter -> FIFO2 (single-clock)
    // ------------------------------------------------------------------------
    wire splitter_wr_valid;
    wire [7:0] splitter_wr_data;
    wire splitter_wr_ready;

    pixel_splitter #(.PIXEL_WIDTH(PIXEL_WIDTH), .CHANNELS(CHANNELS)) splitter_inst (
        .clk(clk),
        .rst(rst),
        .pixel_in(res_out_pixel),
        .pixel_in_valid(res_valid),
        .pixel_in_ready(),    // not used
        .bram_wr_valid(splitter_wr_valid),
        .bram_wr_ready(splitter_wr_ready),
        .bram_wr_data(splitter_wr_data)
    );

    // FIFO2: resized RGB bytes buffer (single-clock)
    wire fifo2_wr_ready;
    wire fifo2_rd_valid;
    wire [7:0] fifo2_rd_data;
    wire [2:0] fifo2_load_bucket;
    wire pixel2_ready;
    bram_fifo #(.DEPTH(FIFO2_DEPTH), .ADDR_WIDTH(ADDR_W_FIFO2)) fifo2 (
        .wr_clk(clk),
        .wr_rst(rst),
        .wr_valid(splitter_wr_valid),
        .wr_ready(fifo2_wr_ready),
        .wr_data(splitter_wr_data),

        .rd_clk(clk),
        .rd_rst(rst),
        .rd_valid(fifo2_rd_valid),
        .rd_ready(pixel2_ready),                // assembler2 will provide ready
        .rd_data(fifo2_rd_data),

        .wr_count_sync(), .rd_count_sync(),
        .load_bucket(fifo2_load_bucket)
    );

    assign splitter_wr_ready = fifo2_wr_ready;

    // ------------------------------------------------------------------------
    // Assembler2 (single-clock) -> grayscale core
    // ------------------------------------------------------------------------
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel2;
    wire pixel2_valid;

    wire fifo2_rd_ready;

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

    // assembler2 always ready
    assign pixel2_ready = 1'b1;

    // ------------------------------------------------------------------------
    // Grayscale – read when input pixel is valid
    // ------------------------------------------------------------------------
    // only read grayscale when both pixel available and CE pulse asserted
    wire gray_read_pulse = pixel2_valid & pixel2_ready & ce_grayscale;

    // grayscale outputs
    wire [7:0] gray_byte;
    wire       gray_valid;

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
        .state(gray_state_wire)
    );


    // ------------------------------------------------------------------------
    // FIFO3: grayscale bytes -> TX (single-clock)
    // ------------------------------------------------------------------------
    wire fifo3_wr_ready;
    wire fifo3_rd_valid;
    wire [7:0] fifo3_rd_data;
    wire [2:0] fifo3_load_bucket;
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

    // ------------------------------------------------------------------------
    // (Logger removed in this build — focusing on image forward path and TX)
    // ------------------------------------------------------------------------

    // Instantiate RL agent and clock module so RL can change dividers at runtime.
    rl_agent_simple #(.INTERVAL(2000000)) rl_agent_inst (
        .clk(clk),
        .rst(rst),
        .rl_valid(rl_valid),
        .core_mask(rl_core_mask),
        .freq_code(rl_freq_code)
    );

    clock_module_simple clock_module_inst (
        .clk(clk),
        .rst(rst),
        .rl_valid(rl_valid),
        .core_mask(rl_core_mask),
        .freq_code(rl_freq_code),
        .ce_resizer(ce_resizer),
        .ce_grayscale(ce_grayscale),
        .divider_resizer(divider_resizer_wire),
        .divider_grayscale(divider_grayscale_wire)
    );

    // ------------------------------------------------------------------------
    // TX FSM (single-clock). Consumes fifo3_rd_valid and sends bytes via tx_inst.
    // After streaming image bytes it sends marker "/0/0" then flushes logger contents
    // (logger_inst read) and then sends trailing marker.
    // ------------------------------------------------------------------------

    // FSM state encodings
    localparam S_IDLE     = 4'd0;
    localparam S_STREAM   = 4'd1;

    localparam S_MARK1_0  = 4'd2;
    localparam S_MARK1_1  = 4'd3;
    localparam S_MARK1_2  = 4'd4;
    localparam S_MARK1_3  = 4'd5;

    // (logger states removed)

    localparam S_MARK2_0  = 4'd10;
    localparam S_MARK2_1  = 4'd11;
    localparam S_MARK2_2  = 4'd12;
    localparam S_MARK2_3  = 4'd13;
    // self-test transmit state
    localparam S_SELF = 4'd14;

    reg [3:0] tx_state;
    reg fifo3_rd_ready_reg;
    reg [7:0] fifo3_latched;
    reg fifo3_latched_valid;
    // self-test request and index
    reg selftest_req;
    reg [2:0] self_idx;

    // TX FSM sequential logic
    always @(posedge clk) begin
        if (rst) begin
            tx_state <= S_IDLE;
            tx_start_reg <= 1'b0;
            tx_data_reg <= 8'h00;
            fifo3_rd_ready_reg <= 1'b0;
            fifo3_latched <= 8'h00;
            fifo3_latched_valid <= 1'b0;
            selftest_req <= 1'b0;
            self_idx <= 3'd0;
        end else begin
                // defaults each clock
                tx_start_reg <= 1'b0;
                // Drive FIFO read-ready whenever FIFO has data and we haven't latched it yet.
                fifo3_rd_ready_reg <= (fifo3_rd_valid && !fifo3_latched_valid);

            // capture self-test request from RX (press 'T' to trigger)
            if (rx_byte_valid && rx_byte == 8'h54) begin
                selftest_req <= 1'b1;
            end

            case (tx_state)
                S_IDLE: begin
                    if (selftest_req) begin
                        tx_state <= S_SELF;
                        self_idx <= 3'd0;
                    end else if (fifo3_rd_valid) begin
                        // don't pulse extra rd_ready here; the default above already
                        // asserts rd_ready when fifo3_rd_valid && !fifo3_latched_valid
                        tx_state <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    if (fifo3_rd_valid && !fifo3_latched_valid) begin
                        fifo3_latched <= fifo3_rd_data;
                        fifo3_latched_valid <= 1'b1;
                    end
                    if (fifo3_latched_valid && !tx_busy) begin
                        tx_data_reg <= fifo3_latched;
                        tx_start_reg <= 1'b1;
                        fifo3_latched_valid <= 1'b0;
                    end
                    // if FIFO empty and no in-flight byte, finish streaming
                    if (!fifo3_rd_valid && !fifo3_latched_valid) begin
                        tx_state <= S_MARK1_0;
                    end
                end

                // send "/0/0"
                S_MARK1_0: if (!tx_busy) begin tx_data_reg<=8'h2F; tx_start_reg<=1'b1; tx_state<=S_MARK1_1; end
                S_MARK1_1: if (!tx_busy) begin tx_data_reg<=8'h30; tx_start_reg<=1'b1; tx_state<=S_MARK1_2; end
                S_MARK1_2: if (!tx_busy) begin tx_data_reg<=8'h2F; tx_start_reg<=1'b1; tx_state<=S_MARK1_3; end
                S_MARK1_3: if (!tx_busy) begin tx_data_reg<=8'h30; tx_start_reg<=1'b1; tx_state<=S_MARK2_0; end

                // Self-test send sequence: "TEST\n" (ascii)
                S_SELF: begin
                    if (!tx_busy) begin
                        case (self_idx)
                            3'd0: begin tx_data_reg <= 8'h54; tx_start_reg <= 1'b1; self_idx <= 3'd1; end // 'T'
                            3'd1: begin tx_data_reg <= 8'h45; tx_start_reg <= 1'b1; self_idx <= 3'd2; end // 'E'
                            3'd2: begin tx_data_reg <= 8'h53; tx_start_reg <= 1'b1; self_idx <= 3'd3; end // 'S'
                            3'd3: begin tx_data_reg <= 8'h54; tx_start_reg <= 1'b1; self_idx <= 3'd4; end // 'T'
                            3'd4: begin tx_data_reg <= 8'h0A; tx_start_reg <= 1'b1; self_idx <= 3'd0; selftest_req <= 1'b0; tx_state <= S_IDLE; end // '\n'
                            default: begin selftest_req <= 1'b0; tx_state <= S_IDLE; end
                        endcase
                    end
                end

                // trailing marker
                S_MARK2_0: if (!tx_busy) begin tx_data_reg<=8'h2F; tx_start_reg<=1'b1; tx_state<=S_MARK2_1; end
                S_MARK2_1: if (!tx_busy) begin tx_data_reg<=8'h30; tx_start_reg<=1'b1; tx_state<=S_MARK2_2; end
                S_MARK2_2: if (!tx_busy) begin tx_data_reg<=8'h2F; tx_start_reg<=1'b1; tx_state<=S_MARK2_3; end
                S_MARK2_3: if (!tx_busy) begin tx_data_reg<=8'h30; tx_start_reg<=1'b1; tx_state<=S_IDLE; end

                default: tx_state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Expose some signals for LEDs or external observation
    // ------------------------------------------------------------------------
    // led_tx_activity assigned earlier (tx_act_cnt), led_resizer_busy & led_gray_busy assigned above
    // led_rx_activity assigned above

endmodule


// =================================================================================
// Small helper modules (Verilog-2001 compatible): rl_agent_simple, clock_module_simple, logger_simple
// =================================================================================

// --------------------------------------------
// rl_agent_simple
// small FSM that periodically issues a freq command
// --------------------------------------------
module rl_agent_simple #(
    parameter integer INTERVAL = 2000000
)(
    input  wire clk,
    input  wire rst,            // active-high
    output reg  rl_valid,
    output reg [1:0] core_mask,
    output reg [7:0] freq_code
);
    reg [31:0] cnt;
    // no typedefs; simple registers
    always @(posedge clk) begin
        if (rst) begin
            cnt <= 32'h0;
            rl_valid <= 1'b0;
            core_mask <= 2'b01;
            freq_code <= 8'd4;
        end else begin
            rl_valid <= 1'b0;
            if (cnt >= INTERVAL - 1) begin
                cnt <= 32'h0;
                rl_valid <= 1'b1;
                if (core_mask == 2'b01) core_mask <= 2'b10;
                else core_mask <= 2'b01;
                freq_code <= freq_code + 1;
            end else begin
                cnt <= cnt + 1;
            end
        end
    end
endmodule


// --------------------------------------------
// clock_module_simple
// Accepts rl commands and exposes two divider registers and generates CE pulses
// --------------------------------------------
module clock_module_simple (
    input  wire clk,
    input  wire rst,
    input  wire rl_valid,
    input  wire [1:0] core_mask,
    input  wire [7:0] freq_code,
    output reg ce_resizer,
    output reg ce_grayscale,
    output reg [7:0] divider_resizer,
    output reg [7:0] divider_grayscale
);
    reg [31:0] cnt_resizer, cnt_gray;

    // map_code_to_div written in Verilog-2001 function style
    function [7:0] map_code_to_div;
        input [7:0] code;
        begin
            map_code_to_div = (code % 250) + 1; // 1..250
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            divider_resizer <= 8'd10;
            divider_grayscale <= 8'd20;
            cnt_resizer <= 32'h0;
            cnt_gray <= 32'h0;
            ce_resizer <= 1'b0;
            ce_grayscale <= 1'b0;
        end else begin
            ce_resizer <= 1'b0;
            ce_grayscale <= 1'b0;

            // apply RL update when requested
            if (rl_valid) begin
                if (core_mask[0]) divider_resizer <= map_code_to_div(freq_code);
                if (core_mask[1]) divider_grayscale <= map_code_to_div(freq_code);
            end

            // resizer CE generation
            if (cnt_resizer >= divider_resizer - 1) begin
                cnt_resizer <= 32'h0;
                ce_resizer <= 1'b1;
            end else begin
                cnt_resizer <= cnt_resizer + 1;
            end

            // grayscale CE generation
            if (cnt_gray >= divider_grayscale - 1) begin
                cnt_gray <= 32'h0;
                ce_grayscale <= 1'b1;
            end else begin
                cnt_gray <= cnt_gray + 1;
            end
        end
    end
endmodule


// --------------------------------------------
// logger_simple
// Synchronously stores small packed entries every INTERVAL_CYCLES into an internal BRAM.
// Read side: rd_en pulses to read next 16-bit word; rd_valid presented same cycle.
// rd_done asserted when read pointer catches up with write pointer.
// --------------------------------------------
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
    output reg [15:0] rd_data,
    output wire rd_done
);
    // compute address width for the internal memory
    function integer clog2_local;
        input integer value;
        integer v;
        begin
            v = value - 1;
            clog2_local = 0;
            while (v > 0) begin
                clog2_local = clog2_local + 1;
                v = v >> 1;
            end
        end
    endfunction

    localparam integer ADDR_WIDTH = clog2_local(LOGGER_DEPTH);

    // internal memory
    reg [ENTRY_WIDTH-1:0] mem [0:LOGGER_DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [15:0] cycle_cnt;
    reg logging_active;

    assign rd_done = (rd_ptr == wr_ptr);

    // write (synchronous)
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
                    // PACK ENTRY (16 bits)
                    // bits: [15:13]=fifo1, [12:10]=fifo2, [9]=resizer, [8]=gray, [7:0]=divider_resizer (LSB)
                    mem[wr_ptr] <= { fifo1_load_bucket, fifo2_load_bucket, resizer_state, gray_state, divider_resizer };
                    wr_ptr <= wr_ptr + 1;
                end
            end
        end
    end

    // read logic (synchronous): rd_en -> rd_data and rd_valid presented same cycle
    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            rd_data <= 16'h0;
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
