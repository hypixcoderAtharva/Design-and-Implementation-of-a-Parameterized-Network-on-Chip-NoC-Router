// =============================================================================
// tb_mesh_rtl.sv
// -----------------------------------------------------------------------------
// Self-checking, UVM-free RTL testbench for the Track A mesh
// (noc_mesh_top.sv). Exercises functionality directly from rtl/ with no
// dependency on the UVM environment.
//
// Tests, in order:
//   T1  reset behaviour            -- no output valid asserted during reset
//   T2  all-pairs delivery         -- every node -> every other node (240 pkts)
//   T3  payload + header integrity -- checked on every arrival
//   T4  correct-node delivery      -- arrival node must equal dest coordinate
//   T5  concurrent injection       -- all 16 nodes inject simultaneously
//   T6  backpressure               -- receivers randomly stall, no flit lost
//   T7  hardware telemetry         -- statistics.sv counters are consistent
//   T8  saturation burst           -- all nodes inject at full rate
//   T9  self-addressed packet      -- dest == src, ejected locally
//   T10 header transparency        -- flit_type / src fields carried untouched
//   T11 sustained congestion       -- input FIFOs driven all the way to full
//   T12 reset recovery             -- reset re-asserted mid-run, mesh recovers
//   T13 out-of-bounds destination  -- error_checker flags a flit addressed
//                                     outside the mesh  (runs last: an
//                                     unroutable flit permanently occupies a
//                                     buffer, so nothing may follow it)
//
// Pass criterion: zero errors, and every injected packet delivered exactly
// once to the node named in its own destination field.
// =============================================================================
`timescale 1ns/1ps

module tb_mesh_rtl;

  import noc_pkg::*;

  localparam int NX = MESH_DIM_X;
  localparam int NY = MESH_DIM_Y;

  // ---------------------------------------------------------------------
  // clock / reset
  // ---------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;                     // 100 MHz

  // ---------------------------------------------------------------------
  // DUT interface
  // ---------------------------------------------------------------------
  flit_t local_flit_in   [NX][NY];
  logic  local_valid_in  [NX][NY];
  logic  local_ready_out [NX][NY];
  flit_t local_flit_out  [NX][NY];
  logic  local_valid_out [NX][NY];
  logic  local_ready_in  [NX][NY];

  logic [31:0] total_accepted, total_forwarded, hotspot_load;
  logic [7:0]  hotspot_id;
  logic        mesh_error;

  noc_mesh_top dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .local_flit_in         (local_flit_in),
    .local_valid_in        (local_valid_in),
    .local_ready_out       (local_ready_out),
    .local_flit_out        (local_flit_out),
    .local_valid_out       (local_valid_out),
    .local_ready_in        (local_ready_in),
    .total_flits_accepted  (total_accepted),
    .total_flits_forwarded (total_forwarded),
    .hotspot_load          (hotspot_load),
    .hotspot_id            (hotspot_id),
    .mesh_error_detected   (mesh_error)
  );

  // ---------------------------------------------------------------------
  // scoreboard: payload is the unique packet key
  // ---------------------------------------------------------------------
  int         exp_dx [int];  // payload -> expected dest x
  int         exp_dy [int];  // payload -> expected dest y
  int         exp_sx [int];
  int         exp_sy [int];
  flit_type_e exp_ft [int];  // payload -> expected flit_type
  bit         pending[int];  // payload -> still in flight

  int n_sent = 0, n_recv = 0, n_err = 0, n_pass = 0;
  bit checking = 1'b0;

  // ---------------------------------------------------------------------
  // unique full-width packet keys
  //
  // The payload doubles as the scoreboard key, so it has to be unique. Draw
  // it from the whole 32-bit range rather than counting up from a constant
  // base: a counter starting at 32'h1000_0000 leaves payload[27:8] pinned at
  // zero for the entire run, and pinned bits are toggle bins no amount of
  // traffic can ever reach.
  // ---------------------------------------------------------------------
  bit used_key [int];

  function automatic int next_key();
    int k;
    do k = int'($urandom());
    while (k == 0 || used_key.exists(k));
    used_key[k] = 1'b1;
    return k;
  endfunction

  // mesh_error_detected is combinational on valid_in (error_checker.sv:39), so
  // it is only high for the cycle the offending flit is presented -- it is not
  // a sticky flag. Latch it here so a test can check it after the fact.
  bit mesh_error_seen = 1'b0;
  always @(posedge clk) if (rst_n && mesh_error) mesh_error_seen <= 1'b1;

  task automatic chk(input bit cond, input string msg);
    if (cond) n_pass++;
    else begin
      n_err++;
      $display("[%0t] ** FAIL: %s", $time, msg);
    end
  endtask

  // ---------------------------------------------------------------------
  // arrival monitor -- samples at the clock edge, so valid and ready are
  // read consistently as the values the DUT itself used
  // ---------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n && checking) begin
      for (int x = 0; x < NX; x++) begin
        for (int y = 0; y < NY; y++) begin
          if (local_valid_out[x][y] && local_ready_in[x][y]) begin
            automatic int pl = int'(local_flit_out[x][y].payload);
            n_recv++;
            if (!pending.exists(pl)) begin
              n_err++;
              $display("[%0t] ** FAIL: node(%0d,%0d) ejected unknown/duplicate payload 0x%08h",
                       $time, x, y, pl);
            end else begin
              // T4 -- delivered to the node its own header names
              if (exp_dx[pl] != x || exp_dy[pl] != y) begin
                n_err++;
                $display("[%0t] ** FAIL: MISROUTE payload 0x%08h dest=(%0d,%0d) but ejected at (%0d,%0d)",
                         $time, pl, exp_dx[pl], exp_dy[pl], x, y);
              end else n_pass++;

              // T3 -- header survived transit intact
              if (local_flit_out[x][y].dest_x != ADDR_WIDTH'(exp_dx[pl]) ||
                  local_flit_out[x][y].dest_y != ADDR_WIDTH'(exp_dy[pl]) ||
                  local_flit_out[x][y].src_x  != ADDR_WIDTH'(exp_sx[pl]) ||
                  local_flit_out[x][y].src_y  != ADDR_WIDTH'(exp_sy[pl])) begin
                n_err++;
                $display("[%0t] ** FAIL: header corrupted for payload 0x%08h", $time, pl);
              end else n_pass++;

              if (local_flit_out[x][y].flit_type != exp_ft[pl]) begin
                n_err++;
                $display("[%0t] ** FAIL: flit_type corrupted for payload 0x%08h", $time, pl);
              end else n_pass++;

              pending.delete(pl);
            end
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------
  // injection
  // ---------------------------------------------------------------------
  // Full-control injection: the header src coordinates and flit_type are
  // arguments rather than being derived from the injecting node. The router
  // must carry both fields through untouched without ever acting on them, and
  // the header fields are 4 bits wide while the mesh is only 4x4 -- so the
  // upper half of dest_x/src_x is only ever exercised from here.
  task automatic inject_hdr(input int x, y, dx, dy, hsx, hsy,
                            input flit_type_e ft, input int pl);
    exp_dx[pl] = dx;   exp_dy[pl] = dy;
    exp_sx[pl] = hsx;  exp_sy[pl] = hsy;
    exp_ft[pl] = ft;
    pending[pl] = 1'b1;

    local_flit_in[x][y].dest_x    <= ADDR_WIDTH'(dx);
    local_flit_in[x][y].dest_y    <= ADDR_WIDTH'(dy);
    local_flit_in[x][y].src_x     <= ADDR_WIDTH'(hsx);
    local_flit_in[x][y].src_y     <= ADDR_WIDTH'(hsy);
    local_flit_in[x][y].flit_type <= ft;
    local_flit_in[x][y].seq_id    <= 8'(pl);
    local_flit_in[x][y].payload   <= DATA_WIDTH'(pl);
    local_valid_in[x][y]          <= 1'b1;

    @(posedge clk);
    while (!local_ready_out[x][y]) @(posedge clk);
    local_valid_in[x][y] <= 1'b0;
    n_sent++;
  endtask

  task automatic inject(input int x, y, dx, dy, input int pl);
    inject_hdr(x, y, dx, dy, x, y, FLIT_SINGLE, pl);
  endtask

  // Injection that is deliberately NOT registered with the scoreboard: used
  // for flits the mesh is expected to refuse to deliver (T13).
  //
  // Unlike inject(), the wait for ready is bounded. An unroutable flit sits at
  // the head of an edge buffer forever, so once enough of them are in flight
  // the injecting port stops draining and an unbounded wait would hang. Giving
  // up is the correct behaviour here: the flit was still presented on valid_in,
  // which is all error_checker needs to see.
  task automatic inject_unscored(input int x, y, dx, dy);
    automatic int guard = 0;
    local_flit_in[x][y].dest_x    <= ADDR_WIDTH'(dx);
    local_flit_in[x][y].dest_y    <= ADDR_WIDTH'(dy);
    local_flit_in[x][y].src_x     <= ADDR_WIDTH'(x);
    local_flit_in[x][y].src_y     <= ADDR_WIDTH'(y);
    local_flit_in[x][y].flit_type <= FLIT_SINGLE;
    local_flit_in[x][y].seq_id    <= 8'hFF;
    local_flit_in[x][y].payload   <= '1;
    local_valid_in[x][y]          <= 1'b1;

    @(posedge clk);
    while (!local_ready_out[x][y] && guard < 100) begin
      @(posedge clk);
      guard++;
    end
    local_valid_in[x][y] <= 1'b0;
  endtask

  // Congest the mesh with nothing able to eject, hold the jam long enough for
  // the buffers to saturate, then reopen the ejection ports and let it drain.
  //
  // hx/hy name a single hotspot every node aims at; passing hx < 0 instead
  // spreads each node's traffic over rotating destinations. Both shapes are
  // needed: the hotspot form is what drives the inter-router buffers along one
  // approach direction to full, while the spread form is the only way a router
  // that is not itself the hotspot ever holds a locally-destined flit at the
  // head of a queue while its own eject port is closed.
  task automatic congest(input int hx, hy, input int per_node, input string tag);
    for (int x = 0; x < NX; x++)
      for (int y = 0; y < NY; y++) local_ready_in[x][y] = 1'b0;

    for (int sx = 0; sx < NX; sx++)
      for (int sy = 0; sy < NY; sy++)
        fork
          automatic int lx = sx, ly = sy;
          begin
            for (int r = 0; r < per_node; r++)
              if (hx < 0) inject(lx, ly, (lx + 1 + r) % NX, (ly + 1 + r) % NY, next_key());
              else        inject(lx, ly, hx, hy, next_key());
          end
        join_none

    repeat (400) @(posedge clk);
    for (int x = 0; x < NX; x++)
      for (int y = 0; y < NY; y++) local_ready_in[x][y] <= 1'b1;
    wait fork;

    repeat (2000) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T11 congestion (%s): %0d packet(s) lost while buffers were full",
                  tag, pending.num()));
  endtask

  task automatic idle_all();
    for (int x = 0; x < NX; x++)
      for (int y = 0; y < NY; y++) begin
        local_valid_in[x][y] = 1'b0;
        local_flit_in[x][y]  = '0;
        local_ready_in[x][y] = 1'b1;
      end
  endtask

  // ---------------------------------------------------------------------
  // randomized backpressure driver (T6)
  // ---------------------------------------------------------------------
  bit bp_enable = 1'b0;
  always @(posedge clk) begin
    if (bp_enable)
      for (int x = 0; x < NX; x++)
        for (int y = 0; y < NY; y++)
          local_ready_in[x][y] <= ($urandom_range(99,0) < 40);
  end

  // ---------------------------------------------------------------------
  // main sequence
  // ---------------------------------------------------------------------
  flit_type_e ft_list [4] = '{FLIT_HEAD, FLIT_BODY, FLIT_TAIL, FLIT_SINGLE};

  initial begin
    idle_all();

    // -------- T1 : reset behaviour --------
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    begin
      automatic bit any_valid = 1'b0;
      for (int x = 0; x < NX; x++)
        for (int y = 0; y < NY; y++)
          if (local_valid_out[x][y] === 1'b1) any_valid = 1'b1;
      chk(!any_valid, "T1 reset: some local_valid_out asserted during reset");
      chk(mesh_error === 1'b0, "T1 reset: mesh_error_detected asserted during reset");
    end
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    checking = 1'b1;
    $display("[%0t] T1 reset behaviour ................ done", $time);

    // -------- T2/T3/T4 : all-pairs delivery, one source at a time --------
    for (int sx = 0; sx < NX; sx++) begin
      for (int sy = 0; sy < NY; sy++) begin
        for (int dx = 0; dx < NX; dx++) begin
          for (int dy = 0; dy < NY; dy++) begin
            if (!(dx == sx && dy == sy)) inject(sx, sy, dx, dy, next_key());
          end
        end
      end
    end
    // drain
    repeat (400) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T2 all-pairs: %0d packet(s) never delivered", pending.num()));
    $display("[%0t] T2 all-pairs delivery ............. %0d sent, %0d received",
             $time, n_sent, n_recv);

    // -------- T5 : concurrent injection from all 16 nodes --------
    begin
      for (int sx = 0; sx < NX; sx++)
        for (int sy = 0; sy < NY; sy++)
          fork
            automatic int lx = sx, ly = sy;
            begin
              // bit-complement destination: worst-case distance
              for (int r = 0; r < 8; r++)
                inject(lx, ly, NX-1-lx, NY-1-ly, next_key());
            end
          join_none
      wait fork;
    end
    repeat (600) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T5 concurrent: %0d packet(s) never delivered", pending.num()));
    $display("[%0t] T5 concurrent injection ........... %0d total received", $time, n_recv);

    // -------- T6 : backpressure --------
    bp_enable = 1'b1;
    begin
      for (int sx = 0; sx < NX; sx++)
        for (int sy = 0; sy < NY; sy++)
          fork
            automatic int lx = sx, ly = sy;
            begin
              for (int r = 0; r < 4; r++)
                inject(lx, ly, (lx+2) % NX, (ly+1) % NY, next_key());
            end
          join_none
      wait fork;
    end
    repeat (2000) @(posedge clk);
    bp_enable = 1'b0;
    for (int x = 0; x < NX; x++)
      for (int y = 0; y < NY; y++) local_ready_in[x][y] <= 1'b1;
    repeat (600) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T6 backpressure: %0d packet(s) lost under stalling", pending.num()));
    $display("[%0t] T6 backpressure ................... %0d total received", $time, n_recv);

    // -------- T7 : telemetry consistency --------
    repeat (5) @(posedge clk);
    chk(mesh_error === 1'b0, "T7 telemetry: mesh_error_detected asserted (no OOB was injected)");
    chk(total_accepted  >= 32'(n_sent),
        $sformatf("T7 telemetry: total_flits_accepted (%0d) < packets injected (%0d)",
                  total_accepted, n_sent));
    chk(total_forwarded >= 32'(n_recv),
        $sformatf("T7 telemetry: total_flits_forwarded (%0d) < packets delivered (%0d)",
                  total_forwarded, n_recv));
    chk(hotspot_load > 0, "T7 telemetry: hotspot_load never incremented");
    $display("[%0t] T7 telemetry ...................... accepted=%0d forwarded=%0d hotspot=router%0d(load %0d)",
             $time, total_accepted, total_forwarded, hotspot_id, hotspot_load);

    // -------- T8 : saturation burst --------
    // Reproduces the UVM stimulus profile: all 16 nodes inject 20 packets
    // back-to-back with no gaps, uniform-random destinations. This is the
    // heaviest offered load the mesh can see and is where flit loss, if any,
    // would appear.
    begin
      for (int sx = 0; sx < NX; sx++)
        for (int sy = 0; sy < NY; sy++)
          fork
            automatic int lx = sx, ly = sy;
            begin
              for (int r = 0; r < 20; r++) begin
                automatic int ddx, ddy;
                do begin
                  ddx = $urandom_range(NX-1, 0);
                  ddy = $urandom_range(NY-1, 0);
                end while (ddx == lx && ddy == ly);
                inject(lx, ly, ddx, ddy, next_key());
              end
            end
          join_none
      wait fork;
    end
    $display("[%0t] T8 saturation burst injected ...... %0d in flight", $time, pending.num());
    repeat (4000) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T8 saturation: %0d packet(s) never delivered", pending.num()));
    $display("[%0t] T8 saturation burst ............... %0d total received", $time, n_recv);

    // -------- T9 : self-addressed packets --------
    // A node sending to itself is the one case where XY routing turns a flit
    // straight from the local input back out the local output. Every other
    // test excludes dest == src, so this L->L path is otherwise never taken.
    begin
      for (int sx = 0; sx < NX; sx++)
        for (int sy = 0; sy < NY; sy++)
          inject(sx, sy, sx, sy, next_key());
    end
    repeat (200) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T9 self-addressed: %0d packet(s) never ejected locally", pending.num()));
    $display("[%0t] T9 self-addressed packets ......... %0d total received", $time, n_recv);

    // -------- T10 : header transparency --------
    // flit_type and the src coordinates are payload as far as the router is
    // concerned: it must forward them bit-exact and must never route on them.
    // Sweeping all four flit_type encodings and the full 4-bit src range also
    // reaches the header bits that a 4x4 mesh of well-behaved traffic leaves
    // permanently at zero.
    begin
      for (int t = 0; t < 4; t++)
        for (int sx = 0; sx < NX; sx++)
          for (int sy = 0; sy < NY; sy++) begin
            automatic int ddx = (sx + 2) % NX;
            automatic int ddy = (sy + 3) % NY;
            // src coordinates deliberately span 0..15, well outside the mesh
            inject_hdr(sx, sy, ddx, ddy,
                       $urandom_range(15, 0), $urandom_range(15, 0),
                       ft_list[t], next_key());
          end
    end
    repeat (600) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T10 header transparency: %0d packet(s) never delivered", pending.num()));
    $display("[%0t] T10 header transparency ........... %0d total received", $time, n_recv);

    // -------- T11 : hotspot congestion, input buffers driven to full --------
    // T6's random 40% stalling never lets a queue grow past a flit or two, so
    // fifo_buffer.full -- and the ready_out deassertion, arbiter starvation and
    // upstream stalling that follow from it -- stay dead.
    //
    // Every node aims at one corner while that corner refuses to eject. The
    // head-of-line flit at the corner can never leave, so its input FIFO fills,
    // ready_out drops, and the backpressure walks hop by hop back up the row
    // and column until the injectors themselves stall.
    //
    // Run it against all four corners. Under XY routing the approach direction
    // decides which input buffer fills: traffic converging on (0,0) arrives on
    // the E and N ports of the routers along the way, traffic converging on
    // (NX-1,NY-1) arrives on their W and S ports, and the two mixed corners
    // reach the buffers the first two leave alone.
    // Sweep the hotspot over every node rather than picking a few. A given
    // input buffer only saturates when the flits queued in it have nowhere to
    // go, and for the Y-direction links into the top and bottom rows that only
    // happens when the router they feed is itself the destination -- so any
    // fixed choice of hotspots leaves some buffers untested.
    for (int hx = 0; hx < NX; hx++)
      for (int hy = 0; hy < NY; hy++)
        congest(hx, hy, 24, $sformatf("hotspot (%0d,%0d)", hx, hy));

    // Finally the spread pattern: this is the only shape in which a router that
    // is not the hotspot holds a locally-destined flit at the head of a queue
    // while its own eject port is closed.
    congest(-1, -1, 24, "all-to-all");
    $display("[%0t] T11 hotspot congestion ............ %0d total received", $time, n_recv);

    // -------- T12 : reset recovery --------
    // rst_n has only ever made one transition, 0->1 at time zero. Pulse it low
    // again with the mesh idle: the design must clear its telemetry, hold every
    // output deasserted, and carry traffic normally once released.
    checking = 1'b0;
    rst_n    = 1'b0;
    repeat (5) @(posedge clk);
    begin
      automatic bit any_valid = 1'b0;
      for (int x = 0; x < NX; x++)
        for (int y = 0; y < NY; y++)
          if (local_valid_out[x][y] === 1'b1) any_valid = 1'b1;
      chk(!any_valid, "T12 re-reset: local_valid_out asserted during reset");
    end
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    chk(total_accepted == 32'd0 && total_forwarded == 32'd0,
        $sformatf("T12 re-reset: telemetry did not clear (accepted=%0d forwarded=%0d)",
                  total_accepted, total_forwarded));
    checking = 1'b1;
    for (int sx = 0; sx < NX; sx++)
      for (int sy = 0; sy < NY; sy++)
        inject(sx, sy, NX-1-sx, NY-1-sy, next_key());
    repeat (400) @(posedge clk);
    chk(pending.num() == 0,
        $sformatf("T12 re-reset: %0d packet(s) lost after reset recovery", pending.num()));
    $display("[%0t] T12 reset recovery ................ %0d total received", $time, n_recv);

    // -------- T13 : out-of-bounds destination (MUST BE LAST) --------
    // A flit addressed outside the mesh is unroutable: XY routing steers it at
    // the edge router towards a tied-off port, where it sits at the head of an
    // input FIFO forever. That permanently blocks one buffer, so no traffic
    // can be scheduled after this point. error_checker must raise
    // mesh_error_detected and count it.
    chk(!mesh_error_seen, "T13 pre-check: mesh_error asserted before any OOB flit was sent");
    begin
      automatic logic [31:0] err_before = dut.errcnt_flat[0];
      checking = 1'b0;                       // nothing below is scoreboarded

      inject_unscored(0, 0, 15, 0);          // dest_x outside the mesh
      repeat (40) @(posedge clk);
      chk(mesh_error_seen,
          "T13 OOB: mesh_error_detected never pulsed for an out-of-mesh dest_x");
      chk(dut.errcnt_flat[0] == err_before + 1,
          "T13 OOB: injecting router's error_count did not increment by one");

      inject_unscored(0, 0, 0, 15);          // dest_y outside the mesh
      repeat (40) @(posedge clk);
      chk(dut.errcnt_flat[0] == err_before + 2,
          "T13 OOB: second out-of-mesh flit (dest_y) was not counted");

      // Sweep the whole mesh: every router must flag an out-of-mesh flit on
      // its own local port, and an unroutable flit has to reach the far edge
      // of every row and column before the edge router sees dest beyond it.
      //
      // Repeat the sweep. error_checker counts per cycle that an offending
      // flit is presented, not per flit accepted, so once the edge buffers
      // have filled and injection starts stalling against a deasserted ready
      // the counters climb quickly -- which is what exercises the upper bits
      // of error_count.
      for (int pass = 0; pass < 2; pass++)
        for (int sx = 0; sx < NX; sx++)
          for (int sy = 0; sy < NY; sy++) begin
            automatic logic [31:0] ec_pre = dut.errcnt_flat[sy*NX + sx];
            inject_unscored(sx, sy, 15, sy);   // runs off the east edge
            inject_unscored(sx, sy, sx, 15);   // runs off the north edge
            repeat (30) @(posedge clk);
            chk(dut.errcnt_flat[sy*NX + sx] > ec_pre,
                $sformatf("T13 OOB: router(%0d,%0d) did not flag an out-of-mesh dest", sx, sy));
          end
      repeat (60) @(posedge clk);
    end
    $display("[%0t] T13 out-of-bounds destination ..... mesh_error_seen=%0b err_count(r0)=%0d",
             $time, mesh_error_seen, dut.errcnt_flat[0]);

    // -------- summary --------
    $display("");
    $display("=====================================================");
    $display(" tb_mesh_rtl  (Track A : noc_mesh_top)");
    $display("   packets injected  : %0d", n_sent);
    $display("   packets delivered : %0d", n_recv);
    $display("   undelivered       : %0d", pending.num());
    $display("   checks passed     : %0d", n_pass);
    $display("   checks failed     : %0d", n_err);
    if (n_err == 0 && pending.num() == 0)
      $display("   RESULT            : *** PASS ***");
    else
      $display("   RESULT            : *** FAIL ***");
    $display("=====================================================");
    $finish;
  end

  // global timeout -- headroom over the ~1ms the full T11 hotspot sweep takes.
  // The stimulus block above finishes at ~564 us, so on a healthy run this
  // never fires; if it does, the run really did hang.
  initial begin
    #5ms;
    $display("** FAIL: tb_mesh_rtl global timeout");
    $display("   RESULT            : *** FAIL ***");
    $finish;
  end

endmodule : tb_mesh_rtl
