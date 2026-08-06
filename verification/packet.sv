// =============================================================================
// packet.sv                                                            [ADD]
// UVM sequence item representing one flit / single-flit packet. Field
// layout mirrors noc_pkg::flit_t so driver.sv can map it 1:1 onto the DUT
// interface, and router_monitor.sv can build one from an observed flit.
// =============================================================================
class packet extends uvm_sequence_item;

  rand bit [noc_pkg::ADDR_WIDTH-1:0] dest_x;
  rand bit [noc_pkg::ADDR_WIDTH-1:0] dest_y;
       bit [noc_pkg::ADDR_WIDTH-1:0] src_x;
       bit [noc_pkg::ADDR_WIDTH-1:0] src_y;
  rand noc_pkg::flit_type_e          flit_type;
       bit [7:0]                    seq_id;
  rand bit [noc_pkg::DATA_WIDTH-1:0] payload;

  `uvm_object_utils_begin(packet)
    `uvm_field_int(dest_x, UVM_ALL_ON)
    `uvm_field_int(dest_y, UVM_ALL_ON)
    `uvm_field_int(src_x,  UVM_ALL_ON)
    `uvm_field_int(src_y,  UVM_ALL_ON)
    `uvm_field_enum(noc_pkg::flit_type_e, flit_type, UVM_ALL_ON)
    `uvm_field_int(seq_id,  UVM_ALL_ON)
    `uvm_field_int(payload, UVM_ALL_ON)
  `uvm_object_utils_end

  // ---------------------------------------------------------------------
  // Stimulus knobs. Both default to the historical behaviour -- in-bounds
  // destinations, single-flit packets -- so every existing test is unchanged
  // unless it opts in. packet_generator.sv copies them onto each item.
  // ---------------------------------------------------------------------

  // when set, the destination is deliberately OUTSIDE the mesh, which is what
  // error_checker.sv's out_of_bounds path exists to catch. Such a flit is
  // unroutable and wedges the buffer it lands in (XY routing steers it at the
  // mesh boundary, where the outward link is tied off), so only oob_error_test
  // sets this -- and it expects the packets never to arrive.
  bit allow_oob_dest = 0;

  // when set, HEAD/BODY/TAIL are injected alongside FLIT_SINGLE. Track A
  // carries flit_type transparently -- nothing in router.sv decodes it -- so
  // this is legal stimulus, and it is the only way to reach the other three
  // cp_flit_type bins (issue V7).
  bit mixed_flit_types = 0;

  constraint c_dest_in_bounds {
    if (!allow_oob_dest) {
      dest_x < noc_pkg::MESH_DIM_X;
      dest_y < noc_pkg::MESH_DIM_Y;
    } else {
      dest_x >= noc_pkg::MESH_DIM_X || dest_y >= noc_pkg::MESH_DIM_Y;
    }
  }

  // this library injects single-flit packets unless a test opts in above
  constraint c_single_flit {
    if (!mixed_flit_types) flit_type == noc_pkg::FLIT_SINGLE;
  }

  function new(string name = "packet");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("dest=(%0d,%0d) src=(%0d,%0d) type=%s seq_id=%0d payload=0x%0h",
                      dest_x, dest_y, src_x, src_y, flit_type.name(), seq_id, payload);
  endfunction

endclass : packet
