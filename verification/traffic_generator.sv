// =============================================================================
// traffic_generator.sv                                                 [ADD]
// Virtual sequence that orchestrates mesh-wide traffic patterns by starting
// packet_generator sub-sequences on every node's sequencer in parallel.
// Supported patterns:
//   UNIFORM_RANDOM - each node sends to random in-bounds destinations
//   BIT_COMPLEMENT - node (x,y) sends to (NX-1-x, NY-1-y): worst-case distance
//   TRANSPOSE      - node (x,y) sends to (y,x): stresses diagonal turns
//   HOTSPOT        - every node sends to one fixed corner node: congestion
//   NEIGHBOR       - node (x,y) sends to its east neighbor: minimum-hop
//   SELF_DEST      - node (x,y) sends to itself: local-port loopback, the
//                    only pattern that reaches xy_route's PORT_L arm from a
//                    LOCAL input and the cp_route_case.same_node bin
//   OUT_OF_BOUNDS  - destinations outside the mesh: exercises error_checker.
//                    These flits are unroutable by design and never arrive.
// env.sv publishes the sequencer handles this class picks up from config_db.
// =============================================================================
typedef enum {
  UNIFORM_RANDOM,
  BIT_COMPLEMENT,
  TRANSPOSE,
  HOTSPOT,
  NEIGHBOR,
  SELF_DEST,
  OUT_OF_BOUNDS
} traffic_pattern_e;

class traffic_generator extends uvm_sequence #(packet);
  `uvm_object_utils(traffic_generator)

  traffic_pattern_e pattern            = UNIFORM_RANDOM;
  int unsigned      packets_per_node   = 20;
  int unsigned      num_nodes          = 1;
  int unsigned      hotspot_x          = 0;
  int unsigned      hotspot_y          = 0;

  // inject HEAD/BODY/TAIL as well as FLIT_SINGLE (see packet.sv)
  bit               mixed_flit_types   = 0;

  // one sequencer per injecting node/port, fetched from config_db
  uvm_sequencer #(packet) seqrs[$];

  function new(string name = "traffic_generator");
    super.new(name);
  endfunction

  task body();
    if (seqrs.size() == 0)
      `uvm_fatal("TRAFGEN", "no sequencers registered -- call add_sequencer() from the test/env")

    `uvm_info("TRAFGEN", $sformatf("pattern=%s packets_per_node=%0d nodes=%0d",
              pattern.name(), packets_per_node, seqrs.size()), UVM_LOW)

    fork
      begin
        for (int n = 0; n < seqrs.size(); n++) begin
          automatic int nn = n;
          fork
            run_on_node(nn);
          join_none
        end
        wait fork;
      end
    join
  endtask

  task run_on_node(int n);
    packet_generator sub = packet_generator::type_id::create($sformatf("pgen_%0d", n));
    int unsigned nx = n % noc_pkg::MESH_DIM_X;
    int unsigned ny = n / noc_pkg::MESH_DIM_X;

    sub.num_packets      = packets_per_node;
    sub.node_x           = nx;
    sub.node_y           = ny;
    sub.mixed_flit_types = mixed_flit_types;

    case (pattern)
      UNIFORM_RANDOM : ;  // leave destinations free / randomized
      BIT_COMPLEMENT : sub.set_fixed_dest(noc_pkg::MESH_DIM_X-1-nx, noc_pkg::MESH_DIM_Y-1-ny);
      TRANSPOSE      : sub.set_fixed_dest(ny, nx);
      HOTSPOT        : sub.set_fixed_dest(hotspot_x, hotspot_y);
      NEIGHBOR       : sub.set_fixed_dest((nx + 1) % noc_pkg::MESH_DIM_X, ny);
      SELF_DEST      : sub.set_fixed_dest(nx, ny);
      // destination is left random, but packet.sv's c_dest_in_bounds inverts
      // itself when allow_oob_dest is set, so every dest lands outside the mesh
      OUT_OF_BOUNDS  : sub.allow_oob_dest = 1;
    endcase

    // TRANSPOSE on a diagonal node, and NEIGHBOR on a 1-wide mesh, can
    // resolve to dest == src; SELF_DEST always does. Allow it so
    // randomization does not fail.
    if (pattern == TRANSPOSE || pattern == NEIGHBOR || pattern == SELF_DEST)
      sub.allow_self_dest = 1;

    sub.start(seqrs[n]);
  endtask

  function void add_sequencer(uvm_sequencer #(packet) s);
    seqrs.push_back(s);
  endfunction

endclass : traffic_generator
