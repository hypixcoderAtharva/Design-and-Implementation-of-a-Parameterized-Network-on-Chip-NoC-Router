// =============================================================================
// router_assertions.sv                                                 [ADD]
// SVA protocol checker module, bound to a router_if instance in each
// testbench top. Checks (per port): valid/output signals are known after
// reset, an accepted flit's destination is always in-mesh, an emitted
// flit's contents are never X/Z, and no port is starved for more than
// MAX_STALL_CYCLES while continuously requesting.
//
// Uses plain $error/$warning (not `uvm_error) since this module is
// standalone SVA, not a UVM class -- keeps it usable even in a testbench
// that isn't UVM-based.
// =============================================================================
module router_assertions
  import noc_pkg::*;
#(
  parameter int MAX_STALL_CYCLES = 200
)(
  input logic clk,
  input logic rst_n,

  input flit_t flit_in   [NUM_PORTS],
  input logic  valid_in  [NUM_PORTS],
  input logic  ready_out [NUM_PORTS],

  input flit_t flit_out  [NUM_PORTS],
  input logic  valid_out [NUM_PORTS],
  input logic  ready_in  [NUM_PORTS]
);

  genvar p;
  generate
    for (p = 0; p < NUM_PORTS; p++) begin : g_assert

      // reset must clear all output-valid signals
      property p_reset_clears_valid;
        @(posedge clk) !rst_n |=> !valid_out[p];
      endproperty
      a_reset_clears_valid: assert property (p_reset_clears_valid)
        else $error("router_assertions: valid_out[%0d] not cleared after reset", p);

      // no unknown values on the handshake signals once out of reset
      property p_no_x_on_valid;
        @(posedge clk) disable iff (!rst_n)
          !$isunknown(valid_in[p]) && !$isunknown(valid_out[p]);
      endproperty
      a_no_x_on_valid: assert property (p_no_x_on_valid)
        else $error("router_assertions: X/Z detected on valid_in/valid_out[%0d]", p);

      // an accepted flit must always carry an in-mesh destination
      property p_dest_in_bounds;
        @(posedge clk) disable iff (!rst_n)
          (valid_in[p] && ready_out[p]) |->
            (flit_in[p].dest_x < MESH_DIM_X) && (flit_in[p].dest_y < MESH_DIM_Y);
      endproperty
      a_dest_in_bounds: assert property (p_dest_in_bounds)
        else $error("router_assertions: port %0d accepted a flit with an out-of-mesh destination", p);

      // an emitted flit must carry fully known (non-X) contents
      property p_output_data_known;
        @(posedge clk) disable iff (!rst_n)
          valid_out[p] |-> !$isunknown(flit_out[p]);
      endproperty
      a_output_data_known: assert property (p_output_data_known)
        else $error("router_assertions: port %0d drove valid_out with unknown flit contents", p);

      // bounded backpressure: a held-valid input should be accepted within
      // MAX_STALL_CYCLES cycles (tune this for your traffic injection rate)
      property p_bounded_stall;
        @(posedge clk) disable iff (!rst_n)
          valid_in[p] |-> ##[0:MAX_STALL_CYCLES] ready_out[p];
      endproperty
      a_bounded_stall: assert property (p_bounded_stall)
        else $warning("router_assertions: port %0d stalled for more than %0d cycles", p, MAX_STALL_CYCLES);

    end
  endgenerate

endmodule : router_assertions
