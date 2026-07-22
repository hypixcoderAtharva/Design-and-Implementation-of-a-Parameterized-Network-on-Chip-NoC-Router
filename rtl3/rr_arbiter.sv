// =============================================================================
// rr_arbiter.sv
// -----------------------------------------------------------------------------
// Generic fixed-width round-robin arbiter. One-hot grant, rotating priority
// pointer that advances past the most recently granted requester. Used
// throughout vc_allocator.sv and switch_allocator.sv.
// =============================================================================

module rr_arbiter #(
  parameter int WIDTH = 5
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic [WIDTH-1:0]   req,
  input  logic               advance,      // rotate priority past this grant
  output logic [WIDTH-1:0]   grant,        // one-hot
  output logic               grant_valid
);

  localparam int PTR_W = (WIDTH > 1) ? $clog2(WIDTH) : 1;

  logic [PTR_W-1:0] base;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      base <= '0;
    end else if (advance && grant_valid) begin
      base <= (base == WIDTH-1) ? '0 : base + 1'b1;
    end
  end

  always_comb begin
    grant       = '0;
    grant_valid = |req;
    for (int offset = 0; offset < WIDTH; offset++) begin
      int idx;
      idx = (base + offset) % WIDTH;
      if (req[idx] && (grant == '0)) begin
        grant[idx] = 1'b1;
      end
    end
  end

endmodule : rr_arbiter
