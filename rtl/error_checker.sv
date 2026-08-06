// =============================================================================
// error_checker.sv                                                     [ADD]
// Lightweight per-router protocol/error checker, synthesizable so it can be
// left in place in real silicon (not just simulation). Flags:
//   - out-of-bounds destinations (a flit addressed outside the mesh)
//   - sender-side overflow attempts (valid held while the port is not ready)
// and accumulates a sticky error counter for debug/telemetry.
// =============================================================================
module error_checker
  import noc_pkg::*;
(
  input logic clk,
  input logic rst_n,

  input flit_t flit_in   [NUM_PORTS],
  input logic  valid_in  [NUM_PORTS],
  input logic  ready_out [NUM_PORTS],

  output logic                 error_detected,
  output logic [31:0]          error_count,
  output logic [NUM_PORTS-1:0] out_of_bounds_flag,
  output logic [NUM_PORTS-1:0] overflow_flag
);

  logic [NUM_PORTS-1:0] oob_comb, ovf_comb;

  always_comb begin
    for (int i = 0; i < NUM_PORTS; i++) begin
      oob_comb[i] = valid_in[i] &&
                    ((flit_in[i].dest_x >= ADDR_WIDTH'(MESH_DIM_X)) ||
                     (flit_in[i].dest_y >= ADDR_WIDTH'(MESH_DIM_Y)));
      ovf_comb[i] = valid_in[i] && !ready_out[i];   // legal backpressure, flagged for visibility
    end
  end

  assign out_of_bounds_flag = oob_comb;
  assign overflow_flag      = ovf_comb;
  assign error_detected     = |oob_comb;   // an out-of-mesh destination is a genuine protocol error

  // Population count of oob_comb, written as an explicit loop rather than
  // $countones(oob_comb): Vivado 2020.1's synthesizer rejects $countones
  // with a non-constant (runtime signal) argument -- "expression must be
  // constant: first argument to $countones" -- even though it is ordinary,
  // legal SystemVerilog that every simulator accepts. This computes the
  // identical value ($countones is defined as exactly this reduction).
  logic [$clog2(NUM_PORTS+1)-1:0] oob_popcount;
  always_comb begin
    oob_popcount = '0;
    for (int i = 0; i < NUM_PORTS; i++) begin
      if (oob_comb[i]) oob_popcount = oob_popcount + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) error_count <= '0;
    else if (|oob_comb) error_count <= error_count + 32'(oob_popcount);
  end

endmodule : error_checker
