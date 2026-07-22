// =============================================================================
// encoder.sv
// -----------------------------------------------------------------------------
// Generic priority encoder: highest-index set bit of in_vec wins.
// Used by vc_allocator (pick a free VC), switch_allocator (VC index of a
// stage-1 grant) and input_buffer (index of the switch-allocation winner).
// =============================================================================

module encoder #(
  parameter int IN_WIDTH  = 5,
  parameter int OUT_WIDTH = (IN_WIDTH > 1) ? $clog2(IN_WIDTH) : 1
) (
  input  logic [IN_WIDTH-1:0]   in_vec,
  output logic [OUT_WIDTH-1:0]  out_idx,
  output logic                  valid
);

  always_comb begin
    out_idx = '0;
    valid   = |in_vec;
    for (int i = IN_WIDTH - 1; i >= 0; i--) begin
      if (in_vec[i]) out_idx = i[OUT_WIDTH-1:0];
    end
  end

endmodule : encoder
