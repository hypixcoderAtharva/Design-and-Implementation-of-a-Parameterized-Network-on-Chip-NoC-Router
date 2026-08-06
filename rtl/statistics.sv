// =============================================================================
// statistics.sv                                                        [ADD]
// Mesh-wide statistics aggregator. Sums per-router accepted/forwarded flit
// counts from performance_monitor instances across the whole mesh and
// reports the busiest router (a simple hotspot indicator useful when
// comparing uniform-random vs hotspot traffic patterns).
// =============================================================================
module statistics
  import noc_pkg::*;
#(
  parameter int NUM_ROUTERS = MESH_DIM_X * MESH_DIM_Y
)(
  input logic clk,
  input logic rst_n,

  input logic [31:0] flits_accepted_i  [NUM_ROUTERS],
  input logic [31:0] flits_forwarded_i [NUM_ROUTERS],

  output logic [31:0] total_flits_accepted,
  output logic [31:0] total_flits_forwarded,
  output logic [31:0] max_router_load,     // highest flits_forwarded among all routers
  output logic [7:0]  hotspot_router_id    // index (y*MESH_DIM_X + x) of that router
);

  logic [31:0] sum_acc, sum_fwd;
  logic [31:0] running_max;
  logic [7:0]  running_max_id;

  always_comb begin
    sum_acc        = '0;
    sum_fwd        = '0;
    running_max    = '0;
    running_max_id = '0;
    for (int i = 0; i < NUM_ROUTERS; i++) begin
      sum_acc += flits_accepted_i[i];
      sum_fwd += flits_forwarded_i[i];
      if (flits_forwarded_i[i] > running_max) begin
        running_max    = flits_forwarded_i[i];
        running_max_id = 8'(i);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      total_flits_accepted  <= '0;
      total_flits_forwarded <= '0;
      max_router_load        <= '0;
      hotspot_router_id      <= '0;
    end else begin
      total_flits_accepted  <= sum_acc;
      total_flits_forwarded <= sum_fwd;
      max_router_load        <= running_max;
      hotspot_router_id      <= running_max_id;
    end
  end

endmodule : statistics
