// route_compute.sv
// Combinational XY route computation - the "RC" pipeline stage.
// Only meaningful when is_head is asserted (i.e. the flit at the
// head of the input buffer is a HEAD or HEAD_TAIL flit); the caller
// is responsible for latching out_port for the rest of the packet.

module route_compute
  import noc_pkg::*;
#(
    parameter logic [COORD_WIDTH-1:0] ROUTER_X = 0,
    parameter logic [COORD_WIDTH-1:0] ROUTER_Y = 0
) (
    input  flit_t     flit_in,
    input  logic      is_head,
    output port_dir_e out_port
);

  always_comb begin
    if (is_head)
      out_port = xy_route(ROUTER_X, ROUTER_Y, flit_in.dest_x, flit_in.dest_y);
    else
      out_port = PORT_LOCAL;  // don't-care for body/tail flits
  end

endmodule : route_compute
