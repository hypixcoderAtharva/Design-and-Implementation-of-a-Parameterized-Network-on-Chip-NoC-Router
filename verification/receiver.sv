// =============================================================================
// receiver.sv                                                          [ADD]
// UVM component that owns the "downstream" side of one port: it drives
// ready_in (either always-ready, or randomized back-pressure) and captures
// every accepted output flit into a packet, published on an analysis port.
// One receiver instance is created per port by env.sv. This is the active
// counterpart to router_monitor.sv's passive observation.
// =============================================================================
class receiver extends uvm_component;
  `uvm_component_utils(receiver)

  virtual router_if.RECEIVER vif;
  int unsigned               port_id;

  // optional randomized back-pressure, configured via config_db if desired
  bit          random_backpressure = 0;
  int unsigned ready_prob_pct      = 100;   // % chance ready is asserted each cycle

  uvm_analysis_port #(packet) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual router_if.RECEIVER)::get(this, "", "vif", vif))
      `uvm_fatal("RCV", "virtual interface not set for receiver (uvm_config_db get failed)")
    if (!uvm_config_db#(int unsigned)::get(this, "", "port_id", port_id))
      `uvm_fatal("RCV", "port_id not set for receiver (uvm_config_db get failed)")
    void'(uvm_config_db#(bit)::get(this, "", "random_backpressure", random_backpressure));
    void'(uvm_config_db#(int unsigned)::get(this, "", "ready_prob_pct", ready_prob_pct));
  endfunction

  task run_phase(uvm_phase phase);
    bit ready_this_cycle;
    vif.ready_in[port_id] <= 1'b0;
    forever begin
      @(posedge vif.clk);
      ready_this_cycle = random_backpressure ?
                          ($urandom_range(99, 0) < ready_prob_pct) : 1'b1;
      vif.ready_in[port_id] <= ready_this_cycle;

      if (vif.valid_out[port_id] && ready_this_cycle) begin
        capture(vif.flit_out[port_id]);
      end
    end
  endtask

  function void capture(noc_pkg::flit_t f);
    packet pkt = packet::type_id::create("pkt");
    pkt.dest_x    = f.dest_x;
    pkt.dest_y    = f.dest_y;
    pkt.src_x     = f.src_x;
    pkt.src_y     = f.src_y;
    pkt.flit_type = f.flit_type;
    pkt.seq_id    = f.seq_id;
    pkt.payload   = f.payload;
    ap.write(pkt);
  endfunction

endclass : receiver
