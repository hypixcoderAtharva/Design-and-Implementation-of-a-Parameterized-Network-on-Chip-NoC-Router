// =============================================================================
// noc_pkg.sv
// Shared type/parameter package for the parameterized NoC router project.
// Every RTL and verification file imports this package so that flit format,
// mesh size and port numbering stay consistent across the whole design.
// =============================================================================
package noc_pkg;

  // ---------------------------------------------------------------------
  // Global parameters (edit here to resize the design)
  // ---------------------------------------------------------------------
  parameter int DATA_WIDTH  = 32;   // payload width per flit, bits
  parameter int ADDR_WIDTH  = 4;    // bits per mesh coordinate (max 16 x 16 mesh)
  parameter int MESH_DIM_X  = 4;    // number of routers along X
  parameter int MESH_DIM_Y  = 4;    // number of routers along Y
  parameter int NUM_PORTS   = 5;    // N, E, S, W, L (local)
  parameter int FIFO_DEPTH  = 8;    // input buffer depth per port, flits

  // Width of the verification interface (router_if.sv). Both testbenches
  // must use the SAME value, because the UVM driver/receiver/monitor classes
  // hold a `virtual router_if` handle whose parameterization is part of its
  // type -- a class compiled against router_if#(5) cannot bind to an
  // instance of router_if#(16). Sized to whichever testbench needs more
  // links: NUM_PORTS for the single router, MESH_DIM_X*MESH_DIM_Y for the mesh.
  parameter int MAX_LINKS   = (MESH_DIM_X * MESH_DIM_Y > NUM_PORTS)
                              ? MESH_DIM_X * MESH_DIM_Y : NUM_PORTS;

  // ---------------------------------------------------------------------
  // Physical port enumeration - used as the array index everywhere
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    PORT_N = 3'd0,
    PORT_E = 3'd1,
    PORT_S = 3'd2,
    PORT_W = 3'd3,
    PORT_L = 3'd4
  } port_e;

  // ---------------------------------------------------------------------
  // Flit type. This library injects single-flit packets (FLIT_SINGLE) by
  // default; HEAD/BODY/TAIL are carried in the format for future multi-flit
  // (wormhole) extension without changing the struct.
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_HEAD   = 2'b00,
    FLIT_BODY   = 2'b01,
    FLIT_TAIL   = 2'b10,
    FLIT_SINGLE = 2'b11
  } flit_type_e;

  // ---------------------------------------------------------------------
  // Flit structure - one flit is one beat on a link
  // ---------------------------------------------------------------------
  typedef struct packed {
    logic [ADDR_WIDTH-1:0] dest_x;
    logic [ADDR_WIDTH-1:0] dest_y;
    logic [ADDR_WIDTH-1:0] src_x;
    logic [ADDR_WIDTH-1:0] src_y;
    flit_type_e            flit_type;
    logic [7:0]            seq_id;    // per-source packet id, for scoreboard matching
    logic [DATA_WIDTH-1:0] payload;
  } flit_t;

endpackage : noc_pkg
