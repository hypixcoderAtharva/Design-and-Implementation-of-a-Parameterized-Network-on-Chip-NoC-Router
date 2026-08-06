// =============================================================================
// rr_arbiter.sv                                                        [FIX B3]
// Round-robin arbiter: grants exactly one requester per cycle among WIDTH
// request lines, rotating priority after every consumed grant.
//
// Unified signature serving BOTH router designs:
//   Track A  router.sv          -- one instance per output port
//   Track B  switch_allocator   -- stage-1 (per input) and stage-2 (per output)
//            vc_allocator       -- one instance per output port
//
// Previously this module took a NUM_REQ parameter and exposed only
// (clk, rst_n, req, grant), while every Track B instantiation used
// #(.WIDTH(n)) with additional .advance and .grant_valid ports. The
// parameter is now WIDTH and both extra ports exist, so a single arbiter
// serves the whole project.
//
//   advance     - when low, a grant is issued but the priority pointer is
//                 held. Lets a caller present a speculative grant that is
//                 not consumed this cycle without unfairly rotating priority.
//                 Tie to 1'b1 for classic round-robin behaviour.
//   grant_valid - |grant, i.e. "some requester won this cycle".
// =============================================================================
module rr_arbiter #(
  parameter int WIDTH = 5
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic [WIDTH-1:0] req,
  input  logic             advance,
  output logic [WIDTH-1:0] grant,
  output logic             grant_valid
);

  localparam int PTR_W = (WIDTH <= 1) ? 1 : $clog2(WIDTH);

  logic [PTR_W-1:0] base_ptr;

  // idx only ever holds a request index, 0..WIDTH-1, so it is sized to the
  // pointer width. It used to be a module-scope 32-bit `int` alongside the
  // loop counter; both are loop bookkeeping rather than state, and as 32-bit
  // module-scope variables they contributed 29 permanently-zero bits each to
  // the toggle database of every arbiter instance.
  logic [PTR_W-1:0] idx;

  // First requester at or after base_ptr wins (wrapping).
  always_comb begin
    grant = '0;
    for (int k = 0; k < WIDTH; k++) begin
      idx = PTR_W'((int'(base_ptr) + k) % WIDTH);
      if (req[idx] && (grant == '0)) grant[idx] = 1'b1;
    end
  end

  assign grant_valid = |grant;

  // Priority rotates past the winner, giving every requester a bounded
  // waiting time of at most WIDTH grant events.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      base_ptr <= '0;
    end else if (advance && grant_valid) begin
      for (int j = 0; j < WIDTH; j++) begin
        if (grant[j]) base_ptr <= PTR_W'((j + 1) % WIDTH);
      end
    end
  end

endmodule : rr_arbiter
