`timescale 1ns/1ps

module testbench_top_uart;

    // Parameters
    localparam CLOCK_FREQ = 100_000_000;
    localparam BAUD_RATE  = 115200;
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE;  // ns per bit

    // Clock
    reg clk = 0;
    always #5 clk = ~clk; // 100 MHz clock (10 ns period)

    // UART line
    reg uart_rx = 1;      // idle = high
    wire uart_tx;

    // Instantiate DUT
    top_module_128 dut (
        .clk(clk),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // Task: send a byte over UART
    task uart_send_byte(input [7:0] data);
        integer i;
        begin
            // Start bit
            uart_rx = 0;
            #(BIT_PERIOD);

            // Send 8 bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #(BIT_PERIOD);
            end

            // Stop bit
            uart_rx = 1;
            #(BIT_PERIOD);
        end
    endtask

    // Capture TX byte
    reg [7:0] rx_from_dut;
    reg [3:0] bit_count = 0;
    reg receiving = 0;

    always @(posedge clk) begin
        // naive UART monitor (oversimplified)
        if (!receiving && uart_tx == 0) begin
            receiving <= 1;
            bit_count <= 0;
        end else if (receiving) begin
            bit_count <= bit_count + 1;
            if (bit_count == 15) begin
                receiving <= 0;
                $display("TX SENT BYTE = %02X", rx_from_dut);
            end
        end
    end

    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, testbench_top_uart);

        #100_000;

        // Send a few bytes
        uart_send_byte(8'h41); // 'A'
        uart_send_byte(8'h42); // 'B'
        uart_send_byte(8'h43); // 'C'

        #1_000_000;
        $finish;
    end

endmodule
