// noc_mesh_top.sv
// MESH_X x MESH_Y mesh of router_top instances, wired N/E/S/W to
// their neighbors. Each router's Local port is exposed at this level
// so a testbench can inject/eject traffic per node. Edge routers with
// no physical neighbor in a given direction have that direction tied
// off (input forced idle, output always sunk).

module noc_mesh_top
  import noc_pkg::*;
#(
    parameter int MESH_X = MESH_SIZE_X,
    parameter int MESH_Y = MESH_SIZE_Y
) (
    input logic clk,
    input logic rst_n,

    noc_if.slave  local_in [MESH_X][MESH_Y],
    noc_if.master local_out[MESH_X][MESH_Y]
);

  // horizontal links: h_link[x][y]   = router(x,y)   -> router(x+1,y)  (east-going)
  //                   h_link_r[x][y] = router(x+1,y) -> router(x,y)    (west-going)
  noc_if h_link  [MESH_X-1][MESH_Y] (.clk(clk), .rst_n(rst_n));
  noc_if h_link_r[MESH_X-1][MESH_Y] (.clk(clk), .rst_n(rst_n));

  // vertical links: v_link[x][y]   = router(x,y)   -> router(x,y+1)  (north-going)
  //                 v_link_r[x][y] = router(x,y+1) -> router(x,y)    (south-going)
  noc_if v_link  [MESH_X][MESH_Y-1] (.clk(clk), .rst_n(rst_n));
  noc_if v_link_r[MESH_X][MESH_Y-1] (.clk(clk), .rst_n(rst_n));

  genvar x, y;

  generate
    for (x = 0; x < MESH_X; x++) begin : g_x
      for (y = 0; y < MESH_Y; y++) begin : g_y

        noc_if link_in [NUM_PORTS] (.clk(clk), .rst_n(rst_n));
        noc_if link_out[NUM_PORTS] (.clk(clk), .rst_n(rst_n));

        // ---- North ----
        if (y < MESH_Y - 1) begin : g_n_conn
          assign v_link[x][y].valid    = link_out[PORT_N].valid;
          assign v_link[x][y].flit     = link_out[PORT_N].flit;
          assign link_out[PORT_N].ready = v_link[x][y].ready;

          assign link_in[PORT_N].valid = v_link_r[x][y].valid;
          assign link_in[PORT_N].flit  = v_link_r[x][y].flit;
          assign v_link_r[x][y].ready  = link_in[PORT_N].ready;
        end else begin : g_n_bnd
          assign link_out[PORT_N].ready = 1'b1;
          assign link_in[PORT_N].valid  = 1'b0;
          assign link_in[PORT_N].flit   = '0;
        end

        // ---- South ----
        if (y > 0) begin : g_s_conn
          assign v_link_r[x][y-1].valid = link_out[PORT_S].valid;
          assign v_link_r[x][y-1].flit  = link_out[PORT_S].flit;
          assign link_out[PORT_S].ready = v_link_r[x][y-1].ready;

          assign link_in[PORT_S].valid = v_link[x][y-1].valid;
          assign link_in[PORT_S].flit  = v_link[x][y-1].flit;
          assign v_link[x][y-1].ready  = link_in[PORT_S].ready;
        end else begin : g_s_bnd
          assign link_out[PORT_S].ready = 1'b1;
          assign link_in[PORT_S].valid  = 1'b0;
          assign link_in[PORT_S].flit   = '0;
        end

        // ---- East ----
        if (x < MESH_X - 1) begin : g_e_conn
          assign h_link[x][y].valid    = link_out[PORT_E].valid;
          assign h_link[x][y].flit     = link_out[PORT_E].flit;
          assign link_out[PORT_E].ready = h_link[x][y].ready;

          assign link_in[PORT_E].valid = h_link_r[x][y].valid;
          assign link_in[PORT_E].flit  = h_link_r[x][y].flit;
          assign h_link_r[x][y].ready  = link_in[PORT_E].ready;
        end else begin : g_e_bnd
          assign link_out[PORT_E].ready = 1'b1;
          assign link_in[PORT_E].valid  = 1'b0;
          assign link_in[PORT_E].flit   = '0;
        end

        // ---- West ----
        if (x > 0) begin : g_w_conn
          assign h_link_r[x-1][y].valid = link_out[PORT_W].valid;
          assign h_link_r[x-1][y].flit  = link_out[PORT_W].flit;
          assign link_out[PORT_W].ready = h_link_r[x-1][y].ready;

          assign link_in[PORT_W].valid = h_link[x-1][y].valid;
          assign link_in[PORT_W].flit  = h_link[x-1][y].flit;
          assign h_link[x-1][y].ready  = link_in[PORT_W].ready;
        end else begin : g_w_bnd
          assign link_out[PORT_W].ready = 1'b1;
          assign link_in[PORT_W].valid  = 1'b0;
          assign link_in[PORT_W].flit   = '0;
        end

        // ---- Local (exposed for traffic injection / ejection) ----
        assign link_in[PORT_LOCAL].valid  = local_in[x][y].valid;
        assign link_in[PORT_LOCAL].flit   = local_in[x][y].flit;
        assign local_in[x][y].ready       = link_in[PORT_LOCAL].ready;

        assign local_out[x][y].valid      = link_out[PORT_LOCAL].valid;
        assign local_out[x][y].flit       = link_out[PORT_LOCAL].flit;
        assign link_out[PORT_LOCAL].ready = local_out[x][y].ready;

        router_top #(
            .ROUTER_X(x[COORD_WIDTH-1:0]),
            .ROUTER_Y(y[COORD_WIDTH-1:0])
        ) u_router (
            .clk     (clk),
            .rst_n   (rst_n),
            .link_in (link_in),
            .link_out(link_out)
        );

      end
    end
  endgenerate

endmodule : noc_mesh_top
