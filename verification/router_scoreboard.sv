// =============================================================================
// router_scoreboard.sv                                                 [ADD]
// Content-based scoreboard. Every packet accepted at an input port (from
// router_monitor.in_ap) is stored, keyed by (src_x, src_y, seq_id) -- unique
// per packet because each network_interface / injecting node increments its
// own seq_id counter. Every packet observed at an output port (via a TLM
// FIFO fed from router_monitor.out_ap) is looked up by that same key and
// checked for header/payload integrity. At the end of the test, any input
// packet never matched at an output is reported as dropped.
// =============================================================================
class router_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(router_scoreboard)

  uvm_analysis_imp #(packet, router_scoreboard) in_imp;

  uvm_analysis_export #(packet)     out_export;
  uvm_tlm_analysis_fifo #(packet)   out_fifo;

  packet       expected_q[string];
  int unsigned num_matched;
  int unsigned num_mismatched;
  int unsigned num_spurious;

  // Set by tests whose stimulus is deliberately undeliverable -- oob_error_test
  // injects out-of-mesh destinations, which XY routing steers into a tied-off
  // boundary link where they stay forever. The count is still reported; it just
  // is not an error. Everything else (mismatch, spurious, duplicate key) is
  // still checked exactly as before.
  bit expect_undelivered = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_imp     = new("in_imp", this);
    out_export = new("out_export", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    out_fifo = new("out_fifo", this);
    void'(uvm_config_db#(bit)::get(this, "", "expect_undelivered", expect_undelivered));
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    out_export.connect(out_fifo.analysis_export);
  endfunction

  function string key_of(packet pkt);
    return $sformatf("%0d_%0d_%0d", pkt.src_x, pkt.src_y, pkt.seq_id);
  endfunction

  // called automatically for every packet written to in_imp (input side)
  function void write(packet pkt);
    string key = key_of(pkt);
    // A duplicate key means seq_id is not unique per source: the previous
    // entry would be silently overwritten and its packet reported as
    // spurious on arrival. Fail loudly rather than corrupt the check.
    if (expected_q.exists(key))
      `uvm_error("SB", $sformatf(
        "duplicate packet key %s -- seq_id is not unique per source", key))
    expected_q[key] = pkt;
  endfunction

  task run_phase(uvm_phase phase);
    packet out_pkt;
    forever begin
      out_fifo.get(out_pkt);
      check_output(out_pkt);
    end
  endtask

  task check_output(packet actual);
    string key = key_of(actual);
    if (!expected_q.exists(key)) begin
      num_spurious++;
      `uvm_error("SB", $sformatf("Unmatched packet observed at output: %s", actual.convert2string()))
      return;
    end
    if (expected_q[key].payload != actual.payload ||
        expected_q[key].dest_x  != actual.dest_x  ||
        expected_q[key].dest_y  != actual.dest_y) begin
      num_mismatched++;
      `uvm_error("SB", $sformatf("Header/payload mismatch. expected=%s actual=%s",
                 expected_q[key].convert2string(), actual.convert2string()))
    end else begin
      num_matched++;
    end
    expected_q.delete(key);
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf(
      "Matched=%0d Mismatched=%0d Spurious=%0d Undelivered=%0d",
      num_matched, num_mismatched, num_spurious, expected_q.num()), UVM_LOW)
    if (expected_q.num() > 0) begin
      if (expect_undelivered)
        `uvm_info("SB", $sformatf(
          "%0d packet(s) undelivered, as expected for this test", expected_q.num()), UVM_LOW)
      else
        `uvm_error("SB", $sformatf(
          "%0d packet(s) were accepted by the router but never observed at any output",
          expected_q.num()))
    end
  endfunction

endclass : router_scoreboard
