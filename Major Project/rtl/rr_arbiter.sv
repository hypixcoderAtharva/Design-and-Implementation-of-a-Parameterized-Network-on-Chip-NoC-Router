// rr_arbiter.sv
// Round-robin arbiter used once per output port to pick which input
// wins the crossbar - the "SA" pipeline stage.
//
// Wormhole switching needs the winner to keep the output for the
// whole packet, not just one flit, so this arbiter LOCKS onto its
// grant once it fires and keeps re-granting the same requester every
// cycle (ignoring req/round-robin) until release_hold pulses - which
// the winning port_ctrl asserts the cycle its tail flit is sent.
// Only after release does the round-robin pointer advance and a new
// winner get picked.

module rr_arbiter
  import noc_pkg::*;
#(
    parameter int NUM_REQ = NUM_PORTS
) (
    input logic clk,
    input logic rst_n,

    input  logic [NUM_REQ-1:0] req,
    input  logic               release_hold,
    output logic [NUM_REQ-1:0] grant,
    output logic               grant_valid
);

  localparam int PTR_WIDTH = (NUM_REQ <= 1) ? 1 : $clog2(NUM_REQ);

  logic                  locked_q;
  logic [NUM_REQ-1:0]    locked_grant_q;
  logic [PTR_WIDTH-1:0]  ptr_q;

  logic [NUM_REQ-1:0] mask;
  logic [NUM_REQ-1:0] req_masked;
  logic [NUM_REQ-1:0] grant_masked;
  logic [NUM_REQ-1:0] grant_unmasked;
  logic [NUM_REQ-1:0] new_grant;

  // returns a one-hot vector for the lowest-index set bit of r
  function automatic logic [NUM_REQ-1:0] fixed_priority(input logic [NUM_REQ-1:0] r);
    logic found;
    fixed_priority = '0;
    found = 1'b0;
    for (int i = 0; i < NUM_REQ; i++) begin
      if (r[i] && !found) begin
        fixed_priority[i] = 1'b1;
        found = 1'b1;
      end
    end
  endfunction

  always_comb begin
    for (int i = 0; i < NUM_REQ; i++) mask[i] = (i > ptr_q);

    req_masked     = req & mask;
    grant_masked   = fixed_priority(req_masked);
    grant_unmasked = fixed_priority(req);
    new_grant      = (|req_masked) ? grant_masked : grant_unmasked;

    if (locked_q) begin
      grant       = locked_grant_q;
      grant_valid = 1'b1;
    end else begin
      grant       = new_grant;
      grant_valid = |req;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      locked_q       <= 1'b0;
      locked_grant_q <= '0;
      ptr_q          <= '0;
    end else if (locked_q) begin
      if (release_hold) begin
        locked_q <= 1'b0;
        for (int i = 0; i < NUM_REQ; i++)
          if (locked_grant_q[i]) ptr_q <= i[PTR_WIDTH-1:0];
      end
    end else if (grant_valid) begin
      locked_q       <= 1'b1;
      locked_grant_q <= grant;
    end
  end

endmodule : rr_arbiter
