// noc_pkg.sv
// Shared types and parameters for the parameterized NoC router.
// Every other RTL file (and the UVM testbench) imports this package,
// so this is the single place to change flit width, buffer depth,
// or mesh size.

package noc_pkg;

  // ---------------------------------------------------------------
  // Parameters - change these to resize the whole design
  // ---------------------------------------------------------------
  parameter int FLIT_WIDTH   = 32;  // payload width carried by every flit
  parameter int BUFFER_DEPTH = 4;   // input FIFO depth (keep a power of 2)
  parameter int MESH_SIZE_X  = 3;   // number of routers along X
  parameter int MESH_SIZE_Y  = 3;   // number of routers along Y
  parameter int NUM_PORTS    = 5;   // N, E, S, W, Local - fixed for a 2D mesh

  // bits needed to represent a coordinate in either dimension
  parameter int COORD_WIDTH  =
      (MESH_SIZE_X > MESH_SIZE_Y) ? $clog2(MESH_SIZE_X) : $clog2(MESH_SIZE_Y);

  // ---------------------------------------------------------------
  // Flit type (position within a packet)
  // ---------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_HEAD      = 2'b00,  // first flit of a multi-flit packet
    FLIT_BODY      = 2'b01,  // middle flit(s)
    FLIT_TAIL      = 2'b10,  // last flit of a multi-flit packet
    FLIT_HEAD_TAIL = 2'b11   // single-flit packet
  } flit_type_e;

  // ---------------------------------------------------------------
  // Port / direction naming - order matches NUM_PORTS indexing
  // (used directly as array indices, e.g. link_in[PORT_N])
  // ---------------------------------------------------------------
  typedef enum logic [2:0] {
    PORT_N     = 3'd0,
    PORT_E     = 3'd1,
    PORT_S     = 3'd2,
    PORT_W     = 3'd3,
    PORT_LOCAL = 3'd4
  } port_dir_e;

  // ---------------------------------------------------------------
  // Flit format
  //   Total width = 2 (type) + 2*COORD_WIDTH (dest coords) + FLIT_WIDTH
  //   Destination coords only matter on the head flit; body/tail
  //   flits carry payload only, but keep the same struct shape so
  //   the datapath stays uniform.
  // ---------------------------------------------------------------
  typedef struct packed {
    flit_type_e             flit_type;
    logic [COORD_WIDTH-1:0] dest_x;
    logic [COORD_WIDTH-1:0] dest_y;
    logic [FLIT_WIDTH-1:0]  payload;
  } flit_t;

  // ---------------------------------------------------------------
  // Dimension-order (XY) routing - deterministic, deadlock-free.
  // Resolve X fully before Y; when both match, the packet has
  // arrived and should exit on the Local port.
  // ---------------------------------------------------------------
  function automatic port_dir_e xy_route(
      input logic [COORD_WIDTH-1:0] cur_x,
      input logic [COORD_WIDTH-1:0] cur_y,
      input logic [COORD_WIDTH-1:0] dest_x,
      input logic [COORD_WIDTH-1:0] dest_y
  );
    if (dest_x != cur_x)
      return (dest_x > cur_x) ? PORT_E : PORT_W;
    else if (dest_y != cur_y)
      return (dest_y > cur_y) ? PORT_N : PORT_S;
    else
      return PORT_LOCAL;
  endfunction

endpackage : noc_pkg
