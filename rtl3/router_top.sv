// =============================================================================
// router_top.sv
// -----------------------------------------------------------------------------
// Top-level 5-port (N/S/E/W/Local) virtual-channel router. Pipeline per
// packet, per VC: Routing (RC) -> VC Allocation (VA) -> Switch Allocation
// (SA) + Switch Traversal (ST, same cycle) -> Link Traversal (LT,
// registered at the output_controller).
//
// External ports are flattened std-logic buses (flit data packed
// NUM_PORTS-wide, valid/credit vectors) rather than noc_if instances or
// unpacked arrays, so this module stays portable across simulators and
// synthesis tools that have uneven support for array-typed / interface-
// typed module ports. See noc_if.sv for how to wire several router_top
// instances together in a mesh testbench.
//
// MY_X / MY_Y are this router's mesh coordinates, used by route_compute
// (via input_buffer) to decide when a packet has arrived (-> DIR_LOCAL).
// =============================================================================

module router_top
  import noc_pkg::*;
  import router_config_pkg::*;
#(
  parameter logic [X_WIDTH-1:0] MY_X = '0,
  parameter logic [Y_WIDTH-1:0] MY_Y = '0
) (
  input  logic clk,
  input  logic rst_n,

  // ---- input links, one per direction (index 0..4 = N,S,E,W,Local) ----
  input  logic [NUM_PORTS*$bits(flit_t)-1:0] in_flit_flat,
  input  logic [NUM_PORTS-1:0]               in_valid,
  input  logic [NUM_PORTS*VC_ID_W-1:0]       in_vc_id_flat,
  output logic [NUM_PORTS*NUM_VCS-1:0]       credit_to_upstream,

  // ---- output links, one per direction ----
  output logic [NUM_PORTS*$bits(flit_t)-1:0] out_flit_flat,
  output logic [NUM_PORTS-1:0]               out_valid,
  input  logic [NUM_PORTS*NUM_VCS-1:0]       credit_from_downstream
);

  localparam int TOTAL_IVCS = NUM_PORTS * NUM_VCS;
  localparam int FW         = $bits(flit_t);

  // -------------------------------------------------------------------
  // Flattened per-input-VC buses shared with the allocators
  // -------------------------------------------------------------------
  logic [TOTAL_IVCS-1:0]            flat_va_request;
  logic [TOTAL_IVCS*PORT_ID_W-1:0]  flat_va_req_port;
  logic [TOTAL_IVCS-1:0]            flat_va_grant;
  logic [TOTAL_IVCS*VC_ID_W-1:0]    flat_va_grant_vc;

  logic [TOTAL_IVCS-1:0]            flat_sa_request;
  logic [TOTAL_IVCS*PORT_ID_W-1:0]  flat_sa_req_port;
  logic [TOTAL_IVCS-1:0]            flat_sa_grant;
  logic [TOTAL_IVCS*VC_ID_W-1:0]    flat_out_vc;

  logic [NUM_PORTS*NUM_VCS-1:0]     flat_has_credit;
  logic [NUM_VCS-1:0]               has_credit_by_port [NUM_PORTS];

  logic [NUM_PORTS*FW-1:0]          hol_flit_flat;
  logic [NUM_PORTS-1:0]             hol_valid;

  logic [NUM_PORTS*NUM_PORTS-1:0]   input_granted_output_flat;
  logic [NUM_PORTS*VC_ID_W-1:0]     xbar_sel_vc_flat;

  logic [NUM_PORTS*FW-1:0]          xbar_out_data_flat;
  logic [NUM_PORTS-1:0]             xbar_out_valid;

  logic [NUM_VCS-1:0] vc_release_by_port [NUM_PORTS];

  // -------------------------------------------------------------------
  // Input side: one input_buffer per direction
  // -------------------------------------------------------------------
  genvar ip;
  generate
    for (ip = 0; ip < NUM_PORTS; ip++) begin : g_ibuf

      logic [VC_ID_W-1:0] in_vc_id_i;
      assign in_vc_id_i = in_vc_id_flat[ip*VC_ID_W +: VC_ID_W];

      input_buffer #(.MY_X(MY_X), .MY_Y(MY_Y)) u_ibuf (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_flit      (in_flit_flat[ip*FW +: FW]),
        .in_valid     (in_valid[ip]),
        .in_vc_id     (in_vc_id_i),
        .credit_out   (credit_to_upstream[ip*NUM_VCS +: NUM_VCS]),

        .va_request   (flat_va_request [ip*NUM_VCS +: NUM_VCS]),
        .va_req_port  (flat_va_req_port[ip*NUM_VCS*PORT_ID_W +: NUM_VCS*PORT_ID_W]),
        .va_grant     (flat_va_grant   [ip*NUM_VCS +: NUM_VCS]),
        .va_grant_vc  (flat_va_grant_vc[ip*NUM_VCS*VC_ID_W +: NUM_VCS*VC_ID_W]),

        .sa_request   (flat_sa_request [ip*NUM_VCS +: NUM_VCS]),
        .sa_req_port  (flat_sa_req_port[ip*NUM_VCS*PORT_ID_W +: NUM_VCS*PORT_ID_W]),
        .sa_grant     (flat_sa_grant   [ip*NUM_VCS +: NUM_VCS]),
        .out_vc       (flat_out_vc     [ip*NUM_VCS*VC_ID_W +: NUM_VCS*VC_ID_W]),

        .has_credit   (flat_has_credit),

        .hol_flit     (hol_flit_flat[ip*FW +: FW]),
        .hol_valid    (hol_valid[ip])
      );
    end
  endgenerate

  // -------------------------------------------------------------------
  // VC allocation: one allocator instance per OUTPUT port
  // -------------------------------------------------------------------
  logic [TOTAL_IVCS-1:0] va_grant_by_port    [NUM_PORTS];
  logic [VC_ID_W-1:0]    va_grant_vc_by_port [NUM_PORTS];

  genvar op, gi;
  generate
    for (op = 0; op < NUM_PORTS; op++) begin : g_va

      logic [TOTAL_IVCS-1:0] req_for_this_port;
      for (gi = 0; gi < TOTAL_IVCS; gi++) begin : g_req_mask
        assign req_for_this_port[gi] =
          flat_va_request[gi] &&
          (flat_va_req_port[gi*PORT_ID_W +: PORT_ID_W] == op[PORT_ID_W-1:0]);
      end

      vc_allocator u_va (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (req_for_this_port),
        .vc_release  (vc_release_by_port[op]),
        .grant       (va_grant_by_port[op]),
        .grant_vc    (va_grant_vc_by_port[op]),
        .grant_valid ()
      );
    end
  endgenerate

  integer gi2, op2;
  always_comb begin
    flat_va_grant    = '0;
    flat_va_grant_vc = '0;
    for (gi2 = 0; gi2 < TOTAL_IVCS; gi2++) begin
      for (op2 = 0; op2 < NUM_PORTS; op2++) begin
        if (va_grant_by_port[op2][gi2]) begin
          flat_va_grant[gi2] = 1'b1;
          flat_va_grant_vc[gi2*VC_ID_W +: VC_ID_W] = va_grant_vc_by_port[op2];
        end
      end
    end
  end

  // -------------------------------------------------------------------
  // Switch allocation (global) + crossbar traversal
  // -------------------------------------------------------------------
  switch_allocator u_sa (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .sa_request                  (flat_sa_request),
    .sa_req_port                 (flat_sa_req_port),
    .sa_out_vc                   (flat_out_vc),
    .sa_grant                    (flat_sa_grant),
    .input_granted_output_flat   (input_granted_output_flat),
    .xbar_sel_vc_flat            (xbar_sel_vc_flat)
  );

  crossbar_switch u_xbar (
    .in_data_flat                (hol_flit_flat),
    .input_granted_output_flat   (input_granted_output_flat),
    .out_data_flat                (xbar_out_data_flat),
    .out_valid                    (xbar_out_valid)
  );

  // -------------------------------------------------------------------
  // Output side: one output_controller per direction
  // -------------------------------------------------------------------
  genvar op3;
  generate
    for (op3 = 0; op3 < NUM_PORTS; op3++) begin : g_octrl

      output_controller u_octrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .xbar_data   (xbar_out_data_flat[op3*FW +: FW]),
        .xbar_valid  (xbar_out_valid[op3]),
        .xbar_vc     (xbar_sel_vc_flat[op3*VC_ID_W +: VC_ID_W]),
        .credit_in   (credit_from_downstream[op3*NUM_VCS +: NUM_VCS]),
        .has_credit  (has_credit_by_port[op3]),
        .vc_release  (vc_release_by_port[op3]),
        .link_flit   (out_flit_flat[op3*FW +: FW]),
        .link_valid  (out_valid[op3])
      );

      assign flat_has_credit[op3*NUM_VCS +: NUM_VCS] = has_credit_by_port[op3];
    end
  endgenerate

  // -------------------------------------------------------------------
  // Verification-only monitor
  // -------------------------------------------------------------------
  logic [NUM_PORTS*NUM_VCS-1:0] mon_has_credit_flat;
  genvar mp;
  generate
    for (mp = 0; mp < NUM_PORTS; mp++) begin : g_mon_credit
      assign mon_has_credit_flat[mp*NUM_VCS +: NUM_VCS] = has_credit_by_port[mp];
    end
  endgenerate

  router_monitor #(.ROUTER_NAME("router")) u_mon (
    .clk              (clk),
    .rst_n            (rst_n),
    .link_flit_flat   (out_flit_flat),
    .link_valid       (out_valid),
    .has_credit_flat  (mon_has_credit_flat)
  );

endmodule : router_top
