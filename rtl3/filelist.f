// Compile order for this design. Packages and leaf primitives first, then
// modules that depend on them, top-level last. Feed this to your simulator,
// e.g.:  vlog -f filelist.f   /   xvlog -f filelist.f   /   iverilog -g2012 -f filelist.f

router_config.sv
noc_pkg.sv
noc_if.sv

fifo.sv
encoder.sv
decoder.sv
mux5.sv
demux5.sv
rr_arbiter.sv

route_compute.sv
virtual_channel.sv
vc_allocator.sv
switch_allocator.sv
crossbar_switch.sv

credit_manager.sv
flow_control.sv
output_controller.sv

input_buffer.sv
router_monitor.sv
router_top.sv
