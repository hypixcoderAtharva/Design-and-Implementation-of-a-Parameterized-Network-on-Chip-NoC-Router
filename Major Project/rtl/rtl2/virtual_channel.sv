// =============================================================================
// virtual_channel.sv
// -----------------------------------------------------------------------------
// Per-VC control FSM: IDLE -> ROUTING -> VA -> ACTIVE, repeating the
// switch-allocation/traversal request in ACTIVE for every flit of the
// packet until the tail flit is granted. One instance per VC, per input
// port, instantiated inside input_buffer.sv.
// =============================================================================

module virtual_channel
  import noc_pkg::*;
  import router_config_pkg::*;
(
  input  logic                clk,
  input  logic                rst_n,

  // status of this VC's FIFO
  input  logic                flit_avail,     // FIFO not empty
  input  flit_type_e          head_ftype,     // type of flit at the FIFO head
  input  direction_e          route_port,     // route_compute result

  // VC allocation handshake
  output logic                va_request,
  input  logic                va_grant,
  input  logic [VC_ID_W-1:0]  va_grant_vc,

  // switch allocation handshake
  output logic                sa_request,
  input  logic                sa_grant,
  input  logic                vc_has_credit,  // room on the granted output VC

  // pop the FIFO once this flit wins switch traversal
  output logic                fifo_pop,

  // this VC's committed routing decision, held for the packet's lifetime
  output direction_e          req_port,       // chosen output port
  output logic [VC_ID_W-1:0]  out_vc,         // output VC granted by VA
  output vc_state_e           state
);

  vc_state_e   cur_state, nxt_state;
  direction_e  bound_port;
  logic [VC_ID_W-1:0] bound_vc;

  assign state    = cur_state;
  assign req_port = bound_port;
  assign out_vc   = bound_vc;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cur_state  <= VC_IDLE;
      bound_port <= DIR_LOCAL;
      bound_vc   <= '0;
    end else begin
      cur_state <= nxt_state;
      if (cur_state == VC_ROUTING)          bound_port <= route_port;
      if (cur_state == VC_VA && va_grant)   bound_vc   <= va_grant_vc;
    end
  end

  always_comb begin
    nxt_state  = cur_state;
    va_request = 1'b0;
    sa_request = 1'b0;
    fifo_pop   = 1'b0;

    unique case (cur_state)
      VC_IDLE: begin
        if (flit_avail) nxt_state = VC_ROUTING;
      end

      VC_ROUTING: begin
        nxt_state = VC_VA;
      end

      VC_VA: begin
        va_request = 1'b1;
        if (va_grant) nxt_state = VC_ACTIVE;
      end

      VC_ACTIVE: begin
        sa_request = flit_avail && vc_has_credit;
        if (sa_grant) begin
          fifo_pop = 1'b1;
          if (head_ftype == FLIT_TAIL || head_ftype == FLIT_HEAD_TAIL) begin
            nxt_state = VC_IDLE;
          end
        end
      end

      default: nxt_state = VC_IDLE;
    endcase
  end

endmodule : virtual_channel