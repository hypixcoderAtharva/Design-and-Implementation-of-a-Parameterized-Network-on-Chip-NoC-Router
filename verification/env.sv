// =============================================================================
// env.sv                                                               [ADD]
// UVM environment. Builds NUM_AGENTS per-port agents (sequencer + driver +
// receiver), one passive router_monitor, one router_scoreboard and one
// router_coverage collector, then wires the analysis paths:
//
//   monitor.in_ap  -> scoreboard.in_imp      (expected packets)
//   monitor.in_ap  -> coverage.analysis_export (functional coverage)
//   monitor.out_ap -> scoreboard.out_export  (actual packets, via TLM FIFO)
//
// NUM_AGENTS comes from config_db so the same env serves both testbenches:
//   tb_router.sv       -> NUM_AGENTS = NUM_PORTS (5)
//   tb_noc_mesh_top.sv -> NUM_AGENTS = MESH_DIM_X * MESH_DIM_Y (16)
// =============================================================================
class env extends uvm_env;
  `uvm_component_utils(env)

  int unsigned num_agents = noc_pkg::NUM_PORTS;

  router_agent      agents[$];
  router_monitor    mon;
  router_scoreboard sb;
  router_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    void'(uvm_config_db#(int unsigned)::get(this, "", "num_agents", num_agents));
    `uvm_info("ENV", $sformatf("building env with %0d agent(s)", num_agents), UVM_LOW)

    for (int i = 0; i < num_agents; i++) begin
      string aname = $sformatf("agent_%0d", i);
      router_agent a;
      uvm_config_db#(int unsigned)::set(this, aname, "port_id", i);
      a = router_agent::type_id::create(aname, this);
      agents.push_back(a);
    end

    mon = router_monitor::type_id::create("mon", this);
    sb  = router_scoreboard::type_id::create("sb",  this);
    cov = router_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.in_ap.connect(sb.in_imp);
    mon.in_ap.connect(cov.analysis_export);
    mon.out_ap.connect(sb.out_export);
  endfunction

  // convenience: hand every agent's sequencer to a traffic_generator
  function void register_sequencers(traffic_generator tg);
    foreach (agents[i]) tg.add_sequencer(agents[i].seqr);
  endfunction

endclass : env
