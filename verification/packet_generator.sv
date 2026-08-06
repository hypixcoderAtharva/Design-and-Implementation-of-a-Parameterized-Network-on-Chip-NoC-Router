// =============================================================================
// packet_generator.sv                                                  [ADD]
// UVM sequence that produces `num_packets` packet items destined for random
// (in-bounds, non-self) mesh coordinates, tagged with this node's (node_x,
// node_y) as the source. traffic_generator.sv reuses this sequence per node
// and can pin the destination to a fixed coordinate via set_fixed_dest() to
// build bit-complement / transpose / hotspot traffic patterns.
// =============================================================================
class packet_generator extends uvm_sequence #(packet);
  `uvm_object_utils(packet_generator)

  rand int unsigned num_packets = 20;
  int unsigned       node_x = 0;
  int unsigned       node_y = 0;

  // when set, every packet targets this fixed destination instead of a
  // random one (used by traffic_generator for patterned traffic)
  bit                           fixed_dest_en = 0;
  bit [noc_pkg::ADDR_WIDTH-1:0] fixed_dest_x, fixed_dest_y;

  // allow destination == source (local-port loopback); off by default
  bit allow_self_dest = 0;

  // forwarded onto every generated item -- see packet.sv for what they mean
  bit allow_oob_dest   = 0;
  bit mixed_flit_types = 0;

  // Per-node packet counter. router_scoreboard keys every packet on
  // (src_x, src_y, seq_id), so seq_id MUST be unique per source or expected
  // packets overwrite one another in the scoreboard's associative array and
  // every subsequent output is reported as spurious. Exactly one
  // packet_generator runs per node, so a plain member counter is already
  // per-source. (Previously seq_id was never assigned and stayed 0 for every
  // packet, which collapsed all packets from a node onto a single key.)
  int unsigned seq_ctr = 0;

  constraint c_count { num_packets inside {[1:1000]}; }

  function new(string name = "packet_generator");
    super.new(name);
  endfunction

  function void set_fixed_dest(int unsigned x, int unsigned y);
    fixed_dest_en = 1;
    fixed_dest_x  = x[noc_pkg::ADDR_WIDTH-1:0];
    fixed_dest_y  = y[noc_pkg::ADDR_WIDTH-1:0];
  endfunction

  task body();
    packet pkt;
    repeat (num_packets) begin
      pkt = packet::type_id::create("pkt");
      // set before randomize(): both are read by packet.sv's constraints
      pkt.allow_oob_dest   = allow_oob_dest;
      pkt.mixed_flit_types = mixed_flit_types;
      start_item(pkt);
      if (!pkt.randomize() with {
            if (fixed_dest_en) {
              dest_x == local::fixed_dest_x;
              dest_y == local::fixed_dest_y;
            } else if (!allow_self_dest) {
              !(dest_x == local::node_x && dest_y == local::node_y);
            }
          }) begin
        `uvm_error("PKTGEN", "Randomization failed")
      end
      pkt.src_x  = node_x[noc_pkg::ADDR_WIDTH-1:0];
      pkt.src_y  = node_y[noc_pkg::ADDR_WIDTH-1:0];
      pkt.seq_id = seq_ctr[7:0];
      seq_ctr++;
      finish_item(pkt);
    end
  endtask

endclass : packet_generator
