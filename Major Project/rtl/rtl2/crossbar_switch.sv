// =============================================================================
// crossbar_switch.sv
// -----------------------------------------------------------------------------
// NUM_PORTS x NUM_PORTS crossbar datapath, built from the verified mux5 /
// demux5 primitives:
//
//   Stage A (per INPUT port): demux5 steers that port's head-of-line flit
//     toward its switch-allocator-granted output lane (all-zero if it
//     wasn't granted this cycle).
//
//   Stage B (per OUTPUT port): mux5 collects from the 5 candidate lanes.
//     Exactly one lane can be valid per output port, guaranteed by
//     switch_allocator's stage-2 arbitration, so this is a clean select
//     with no arbitration logic duplicated here.
// =============================================================================

module crossbar_switch
  import noc_pkg::*;
  import router_config_pkg::*;
(
  input  flit_t                 in_data              [NUM_PORTS], // per input port
  input  logic  [NUM_PORTS-1:0] input_granted_output [NUM_PORTS], // per input port, one-hot over outputs
  output flit_t                 out_data             [NUM_PORTS],
  output logic  [NUM_PORTS-1:0] out_valid
);

  localparam int FW = $bits(flit_t);

  flit_t                 lane       [NUM_PORTS][NUM_PORTS]; // lane[in_port][out_port]
  logic  [NUM_PORTS-1:0] lane_valid [NUM_PORTS];             // lane_valid[in_port][out_port]

  genvar ip;
  generate
    for (ip = 0; ip < NUM_PORTS; ip++) begin : g_demux_in
      demux5 #(.WIDTH(FW)) u_demux (
        .sel       (input_granted_output[ip]),
        .in_data   (in_data[ip]),
        .in_valid  (|input_granted_output[ip]),
        .out0      (lane[ip][0]),
        .out1      (lane[ip][1]),
        .out2      (lane[ip][2]),
        .out3      (lane[ip][3]),
        .out4      (lane[ip][4]),
        .out_valid (lane_valid[ip])
      );
    end
  endgenerate

  genvar op, k;
  generate
    for (op = 0; op < NUM_PORTS; op++) begin : g_mux_out

      logic [NUM_PORTS-1:0] col_sel;
      for (k = 0; k < NUM_PORTS; k++) begin : g_col
        assign col_sel[k] = lane_valid[k][op];
      end

      mux5 #(.WIDTH(FW)) u_mux (
        .sel       (col_sel),
        .in0       (lane[0][op]),
        .in1       (lane[1][op]),
        .in2       (lane[2][op]),
        .in3       (lane[3][op]),
        .in4       (lane[4][op]),
        .out       (out_data[op]),
        .out_valid (out_valid[op])
      );
    end
  endgenerate

endmodule : crossbar_switch