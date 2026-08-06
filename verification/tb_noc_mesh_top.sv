// =============================================================================
// tb_noc_mesh_top.sv
// Full-mesh testbench top. Instantiates the MESH_DIM_X x MESH_DIM_Y mesh and
// drives every node's LOCAL port, so NUM_AGENTS = MESH_DIM_X * MESH_DIM_Y
// (16 for the default 4x4). Link index i maps to mesh coordinate
// (x, y) = (i % MESH_DIM_X, i / MESH_DIM_X) -- the same mapping
// traffic_generator.sv uses to compute each node's source coordinate, so
// patterns like TRANSPOSE and BIT_COMPLEMENT line up correctly.
//
// This file was not in your "Add" list; re-created here for a self-contained
// package.
//
// Run with e.g.:  +UVM_TESTNAME=hotspot_test
// =============================================================================
`timescale 1ns/1ps

module tb_noc_mesh_top;

  import uvm_pkg::*;
  import noc_pkg::*;
  import noc_test_pkg::*;
  `include "uvm_macros.svh"

  localparam int NX = MESH_DIM_X;
  localparam int NY = MESH_DIM_Y;
  localparam int NR = NX * NY;

  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;   // 100 MHz
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---- interface: one link per mesh node's local port ----
  router_if #(.NUM_LINKS(MAX_LINKS)) dut_if (.clk(clk), .rst_n(rst_n));

  // ---- mesh-facing 2-D arrays, flattened to/from the 1-D interface ----
  flit_t local_flit_in   [NX][NY];
  logic  local_valid_in  [NX][NY];
  logic  local_ready_out [NX][NY];
  flit_t local_flit_out  [NX][NY];
  logic  local_valid_out [NX][NY];
  logic  local_ready_in  [NX][NY];

  // link index i <-> node (x,y) = (i % NX, i / NX)
  genvar gx, gy;
  generate
    for (gx = 0; gx < NX; gx++) begin : g_map_x
      for (gy = 0; gy < NY; gy++) begin : g_map_y
        localparam int LI = gy*NX + gx;

        assign local_flit_in[gx][gy]   = dut_if.flit_in[LI];
        assign local_valid_in[gx][gy]  = dut_if.valid_in[LI];
        assign dut_if.ready_out[LI]    = local_ready_out[gx][gy];

        assign dut_if.flit_out[LI]     = local_flit_out[gx][gy];
        assign dut_if.valid_out[LI]    = local_valid_out[gx][gy];
        assign local_ready_in[gx][gy]  = dut_if.ready_in[LI];
      end
    end
  endgenerate

  // ---- mesh-wide telemetry from statistics.sv ----
  logic [31:0] total_accepted, total_forwarded, hotspot_load;
  logic [7:0]  hotspot_id;
  logic        mesh_error;

  // ---- DUT ----
  noc_mesh_top dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .local_flit_in         (local_flit_in),
    .local_valid_in        (local_valid_in),
    .local_ready_out       (local_ready_out),
    .local_flit_out        (local_flit_out),
    .local_valid_out       (local_valid_out),
    .local_ready_in        (local_ready_in),
    .total_flits_accepted  (total_accepted),
    .total_flits_forwarded (total_forwarded),
    .hotspot_load          (hotspot_load),
    .hotspot_id            (hotspot_id),
    .mesh_error_detected   (mesh_error)
  );

  // ---- UVM configuration and run ----
  initial begin
    uvm_config_db#(virtual router_if.DRIVER  )::set(null, "uvm_test_top.e.agent_*.drv", "vif", dut_if);
    uvm_config_db#(virtual router_if.RECEIVER)::set(null, "uvm_test_top.e.agent_*.rcv", "vif", dut_if);
    uvm_config_db#(virtual router_if.MONITOR )::set(null, "uvm_test_top.e.mon",         "vif", dut_if);
    uvm_config_db#(int unsigned)::set(null, "uvm_test_top", "num_agents", NR);

    run_test("uniform_random_test");   // override with +UVM_TESTNAME=...
  end

  // ---- report hardware telemetry alongside the UVM summary ----
  final begin
    $display("--------------------------------------------------------");
    $display(" Mesh hardware counters (from statistics.sv)");
    $display("   total flits accepted  : %0d", total_accepted);
    $display("   total flits forwarded : %0d", total_forwarded);
    $display("   hotspot router id     : %0d (load %0d)", hotspot_id, hotspot_load);
    $display("   error flag            : %0b", mesh_error);
    $display("--------------------------------------------------------");
  end

  initial begin
    $dumpfile("tb_noc_mesh_top.vcd");
    $dumpvars(0, tb_noc_mesh_top);
  end

  initial begin
    #500us;
    `uvm_fatal("TIMEOUT", "tb_noc_mesh_top global timeout reached")
  end

endmodule : tb_noc_mesh_top
