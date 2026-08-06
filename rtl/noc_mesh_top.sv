// =============================================================================
// noc_mesh_top.sv
// Top-level MESH_DIM_X x MESH_DIM_Y mesh of routers. Instantiates one
// router per (x,y) coordinate, wires N/E/S/W links to physical neighbors
// (tying off links at mesh boundaries), and exposes each router's local
// port (PORT_L) directly at the flit level as a top-level array port --
// this is what the verification environment drives/monitors.
//
// Also instantiates one performance_monitor and one error_checker per
// router, feeding aggregated results into a single statistics block.
//
// Like router.sv, this file was not in your "Add" list (implying it
// already exists in your project); it is re-created here for a
// self-contained, consistent package. Swap in your original if it differs.
// =============================================================================
module noc_mesh_top
  import noc_pkg::*;
(
  input logic clk,
  input logic rst_n,

  // ---- local port, exposed per mesh node at the flit level ----
  input  flit_t local_flit_in   [MESH_DIM_X][MESH_DIM_Y],
  input  logic  local_valid_in  [MESH_DIM_X][MESH_DIM_Y],
  output logic  local_ready_out [MESH_DIM_X][MESH_DIM_Y],

  output flit_t local_flit_out  [MESH_DIM_X][MESH_DIM_Y],
  output logic  local_valid_out [MESH_DIM_X][MESH_DIM_Y],
  input  logic  local_ready_in  [MESH_DIM_X][MESH_DIM_Y],

  // ---- mesh-wide telemetry ----
  output logic [31:0] total_flits_accepted,
  output logic [31:0] total_flits_forwarded,
  output logic [31:0] hotspot_load,
  output logic [7:0]  hotspot_id,
  output logic        mesh_error_detected
);

  localparam int NX = MESH_DIM_X;
  localparam int NY = MESH_DIM_Y;
  localparam int NR = NX * NY;

  // per-router port bundles
  flit_t r_flit_in   [NX][NY][NUM_PORTS];
  logic  r_valid_in  [NX][NY][NUM_PORTS];
  logic  r_ready_out [NX][NY][NUM_PORTS];
  flit_t r_flit_out  [NX][NY][NUM_PORTS];
  logic  r_valid_out [NX][NY][NUM_PORTS];
  logic  r_ready_in  [NX][NY][NUM_PORTS];

  genvar x, y;
  generate
    for (x = 0; x < NX; x++) begin : g_x
      for (y = 0; y < NY; y++) begin : g_y

        router #(.ROUTER_X(x), .ROUTER_Y(y)) u_router (
          .clk       (clk),
          .rst_n     (rst_n),
          .flit_in   (r_flit_in[x][y]),
          .valid_in  (r_valid_in[x][y]),
          .ready_out (r_ready_out[x][y]),
          .flit_out  (r_flit_out[x][y]),
          .valid_out (r_valid_out[x][y]),
          .ready_in  (r_ready_in[x][y])
        );

        // ---- East-West inter-router links ----
        if (x < NX-1) begin : g_link_ew
          assign r_flit_in [x+1][y][PORT_W] = r_flit_out [x][y][PORT_E];
          assign r_valid_in[x+1][y][PORT_W] = r_valid_out[x][y][PORT_E];
          assign r_ready_in[x][y][PORT_E]   = r_ready_out[x+1][y][PORT_W];

          assign r_flit_in [x][y][PORT_E]   = r_flit_out [x+1][y][PORT_W];
          assign r_valid_in[x][y][PORT_E]   = r_valid_out[x+1][y][PORT_W];
          assign r_ready_in[x+1][y][PORT_W] = r_ready_out[x][y][PORT_E];
        end else begin : g_edge_e
          assign r_valid_in[x][y][PORT_E] = 1'b0;
          assign r_flit_in [x][y][PORT_E] = '0;
          assign r_ready_in[x][y][PORT_E] = 1'b0;
        end

        // ---- North-South inter-router links ----
        if (y < NY-1) begin : g_link_ns
          assign r_flit_in [x][y+1][PORT_S] = r_flit_out [x][y][PORT_N];
          assign r_valid_in[x][y+1][PORT_S] = r_valid_out[x][y][PORT_N];
          assign r_ready_in[x][y][PORT_N]   = r_ready_out[x][y+1][PORT_S];

          assign r_flit_in [x][y][PORT_N]   = r_flit_out [x][y+1][PORT_S];
          assign r_valid_in[x][y][PORT_N]   = r_valid_out[x][y+1][PORT_S];
          assign r_ready_in[x][y+1][PORT_S] = r_ready_out[x][y][PORT_N];
        end else begin : g_edge_n
          assign r_valid_in[x][y][PORT_N] = 1'b0;
          assign r_flit_in [x][y][PORT_N] = '0;
          assign r_ready_in[x][y][PORT_N] = 1'b0;
        end

        // west / south mesh boundary tie-offs (east/north handled by the
        // g_link_ew / g_link_ns generate blocks above from the neighbor's side)
        if (x == 0) begin : g_edge_w
          assign r_valid_in[x][y][PORT_W] = 1'b0;
          assign r_flit_in [x][y][PORT_W] = '0;
          assign r_ready_in[x][y][PORT_W] = 1'b0;
        end
        if (y == 0) begin : g_edge_s
          assign r_valid_in[x][y][PORT_S] = 1'b0;
          assign r_flit_in [x][y][PORT_S] = '0;
          assign r_ready_in[x][y][PORT_S] = 1'b0;
        end

        // ---- local port <-> top-level mesh port (flit level) ----
        assign r_flit_in [x][y][PORT_L]  = local_flit_in[x][y];
        assign r_valid_in[x][y][PORT_L]  = local_valid_in[x][y];
        assign local_ready_out[x][y]     = r_ready_out[x][y][PORT_L];

        assign local_flit_out[x][y]      = r_flit_out[x][y][PORT_L];
        assign local_valid_out[x][y]     = r_valid_out[x][y][PORT_L];
        assign r_ready_in[x][y][PORT_L]  = local_ready_in[x][y];

      end
    end
  endgenerate

  // ---------------------------------------------------------------------
  // Per-router performance monitoring + error checking, flattened for
  // the mesh-wide statistics aggregator (index = y*NX + x)
  // ---------------------------------------------------------------------
  logic [31:0]  acc_flat   [NR];
  logic [31:0]  fwd_flat   [NR];
  logic [31:0]  active_flat[NR];   // per-router active cycles
  logic [31:0]  busy_flat  [NR];   // per-router summed port-busy cycles
  logic [31:0]  stall_flat [NR];   // per-router input stall cycles
  logic [31:0]  errcnt_flat[NR];   // per-router sticky error count
  logic [NUM_PORTS-1:0] oob_flat [NR];
  logic [NUM_PORTS-1:0] ovf_flat [NR];
  logic [NR-1:0] err_flat;

  generate
    for (x = 0; x < NX; x++) begin : g_pm_x
      for (y = 0; y < NY; y++) begin : g_pm_y
        localparam int RID = y*NX + x;

        performance_monitor u_pm (
          .clk                (clk),
          .rst_n              (rst_n),
          .valid_in           (r_valid_in[x][y]),
          .ready_out          (r_ready_out[x][y]),
          .valid_out          (r_valid_out[x][y]),
          .ready_in           (r_ready_in[x][y]),
          .flits_accepted     (acc_flat[RID]),
          .flits_forwarded    (fwd_flat[RID]),
          .cycles_active      (active_flat[RID]),
          .busy_cycles_sum    (busy_flat[RID]),
          .input_stall_cycles (stall_flat[RID])
        );

        error_checker u_ec (
          .clk                 (clk),
          .rst_n               (rst_n),
          .flit_in             (r_flit_in[x][y]),
          .valid_in            (r_valid_in[x][y]),
          .ready_out           (r_ready_out[x][y]),
          .error_detected      (err_flat[RID]),
          .error_count         (errcnt_flat[RID]),
          .out_of_bounds_flag  (oob_flat[RID]),
          .overflow_flag       (ovf_flat[RID])
        );
      end
    end
  endgenerate

  // active_flat / busy_flat / stall_flat / errcnt_flat / oob_flat / ovf_flat
  // are observation-only: they are not consumed by the mesh's own logic, but
  // they are visible in waveforms and can be probed hierarchically from a
  // testbench (e.g. dut.stall_flat[5]) for per-router performance analysis.
  assign mesh_error_detected = |err_flat;

  statistics #(.NUM_ROUTERS(NR)) u_stats (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .flits_accepted_i       (acc_flat),
    .flits_forwarded_i      (fwd_flat),
    .total_flits_accepted   (total_flits_accepted),
    .total_flits_forwarded  (total_flits_forwarded),
    .max_router_load        (hotspot_load),
    .hotspot_router_id      (hotspot_id)
  );

endmodule : noc_mesh_top
