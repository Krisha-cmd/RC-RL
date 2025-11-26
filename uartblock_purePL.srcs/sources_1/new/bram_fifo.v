`timescale 1ns / 1ps
module bram_fifo #(
    parameter integer DEPTH = 4096,     
    parameter integer ADDR_WIDTH = $clog2(DEPTH)
)(
    
    input  wire                 wr_clk,
    input  wire                 wr_rst,
    input  wire                 wr_valid,
    output reg                  wr_ready,
    input  wire [7:0]           wr_data,

    
    input  wire                 rd_clk,
    input  wire                 rd_rst,
    output reg                  rd_valid,
    input  wire                 rd_ready,
    output reg  [7:0]           rd_data,

    
    output wire [ADDR_WIDTH:0]  wr_count_sync,
    output wire [ADDR_WIDTH:0]  rd_count_sync,

    
    output reg  [2:0]           load_bucket
);

    
    
    

    reg [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin;
    reg [ADDR_WIDTH:0] wr_ptr_bin_next;
    reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;

    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    
    function [ADDR_WIDTH:0] bin2gray(input [ADDR_WIDTH:0] b);
        bin2gray = (b >> 1) ^ b;
    endfunction

    function [ADDR_WIDTH:0] gray2bin(input [ADDR_WIDTH:0] g);
        integer i;
        reg [ADDR_WIDTH:0] b;
        begin
            b = 0;
            for (i = ADDR_WIDTH; i >= 0; i = i - 1)
                b = b ^ (g >> i);
            gray2bin = b;
        end
    endfunction

    wire [ADDR_WIDTH:0] rd_ptr_bin_synced = gray2bin(rd_ptr_gray_sync2);
    wire [ADDR_WIDTH:0] wr_ptr_bin_synced = gray2bin(wr_ptr_gray_sync2);

    
    
    

    wire [7:0] bram_rd_dout;
    reg  bram_wr_en_reg;
    reg  [7:0] bram_wr_din;

    wire [ADDR_WIDTH-1:0] bram_wr_addr = wr_ptr_bin[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] bram_rd_addr = rd_ptr_bin[ADDR_WIDTH-1:0];
    bram_11 #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) bram_inst (
        
        .clk_a                (wr_clk),
        .porta_write_address  (bram_wr_addr),     
        .porta_write_enabled  (bram_wr_en_reg),   
        .porta_enabled        (bram_wr_en_reg),   
        .porta_data_in        (bram_wr_din),
    
        
        .clk_b                (rd_clk),
        .portb_read_address   (bram_rd_addr),     
        .portb_enabled        (1'b1),             
        .portb_data_out       (bram_rd_dout)
    );
    

    
    
    

    
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst==1'b1) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    
    wire [ADDR_WIDTH:0] rd_ptr_bin_wr = rd_ptr_bin_synced;
    wire full_flag =
        ((wr_ptr_bin_next - rd_ptr_bin_wr) == {1'b1, {ADDR_WIDTH{1'b0}}});

    
    always @(*) begin
        wr_ready = ~full_flag;
        bram_wr_din = wr_data;
        bram_wr_en_reg = 1'b0;
        wr_ptr_bin_next = wr_ptr_bin;

        if (wr_valid && wr_ready) begin
            bram_wr_en_reg = 1'b1;
            wr_ptr_bin_next = wr_ptr_bin + 1'b1;
        end
    end

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst==1) begin
            wr_ptr_bin <= 0;
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            wr_ptr_gray <= bin2gray(wr_ptr_bin_next);
        end
    end

    
    
    

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst==1'b1) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    wire empty_flag = (rd_ptr_bin == wr_ptr_bin_synced);

    always @(*) begin
        rd_valid = ~empty_flag;
        rd_data = bram_rd_dout;
    end

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst==1'b1) begin
            rd_ptr_bin <= 0;
            rd_ptr_gray <= 0;
        end else if (rd_valid && rd_ready) begin
            rd_ptr_bin <= rd_ptr_bin + 1'b1;
            rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
        end
    end

    
    
    

    assign wr_count_sync = wr_ptr_bin - rd_ptr_bin_synced;
    assign rd_count_sync = wr_ptr_bin_synced - rd_ptr_bin;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst==1'b1) begin
            load_bucket <= 3'd0;
        end else begin
            
            load_bucket <= wr_count_sync[ADDR_WIDTH : ADDR_WIDTH-2];
        end
    end

endmodule
