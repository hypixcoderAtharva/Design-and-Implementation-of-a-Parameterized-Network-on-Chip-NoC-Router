# Parameterized Network-on-Chip Router

SystemVerilog implementations of a parameterized 2-D mesh Network-on-Chip (NoC), with UVM verification, UVM-free self-checking RTL tests, coverage flows, and ZedBoard FPGA build support.

The active source tree is [`noc_router_project_paid/`](noc_router_project_paid/). It contains two separate router designs; choose one track and its corresponding top module rather than mixing files from both.

## Highlights

- 4 × 4 mesh of 16 routers, each with five ports: North, South, East, West, and Local
- Deterministic XY dimension-order routing
- Parameterized flit, coordinate, buffer, and virtual-channel widths
- Round-robin arbitration and full 5 × 5 crossbar connectivity
- UVM test environment for the valid/ready implementation, including scoreboard, assertions, functional coverage, and nine traffic tests
- UVM-free, self-checking RTL testbenches for fast functional validation
- FPGA harnesses for Digilent ZedBoard (XC7Z020), including TCL build and programming scripts

## Router implementations

| | Track A — flat pipelined mesh | Track B — virtual-channel mesh |
|---|---|---|
| Top-level router | `rtl/router.sv` | `rtl/router_top.sv` |
| Mesh top | `rtl/noc_mesh_top.sv` | `rtl/noc_vc_mesh_top.sv` |
| Flow control | Valid/ready with FIFO-full backpressure | Per-VC credit-based |
| Virtual channels | None | 4 by default |
| Arbitration | One round-robin arbiter per output | Separable VC and switch allocation |
| Packet support | Single-flit | Multi-flit with route latching |
| Hop latency | 2 cycles | 5 cycles for a head flit |
| Verification | UVM + directed RTL testbench | Directed RTL testbenches |
| FPGA target | 100 MHz, timing closed | 50 MHz, timing closed |

Track A is the best starting point for learning, simulation, and UVM verification. Track B adds virtual channels and credit flow control for a more complete microarchitecture.

## Repository layout

```text
FPGA IMPLEMENTATION/
├── README.md
├── CLAUDE.md                         # Workspace notes and verified status
└── noc_router_project_paid/
    ├── rtl/                          # Both RTL tracks
    ├── verification/                 # Track A UVM environment and RTL tests
    │   └── rtl_tests/                # UVM-free self-checking testbenches
    ├── sim/                          # File lists, Makefile, simulator scripts
    ├── FPGA/                         # ZedBoard wrappers, constraints, TCL
    ├── docs/                         # Architecture, decisions, reports
    ├── context_mkdwn/                # Focused implementation reference notes
    ├── INDEX.md                      # Documentation entry point
    └── master_markdown/              # Consolidated project reference
```

## Architecture

### Track A: flat pipelined router

Each input is buffered in a FIFO. A flit's destination coordinates are compared with the current router coordinates to select an XY route: resolve X first, then Y, then eject through the local port. Per-output round-robin arbiters choose winners, and a 5 × 5 crossbar drives registered outputs.

```text
flit input → input FIFO → route/head stage → RR arbitration → crossbar → output register
```

The two-cycle-per-hop pipeline keeps inter-router paths registered while retaining up to one flit per output per cycle of throughput.

### Track B: VC / credit router

Each physical input port contains multiple virtual-channel buffers. Route computation, virtual-channel allocation, switch allocation, crossbar traversal, output registration, and credit return are separated into dedicated modules. This isolates traffic classes and supports multi-flit packets.

## Quick start

The tested simulation flow uses QuestaSim 2021.1. Run commands from `noc_router_project_paid/sim`.

### Fast functional checks (recommended)

These testbenches do not require UVM and are the most dependable functional gate.

```powershell
cd noc_router_project_paid\sim
vlib work
vlog -sv -f filelist_rtl.f -f filelist_rtl_tests.f

# Track A: 4 × 4 valid/ready mesh
vsim -c work.tb_mesh_rtl -voptargs="+acc" -do "run -all; quit -f"

# Track B: virtual-channel router
vsim -c work.tb_router_top_rtl -voptargs="+acc" -do "run -all; quit -f"
```

Look for the `*** PASS ***` summary in the transcript.

### UVM test (Track A)

```powershell
cd noc_router_project_paid\sim
vsim -c -do "do run_questa.do tb_noc_mesh_top hotspot_test"
```

Available tests are:

`uniform_random_test`, `bit_complement_test`, `transpose_test`, `neighbor_test`, `hotspot_test`, `backpressure_test`, `self_dest_test`, `mixed_flit_test`, and `oob_error_test`.

On POSIX systems, the Makefile provides equivalent shortcuts:

```bash
cd noc_router_project_paid/sim
make questa TOP=tb_noc_mesh_top TEST=hotspot_test
make regress
make coverage
make coverage-uvm
```

UVM requires UVM 1.2. The UVM regression is useful for stimulus and coverage, but the UVM-free RTL tests are the preferred pass/fail functional check.

## Verification and coverage

Track A verification includes a packet generator, drivers and receivers, monitor, scoreboard, functional coverage, SVA assertions, and mesh traffic patterns:

- Uniform random
- Bit complement
- Transpose
- Neighbor
- Hotspot
- Backpressure
- Self-destination
- Mixed flit types
- Out-of-bounds destination

Current measured results for Track A:

| Flow | Result |
|---|---|
| Directed RTL testbench | 7,376/7,376 packets delivered; 22,196 checks passed |
| UVM regression | 9/9 tests run; 100% functional coverage |
| Directed RTL code coverage | 92.94% total |
| UVM code coverage | 84.19% total |

Coverage figures apply only to Track A and use different benches, runtimes, and instrumentation; they should not be compared as a single metric. Track B currently has directed functional tests but no reported coverage baseline.

## FPGA implementation

The project includes ZedBoard FPGA wrappers, constraints, self-test traffic injectors, ILA/VIO support, build scripts, and programming scripts in [`noc_router_project_paid/FPGA/`](noc_router_project_paid/FPGA/).

| Track | Device | Target clock | Timing result |
|---|---|---:|---|
| Track A | Zynq-7000 XC7Z020-CLG484-1 | 100 MHz | WNS +0.192 ns, WHS +0.029 ns |
| Track B | Zynq-7000 XC7Z020-CLG484-1 | 50 MHz | WNS +1.677 ns, WHS +0.024 ns |

With Vivado 2020.1 installed, build Track A from the project directory:

```powershell
cd noc_router_project_paid
& $env:VIVADO_BIN -mode batch -source FPGA/tcl/build_noc_fpga.tcl
```

Before building hardware, simulate `FPGA/sim/tb_noc_fpga_core.sv`. After implementation, check the script's `TIMING : *** MET ***` or `*** FAILED ***` line; a generated bitstream alone is not evidence that timing closed.

## Configuration

Track A parameters are defined in [`rtl/noc_pkg.sv`](noc_router_project_paid/rtl/noc_pkg.sv), including mesh dimensions, FIFO depth, data width, and coordinate width.

Track B parameters are defined in [`rtl/router_config.sv`](noc_router_project_paid/rtl/router_config.sv):

```systemverilog
parameter int NUM_PORTS  = 5;
parameter int NUM_VCS    = 4;
parameter int VC_DEPTH   = 4;
parameter int FLIT_WIDTH = 32;
parameter int X_WIDTH    = 4;
parameter int Y_WIDTH    = 4;
```

`NUM_PORTS` remains fixed at five because the router topology and 5-way crossbar primitives are deliberately built around the standard 2-D mesh port set.

## Documentation

Start with the [project index](noc_router_project_paid/INDEX.md). It links to the architecture, design decisions, verification guide, timing analysis, FPGA implementation guide, and focused per-module notes.

Useful entry points:

- [Project map and track selection](noc_router_project_paid/context_mkdwn/00-project-map.md)
- [Track A router details](noc_router_project_paid/context_mkdwn/10-rtl-flat-router.md)
- [Track B architecture](noc_router_project_paid/context_mkdwn/20-rtl-vc-input-buffer.md)
- [Simulation and coverage flow](noc_router_project_paid/context_mkdwn/40-sim-flow.md)
- [Known issues and limitations](noc_router_project_paid/context_mkdwn/90-known-issues.md)
- [ZedBoard bring-up for Track A](noc_router_project_paid/context_mkdwn/50-fpga-bringup.md)

## Important notes

- The two tracks use different packages and types. Do not import `noc_pkg` into Track B modules; Track B uses `router_config_pkg` and `noc_vc_pkg`.
- `rtl/` includes generated simulator work libraries and the project includes simulation artifacts. Keep source file lists explicit when compiling.
- The original README inside `noc_router_project_paid/` predates later fixes. Prefer the root README, the project index, and the context notes for the current implementation status.

## License

No license file is currently included. Add a license before distributing or accepting external contributions.
