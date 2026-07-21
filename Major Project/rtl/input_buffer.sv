// input_buffer.sv
// Parameterized FIFO sitting behind every input port - this is the
// "BW" (buffer write) pipeline stage. Plain valid/ready on both sides.
//
// NOTE: DEPTH is assumed to be a power of 2 so the pointers can wrap
// with simple unsigned overflow. If you need a non-power-of-2 depth,
// add explicit modulo/compare logic to the pointer increments.

module input_buffer
  import noc_pkg::*;
#(
  parameter int DEPTH = BUFFER_DEPTH
) (
    input logic clk,
    input logic rst_n,

    // write side - from the upstream link
    input  logic  wr_valid,
    output logic  wr_ready,
    input  flit_t wr_flit,

    // read side - to route compute / switch allocation
    output logic  rd_valid,
    input  logic  rd_ready,
    output flit_t rd_flit
);

  localparam int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  flit_t                mem[DEPTH];
  logic [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
  logic [PTR_WIDTH:0]   count;

  logic wr_en, rd_en;

  assign wr_ready = (count < DEPTH);
  assign rd_valid = (count > 0);
  assign wr_en    = wr_valid && wr_ready;
  assign rd_en    = rd_valid && rd_ready;
  assign rd_flit  = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      if (wr_en) begin
        mem[wr_ptr] <= wr_flit;
        wr_ptr      <= wr_ptr + 1'b1;
      end
      if (rd_en) begin
        rd_ptr <= rd_ptr + 1'b1;
      end

      case ({wr_en, rd_en})
        2'b10:   count <= count + 1'b1;
        2'b01:   count <= count - 1'b1;
        default: count <= count;  // 2'b00 (idle) and 2'b11 (simultaneous) both net zero change
      endcase
    end
  end

endmodule : input_buffer
