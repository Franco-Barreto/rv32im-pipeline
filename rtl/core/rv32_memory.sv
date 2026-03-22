// rv32_memory.sv — Memory Stage (MEM)
// Fourth stage of the 5-stage pipeline.  Entirely combinational — no clock.
//
// Two jobs:
//   STORES → align the register data onto the correct byte lanes of the
//            32-bit data bus and assert the matching byte-enable bits.
//   LOADS  → pick the addressed byte/halfword out of the 32-bit word that
//            memory returns, then sign- or zero-extend it to 32 bits.
//
// The ALU result computed in Execute doubles as the memory address here
// (base + offset was already added by the ALU for OP_LOAD / OP_STORE).
//
// Everything this stage produces is bundled into mem_wb_out and latched
// into the MEM/WB pipeline register on the next clock edge by pipeline_top.

module rv32_memory
  import rv32_types::*;  // Pulls shared enums (mem_width_t) and structs
(
  input  ex_mem_reg_t  ex_mem_in,   // Comes from the EX/MEM pipeline register — carries ALU result, store data, control signals, etc.

  // Data memory interface — directly drives the data RAM (or D-cache in the SoC path)
  output logic [31:0]  dmem_addr,   // Address to read/write.  Always the ALU result (base + imm computed in Execute).
  output logic [31:0]  dmem_wdata,  // Write data, shifted into the correct byte lanes for SB/SH/SW.
  output logic         dmem_we,     // Write-enable: high for one cycle on a valid store.  Gated by ex_mem_in.valid to prevent bubble-writes.
  output logic [3:0]   dmem_be,     // Byte enables — one bit per byte lane.  Memory only overwrites lanes where the bit is 1.
  input  logic [31:0]  dmem_rdata,  // Read data returning from memory — always a full 32-bit word, even for LB/LH.

  // Output to MEM/WB pipeline register — everything writeback needs
  output mem_wb_reg_t  mem_wb_out
);

  // ============================================================
  // Address and write-enable
  // ============================================================
  // The ALU already computed (rs1 + immediate) for loads/stores,
  // so the result IS the effective memory address.
  assign dmem_addr = ex_mem_in.alu_result;

  // Only assert write-enable when this is genuinely a store AND the
  // instruction is valid (not a flushed bubble travelling through the pipe).
  assign dmem_we   = ex_mem_in.ctrl.mem_write && ex_mem_in.valid;

  // ============================================================
  // Store data alignment and byte enables
  // ============================================================
  // RISC-V memory is byte-addressable but the data bus is 32 bits wide.
  // For sub-word stores (SB, SH) we must:
  //   1. Shift the low byte(s) of rs2 into whichever lane the address selects.
  //   2. Assert only the byte-enable bits for those lanes.
  // This way the other bytes in the word are left untouched by memory.
  //
  // addr[1:0] selects the byte lane for SB:
  //   00 → byte 0 (bits  7:0),  BE = 0001
  //   01 → byte 1 (bits 15:8),  BE = 0010
  //   10 → byte 2 (bits 23:16), BE = 0100
  //   11 → byte 3 (bits 31:24), BE = 1000
  //
  // addr[1] selects the halfword lane for SH:
  //   0  → lower half (bits 15:0),  BE = 0011
  //   1  → upper half (bits 31:16), BE = 1100
  //
  // SW always writes all four bytes, BE = 1111.

  always_comb begin
    dmem_wdata = 32'b0;     // Default: no data driven (all zeros on unused lanes)
    dmem_be    = 4'b0000;   // Default: no bytes enabled

    if (ex_mem_in.ctrl.mem_write) begin
      case (ex_mem_in.ctrl.mem_width)

        // ---- SB (store byte) ----
        // MEM_BYTE_U is included because funct3 encodes the width the same
        // way for both loads and stores; for stores only the low bits matter.
        MEM_BYTE, MEM_BYTE_U: begin
          case (ex_mem_in.alu_result[1:0])                          // Which byte lane?
            2'b00: begin dmem_be = 4'b0001; dmem_wdata[7:0]   = ex_mem_in.rs2_data[7:0]; end  // Lane 0
            2'b01: begin dmem_be = 4'b0010; dmem_wdata[15:8]  = ex_mem_in.rs2_data[7:0]; end  // Lane 1 — same source byte, shifted up
            2'b10: begin dmem_be = 4'b0100; dmem_wdata[23:16] = ex_mem_in.rs2_data[7:0]; end  // Lane 2
            2'b11: begin dmem_be = 4'b1000; dmem_wdata[31:24] = ex_mem_in.rs2_data[7:0]; end  // Lane 3
          endcase
        end

        // ---- SH (store halfword) ----
        MEM_HALF, MEM_HALF_U: begin
          case (ex_mem_in.alu_result[1])                            // Which halfword lane?
            1'b0: begin dmem_be = 4'b0011; dmem_wdata[15:0]  = ex_mem_in.rs2_data[15:0]; end  // Lower half
            1'b1: begin dmem_be = 4'b1100; dmem_wdata[31:16] = ex_mem_in.rs2_data[15:0]; end  // Upper half — same source halfword, shifted up
          endcase
        end

        // ---- SW (store word) ----
        MEM_WORD: begin
          dmem_be    = 4'b1111;             // All four bytes written
          dmem_wdata = ex_mem_in.rs2_data;  // Whole 32-bit register value goes straight through
        end

        default: begin
          dmem_be    = 4'b0000;   // Safety: unknown width → write nothing
          dmem_wdata = 32'b0;
        end
      endcase
    end
  end

  // ============================================================
  // Load data extraction and sign extension
  // ============================================================
  // Memory always returns a full 32-bit word.  For sub-word loads
  // (LB, LBU, LH, LHU) we must:
  //   1. Pick the correct byte or halfword out of that word (using addr[1:0]).
  //   2. Sign-extend (LB, LH) or zero-extend (LBU, LHU) to 32 bits.
  //
  // Why sign extension matters:  loading a signed -1 byte (0xFF) must
  // produce 0xFFFFFFFF in the register, not 0x000000FF.  The RISC-V ISA
  // distinguishes LB (signed) from LBU (unsigned) for exactly this reason.

  logic [31:0] load_data;   // Final 32-bit value that will reach writeback
  logic [7:0]  byte_sel;    // The one byte plucked out of the 32-bit word
  logic [15:0] half_sel;    // The one halfword plucked out of the 32-bit word

  always_comb begin

    // ---- Step 1: Byte selection (which of the 4 bytes?) ----
    // addr[1:0] is the byte offset within the 32-bit word.
    case (ex_mem_in.alu_result[1:0])
      2'b00: byte_sel = dmem_rdata[7:0];     // Byte 0 — lowest
      2'b01: byte_sel = dmem_rdata[15:8];    // Byte 1
      2'b10: byte_sel = dmem_rdata[23:16];   // Byte 2
      2'b11: byte_sel = dmem_rdata[31:24];   // Byte 3 — highest
    endcase

    // ---- Step 2: Halfword selection (which of the 2 halves?) ----
    // addr[1] picks the lower or upper 16 bits.
    // (addr[0] is assumed 0 for aligned halfword access.)
    case (ex_mem_in.alu_result[1])
      1'b0: half_sel = dmem_rdata[15:0];     // Lower halfword
      1'b1: half_sel = dmem_rdata[31:16];    // Upper halfword
    endcase

    // ---- Step 3: Extend to 32 bits based on load type ----
    // mem_width comes from the funct3 field decoded back in the Decode stage.
    case (ex_mem_in.ctrl.mem_width)
      MEM_BYTE:   load_data = {{24{byte_sel[7]}}, byte_sel};   // LB:  sign-extend bit 7 across upper 24 bits
      MEM_BYTE_U: load_data = {24'b0, byte_sel};               // LBU: zero-extend — positive values only
      MEM_HALF:   load_data = {{16{half_sel[15]}}, half_sel};   // LH:  sign-extend bit 15 across upper 16 bits
      MEM_HALF_U: load_data = {16'b0, half_sel};               // LHU: zero-extend
      MEM_WORD:   load_data = dmem_rdata;                       // LW:  full 32-bit word, no extension needed
      default:    load_data = dmem_rdata;                       // Fallback: treat as full word
    endcase
  end

  // ============================================================
  // Output assembly — pack everything writeback needs into mem_wb_out
  // ============================================================
  // Writeback will choose between alu_result and mem_data using the
  // mem_to_reg control signal (0 = ALU path, 1 = load path).
  // Both are forwarded so writeback can pick at the last moment.

  always_comb begin
    mem_wb_out.pc_plus4   = ex_mem_in.pc_plus4;    // Passed through for JAL/JALR — the return address (PC+4) was saved back in Fetch
    mem_wb_out.alu_result = ex_mem_in.alu_result;   // The ALU/address result — used by all non-load instructions
    mem_wb_out.mem_data   = load_data;              // The sign/zero-extended load result — used only when mem_to_reg = 1
    mem_wb_out.rd_addr    = ex_mem_in.rd_addr;      // Destination register number — tells writeback WHERE to write
    mem_wb_out.ctrl       = ex_mem_in.ctrl;         // Control signals pass through unchanged — writeback needs reg_write, mem_to_reg, valid
    mem_wb_out.valid      = ex_mem_in.valid;        // Valid bit — if 0 this is a bubble and writeback must not write to the register file
  end

endmodule
