// =============================================================================
// demux5.sv
// -----------------------------------------------------------------------------
// Parameterized 1:5 demultiplexer, one-hot select. Used at each crossbar
// input to steer that port's head-of-line flit toward its granted output
// lane; paired with mux5 at each output to collect from the 5 lanes.
// =============================================================================

module demux5 #(
  parameter int WIDTH = 32
) (
  input  logic [4:0]        sel,       // one-hot select
  input  logic [WIDTH-1:0]  in_data,
  input  logic              in_valid,
  output logic [WIDTH-1:0]  out0,
  output logic [WIDTH-1:0]  out1,
  output logic [WIDTH-1:0]  out2,
  output logic [WIDTH-1:0]  out3,
  output logic [WIDTH-1:0]  out4,
  output logic [4:0]        out_valid
);

  assign out0 = in_data;
  assign out1 = in_data;
  assign out2 = in_data;
  assign out3 = in_data;
  assign out4 = in_data;

  assign out_valid = in_valid ? sel : 5'b0;

endmodule : demux5
