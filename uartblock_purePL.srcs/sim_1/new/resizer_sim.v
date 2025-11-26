`timescale 1ns / 1ps

module resizer_sim;

    localparam IN_WIDTH  = 128;
    localparam IN_HEIGHT = 128;
    localparam OUT_WIDTH = 64;
    localparam OUT_HEIGHT= 64;
    localparam PIXEL_WIDTH = 8;
    localparam CHANNELS  = 3;
    localparam PIXEL_BITS = PIXEL_WIDTH * CHANNELS;

    reg clk;
    reg rst;

    reg  [PIXEL_BITS-1:0] data_in;
    reg                   read_signal;
    wire [PIXEL_BITS-1:0] data_out;
    wire                  write_signal;
    wire                  frame_done;
    wire                  state;

    resizer_core #(
        .IN_WIDTH(IN_WIDTH),
        .IN_HEIGHT(IN_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .CHANNELS(CHANNELS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .read_signal(read_signal),
        .data_out(data_out),
        .write_signal(write_signal),
        .frame_done(frame_done),
        .state(state)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;  
    end

    initial begin
        rst = 0;
        read_signal = 0;
        data_in = 0;
        #50;
        rst = 1;
    end


    integer x, y;
    reg [7:0] r, g, b;

    initial begin
        @(posedge rst); 
        #20;

        $display("============================================");
        $display("   Starting resizer_core Testbench          ");
        $display("============================================");

        for (y = 0; y < IN_HEIGHT; y = y + 1) begin
            for (x = 0; x < IN_WIDTH; x = x + 1) begin

                // Generate a simple pixel pattern
                r = x;      // red = x coordinate
                g = y;      // green = y coordinate
                b = x ^ y;  // blue = XOR for variety

                data_in = {r, g, b};

                read_signal = 1'b1;
                @(posedge clk);
                read_signal = 1'b0;

                // -------------------------------------------------
                // Check output
                // -------------------------------------------------
                if (write_signal) begin
                    $display("Output Pixel: (%3d,%3d) -> RGB = (%3d,%3d,%3d)",
                              x, y,
                              data_out[23:16], data_out[15:8], data_out[7:0]);

                    // Check that only even x,y produce output
                    if (x[0] == 1'b1 || y[0] == 1'b1) begin
                        $display("ERROR: Pixel output should NOT happen for odd x or y!");
                        $stop;
                    end
                end

            end
        end

        // -------------------------------------------------
        // End of frame check
        // -------------------------------------------------
        @(posedge clk);
        if (frame_done) begin
            $display("============================================");
            $display("Frame Done detected. Test PASSED!");
            $display("============================================");
        end else begin
            $display("ERROR: Frame_done NOT asserted at end of scan.");
        end

        #50;
        $finish;
    end

endmodule
