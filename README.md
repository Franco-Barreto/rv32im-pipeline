# RV32IM Pipelined Processor

5-stage pipelined RV32IM processor core in SystemVerilog, targeting the Xilinx Zynq-7020 FPGA (PYNQ Z2).

## Architecture

```
                         ┌──────────────────────────────────────────────────────┐
                         │                  Hazard Unit                         │
                         │          (forwarding / stall / flush)                │
                         └────┬─────────┬──────────┬──────────┬────────────────┘
                              │         │          │          │
              ┌───────┐  ┌───┴───┐  ┌──┴────┐  ┌─┴──────┐  ┌┴─────────┐
  PC -------->│ FETCH │─>│DECODE │─>│EXECUTE│─>│ MEMORY │─>│WRITEBACK │
              │       │  │       │  │       │  │        │  │          │
              │ I$    │  │ RegF  │  │ ALU   │  │ D$     │  │ WB Mux   │
              │ GHR   │  │ ImmGen│  │ BrCmp │  │ LD/ST  │  │          │
              │ PHT   │  │ Ctrl  │  │ Mul/Div│ │        │  │          │
              └───────┘  └───────┘  └───────┘  └────────┘  └──────────┘
                  │                                              │
                  └──────────────────────────────────────────────┘
                                (writeback → fetch/decode)

         ┌──────────────────── AXI4-Lite Bus ────────────────────┐
         │              │              │              │           │
    ┌────┴────┐   ┌─────┴────┐   ┌────┴────┐   ┌────┴────┐     ...
    │  SRAM   │   │   UART   │   │  GPIO   │   │  Timer  │
    │         │   │  8N1/115k│   │  LEDs   │   │mtime/cmp│
    └─────────┘   └──────────┘   └─────────┘   └─────────┘
```

## Features

### Core
- [x] Project structure and type definitions
- [ ] 5-stage pipeline (IF → ID → EX → MEM → WB)
- [ ] RV32I base integer instruction set
- [ ] M extension (MUL/DIV/REM, mapped to DSP48)
- [ ] Data hazard detection with full forwarding (EX→EX, MEM→EX)
- [ ] Load-use hazard stall logic
- [ ] Control hazard flush

### Branch Prediction
- [ ] Static predict-not-taken (baseline)
- [ ] Gshare predictor (GHR ⊕ PC indexing into 2-bit saturating counter PHT)

### Cache
- [ ] L1 instruction cache (4 KB, direct-mapped, 32B lines)
- [ ] L1 data cache (4 KB, direct-mapped, 32B lines, write-through)

### SoC
- [ ] AXI4-Lite interconnect (1 master, 4 slaves)
- [ ] UART transmitter (8N1, 115200 baud)
- [ ] GPIO (memory-mapped LED control)
- [ ] Timer (RISC-V mtime/mtimecmp)

### Verification
- [ ] Unit testbenches per pipeline stage
- [ ] Integration tests (fibonacci, loop sum)
- [ ] RISC-V architectural compliance tests (`riscv-arch-test`)

## Project Structure

```
rtl/
├── core/
│   ├── rv32_fetch.sv
│   ├── rv32_decode.sv
│   ├── rv32_execute.sv
│   ├── rv32_memory.sv
│   ├── rv32_writeback.sv
│   ├── rv32_regfile.sv
│   ├── rv32_hazard_unit.sv
│   └── rv32_pipeline_top.sv
├── soc/
│   ├── axi_interconnect.sv
│   ├── uart.sv
│   └── gpio.sv
└── pkg/
    └── rv32_types.sv

tb/
├── rv32_tb.sv
└── test_programs/
```

## Target Platform

| | |
|---|---|
| **Board** | PYNQ Z2 |
| **FPGA** | Xilinx Zynq XC7Z020-1CLG400C |
| **LUTs** | 53,200 |
| **DSP48** | 220 |
| **BRAM** | 140 (36 Kb each) |

## Results

*Testing in progress — results will be added as each milestone is completed.*

| Metric | Target | Actual |
|---|---|---|
| Fmax | ≥ 50 MHz | — |
| RV32I compliance | 100% pass | — |
| RV32M compliance | 100% pass | — |
| Branch prediction accuracy (loop benchmark) | > 90% | — |
| CPI (coremark) | — | — |

## Building

**Simulation (Verilator):**
```bash
# coming soon
```

**Synthesis (Vivado 2022.1+):**
```bash
# coming soon
```

## References

- [RISC-V ISA Specification (Volume 1)](https://riscv.org/technical/specifications/)
- [Patterson & Hennessy — Computer Organization and Design, RISC-V Edition](https://www.elsevier.com/books/computer-organization-and-design-risc-v-edition/patterson/978-0-12-812275-4)
- [RISC-V Architectural Tests](https://github.com/riscv-non-isa/riscv-arch-test)

## License

MIT
