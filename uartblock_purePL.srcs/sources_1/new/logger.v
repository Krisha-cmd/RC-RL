`timescale 1ns / 1ps

module logger #(
    parameter integer INTERVAL_CYCLES = 20,
    parameter integer ENTRY_WIDTH     = 16,
    parameter integer LOGGER_DEPTH    = 12288,
    
    parameter integer DEFAULT_ACTIVE  = 1,
    parameter integer ADDR_WIDTH      = $clog2(LOGGER_DEPTH)
)(
    input  wire clk,
    input  wire rst,

    
    input  wire [2:0] fifo1_load_bucket,
    input  wire [2:0] fifo2_load_bucket,
    input  wire       resizer_state,
    input  wire       gray_state,

    
    input  wire [7:0] divider_resizer,     
    input  wire [7:0] divider_grayscale,

    
    input  wire       start_logging,
    input  wire       stop_logging,

    
    input  wire       rd_clk,
    input  wire       rd_en,
    output reg        rd_valid,
    output reg [15:0] rd_data,
    output wire       rd_done
);

    reg [ENTRY_WIDTH-1:0] mem [0:LOGGER_DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    reg [15:0] cycle_cnt;
    reg logging_active;
    
    reg rd_valid_hold;

    assign rd_done = (rd_ptr == wr_ptr);

    
    always @(posedge clk or posedge rst) begin
        if (rst==1'b1) begin
            wr_ptr <= 0;
            cycle_cnt <= 0;
            
            logging_active <= (DEFAULT_ACTIVE != 0) ? 1'b1 : 1'b0;
        end else begin

            if (start_logging)
                logging_active <= 1;

            if (stop_logging)
                logging_active <= 0;

            if (!logging_active) begin
                cycle_cnt <= 0;
            end else begin
                if (cycle_cnt < INTERVAL_CYCLES-1)
                    cycle_cnt <= cycle_cnt + 1;
                else begin
                    cycle_cnt <= 0;

                    
                    
                    
                    
                    
                    
                    
                    mem[wr_ptr] <= {
                        fifo1_load_bucket,     
                        fifo2_load_bucket,     
                        resizer_state,         
                        gray_state,            
                        divider_resizer[3:0],  
                        divider_grayscale[3:0] 
                    };
                    
                    

                    wr_ptr <= wr_ptr + 1;
                end
            end
        end
    end

    
    
    
    
    always @(posedge rd_clk or posedge rst) begin
        if (rst==1'b1) begin
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            rd_data <= 16'h0;
            rd_valid <= 1'b0;
            rd_valid_hold <= 1'b0;
        end else begin
            
            rd_valid <= 1'b0;

            if (rd_en && (rd_ptr != wr_ptr)) begin
                
                rd_data <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1;
                rd_valid <= 1'b1;
                rd_valid_hold <= 1'b1; 
            end else if (rd_valid_hold) begin
                
                rd_valid <= 1'b1;
                rd_valid_hold <= 1'b0;
            end else begin
                rd_valid <= 1'b0;
            end
        end
    end

endmodule
