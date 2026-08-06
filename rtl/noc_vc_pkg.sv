// =============================================================================
// noc_vc_pkg.sv                                                        [FIX B1/B2]
// -----------------------------------------------------------------------------
// Type package for the virtual-channel router (Track B).
//
// Track B modules previously imported noc_pkg (Track A's package), which
// caused two problems:
//   1. Both noc_pkg and router_config_pkg export NUM_PORTS, so under wildcard
//      import the name was ambiguous and every Track B module failed to
//      elaborate.
//   2. noc_pkg does not define direction_e, vc_state_e, FLIT_HEAD_TAIL, or a
//      flit_t with a .ftype field -- all of which Track B references.
//
// This package supplies exactly what Track B needs and deliberately does NOT
// re-export NUM_PORTS (that stays owned by router_config_pkg), so the two
// packages compose without ambiguity.
//
// Track A continues to use noc_pkg unchanged.
// =============================================================================

package noc_vc_pkg;

  import router_config_pkg::*;

  // ---------------------------------------------------------------------
  // Output direction. Encoding intentionally matches noc_pkg::port_e
  // (N, E, S, W, Local) so that a mesh built from either router uses the
  // same port index convention.
  // ---------------------------------------------------------------------
  typedef enum logic [2:0] {
    DIR_N     = 3'd0,
    DIR_E     = 3'd1,
    DIR_S     = 3'd2,
    DIR_W     = 3'd3,
    DIR_LOCAL = 3'd4
  } direction_e;

  // ---------------------------------------------------------------------
  // Per-VC control FSM states (virtual_channel.sv)
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    VC_IDLE    = 2'd0,
    VC_ROUTING = 2'd1,
    VC_VA      = 2'd2,
    VC_ACTIVE  = 2'd3
  } vc_state_e;

  // ---------------------------------------------------------------------
  // Flit type. Unlike Track A this carries FLIT_HEAD_TAIL (a complete
  // single-flit packet) because the VC FSM keys packet completion on the
  // tail: both FLIT_TAIL and FLIT_HEAD_TAIL release the VC.
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_HEAD      = 2'b00,
    FLIT_BODY      = 2'b01,
    FLIT_TAIL      = 2'b10,
    FLIT_HEAD_TAIL = 2'b11
  } flit_type_e;

  // ---------------------------------------------------------------------
  // Flit structure. Field is named .ftype (not .flit_type) to match the
  // Track B module sources.
  // ---------------------------------------------------------------------
  typedef struct packed {
    logic [X_WIDTH-1:0]    dest_x;
    logic [Y_WIDTH-1:0]    dest_y;
    logic [X_WIDTH-1:0]    src_x;
    logic [Y_WIDTH-1:0]    src_y;
    flit_type_e            ftype;
    logic [7:0]            seq_id;
    logic [FLIT_WIDTH-1:0] payload;
  } flit_t;

  parameter int FLIT_BITS = $bits(flit_t);

endpackage : noc_vc_pkg
