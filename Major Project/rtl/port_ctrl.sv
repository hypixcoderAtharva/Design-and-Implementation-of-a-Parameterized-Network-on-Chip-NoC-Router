// port_ctrl.sv
// One instance per input port. Sequences a packet through the
// remaining pipeline stages once it's sitting in the input buffer:
//   IDLE       - wait for a head flit
//   ARBITRATE  - request the routed output port, wait for grant (SA)
//   ACTIVE     - drive the crossbar, flit by flit, until the tail
//                flit is transferred (ST), then release the arbiter
//
// arb_req / arb_grant are NUM_PORTS-wide, one bit per possible output
// port (bit position = port_dir_e value), so this module can talk to
// all NUM_PORTS output arbiters through one bus each.

module port_ctrl
  import noc_pkg::*;
(
    input logic clk,
    input logic rst_n,

    // this port's input buffer
    input  logic  buf_valid,
    output logic  buf_ready,
    input  flit_t buf_flit,

    // this port's route_compute result (combinational, valid on head flits)
    input port_dir_e route_port_in,

    // to / from the NUM_PORTS output-port arbiters
    output logic [NUM_PORTS-1:0] arb_req,
    input  logic [NUM_PORTS-1:0] arb_grant,
    output logic                 release_o,

    // to the crossbar
    output logic      xbar_valid,
    output flit_t     xbar_flit,
    output port_dir_e xbar_sel_port,

    // downstream readiness for whichever output this input is
    // currently targeting (muxed externally by xbar_sel_port)
    input logic xbar_ready
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_ARBITRATE,
    S_ACTIVE
  } state_e;

  state_e    state_q, state_n;
  port_dir_e route_port_q;

  logic is_head;
  logic is_tail;

  assign is_head = buf_valid && (buf_flit.flit_type == FLIT_HEAD ||
                                  buf_flit.flit_type == FLIT_HEAD_TAIL);
  assign is_tail = (buf_flit.flit_type == FLIT_TAIL ||
                     buf_flit.flit_type == FLIT_HEAD_TAIL);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= S_IDLE;
      route_port_q <= PORT_LOCAL;
    end else begin
      state_q <= state_n;
      if (state_q == S_IDLE && is_head) route_port_q <= route_port_in;
    end
  end

  always_comb begin
    state_n       = state_q;
    buf_ready     = 1'b0;
    arb_req       = '0;
    release_o     = 1'b0;
    xbar_valid    = 1'b0;
    xbar_flit     = buf_flit;
    xbar_sel_port = route_port_q;

    unique case (state_q)

      S_IDLE: begin
        if (is_head) state_n = S_ARBITRATE;
      end

      S_ARBITRATE: begin
        arb_req[route_port_q] = 1'b1;
        if (arb_grant[route_port_q]) state_n = S_ACTIVE;
      end

      S_ACTIVE: begin
        xbar_valid = buf_valid;
        if (buf_valid && xbar_ready) begin
          buf_ready = 1'b1;
          if (is_tail) begin
            release_o = 1'b1;
            state_n   = S_IDLE;
          end
        end
      end

      default: state_n = S_IDLE;

    endcase
  end

endmodule : port_ctrl
