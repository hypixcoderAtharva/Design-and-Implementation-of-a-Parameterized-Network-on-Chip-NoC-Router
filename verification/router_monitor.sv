// =============================================================================
// router_monitor.sv
// Passive UVM monitor: snoops the accept handshake on every input port and
// the forward handshake on every output port, publishing each observed
// transaction as a packet on two analysis ports (in_ap / out_ap). Feeds
// router_scoreboard.sv (checking) and router_coverage.sv (functional
// coverage).
//
// This file was not in your "Add" list (implying it already exists); it is
// re-created here to keep the package self-contained.
// =============================================================================
class router_monitor extends uvm_monitor;
  `uvm_component_utils(router_monitor)

  virtual router_if.MONITOR vif;

  uvm_analysis_port #(packet) in_ap;    // packets accepted at an input port
  uvm_analysis_port #(packet) out_ap;   // packets emitted at an output port

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_ap  = new("in_ap", this);
    out_ap = new("out_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual router_if.MONITOR)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "virtual interface not set for router_monitor (uvm_config_db get failed)")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      watch_inputs();
      watch_outputs();
    join
  endtask

  // observation counters -- these are what the scoreboard's expected/actual
  // totals are derived from, so reporting them separates "the DUT dropped a
  // flit" from "the monitor never saw it"
  int unsigned n_in_obs  = 0;
  int unsigned n_out_obs = 0;

  task watch_inputs();
    forever begin
      @(posedge vif.clk);
      for (int p = 0; p < $size(vif.valid_in); p++) begin
        if (vif.valid_in[p] && vif.ready_out[p]) begin
          n_in_obs++;
          in_ap.write(to_packet(vif.flit_in[p]));
        end
      end
    end
  endtask

  task watch_outputs();
    forever begin
      @(posedge vif.clk);
      for (int p = 0; p < $size(vif.valid_out); p++) begin
        if (vif.valid_out[p] && vif.ready_in[p]) begin
          n_out_obs++;
          out_ap.write(to_packet(vif.flit_out[p]));
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("MON", $sformatf("observed %0d input accept(s), %0d output forward(s) on %0d link(s)",
              n_in_obs, n_out_obs, $size(vif.valid_in)), UVM_LOW)
  endfunction

  function packet to_packet(noc_pkg::flit_t f);
    packet pkt = packet::type_id::create("pkt");
    pkt.dest_x    = f.dest_x;
    pkt.dest_y    = f.dest_y;
    pkt.src_x     = f.src_x;
    pkt.src_y     = f.src_y;
    pkt.flit_type = f.flit_type;
    pkt.seq_id    = f.seq_id;
    pkt.payload   = f.payload;
    return pkt;
  endfunction

endclass : router_monitor
