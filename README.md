# Tiny Dataflow Inference Processor

[![GDS](../../workflows/gds/badge.svg)](../../actions/workflows/gds.yaml)
[![Documentation](../../workflows/docs/badge.svg)](../../actions/workflows/docs.yaml)
[![Tests](../../workflows/test/badge.svg)](../../actions/workflows/test.yaml)
[![FPGA](../../workflows/fpga/badge.svg)](../../actions/workflows/fpga.yaml)

**A programmable 4-PE INT4 dataflow accelerator for neural-network inference, built in SystemVerilog for Tiny Tapeout using the SKY130 open-source process.**

## Overview

The Tiny Dataflow Inference Processor is an experimental, programmable computing architecture designed to explore efficient low-precision arithmetic and configurable data movement.

Instead of a traditional CPU instruction pipeline, the processor uses a 2×2 array of processing elements (PEs). Each PE independently executes arithmetic operations while exchanging intermediate results with its neighbors.

The goal is to explore how programmable dataflow architectures can execute inference workloads using local computation, compact instructions, and reduced movement of intermediate results.

The design is intended for fabrication through [Tiny Tapeout](https://tinytapeout.com/) using the SkyWater SKY130 process.

## Architecture

The processor contains five major subsystems:

| Component                 | Description                                                       |
| ------------------------- | ----------------------------------------------------------------- |
| Processing Element Fabric | Four programmable PEs connected in a 2×2 topology                 |
| Instruction Memory        | Eight 72-bit programmable instructions                            |
| Operand Buffer            | 16 INT4 inputs and four banks of 16 INT4 weights                  |
| Sequencer                 | Controls execution, instruction selection, and operand streaming  |
| Host Interface            | Memory-mapped 8-bit interface for programming and result readback |

### Processing Element Fabric

Each PE contains:

- Signed INT4 multiplier
- 16-bit arithmetic and accumulation datapath
- Programmable operand multiplexers
- Two 16-bit registers: R and S
- Horizontal and vertical neighbor connections
- Arithmetic overflow indication

Supported operations include signed multiplication, addition, subtraction, multiply-accumulate, and register/data movement.

All four PEs execute in parallel according to the uploaded instruction program.

### Programmable Dataflow

The processor supports local and neighbor-sourced operands, allowing intermediate results to be reused without returning them to a central memory.

For example, four independent PE results can be combined through a two-stage neighbor reduction.

This makes the design suitable for studying:

- Low-precision neural-network inference
- Dot products and multiply-accumulate kernels
- Programmable dataflow scheduling
- Local interconnect architectures
- Reconfigurable computing

### Instruction Execution

Each program can contain up to eight instructions, with a 72-bit instruction format.

The sequencer coordinates instruction execution and repeated arithmetic operations over streamed operands.

Programs, operands, and initial register values are uploaded through the host interface before execution.

## Host Interface

The chip is controlled through the standard Tiny Tapeout input, output, and bidirectional pins.

| Pins          | Function                        |
| ------------- | ------------------------------- |
| `ui_in[7:0]`  | Host write-data/address bus     |
| `uo_out[7:0]` | Host read-data bus              |
| `uio[0]`      | REQ — transaction request       |
| `uio[1]`      | WR — write selection            |
| `uio[2]`      | ADDR — address-register access  |
| `uio[3]`      | HI — high address-bit selection |
| `uio[4]`      | READY                           |
| `uio[5]`      | BUSY                            |
| `uio[6]`      | DONE                            |
| `uio[7]`      | FAULT                           |

The interface provides access to instruction memory, operand storage, PE registers, sequencer status, and execution controls.

### Register Map

| Address       | Description                         |
| ------------- | ----------------------------------- |
| `0x000`       | Device ID (`0xC1`)                  |
| `0x001`       | ISA version (`0x10`)                |
| `0x002`       | Status                              |
| `0x003`       | Control: START, ABORT, CLEAR_STATUS |
| `0x004`       | Final instruction index             |
| `0x005`       | Cycle counter                       |
| `0x006`       | Program counter                     |
| `0x007`       | Iteration counter                   |
| `0x008`       | Stream index                        |
| `0x009`       | Error code                          |
| `0x010–0x017` | PE R registers                      |
| `0x018–0x01F` | PE S registers                      |
| `0x020–0x027` | INT4 input buffer                   |
| `0x030–0x04F` | INT4 weight buffers                 |
| `0x100–0x17F` | Instruction memory                  |

See [the project datasheet](docs/info.md) for the complete host transaction protocol.

## Verification

The RTL has been functionally verified using Icarus Verilog with an end-to-end host-driven simulation.

### Four-PE MAC Test

A reference program executes signed INT4 arithmetic across all four processing elements.

| PE  | Expected Result | Verified RTL Result |
| --- | --------------: | ------------------: |
| PE0 |               3 |                   3 |
| PE1 |              -1 |                  -1 |
| PE2 |              -3 |                  -3 |
| PE3 |              10 |                  10 |

The reference execution completes in four cycles and asserts the DONE status.

### Neighbor Routing Test

A second simulation exercises inter-PE communication and a two-stage reduction.

Given the values `3`, `-1`, `-3`, and `10`, the expected final reduction is:

`3 + (-1) + (-3) + 10 = 9`

This tests programmable neighbor communication in addition to independent PE arithmetic.

### Synthesis

The complete design has passed generic Yosys synthesis and structural checks.

Initial SKY130 technology mapping produced approximately:

- 6,867 standard-cell, fill, tap, and other instances
- 1,076 sequential cells
- 76,887 µm² total reported cell area at the power-grid stage

These are preliminary implementation results, not final routed area or silicon signoff.

Physical-design placement, routing, static timing analysis, and final verification are performed by the Tiny Tapeout GDS workflow.

## Repository Structure

```text
src/
  tt_um_dataflow.sv
  host_if.sv
  instruction_memory.sv
  operand_buffer.sv
  sequencer.sv
  fabric.sv
  pe.sv

test/
  tb.v
  test.py
  Makefile

docs/
  info.md

info.yaml
```

## Running the Tests

The project uses the standard Tiny Tapeout Cocotb verification infrastructure.

From the repository root:

```bash
cd test
make SIM=icarus
```

The Cocotb test checks processor initialization, host-interface status, device identification, and ISA version.

The project's development testbenches additionally verify parallel MAC execution and inter-PE neighbor routing.

The same Tiny Tapeout verification infrastructure supports RTL and synthesized gate-level testing.

## ASIC Implementation

The processor targets the SkyWater SKY130 open-source technology.

The Tiny Tapeout build flow uses [LibreLane](https://github.com/librelane/librelane) for:

1. RTL synthesis and technology mapping
2. Floorplanning
3. Standard-cell placement
4. Clock-tree synthesis
5. Global and detailed routing
6. Static timing analysis
7. Physical-design checks
8. GDS generation

The initial target clock frequency is 10 MHz, pending physical timing verification.

The final tile footprint will be determined by placement, routing, and timing results.

## Project Goals

This project is an experimental implementation of a small programmable dataflow processor.

Its primary goals are to:

- Demonstrate programmable parallel execution using four PEs.
- Evaluate low-precision arithmetic for inference workloads.
- Explore register-based neighbor communication.
- Implement a software-programmable instruction and operand interface.
- Complete the ASIC design flow from SystemVerilog to a manufacturable layout.

Potential future extensions include larger PE arrays, improved operand streaming, automated instruction scheduling, and compiler-generated dataflow programs.

## Tiny Tapeout

[Tiny Tapeout](https://tinytapeout.com/) is an educational project that makes semiconductor manufacturing accessible for small digital and analog designs.

This project uses the Tiny Tapeout SKY130 infrastructure to explore programmable processor architectures in real silicon.

## Author

**Petar Vukasinovic**

Electrical Engineering — Arizona State University

GitHub: [@pvukasinovic](https://github.com/pvukasinovic)

## Documentation

- [Full project datasheet](docs/info.md)
- [Tiny Tapeout](https://tinytapeout.com/)
- [Tiny Tapeout documentation](https://tinytapeout.com/digital_design/)
- [LibreLane](https://github.com/librelane/librelane)
- [SkyWater SKY130 PDK](https://github.com/google/skywater-pdk)

## License

See the repository license and source file headers for applicable licensing terms.
