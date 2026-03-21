// No clk or rst_n, the whole circuit is combinational, no flip-flops, no state. All work is done in zero clock cycles (combinational delay).
module rv32_decode
  import rv32_types::*;
(
  input  if_id_reg_t  if_id_in, // The strut fetch packed: PC, PC+4, 32 bit instruction and valid bit.

  output logic [4:0]  rs1_addr,	// Both go out to the register file, decode asks to give the value in 2 registers
  output logic [4:0]  rs2_addr,
  input  logic [31:0] rs1_data, // The responds here in the same cycle, the register file ports are here instead of internal as it is a shared resource, writeback connects it
  input  logic [31:0] rs2_data,

  // Output to ID/EX pipeline register
  output id_ex_reg_t  id_ex_out // Struct heading to execute stage. Carries everything: register values, devoded immediate, control signals, 
//				   source/destination register addrress and func3/7 for ALU
);
  logic [31:0] inst;
  logic [6:0]  opcode;	// Opcode is 7 bits to tell us the class of instruction
  logic [4:0]  rd;	//bits 11:7, destination register, rs1 and 2 are the source register addresses.
  logic [2:0]  funct3;	//14:12, a 3 bit subcode that disambiguates within a class
  logic [6:0]  funct7;	// 31:25, a further disambiguator (ADD vs SUB, SRL vs SRA)

  assign inst    = if_id_in.instruction;
  assign opcode  = inst[6:0];
  assign rd      = inst[11:7];
  assign rs1_addr = inst[19:15];
  assign rs2_addr = inst[24:20];
  assign funct3  = inst[14:12];
  assign funct7  = inst[31:25];

  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  logic [31:0] immediate;			///inst31 is the sign bit, every immediate form sign extends it from bit 31. 20{inst[31]} replicates it 20 times to fill upper bits

  assign imm_i = {{20{inst[31]}}, inst[31:20]};	// imm_i is the simplest just bits 31:20 sign extended, allowing us to get 12 bit signed, and used for addi x1, x2, 5 loads like lw x3, 8(x1) and jalr.

  assign imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]}; // imm_s is for stores. The immediate is split across two fields, 31:25 and 11:7 because rd doesn't exist in store instructions 
//  								and get repurposed for immediate. Same 12 bit range.

  assign imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}; // For branches. Bits are scrambled more, and theres a 1'b0 at the bottom, branch targets are 2 byte aligned, 
//  											so the bit 0 is implicitly 0, giving an extra bit of range. Branches can reach +/- 4KB from the current PC

  assign imm_u = {inst[31:12], 12'b0}; //imm_u is for LUI and AUIPC, no sign extension needed because the 20 bit immediate is placed directly into upper 20 bits, with lower 12 zeroed out. Large 
//  					 constants are made like this: LUI loads upper 20, and ADDI fills the lower 12

  assign imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}; //For JAL, bits are maximally scrambled to keep the sign but at position 31. Same 1'b0 trick as B-type for 
//  											 alignment giving a 21 bit signed offset,jal can reach +/- from the current PC

  always_comb begin
    case (opcode)
      OP_LOAD, OP_OP_IMM, OP_JALR, OP_SYSTEM: immediate = imm_i;
      OP_STORE:                                 immediate = imm_s;
      OP_BRANCH:                                immediate = imm_b;
      OP_LUI, OP_AUIPC:                        immediate = imm_u;
      OP_JAL:                                   immediate = imm_j;
      default:                                  immediate = 32'b0;
    endcase
  end					// All five immediates are computed in parallel. Mux just picks which is most relevant on the opcode. The default case cathches register instructions that 
  					// don't use an immediate, so regardless the output, it will be zeroed

  ctrl_signals_t ctrl;

  always_comb begin
    // Default: all control signals inactive (safe NOP-like behavior)
    ctrl = '0;
    ctrl.alu_op   = ALU_ADD;
    ctrl.mem_width = MEM_WORD;

    case (opcode)
      // ----- LUI: rd = immediate (upper 20 bits) -----
      OP_LUI: begin
        ctrl.reg_write = 1'b1;
        ctrl.lui       = 1'b1;
      end

      // ----- AUIPC: rd = PC + immediate -----
      OP_AUIPC: begin
        ctrl.reg_write = 1'b1;
        ctrl.auipc     = 1'b1;
        ctrl.alu_op    = ALU_ADD;
      end

      // ----- JAL: rd = PC+4, PC = PC + imm_j -----
      OP_JAL: begin
        ctrl.reg_write = 1'b1;
        ctrl.jump      = 1'b1;
      end

      // ----- JALR: rd = PC+4, PC = (rs1 + imm_i) & ~1 -----
      OP_JALR: begin
        ctrl.reg_write = 1'b1;
        ctrl.jump      = 1'b1;
        ctrl.is_jalr   = 1'b1;
        ctrl.alu_src   = 1'b1;  // use immediate
        ctrl.alu_op    = ALU_ADD;
      end

      // ----- BRANCH: compare rs1 and rs2, branch if condition met -----
      OP_BRANCH: begin
        ctrl.branch = 1'b1;
      end

      // ----- LOAD: rd = mem[rs1 + imm_i] -----
      OP_LOAD: begin
        ctrl.reg_write  = 1'b1;
        ctrl.mem_read   = 1'b1;
        ctrl.mem_to_reg = 1'b1;
        ctrl.alu_src    = 1'b1;  // address = rs1 + immediate
        ctrl.alu_op     = ALU_ADD;
        ctrl.mem_width  = mem_width_t'(funct3);
      end

      // ----- STORE: mem[rs1 + imm_s] = rs2 -----
      OP_STORE: begin
        ctrl.mem_write = 1'b1;
        ctrl.alu_src   = 1'b1;  // address = rs1 + immediate
        ctrl.alu_op    = ALU_ADD;
        ctrl.mem_width = mem_width_t'(funct3);
      end

      // ----- OP-IMM: register-immediate ALU operations -----
      OP_OP_IMM: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b1;  // second operand is immediate
        case (funct3)
          3'b000: ctrl.alu_op = ALU_ADD;   // ADDI (no SUBI in RISC-V)
          3'b010: ctrl.alu_op = ALU_SLT;   // SLTI
          3'b011: ctrl.alu_op = ALU_SLTU;  // SLTIU
          3'b100: ctrl.alu_op = ALU_XOR;   // XORI
          3'b110: ctrl.alu_op = ALU_OR;    // ORI
          3'b111: ctrl.alu_op = ALU_AND;   // ANDI
          3'b001: ctrl.alu_op = ALU_SLL;   // SLLI
          3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRAI / SRLI
          default: ctrl.alu_op = ALU_ADD;
        endcase
      end

      // ----- OP: register-register ALU operations -----
      OP_OP: begin
        ctrl.reg_write = 1'b1;
        ctrl.alu_src   = 1'b0;  // second operand is rs2

        if (funct7 == 7'b0000001) begin
          // M extension: multiply/divide
          case (funct3)
            3'b000: ctrl.alu_op = ALU_MUL;   // MUL
            3'b001: ctrl.alu_op = ALU_MULH;  // MULH
            3'b010: ctrl.alu_op = ALU_MULH;  // MULHSU (handle in ALU)
            3'b011: ctrl.alu_op = ALU_MULH;  // MULHU  (handle in ALU)
            3'b100: ctrl.alu_op = ALU_DIV;   // DIV
            3'b101: ctrl.alu_op = ALU_DIV;   // DIVU   (handle in ALU)
            3'b110: ctrl.alu_op = ALU_REM;   // REM
            3'b111: ctrl.alu_op = ALU_REM;   // REMU   (handle in ALU)
            default: ctrl.alu_op = ALU_ADD;
          endcase
        end else begin
          // Base integer operations
          case (funct3)
            3'b000: ctrl.alu_op = funct7[5] ? ALU_SUB : ALU_ADD; // ADD / SUB
            3'b001: ctrl.alu_op = ALU_SLL;   // SLL
            3'b010: ctrl.alu_op = ALU_SLT;   // SLT
            3'b011: ctrl.alu_op = ALU_SLTU;  // SLTU
            3'b100: ctrl.alu_op = ALU_XOR;   // XOR
            3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRA / SRL
            3'b110: ctrl.alu_op = ALU_OR;    // OR
            3'b111: ctrl.alu_op = ALU_AND;   // AND
            default: ctrl.alu_op = ALU_ADD;
          endcase
        end
      end

      // ----- SYSTEM: CSR instructions (basic support) -----
      OP_SYSTEM: begin
        // Placeholder — will expand when adding CSR unit
        ctrl.reg_write = 1'b0;
      end

      default: begin
        // Unknown opcode — treat as NOP
        ctrl = '0;
      end
    endcase
  end

  // ============================================================
  // ID/EX output assembly
  // ============================================================
  always_comb begin
    id_ex_out.pc        = if_id_in.pc;
    id_ex_out.pc_plus4  = if_id_in.pc_plus4;
    id_ex_out.rs1_data  = rs1_data;
    id_ex_out.rs2_data  = rs2_data;
    id_ex_out.immediate = immediate;
    id_ex_out.rs1_addr  = rs1_addr;
    id_ex_out.rs2_addr  = rs2_addr;
    id_ex_out.rd_addr   = rd;
    id_ex_out.funct3    = funct3;
    id_ex_out.funct7    = funct7;
    id_ex_out.ctrl      = ctrl;
    id_ex_out.valid     = if_id_in.valid;
  end

endmodule
