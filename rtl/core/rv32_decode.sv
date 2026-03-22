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

  assign inst    = if_id_in.instruction;	// Just renaming so the bit slicing below isn't so long
  assign opcode  = inst[6:0];		// Bits 6:0 are always the opcode in RISC-V, tells us what family of instruction we're dealing with
  assign rd      = inst[11:7];		// Where the result goes. Stores and branches don't actually write back, but the bits are still here
  assign rs1_addr = inst[19:15];	// Goes straight out to the register file to ask for the value
  assign rs2_addr = inst[24:20];	// Same thing for the second source. For I-type instructions this field is actually part of the immediate, but we extract it anyway
  assign funct3  = inst[14:12];	// The sub-opcode, like ADD vs XOR share the same opcode but funct3 tells them apart
  assign funct7  = inst[31:25];	// Only a few instructions care about this, mainly ADD vs SUB, SRL vs SRA, and checking if it's an M-extension instruction

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

  ctrl_signals_t ctrl;	// This struct holds all the control bits that tell execute, memory, and writeback what to do with the instruction

  always_comb begin
    ctrl = '0;			// Start by zeroing everything out so any instruction that doesn't set a signal gets safe NOP behaviour. Without this,
//				   latches could be inferred or stale signals from a previous instruction could leak through
    ctrl.alu_op   = ALU_ADD;	// ADD is the safest default since loads and stores both need addition for address calculation
    ctrl.mem_width = MEM_WORD;	// Default to full 32-bit word access

    case (opcode)		// Big case statement that looks at the opcode and sets the right control signals. Each case is one instruction family
      OP_LUI: begin		// Load Upper Immediate. Just takes the upper 20 bits of the immediate and puts it in rd. The execute stage handles this
        ctrl.reg_write = 1'b1;	//   with the lui flag, it doesn't even go through the ALU
        ctrl.lui       = 1'b1;
      end

      OP_AUIPC: begin		// Add Upper Immediate to PC. Same idea as LUI but adds the immediate to the current PC instead. Used for
        ctrl.reg_write = 1'b1;	//   position-independent code and building 32-bit addresses together with ADDI
        ctrl.auipc     = 1'b1;
        ctrl.alu_op    = ALU_ADD;
      end

      OP_JAL: begin		// Jump And Link. Saves PC+4 into rd (the return address) and jumps to PC + imm_j. This is how function calls work,
        ctrl.reg_write = 1'b1;	//   rd is usually x1 (ra). Execute stage computes the target and tells fetch to redirect
        ctrl.jump      = 1'b1;
      end

      OP_JALR: begin		// Jump And Link Register. Same as JAL but the target is rs1 + immediate instead of PC + immediate, and bit 0 is
        ctrl.reg_write = 1'b1;	//   forced to 0 (the & ~1). This is how function returns work (jalr x0, 0(ra)) and indirect jumps like vtables
        ctrl.jump      = 1'b1;
        ctrl.is_jalr   = 1'b1;
        ctrl.alu_src   = 1'b1;  // needs the immediate as ALU input to compute rs1 + offset
        ctrl.alu_op    = ALU_ADD;
      end

      OP_BRANCH: begin		// All branch instructions (BEQ, BNE, BLT, etc.). Decode just raises the branch flag and passes funct3 along,
        ctrl.branch = 1'b1;	//   the execute stage does the actual comparison and decides whether to take it or not
      end

      OP_LOAD: begin		// Loads from memory (LB, LH, LW, LBU, LHU). The ALU computes the address as rs1 + immediate, memory stage reads
        ctrl.reg_write  = 1'b1;	//   the data, and writeback puts it into rd. mem_to_reg tells writeback to grab from memory output instead of ALU
        ctrl.mem_read   = 1'b1;
        ctrl.mem_to_reg = 1'b1;
        ctrl.alu_src    = 1'b1;  // address = rs1 + immediate
        ctrl.alu_op     = ALU_ADD;
        ctrl.mem_width  = mem_width_t'(funct3); // funct3 encodes byte/half/word and signed vs unsigned, cast directly to the enum
      end

      OP_STORE: begin		// Stores to memory (SB, SH, SW). Similar to loads but rs2 provides the data to write. No reg_write since stores
        ctrl.mem_write = 1'b1;	//   don't produce a result. The immediate is S-type (split across two fields) but the mux above already handled that
        ctrl.alu_src   = 1'b1;  // address = rs1 + immediate
        ctrl.alu_op    = ALU_ADD;
        ctrl.mem_width = mem_width_t'(funct3);
      end

      OP_OP_IMM: begin		// Register-immediate ALU operations (ADDI, SLTI, XORI, etc.). Same as R-type but the second operand comes from
        ctrl.reg_write = 1'b1;	//   the immediate instead of rs2. Interestingly RISC-V has no SUBI, you just use ADDI with a negative immediate
        ctrl.alu_src   = 1'b1;  // tells the ALU mux to pick the immediate
        case (funct3)		// funct3 picks which ALU operation
          3'b000: ctrl.alu_op = ALU_ADD;   // ADDI
          3'b010: ctrl.alu_op = ALU_SLT;   // SLTI
          3'b011: ctrl.alu_op = ALU_SLTU;  // SLTIU
          3'b100: ctrl.alu_op = ALU_XOR;   // XORI
          3'b110: ctrl.alu_op = ALU_OR;    // ORI
          3'b111: ctrl.alu_op = ALU_AND;   // ANDI
          3'b001: ctrl.alu_op = ALU_SLL;   // SLLI
          3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRAI vs SRLI, funct7 bit 5 is the only way to tell them apart
          default: ctrl.alu_op = ALU_ADD;
        endcase
      end

      OP_OP: begin		// Register-register ALU operations. Both operands come from the register file. This is also where the M extension
        ctrl.reg_write = 1'b1;	//   (multiply/divide) lives, distinguished by funct7 being 0000001
        ctrl.alu_src   = 1'b0;  // second operand is rs2, not an immediate

        if (funct7 == 7'b0000001) begin // M extension check. If funct7 is exactly 1, it's a multiply or divide instruction
          case (funct3)
            3'b000: ctrl.alu_op = ALU_MUL;   // MUL, lower 32 bits of result
            3'b001: ctrl.alu_op = ALU_MULH;  // MULH, upper 32 bits signed x signed
            3'b010: ctrl.alu_op = ALU_MULH;  // MULHSU, signed x unsigned. The ALU uses funct3 to tell these apart
            3'b011: ctrl.alu_op = ALU_MULH;  // MULHU, unsigned x unsigned
            3'b100: ctrl.alu_op = ALU_DIV;   // DIV, signed division
            3'b101: ctrl.alu_op = ALU_DIV;   // DIVU, unsigned division. Again ALU handles the signed/unsigned distinction
            3'b110: ctrl.alu_op = ALU_REM;   // REM, signed remainder
            3'b111: ctrl.alu_op = ALU_REM;   // REMU, unsigned remainder
            default: ctrl.alu_op = ALU_ADD;
          endcase
        end else begin		// Base integer operations, the normal R-type instructions
          case (funct3)
            3'b000: ctrl.alu_op = funct7[5] ? ALU_SUB : ALU_ADD; // ADD vs SUB, the only difference is funct7 bit 5
            3'b001: ctrl.alu_op = ALU_SLL;   // SLL
            3'b010: ctrl.alu_op = ALU_SLT;   // SLT
            3'b011: ctrl.alu_op = ALU_SLTU;  // SLTU
            3'b100: ctrl.alu_op = ALU_XOR;   // XOR
            3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRA vs SRL, same funct7 bit 5 trick
            3'b110: ctrl.alu_op = ALU_OR;    // OR
            3'b111: ctrl.alu_op = ALU_AND;   // AND
            default: ctrl.alu_op = ALU_ADD;
          endcase
        end
      end

      OP_SYSTEM: begin		// CSR instructions like CSRRW, CSRRS, etc. Not really implemented yet, just a placeholder. reg_write is off
        ctrl.reg_write = 1'b0;	//   so it doesn't accidentally corrupt a register
      end

      default: begin		// If the opcode doesn't match anything, zero everything. Acts like a NOP so the pipeline doesn't do anything weird
        ctrl = '0;
      end
    endcase
  end

  // Packing everything into the ID/EX struct that gets sent to the execute stage. This is basically just wiring, no logic involved.
  // Everything decode figured out (register values, the immediate, control signals, addresses) gets bundled into one struct so execute has it all in one place
  always_comb begin
    id_ex_out.pc        = if_id_in.pc;		// Pass PC along, execute needs it for AUIPC, JAL, and branch target calculation
    id_ex_out.pc_plus4  = if_id_in.pc_plus4;	// JAL and JALR save this as the return address into rd
    id_ex_out.rs1_data  = rs1_data;		// The actual register values that came back from the register file
    id_ex_out.rs2_data  = rs2_data;		// rs2 is also the store data for SW/SH/SB, memory stage will grab it from here
    id_ex_out.immediate = immediate;		// Whichever immediate the mux above selected based on the opcode
    id_ex_out.rs1_addr  = rs1_addr;		// The addresses are passed along too, the forwarding unit in execute needs them to detect data hazards
    id_ex_out.rs2_addr  = rs2_addr;
    id_ex_out.rd_addr   = rd;			// Destination register, writeback will need this to know where to put the result
    id_ex_out.funct3    = funct3;		// Execute and memory stages still need funct3 for things like branch comparison type and load sign extension
    id_ex_out.funct7    = funct7;		// ALU needs this for a few instructions where funct3 alone isn't enough
    id_ex_out.ctrl      = ctrl;			// All the control signals we just set up above
    id_ex_out.valid     = if_id_in.valid;	// If fetch injected a bubble, valid is 0 and execute will ignore this instruction
  end

endmodule
