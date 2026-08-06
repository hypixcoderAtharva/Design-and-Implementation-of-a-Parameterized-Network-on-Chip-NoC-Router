// =============================================================================
// router_top.sv                                                        [FIX B5]
// -----------------------------------------------------------------------------
// Integrating top level for the virtual-channel router (Track B). This file
// was referenced by six other Track B sources but had never been written, so
// none of those modules had ever been elaborated.
//
// Instantiates and wires:
//     NUM_PORTS x input_buffer       (one per input port, NUM_VCS lanes each)
//     NUM_PORTS x vc_allocator       (one per output port)
//             1 x switch_allocator   (whole router, separable two-stage)
//             1 x crossbar_switch    (whole router, demux5 -> mux5)
//     NUM_PORTS x output_controller  (one per output port, incl. credit_manager)
//
// All module-boundary buses are flattened packed vectors rather than unpacked
// arrays, matching the convention the rest of Track B already uses for
// simulator/synthesis portability.
//
// Link protocol (credit-based, no ready signal):
//     in_flit / in_valid / in_vc_id      arriving flit + its VC tag
//     in_credit_out                      credits returned to the upstream router
//     out_flit / out_valid / out_vc      departing flit + its output VC
//     out_credit_in                      credits arriving from the downstream router
// =============================================================================

module router_top
  import noc_vc_pkg::*;
  import router_config_pkg::*;
#(
  parameter logic [X_WIDTH-1:0] MY_X = '0,
  parameter logic [Y_WIDTH-1:0] MY_Y = '0
)(
  input  logic clk,
  input  logic rst_n,

  // ---- incoming links, one slice per input port ----
  input  logic [NUM_PORTS*FLIT_BITS-1:0] in_flit_flat,
  input  logic [NUM_PORTS-1:0]           in_valid,
  input  logic [NUM_PORTS*VC_ID_W-1:0]   in_vc_id_flat,
  output logic [NUM_PORTS*NUM_VCS-1:0]   in_credit_out_flat,

  // ---- outgoing links, one slice per output port ----
  output logic [NUM_PORTS*FLIT_BITS-1:0] out_flit_flat,
  output logic [NUM_PORTS-1:0]           out_valid,
  output logic [NUM_PORTS*VC_ID_W-1:0]   out_vc_flat,
  input  logic [NUM_PORTS*NUM_VCS-1:0]   out_credit_in_flat
);

  localparam int TOTAL_IVCS = NUM_PORTS * NUM_VCS;

  // =====================================================================
  // Per-input-port nets (unpacked here, flattened where they cross into
  // the allocators)
  // =====================================================================
  logic [NUM_VCS-1:0]           ib_va_request  [NUM_PORTS];
  logic [NUM_VCS*PORT_ID_W-1:0] ib_va_req_port [NUM_PORTS];
  logic [NUM_VCS-1:0]           ib_va_grant    [NUM_PORTS];
  logic [NUM_VCS*VC_ID_W-1:0]   ib_va_grant_vc [NUM_PORTS];

  logic [NUM_VCS-1:0]           ib_sa_request  [NUM_PORTS];
  logic [NUM_VCS*PORT_ID_W-1:0] ib_sa_req_port [NUM_PORTS];
  logic [NUM_VCS-1:0]           ib_sa_grant    [NUM_PORTS];
  logic [NUM_VCS*VC_ID_W-1:0]   ib_out_vc      [NUM_PORTS];

  flit_t                        ib_hol_flit    [NUM_PORTS];
  logic                         ib_hol_valid   [NUM_PORTS];

  // Router-wide credit status, NUM_VCS bits per output port. Broadcast to
  // every input buffer so any VC can test the output it is bound to.
  logic [NUM_PORTS*NUM_VCS-1:0] has_credit_bus;

  // =====================================================================
  // Input buffers
  // =====================================================================
  genvar ip;
  generate
    for (ip = 0; ip < NUM_PORTS; ip++) begin : g_input_buffer

      input_buffer #(.MY_X(MY_X), .MY_Y(MY_Y)) u_ib (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_flit     (flit_t'(in_flit_flat[ip*FLIT_BITS +: FLIT_BITS])),
        .in_valid    (in_valid[ip]),
        .in_vc_id    (in_vc_id_flat[ip*VC_ID_W +: VC_ID_W]),
        .credit_out  (in_credit_out_flat[ip*NUM_VCS +: NUM_VCS]),

        .va_request  (ib_va_request[ip]),
        .va_req_port (ib_va_req_port[ip]),
        .va_grant    (ib_va_grant[ip]),
        .va_grant_vc (ib_va_grant_vc[ip]),

        .sa_request  (ib_sa_request[ip]),
        .sa_req_port (ib_sa_req_port[ip]),
        .sa_grant    (ib_sa_grant[ip]),
        .out_vc      (ib_out_vc[ip]),

        .has_credit  (has_credit_bus),

        .hol_flit    (ib_hol_flit[ip]),
        .hol_valid   (ib_hol_valid[ip])
      );

    end
  endgenerate

  // =====================================================================
  // Flatten per-port buses into router-wide TOTAL_IVCS buses
  // =====================================================================
  logic [TOTAL_IVCS-1:0]           va_request_flat;
  logic [TOTAL_IVCS*PORT_ID_W-1:0] va_req_port_flat;
  logic [TOTAL_IVCS-1:0]           va_grant_flat;
  logic [TOTAL_IVCS*VC_ID_W-1:0]   va_grant_vc_flat;

  logic [TOTAL_IVCS-1:0]           sa_request_flat;
  logic [TOTAL_IVCS*PORT_ID_W-1:0] sa_req_port_flat;
  logic [TOTAL_IVCS*VC_ID_W-1:0]   sa_out_vc_flat;
  logic [TOTAL_IVCS-1:0]           sa_grant_flat;

  generate
    for (ip = 0; ip < NUM_PORTS; ip++) begin : g_flatten
      assign va_request_flat [ip*NUM_VCS +: NUM_VCS]                       = ib_va_request[ip];
      assign va_req_port_flat[ip*NUM_VCS*PORT_ID_W +: NUM_VCS*PORT_ID_W]   = ib_va_req_port[ip];
      assign ib_va_grant[ip]                                               = va_grant_flat[ip*NUM_VCS +: NUM_VCS];
      assign ib_va_grant_vc[ip]                                            = va_grant_vc_flat[ip*NUM_VCS*VC_ID_W +: NUM_VCS*VC_ID_W];

      assign sa_request_flat [ip*NUM_VCS +: NUM_VCS]                       = ib_sa_request[ip];
      assign sa_req_port_flat[ip*NUM_VCS*PORT_ID_W +: NUM_VCS*PORT_ID_W]   = ib_sa_req_port[ip];
      assign sa_out_vc_flat  [ip*NUM_VCS*VC_ID_W   +: NUM_VCS*VC_ID_W]     = ib_out_vc[ip];
      assign ib_sa_grant[ip]                                               = sa_grant_flat[ip*NUM_VCS +: NUM_VCS];
    end
  endgenerate

  // =====================================================================
  // VC allocation: one allocator per OUTPUT port.
  //
  // Each allocator sees a "does input VC i want me?" bit for every input VC
  // in the router, derived from the flat VA request plus the port index that
  // VC is asking for.
  // =====================================================================
  logic [TOTAL_IVCS-1:0] vca_req      [NUM_PORTS];
  logic [TOTAL_IVCS-1:0] vca_grant    [NUM_PORTS];
  logic [VC_ID_W-1:0]    vca_grant_vc [NUM_PORTS];
  logic                  vca_valid    [NUM_PORTS];
  logic [NUM_VCS-1:0]    oc_vc_release[NUM_PORTS];

  genvar op, iv;
  generate
    for (op = 0; op < NUM_PORTS; op++) begin : g_vca_req
      for (iv = 0; iv < TOTAL_IVCS; iv++) begin : g_vca_req_bit
        assign vca_req[op][iv] = va_request_flat[iv] &&
               (va_req_port_flat[iv*PORT_ID_W +: PORT_ID_W] == PORT_ID_W'(op));
      end
    end

    for (op = 0; op < NUM_PORTS; op++) begin : g_vca
      vc_allocator #(.TOTAL_IVCS(TOTAL_IVCS)) u_vca (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (vca_req[op]),
        .vc_release  (oc_vc_release[op]),
        .grant       (vca_grant[op]),
        .grant_vc    (vca_grant_vc[op]),
        .grant_valid (vca_valid[op])
      );
    end
  endgenerate

  // Collapse the per-output-port VA grants back onto the flat per-input-VC
  // bus. A VC requests exactly one output port, so at most one allocator can
  // grant any given VC.
  always_comb begin
    va_grant_flat    = '0;
    va_grant_vc_flat = '0;
    for (int i = 0; i < TOTAL_IVCS; i++) begin
      for (int o = 0; o < NUM_PORTS; o++) begin
        if (vca_grant[o][i]) begin
          va_grant_flat[i]                        = 1'b1;
          va_grant_vc_flat[i*VC_ID_W +: VC_ID_W]  = vca_grant_vc[o];
        end
      end
    end
  end

  // =====================================================================
  // Switch allocation (separable two-stage), one for the whole router
  // =====================================================================
  logic [NUM_PORTS*NUM_PORTS-1:0] input_granted_output_flat;
  logic [NUM_PORTS*VC_ID_W-1:0]   xbar_sel_vc_flat;

  switch_allocator #(.TOTAL_IVCS(TOTAL_IVCS)) u_sa (
    .clk                       (clk),
    .rst_n                     (rst_n),
    .sa_request                (sa_request_flat),
    .sa_req_port               (sa_req_port_flat),
    .sa_out_vc                 (sa_out_vc_flat),
    .sa_grant                  (sa_grant_flat),
    .input_granted_output_flat (input_granted_output_flat),
    .xbar_sel_vc_flat          (xbar_sel_vc_flat)
  );

  // =====================================================================
  // Crossbar
  // =====================================================================
  logic [NUM_PORTS*FLIT_BITS-1:0] xbar_in_flat;
  logic [NUM_PORTS*FLIT_BITS-1:0] xbar_out_flat;
  logic [NUM_PORTS-1:0]           xbar_out_valid;

  generate
    for (ip = 0; ip < NUM_PORTS; ip++) begin : g_xbar_in
      assign xbar_in_flat[ip*FLIT_BITS +: FLIT_BITS] = ib_hol_flit[ip];
    end
  endgenerate

  crossbar_switch u_xbar (
    .in_data_flat              (xbar_in_flat),
    .input_granted_output_flat (input_granted_output_flat),
    .out_data_flat             (xbar_out_flat),
    .out_valid                 (xbar_out_valid)
  );

  // =====================================================================
  // Output controllers (link register + credit_manager + VC release)
  // =====================================================================
  generate
    for (op = 0; op < NUM_PORTS; op++) begin : g_oc

      flit_t oc_link_flit;
      logic  oc_link_valid;

      output_controller u_oc (
        .clk        (clk),
        .rst_n      (rst_n),
        .xbar_data  (flit_t'(xbar_out_flat[op*FLIT_BITS +: FLIT_BITS])),
        .xbar_valid (xbar_out_valid[op]),
        .xbar_vc    (xbar_sel_vc_flat[op*VC_ID_W +: VC_ID_W]),
        .credit_in  (out_credit_in_flat[op*NUM_VCS +: NUM_VCS]),
        .has_credit (has_credit_bus[op*NUM_VCS +: NUM_VCS]),
        .vc_release (oc_vc_release[op]),
        .link_flit  (oc_link_flit),
        .link_valid (oc_link_valid)
      );

      assign out_flit_flat[op*FLIT_BITS +: FLIT_BITS] = oc_link_flit;
      assign out_valid[op]                            = oc_link_valid;
    end
  endgenerate

  // The VC a flit went out on, registered alongside the link so it stays
  // aligned with out_flit / out_valid for downstream credit accounting.
  logic [NUM_PORTS*VC_ID_W-1:0] out_vc_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_vc_q <= '0;
    else        out_vc_q <= xbar_sel_vc_flat;
  end
  assign out_vc_flat = out_vc_q;

endmodule : router_top
