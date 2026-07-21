// =============================================================================
// fifo.sv
// -----------------------------------------------------------------------------
// Generic parameterized synchronous FIFO, used as the per-VC flit buffer
// inside input_buffer.sv. Standalone / reusable -- no NoC-specific types.
// =============================================================================

module fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 4
) (
  input  logic                          clk,
  input  logic                          rst_n,

  input  logic                          wr_en,
  input  logic [WIDTH-1:0]              wr_data,
  output logic                          full,

  input  logic                          rd_en,
  output logic [WIDTH-1:0]              rd_data,
  output logic                          empty,

  output logic [$clog2(DEPTH+1)-1:0]    count
);

  localparam int PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  logic [WIDTH-1:0]              mem [0:DEPTH-1];
  logic [PTR_W-1:0]              wr_ptr, rd_ptr;
  logic [$clog2(DEPTH+1)-1:0]    cnt;

  assign full   = (cnt == DEPTH);
  assign empty  = (cnt == 0);
  assign count  = cnt;
  assign rd_data = mem[rd_ptr];

  wire do_wr = wr_en && !full;
  wire do_rd = rd_en && !empty;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      cnt    <= '0;
    end else begin
      if (do_wr) begin
        mem[wr_ptr] <= wr_data;
        wr_ptr      <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
      end
      if (do_rd) begin
        rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
      end

      case ({do_wr, do_rd})
        2'b10:   cnt <= cnt + 1'b1;
        2'b01:   cnt <= cnt - 1'b1;
        default: cnt <= cnt;
      endcase
    end
  end

endmodule : fifo