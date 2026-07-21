// =============================================================================
// vc_allocator.sv
// -----------------------------------------------------------------------------
// Virtual-channel allocator for ONE output port. router_top.sv instantiates
// five of these (one per output port) via generate, each seeing the flat
// "wants this output port" request bit of every input VC in the router.
//
// Maintains a free-VC bitmap for its output port (an output VC is "free"
// once its previous packet's tail flit has been released) and hands the
// lowest-index free VC to the round-robin winner among competing input
// VCs. TOTAL_IVCS = NUM_PORTS * NUM_VCS is the total number of input VCs
// in the whole router.
// =============================================================================

module vc_allocator
  import noc_pkg::*;
  import router_config_pkg::*;
#(
  parameter int TOTAL_IVCS = NUM_PORTS * NUM_VCS
) (
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic [TOTAL_IVCS-1:0]  req,          // bit i: input VC i wants this port
  input  logic [NUM_VCS-1:0]     vc_release,    // pulsed when an output VC frees up

  output logic [TOTAL_IVCS-1:0]  grant,         // one-hot winner, if any
  output logic [VC_ID_W-1:0]     grant_vc,      // output VC handed to the winner
  output logic                   grant_valid
);

  logic [NUM_VCS-1:0] vc_free_q;
  logic [VC_ID_W-1:0] free_vc_idx;
  logic                free_vc_valid;
  logic [NUM_VCS-1:0]  consumed_mask;

  encoder #(.IN_WIDTH(NUM_VCS)) u_free_pick (
    .in_vec  (vc_free_q),
    .out_idx (free_vc_idx),
    .valid   (free_vc_valid)
  );

  decoder #(.IN_WIDTH(VC_ID_W), .OUT_WIDTH(NUM_VCS)) u_consumed (
    .in_idx  (free_vc_idx),
    .en      (grant_valid),
    .out_vec (consumed_mask)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) vc_free_q <= '1;
    else        vc_free_q <= (vc_free_q | vc_release) & ~consumed_mask;
  end

  rr_arbiter #(.WIDTH(TOTAL_IVCS)) u_va_arb (
    .clk         (clk),
    .rst_n       (rst_n),
    .req         (req & {TOTAL_IVCS{free_vc_valid}}),
    .advance     (1'b1),
    .grant       (grant),
    .grant_valid (grant_valid)
  );

  assign grant_vc = free_vc_idx;

endmodule : vc_allocator