// =============================================================================
// driver.sv                                                            [ADD]
// UVM driver: pulls packet items off its sequencer and drives them onto one
// flit-level port (port_id, set via config_db) using a standard valid/ready
// handshake. One driver instance is created per port by env.sv.
// =============================================================================
class driver extends uvm_driver #(packet);
  `uvm_component_utils(driver)

  virtual router_if.DRIVER vif;
  int unsigned             port_id;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual router_if.DRIVER)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "virtual interface not set for driver (uvm_config_db get failed)")
    if (!uvm_config_db#(int unsigned)::get(this, "", "port_id", port_id))
      `uvm_fatal("DRV", "port_id not set for driver (uvm_config_db get failed)")
  endfunction

  task run_phase(uvm_phase phase);
    // ports idle at reset
    vif.valid_in[port_id] <= 1'b0;
    forever begin
      packet pkt;
      seq_item_port.get_next_item(pkt);
      drive_packet(pkt);
      seq_item_port.item_done();
    end
  endtask

  task drive_packet(packet pkt);
    vif.flit_in[port_id].dest_x    <= pkt.dest_x;
    vif.flit_in[port_id].dest_y    <= pkt.dest_y;
    vif.flit_in[port_id].src_x     <= pkt.src_x;
    vif.flit_in[port_id].src_y     <= pkt.src_y;
    vif.flit_in[port_id].flit_type <= pkt.flit_type;
    vif.flit_in[port_id].seq_id    <= pkt.seq_id;
    vif.flit_in[port_id].payload   <= pkt.payload;
    vif.valid_in[port_id]          <= 1'b1;

    @(posedge vif.clk);
    while (!vif.ready_out[port_id]) @(posedge vif.clk);

    vif.valid_in[port_id] <= 1'b0;
  endtask

endclass : driver
