
























module uart_receiver_module #(
    parameter integer CLOCK_FREQ = 100_000_000,
    parameter integer BAUD_RATE  = 115200
)(
    input  wire        clk,        
    input  wire        rst,      
    input  wire        rx,         
    output reg  [7:0]  rx_byte,    
    output reg         rx_byte_valid 
);

    localparam integer OVERSAMPLE = 16;
    
    localparam integer SAMPLE_CLK_DIV = (CLOCK_FREQ + (BAUD_RATE*OVERSAMPLE)/2) / (BAUD_RATE*OVERSAMPLE);

    
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [4:0] sample_cnt; 
    reg [2:0] bit_index;
    reg [7:0] shift_reg;
    reg rx_sync0, rx_sync1;

    
    reg [31:0] clk_div_cnt;
    wire sample_tick = (clk_div_cnt == 0);

    
    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
        end
    end

    
    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            clk_div_cnt <= 0;
        end else begin
            if (clk_div_cnt == 0)
                clk_div_cnt <= SAMPLE_CLK_DIV - 1;
            else
                clk_div_cnt <= clk_div_cnt - 1;
        end
    end

    
    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            state <= IDLE;
            sample_cnt <= 0;
            bit_index <= 0;
            shift_reg <= 8'd0;
            rx_byte <= 8'd0;
            rx_byte_valid <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;
            if (sample_tick) begin
                case (state)
                    IDLE: begin
                        if (rx_sync1 == 1'b0) begin 
                            state <= START;
                            sample_cnt <= 0;
                        end
                    end
                    START: begin
                        sample_cnt <= sample_cnt + 1;
                        
                        if (sample_cnt == (OVERSAMPLE/2 - 1)) begin
                            if (rx_sync1 == 1'b0) begin
                                state <= DATA;
                                sample_cnt <= 0;
                                bit_index <= 0;
                                shift_reg <= 8'd0;
                            end else begin
                                state <= IDLE;
                            end
                        end
                    end
                    DATA: begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == OVERSAMPLE - 1) begin
                            sample_cnt <= 0;
                            shift_reg[bit_index] <= rx_sync1; 
                            if (bit_index == 7) begin
                                state <= STOP;
                            end else begin
                                bit_index <= bit_index + 1;
                            end
                        end
                    end
                    STOP: begin
                        sample_cnt <= sample_cnt + 1;
                        if (sample_cnt == (OVERSAMPLE - 1)) begin
                            rx_byte <= shift_reg;
                            rx_byte_valid <= 1'b1;
                            state <= IDLE;
                            sample_cnt <= 0;
                        end
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
