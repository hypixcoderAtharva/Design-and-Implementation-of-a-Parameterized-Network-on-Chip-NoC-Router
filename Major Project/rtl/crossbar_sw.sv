// crossbar_sw.sv
// Mux-based NxN crossbar - the "ST" (switch traversal) pipeline stage.
// sel[o] is the one-hot grant vector for output o (from that output's
// rr_arbiter): sel[o][i] = 1 means input i currently owns output o.

module crossbar_sw
  import noc_pkg::*;
#(
    parameter int NUM_PORTS_L = NUM_PORTS
) (
    input  flit_t              in_flit  [NUM_PORTS_L],
    input  logic               in_valid [NUM_PORTS_L],
    input  logic [NUM_PORTS_L-1:0] sel  [NUM_PORTS_L],
    output flit_t              out_flit [NUM_PORTS_L],
    output logic               out_valid[NUM_PORTS_L]
);

  always_comb begin
    for (int o = 0; o < NUM_PORTS_L; o++) begin
      out_flit[o]  = '0;
      out_valid[o] = 1'b0;
      for (int i = 0; i < NUM_PORTS_L; i++) begin
        if (sel[o][i]) begin
          out_flit[o]  = in_flit[i];
          out_valid[o] = in_valid[i];
        end
      end
    end
  end

endmodule : crossbar_sw
