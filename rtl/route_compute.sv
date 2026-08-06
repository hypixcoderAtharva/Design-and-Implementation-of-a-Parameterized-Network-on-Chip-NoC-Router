// =============================================================================
// route_compute.sv
// -----------------------------------------------------------------------------
// Dimension-order (XY) routing: resolve X first, then Y, then Local.
// One instance per VC inside input_buffer.sv, evaluated against the head
// flit currently at that VC's FIFO output.
// =============================================================================

module route_compute
  import noc_vc_pkg::*;
  import router_config_pkg::*;
#(
  parameter logic [X_WIDTH-1:0] MY_X = '0,
  parameter logic [Y_WIDTH-1:0] MY_Y = '0
) (
  input  logic [X_WIDTH-1:0]  dest_x,
  input  logic [Y_WIDTH-1:0]  dest_y,
  output direction_e          out_port
);

  // Y polarity matches Track A's router.sv (dest_y > MY_Y -> North). The two
  // designs previously disagreed on which way Y grows, which would have made
  // a mesh built from a mix of them route packets in opposite directions.
  always_comb begin
    if (dest_x != MY_X) begin
      out_port = direction_e'((dest_x > MY_X) ? DIR_E : DIR_W);
    end else if (dest_y != MY_Y) begin
      out_port = direction_e'((dest_y > MY_Y) ? DIR_N : DIR_S);
    end else begin
      out_port = DIR_LOCAL;
    end
  end

endmodule : route_compute
