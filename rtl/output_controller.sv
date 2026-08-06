// =============================================================================
// output_controller.sv
// -----------------------------------------------------------------------------
// Drives one output link. Registers the crossbar's winning flit onto the
// link each cycle (link traversal), tracks downstream credits via
// credit_manager.sv, and pulses vc_release for vc_allocator.sv once a
// tail flit for a given output VC has gone out (freeing that VC for the
// next packet). One instance per output port, instantiated in
// router_top.sv.
// =============================================================================

module output_controller
  import noc_vc_pkg::*;
  import router_config_pkg::*;
(
  input  logic    clk,
  input  logic    rst_n,

  // from the crossbar, for this output port
  input  flit_t                xbar_data,
  input  logic                 xbar_valid,
  input  logic [VC_ID_W-1:0]   xbar_vc,

  // credit-based flow control with the downstream neighbour
  input  logic [NUM_VCS-1:0]   credit_in,
  output logic [NUM_VCS-1:0]   has_credit,

  // pulsed for one cycle per VC whose packet just finished (tail sent)
  output logic [NUM_VCS-1:0]   vc_release,

  // registered link outputs
  output flit_t   link_flit,
  output logic    link_valid
);

  logic [NUM_VCS-1:0] consume;
  assign consume = xbar_valid ? (NUM_VCS'(1) << xbar_vc) : '0;

  credit_manager #(.NUM_VCS(NUM_VCS), .VC_DEPTH(VC_DEPTH)) u_credit (
    .clk        (clk),
    .rst_n      (rst_n),
    .consume    (consume),
    .credit_in  (credit_in),
    .has_credit (has_credit)
  );

  logic [NUM_VCS-1:0] release_comb;
  always_comb begin
    release_comb = '0;
    if (xbar_valid &&
        (xbar_data.ftype == FLIT_TAIL || xbar_data.ftype == FLIT_HEAD_TAIL)) begin
      release_comb[xbar_vc] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      link_flit  <= '0;
      link_valid <= 1'b0;
      vc_release <= '0;
    end else begin
      link_flit  <= xbar_data;
      link_valid <= xbar_valid;
      vc_release <= release_comb;
    end
  end

endmodule : output_controller
