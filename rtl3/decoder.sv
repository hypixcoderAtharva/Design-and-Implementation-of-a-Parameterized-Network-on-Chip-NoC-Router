// =============================================================================
// decoder.sv
// -----------------------------------------------------------------------------
// Generic binary-to-one-hot decoder, gated by an enable.
// Used by input_buffer (steer an incoming flit to its target VC FIFO) and
// vc_allocator (turn the newly-consumed free-VC index into a clear mask).
// =============================================================================

module decoder #(
  parameter int IN_WIDTH  = 3,
  parameter int OUT_WIDTH = 5
) (
  input  logic [IN_WIDTH-1:0]   in_idx,
  input  logic                  en,
  output logic [OUT_WIDTH-1:0]  out_vec
);

  always_comb begin
    out_vec = '0;
    if (en && (in_idx < OUT_WIDTH)) out_vec[in_idx] = 1'b1;
  end

endmodule : decoder
