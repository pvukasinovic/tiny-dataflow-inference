# SPDX-License-Identifier: Apache-2.0
"""Tiny Dataflow Inference Processor host-driven Cocotb regression.

Place in test/test.py of the official Tiny Tapeout template.
Runs against the same external pin interface in RTL and gate-level simulation.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

REQ, WR, ADDR, HI = 1, 2, 4, 8


async def init(dut):
    dut.clk.value = 0
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    for _ in range(4):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(2, unit="ns")


async def cycle_bus(dut, mode, value=0):
    """Drive controls before rising edge; release request after sampling."""
    await FallingEdge(dut.clk)
    dut.ui_in.value = value & 255
    dut.uio_in.value = mode & 15
    await RisingEdge(dut.clk)
    await Timer(2, unit="ns")
    dut.uio_in.value = 0


async def address(dut, a):
    assert 0 <= a < 512
    await cycle_bus(dut, REQ | WR | ADDR, a & 255)
    await cycle_bus(dut, REQ | WR | ADDR | HI, (a >> 8) & 1)


async def write(dut, a, data):
    await address(dut, a)
    await cycle_bus(dut, REQ | WR, data)


async def read(dut, a):
    await address(dut, a)
    await Timer(2, unit="ns")
    return int(dut.uo_out.value)


async def expect(dut, a, value):
    observed = await read(dut, a)
    assert observed == value, (
        f"Register 0x{a:03X}: expected 0x{value:02X}, observed 0x{observed:02X}"
    )


async def read16(dut, a):
    lo = await read(dut, a)
    hi = await read(dut, a + 1)
    value = lo | (hi << 8)
    return value - 65536 if value >= 32768 else value


async def write16(dut, a, value):
    await write(dut, a, value & 255)
    await write(dut, a + 1, (value >> 8) & 255)


def encode_pe(op, a=0, b=0, shift=0):
    """16-bit PE command: op[2:0], A[5:3], B[8:6], shift[12:9]."""
    return (op & 7) | ((a & 7) << 3) | ((b & 7) << 6) | ((shift & 15) << 9)


async def program(dut, slot, commands, metadata=0):
    assert len(commands) == 4
    base = 0x100 + 16 * slot
    for i, insn in enumerate(commands):
        await write(dut, base + 2*i, insn & 255)
        await write(dut, base + 2*i + 1, (insn >> 8) & 255)
    await write(dut, base + 8, metadata)


async def execute(dut, last=0, max_cycles=50):
    await write(dut, 0x004, last)
    await write(dut, 0x003, 1)
    # Poll combinational DONE output using clocks, with an upper bound.
    for _ in range(max_cycles):
        await FallingEdge(dut.clk)
        await Timer(2, unit="ns")
        flags = int(dut.uio_out.value)
        if flags & 0x40:
            assert not (flags & 0x80), "FAULT during execution"
            return
    raise AssertionError(f"Execution timed out after {max_cycles} clock cycles")


@cocotb.test()
async def identity_reset_enable_and_address(dut):
    await init(dut)
    assert int(dut.uio_oe.value) == 0xF0
    assert int(dut.uio_out.value) & 0x10
    await expect(dut, 0x000, 0xC1)
    await expect(dut, 0x001, 0x10)
    await expect(dut, 0x002, 0x00)
    await expect(dut, 0x009, 0x00)
    await write(dut, 0x004, 5)
    await expect(dut, 0x004, 5)
    # ena=0 must block bus outputs and prevent state updates.
    await FallingEdge(dut.clk)
    dut.ena.value = 0
    await Timer(2, unit="ns")
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uo_out.value) == 0
    await cycle_bus(dut, REQ | WR, 2)
    dut.ena.value = 1
    await Timer(2, unit="ns")
    await expect(dut, 0x004, 5)
    # Synchronous reset returns control state to defaults.
    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await Timer(2, unit="ns")
    dut.uio_in.value = 0
    dut.rst_n.value = 1
    await expect(dut, 0x004, 0)
    dut._log.info("PASS identity, reset, enable and address protocol")


@cocotb.test()
async def storage_readback_and_bad_commands(dut):
    await init(dut)
    for a, value in [(0x020, 0xE1), (0x021, 0x03),
                     (0x030, 0x11), (0x038, 0x02),
                     (0x040, 0x2F), (0x048, 0xF0)]:
        await write(dut, a, value)
        await expect(dut, a, value)
    for pe, value in enumerate([0x1234, -1, -32768, 32767]):
        await write16(dut, 0x010 + pe*2, value)
        result = await read16(dut, 0x010 + pe*2)
        assert result == value, f"R register {pe}: {result} != {value}"
    for pe, value in enumerate([0x5678, -2, -1234, 22222]):
        await write16(dut, 0x018 + pe*2, value)
        result = await read16(dut, 0x018 + pe*2)
        assert result == value, f"S register {pe}: {result} != {value}"
    insns = [encode_pe(4, 3, 4)] * 4
    await program(dut, 7, insns, 0x13)
    for i, value in enumerate([0x1c, 0x01]*4 + [0x13]):
        await expect(dut, 0x170 + i, value)
    # Illegal program last value should latch BAD_FIELD (4).
    await write(dut, 0x004, 0xFF)
    await expect(dut, 0x004, 0)
    await expect(dut, 0x009, 4)
    assert (await read(dut, 0x002)) & 4
    await write(dut, 0x003, 4)
    await expect(dut, 0x009, 0)
    assert not ((await read(dut, 0x002)) & 4)
    # Unmapped address should latch BAD_ADDRESS (1).
    await write(dut, 0x00A, 0x11)
    await expect(dut, 0x009, 1)
    await write(dut, 0x003, 4)
    # Invalid command should latch BAD_COMMAND (2).
    await write(dut, 0x003, 0x80)
    await expect(dut, 0x009, 2)
    dut._log.info("PASS buffer/register/instruction readback and error reporting")


@cocotb.test()
async def four_parallel_macs(dut):
    await init(dut)
    # Inputs [1,-2,3,0] (low nibble first).
    await write(dut, 0x020, 0xE1)
    await write(dut, 0x021, 0x03)
    # Weights for each PE.
    for addr, value in [(0x030, 0x11), (0x031, 0x11),
                        (0x038, 0x02), (0x039, 0x1F),
                        (0x040, 0x2F), (0x041, 0x01),
                        (0x048, 0xF0), (0x049, 0x12)]:
        await write(dut, addr, value)
    for pe, val in enumerate([1, 0, -1, 2]):
        await write16(dut, 0x010 + pe*2, val)
    await program(dut, 0, [encode_pe(4, 3, 4)]*4, 0x13)
    await execute(dut)
    for pe, expected in enumerate([3, -1, -3, 10]):
        actual = await read16(dut, 0x010 + pe*2)
        assert actual == expected, f"PE{pe}: expected {expected}, got {actual}"
    await expect(dut, 0x002, 0x02)
    await expect(dut, 0x005, 0x04)
    await expect(dut, 0x008, 0x04)
    dut._log.info("PASS four parallel MACs")


@cocotb.test()
async def horizontal_vertical_reduction(dut):
    await init(dut)
    for pe, val in enumerate([3, -1, -3, 10]):
        await write16(dut, 0x010 + pe*2, val)
    # PE0+PE1 and PE2+PE3, followed by PE0+PE2.
    await program(dut, 0,
                  [encode_pe(2, 1, 5), 0, encode_pe(2, 1, 5), 0], 0)
    await program(dut, 1, [encode_pe(2, 1, 6), 0, 0, 0], 0)
    await execute(dut, last=1)
    for pe, expected in enumerate([9, -1, 7, 10]):
        actual = await read16(dut, 0x010 + pe*2)
        assert actual == expected, f"PE{pe}: expected {expected}, got {actual}"
    await expect(dut, 0x005, 2)
    await expect(dut, 0x008, 0)
    dut._log.info("PASS horizontal + vertical registered reduction")


@cocotb.test()
async def signed_multiply_and_alu_extremes(dut):
    await init(dut)
    # This deliberately detects incorrect 8->16 bit zero extension in MUL.
    # PE0: (-8)*7=-56. PE1: (-8)*(-8)=64.
    await write(dut, 0x020, 0x88)   # X0=-8, X1=-8
    await write(dut, 0x030, 0x07)   # W0=7
    await write(dut, 0x038, 0x08)   # W1=-8
    await program(dut, 0,
                  [encode_pe(3, 3, 4), encode_pe(3, 3, 4), 0, 0], 0)
    await execute(dut)
    assert await read16(dut, 0x010) == -56, (
        "Signed MUL -8*7 must produce 0xFFC8, not 0x00C8. "
        "Fix PE MUL sign extension if this fails."
    )
    assert await read16(dut, 0x012) == 64
    dut._log.info("PASS signed multiplication extremes")


@cocotb.test()
async def overflow_sticky_fault_clear(dut):
    await init(dut)
    # Overflow: 32767 + 1 -> -32768 and sticky OVF bit.
    await write16(dut, 0x010, 32767)
    await program(dut, 0, [encode_pe(2, 1, 7), 0, 0, 0], 0)
    await execute(dut)
    assert await read16(dut, 0x010) == -32768
    status = await read(dut, 0x002)
    assert status & 0x08, f"Overflow flag expected, STATUS=0x{status:02X}"
    await write(dut, 0x003, 4)
    status = await read(dut, 0x002)
    assert not (status & 0x08), f"Overflow flag was not cleared: 0x{status:02X}"
    dut._log.info("PASS overflow and clear-status behavior")

# ---- Extended silicon-preflight tests ----------------------------------------
# The reference functions below are independent of the DUT implementation.
import random


def s4(x):
    x &= 15
    return x - 16 if x & 8 else x


def s16(x):
    x &= 65535
    return x - 65536 if x & 32768 else x


def packed(xs):
    assert len(xs) == 16
    return [((xs[2*i] & 15) | ((xs[2*i+1] & 15) << 4)) for i in range(8)]


async def upload_tensor(dut, activations, weights):
    """Pack real signed INT4 values exactly as the on-chip buffer expects."""
    assert len(activations) == 16 and len(weights) == 4
    for i, b in enumerate(packed(activations)):
        await write(dut, 0x020+i, b)
    for pe in range(4):
        assert len(weights[pe]) == 16
        for i, b in enumerate(packed(weights[pe])):
            await write(dut, 0x030+8*pe+i, b)


async def read_rs(dut):
    return [await read16(dut, 0x010+2*i) for i in range(4)], [await read16(dut, 0x018+2*i) for i in range(4)]


def model_pe(op, a, b, r, shift):
    if op == 0: return r
    if op == 1: return s16(a)
    if op == 2: return s16(a+b)
    if op == 3: return s16(s4(a)*s4(b))
    if op == 4: return s16(r+s4(a)*s4(b))
    if op == 5: return s16(max(a,b))
    if op == 6: return s16(a >> shift)
    if op == 7: return s16(max(-8,min(7,a >> shift)))
    raise ValueError(op)


def source_model(sel, pe, rs, ss, activation, weights):
    nbr_h = [1,0,3,2][pe]
    nbr_v = [2,3,0,1][pe]
    return [0, rs[pe], ss[pe], activation, weights[pe],
            rs[nbr_h], rs[nbr_v], 1][sel]


async def program_one(dut, ops, metadata=0):
    await program(dut, 0, ops, metadata)


@cocotb.test()
async def exhaustive_int4_activation_weight_pairs(dut):
    """All 16x16 signed INT4 products, distributed over 4 distinct weight banks."""
    await init(dut)
    await program_one(dut, [encode_pe(3,3,4)]*4)
    # 16 activation values x 4 batches x 4 parallel weights = 256 pairs.
    for a in range(-8, 8):
        for group in range(4):
            weights = [(-8+4*group+i) for i in range(4)]
            await write(dut, 0x020, a & 15)
            for pe, w in enumerate(weights):
                await write(dut, 0x030+8*pe, w & 15)
            await execute(dut)
            result,_ = await read_rs(dut)
            for pe,w in enumerate(weights):
                expected = a*w
                assert result[pe] == expected, (
                    f"signed INT4 MUL activation={a}, weight={w}, PE{pe}: "
                    f"expected {expected}, got {result[pe]}")
    dut._log.info("PASS all 256 signed INT4 activation x weight products")


@cocotb.test()
async def tensor_packing_and_weight_bank_isolation(dut):
    """Check every input/weight nibble and all 4 independent model-weight banks."""
    await init(dut)
    rng = random.Random(0x44A55)
    activations = [rng.randrange(-8,8) for _ in range(16)]
    weights = [[rng.randrange(-8,8) for _ in range(16)] for _ in range(4)]
    await upload_tensor(dut, activations, weights)
    for off, value in enumerate(packed(activations)):
        await expect(dut, 0x020+off, value)
    for pe in range(4):
        for off, value in enumerate(packed(weights[pe])):
            await expect(dut, 0x030+8*pe+off, value)
    # Overwrite only the last byte of bank 2; all others must be intact.
    await write(dut, 0x040+7, 0x8F)
    weights[2][14:16] = [-1,-8]
    for pe in range(4):
        for off, value in enumerate(packed(weights[pe])):
            await expect(dut, 0x030+8*pe+off, value)
    dut._log.info("PASS tensor nibble packing / four weight bank isolation")


@cocotb.test()
async def streamed_model_dot_products(dut):
    """Four simultaneous 16-element INT4 dot products with Python golden outputs."""
    await init(dut)
    rng = random.Random(0xD07D07)
    a = [rng.randrange(-8,8) for _ in range(16)]
    w = [[rng.randrange(-8,8) for _ in range(16)] for _ in range(4)]
    await upload_tensor(dut, a, w)
    initial = [-23, 100, -200, 327]
    for pe, r in enumerate(initial):
        await write16(dut, 0x010+2*pe, r)
    # repeat 15 => 16 MAC cycles; metadata[4] increments stream every cycle
    await program_one(dut, [encode_pe(4,3,4)]*4, 0x1F)
    await execute(dut, max_cycles=60)
    actual,_ = await read_rs(dut)
    expected = [s16(initial[pe]+sum(a[i]*w[pe][i] for i in range(16))) for pe in range(4)]
    assert actual == expected, f"four 16-element dot products: expected={expected}, got={actual}"
    await expect(dut, 0x005, 16)
    await expect(dut, 0x008, 0)  # 4-bit stream index wraps 15 -> 0
    dut._log.info("PASS four independent 16-lane INT4 dot products: %s", expected)


@cocotb.test()
async def randomized_model_dot_products(dut):
    """Multiple seeded model-like inference vectors, including sparse/extreme values."""
    await init(dut)
    rng = random.Random(0x51A7)
    await program_one(dut, [encode_pe(4,3,4)]*4, 0x1F)
    patterns = [
        ([0]*16, [[rng.randrange(-8,8) for _ in range(16)] for _ in range(4)]),
        ([7]*16, [[-8]*16, [7]*16, [0]*16, [1]*16]),
        ([-8]*16, [[-8]*16, [7]*16, [-1]*16, [0]*16]),
        ([(-8 if i%2 else 7) for i in range(16)], [[(-8 if (i+p)%2 else 7) for i in range(16)] for p in range(4)]),
    ]
    for _ in range(12):
        patterns.append(([rng.randrange(-8,8) if rng.randrange(4) else 0 for _ in range(16)],
                         [[rng.randrange(-8,8) if rng.randrange(4) else 0 for _ in range(16)] for _ in range(4)]))
    for case,(a,w) in enumerate(patterns):
        await upload_tensor(dut,a,w)
        initial = [rng.randrange(-30000,30000) for _ in range(4)]
        for p in range(4):
            await write16(dut,0x010+2*p,initial[p])
        await execute(dut,max_cycles=60)
        actual,_ = await read_rs(dut)
        expected=[s16(initial[p]+sum(a[i]*w[p][i] for i in range(16))) for p in range(4)]
        assert actual==expected, f"dot-product case={case} expected={expected} got={actual}"
    dut._log.info("PASS %d seeded model-style dot-product vectors",len(patterns))


@cocotb.test()
async def all_pe_operations_and_sources(dut):
    """Golden-model check across all opcodes and 8x8 operand selector combinations."""
    await init(dut)
    rng = random.Random(0x0FFEE)
    # All selectors on A and B for each opcode; 8*8*8=512 cases.
    # Check 4 PEs concurrently (one operation per execution).
    cases = [(op,a,b) for op in range(8) for a in range(8) for b in range(8)]
    rng.shuffle(cases)
    for idx,(op,sa,sb) in enumerate(cases):
        initial_r=[rng.randrange(-32768,32768) for _ in range(4)]
        initial_s=[rng.randrange(-32768,32768) for _ in range(4)]
        shift=idx%16
        activation=rng.randrange(-8,8)
        ww=[rng.randrange(-8,8) for _ in range(4)]
        await write(dut,0x020,activation&15)
        for p in range(4):
            await write(dut,0x030+8*p,ww[p]&15)
            await write16(dut,0x010+2*p,initial_r[p])
            await write16(dut,0x018+2*p,initial_s[p])
        await program_one(dut,[encode_pe(op,sa,sb,shift)]*4)
        expect_r=[]
        for p in range(4):
            va=source_model(sa,p,initial_r,initial_s,activation,ww)
            vb=source_model(sb,p,initial_r,initial_s,activation,ww)
            expect_r.append(model_pe(op,va,vb,initial_r[p],shift))
        await execute(dut)
        actual_r, actual_s = await read_rs(dut)
        assert actual_r == expect_r, (
            f"opcode={op} srcA={sa} srcB={sb} shift={shift} "
            f"case={idx} expected={expect_r} got={actual_r}")
        assert actual_s == initial_s, f"S registers changed unexpectedly in case {idx}"
    dut._log.info("PASS 512 opcode/selector combinations on all four PEs")


@cocotb.test()
async def eight_instruction_program_and_restarts(dut):
    """Exercise all 8 instruction slots, PC advancement, and consecutive starts."""
    await init(dut)
    await write16(dut,0x010,0)
    for slot in range(8):
        await program(dut,slot,[encode_pe(2,1,7),0,0,0],0)
    await execute(dut,last=7,max_cycles=50)
    assert await read16(dut,0x010)==8
    await expect(dut,0x005,8)
    await expect(dut,0x006,7)
    await execute(dut,last=7,max_cycles=50)
    assert await read16(dut,0x010)==16
    await expect(dut,0x005,8)
    dut._log.info("PASS 8 instruction slots and program re-execution")


@cocotb.test()
async def stream_wrap_and_multipass_accumulation(dut):
    """Simulate two passes over a 16-activation vector via two program slots."""
    await init(dut)
    rng=random.Random(0xCAFE)
    aa=[rng.randrange(-8,8) for _ in range(16)]
    ww=[[rng.randrange(-8,8) for _ in range(16)] for _ in range(4)]
    await upload_tensor(dut,aa,ww)
    for p in range(4):
        await write16(dut,0x010+2*p,0)
    for slot in range(2):
        await program(dut,slot,[encode_pe(4,3,4)]*4,0x1F)
    await execute(dut,last=1,max_cycles=80)
    got,_=await read_rs(dut)
    golden=[s16(2*sum(aa[i]*ww[p][i] for i in range(16))) for p in range(4)]
    assert got==golden, f"two streamed passes: expected={golden} got={got}"
    await expect(dut,0x005,32)
    await expect(dut,0x008,0)
    dut._log.info("PASS 2x16 streaming cycles with wraparound and accumulation")


@cocotb.test()
async def write_protection_when_busy(dut):
    """Attempt forbidden writes during a running program; expect BUSY_WRITE fault."""
    await init(dut)
    await program_one(dut,[encode_pe(0)]*4,0x0F)
    await write(dut,0x004,0)
    await write(dut,0x003,1)
    # During busy, select operand address, then write it.
    await write(dut,0x020,0xA5)
    code=await read(dut,0x009)
    assert code==3, f"BUSY_WRITE expected error 3, got {code}"
    assert (await read(dut,0x002)) & 4
    await write(dut,0x003,4)
    # Clearing status is only legal after the sequencer stops.
    dut._log.info("PASS busy-write violation detected")

@cocotb.test()
async def instruction_memory_all_slots_and_invalid_offsets(dut):
    """Distinct nontrivial instruction bytes in all 8 slots; detect aliasing."""
    await init(dut)
    rng=random.Random(0x1234)
    written={}
    for slot in range(8):
        words=[encode_pe(rng.randrange(8),rng.randrange(8),rng.randrange(8),rng.randrange(16)) for _ in range(4)]
        metadata=rng.randrange(32)
        await program(dut,slot,words,metadata)
        for p,word in enumerate(words):
            written[0x100+16*slot+2*p]=word&255
            written[0x100+16*slot+2*p+1]=(word>>8)&255
        written[0x100+16*slot+8]=metadata
    for a,value in written.items():
        await expect(dut,a,value)
    for slot in range(8):
        for offset in range(9,16):
            await expect(dut,0x100+16*slot+offset,0)
    dut._log.info("PASS all eight instruction slots and unused byte regions")


@cocotb.test()
async def inference_layer_with_bias_and_register_reuse(dut):
    """Emulate a quantized dense layer: int4 inputs and weights, int16 biases and outputs."""
    await init(dut)
    rng=random.Random(0x1A9E)
    activations=[rng.randrange(-8,8) for _ in range(16)]
    weights=[[rng.randrange(-8,8) for _ in range(16)] for _ in range(4)]
    biases=[-321, 127, 0, 2048]
    await upload_tensor(dut,activations,weights)
    for p in range(4):
        await write16(dut,0x010+2*p,biases[p])
        await write16(dut,0x018+2*p,biases[p])
    await program_one(dut,[encode_pe(4,3,4)]*4,0x1F)
    await execute(dut,max_cycles=60)
    golden=[s16(biases[p]+sum(activations[i]*weights[p][i] for i in range(16))) for p in range(4)]
    got,s=await read_rs(dut)
    assert got==golden, f"dense layer logits: expected={golden} got={got}"
    assert s==biases, f"S register corrupted during dense layer: {s}"
    # Emulate a subsequent activation stage using an independent instruction.
    # Clamp the accumulated logits to signed 4-bit range [-8, 7].
    await program_one(dut,[encode_pe(7,1,0)]*4,0)
    await execute(dut)
    activated,_=await read_rs(dut)
    expect_act=[min(7,max(-8,value)) for value in golden]
    assert activated==expect_act, f"clamped logits: expected={expect_act} got={activated}"
    dut._log.info("PASS dense layer with bias, 16-lane dot products, and clamp stage")
