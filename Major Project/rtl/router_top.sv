// router_top.sv
// Single 5-port (N/E/S/W/Local) wormhole router.
// Pipeline per input port: BW (input_buffer) -> RC (route_compute)
// -> SA (rr_arbiter, one per output) -> ST (crossbar_sw).
// ROUTER_X / ROUTER_Y are this router's coordinates in the mesh,
// used by route_compute for XY routing decisions.

module router_top
  import noc_pkg::*;
#(
    parameter logic [COORD_WIDTH-1:0] ROUTER_X = 0,
    parameter logic [COORD_WIDTH-1:0] ROUTER_Y = 0
) (
    input logic clk,
    input logic rst_n,

    noc_if.slave  link_in [NUM_PORTS],
    noc_if.master link_out[NUM_PORTS]
);

  // ---- per-input signals ----
  logic      ibuf_rd_valid[NUM_PORTS];
  logic      ibuf_rd_ready[NUM_PORTS];
  flit_t     ibuf_rd_flit [NUM_PORTS];

  port_dir_e rc_out_port  [NUM_PORTS];

  logic [NUM_PORTS-1:0] pc_arb_req  [NUM_PORTS];  // pc_arb_req[i]    : one-hot over output ports
  logic [NUM_PORTS-1:0] pc_arb_grant[NUM_PORTS];  // pc_arb_grant[i][j]: arbiter j grants input i
  logic                 pc_release  [NUM_PORTS];
  logic                 pc_xbar_valid[NUM_PORTS];
  flit_t                pc_xbar_flit [NUM_PORTS];
  port_dir_e             pc_sel_port [NUM_PORTS];
  logic                  pc_xbar_ready[NUM_PORTS];

  // ---- per-output arbiter signals ----
  logic [NUM_PORTS-1:0] arb_req_in    [NUM_PORTS];  // arb_req_in[j][i]
  logic [NUM_PORTS-1:0] arb_grant_out [NUM_PORTS];  // arb_grant_out[j][i]
  logic                 arb_release_in[NUM_PORTS];

  // ---- crossbar output ----
  flit_t xbar_out_flit [NUM_PORTS];
  logic  xbar_out_valid[NUM_PORTS];

  genvar gi, gj;

  // =================================================================
  // per-input pipeline: BW -> RC -> port FSM (SA request / ST drive)
  // =================================================================
  generate
    for (gi = 0; gi < NUM_PORTS; gi++) begin : g_input

      input_buffer u_ibuf (
          .clk     (clk),
          .rst_n   (rst_n),
          .wr_valid(link_in[gi].valid),
          .wr_ready(link_in[gi].ready),
          .wr_flit (link_in[gi].flit),
          .rd_valid(ibuf_rd_valid[gi]),
          .rd_ready(ibuf_rd_ready[gi]),
          .rd_flit (ibuf_rd_flit[gi])
      );

      route_compute #(
          .ROUTER_X(ROUTER_X),
          .ROUTER_Y(ROUTER_Y)
      ) u_rc (
          .flit_in (ibuf_rd_flit[gi]),
          .is_head (ibuf_rd_valid[gi] &&
                     (ibuf_rd_flit[gi].flit_type == FLIT_HEAD ||
                      ibuf_rd_flit[gi].flit_type == FLIT_HEAD_TAIL)),
          .out_port(rc_out_port[gi])
      );

      port_ctrl u_pc (
          .clk          (clk),
          .rst_n        (rst_n),
          .buf_valid    (ibuf_rd_valid[gi]),
          .buf_ready    (ibuf_rd_ready[gi]),
          .buf_flit     (ibuf_rd_flit[gi]),
          .route_port_in(rc_out_port[gi]),
          .arb_req      (pc_arb_req[gi]),
          .arb_grant    (pc_arb_grant[gi]),
          .release_o    (pc_release[gi]),
          .xbar_valid   (pc_xbar_valid[gi]),
          .xbar_flit    (pc_xbar_flit[gi]),
          .xbar_sel_port(pc_sel_port[gi]),
          .xbar_ready   (pc_xbar_ready[gi])
      );

    end
  endgenerate

  // =================================================================
  // request / grant / release matrix transpose between the NUM_PORTS
  // inputs and the NUM_PORTS output arbiters
  // =================================================================
always_comb begin
    for (int j = 0; j < NUM_PORTS; j++) begin
        arb_release_in[j] = 1'b0;

        for (int i = 0; i < NUM_PORTS; i++) begin
            arb_req_in[j][i] = pc_arb_req[i][j];

            if (pc_sel_port[i] == port_dir_e'(j) && pc_release[i])
                arb_release_in[j] = 1'b1;
        end
    end

    for (int i = 0; i < NUM_PORTS; i++) begin
        pc_arb_grant[i] = '0;

        for (int j = 0; j < NUM_PORTS; j++)
            pc_arb_grant[i][j] = arb_grant_out[j][i];

        case (pc_sel_port[i])
            PORT_N : pc_xbar_ready[i] = link_out[PORT_N].ready;
            PORT_E  : pc_xbar_ready[i] = link_out[PORT_E].ready;
            PORT_S : pc_xbar_ready[i] = link_out[PORT_S].ready;
            PORT_W  : pc_xbar_ready[i] = link_out[PORT_W].ready;
            PORT_LOCAL : pc_xbar_ready[i] = link_out[PORT_LOCAL].ready;
            default    : pc_xbar_ready[i] = 1'b0;
        endcase
    end
end
  // =================================================================
  // one locking round-robin arbiter per output port (SA stage)
  // =================================================================
  generate
    for (gj = 0; gj < NUM_PORTS; gj++) begin : g_arb
      rr_arbiter u_arb (
          .clk         (clk),
          .rst_n       (rst_n),
          .req         (arb_req_in[gj]),
          .release_hold(arb_release_in[gj]),
          .grant       (arb_grant_out[gj]),
          .grant_valid ()  // unused at this level
      );
    end
  endgenerate

  // =================================================================
  // crossbar (ST stage) and output link drive
  // =================================================================
  crossbar_sw u_xbar (
      .in_flit  (pc_xbar_flit),
      .in_valid (pc_xbar_valid),
      .sel      (arb_grant_out),
      .out_flit (xbar_out_flit),
      .out_valid(xbar_out_valid)
  );

  generate
    for (gj = 0; gj < NUM_PORTS; gj++) begin : g_outlink
      assign link_out[gj].valid = xbar_out_valid[gj];
      assign link_out[gj].flit  = xbar_out_flit[gj];
    end
  endgenerate

endmodule : router_top
