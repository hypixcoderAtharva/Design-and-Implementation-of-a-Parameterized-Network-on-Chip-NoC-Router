// =============================================================================
// tb_router.sv
// Single-router testbench top. Instantiates ONE router at coordinate
// (ROUTER_X, ROUTER_Y) = (1,1) -- deliberately an interior coordinate so
// that all four directions (N/E/S/W) are reachable and the XY routing logic
// is fully exercised. The 5 physical ports are driven and monitored
// directly, so NUM_AGENTS = NUM_PORTS.
//
// This file was not in your "Add" list; re-created here for a self-contained
// package.
//
// Run with e.g.:  +UVM_TESTNAME=uniform_random_test
// =============================================================================
`timescale 1ns/1ps

module tb_router;

  import uvm_pkg::*;
  import noc_pkg::*;
  import noc_test_pkg::*;
  `include "uvm_macros.svh"

  // router under test sits at an interior mesh coordinate
  localparam int RX = 1;
  localparam int RY = 1;

  logic clk;
  logic rst_n;

  // ---- clock and reset ----
  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;   // 100 MHz
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---- interface ----
  // Sized MAX_LINKS (not NUM_PORTS) so the virtual-interface type matches the
  // one the UVM classes hold; only the first NUM_PORTS links are used here.
  router_if #(.NUM_LINKS(MAX_LINKS)) dut_if (.clk(clk), .rst_n(rst_n));

  // ---- map the first NUM_PORTS interface links onto the router's ports ----
  flit_t d_flit_in   [NUM_PORTS];
  logic  d_valid_in  [NUM_PORTS];
  logic  d_ready_out [NUM_PORTS];
  flit_t d_flit_out  [NUM_PORTS];
  logic  d_valid_out [NUM_PORTS];
  logic  d_ready_in  [NUM_PORTS];

  genvar gp;
  generate
    for (gp = 0; gp < NUM_PORTS; gp++) begin : g_port_map
      assign d_flit_in[gp]        = dut_if.flit_in[gp];
      assign d_valid_in[gp]       = dut_if.valid_in[gp];
      assign dut_if.ready_out[gp] = d_ready_out[gp];
      assign dut_if.flit_out[gp]  = d_flit_out[gp];
      assign dut_if.valid_out[gp] = d_valid_out[gp];
      assign d_ready_in[gp]       = dut_if.ready_in[gp];
    end
  endgenerate

  // Links beyond the router's 5 ports are unused in this testbench; park them
  // at known values so the monitor never samples X on them.
  //
  // The DUT-side signals (ready_out/flit_out/valid_out) MUST be parked with
  // continuous assignments, not from an initial block: the generate loop above
  // already drives elements 0..NUM_PORTS-1 of those same arrays continuously,
  // and Questa resolves the "continuous vs procedural driver" check per
  // variable, not per array element (vopt-12003).
  generate
    for (gp = NUM_PORTS; gp < MAX_LINKS; gp++) begin : g_unused_dut_side
      assign dut_if.ready_out[gp] = 1'b0;
      assign dut_if.flit_out[gp]  = '0;
      assign dut_if.valid_out[gp] = 1'b0;
    end
  endgenerate

  // TB-side signals are only ever written procedurally (here and by the UVM
  // driver/receiver through the virtual interface), so an initial block is fine.
  initial begin
    for (int i = NUM_PORTS; i < MAX_LINKS; i++) begin
      dut_if.flit_in[i]  = '0;
      dut_if.valid_in[i] = 1'b0;
      dut_if.ready_in[i] = 1'b0;
    end
  end

  // ---- DUT ----
  router #(.ROUTER_X(RX), .ROUTER_Y(RY)) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .flit_in   (d_flit_in),
    .valid_in  (d_valid_in),
    .ready_out (d_ready_out),
    .flit_out  (d_flit_out),
    .valid_out (d_valid_out),
    .ready_in  (d_ready_in)
  );

  // ---- SVA protocol checker ----
  router_assertions #(.MAX_STALL_CYCLES(200)) u_sva (
    .clk       (clk),
    .rst_n     (rst_n),
    .flit_in   (d_flit_in),
    .valid_in  (d_valid_in),
    .ready_out (d_ready_out),
    .flit_out  (d_flit_out),
    .valid_out (d_valid_out),
    .ready_in  (d_ready_in)
  );

  // ---- UVM configuration and run ----
  initial begin
    uvm_config_db#(virtual router_if.DRIVER  )::set(null, "uvm_test_top.e.agent_*.drv", "vif", dut_if);
    uvm_config_db#(virtual router_if.RECEIVER)::set(null, "uvm_test_top.e.agent_*.rcv", "vif", dut_if);
    uvm_config_db#(virtual router_if.MONITOR )::set(null, "uvm_test_top.e.mon",         "vif", dut_if);
    uvm_config_db#(int unsigned)::set(null, "uvm_test_top", "num_agents", NUM_PORTS);

    run_test("uniform_random_test");   // override with +UVM_TESTNAME=...
  end

  // ---- waveform dump ----
  initial begin
    $dumpfile("tb_router.vcd");
    $dumpvars(0, tb_router);
  end

  // ---- global timeout safety net ----
  initial begin
    #200us;
    `uvm_fatal("TIMEOUT", "tb_router global timeout reached")
  end

endmodule : tb_router
