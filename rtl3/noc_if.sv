// =============================================================================
// noc_if.sv
// -----------------------------------------------------------------------------
// Point-to-point link interface between two neighbouring routers (or a
// router and a network interface / traffic generator).
//
// router_top.sv itself uses flattened std-logic ports (flit_t / valid /
// credit buses) rather than this interface directly, so that router_top
// stays portable across simulators and synthesis tools that have uneven
// support for interface-typed module ports. noc_if is provided as the
// convenience wrapper for wiring several router_top instances together in
// a mesh testbench or a chip-level top: instantiate one noc_if per link,
// drive the .tx side from one router's flattened outputs, and connect the
// .rx side to the neighbour's flattened inputs (or bind the modports
// straight into a small glue module if you prefer interfaces end to end).
// =============================================================================

interface noc_if
  import noc_pkg::*;
  import router_config_pkg::*;
(
  input logic clk,
  input logic rst_n
);

  flit_t               flit;    // flit currently driven on the link
  logic                valid;   // flit is valid this cycle
  logic [NUM_VCS-1:0]  credit;  // one credit pulse per VC, sent back upstream

  modport tx (
    input  clk, rst_n,
    output flit, valid,
    input  credit
  );

  modport rx (
    input  clk, rst_n,
    input  flit, valid,
    output credit
  );

endinterface : noc_if
