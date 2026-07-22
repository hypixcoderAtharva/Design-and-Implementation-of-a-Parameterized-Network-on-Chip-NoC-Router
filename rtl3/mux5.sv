// =============================================================================
// mux5.sv
// -----------------------------------------------------------------------------
// Parameterized 5:1 multiplexer, one-hot select (matches the router's fixed
// 5-port topology: N/S/E/W/Local). Used at each crossbar output to collect
// the winning input port's flit.
// =============================================================================

module mux5 #(
  parameter int WIDTH = 32
) (
  input  logic [4:0]        sel,      // one-hot, one bit per input
  input  logic [WIDTH-1:0]  in0,
  input  logic [WIDTH-1:0]  in1,
  input  logic [WIDTH-1:0]  in2,
  input  logic [WIDTH-1:0]  in3,
  input  logic [WIDTH-1:0]  in4,
  output logic [WIDTH-1:0]  out,
  output logic              out_valid
);

  always_comb begin
    out       = '0;
    out_valid = |sel;
    unique case (1'b1)
      sel[0]:  out = in0;
      sel[1]:  out = in1;
      sel[2]:  out = in2;
      sel[3]:  out = in3;
      sel[4]:  out = in4;
      default: out = '0;
    endcase
  end

endmodule : mux5
