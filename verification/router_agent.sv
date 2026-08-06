// =============================================================================
// router_agent.sv
// Per-port UVM agent: sequencer + driver (stimulus into the port) and a
// receiver (consumes output flits and drives ready_in). env.sv creates one
// agent per port/node. Not in the requested file list, but needed to give
// env.sv a clean per-port container instead of a flat sea of components.
// =============================================================================
class router_agent extends uvm_agent;
  `uvm_component_utils(router_agent)

  int unsigned port_id;

  uvm_sequencer #(packet) seqr;
  driver                  drv;
  receiver                rcv;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(int unsigned)::get(this, "", "port_id", port_id))
      `uvm_fatal("AGENT", "port_id not set for router_agent (uvm_config_db get failed)")

    // propagate port_id down to the driver and receiver
    uvm_config_db#(int unsigned)::set(this, "drv", "port_id", port_id);
    uvm_config_db#(int unsigned)::set(this, "rcv", "port_id", port_id);

    seqr = uvm_sequencer#(packet)::type_id::create("seqr", this);
    drv  = driver::type_id::create("drv", this);
    rcv  = receiver::type_id::create("rcv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction

endclass : router_agent
