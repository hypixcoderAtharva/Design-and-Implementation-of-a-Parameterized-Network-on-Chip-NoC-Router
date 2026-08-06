// =============================================================================
// noc_test_pkg.sv
// Wraps all verification classes in one package so the compile order is
// fixed and correct regardless of how the simulator is invoked. Both
// testbench tops import this. Not in your requested file list, but it is
// what keeps `include ordering from becoming a source of build errors.
// =============================================================================
package noc_test_pkg;

  import uvm_pkg::*;
  import noc_pkg::*;
  `include "uvm_macros.svh"

  // order matters: transaction -> sequences -> components -> env -> tests
  `include "packet.sv"
  `include "packet_generator.sv"
  `include "driver.sv"
  `include "receiver.sv"
  `include "router_monitor.sv"
  `include "router_scoreboard.sv"
  `include "router_coverage.sv"
  `include "traffic_generator.sv"
  `include "router_agent.sv"
  `include "env.sv"
  `include "router_test.sv"

endpackage : noc_test_pkg
