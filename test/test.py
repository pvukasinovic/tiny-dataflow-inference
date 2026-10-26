
# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, FallingEdge, RisingEdge


async def set_address(dut, address):
    """Load a 9-bit address into the host interface."""

    # Load low 8 bits
    await FallingEdge(dut.clk)
    dut.ui_in.value = address & 0xFF
    dut.uio_in.value = 0x07  # REQ | WR | ADDR

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.uio_in.value = 0

    # Load high address bit
    await FallingEdge(dut.clk)
    dut.ui_in.value = (address >> 8) & 1
    dut.uio_in.value = 0x0F  # REQ | WR | ADDR | HI

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.uio_in.value = 0


async def read_register(dut, address):
    """Read a register through the external host interface."""
    await set_address(dut, address)
    await Timer(2, unit="ns")
    return int(dut.uo_out.value)


@cocotb.test()
async def test_project(dut):

    dut._log.info("Starting Tiny Dataflow Inference Processor test")

    # 10 MHz clock: 100 ns period
    dut.clk.value = 0
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())

    # Reset for five clock cycles
    for _ in range(5):
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await Timer(2, unit="ns")

    # Test 1: READY
    assert int(dut.uio_out.value) & 0x10, "READY not asserted"
    assert int(dut.uio_oe.value) == 0xF0, "Incorrect GPIO output enables"
    dut._log.info("PASS: READY and GPIO direction")

    # Test 2: Device ID
    device_id = await read_register(dut, 0x000)
    assert device_id == 0xC1, (
        f"DEVICE_ID expected 0xC1, got 0x{device_id:02X}"
    )
    dut._log.info("PASS: DEVICE_ID = 0xC1")

    # Test 3: ISA version
    version = await read_register(dut, 0x001)
    assert version == 0x10, (
        f"ISA_VERSION expected 0x10, got 0x{version:02X}"
    )
    dut._log.info("PASS: ISA_VERSION = 0x10")

    # Test 4: Idle status
    status = await read_register(dut, 0x002)
    assert (status & 0x03) == 0, (
        f"Expected idle status, got 0x{status:02X}"
    )
    dut._log.info("PASS: Processor idle")

    dut._log.info("SUCCESS: All host interface tests passed")