// =============================================================================
// router.sv
// Core 5-port (N, E, S, W, L) input-buffered NoC router with dimension-order
// (XY) routing and per-output round-robin arbitration.
//
// This file was not in your "Add" list, meaning it likely already exists in
// your project. It is re-created here from scratch (I do not have your
// original implementation) so that this whole package is self-contained and
// consistent. If you already have a router.sv, drop this one and keep yours
// -- just make sure the port list below matches what network_interface.sv,
// noc_mesh_top.sv and the verification environment expect.
//
// Protocol: simple valid/ready handshake per port, one flit per port per
// cycle. Each router coordinate (ROUTER_X, ROUTER_Y) is set at instantiation
// time by noc_mesh_top.sv.
// =============================================================================
module router
  import noc_pkg::*;
#(
  parameter int ROUTER_X = 0,
  parameter int ROUTER_Y = 0
)(
  input  logic  clk,
  input  logic  rst_n,

  input  flit_t flit_in   [NUM_PORTS],
  input  logic  valid_in  [NUM_PORTS],
  output logic  ready_out [NUM_PORTS],

  output flit_t flit_out  [NUM_PORTS],
  output logic  valid_out [NUM_PORTS],
  input  logic  ready_in  [NUM_PORTS]
);

  // ---------------------------------------------------------------------
  // Per-input FIFO buffers
  // ---------------------------------------------------------------------
  logic  fifo_wr_en   [NUM_PORTS];
  logic  fifo_full    [NUM_PORTS];
  logic  fifo_rd_en   [NUM_PORTS];
  logic  fifo_empty   [NUM_PORTS];
  flit_t fifo_rd_data [NUM_PORTS];

  genvar gi;
  generate
    for (gi = 0; gi < NUM_PORTS; gi++) begin : g_fifo
      fifo_buffer #(
        .WIDTH ($bits(flit_t)),
        .DEPTH (FIFO_DEPTH)
      ) u_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (fifo_wr_en[gi]),
        .wr_data (flit_in[gi]),
        .full    (fifo_full[gi]),
        .rd_en   (fifo_rd_en[gi]),
        .rd_data (fifo_rd_data[gi]),
        .empty   (fifo_empty[gi])
      );

      assign fifo_wr_en[gi] = valid_in[gi] && !fifo_full[gi];
      assign ready_out[gi]  = !fifo_full[gi];
    end
  endgenerate

  // ---------------------------------------------------------------------
  // XY routing decision for the flit currently at the head of each FIFO
  // ---------------------------------------------------------------------
  function automatic port_e xy_route(flit_t f);
    if (f.dest_x != ROUTER_X[ADDR_WIDTH-1:0]) begin
      xy_route = (f.dest_x > ROUTER_X[ADDR_WIDTH-1:0]) ? PORT_E : PORT_W;
    end else if (f.dest_y != ROUTER_Y[ADDR_WIDTH-1:0]) begin
      xy_route = (f.dest_y > ROUTER_Y[ADDR_WIDTH-1:0]) ? PORT_N : PORT_S;
    end else begin
      xy_route = PORT_L;
    end
  endfunction

  port_e route_port [NUM_PORTS];
  generate
    for (gi = 0; gi < NUM_PORTS; gi++) begin : g_route
      assign route_port[gi] = xy_route(fifo_rd_data[gi]);
    end
  endgenerate

  // ---------------------------------------------------------------------
  // Per-output arbitration: req_matrix[o][i] = input i wants output o
  // ---------------------------------------------------------------------
  logic [NUM_PORTS-1:0] req_matrix   [NUM_PORTS];
  logic [NUM_PORTS-1:0] grant_matrix [NUM_PORTS];

  genvar go, gj;
  generate
    for (go = 0; go < NUM_PORTS; go++) begin : g_out
      for (gj = 0; gj < NUM_PORTS; gj++) begin : g_in
        assign req_matrix[go][gj] = !fifo_empty[gj] &&
                                     (route_port[gj] == port_e'(go)) &&
                                     ready_in[go];
      end

      rr_arbiter #(.WIDTH(NUM_PORTS)) u_arb (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (req_matrix[go]),
        .advance     (1'b1),
        .grant       (grant_matrix[go]),
        .grant_valid ()
      );

      always_comb begin
        valid_out[go] = |grant_matrix[go];
        flit_out[go]  = '0;
        for (int k = 0; k < NUM_PORTS; k++) begin
          if (grant_matrix[go][k]) flit_out[go] = fifo_rd_data[k];
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------
  // An input FIFO pops only when it won arbitration for its requested output
  // ---------------------------------------------------------------------
  generate
    for (gi = 0; gi < NUM_PORTS; gi++) begin : g_pop
      assign fifo_rd_en[gi] = !fifo_empty[gi] && grant_matrix[int'(route_port[gi])][gi];
    end
  endgenerate

endmodule : router
