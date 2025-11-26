`timescale 1ns / 1ps

// Performance Logger - Logs core states, FIFO loads, and clock dividers
// Stores data in BRAM and transmits after image processing completes

module performance_logger #(
    parameter integer NUM_CORES = 4,
    parameter integer LOG_INTERVAL = 100,  // Log every N clock cycles
    parameter integer MAX_LOG_ENTRIES = 512,  // Maximum number of log entries
    parameter integer ADDR_WIDTH = 9  // log2(512)
)(
    input  wire clk,
    input  wire rst,
    
    // Control signals
    input  wire logging_enabled,     // Enable logging during image processing
    input  wire transmit_logs,       // Trigger log transmission
    output reg  logs_transmitted,    // Signals completion of transmission
    
    // Data inputs to log
    input  wire [NUM_CORES-1:0] core_busy,      // Core busy states
    input  wire [2:0] fifo1_load,
    input  wire [2:0] fifo2_load,
    input  wire [2:0] fifo3_load,
    input  wire [3:0] core0_divider,
    input  wire [3:0] core1_divider,
    input  wire [3:0] core2_divider,
    input  wire [3:0] core3_divider,
    
    // RL Agent state
    input  wire rl_enabled,          // RL agent enabled flag
    
    // UART TX interface (compatible with tx module)
    output reg  tx_start,
    output reg  [7:0] tx_data,
    input  wire tx_busy
);

    // FSM States
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
    reg [15:0] num_entries;  // 16 bits for protocol compatibility (2-byte count)
    
    // Log entry format: 24 bits
    // [23:20] = core_busy (4 bits)
    // [19:17] = fifo1_load (3 bits)
    // [16:14] = fifo2_load (3 bits)
    // [13:11] = fifo3_load (3 bits)
    // [10:7]  = core0_divider (4 bits)
    // [6:3]   = core1_divider (4 bits)
    // [2:0]   = Packed: core2_div[3:2], core3_div[3:2], combined_low[2:0]
    // Actually let's use 32 bits for simplicity
    
    // Simplified: 32-bit log entry
    // [31:28] = core_busy (4 bits)
    // [27:25] = fifo1_load (3 bits)
    // [24:22] = fifo2_load (3 bits)
    // [21:19] = fifo3_load (3 bits)
    // [18:15] = core0_divider (4 bits)
    // [14:11] = core1_divider (4 bits)
    // [10:7]  = core2_divider (4 bits)
    // [6:3]   = core3_divider (4 bits)
    // [2:0]   = reserved
    
    reg [31:0] log_memory [0:MAX_LOG_ENTRIES-1];
    reg [31:0] current_log_entry;
    
    // TX state machine
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
            
            // Initialize memory with zeros instead of DEADBEEF
            for (i = 0; i < MAX_LOG_ENTRIES; i = i + 1) begin
                log_memory[i] <= 32'h00000000;
            end
            // Start with zero entries - will be populated during logging
            num_entries <= 0;
        end else begin
            // Default: clear tx_start pulse
            tx_start <= 0;
            
            case (state)
                STATE_IDLE: begin
                    logs_transmitted <= 0;
                    
                    if (logging_enabled) begin
                        log_counter <= 0;
                        write_addr <= 0;  // Always start from beginning
                        num_entries <= 0;  // Reset count when starting new logging session
                        state <= STATE_LOGGING;
                    end else if (transmit_logs) begin
                        // Start transmission (will send whatever was logged)
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
                            
                            // Capture current state
                            if (write_addr < MAX_LOG_ENTRIES) begin
                                current_log_entry <= {
                                    core_busy,           // [31:28] - 4 bits
                                    fifo1_load,          // [27:25] - 3 bits
                                    fifo2_load,          // [24:22] - 3 bits
                                    fifo3_load,          // [21:19] - 3 bits
                                    core0_divider,       // [18:15] - 4 bits
                                    core1_divider,       // [14:11] - 4 bits
                                    core2_divider,       // [10:7]  - 4 bits
                                    core3_divider,       // [6:3]   - 4 bits
                                    rl_enabled,          // [2]     - 1 bit: RL agent state
                                    2'b00                // [1:0]   - reserved
                                };
                                
                                log_memory[write_addr] <= current_log_entry;
                                write_addr <= write_addr + 1;
                                num_entries <= write_addr + 1;
                            end
                        end
                    end
                end
                
                STATE_TX_HEADER: begin
                    // Send header: "LOG:" + num_entries (2 bytes)
                    if (!tx_busy && !tx_start) begin
                        case (tx_byte_index)
                            3'd0: begin
                                tx_data <= "L";
                                tx_start <= 1;
                                tx_byte_index <= 1;
                            end
                            3'd1: begin
                                tx_data <= "O";
                                tx_start <= 1;
                                tx_byte_index <= 2;
                            end
                            3'd2: begin
                                tx_data <= "G";
                                tx_start <= 1;
                                tx_byte_index <= 3;
                            end
                            3'd3: begin
                                tx_data <= ":";
                                tx_start <= 1;
                                tx_byte_index <= 4;
                            end
                            3'd4: begin
                                tx_data <= num_entries[15:8];  // High byte
                                tx_start <= 1;
                                tx_byte_index <= 5;
                            end
                            3'd5: begin
                                tx_data <= num_entries[7:0];   // Low byte
                                tx_start <= 1;
                                tx_byte_index <= 0;
                                read_addr <= 0;
                                state <= STATE_TX_DATA;
                            end
                        endcase
                    end
                end
                
                STATE_TX_DATA: begin
                    if (read_addr >= num_entries) begin
                        tx_byte_index <= 0;
                        state <= STATE_TX_FOOTER;
                    end else begin
                        if (!tx_busy && !tx_start) begin
                            if (tx_byte_index == 0) begin
                                tx_log_entry <= log_memory[read_addr];
                            end
                            
                            case (tx_byte_index)
                                3'd0: begin
                                    tx_data <= tx_log_entry[31:24];
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
                            endcase
                        end
                    end
                end
                
                STATE_TX_FOOTER: begin
                    // Send footer: "END\n"
                    if (!tx_busy && !tx_start) begin
                        case (tx_byte_index)
                            3'd0: begin
                                tx_data <= "E";
                                tx_start <= 1;
                                tx_byte_index <= 1;
                            end
                            3'd1: begin
                                tx_data <= "N";
                                tx_start <= 1;
                                tx_byte_index <= 2;
                            end
                            3'd2: begin
                                tx_data <= "D";
                                tx_start <= 1;
                                tx_byte_index <= 3;
                            end
                            3'd3: begin
                                tx_data <= 8'h0A;  // Newline
                                tx_start <= 1;
                                tx_byte_index <= 0;
                                state <= STATE_DONE;
                            end
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
