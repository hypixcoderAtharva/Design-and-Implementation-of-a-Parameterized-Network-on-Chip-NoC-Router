// =============================================================================
// input_buffer.sv
// -----------------------------------------------------------------------------
// One instance per physical input port. Owns NUM_VCS parallel (fifo +
// route_compute + virtual_channel) lanes, decodes the incoming flit's VC
// tag into a FIFO write-enable, and combinationally offers the
// switch-allocation winner's head-of-line flit (hol_flit) to the crossbar.
//
// va_request/va_req_port/sa_request/sa_req_port/out_vc are flattened,
// NUM_VCS entries wide, so this module's ports stay simple packed vectors
// (no arrays-of-arrays crossing the boundary) -- router_top.sv further
// flattens these across all NUM_PORTS instances before handing them to
// vc_allocator.sv / switch_allocator.sv.
// =============================================================================

module input_buffer
  import noc_pkg::*;
  import router_config_pkg::*;
#(
  parameter logic [X_WIDTH-1:0] MY_X = '0,
  parameter logic [Y_WIDTH-1:0] MY_Y = '0
) (
  input  logic   clk,
  input  logic   rst_n,

  // incoming link from a neighbour router (or NI, for the Local port)
  input  flit_t                 in_flit,
  input  logic                  in_valid,
  input  logic [VC_ID_W-1:0]    in_vc_id,

  output logic [NUM_VCS-1:0]    credit_out,   // sent back upstream

  // VC allocation, flattened one entry per VC
  output logic [NUM_VCS-1:0]            va_request,
  output logic [NUM_VCS*PORT_ID_W-1:0]  va_req_port,
  input  logic [NUM_VCS-1:0]            va_grant,
  input  logic [NUM_VCS*VC_ID_W-1:0]    va_grant_vc,

  // switch allocation, flattened one entry per VC
  output logic [NUM_VCS-1:0]            sa_request,
  output logic [NUM_VCS*PORT_ID_W-1:0]  sa_req_port,
  input  logic [NUM_VCS-1:0]            sa_grant,
  output logic [NUM_VCS*VC_ID_W-1:0]    out_vc,

  // router-wide downstream credit status: NUM_VCS bits per output port
  input  logic [NUM_PORTS*NUM_VCS-1:0]  has_credit,

  // head-of-line flit offered to the crossbar this cycle (valid only when
  // one of this port's VCs won switch allocation)
  output flit_t  hol_flit,
  output logic   hol_valid
);

  logic [NUM_VCS-1:0] wr_en, fifo_full, fifo_empty, rd_en, vc_popped;
  flit_t               fifo_rd_data [NUM_VCS];
  logic [VC_ID_W-1:0]  win_vc_idx;
  logic                win_valid;

  decoder #(.IN_WIDTH(VC_ID_W), .OUT_WIDTH(NUM_VCS)) u_wr_dec (
    .in_idx  (in_vc_id),
    .en      (in_valid),
    .out_vec (wr_en)
  );

  genvar v;
  generate
    for (v = 0; v < NUM_VCS; v++) begin : g_vc

      direction_e            vc_route_port, vc_bound_port;
      logic [VC_ID_W-1:0]     vc_out_vc;
      vc_state_e              vc_state_dbg;
      logic [PORT_ID_W-1:0]   vc_bound_port_idx;
      logic                   vc_has_credit;

      flit_t vc_head_flit;

      fifo #(.WIDTH($bits(flit_t)), .DEPTH(VC_DEPTH)) u_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr_en[v]),
        .wr_data (in_flit),
        .full    (fifo_full[v]),
        .rd_en   (rd_en[v]),
        .rd_data (fifo_rd_data[v]),
        .empty   (fifo_empty[v]),
        .count   ()
      );

      assign vc_head_flit = fifo_rd_data[v];

      route_compute #(.MY_X(MY_X), .MY_Y(MY_Y)) u_rc (
        .dest_x   (vc_head_flit.dest_x),
        .dest_y   (vc_head_flit.dest_y),
        .out_port (vc_route_port)
      );

      assign vc_bound_port_idx = PORT_ID_W'(vc_bound_port);
      assign vc_has_credit     = has_credit[vc_bound_port_idx*NUM_VCS + vc_out_vc];

      virtual_channel u_vc (
        .clk           (clk),
        .rst_n         (rst_n),
        .flit_avail    (!fifo_empty[v]),
        .head_ftype    (vc_head_flit.ftype),
        .route_port    (vc_route_port),
        .va_request    (va_request[v]),
        .va_grant      (va_grant[v]),
        .va_grant_vc   (va_grant_vc[v*VC_ID_W +: VC_ID_W]),
        .sa_request    (sa_request[v]),
        .sa_grant      (sa_grant[v]),
        .vc_has_credit (vc_has_credit),
        .fifo_pop      (rd_en[v]),
        .req_port      (vc_bound_port),
        .out_vc        (vc_out_vc),
        .state         (vc_state_dbg)
      );

      assign va_req_port[v*PORT_ID_W +: PORT_ID_W] = vc_bound_port_idx;
      assign sa_req_port[v*PORT_ID_W +: PORT_ID_W] = vc_bound_port_idx;
      assign out_vc[v*VC_ID_W +: VC_ID_W]          = vc_out_vc;
      assign vc_popped[v] = rd_en[v];
    end
  endgenerate

  encoder #(.IN_WIDTH(NUM_VCS)) u_win_enc (
    .in_vec  (sa_grant),
    .out_idx (win_vc_idx),
    .valid   (win_valid)
  );

  assign hol_flit  = fifo_rd_data[win_vc_idx];
  assign hol_valid = win_valid;

  flow_control u_flow_ctrl (
    .clk        (clk),
    .rst_n      (rst_n),
    .vc_popped  (vc_popped),
    .credit_out (credit_out)
  );

endmodule : input_buffer
