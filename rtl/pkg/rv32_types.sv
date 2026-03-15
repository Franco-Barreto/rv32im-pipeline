`ifndef RV32_TYPES_SV
`define RV32_TYPES_SV

package rv32_types;

  // ──────────────────────────────────────────────
  // Opcodes (inst[6:0])
  // ──────────────────────────────────────────────
  typedef enum logic [6:0] {
    OP_LUI      = 7'b0110111,
    OP_AUIPC    = 7'b0010111,
    OP_JAL      = 7'b1101111,
    OP_JALR     = 7'b1100111,
    OP_BRANCH   = 7'b1100011,
    OP_LOAD     = 7'b0000011,
    OP_STORE    = 7'b0100011,
    OP_IMM      = 7'b0010011,
    OP_REG      = 7'b0110011,
    OP_FENCE    = 7'b0001111,
    OP_SYSTEM   = 7'b1110011
  } opcode_t;

  // ──────────────────────────────────────────────
  // ALU operations
  // ──────────────────────────────────────────────
  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b0001,
    ALU_AND  = 4'b0010,
    ALU_OR   = 4'b0011,
    ALU_XOR  = 4'b0100,
    ALU_SLL  = 4'b0101,
    ALU_SRL  = 4'b0110,
    ALU_SRA  = 4'b0111,
    ALU_SLT  = 4'b1000,
    ALU_SLTU = 4'b1001,
    // M extension
    ALU_MUL    = 4'b1010,
    ALU_MULH   = 4'b1011,
    ALU_DIV    = 4'b1100,
    ALU_REM    = 4'b1101
  } alu_op_t;

  // ──────────────────────────────────────────────
  // Branch types (funct3)
  // ──────────────────────────────────────────────
  typedef enum logic [2:0] {
    BR_BEQ  = 3'b000,
    BR_BNE  = 3'b001,
    BR_BLT  = 3'b100,
    BR_BGE  = 3'b101,
    BR_BLTU = 3'b110,
    BR_BGEU = 3'b111
  } branch_t;

  // ──────────────────────────────────────────────
  // Immediate type select
  // ──────────────────────────────────────────────
  typedef enum logic [2:0] {
    IMM_I = 3'b000,
    IMM_S = 3'b001,
    IMM_B = 3'b010,
    IMM_U = 3'b011,
    IMM_J = 3'b100
  } imm_type_t;

  // ──────────────────────────────────────────────
  // Forwarding mux select
  // ──────────────────────────────────────────────
  typedef enum logic [1:0] {
    FWD_NONE   = 2'b00,   // no forwarding, use register file
    FWD_EX_MEM = 2'b01,   // forward from EX/MEM pipeline reg
    FWD_MEM_WB = 2'b10    // forward from MEM/WB pipeline reg
  } fwd_sel_t;

  // ──────────────────────────────────────────────
  // Memory access width
  // ──────────────────────────────────────────────
  typedef enum logic [1:0] {
    MEM_WORD = 2'b00,
    MEM_HALF = 2'b01,
    MEM_BYTE = 2'b10
  } mem_width_t;

  // ──────────────────────────────────────────────
  // Pipeline registers
  // ──────────────────────────────────────────────

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] instruction;
    logic        valid;
  } if_id_reg_t;

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    alu_op_t     alu_op;
    logic        alu_src;       // 0 = rs2, 1 = imm
    logic        mem_read;
    logic        mem_write;
    mem_width_t  mem_width;
    logic        mem_unsigned;  // zero-extend loaded value
    logic        reg_write;
    logic        wb_sel;        // 0 = ALU result, 1 = memory
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    branch_t     branch_type;
    logic        valid;
  } id_ex_reg_t;

  typedef struct packed {
    logic [31:0] pc_plus4;
    logic [31:0] alu_result;
    logic [31:0] rs2_data;      // store data
    logic [4:0]  rd_addr;
    logic        mem_read;
    logic        mem_write;
    mem_width_t  mem_width;
    logic        mem_unsigned;
    logic        reg_write;
    logic        wb_sel;
    logic        valid;
  } ex_mem_reg_t;

  typedef struct packed {
    logic [31:0] pc_plus4;
    logic [31:0] alu_result;
    logic [31:0] mem_data;
    logic [4:0]  rd_addr;
    logic        reg_write;
    logic        wb_sel;
    logic        valid;
  } mem_wb_reg_t;

  // ──────────────────────────────────────────────
  // Branch predictor (gshare)
  // ──────────────────────────────────────────────
  parameter int GHR_WIDTH = 8;
  parameter int PHT_DEPTH = 256;  // 2^GHR_WIDTH

  typedef logic [1:0] sat_counter_t;  // 2-bit saturating counter

endpackage

`endif
