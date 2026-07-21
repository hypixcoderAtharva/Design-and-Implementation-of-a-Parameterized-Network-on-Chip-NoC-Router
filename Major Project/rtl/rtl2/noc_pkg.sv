// =============================================================================
// noc_pkg.sv
// -----------------------------------------------------------------------------
// Shared enums, typedefs and the flit structure used across the router.
// Depends on router_config_pkg -- compile router_config.sv first (see
// filelist.f).
// =============================================================================

package noc_pkg;
  import router_config_pkg::*;

  // ---------------------------------------------------------------------
  // Direction / port identifiers
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    DIR_N     = 3'd0,
    DIR_S     = 3'd1,
    DIR_E     = 3'd2,
    DIR_W     = 3'd3,
    DIR_LOCAL = 3'd4
  } direction_e;

  // ---------------------------------------------------------------------
  // Flit type
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_HEAD      = 2'b00,
    FLIT_BODY      = 2'b01,
    FLIT_TAIL      = 2'b10,
    FLIT_HEAD_TAIL = 2'b11   // single-flit packet
  } flit_type_e;

  // ---------------------------------------------------------------------
  // Per-VC pipeline state (RC -> VA -> SA/ST, repeated per flit until tail)
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    VC_IDLE,     // waiting for a head flit
    VC_ROUTING,  // route_compute evaluating the header this cycle
    VC_VA,       // requesting an output VC from vc_allocator
    VC_ACTIVE    // holds an output VC, requesting switch traversal per flit
  } vc_state_e;

  // ---------------------------------------------------------------------
  // Flit structure
  // ---------------------------------------------------------------------
  typedef struct packed {
    flit_type_e            ftype;
    logic [VC_ID_W-1:0]     vc_id;    // source-side VC tag on the wire
    logic [X_WIDTH-1:0]     dest_x;
    logic [Y_WIDTH-1:0]     dest_y;
    logic [FLIT_WIDTH-1:0]  payload;
  } flit_t;

endpackage : noc_pkg