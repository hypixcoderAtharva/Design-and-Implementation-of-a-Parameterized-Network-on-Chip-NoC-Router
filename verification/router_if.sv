// =============================================================================
// router_if.sv
// Verification interface bundling one router's worth of flit-level link
// signals. Parameterized by NUM_LINKS so the SAME interface (and the same
// driver/receiver/monitor classes) can bind to:
//   - a single router's 5 physical ports  (tb_router.sv, NUM_LINKS = 5)
//   - a mesh's local ports, one per node  (tb_noc_mesh_top.sv, NUM_LINKS = NX*NY)
// Not in the requested file list, but required as the virtual-interface
// type used by driver.sv / receiver.sv / router_monitor.sv / router_assertions.sv.
// =============================================================================
interface router_if
  import noc_pkg::*;
#(
  // Defaults to MAX_LINKS so that the virtual-interface type held by the
  // driver/receiver/monitor classes matches BOTH testbench instantiations.
  // Previously this defaulted to NUM_PORTS (5), which meant the classes
  // could only ever bind to tb_router -- tb_noc_mesh_top instantiates
  // router_if#(16) and every UVM run on the mesh died at time 0 with
  // "Virtual interface resolution cannot find a matching instance".
  parameter int NUM_LINKS = MAX_LINKS
)(
  input logic clk,
  input logic rst_n
);

  flit_t flit_in   [NUM_LINKS];
  logic  valid_in  [NUM_LINKS];
  logic  ready_out [NUM_LINKS];

  flit_t flit_out  [NUM_LINKS];
  logic  valid_out [NUM_LINKS];
  logic  ready_in  [NUM_LINKS];

  modport DRIVER (
    input  clk, rst_n,
    output flit_in, valid_in,
    input  ready_out
  );

  modport RECEIVER (
    input  clk, rst_n,
    input  flit_out, valid_out,
    output ready_in
  );

  modport MONITOR (
    input clk, rst_n,
    input flit_in, valid_in, ready_out,
    input flit_out, valid_out, ready_in
  );

endinterface : router_if
