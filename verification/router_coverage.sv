// =============================================================================
// router_coverage.sv                                                   [ADD]
// Functional coverage subscriber, fed from router_monitor.in_ap. Tracks
// destination coordinate coverage, flit type, and the "route case" a packet
// exercises (same-node, same-row / pure E-W, same-column / pure N-S, or a
// diagonal move that forces a turn) -- the corner cases that matter most for
// an XY-routed mesh -- plus a full dest_x x dest_y cross.
// =============================================================================
class router_coverage extends uvm_subscriber #(packet);
  `uvm_component_utils(router_coverage)

  packet cov_pkt;

  covergroup cg_packet;
    option.per_instance = 1;

    cp_dest_x: coverpoint cov_pkt.dest_x { bins x[] = {[0:noc_pkg::MESH_DIM_X-1]}; }
    cp_dest_y: coverpoint cov_pkt.dest_y { bins y[] = {[0:noc_pkg::MESH_DIM_Y-1]}; }
    cp_flit_type: coverpoint cov_pkt.flit_type;

    cp_route_case: coverpoint route_case(cov_pkt) {
      bins same_node = {0};   // dest == src (local-port loopback)
      bins same_row   = {1};  // dest_y == src_y, dest_x != src_x -> pure E/W
      bins same_col   = {2};  // dest_x == src_x, dest_y != src_y -> pure N/S
      bins diagonal    = {3}; // differs in both x and y -> exercises a turn
    }

    cx_dest: cross cp_dest_x, cp_dest_y;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_packet = new();
  endfunction

  function int route_case(packet p);
    if (p.dest_x == p.src_x && p.dest_y == p.src_y) return 0;
    if (p.dest_y == p.src_y) return 1;
    if (p.dest_x == p.src_x) return 2;
    return 3;
  endfunction

  function void write(packet t);
    cov_pkt = t;
    cg_packet.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("Functional coverage = %0.2f%%", cg_packet.get_coverage()), UVM_LOW)
  endfunction

endclass : router_coverage
