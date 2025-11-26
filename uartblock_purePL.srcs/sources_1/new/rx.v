module rx #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,

    output reg [7:0] rx_byte      = 8'd0,
    output reg       rx_byte_valid = 1'b0
);

    localparam integer BAUD_DIV = CLOCK_FREQ / BAUD_RATE;

    reg rx_sync1 = 1;
    reg rx_sync2 = 1;

    
    always @(posedge clk) begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end

    
    localparam IDLE      = 0,
               START_BIT = 1,
               DATA_BITS = 2,
               STOP_BIT  = 3;

    reg [1:0] state = IDLE;

    reg [15:0] baud_cnt = 0;
    reg [2:0]  bit_idx  = 0;
    reg [7:0]  shift_reg = 0;

    always @(posedge clk) begin
        if (rst==1'b1) begin
            state          <= IDLE;
            rx_byte_valid  <= 1'b0;
            baud_cnt       <= 0;
            bit_idx        <= 0;
            shift_reg      <= 0;
        end else begin
            rx_byte_valid <= 1'b0; 

            case (state)

            
            
            
            IDLE: begin
                if (rx_sync2 == 1'b0) begin
                    state     <= START_BIT;
                    baud_cnt  <= BAUD_DIV/2;  
                end
            end

            
            
            
            START_BIT: begin
                if (baud_cnt == 0) begin
                    if (rx_sync2 == 1'b0) begin
                        state    <= DATA_BITS;
                        bit_idx  <= 0;
                        baud_cnt <= BAUD_DIV - 1;
                    end else begin
                        state <= IDLE;
                    end
                end else
                    baud_cnt <= baud_cnt - 1;
            end

            
            
            
            DATA_BITS: begin
                if (baud_cnt == 0) begin
                    shift_reg[bit_idx] <= rx_sync2;

                    if (bit_idx == 3'd7)
                        state <= STOP_BIT;
                    else
                        bit_idx <= bit_idx + 1;

                    baud_cnt <= BAUD_DIV - 1;
                end else
                    baud_cnt <= baud_cnt - 1;
            end

            
            
            
            STOP_BIT: begin
                if (baud_cnt == 0) begin
                    if (rx_sync2 == 1'b1) begin
                        rx_byte       <= shift_reg;
                        rx_byte_valid <= 1'b1;  
                    end
                    state <= IDLE;
                end else
                    baud_cnt <= baud_cnt - 1;
            end

            endcase
        end
    end

endmodule
