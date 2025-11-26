`timescale 1ns / 1ps




module performance_logger #(
    parameter integer NUM_CORES = 4,
    parameter integer LOG_INTERVAL = 100,  
    parameter integer MAX_LOG_ENTRIES = 512,  
    parameter integer ADDR_WIDTH = 9  
)(
    input  wire clk,
    input  wire rst,
    
    
    input  wire logging_enabled,     
    input  wire transmit_logs,       
    output reg  logs_transmitted,    
    
    
    input  wire [NUM_CORES-1:0] core_busy,      
    input  wire [2:0] fifo1_load,
    input  wire [2:0] fifo2_load,
    input  wire [2:0] fifo3_load,
    input  wire [3:0] core0_divider,
    input  wire [3:0] core1_divider,
    input  wire [3:0] core2_divider,
    input  wire [3:0] core3_divider,
    
    
    input  wire rl_enabled,          
    
    
    output reg  tx_start,
    output reg  [7:0] tx_data,
    input  wire tx_busy
);

    
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_LOGGING    = 3'd1;
    localparam STATE_TX_HEADER  = 3'd2;
    localparam STATE_TX_DATA    = 3'd3;
    localparam STATE_TX_FOOTER  = 3'd4;
    localparam STATE_DONE       = 3'd5;
    
    reg [2:0] state;
    reg [15:0] log_counter;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [15:0] num_entries;  
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    reg [31:0] log_memory [0:MAX_LOG_ENTRIES-1];
    reg [31:0] current_log_entry;
    
    
    reg [2:0] tx_byte_index;
    reg [31:0] tx_log_entry;
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            log_counter <= 0;
            write_addr <= 0;
            read_addr <= 0;
            num_entries <= 0;
            tx_start <= 0;
            tx_data <= 0;
            logs_transmitted <= 0;
            tx_byte_index <= 0;
            tx_log_entry <= 0;
            
            
            for (i = 0; i < MAX_LOG_ENTRIES; i = i + 1) begin
                log_memory[i] <= 32'h00000000;
            end
            
            num_entries <= 0;
        end else begin
            
            tx_start <= 0;
            
            case (state)
                STATE_IDLE: begin
                    logs_transmitted <= 0;
                    
                    if (logging_enabled) begin
                        log_counter <= 0;
                        write_addr <= 0;  
                        num_entries <= 0;  
                        state <= STATE_LOGGING;
                    end else if (transmit_logs) begin
                        
                        read_addr <= 0;
                        tx_byte_index <= 0;
                        state <= STATE_TX_HEADER;
                    end
                end
                
                STATE_LOGGING: begin
                    if (!logging_enabled) begin
                        state <= STATE_IDLE;
                    end else begin
                        log_counter <= log_counter + 1;
                        
                        if (log_counter >= LOG_INTERVAL - 1) begin
                            log_counter <= 0;
                            
                            
                            if (write_addr < MAX_LOG_ENTRIES) begin
                                current_log_entry <= {
                                    core_busy,           
                                    fifo1_load,          
                                    fifo2_load,          
                                    fifo3_load,          
                                    core0_divider,       
                                    core1_divider,       
                                    core2_divider,       
                                    core3_divider,       
                                    rl_enabled,          
                                    2'b00                
                                };
                                
                                log_memory[write_addr] <= current_log_entry;
                                write_addr <= write_addr + 1;
                                num_entries <= write_addr + 1;
                            end
                        end
                    end
                end
                
                STATE_TX_HEADER: begin
                    
                    
                    if (!tx_busy && !tx_start) begin
                        case (tx_byte_index)
                            3'd0: begin
                                tx_data <= 8'h4C;  
                                tx_start <= 1;
                                tx_byte_index <= 1;
                            end
                            3'd1: begin
                                tx_data <= 8'h4F;  
                                tx_start <= 1;
                                tx_byte_index <= 2;
                            end
                            3'd2: begin
                                tx_data <= 8'h47;  
                                tx_start <= 1;
                                tx_byte_index <= 3;
                            end
                            3'd3: begin
                                tx_data <= 8'h3A;  
                                tx_start <= 1;
                                tx_byte_index <= 4;
                            end
                            3'd4: begin
                                tx_data <= num_entries[15:8];  
                                tx_start <= 1;
                                tx_byte_index <= 5;
                            end
                            3'd5: begin
                                tx_data <= num_entries[7:0];   
                                tx_start <= 1;
                                tx_byte_index <= 0;
                                read_addr <= 0;
                                state <= STATE_TX_DATA;
                            end
                            default: tx_byte_index <= 0;
                        endcase
                    end
                end
                
                STATE_TX_DATA: begin
                    if (read_addr >= num_entries) begin
                        tx_byte_index <= 0;
                        state <= STATE_TX_FOOTER;
                    end else begin
                        if (!tx_busy && !tx_start) begin
                            case (tx_byte_index)
                                3'd0: begin
                                    
                                    tx_log_entry <= log_memory[read_addr];
                                    tx_data <= log_memory[read_addr][31:24];
                                    tx_start <= 1;
                                    tx_byte_index <= 1;
                                end
                                3'd1: begin
                                    tx_data <= tx_log_entry[23:16];
                                    tx_start <= 1;
                                    tx_byte_index <= 2;
                                end
                                3'd2: begin
                                    tx_data <= tx_log_entry[15:8];
                                    tx_start <= 1;
                                    tx_byte_index <= 3;
                                end
                                3'd3: begin
                                    tx_data <= tx_log_entry[7:0];
                                    tx_start <= 1;
                                    tx_byte_index <= 0;
                                    read_addr <= read_addr + 1;
                                end
                                default: tx_byte_index <= 0;
                            endcase
                        end
                    end
                end
                
                STATE_TX_FOOTER: begin
                    
                    if (!tx_busy && !tx_start) begin
                        case (tx_byte_index)
                            3'd0: begin
                                tx_data <= 8'h45;  
                                tx_start <= 1;
                                tx_byte_index <= 1;
                            end
                            3'd1: begin
                                tx_data <= 8'h4E;  
                                tx_start <= 1;
                                tx_byte_index <= 2;
                            end
                            3'd2: begin
                                tx_data <= 8'h44;  
                                tx_start <= 1;
                                tx_byte_index <= 3;
                            end
                            3'd3: begin
                                tx_data <= 8'h0A;  
                                tx_start <= 1;
                                tx_byte_index <= 0;
                                state <= STATE_DONE;
                            end
                            default: tx_byte_index <= 0;
                        endcase
                    end
                end
                
                STATE_DONE: begin
                    logs_transmitted <= 1;
                    state <= STATE_IDLE;
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
