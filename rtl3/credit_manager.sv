// =============================================================================
// credit_manager.sv
// -----------------------------------------------------------------------------
// Per-output-port credit counters, one per VC. Tracks how many free flit
// slots remain in the downstream neighbour's input VC buffer:
//   - increments on credit_in[v]  (downstream popped its FIFO, freeing a slot)
//   - decrements on consume[v]    (this router just sent a flit on VC v)
// has_credit[v] gates whether switch allocation may send another flit on
// that VC. Instantiated once per output port, inside output_controller.sv.
// =============================================================================

module credit_manager #(
  parameter int NUM_VCS  = 4,
  parameter int VC_DEPTH = 4
) (
  input  logic clk,
  input  logic rst_n,

  input  logic [NUM_VCS-1:0] consume,    // a flit was sent on this VC this cycle
  input  logic [NUM_VCS-1:0] credit_in,  // downstream freed a slot on this VC

  output logic [NUM_VCS-1:0] has_credit
);

  localparam int CW = $clog2(VC_DEPTH + 1);

  logic [CW-1:0] credits [NUM_VCS];

  genvar i;
  generate
    for (i = 0; i < NUM_VCS; i++) begin : g_credit

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          credits[i] <= CW'(VC_DEPTH);
        end else begin
          case ({credit_in[i], consume[i]})
            2'b10:   credits[i] <= (credits[i] == CW'(VC_DEPTH)) ? credits[i] : credits[i] + 1'b1;
            2'b01:   credits[i] <= credits[i] - 1'b1;
            default: credits[i] <= credits[i];
          endcase
        end
      end

      assign has_credit[i] = (credits[i] != 0);
    end
  endgenerate

endmodule : credit_manager
