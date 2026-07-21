// =============================================================================
// router_config.sv
// -----------------------------------------------------------------------------
// Global configuration parameters for the parameterized NoC router.
// Every other file in rtl/ imports router_config_pkg so that a single edit
// here re-sizes the whole design consistently.
//
// NOTE: NUM_PORTS is architecturally fixed at 5 (North, South, East, West,
// Local) for this router -- mux5.sv / demux5.sv / crossbar_switch.sv are
// hard-wired for exactly 5 ports to match the standard 2D-mesh topology.
// NUM_VCS, VC_DEPTH, FLIT_WIDTH, X_WIDTH and Y_WIDTH are the parameters
// meant to be tuned per project/testbench.
// =============================================================================

package router_config_pkg;

  parameter int NUM_PORTS  = 5;   // N, S, E, W, Local  (fixed topology width)
  parameter int NUM_VCS    = 4;   // virtual channels per physical port
  parameter int VC_DEPTH   = 4;   // flit-buffer depth per virtual channel
  parameter int FLIT_WIDTH = 32;  // flit payload width, in bits
  parameter int X_WIDTH    = 4;   // mesh X-coordinate width, in bits
  parameter int Y_WIDTH    = 4;   // mesh Y-coordinate width, in bits

  // Derived widths -- do not override directly, they track the params above.
  parameter int VC_ID_W   = (NUM_VCS   > 1) ? $clog2(NUM_VCS)   : 1;
  parameter int PORT_ID_W = (NUM_PORTS > 1) ? $clog2(NUM_PORTS) : 1;
  parameter int CREDIT_W  = $clog2(VC_DEPTH + 1);

endpackage : router_config_pkg