// noc_if.sv
// Point-to-point link between two routers (or a router and the local
// traffic source/sink). Simple valid/ready handshake: a flit transfers
// on any cycle where both valid and ready are high.
//
// clk/rst_n are carried on the interface so protocol assertions
// (see noc_assertions.sv) can be bound to it later without extra wiring.

interface noc_if
  import noc_pkg::*;
(
  input logic clk,
  input logic rst_n
);

  logic  valid;
  logic  ready;
  flit_t flit;

  // driven by the upstream side (whoever is sending flits)
  modport master (
    input  clk, rst_n,
    output valid,
    input  ready,
    output flit
  );

  // driven by the downstream side (whoever is receiving flits)
  modport slave (
    input  clk, rst_n,
    input  valid,
    output ready,
    input  flit
  );

endinterface : noc_if
