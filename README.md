# SCORE-Serial-COmpute-and-Register-Engine
A hardware mini-system built in Verilog that combines a **UART**, **FIFO buffer**, **Register File**, and **ALU** into a simple serial-commanded compute engine. Designed and implemented at the RTL level, targeting FPGA deployment on a 50 MHz clock.

---

## Overview

The system accepts commands and operands over a UART serial interface, performs arithmetic and logic operations via an ALU, stores intermediate results in a register file, and returns results back over UART — all coordinated through FIFO buffers that decouple the slow serial world from the fast internal datapath.

This architecture mirrors the core of a minimal 8-bit microcontroller or a hardware command processor.

---

## System Architecture

```
Host / PC
   │  (serial)
   ▼
UART RX  ──►  RX FIFO  ──►  Register File  ──►  ALU
                                  ▲                │
                                  └────────────────┘
                                    (writeback)
                                        │
                              TX FIFO  ◄──  ALU result
                                  │
                                  ▼
                               UART TX
                                  │  (serial)
                                  ▼
                              Host / PC
```

---

## Modules

### UART (`TxUnit.v` / `RxUnit.v` / `UARTTOPMOD.v`)
The serial communication front-end. Handles conversion between the single-wire serial bitstream and internal parallel bytes.

| Sub-module | Description |
|---|---|
| `BaudGenT.v` | TX baud rate generator — 1× clock divider for 50 MHz |
| `BaudGeneratorR.v` | RX baud rate generator — 16× oversampled for bit centering |
| `Parity.v` | Computes odd/even parity bit via XOR reduction |
| `PISO.v` | Parallel-in serial-out shift register — serializes the 11-bit frame |
| `SIPO.v` | Serial-in parallel-out shift register with 4-state FSM |
| `DeFrame.v` | Strips start/stop/parity bits, extracts raw 8-bit data |
| `ErrorCheck.v` | Detects parity, start bit, and stop bit errors |

**Supported baud rates:** 2400 / 4800 / 9600 / 19200  
**Frame format:** 1 start bit + 8 data bits + 1 parity bit + 1 stop bit  
**Parity modes:** Odd, Even, None

---

### FIFO
Decouples the UART serial interface from the internal datapath. Two FIFOs are used — one on the RX path (incoming data buffer) and one on the TX path (outgoing result buffer). This allows the CPU-side logic to read and write in bursts while UART drains/fills at the baud rate.

- **RX FIFO** — buffers incoming bytes from UART RX until the datapath is ready
- **TX FIFO** — buffers outgoing results until UART TX drains them serially

---

### Register File
Fast internal scratch storage holding operands and intermediate results. Organized as an array of general-purpose registers (e.g. R0–R7), each 8 bits wide.

- Two read ports (operand A and operand B to ALU)
- One write port (result writeback from ALU)
- Loaded from the RX FIFO, read out to the ALU, written back from ALU output

---

### ALU
The compute engine. Takes two operands from the register file and produces a result written back to the register file or forwarded to the TX FIFO.

**Supported operations:**
- Arithmetic: ADD, SUB
- Logic: AND, OR, XOR, NOT
- Comparison: equality / magnitude

---

## Data Flow

```
1. Host sends operands and opcode over serial (UART RX)
2. Bytes buffered in RX FIFO
3. Datapath reads operands from RX FIFO → writes to Register File
4. ALU reads two registers, executes operation
5. Result written back to Register File
6. Result forwarded to TX FIFO
7. UART TX drains TX FIFO → sends result back to host serially
```

---

## Project Status

| Component | RTL Design | Simulation | Synthesis | FPGA Test |
|---|---|---|---|---|
| UART TX | ✅ Done | ⬜ Pending | ⬜ Pending | ⬜ Pending |
| UART RX | ✅ Done | ⬜ Pending | ⬜ Pending | ⬜ Pending |
| FIFO | ⬜ Pending | ⬜ Pending | ⬜ Pending | ⬜ Pending |
| Register File | ⬜ Pending | ⬜ Pending | ⬜ Pending | ⬜ Pending |
| ALU | ⬜ Pending | ⬜ Pending | ⬜ Pending | ⬜ Pending |
| Top Level | ⬜ Pending | ⬜ Pending | ⬜ Pending | ⬜ Pending |

---

## Known Issues

- **`PISO.v`** — shift logic (`frame_man >> 1`) is inside a combinational `always @(*)` block. This creates a feedback loop that won't synthesize cleanly. Needs to be moved into a clocked block.
- **`SIPO.v`** — the `if(!reset_n)` block runs outside the `case` statement but inside the same `always` block, so reset and FSM logic execute simultaneously rather than being mutually exclusive. Needs an `else` to properly guard the `case`.

---

## Target Platform

- **Clock:** 50 MHz
- **Target:** FPGA (Xilinx / Intel)
- **HDL:** Verilog

---

## Next Steps

- [ ] Fix known bugs in `PISO.v` and `SIPO.v`
- [ ] Write testbenches for all modules
- [ ] Simulate full system in ModelSim / Vivado
- [ ] Design and integrate FIFO module
- [ ] Design and integrate Register File
- [ ] Design and integrate ALU
- [ ] Write top-level integration module
- [ ] Synthesize and check timing / resource utilization
- [ ] Deploy to FPGA and test with a real serial terminal

---

## License

MIT License — feel free to use, modify, and build on this.
