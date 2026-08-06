// =============================================================================
// flow_control.sv
// -----------------------------------------------------------------------------
// Input-side half of credit-based flow control. Every time this input
// port's per-VC FIFO is popped (a slot just freed up), a credit pulse is
// registered and sent back upstream so the sender's credit_manager can
// re-enable that VC. Instantiated once per input port, inside
// input_buffer.sv; the matching output-side bookkeeping lives in
// credit_manager.sv / output_controller.sv.
// =============================================================================

module flow_control
  import router_config_pkg::*;
(
  input  logic                clk,
  input  logic                rst_n,

  input  logic [NUM_VCS-1:0]  vc_popped,   // this VC's FIFO was read this cycle

  output logic [NUM_VCS-1:0]  credit_out   // registered pulse sent upstream
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) credit_out <= '0;
    else        credit_out <= vc_popped;
  end

endmodule : flow_control
