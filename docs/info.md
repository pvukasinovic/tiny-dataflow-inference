# Tiny Dataflow Inference Processor

A programmable 4-processing-element (PE) dataflow accelerator for INT4 neural-network inference and experimental reconfigurable computing.

## How it works

### Architecture

The processor implements a 2×2 array of processing elements with configurable arithmetic operations, programmable operand routing, local registers, and a hardware instruction sequencer.

The architecture consists of five main components:

1. **Host Interface** — An 8-bit memory-mapped interface for uploading programs, loading operands, configuring registers, starting execution, and reading results.
2. **Instruction Memory** — Eight programmable 72-bit instruction words.
3. **Operand Buffer** — Stores 16 INT4 input values and four banks of 16 INT4 weights.
4. **Processing Element Fabric** — Four interconnected PEs, each containing arithmetic logic, programmable operand selection, and two 16-bit registers (R and S).
5. **Sequencer** — Executes instructions, controls the PEs, advances operand streams, and reports execution status.

### Processing Elements

Each PE supports:

- Signed INT4 multiplication.
- INT16 addition and subtraction.
- Multiply-accumulate (MAC) operations.
- Register-based intermediate-result storage.
- Programmable operand selection.
- Horizontal and vertical neighbor communication.

All four processing elements operate in parallel under control of the instruction sequencer.

Intermediate results can be routed between neighboring PEs, enabling multi-stage computations such as reductions and dot products.

### Programmable Execution

The processor executes programs uploaded through its host interface.

A typical program runs as follows:

1. The host uploads instructions into instruction memory.
2. Input operands and weights are written into the operand buffer.
3. PE registers are initialized if required.
4. The host configures the final instruction index.
5. The host issues the START command.
6. The sequencer executes the programmed operations.
7. The processor asserts DONE.
8. The host reads the resulting PE registers.

Each PE can perform a different operation according to its instruction configuration.

### Host Interface

The processor communicates through an 8-bit host data bus and four control inputs.

#### Dedicated Inputs

| Pins         | Description                     |
| ------------ | ------------------------------- |
| `ui_in[7:0]` | Host write-data and address bus |

#### Dedicated Outputs

| Pins          | Description        |
| ------------- | ------------------ |
| `uo_out[7:0]` | Host read-data bus |

#### Bidirectional Pins

| Pin      | Signal | Direction | Description                      |
| -------- | ------ | --------- | -------------------------------- |
| `uio[0]` | REQ    | Input     | Host transaction request         |
| `uio[1]` | WR     | Input     | Write operation selector         |
| `uio[2]` | ADDR   | Input     | Address-register access selector |
| `uio[3]` | HI     | Input     | High address-bit selector        |
| `uio[4]` | READY  | Output    | Interface ready                  |
| `uio[5]` | BUSY   | Output    | Sequencer executing              |
| `uio[6]` | DONE   | Output    | Execution completed              |
| `uio[7]` | FAULT  | Output    | Error detected                   |

The host interface uses synchronous transactions. Writes are captured on the rising edge of the clock, while the selected register's read data is available combinationally.

### Memory Map

| Address       | Function                |
| ------------- | ----------------------- |
| `0x000`       | Device ID (`0xC1`)      |
| `0x001`       | ISA version (`0x10`)    |
| `0x002`       | Status register         |
| `0x003`       | Control register        |
| `0x004`       | Final instruction index |
| `0x005`       | Cycle counter           |
| `0x006`       | Program counter         |
| `0x007`       | Iteration counter       |
| `0x008`       | Stream index            |
| `0x009`       | Error code              |
| `0x010–0x017` | PE R registers          |
| `0x018–0x01F` | PE S registers          |
| `0x020–0x027` | Input operand buffer    |
| `0x030–0x04F` | Weight buffers          |
| `0x100–0x17F` | Instruction memory      |

Each PE register is 16 bits and is accessed through two consecutive byte addresses.

### Control Commands

Write the following values to address `0x003`:

| Value  | Command      | Description                  |
| ------ | ------------ | ---------------------------- |
| `0x01` | START        | Begin program execution      |
| `0x02` | ABORT        | Stop execution               |
| `0x04` | CLEAR_STATUS | Clear fault and status flags |

### Arithmetic Precision

The processor uses signed INT4 inputs and weights with values between -8 and +7.

Multiplication produces an 8-bit signed product. Arithmetic results and accumulators are stored in 16-bit registers.

The architecture is designed to explore compact inference kernels, dot products, parallel arithmetic, and reconfigurable dataflow scheduling.

## How to test

### 1. Initialize the processor

1. Connect a clock to `clk`.
2. Set `ena = 1`.
3. Assert `rst_n = 0` for several clock cycles.
4. Deassert reset by setting `rst_n = 1`.
5. Verify that READY (`uio[4]`) becomes high.

The current design target is 10 MHz. The maximum physical operating frequency has not yet been verified.

### 2. Access a register

The processor uses a 9-bit internal address register.

To select an address:

1. Place the low eight address bits on `ui_in[7:0]`.
2. Set `REQ=1`, `WR=1`, `ADDR=1`, and `HI=0`.
3. Hold these signals through a rising clock edge.
4. Deassert REQ.
5. Place address bit 8 on `ui_in[0]`, with `ui_in[7:1]` set to zero.
6. Set `REQ=1`, `WR=1`, `ADDR=1`, and `HI=1`.
7. Hold through another rising clock edge and deassert REQ.

The selected register's value appears on `uo_out[7:0]`.

### 3. Read the device ID

Select address `0x000`.

Expected result:

`uo_out = 0xC1`

Select address `0x001`.

Expected result:

`uo_out = 0x10`

These values identify the device and instruction-set version.

### 4. Upload instructions

Instruction memory begins at address `0x100`.

Each instruction contains nine bytes, with 16 bytes of address space reserved for each instruction slot.

To write a data byte:

1. Select the target address.
2. Place the byte on `ui_in[7:0]`.
3. Set `REQ=1`, `WR=1`, `ADDR=0`, and `HI=0`.
4. Hold the transaction through a rising clock edge.
5. Deassert REQ.

The internal address automatically increments after a valid data transaction.

Valid instruction-byte offsets are 0 through 8.

### 5. Load operands

Write packed INT4 input values to addresses `0x020–0x027`.

Write packed INT4 weights to addresses `0x030–0x04F`.

Each byte contains two 4-bit operands.

Initialize the R and S registers if the program requires nonzero starting values.

### 6. Execute the program

1. Write the last instruction index to register `0x004`.
2. Write `0x01` to control register `0x003`.
3. Observe BUSY (`uio[5]`) during execution.
4. Wait until DONE (`uio[6]`) is asserted.
5. Read the output registers.

### 7. Read computation results

The four R registers are mapped to addresses `0x010–0x017`.

The four S registers are mapped to addresses `0x018–0x01F`.

Each 16-bit value is read as two bytes, low byte first.

The reference parallel-MAC simulation produces:

| Processing Element | Decimal Result | Hexadecimal Result |
| ------------------ | -------------- | ------------------ |
| PE0                | 3              | `0x0003`           |
| PE1                | -1             | `0xFFFF`           |
| PE2                | -3             | `0xFFFD`           |
| PE3                | 10             | `0x000A`           |

The reference program completes in four execution cycles.

The corresponding expected registers are:

| Address | Expected Value        |
| ------- | --------------------- |
| `0x002` | `0x02` (DONE)         |
| `0x005` | `0x04` (cycles)       |
| `0x008` | `0x04` (stream index) |
| `0x010` | `0x03`                |
| `0x011` | `0x00`                |
| `0x012` | `0xFF`                |
| `0x013` | `0xFF`                |
| `0x014` | `0xFD`                |
| `0x015` | `0xFF`                |
| `0x016` | `0x0A`                |
| `0x017` | `0x00`                |

### 8. RTL Verification

The design has been tested using SystemVerilog simulation with Icarus Verilog.

The integration test covers:

- Host interface transactions.
- Device identification and version readback.
- Instruction upload and readback.
- Operand loading.
- Parallel execution across four PEs.
- Signed MAC operations.
- Sequencer completion.
- Result register readback.
- Horizontal and vertical neighbor communication.

The complete RTL also passes generic synthesis using Yosys.

Physical-design validation and timing signoff are separate from these functional tests.

## External hardware

No external peripherals are needed for the processor's internal computations.

To operate the fabricated design, a digital host controller must provide the clock, reset, enable, data bus, and control signals.

Suitable host devices include:

- Microcontrollers with compatible digital I/O.
- FPGA development boards.
- Digital logic test equipment.
- The Tiny Tapeout demonstration board with an appropriate host interface.

A logic analyzer or oscilloscope is optional for debugging transactions and observing execution status.

The processor stores its instructions, operands, weights, and intermediate results internally. No external RAM or storage device is required for the supported workloads.
