// =============================================================================
// tb_router_top_rtl.sv
// -----------------------------------------------------------------------------
// Self-checking, UVM-free RTL testbench for the Track B virtual-channel
// router (router_top.sv). This is the first testbench that has ever
// elaborated Track B -- router_top.sv did not exist before, so none of
// input_buffer / vc_allocator / switch_allocator / crossbar_switch /
// output_controller had been exercised.
//
// Router under test sits at (MY_X, MY_Y) = (1,1), an interior coordinate,
// so all five routing outcomes are reachable.
//
// Tests:
//   T1  reset behaviour       -- no output valid during reset
//   T2  routing, all 5 ways   -- E / W / N / S / Local from (1,1)
//   T3  payload integrity     -- flit contents survive the crossbar
//   T4  credit return         -- popping an input VC returns a credit upstream
//   T5  multi-VC independence -- traffic on different VCs does not interfere
//   T6  multi-flit packet     -- HEAD/BODY/TAIL stay on one output (wormhole)
// =============================================================================
`timescale 1ns/1ps

module tb_router_top_rtl;

  import noc_vc_pkg::*;
  import router_config_pkg::*;

  localparam int MYX = 1;
  localparam int MYY = 1;
  localparam int FB  = FLIT_BITS;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [NUM_PORTS*FB-1:0]      in_flit_flat;
  logic [NUM_PORTS-1:0]         in_valid;
  logic [NUM_PORTS*VC_ID_W-1:0] in_vc_id_flat;
  logic [NUM_PORTS*NUM_VCS-1:0] in_credit_out_flat;

  logic [NUM_PORTS*FB-1:0]      out_flit_flat;
  logic [NUM_PORTS-1:0]         out_valid;
  logic [NUM_PORTS*VC_ID_W-1:0] out_vc_flat;
  logic [NUM_PORTS*NUM_VCS-1:0] out_credit_in_flat;

  router_top #(.MY_X(X_WIDTH'(MYX)), .MY_Y(Y_WIDTH'(MYY))) dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .in_flit_flat       (in_flit_flat),
    .in_valid           (in_valid),
    .in_vc_id_flat      (in_vc_id_flat),
    .in_credit_out_flat (in_credit_out_flat),
    .out_flit_flat      (out_flit_flat),
    .out_valid          (out_valid),
    .out_vc_flat        (out_vc_flat),
    .out_credit_in_flat (out_credit_in_flat)
  );

  int n_pass = 0, n_err = 0;

  task automatic chk(input bit cond, input string msg);
    if (cond) n_pass++;
    else begin
      n_err++;
      $display("[%0t] ** FAIL: %s", $time, msg);
    end
  endtask

  function automatic flit_t mk(input int dx, dy, sx, sy, input flit_type_e ft,
                               input int sid, input int pl);
    flit_t f;
    f.dest_x  = X_WIDTH'(dx);
    f.dest_y  = Y_WIDTH'(dy);
    f.src_x   = X_WIDTH'(sx);
    f.src_y   = Y_WIDTH'(sy);
    f.ftype   = ft;
    f.seq_id  = 8'(sid);
    f.payload = FLIT_WIDTH'(pl);
    return f;
  endfunction

  function automatic flit_t get_out(input int port);
    return flit_t'(out_flit_flat[port*FB +: FB]);
  endfunction

  task automatic drive(input int port, input int vc, input flit_t f);
    in_flit_flat[port*FB +: FB]           <= f;
    in_vc_id_flat[port*VC_ID_W +: VC_ID_W] <= VC_ID_W'(vc);
    in_valid[port]                         <= 1'b1;
    @(posedge clk);
    in_valid[port] <= 1'b0;
  endtask

  // wait up to `lim` cycles for out_valid[port]; returns 1 on success
  task automatic wait_out(input int port, input int lim, output bit ok);
    ok = 1'b0;
    for (int i = 0; i < lim; i++) begin
      @(posedge clk);
      if (out_valid[port]) begin
        ok = 1'b1;
        return;
      end
    end
  endtask

  // observe credit pulses returned upstream
  logic [NUM_PORTS*NUM_VCS-1:0] credit_seen;
  always @(posedge clk) begin
    if (!rst_n) credit_seen <= '0;
    else        credit_seen <= credit_seen | in_credit_out_flat;
  end

  // ---------------------------------------------------------------------
  // Ideal downstream neighbour model.
  //
  // Without this the router is correct but starves: credit_manager resets
  // to VC_DEPTH credits per output VC and decrements on every flit sent,
  // so after VC_DEPTH flits on one VC has_credit drops and switch
  // allocation legitimately stops. A real neighbour returns a credit as it
  // drains its input buffer; this models one that drains immediately.
  // ---------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      out_credit_in_flat <= '0;
    end else begin
      out_credit_in_flat <= '0;
      for (int p = 0; p < NUM_PORTS; p++)
        if (out_valid[p])
          out_credit_in_flat[p*NUM_VCS + out_vc_flat[p*VC_ID_W +: VC_ID_W]] <= 1'b1;
    end
  end

  bit ok;
  flit_t got;

  initial begin
    in_flit_flat       = '0;
    in_valid           = '0;
    in_vc_id_flat      = '0;

    // -------- T1 : reset --------
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    chk(out_valid === '0, "T1 reset: out_valid not all-zero during reset");
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    $display("[%0t] T1 reset behaviour ................ done", $time);

    // -------- T2/T3 : routing in all five directions from (1,1) --------
    // dest (3,1): dest_x > MY_X  -> East (port 1)
    drive(DIR_W, 0, mk(3,1, 0,1, FLIT_HEAD_TAIL, 1, 32'hAAAA_0001));
    wait_out(DIR_E, 40, ok);
    chk(ok, "T2 East: no flit emerged on the East output");
    if (ok) begin
      got = get_out(DIR_E);
      chk(got.payload == 32'hAAAA_0001, "T3 East: payload corrupted");
      chk(got.dest_x == 4'd3 && got.dest_y == 4'd1, "T3 East: header corrupted");
    end
    repeat (12) @(posedge clk);

    // dest (0,1): dest_x < MY_X -> West (port 3)
    drive(DIR_E, 0, mk(0,1, 3,1, FLIT_HEAD_TAIL, 2, 32'hAAAA_0002));
    wait_out(DIR_W, 40, ok);
    chk(ok, "T2 West: no flit emerged on the West output");
    if (ok) chk(get_out(DIR_W).payload == 32'hAAAA_0002, "T3 West: payload corrupted");
    repeat (12) @(posedge clk);

    // dest (1,3): x matches, dest_y > MY_Y -> North (port 0)
    drive(DIR_S, 0, mk(1,3, 1,0, FLIT_HEAD_TAIL, 3, 32'hAAAA_0003));
    wait_out(DIR_N, 40, ok);
    chk(ok, "T2 North: no flit emerged on the North output");
    if (ok) chk(get_out(DIR_N).payload == 32'hAAAA_0003, "T3 North: payload corrupted");
    repeat (12) @(posedge clk);

    // dest (1,0): x matches, dest_y < MY_Y -> South (port 2)
    drive(DIR_N, 0, mk(1,0, 1,3, FLIT_HEAD_TAIL, 4, 32'hAAAA_0004));
    wait_out(DIR_S, 40, ok);
    chk(ok, "T2 South: no flit emerged on the South output");
    if (ok) chk(get_out(DIR_S).payload == 32'hAAAA_0004, "T3 South: payload corrupted");
    repeat (12) @(posedge clk);

    // dest (1,1): this router -> Local (port 4)
    drive(DIR_W, 0, mk(1,1, 0,1, FLIT_HEAD_TAIL, 5, 32'hAAAA_0005));
    wait_out(DIR_LOCAL, 40, ok);
    chk(ok, "T2 Local: no flit emerged on the Local output");
    if (ok) chk(get_out(DIR_LOCAL).payload == 32'hAAAA_0005, "T3 Local: payload corrupted");
    repeat (12) @(posedge clk);
    $display("[%0t] T2 routing (E/W/N/S/L) ............ done", $time);
    $display("[%0t] T3 payload integrity .............. done", $time);

    // -------- T4 : credit return to upstream --------
    chk(credit_seen != '0, "T4 credit: no credit pulse ever returned upstream");
    $display("[%0t] T4 credit return .................. seen=0x%0h", $time, credit_seen);

    // -------- T5 : two VCs on one input port, different destinations --------
    drive(DIR_W, 0, mk(3,1, 0,1, FLIT_HEAD_TAIL, 6, 32'hBBBB_0001));
    drive(DIR_W, 1, mk(1,3, 0,1, FLIT_HEAD_TAIL, 7, 32'hBBBB_0002));
    begin
      automatic bit got_e = 1'b0, got_n = 1'b0;
      for (int i = 0; i < 80; i++) begin
        @(posedge clk);
        if (out_valid[DIR_E] && get_out(DIR_E).payload == 32'hBBBB_0001) got_e = 1'b1;
        if (out_valid[DIR_N] && get_out(DIR_N).payload == 32'hBBBB_0002) got_n = 1'b1;
      end
      chk(got_e, "T5 multi-VC: VC0 flit (East) never arrived");
      chk(got_n, "T5 multi-VC: VC1 flit (North) never arrived");
    end
    $display("[%0t] T5 multi-VC independence .......... done", $time);

    // -------- T6 : multi-flit wormhole packet, HEAD -> BODY -> TAIL --------
    // All three must leave on the same output (East), in order.
    repeat (10) @(posedge clk);
    fork
      begin
        drive(DIR_S, 2, mk(3,1, 1,0, FLIT_HEAD, 8, 32'hCCCC_0001));
        drive(DIR_S, 2, mk(3,1, 1,0, FLIT_BODY, 8, 32'hCCCC_0002));
        drive(DIR_S, 2, mk(3,1, 1,0, FLIT_TAIL, 8, 32'hCCCC_0003));
      end
      begin
        automatic int seen = 0;
        automatic bit order_ok = 1'b1;
        for (int i = 0; i < 120; i++) begin
          @(posedge clk);
          if (out_valid[DIR_E]) begin
            automatic flit_t f = get_out(DIR_E);
            if (f.payload == 32'hCCCC_0001) begin
              if (seen != 0) order_ok = 1'b0;
              seen = 1;
            end else if (f.payload == 32'hCCCC_0002) begin
              if (seen != 1) order_ok = 1'b0;
              seen = 2;
            end else if (f.payload == 32'hCCCC_0003) begin
              if (seen != 2) order_ok = 1'b0;
              seen = 3;
            end
          end
        end
        chk(seen == 3, $sformatf("T6 wormhole: only %0d of 3 flits arrived on East", seen));
        chk(order_ok, "T6 wormhole: HEAD/BODY/TAIL arrived out of order");
      end
    join
    $display("[%0t] T6 multi-flit wormhole ............ done", $time);

    // -------- summary --------
    $display("");
    $display("=====================================================");
    $display(" tb_router_top_rtl  (Track B : router_top)");
    $display("   checks passed     : %0d", n_pass);
    $display("   checks failed     : %0d", n_err);
    if (n_err == 0) $display("   RESULT            : *** PASS ***");
    else            $display("   RESULT            : *** FAIL ***");
    $display("=====================================================");
    $finish;
  end

  // The stimulus block above finishes at ~3 us, so on a healthy run this
  // never fires; if it does, the run really did hang.
  initial begin
    #500us;
    $display("** FAIL: tb_router_top_rtl global timeout");
    $display("   RESULT            : *** FAIL ***");
    $finish;
  end

endmodule : tb_router_top_rtl
