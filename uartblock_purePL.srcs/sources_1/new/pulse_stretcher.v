
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/10/2025 02:50:32 PM
// Design Name: 
// Module Name: pulse_stretcher
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pulse_stretcher #(
  parameter integer WIDTH = 24  // at 100 MHz, 2^24 / 100e6 ? 0.167s (if preloaded to all-ones)
) (
  input  wire clk,
  input  wire rst_n,
  input  wire pulse_in,
  output reg  stretched_out
);

  reg [WIDTH-1:0] cnt;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= {WIDTH{1'b0}};
      stretched_out <= 1'b0;
    end else begin
      if (pulse_in) begin
        cnt <= {WIDTH{1'b1}}; // preload to max for visible time
        stretched_out <= 1'b1;
      end else if (cnt != 0) begin
        cnt <= cnt - 1'b1;
        stretched_out <= 1'b1;
      end else begin
        stretched_out <= 1'b0;
      end
    end
  end

endmodule
