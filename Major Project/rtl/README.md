# NoC router RTL

Compile order (also in `filelist.f`, respects package/interface-before-use dependencies):

1. `noc_pkg.sv`      - flit type, parameters, XY routing function
2. `noc_if.sv`        - inter-router link interface (valid/ready)
3. `input_buffer.sv`  - per-port input FIFO (BW stage)
4. `route_compute.sv` - combinational XY route computation (RC stage)
5. `rr_arbiter.sv`    - locking round-robin arbiter (SA stage)
6. `crossbar_sw.sv`   - mux-based crossbar (ST stage)
7. `port_ctrl.sv`     - per-input FSM tying BW/RC/SA/ST together
8. `router_top.sv`    - single 5-port router
9. `noc_mesh_top.sv`  - MESH_X x MESH_Y mesh of routers

## Questa
```
vsim -do compile_questa.do
```
or manually:
```
vlib work
vlog -sv -f filelist.f
```

## A note on how this was checked
Files 1-7 were compiled and elaborated clean with Icarus Verilog (`-g2012`)
as a syntax/connectivity sanity check. `router_top.sv` and `noc_mesh_top.sv`
use arrays of interface ports (e.g. `noc_if.slave link_in [NUM_PORTS]`) -
standard IEEE 1800-2012 SystemVerilog, but a construct Icarus doesn't parse
(confirmed with a minimal isolated repro, unrelated to this design). Questa
supports this natively. The request/grant/release matrix wiring and the
mesh's N/E/S/W index pairing were traced by hand for consistency, but since
they couldn't be elaborated end-to-end here, compile these two first in
Questa and treat any errors as the starting point for debugging - normal
for RTL this size.

No testbench yet - `tb/` (UVM environment) is the next phase.
