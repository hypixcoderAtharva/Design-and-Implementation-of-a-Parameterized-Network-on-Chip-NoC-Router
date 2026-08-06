// =============================================================================
// performance_monitor.sv                                               [ADD]
// Per-router hardware performance counters: flits accepted, flits forwarded,
// cycles the router was active, per-port busy-cycle accumulation, and cycles
// lost to input-side backpressure. One instance is intended per router;
// noc_mesh_top.sv instantiates one per mesh node and feeds the results into
// statistics.sv for mesh-wide aggregation.
// =============================================================================
module performance_monitor
  import noc_pkg::*;
(
  input logic clk,
  input logic rst_n,

  input logic valid_in  [NUM_PORTS],
  input logic ready_out [NUM_PORTS],
  input logic valid_out [NUM_PORTS],
  input logic ready_in  [NUM_PORTS],

  output logic [31:0] flits_accepted,      // valid_in && ready_out events
  output logic [31:0] flits_forwarded,     // valid_out && ready_in events
  output logic [31:0] cycles_active,       // cycles with at least one accept/forward
  output logic [31:0] busy_cycles_sum,     // sum over ports of cycles valid_out was high
  output logic [31:0] input_stall_cycles   // valid_in high while ready_out low
);

  logic [$clog2(NUM_PORTS+1)-1:0] accept_cnt, forward_cnt, busy_cnt, stall_cnt;
  logic                           any_active;

  always_comb begin
    accept_cnt  = '0;
    forward_cnt = '0;
    busy_cnt    = '0;
    stall_cnt   = '0;
    for (int i = 0; i < NUM_PORTS; i++) begin
      if (valid_in[i]  && ready_out[i])  accept_cnt  = accept_cnt  + 1'b1;
      if (valid_out[i] && ready_in[i])   forward_cnt = forward_cnt + 1'b1;
      if (valid_out[i])                  busy_cnt    = busy_cnt    + 1'b1;
      if (valid_in[i]  && !ready_out[i]) stall_cnt   = stall_cnt   + 1'b1;
    end
  end
  assign any_active = (accept_cnt != 0) || (forward_cnt != 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      flits_accepted     <= '0;
      flits_forwarded    <= '0;
      cycles_active       <= '0;
      busy_cycles_sum     <= '0;
      input_stall_cycles  <= '0;
    end else begin
      flits_accepted    <= flits_accepted  + 32'(accept_cnt);
      flits_forwarded   <= flits_forwarded + 32'(forward_cnt);
      busy_cycles_sum   <= busy_cycles_sum + 32'(busy_cnt);
      input_stall_cycles<= input_stall_cycles + 32'(stall_cnt);
      if (any_active) cycles_active <= cycles_active + 1'b1;
    end
  end

endmodule : performance_monitor
