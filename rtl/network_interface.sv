// =============================================================================
// network_interface.sv                                                 [ADD]
// Network Interface Unit (NIU): adapts a simple PE-facing valid/ready +
// data/destination bus into the router's flit_t format, and unpacks
// received flits back into plain data for the PE. Single-flit packets only
// (payload fits in one flit -- no fragmentation needed at DATA_WIDTH=32).
//
// This module is a standalone, reusable adapter. It is not wired into
// noc_mesh_top.sv by default -- the verification environment talks to each
// router's local port directly at the flit level for simplicity. Instantiate
// this module between a real processing element and a mesh local port
// (local_flit_in/out in noc_mesh_top.sv) for SoC-level integration.
// =============================================================================
module network_interface
  import noc_pkg::*;
#(
  parameter int NODE_X = 0,
  parameter int NODE_Y = 0
)(
  input  logic              clk,
  input  logic              rst_n,

  // ---- PE-facing transmit side ----
  input  logic               tx_valid,
  input  logic [ADDR_WIDTH-1:0] tx_dest_x,
  input  logic [ADDR_WIDTH-1:0] tx_dest_y,
  input  logic [DATA_WIDTH-1:0] tx_data,
  output logic               tx_ready,

  // ---- PE-facing receive side ----
  output logic               rx_valid,
  output logic [DATA_WIDTH-1:0] rx_data,
  output logic [ADDR_WIDTH-1:0] rx_src_x,
  output logic [ADDR_WIDTH-1:0] rx_src_y,
  input  logic               rx_ready,

  // ---- router local-port side ----
  output flit_t out_flit,
  output logic  out_valid,
  input  logic  out_ready,

  input  flit_t in_flit,
  input  logic  in_valid,
  output logic  in_ready
);

  // Free-running per-node sequence counter, one increment per accepted
  // outgoing packet. Combined with (src_x, src_y) this gives every packet
  // injected by this node a unique id for the scoreboard to track.
  logic [7:0] seq_ctr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) seq_ctr <= '0;
    else if (tx_valid && tx_ready) seq_ctr <= seq_ctr + 1'b1;
  end

  // ---- packetize: PE -> flit ----
  assign out_valid         = tx_valid;
  assign tx_ready          = out_ready;
  assign out_flit.dest_x   = tx_dest_x;
  assign out_flit.dest_y   = tx_dest_y;
  assign out_flit.src_x    = NODE_X[ADDR_WIDTH-1:0];
  assign out_flit.src_y    = NODE_Y[ADDR_WIDTH-1:0];
  assign out_flit.flit_type = FLIT_SINGLE;
  assign out_flit.seq_id   = seq_ctr;
  assign out_flit.payload  = tx_data;

  // ---- de-packetize: flit -> PE ----
  assign rx_valid = in_valid;
  assign in_ready = rx_ready;
  assign rx_data  = in_flit.payload;
  assign rx_src_x = in_flit.src_x;
  assign rx_src_y = in_flit.src_y;

endmodule : network_interface
