// =============================================================================
// tb_router_top.sv
// -----------------------------------------------------------------------------
// Self-checking directed testbench for router_top.sv. Not part of the
// synthesizable rtl/ file list -- add it separately to your sim-only file
// list (it is NOT included in filelist.f).
//
// Router under test sits at mesh coordinates (MY_X, MY_Y) = (1,1).
// Port index convention matches direction_e in noc_pkg.sv:
//   0 = North, 1 = South, 2 = East, 3 = West, 4 = Local
//
// Coverage:
//   Test 1 - single-flit packets routed to every direction (incl. Local)
//   Test 2 - a multi-flit packet (HEAD + body flits + TAIL)
//   Test 3 - two packets injected concurrently on different input ports,
//            to different output ports, exercising both allocators together
//   Test 4 - credit-based back-pressure: withhold the East output's
//            downstream credit, send a packet longer than VC_DEPTH, and
//            confirm the router stalls after VC_DEPTH flits and drains
//            the rest once credit is granted
//
// The scoreboard tracks one expected-flit queue per output port and
// compares every flit that leaves the DUT against it, in order.
//
// The stimulus tasks mirror the DUT's own input-side credit accounting
// (reusing credit_manager.sv) so they never write into a full input VC
// FIFO, exactly as a well-behaved upstream neighbour router would.
// =============================================================================

`timescale 1ns/1ps

module tb_router_top;
  import noc_pkg::*;
  import router_config_pkg::*;

  localparam int FW = $bits(flit_t);
  localparam logic [X_WIDTH-1:0] DUT_X = 4'd1;
  localparam logic [Y_WIDTH-1:0] DUT_Y = 4'd1;
  localparam int CLK_PERIOD = 10;

  localparam int PORT_N = 0;
  localparam int PORT_S = 1;
  localparam int PORT_E = 2;
  localparam int PORT_W = 3;
  localparam int PORT_L = 4;

  // -------------------------------------------------------------------
  // DUT hookup
  // -------------------------------------------------------------------
  logic clk = 0;
  logic rst_n = 0;

  logic [NUM_PORTS*FW-1:0]      in_flit_flat;
  logic [NUM_PORTS-1:0]         in_valid;
  logic [NUM_PORTS*VC_ID_W-1:0] in_vc_id_flat;
  logic [NUM_PORTS*NUM_VCS-1:0] credit_to_upstream;

  logic [NUM_PORTS*FW-1:0]      out_flit_flat;
  logic [NUM_PORTS-1:0]         out_valid;
  logic [NUM_PORTS*NUM_VCS-1:0] credit_from_downstream;

  router_top #(.MY_X(DUT_X), .MY_Y(DUT_Y)) dut (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .in_flit_flat           (in_flit_flat),
    .in_valid               (in_valid),
    .in_vc_id_flat          (in_vc_id_flat),
    .credit_to_upstream     (credit_to_upstream),
    .out_flit_flat          (out_flit_flat),
    .out_valid              (out_valid),
    .credit_from_downstream (credit_from_downstream)
  );

  always #(CLK_PERIOD/2) clk = ~clk;

  // -------------------------------------------------------------------
  // Mirror the DUT's own input-side credit bookkeeping (one instance
  // per input port) so stimulus never overruns a VC FIFO. Reuses the
  // same credit_manager block the DUT itself uses on its output side.
  // -------------------------------------------------------------------
  logic [NUM_PORTS*NUM_VCS-1:0] my_consume;
  logic [NUM_PORTS*NUM_VCS-1:0] my_has_credit;

  genvar cip;
  generate
    for (cip = 0; cip < NUM_PORTS; cip++) begin : g_send_credit
      credit_manager #(.NUM_VCS(NUM_VCS), .VC_DEPTH(VC_DEPTH)) u_send_credit (
        .clk        (clk),
        .rst_n      (rst_n),
        .consume    (my_consume[cip*NUM_VCS +: NUM_VCS]),
        .credit_in  (credit_to_upstream[cip*NUM_VCS +: NUM_VCS]),
        .has_credit (my_has_credit[cip*NUM_VCS +: NUM_VCS])
      );
    end
  endgenerate

  // -------------------------------------------------------------------
  // Scoreboard -- one expected-flit queue per output port. (Kept as
  // five named queues rather than an array of queues / a queue of a
  // struct type: both of those are unsupported by at least one common
  // open-source simulator.)
  // -------------------------------------------------------------------
  logic [FW-1:0] exp_q0[$];
  logic [FW-1:0] exp_q1[$];
  logic [FW-1:0] exp_q2[$];
  logic [FW-1:0] exp_q3[$];
  logic [FW-1:0] exp_q4[$];

  int unsigned recv_count [NUM_PORTS];
  int          pass_count = 0;
  int          fail_count = 0;

  task automatic push_expected(input int unsigned port, input flit_t f);
    case (port)
      0: exp_q0.push_back(f);
      1: exp_q1.push_back(f);
      2: exp_q2.push_back(f);
      3: exp_q3.push_back(f);
      4: exp_q4.push_back(f);
      default: ;
    endcase
  endtask

  function automatic int unsigned queue_size(input int unsigned port);
    case (port)
      0: queue_size = exp_q0.size();
      1: queue_size = exp_q1.size();
      2: queue_size = exp_q2.size();
      3: queue_size = exp_q3.size();
      4: queue_size = exp_q4.size();
      default: queue_size = 0;
    endcase
  endfunction

  function automatic flit_t pop_expected(input int unsigned port);
    case (port)
      0: pop_expected = flit_t'(exp_q0.pop_front());
      1: pop_expected = flit_t'(exp_q1.pop_front());
      2: pop_expected = flit_t'(exp_q2.pop_front());
      3: pop_expected = flit_t'(exp_q3.pop_front());
      4: pop_expected = flit_t'(exp_q4.pop_front());
      default: pop_expected = flit_t'('0);
    endcase
  endfunction

  // mirrors route_compute.sv's XY algorithm, to predict which output
  // port a given destination should arrive on
  function automatic int unsigned expected_port(input logic [X_WIDTH-1:0] dx,
                                                 input logic [Y_WIDTH-1:0] dy);
    if (dx != DUT_X)      expected_port = (dx > DUT_X) ? PORT_E : PORT_W;
    else if (dy != DUT_Y) expected_port = (dy > DUT_Y) ? PORT_S : PORT_N;
    else                  expected_port = PORT_L;
  endfunction

  genvar mp;
  generate
    for (mp = 0; mp < NUM_PORTS; mp++) begin : g_scoreboard
      always_ff @(posedge clk) begin
        flit_t got, exp;
        if (rst_n && out_valid[mp]) begin
          got = flit_t'(out_flit_flat[mp*FW +: FW]);
          recv_count[mp] = recv_count[mp] + 1;
          if (queue_size(mp) == 0) begin
            $display("[%0t] FAIL port%0d: unexpected flit, none was expected here (payload=%h)",
                      $time, mp, got.payload);
            fail_count = fail_count + 1;
          end else begin
            exp = pop_expected(mp);
            if (got === exp) begin
              $display("[%0t] PASS port%0d: flit matched (ftype=%0d vc=%0d dest=(%0d,%0d) payload=%h)",
                        $time, mp, got.ftype, got.vc_id, got.dest_x, got.dest_y, got.payload);
              pass_count = pass_count + 1;
            end else begin
              $display("[%0t] FAIL port%0d: flit mismatch. got payload=%h exp payload=%h",
                        $time, mp, got.payload, exp.payload);
              fail_count = fail_count + 1;
            end
          end
        end
      end
    end
  endgenerate

  // -------------------------------------------------------------------
  // Stimulus helpers
  // -------------------------------------------------------------------
  task automatic send_packet(
    input int unsigned           port,
    input logic [VC_ID_W-1:0]    vc,
    input logic [X_WIDTH-1:0]    dx,
    input logic [Y_WIDTH-1:0]    dy,
    input int unsigned           num_body_flits,
    input logic [FLIT_WIDTH-1:0] base_payload
  );
    int unsigned i, total_flits, eport;
    flit_t      f;
    flit_type_e ft;

    total_flits = (num_body_flits == 0) ? 1 : (num_body_flits + 2);
    eport       = expected_port(dx, dy);

    for (i = 0; i < total_flits; i = i + 1) begin
      if (total_flits == 1)          ft = FLIT_HEAD_TAIL;
      else if (i == 0)               ft = FLIT_HEAD;
      else if (i == total_flits - 1) ft = FLIT_TAIL;
      else                           ft = FLIT_BODY;

      f.ftype   = ft;
      f.vc_id   = vc;
      f.dest_x  = dx;
      f.dest_y  = dy;
      f.payload = base_payload + i;

      // wait for room in the DUT's input VC FIFO before sending
      while (my_has_credit[port*NUM_VCS + vc] !== 1'b1) @(posedge clk);

      push_expected(eport, f);

      @(negedge clk);
      in_flit_flat[port*FW +: FW]            = f;
      in_vc_id_flat[port*VC_ID_W +: VC_ID_W] = vc;
      in_valid[port]                         = 1'b1;
      my_consume[port*NUM_VCS + vc]          = 1'b1;
      @(negedge clk);
      in_valid[port]                = 1'b0;
      my_consume[port*NUM_VCS + vc] = 1'b0;
    end
  endtask

  task automatic wait_cycles(input int unsigned n);
    int unsigned i;
    for (i = 0; i < n; i = i + 1) @(posedge clk);
  endtask

  task automatic check(input bit cond, input string msg);
    if (cond) begin
      $display("[%0t] PASS: %s", $time, msg);
      pass_count = pass_count + 1;
    end else begin
      $display("[%0t] FAIL: %s", $time, msg);
      fail_count = fail_count + 1;
    end
  endtask

  task automatic do_reset;
    in_valid                = '0;
    in_vc_id_flat            = '0;
    in_flit_flat              = '0;
    my_consume                = '0;
    credit_from_downstream   = '1;  // idealized: unlimited downstream room by default
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
  endtask

  // -------------------------------------------------------------------
  // Test sequence
  // -------------------------------------------------------------------
  initial begin
    $display("=== router_top testbench starting (router at %0d,%0d) ===", DUT_X, DUT_Y);
    do_reset();

    $display("--- Test 1: single-flit routing, one packet per direction ---");
    send_packet(PORT_L, 0, DUT_X,          DUT_Y,          0, 32'hA000_0000); // -> Local
    wait_cycles(10);
    send_packet(PORT_L, 0, DUT_X + 4'd1,   DUT_Y,          0, 32'hA000_0001); // -> East
    wait_cycles(10);
    send_packet(PORT_L, 0, DUT_X - 4'd1,   DUT_Y,          0, 32'hA000_0002); // -> West
    wait_cycles(10);
    send_packet(PORT_L, 0, DUT_X,          DUT_Y + 4'd1,   0, 32'hA000_0003); // -> South
    wait_cycles(10);
    send_packet(PORT_L, 0, DUT_X,          DUT_Y - 4'd1,   0, 32'hA000_0004); // -> North
    wait_cycles(15);

    $display("--- Test 2: multi-flit packet (HEAD + 2 BODY + TAIL) ---");
    send_packet(PORT_N, 1, DUT_X + 4'd1, DUT_Y, 2, 32'hB000_0000);
    wait_cycles(20);

    $display("--- Test 3: concurrent packets on separate input ports ---");
    fork
      send_packet(PORT_N, 0, DUT_X + 4'd1, DUT_Y, 1, 32'hC000_0000); // N -> East
      send_packet(PORT_S, 0, DUT_X - 4'd1, DUT_Y, 1, 32'hD000_0000); // S -> West
    join
    wait_cycles(20);

    $display("--- Test 4: credit-based back-pressure on East ---");
    begin
      int unsigned east_count_before;
      east_count_before = recv_count[PORT_E];
      credit_from_downstream[PORT_E*NUM_VCS +: NUM_VCS] = '0;
      send_packet(PORT_L, 2, DUT_X + 4'd1, DUT_Y, 4, 32'hE000_0000); // 6 flits, > VC_DEPTH
      wait_cycles(30);
      check((recv_count[PORT_E] - east_count_before) == VC_DEPTH,
            $sformatf("East stalled after exactly VC_DEPTH=%0d flits with no downstream credit (got %0d)",
                       VC_DEPTH, recv_count[PORT_E] - east_count_before));
      credit_from_downstream[PORT_E*NUM_VCS +: NUM_VCS] = '1;
      wait_cycles(20);
      check(queue_size(PORT_E) == 0, "remaining East flits drained once credit was granted");
    end

    wait_cycles(20);
    check(queue_size(PORT_N) == 0, "no outstanding expected flits on North");
    check(queue_size(PORT_S) == 0, "no outstanding expected flits on South");
    check(queue_size(PORT_E) == 0, "no outstanding expected flits on East");
    check(queue_size(PORT_W) == 0, "no outstanding expected flits on West");
    check(queue_size(PORT_L) == 0, "no outstanding expected flits on Local");

    $display("=====================================================");
    $display(" RESULT: %0d PASSED, %0d FAILED", pass_count, fail_count);
    if (fail_count == 0) $display(" *** ALL TESTS PASSED ***");
    else                  $display(" *** TESTS FAILED ***");
    $display("=====================================================");
    $finish;
  end

  // watchdog: fail loudly instead of hanging forever
  initial begin
    #100000;
    $display("[%0t] TIMEOUT: testbench did not finish in time", $time);
    $finish;
  end

endmodule : tb_router_top