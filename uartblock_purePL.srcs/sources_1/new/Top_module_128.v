`timescale 1ns / 1ps

module top_module_128 #(
    parameter integer CLOCK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE    = 115200,
    parameter integer IMG_WIDTH    = 128,
    parameter integer IMG_HEIGHT   = 128,
    parameter integer PIXEL_WIDTH  = 8,
    parameter integer IMG_SIZE     = IMG_WIDTH * IMG_HEIGHT,
    parameter integer ADDR_WIDTH   = $clog2((IMG_SIZE==1)?2:IMG_SIZE)
)(
    input  wire clk,
    input  wire uart_rx,
    output wire uart_tx
);

    //----------------------------------------------------------
    // Reset
    //----------------------------------------------------------
    wire rst_n = 1'b1;

    //----------------------------------------------------------
    // Address pointers
    //----------------------------------------------------------
    reg [ADDR_WIDTH-1:0] write_addr = 0;
    reg [ADDR_WIDTH-1:0] read_addr  = 0;

    //----------------------------------------------------------
    // UART RX wires
    //----------------------------------------------------------
    wire [PIXEL_WIDTH-1:0] rx_byte;
    wire                   rx_byte_valid;

    //----------------------------------------------------------
    // BRAM read output
    //----------------------------------------------------------
    wire [PIXEL_WIDTH-1:0] read_pixel;

    //----------------------------------------------------------
    // TX control
    //----------------------------------------------------------
    reg                    tx_start = 0;
    reg [PIXEL_WIDTH-1:0]  tx_data  = 0;

    //----------------------------------------------------------
    // UART RECEIVER
    //----------------------------------------------------------
    rx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) rx1 (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid)
    );

    //----------------------------------------------------------
    // BRAM
    //----------------------------------------------------------
    bram_11 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_11 (
        .clk(clk),
        .rst_n(rst_n),

        // write port
        .write_data(rx_byte),
        .write_valid(rx_byte_valid),
        .write_addr(write_addr),

        // read port
        .read_addr(read_addr),
        .read_data(read_pixel)
    );

    //----------------------------------------------------------
    // UART TRANSMITTER
    //----------------------------------------------------------
    tx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) tx1 (
        .clk(clk),
        .rst_n(rst_n),
        .tx(uart_tx),
        .tx_start(tx_start),
        .tx_data(tx_data)
    );

    //----------------------------------------------------------
    // WRITE POINTER LOGIC (BRAM Write)
    //----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            write_addr <= 0;
        else if (rx_byte_valid)
            write_addr <= write_addr + 1;
    end

    //----------------------------------------------------------
    // READ → TX LOGIC (1-cycle delayed read for BRAM)
    //----------------------------------------------------------
    reg rx_valid_dly = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            read_addr   <= 0;
            rx_valid_dly <= 0;
            tx_start    <= 0;
        end else begin
            // delay RX valid so BRAM read data is ready
            rx_valid_dly <= rx_byte_valid;

            // 1 cycle after BRAM write, read_pixel is valid
            if (rx_valid_dly) begin
                tx_data <= read_pixel; // correct byte
                tx_start <= 1'b1;      // pulse
                read_addr <= read_addr + 1;
            end else begin
                tx_start <= 1'b0;
            end
        end
    end

endmodule
