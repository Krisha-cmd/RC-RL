





















module pulse_stretcher #(
  parameter integer WIDTH = 24  
) (
  input  wire clk,
  input  wire rst,
  input  wire pulse_in,
  output reg  stretched_out
);

  reg [WIDTH-1:0] cnt;

  always @(posedge clk or posedge rst) begin
    if (rst==1'b1) begin
      cnt <= {WIDTH{1'b0}};
      stretched_out <= 1'b0;
    end else begin
      if (pulse_in) begin
        cnt <= {WIDTH{1'b1}}; 
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
