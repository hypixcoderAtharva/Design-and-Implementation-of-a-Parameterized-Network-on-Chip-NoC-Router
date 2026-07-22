# Parameterized NoC Router -- RTL

A 5-port (North / South / East / West / Local), virtual-channel, credit-based
flow-control router for a 2D-mesh Network-on-Chip, in synthesizable
SystemVerilog.

## Pipeline

Per packet, per virtual channel:

```
RC (route_compute) -> VA (vc_allocator) -> SA + ST (switch_allocator + crossbar_switch, same cycle) -> LT (output_controller, registered)
```

- **RC** -- dimension-order (XY) routing: resolve X, then Y, then Local.
- **VA** -- reserve one free VC on the chosen output port (round-robin
  across competing input VCs, per output port).
- **SA** -- two-stage separable allocation: each input port picks one ready
  VC to represent it, then each output port picks one winning input port.
- **ST** -- the winning flit crosses the crossbar the same cycle it wins SA.
- **LT** -- the output_controller registers the flit onto the link and
  updates downstream credit bookkeeping.

## Configuration

All tunable parameters live in `router_config.sv` (`router_config_pkg`):
`NUM_VCS`, `VC_DEPTH`, `FLIT_WIDTH`, `X_WIDTH`, `Y_WIDTH`. `NUM_PORTS` is
architecturally fixed at 5 -- `mux5.sv` / `demux5.sv` / `crossbar_switch.sv`
are hard-wired for the 5-port mesh topology.

## File map

| File                  | Role                                                          |
|-----------------------|----------------------------------------------------------------|
| `router_config.sv`    | Global parameters package                                     |
| `noc_pkg.sv`          | Shared enums / flit struct                                    |
| `noc_if.sv`           | Link interface for wiring `router_top` instances into a mesh  |
| `router_top.sv`       | Top-level integration                                         |
| `input_buffer.sv`     | Per-port VC FIFOs, routing, allocation requests                |
| `fifo.sv`             | Generic synchronous FIFO                                       |
| `route_compute.sv`    | XY routing                                                     |
| `virtual_channel.sv`  | Per-VC RC/VA/SA control FSM                                    |
| `vc_allocator.sv`     | Per-output-port VC allocator                                   |
| `switch_allocator.sv` | Two-stage separable switch allocator (whole router)             |
| `rr_arbiter.sv`       | Generic round-robin arbiter primitive                          |
| `crossbar_switch.sv`  | Datapath (demux-per-input, mux-per-output)                      |
| `output_controller.sv`| Per-port link driver + credit bookkeeping                      |
| `credit_manager.sv`   | Per-VC downstream credit counters                               |
| `flow_control.sv`     | Per-port upstream credit generation                             |
| `encoder.sv`          | Generic priority encoder primitive                              |
| `decoder.sv`          | Generic binary-to-one-hot decoder primitive                     |
| `mux5.sv` / `demux5.sv`| Generic 5-way mux / demux primitives                            |
| `router_monitor.sv`   | Simulation-only logging + basic protocol assertions              |

## Simulating

`filelist.f` lists every file in dependency order:

```
iverilog -g2012 -f filelist.f -s router_top
vlog     -f filelist.f
xvlog    -f filelist.f
```

This RTL has been lint-clean and functionally smoke-tested end to end with
Icarus Verilog 12.0 (a single-flit packet injected on the Local input port
correctly traverses RC -> VA -> SA/ST -> LT and reappears on the Local
output port with the right header fields). All module ports use flattened
packed buses rather than unpacked arrays or interface types, specifically
so the design elaborates cleanly on open-source as well as commercial
simulators. No testbench is included yet -- `noc_if.sv` is provided for
wiring several `router_top` instances together in a mesh-level testbench
when you're ready to build one.
