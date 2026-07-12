# SCORE — Serial COmpute and Register Engine

A hardware mini-system built in Verilog that combines a **UART**, **FIFO buffers**, a **Register File**, and an **ALU** into a simple serial-commanded compute engine. Designed and implemented at the RTL level, targeting FPGA deployment on a 50 MHz clock.

---

## Overview

The system accepts fixed-format 5-byte command packets over a UART serial interface, performs an 8-bit arithmetic or logic operation via the ALU, stores intermediate results in a register file, and returns the result byte back over UART — all coordinated through two FIFO buffers that decouple the slow serial world from the fast internal datapath.

This mirrors the core of a minimal 8-bit microcontroller (comparable to a simplified 8051 or PIC) or a hardware command processor: send an opcode and operands over serial, the chip computes, and sends the result back.

**The datapath is 8 bits wide end to end** — UART byte, FIFO width, register file, and ALU all operate on 8-bit values. This was a deliberate design choice (see [Design Notes](#design-notes)): it eliminates the need for any byte-to-word assembly logic entirely, since one FIFO byte maps directly onto one operand.

---

## System Architecture

```
                         baud_clk domain                    system clock domain                    baud_clk domain
                       ┌───────────────┐   sync   ┌────────────────────────────────────┐  sync   ┌───────────────┐
   Host / PC  ───TX───►│    RxUnit     │─────────►│  RX FIFO → RxDecoder →             │────────►│    TxUnit     │───TX───► Host / PC
   Host / PC  ◄───RX───│  (BaudGenR,   │ 2-flop + │  CommandExecUnit → RegFile/ALU →   │ send vs │  (BaudGenT,   │◄───RX─── Host / PC
                       │ SIPO, DeFrame,│ edge-det │  TxFIFOWriteCtrl → TX FIFO         │ active/ │ Parity, PISO) │
                       │  ErrorCheck)  │          │                                    │  done   │               │
                       └───────────────┘          └────────────────────────────────────┘         └───────────────┘
```

The two `baud_clk`-domain boxes are physically clocked by dividers generated *from* `clock` (mesochronous, not independent oscillators). The two `sync` points are the only places clock-domain-crossing logic exists in the whole design — `RxFIFOWriteCtrl` on the way in, `TxFIFOReadCtrl` on the way out.

---

## Modules

### UART physical layer (`TxUnit.v` / `RxUnit.v` / `UARTTOPMOD.v`)

| Sub-module | Description |
|---|---|
| `BaudGenT.v` | TX baud rate generator — 1x bit clock, divided from 50 MHz |
| `BaudGenR.v` | RX baud rate generator — 16x oversampled clock, for bit-center alignment |
| `Parity.v` | Computes odd/even parity bit via XOR reduction |
| `PISO.v` | Parallel-in serial-out shift register — serializes the 11-bit TX frame |
| `SIPO.v` | Serial-in parallel-out shift register with a 4-state bit-timing FSM |
| `DeFrame.v` | Strips start/stop/parity bits, extracts the raw 8-bit data byte |
| `ErrorCheck.v` | Detects parity, start-bit, and stop-bit errors |
| `UARTTOPMOD.v` | Internal TX->RX loopback harness for validating the UART physical layer in isolation — **not** part of the compute pipeline (see `UARTComputeTop.v` below) |

**Supported baud rates:** 2400 / 4800 / 9600 / 19200
**Frame format:** 1 start bit + 8 data bits (LSB first) + 1 parity bit + 1 stop bit
**Parity modes:** Odd, Even

### Rate decoupling & protocol layer

| Module | Description |
|---|---|
| `SyncFIFO.v` | Generic, parameterized, First-Word-Fall-Through (FWFT) synchronous FIFO. Instantiated twice — independent RX and TX instances, each with its own storage and pointers. |
| `RxFIFOWriteCtrl.v` | Synchronizes `RxUnit`'s `done_flag` into the `clock` domain (2-flop + edge-detect), filters out bytes with a nonzero `error_flag` |
| `RxDecoder.v` | Assembles the fixed 5-byte command packet from the RX FIFO into decoded fields; has no knowledge of `RxUnit` or `baud_clk` at all |
| `CommandExecUnit.v` | Drives the register file's read addresses and the ALU's operand mux from the decoded command; handles writeback and one-cycle result capture |
| `TxFIFOWriteCtrl.v` | Pushes each ALU result byte into the TX FIFO (no synchronizer needed — already in the `clock` domain) |
| `TxFIFOReadCtrl.v` | Drains the TX FIFO into `TxUnit`, sequencing `send` against synchronized `tx_active_flag`/`tx_done_flag` |

### Register File (`reg_array.v`, module `reg_array`)
8 general-purpose registers (R0-R7), each 8 bits wide.
- Two combinational read ports (operand A / operand B to the ALU); `R0` is hardwired to always read as zero
- One synchronous write port, gated by `write_enable && wr != 0` — writes to `R0` are silently dropped
- Synchronous reset clears all 8 registers

### ALU (`alu.v`, module `alu`)
8-bit ALU built on an explicit distributed carry-lookahead adder (`gp_cell` + `carry_lookahead_network` + `distributed_cla_adder`), RISC-V-style opcode encoding.

**Supported operations:** ADD, SUB, AND, OR, XOR, SLT (signed less-than), SLTU (unsigned less-than), SLL, SRL, SRA

### Top-level integration
- `UARTComputeTop.v` — the real system: full chain from `rx_serial_in` through every module above to `tx_serial_out`
- `UARTTOPMOD.v` — the UART-only loopback harness (see table above), useful specifically because it isolates physical-layer bugs from everything built on top of it

---

## Protocol

Fixed 5-byte command packet, host -> device:

| Byte | Field | Notes |
|---|---|---|
| 0 | opcode | `[7]=imm_sel`, `[6:4]=reserved`, `[3:0]=alu_control` (passed straight into the ALU) |
| 1 | sr1 | Source register 1 (low 3 bits used; upper bits reserved on the wire) |
| 2 | sr2 | Source register 2 (ignored when `imm_sel=1`) |
| 3 | wr | Destination register. `wr=0` computes and returns a result without writing back |
| 4 | immediate | Used as operand B when `imm_sel=1`; ignored otherwise |

Operand A is always `sr1`. Operand B is `sr2` or `immediate`, selected by `imm_sel`. Setting `sr1=0, imm_sel=1, alu_control=ADD` loads an arbitrary 8-bit constant into a register with no dedicated "load immediate" opcode, since `R0` reads as zero.

The device returns exactly one response byte (the ALU result) per command.

---

## Data Flow

1. Host sends a 5-byte command packet over UART RX
2. `RxFIFOWriteCtrl` synchronizes and pushes each validated byte into the RX FIFO
3. `RxDecoder` assembles the 5 bytes into `opcode` / `sr1` / `sr2` / `wr` / `immediate`, then pulses `cmd_valid`
4. `CommandExecUnit` drives the register file's read ports and the ALU's operand mux, computes the result
5. Result is written back to the register file (unless `wr=0`) and captured as a one-cycle `result_valid` pulse
6. `TxFIFOWriteCtrl` pushes the result byte into the TX FIFO
7. `TxFIFOReadCtrl` sequences the byte out to `TxUnit`, which serializes it back to the host over UART TX

---

## Testbenches

**Verification status: 152/152 checks passing across all eleven testbenches** (Icarus Verilog). Raw console output for each run is saved under `sim/results/`, mirroring this table's structure; a GTKWave-ready waveform dump/session for the full system test lives under `sim/waves/`.

| Testbench | Covers | Result |
|---|---|---|
| `tb/uart/UARTTOPMOD_tb.v` | Entire UART physical layer via internal loopback — byte sweep across multiple baud rates and parity modes, absolute `baud_clk` period measurement, and fault injection (corrupted parity bit) to exercise `ErrorCheck`'s detection path. Individual UART submodules (`TxUnit`, `RxUnit`, `PISO`, `SIPO`, `Parity`, `ErrorCheck`, `DeFrame`, `BaudGenT`, `BaudGenR`) are intentionally **not** tested separately — this one testbench covers them all through their real, wired interfaces. | [22/22](sim_results/uart/UARTTOPMOD_tb.png) |
| `tb/uart/SIPO_reset_stress_tb.v` | Narrow, purpose-built test sweeping the phase of `reset_n` relative to `baud_clk` while `SIPO`'s FSM is forced into non-`IDLE` states, targeting the specific reset/case-ordering bug that was fixed | [30/30](sim_results/uart/SIPO_reset_stress_tb.png) |
| `tb/fifo/SyncFIFO_tb.v` | Fill-to-full/overflow rejection, FWFT visibility, drain ordering, same-cycle read+write, mid-operation reset | [28/28](sim_results/fifo/SyncFIFO_tb.png) |
| `tb/core/ALU_tb.v` | Every opcode, overflow/carry/borrow flags, and the shift-amount masking (`operand_b[2:0]`) | [20/20](sim_results/core/ALU_tb.png) |
| `tb/core/RegisterFile_tb.v` | `R0` hardwiring, write guards, reset, boundary address | [8/8](sim_results/core/RegisterFile_tb.png) |
| `tb/ctrl/RxDecoder_tb.v` | Full 5-byte packet decode, back-to-back packets, mid-packet stall — driven through a behavioral FIFO stub, no UART timing involved | [13/13](sim_results/ctrl/RxDecoder_tb.png) |
| `tb/ctrl/CommandExecUnit_tb.v` | Load-immediate, register-register ops, compute-without-store, integrated against the real register file and ALU | [9/9](sim_results/ctrl/CommandExecUnit_tb.png) |
| `tb/ctrl/RxFIFOWriteCtrl_tb.v` | Synchronizer pulse correctness, error-byte drop, full-FIFO drop | [5/5](sim_results/ctrl/RxFIFOWriteCtrl_tb.png) |
| `tb/ctrl/TxFIFOWriteCtrl_tb.v` | Registered pass-through, full-FIFO drop | [4/4](sim_results/ctrl/TxFIFOWriteCtrl_tb.png) |
| `tb/ctrl/TxFIFOReadCtrl_tb.v` | `send`/`active`/`done` sequencing against a mimicked PISO | [4/4](sim_results/ctrl/TxFIFOReadCtrl_tb.png) |
| `tb/top/UARTComputeTop_tb.v` | Full system: real bit-banged UART command packets in, decoded response bytes out, exercising every module through the actual top-level wiring | [9/9](sim_results/top/UARTComputeTop_tb.png) |

---

## Project Status

| Component | RTL Design | Testbench | Simulation Run | Synthesis |
|---|---|---|---|---|
| UART TX | Done | Done | Done | Pending |
| UART RX | Done (2 bugs fixed) | Done | Done | Pending |
| FIFO | Done | Done | Done | Pending |
| RX/TX control (decoder, exec unit, FIFO ctrl) | Done | Done | Done | Pending |
| Register File | Done (2 bugs fixed) | Done | Done | Pending |
| ALU | Done (3 bugs fixed) | Done | Done | Pending |
| Top Level | Done | Done | Done | Pending |

---

## Known Issues

- **`SIPO.v` — FIXED.** The original `if (!reset_n) begin ... end` had no `else` before the following `case(next_state)`, so on the reset edge both branches executed in the same always-block invocation — the `case` read the pre-reset (stale) value of `next_state`, and its own non-blocking assignments, issued later in program order, won at the end of the time step, undermining the reset on that exact cycle. Fixed by adding the missing `else`. See `tb/uart/SIPO_reset_stress_tb.v` for a targeted regression test.
- **`BaudGenR.v` — FIXED.** `RxUnit.v` instantiates a module named `BaudGenR`, but the module was originally defined under a mismatched module/file name. Fixed by aligning the module name, filename, and every instantiation to `BaudGenR` consistently.
- **`alu.v` — FIXED.** `SLTU`'s comparison logic (`comp_flag = ~carry_out`) is only valid if the shared adder is actually computing `A - B`, but the `is_sub` control wire never included `SLTU` in its condition — only `SUB`/`SLT` did. This meant `SLTU` silently computed `A + B` instead, giving wrong results whenever the addition's carry-out happened to differ from the subtraction's. Caught by `ALU_tb`'s `SLTU unsigned 1 < 0xFF` vector. Fixed by adding `SLTU` to `is_sub`.
- **`PISO.v` — reviewed, not a synthesis blocker.** The shift register (`frame_man`) is updated inside a combinational `always @(*)` block that reads and writes itself, which does infer a latch rather than a clean synchronous register. This works correctly in simulation because it's continuously re-evaluated on every `baud_clk`-paced state change from the surrounding clocked FSM (`stop_count`/`next_state`) — it is not a combinational feedback loop with no clocked anchor, and it is not expected to actually fail synthesis. That said, it is not textbook synchronous-design style, and moving `frame_man`'s shift into a clocked `always @(posedge baud_clk)` block would be a worthwhile cleanup for a more portable, "textbook-correct" HDL structure across toolchains.

---

## Design Notes

- The compute core (ALU + register file) is deliberately 8 bits wide, matching UART byte granularity end to end — this was a scale-down from an earlier 32-bit version, made specifically because it eliminates the need for any byte-to-word assembly/disassembly logic between the FIFOs and the compute core, at the cost of a 0-255 (unsigned) / -128 to 127 (signed) result range. There is no memory subsystem in this design — the register file is the only storage.
- `SyncFIFO` is a single reusable module template, instantiated twice (RX and TX) with fully independent storage and pointers — never a single shared instance, since the two directions have opposite data flow, different producers/consumers, and independent backpressure semantics.
- Verification uses three tiers deliberately, not just one: module-level tests reach corner cases and internal signals (ALU flags, CDC stress timing) a system-level test can't observe or provoke; subsystem/system-level tests catch wiring and integration bugs (e.g. a reset-polarity mismatch at an instantiation boundary) that no module-level test can see, since those bugs only exist at the connection point.

---

## Next Steps

- [x] Run the full testbench suite in a simulator (Icarus Verilog) and confirm all self-checks pass — **152/152 passing**
- [ ] Synthesize each module and record timing/area/power reports (see repository structure under `synth/reports/`)
- [ ] Check timing closure at 50 MHz, particularly across the two clock-domain-crossing points

---

## License

MIT License — see [LICENSE](LICENSE) for details. Feel free to use, modify, and build on this.
