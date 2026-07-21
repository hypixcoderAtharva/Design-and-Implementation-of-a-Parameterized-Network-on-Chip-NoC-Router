`timescale 1ns/1ps
// tb_noc_mesh_top.sv
//
// Starter self-checking testbench for noc_mesh_top.
// Fill in additional directed/random tests as needed.

import noc_pkg::*;

module tb_noc_mesh_top;

  logic clk;
  logic rst_n;

  noc_if local_in [MESH_SIZE_X][MESH_SIZE_Y](.clk(clk), .rst_n(rst_n));
  noc_if local_out[MESH_SIZE_X][MESH_SIZE_Y](.clk(clk), .rst_n(rst_n));

  noc_mesh_top dut(
    .clk(clk),
    .rst_n(rst_n),
    .local_in(local_in),
    .local_out(local_out)
  );

  initial clk=0;
  always #5 clk=~clk;

  initial begin
    rst_n=0;
    repeat(5) @(posedge clk);
    rst_n=1;
  end

  // ---------------------------------------------------------------
  // local_in / local_out are arrays of interface INSTANCES, so they
  // can only be indexed with an elaboration-time constant (a genvar,
  // or a fixed literal) - not a runtime variable like the x/y loop
  // vars below or the sx/sy task arguments further down. Virtual
  // interface handles, by contrast, are ordinary variables and CAN
  // be indexed at runtime, so we populate one array of virtual
  // interface handles per direction (using a genvar-indexed generate
  // block, which is legal) and do all the runtime-indexed driving
  // through those instead.
  // ---------------------------------------------------------------
  virtual noc_if vif_in [MESH_SIZE_X][MESH_SIZE_Y];
  virtual noc_if vif_out[MESH_SIZE_X][MESH_SIZE_Y];

  genvar tx, ty;
  generate
    for (tx = 0; tx < MESH_SIZE_X; tx++) begin : g_tx
      for (ty = 0; ty < MESH_SIZE_Y; ty++) begin : g_ty
        initial begin
          vif_in[tx][ty]  = local_in[tx][ty];
          vif_out[tx][ty] = local_out[tx][ty];
        end
      end
    end
  endgenerate

  initial begin : init_ready
    for (int x=0;x<MESH_SIZE_X;x++)
      for (int y=0;y<MESH_SIZE_Y;y++) begin
        vif_in[x][y].valid  = 0;
        vif_in[x][y].flit   = '0;
        vif_out[x][y].ready = 1;
      end
  end

  task automatic send_single_flit(
      input int sx, sy,
      input logic [COORD_WIDTH-1:0] dx, dy,
      input logic [FLIT_WIDTH-1:0] payload
  );
    flit_t f;
    f.flit_type = FLIT_HEAD_TAIL;
    f.dest_x    = dx;
    f.dest_y    = dy;
    f.payload   = payload;

    @(posedge clk);
    while(!vif_in[sx][sy].ready) @(posedge clk);
    vif_in[sx][sy].flit  <= f;
    vif_in[sx][sy].valid <= 1;
    @(posedge clk);
    vif_in[sx][sy].valid <= 0;
  endtask

  initial begin
    @(posedge rst_n);
    repeat(2) @(posedge clk);

    $display("TEST1: (0,0)->(2,2)");
    send_single_flit(0,0,2,2,32'hDEADBEEF);

    repeat(100) @(posedge clk);
    $display("Simulation finished");
    $finish;
  end

  initial begin
    $dumpfile("noc.vcd");
    $dumpvars(0,tb_noc_mesh_top);
  end
endmodule
