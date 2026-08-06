// =============================================================================
// fifo_buffer.sv
// Generic parameterized synchronous FIFO. Used as the per-input-port buffer
// inside router.sv. Not in the requested file list, but required by
// noc_mesh_top.sv / router.sv, so it is included as a foundation block.
// =============================================================================
module fifo_buffer #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 8
)(
  input  logic             clk,
  input  logic             rst_n,

  input  logic             wr_en,
  input  logic [WIDTH-1:0] wr_data,
  output logic             full,

  input  logic             rd_en,
  output logic [WIDTH-1:0] rd_data,
  output logic             empty
);

  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  logic [WIDTH-1:0] mem [DEPTH];
  logic [PTR_W:0]   wr_ptr, rd_ptr;   // extra MSB distinguishes full vs empty

  assign full    = (wr_ptr[PTR_W-1:0] == rd_ptr[PTR_W-1:0]) &&
                    (wr_ptr[PTR_W]    != rd_ptr[PTR_W]);
  assign empty   = (wr_ptr == rd_ptr);
  assign rd_data = mem[rd_ptr[PTR_W-1:0]];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (wr_en && !full) begin
      mem[wr_ptr[PTR_W-1:0]] <= wr_data;
      wr_ptr                 <= wr_ptr + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= '0;
    end else if (rd_en && !empty) begin
      rd_ptr <= rd_ptr + 1'b1;
    end
  end

endmodule : fifo_buffer
