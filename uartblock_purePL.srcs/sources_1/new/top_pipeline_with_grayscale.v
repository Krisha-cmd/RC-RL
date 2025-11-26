`timescale 1ns / 1ps






module top_pipeline_with_grayscale #(
    parameter integer PIXEL_WIDTH = 8,
    parameter integer CHANNELS    = 3,
    parameter integer IN_WIDTH    = 128,
    parameter integer IN_HEIGHT   = 128,
    parameter integer FIFO1_DEPTH = 8192,
    parameter integer FIFO2_DEPTH = 8192,
    parameter integer FIFO3_DEPTH = 4096,
    parameter integer DIFF_AMP_GAIN = 3
)(
    input  wire clk,
    input  wire rst,
    input  wire rl_enable,           
    input  wire uart_rx,
    output wire uart_tx,
    output wire led_rx_activity,
    output wire led_tx_activity,
    output wire led_resizer_busy,
    output wire led_gray_busy,
    output wire led_diffamp_busy,
    output wire led_blur_busy
);

    function integer clog2;
        input integer v;
        integer i;
        begin
            i = v - 1;
            clog2 = 0;
            while (i > 0) begin
                clog2 = clog2 + 1;
                i = i >> 1;
            end
        end
    endfunction
    
    localparam ADDR_W_FIFO1 = clog2(FIFO1_DEPTH);
    localparam ADDR_W_FIFO2 = clog2(FIFO2_DEPTH);
    localparam ADDR_W_FIFO3 = clog2(FIFO3_DEPTH);

    
    
    
    
    wire [3:0] rl_core0_div, rl_core1_div, rl_core2_div, rl_core3_div;
    wire rl_update_valid;
    wire [15:0] rl_total_updates, rl_exploration_count, rl_exploitation_count;
    wire signed [15:0] rl_avg_reward;
    wire [8:0] rl_current_state;
    wire [15:0] rl_current_action;
    wire core_stall, throughput_good;
    
    rl_q_learning_agent #(
        .NUM_CORES(4),
        .UPDATE_INTERVAL(1000)  
    ) rl_agent_inst (
        .clk(clk),
        .rst(rst),
        .enable(rl_enable),  
        .fifo1_load(fifo1_load_bucket),
        .fifo2_load(fifo2_load_bucket),
        .fifo3_load(fifo3_load_bucket),
        .current_core0_div(core0_divider),
        .current_core1_div(core1_divider),
        .current_core2_div(core2_divider),
        .current_core3_div(core3_divider),
        .rl_core0_div(rl_core0_div),
        .rl_core1_div(rl_core1_div),
        .rl_core2_div(rl_core2_div),
        .rl_core3_div(rl_core3_div),
        .rl_update_valid(rl_update_valid),
        .core_stall(core_stall),
        .throughput_good(throughput_good),
        .total_updates(rl_total_updates),
        .exploration_count(rl_exploration_count),
        .exploitation_count(rl_exploitation_count),
        .avg_reward(rl_avg_reward),
        .current_state_out(rl_current_state),
        .current_action_out(rl_current_action)
    );
    
    
    wire [3:0] core_clk_en;  
    wire [3:0] core_busy_signals;
    wire [3:0] core0_divider, core1_divider, core2_divider, core3_divider;
    
    clock_agent #(
        .NUM_CORES(4),
        .UPDATE_INTERVAL(100),
        .MAX_DIV_BITS(4)
    ) clock_agent_inst (
        .clk(clk),
        .rst(rst),
        .rl_enable(rl_enable),  
        .rl_core0_div(rl_core0_div),
        .rl_core1_div(rl_core1_div),
        .rl_core2_div(rl_core2_div),
        .rl_core3_div(rl_core3_div),
        .rl_update_valid(rl_update_valid),
        .core_busy(core_busy_signals),
        .fifo1_load(fifo1_load_bucket),
        .fifo2_load(fifo2_load_bucket),
        .fifo3_load(fifo3_load_bucket),
        .core_clk_en(core_clk_en),
        .core0_divider(core0_divider),
        .core1_divider(core1_divider),
        .core2_divider(core2_divider),
        .core3_divider(core3_divider),
        .core_stall(core_stall),
        .throughput_good(throughput_good),
        .total_decisions(),
        .clock_cycles_saved()
    );

    
    wire [7:0] rx_byte;
    wire rx_byte_valid;
    
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
    
    
    wire logger_logging_enabled;
    wire logger_transmit_logs;
    wire logger_tx_start;
    wire [7:0] logger_tx_data;
    wire logger_tx_busy;
    wire logger_logs_transmitted;
    
    performance_logger #(
        .MAX_LOG_ENTRIES(512),
        .LOG_INTERVAL(100)
    ) logger_inst (
        .clk(clk),
        .rst(rst),
        .core_busy(core_busy_signals),
        .fifo1_load(fifo1_load_bucket),
        .fifo2_load(fifo2_load_bucket),
        .fifo3_load(fifo3_load_bucket),
        .core0_divider(core0_divider),
        .core1_divider(core1_divider),
        .core2_divider(core2_divider),
        .core3_divider(core3_divider),
        .rl_enabled(rl_enable),              
        .logging_enabled(logger_logging_enabled),
        .transmit_logs(logger_transmit_logs),
        .tx_start(logger_tx_start),
        .tx_data(logger_tx_data),
        .tx_busy(logger_tx_busy),
        .logs_transmitted(logger_logs_transmitted)
    );
    
    
    reg tx_mux_state;  
    reg [7:0] mux_switch_delay;  
    
    always @(posedge clk) begin
        if (rst) begin
            tx_mux_state <= 1'b0;
            mux_switch_delay <= 0;
        end else begin
            
            if (image_processing_done && !tx_mux_state && !tx_busy) begin
                if (mux_switch_delay < 8'd100) begin
                    mux_switch_delay <= mux_switch_delay + 1;
                end else begin
                    tx_mux_state <= 1'b1;
                    mux_switch_delay <= 0;
                end
            end
            
            if (logger_logs_transmitted) begin
                tx_mux_state <= 1'b0;
                mux_switch_delay <= 0;
            end
        end
    end
    
    
    wire tx_start_mux = tx_mux_state ? logger_tx_start : tx_start_reg;
    wire [7:0] tx_data_mux = tx_mux_state ? logger_tx_data : tx_data_reg;
    assign logger_tx_busy = tx_busy;
    
    tx #(
        .CLOCK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) tx_inst (
        .clk(clk),
        .rst(rst),
        .tx(uart_tx),
        .tx_start(tx_start_mux),
        .tx_data(tx_data_mux),
        .tx_busy(tx_busy)
    );

    
    localparam integer LED_PULSE_CYCLES = 500000;
    reg [22:0] rx_led_cnt;
    reg [22:0] tx_led_cnt;
    reg [22:0] resizer_led_cnt;
    reg [22:0] gray_led_cnt;
    reg led_rx_r;
    reg led_tx_r;
    reg led_resizer_r;
    reg led_gray_r;
    reg tx_busy_prev;
    
    always @(posedge clk) begin
        if (rst) begin
            rx_led_cnt <= 0;
            led_rx_r <= 1'b0;
        end else if (rx_byte_valid) begin
            rx_led_cnt <= LED_PULSE_CYCLES;
            led_rx_r <= 1'b1;
        end else if (rx_led_cnt != 0) begin
            rx_led_cnt <= rx_led_cnt - 1;
            led_rx_r <= 1'b1;
        end else begin
            led_rx_r <= 1'b0;
        end
    end
    
    always @(posedge clk) begin
        if (rst) begin
            tx_led_cnt <= 0;
            led_tx_r <= 1'b0;
            tx_busy_prev <= 1'b0;
        end else begin
            if (tx_start_reg || (tx_busy && !tx_busy_prev)) begin
                tx_led_cnt <= LED_PULSE_CYCLES;
            end else if (tx_led_cnt != 0) begin
                tx_led_cnt <= tx_led_cnt - 1;
            end
            led_tx_r <= (tx_led_cnt != 0);
            tx_busy_prev <= tx_busy;
        end
    end
    
    assign led_rx_activity = led_rx_r;
    assign led_tx_activity = led_tx_r;

    
    wire fifo1_wr_ready;
    wire fifo1_rd_valid;
    wire [7:0] fifo1_rd_data;
    wire [2:0] fifo1_load_bucket;
    wire fifo1_rd_ready;
    
    bram_fifo #(
        .DEPTH(FIFO1_DEPTH),
        .ADDR_WIDTH(ADDR_W_FIFO1)
    ) fifo1 (
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
        .wr_count_sync(),
        .rd_count_sync(),
        .load_bucket(fifo1_load_bucket)
    );

    
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel1;
    wire pixel1_valid;
    wire pixel1_ready;
    
    pixel_assembler #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .CHANNELS(CHANNELS)
    ) assembler1 (
        .clk(clk),
        .rst(rst),
        .bram_rd_valid(fifo1_rd_valid),
        .bram_rd_ready(fifo1_rd_ready),
        .bram_rd_data(fifo1_rd_data),
        .pixel_out(pixel1),
        .pixel_valid(pixel1_valid),
        .pixel_ready(pixel1_ready)
    );
    
    assign pixel1_ready = 1'b1;

    
    wire [CHANNELS*PIXEL_WIDTH-1:0] res_out_pixel;
    wire res_valid;
    wire res_frame_done;
    wire resizer_state;
    wire resizer_read;
    
    assign resizer_read = pixel1_valid & pixel1_ready;
    
    resizer_core #(
        .IN_WIDTH(IN_WIDTH),
        .IN_HEIGHT(IN_HEIGHT),
        .OUT_WIDTH(IN_WIDTH/2),
        .OUT_HEIGHT(IN_HEIGHT/2),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .CHANNELS(CHANNELS)
    ) resizer_inst (
        .clk(clk),
        .rst(rst),
        .clk_en(core_clk_en[0]),  
        .data_in(pixel1),
        .read_signal(resizer_read),
        .data_out(res_out_pixel),
        .write_signal(res_valid),
        .frame_done(res_frame_done),
        .state(resizer_state)
    );
    
    always @(posedge clk) begin
        if (rst) begin
            resizer_led_cnt <= 0;
            led_resizer_r <= 1'b0;
        end else if (resizer_state) begin
            resizer_led_cnt <= LED_PULSE_CYCLES;
        end else if (resizer_led_cnt != 0) begin
            resizer_led_cnt <= resizer_led_cnt - 1;
        end
        led_resizer_r <= (resizer_led_cnt != 0);
    end
    
    assign led_resizer_busy = led_resizer_r;

    
    wire splitter_wr_valid;
    wire [7:0] splitter_wr_data;
    wire splitter_wr_ready;
    
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

    
    wire fifo2_rd_valid;
    wire [7:0] fifo2_rd_data;
    wire fifo2_rd_ready;
    wire fifo2_wr_ready;
    wire [2:0] fifo2_load_bucket;
    
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

    
    wire [CHANNELS*PIXEL_WIDTH-1:0] pixel2;
    wire pixel2_valid;
    wire pixel2_ready;
    
    pixel_assembler #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .CHANNELS(CHANNELS)
    ) assembler2 (
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

    
    wire gray_write;
    wire [7:0] gray_byte;
    wire gray_busy;
    wire gray_read;
    
    assign gray_read = pixel2_valid & pixel2_ready;
    
    grayscale_core #(
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) gray_inst (
        .clk(clk),
        .rst(rst),
        .clk_en(core_clk_en[1]),  
        .read_signal(gray_read),
        .data_in(pixel2),
        .data_out(gray_byte),
        .write_signal(gray_write),
        .state(gray_busy)
    );
    
    always @(posedge clk) begin
        if (rst) begin
            gray_led_cnt <= 0;
            led_gray_r <= 1'b0;
        end else if (gray_busy) begin
            gray_led_cnt <= LED_PULSE_CYCLES;
        end else if (gray_led_cnt != 0) begin
            gray_led_cnt <= gray_led_cnt - 1;
        end
        led_gray_r <= (gray_led_cnt != 0);
    end
    
    assign led_gray_busy = led_gray_r;

    
    wire diffamp_write;
    wire [7:0] diffamp_byte;
    wire diffamp_busy;
    wire diffamp_read;
    reg [22:0] diffamp_led_cnt;
    reg led_diffamp_r;
    
    assign diffamp_read = gray_write;
    
    difference_amplifier #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .GAIN(DIFF_AMP_GAIN)
    ) diffamp_inst (
        .clk(clk),
        .rst(rst),
        .clk_en(core_clk_en[2]),  
        .read_signal(diffamp_read),
        .data_in(gray_byte),
        .data_out(diffamp_byte),
        .write_signal(diffamp_write),
        .state(diffamp_busy)
    );
    
    always @(posedge clk) begin
        if (rst) begin
            diffamp_led_cnt <= 0;
            led_diffamp_r <= 1'b0;
        end else if (diffamp_busy) begin
            diffamp_led_cnt <= LED_PULSE_CYCLES;
        end else if (diffamp_led_cnt != 0) begin
            diffamp_led_cnt <= diffamp_led_cnt - 1;
        end
        led_diffamp_r <= (diffamp_led_cnt != 0);
    end
    
    assign led_diffamp_busy = led_diffamp_r;

    
    wire blur_write;
    wire [7:0] blur_byte;
    wire blur_busy;
    wire blur_read;
    reg [22:0] blur_led_cnt;
    reg led_blur_r;
    
    assign blur_read = diffamp_write;
    
    box_blur_1d #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMG_WIDTH(IN_WIDTH/2)  
    ) blur_inst (
        .clk(clk),
        .rst(rst),
        .clk_en(core_clk_en[3]),  
        .read_signal(blur_read),
        .data_in(diffamp_byte),
        .data_out(blur_byte),
        .write_signal(blur_write),
        .state(blur_busy)
    );
    
    always @(posedge clk) begin
        if (rst) begin
            blur_led_cnt <= 0;
            led_blur_r <= 1'b0;
        end else if (blur_busy) begin
            blur_led_cnt <= LED_PULSE_CYCLES;
        end else if (blur_led_cnt != 0) begin
            blur_led_cnt <= blur_led_cnt - 1;
        end
        led_blur_r <= (blur_led_cnt != 0);
    end
    
    assign led_blur_busy = led_blur_r;

    
    wire fifo3_rd_valid;
    wire [7:0] fifo3_rd_data;
    wire fifo3_rd_ready;
    wire fifo3_wr_ready;
    wire [2:0] fifo3_load_bucket;
    
    bram_fifo #(
        .DEPTH(FIFO3_DEPTH),
        .ADDR_WIDTH(ADDR_W_FIFO3)
    ) fifo3 (
        .wr_clk(clk),
        .wr_rst(rst),
        .wr_valid(blur_write),
        .wr_ready(fifo3_wr_ready),
        .wr_data(blur_byte),
        .rd_clk(clk),
        .rd_rst(rst),
        .rd_valid(fifo3_rd_valid),
        .rd_ready(fifo3_rd_ready),
        .rd_data(fifo3_rd_data),
        .wr_count_sync(),
        .rd_count_sync(),
        .load_bucket(fifo3_load_bucket)
    );

    
    reg [7:0] tx_byte_latch;
    reg tx_byte_valid;
    reg tx_state;
    reg [15:0] tx_byte_count;  
    reg image_processing_done;
    reg logger_trigger_sent;
    reg image_tx_complete;  
    
    localparam EXPECTED_BYTES = (IN_WIDTH/2) * (IN_HEIGHT/2);  
    localparam EXPECTED_RX_BYTES = IN_WIDTH * IN_HEIGHT * CHANNELS;  
    
    
    reg logger_enabled_reg;
    reg logger_transmit_reg;
    reg start_new_image;  
    reg [15:0] rx_byte_count;  
    
    
    reg rx_in_progress;  
    reg tx_in_progress;  
    
    always @(posedge clk) begin
        if (rst) begin
            logger_enabled_reg <= 1'b0;
            logger_transmit_reg <= 1'b0;
            logger_trigger_sent <= 1'b0;
            image_processing_done <= 1'b0;
            image_tx_complete <= 1'b0;
            start_new_image <= 1'b0;
            rx_byte_count <= 0;
            rx_in_progress <= 1'b0;
            tx_in_progress <= 1'b0;
        end else begin
            start_new_image <= 1'b0;  
            logger_transmit_reg <= 1'b0;  
            
            
            if (rx_byte_valid && !rx_in_progress) begin
                start_new_image <= 1'b1;
                rx_in_progress <= 1'b1;
                rx_byte_count <= 1;
                logger_enabled_reg <= 1'b1;  
                logger_trigger_sent <= 1'b0;
                tx_in_progress <= 1'b1;
            end else if (rx_byte_valid && rx_in_progress) begin
                rx_byte_count <= rx_byte_count + 1;
                
                
                if (rx_byte_count >= EXPECTED_RX_BYTES - 1) begin
                    rx_in_progress <= 1'b0;
                    rx_byte_count <= 0;
                end
            end
            
            
            
            if (tx_in_progress && tx_byte_count >= EXPECTED_BYTES && !logger_trigger_sent && !tx_busy) begin
                
                logger_transmit_reg <= 1'b1;  
                logger_trigger_sent <= 1'b1;
                image_processing_done <= 1'b1;
                logger_enabled_reg <= 1'b0;  
            end
            
            
            if (logger_logs_transmitted) begin
                logger_enabled_reg <= 1'b0;
                logger_trigger_sent <= 1'b0;
                image_processing_done <= 1'b0;
                tx_in_progress <= 1'b0;
            end
            
            image_tx_complete <= 1'b0;  
        end
    end
    
    assign logger_logging_enabled = logger_enabled_reg;
    assign logger_transmit_logs = logger_transmit_reg;
    
    always @(posedge clk) begin
        if (rst) begin
            tx_start_reg <= 1'b0;
            tx_data_reg <= 8'h00;
            tx_byte_latch <= 8'h00;
            tx_byte_valid <= 1'b0;
            tx_state <= 1'b0;
            tx_byte_count <= 0;
        end else begin
            tx_start_reg <= 1'b0;
            
            
            if (start_new_image) begin
                tx_byte_count <= 0;
            end
            
            case (tx_state)
                1'b0: begin
                    
                    if (fifo3_rd_valid && !tx_mux_state) begin
                        tx_byte_latch <= fifo3_rd_data;
                        tx_byte_valid <= 1'b1;
                        tx_state <= 1'b1;
                    end
                end
                1'b1: begin
                    
                    if (!tx_busy && tx_byte_valid && !tx_mux_state) begin
                        tx_data_reg <= tx_byte_latch;
                        tx_start_reg <= 1'b1;
                        tx_byte_valid <= 1'b0;
                        tx_byte_count <= tx_byte_count + 1;
                        tx_state <= 1'b0;
                    end else if (tx_mux_state) begin
                        
                        tx_byte_valid <= 1'b0;
                        tx_state <= 1'b0;
                    end
                end
            endcase
        end
    end
    
    
    assign fifo3_rd_ready = (tx_state == 1'b0) && fifo3_rd_valid && !tx_mux_state;

    
    assign core_busy_signals[0] = resizer_state;
    assign core_busy_signals[1] = gray_busy;
    assign core_busy_signals[2] = diffamp_busy;
    assign core_busy_signals[3] = blur_busy;

endmodule
