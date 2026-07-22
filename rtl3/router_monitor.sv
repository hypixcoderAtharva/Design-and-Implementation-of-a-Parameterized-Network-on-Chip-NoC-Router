// =============================================================================
// router_monitor.sv
// -----------------------------------------------------------------------------
// Simulation-only verification helper: logs each accepted flit on every
// output link, and flags ports that stay out of credit for an extended
// number of cycles (a cheap early warning for backpressure storms /
// possible deadlock during directed or random testing). Also carries a
// couple of basic protocol assertions. None of this block is meant to be
// synthesized -- it is bound into router_top.sv purely for testbench
// visibility while this feeds into the wider UVM verification environment.
//
// Ports are flattened packed buses rather than unpacked arrays, for
// maximum portability across simulators/synthesis tools.
// =============================================================================

module router_monitor
  import noc_pkg::*;
  import router_config_pkg::*;
#(
  parameter string ROUTER_NAME = "router"
) (
  input logic clk,
  input logic rst_n,

  input logic [NUM_PORTS*$bits(flit_t)-1:0] link_flit_flat,
  input logic [NUM_PORTS-1:0]               link_valid,
  input logic [NUM_PORTS*NUM_VCS-1:0]       has_credit_flat
);

  // synthesis translate_off

  localparam int FW = $bits(flit_t);

  genvar p;
  generate
    for (p = 0; p < NUM_PORTS; p++) begin : g_mon

      flit_t      mon_flit;
      flit_type_e mon_ftype;
      always_comb mon_flit  = flit_t'(link_flit_flat[p*FW +: FW]);
      always_comb mon_ftype = mon_flit.ftype;

      always_ff @(posedge clk) begin
        if (rst_n && link_valid[p]) begin
          $display("[%0t] %s port%0d: flit type=%s vc=%0d dest=(%0d,%0d)",
                    $time, ROUTER_NAME, p, mon_ftype.name(),
                    mon_flit.vc_id, mon_flit.dest_x, mon_flit.dest_y);
        end
      end

      // liveness check: flag a port that has been fully out of credit for
      // an extended stretch, a symptom of backpressure buildup / deadlock
      logic [15:0] stall_cycles;
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          stall_cycles <= '0;
        end else if (has_credit_flat[p*NUM_VCS +: NUM_VCS] == '0) begin
          stall_cycles <= stall_cycles + 1'b1;
          if (stall_cycles == 16'hFFFF) begin
            $warning("%s port%0d out of credit for an extended period",
                      ROUTER_NAME, p);
          end
        end else begin
          stall_cycles <= '0;
        end
      end

      always @(posedge clk) begin
        assert (rst_n || !link_valid[p])
          else $error("%s port%0d: link_valid asserted during reset", ROUTER_NAME, p);
      end

    end
  endgenerate

  // synthesis translate_on

endmodule : router_monitor
