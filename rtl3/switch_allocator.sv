// =============================================================================
// switch_allocator.sv
// -----------------------------------------------------------------------------
// Classic separable (two-stage) switch allocator for the whole router,
// instantiated once in router_top.sv:
//
//   Stage 1 (per INPUT port): arbitrate among that port's own NUM_VCS
//     lanes -- an input port can only offer one flit per cycle, since it
//     has a single physical lane into the crossbar.
//
//   Stage 2 (per OUTPUT port): arbitrate among the (up to NUM_PORTS)
//     stage-1 winners that are asking for this particular output port.
//
// Outputs both the flattened per-VC sa_grant bus (input_buffer.sv pops
// its FIFO and clocks the flit out when granted) and, for the crossbar,
// a flattened one-hot "input_granted_output" vector per input port plus
// the output VC each winning flit is using (for credit bookkeeping
// downstream). All ports are flattened packed buses rather than
// unpacked arrays, for maximum portability across simulators/synthesis
// tools.
// =============================================================================

module switch_allocator
  import noc_pkg::*;
  import router_config_pkg::*;
#(
  parameter int TOTAL_IVCS = NUM_PORTS * NUM_VCS
) (
  input  logic clk,
  input  logic rst_n,

  input  logic [TOTAL_IVCS-1:0]            sa_request,
  input  logic [TOTAL_IVCS*PORT_ID_W-1:0]  sa_req_port,
  input  logic [TOTAL_IVCS*VC_ID_W-1:0]    sa_out_vc,

  output logic [TOTAL_IVCS-1:0]            sa_grant,

  output logic [NUM_PORTS*NUM_PORTS-1:0]  input_granted_output_flat, // per input port
  output logic [NUM_PORTS*VC_ID_W-1:0]    xbar_sel_vc_flat           // per output port
);

  // ---- Stage 1: per input port, pick one ready VC to represent the port ----
  logic [NUM_VCS-1:0]   stage1_grant [NUM_PORTS];
  logic                 stage1_valid [NUM_PORTS];
  logic [VC_ID_W-1:0]   stage1_vc_idx[NUM_PORTS];
  logic [PORT_ID_W-1:0] stage1_out_port[NUM_PORTS];

  genvar ip;
  generate
    for (ip = 0; ip < NUM_PORTS; ip++) begin : g_stage1

      rr_arbiter #(.WIDTH(NUM_VCS)) u_in_arb (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (sa_request[ip*NUM_VCS +: NUM_VCS]),
        .advance     (1'b1),
        .grant       (stage1_grant[ip]),
        .grant_valid (stage1_valid[ip])
      );

      encoder #(.IN_WIDTH(NUM_VCS)) u_vc_enc (
        .in_vec  (stage1_grant[ip]),
        .out_idx (stage1_vc_idx[ip]),
        .valid   ()
      );

      assign stage1_out_port[ip] =
        sa_req_port[(ip*NUM_VCS + stage1_vc_idx[ip])*PORT_ID_W +: PORT_ID_W];

    end
  endgenerate

  // ---- Stage 2: per output port, pick one winning input port ----
  logic [NUM_PORTS-1:0] stage2_req   [NUM_PORTS];
  logic [NUM_PORTS-1:0] stage2_grant [NUM_PORTS];
  logic                 stage2_valid [NUM_PORTS];

  genvar go, gi;
  generate
    for (go = 0; go < NUM_PORTS; go++) begin : g_out_req
      for (gi = 0; gi < NUM_PORTS; gi++) begin : g_out_req_in
        assign stage2_req[go][gi] =
          stage1_valid[gi] && (stage1_out_port[gi] == go[PORT_ID_W-1:0]);
      end
    end

    for (go = 0; go < NUM_PORTS; go++) begin : g_stage2
      rr_arbiter #(.WIDTH(NUM_PORTS)) u_out_arb (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (stage2_req[go]),
        .advance     (1'b1),
        .grant       (stage2_grant[go]),
        .grant_valid (stage2_valid[go])
      );
    end
  endgenerate

  // ---- Combine: translate stage-2 winners into per-VC grants / xbar info ----
  logic [NUM_PORTS-1:0] input_granted_output [NUM_PORTS];
  logic [VC_ID_W-1:0]   xbar_sel_vc          [NUM_PORTS];

  integer op, ip2;
  always_comb begin
    sa_grant = '0;
    for (ip2 = 0; ip2 < NUM_PORTS; ip2++) input_granted_output[ip2] = '0;

    for (op = 0; op < NUM_PORTS; op++) begin
      xbar_sel_vc[op] = '0;
      if (stage2_valid[op]) begin
        for (ip2 = 0; ip2 < NUM_PORTS; ip2++) begin
          if (stage2_grant[op][ip2]) begin
            sa_grant[ip2*NUM_VCS + stage1_vc_idx[ip2]] = 1'b1;
            xbar_sel_vc[op] =
              sa_out_vc[(ip2*NUM_VCS + stage1_vc_idx[ip2])*VC_ID_W +: VC_ID_W];
            input_granted_output[ip2][op] = 1'b1;
          end
        end
      end
    end
  end

  // ---- Flatten the per-port arrays onto the module's packed-bus ports ----
  genvar fp;
  generate
    for (fp = 0; fp < NUM_PORTS; fp++) begin : g_flatten
      assign input_granted_output_flat[fp*NUM_PORTS +: NUM_PORTS] = input_granted_output[fp];
      assign xbar_sel_vc_flat[fp*VC_ID_W +: VC_ID_W]               = xbar_sel_vc[fp];
    end
  endgenerate

endmodule : switch_allocator
