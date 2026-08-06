// =============================================================================
// router_test.sv
// UVM test library. base_test builds the env and provides the shared
// run_traffic() helper; the derived tests each select a traffic pattern.
// Not in your requested file list, but the testbench tops need at least one
// uvm_test to run, so a small library is included:
//   base_test            - env only, no traffic (smoke / reset check)
//   uniform_random_test  - random destinations from every node
//   bit_complement_test  - worst-case-distance traffic
//   transpose_test       - diagonal / turn-heavy traffic
//   hotspot_test         - all nodes -> one node, congestion + backpressure
//   backpressure_test    - uniform traffic with randomized ready_in stalling
//   self_dest_test       - every node addresses itself: local-port loopback
//   mixed_flit_test      - uniform traffic carrying HEAD/BODY/TAIL as well
//   oob_error_test       - out-of-mesh destinations: error_checker stimulus
//
// The last three were added on 2026-08-03 to close coverage holes the five
// traffic patterns structurally cannot reach; see docs/changelog.md. They are
// part of `run_cov_uvm.do`'s merged regression.
// =============================================================================
class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  env e;
  int unsigned num_agents       = noc_pkg::NUM_PORTS;
  int unsigned packets_per_node = 20;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int unsigned)::get(this, "", "num_agents", num_agents));
    uvm_config_db#(int unsigned)::set(this, "e", "num_agents", num_agents);
    e = env::type_id::create("e", this);
  endfunction

  // Shared traffic runner. drain_time lets in-flight flits reach their
  // destination before the scoreboard's report_phase would otherwise
  // declare them undelivered. Every derived test below calls this.
  task run_traffic(uvm_phase phase, traffic_pattern_e pat, time drain_time = 20us,
                   bit mixed_flit_types = 1'b0);
    traffic_generator tg = traffic_generator::type_id::create("tg");
    phase.raise_objection(this);

    tg.pattern          = pat;
    tg.packets_per_node = packets_per_node;
    tg.mixed_flit_types = mixed_flit_types;
    if (pat == HOTSPOT) begin
      tg.hotspot_x = 0;
      tg.hotspot_y = 0;
    end
    e.register_sequencers(tg);

    tg.start(null);
    #drain_time;

    phase.drop_objection(this);
  endtask

endclass : base_test


// ---------------------------------------------------------------------------
// Derived tests: each one just picks a traffic pattern and a drain time.
// ---------------------------------------------------------------------------
class uniform_random_test extends base_test;
  `uvm_component_utils(uniform_random_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    run_traffic(phase, UNIFORM_RANDOM, 20us);
  endtask
endclass : uniform_random_test


class bit_complement_test extends base_test;
  `uvm_component_utils(bit_complement_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    // worst-case hop count -- longest paths in the mesh
    run_traffic(phase, BIT_COMPLEMENT, 30us);
  endtask
endclass : bit_complement_test


class transpose_test extends base_test;
  `uvm_component_utils(transpose_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    // turn-heavy: every packet changes dimension at least once under XY routing
    run_traffic(phase, TRANSPOSE, 30us);
  endtask
endclass : transpose_test


class neighbor_test extends base_test;
  `uvm_component_utils(neighbor_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    // minimum-hop traffic -- highest achievable throughput
    run_traffic(phase, NEIGHBOR, 15us);
  endtask
endclass : neighbor_test


class hotspot_test extends base_test;
  `uvm_component_utils(hotspot_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    // all nodes target router (0,0): maximum congestion, longest drain
    run_traffic(phase, HOTSPOT, 40us);
  endtask
endclass : hotspot_test


class backpressure_test extends base_test;
  `uvm_component_utils(backpressure_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    // enable randomized ready_in stalling in every receiver before the
    // agents (and therefore the receivers) are constructed
    uvm_config_db#(bit)::set(this, "e.*.rcv", "random_backpressure", 1'b1);
    uvm_config_db#(int unsigned)::set(this, "e.*.rcv", "ready_prob_pct", 40);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_traffic(phase, UNIFORM_RANDOM, 60us);
  endtask
endclass : backpressure_test


// ---------------------------------------------------------------------------
// Coverage-directed tests. Each one reaches something the five traffic
// patterns above structurally cannot.
// ---------------------------------------------------------------------------

// Every node addresses itself. This is the only stimulus in which xy_route
// returns PORT_L for a flit that arrived on the LOCAL input, and the only one
// that reaches router_coverage's cp_route_case.same_node bin.
class self_dest_test extends base_test;
  `uvm_component_utils(self_dest_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    run_traffic(phase, SELF_DEST, 15us);
  endtask
endclass : self_dest_test


// Uniform traffic carrying HEAD/BODY/TAIL as well as SINGLE. Track A routes on
// the destination alone and carries flit_type transparently, so this is legal
// stimulus for the design as built; it closes the three cp_flit_type bins that
// were permanently missing (V7) and toggles the flit_type field of every flit
// register in the mesh.
class mixed_flit_test extends base_test;
  `uvm_component_utils(mixed_flit_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    run_traffic(phase, UNIFORM_RANDOM, 20us, .mixed_flit_types(1'b1));
  endtask
endclass : mixed_flit_test


// Destinations outside the 4x4 mesh. error_checker.sv exists to catch exactly
// this, and nothing else in the regression raises out_of_bounds_flag,
// error_detected or error_count.
//
// Such a flit is unroutable: XY routing steers it toward the mesh boundary,
// where the outward link is tied off, so it occupies a buffer permanently and
// eventually wedges the node that injected it. That is the intended behaviour,
// not a defect -- hence the small packet count, the short drain, and
// expect_undelivered on the scoreboard. Delivery is not what this test checks;
// it checks that the error path fires and that nothing is mis-delivered.
class oob_error_test extends base_test;
  `uvm_component_utils(oob_error_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    packets_per_node = 4;
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_db#(bit)::set(this, "e.sb", "expect_undelivered", 1'b1);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    run_traffic(phase, OUT_OF_BOUNDS, 10us);
  endtask
endclass : oob_error_test
