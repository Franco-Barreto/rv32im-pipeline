// rv32_dual_core_top.sv -- Dual-Core RV32IM Pipeline Top
// Instantiates two rv32_pipeline_top cores with separate instruction
// memories and a shared data memory through a round-robin bus arbiter.

module rv32_dual_core_top
  import rv32_types::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // Core 0 instruction memory (private)
  output logic [31:0] c0_imem_addr,
  input  logic [31:0] c0_imem_data,

  // Core 1 instruction memory (private)
  output logic [31:0] c1_imem_addr,
  input  logic [31:0] c1_imem_data,

  // Shared data memory (arbitrated)
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  input  logic [31:0] dmem_rdata
);

  // Core 0 data memory signals
  logic [31:0] c0_dmem_addr, c0_dmem_wdata, c0_dmem_rdata;
  logic        c0_dmem_we, c0_dmem_req;
  logic [3:0]  c0_dmem_be;
  logic        c0_stall;

  // Core 1 data memory signals
  logic [31:0] c1_dmem_addr, c1_dmem_wdata, c1_dmem_rdata;
  logic        c1_dmem_we, c1_dmem_req;
  logic [3:0]  c1_dmem_be;
  logic        c1_stall;

  // ============================================================
  // Core 0
  // ============================================================
  rv32_pipeline_top core0 (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (c0_imem_addr),
    .imem_data  (c0_imem_data),
    .dmem_addr  (c0_dmem_addr),
    .dmem_wdata (c0_dmem_wdata),
    .dmem_we    (c0_dmem_we),
    .dmem_be    (c0_dmem_be),
    .dmem_rdata (c0_dmem_rdata),
    .ext_stall    (c0_stall),
    .dmem_req     (c0_dmem_req),
    .ext_irq      (1'b0),
    .dbg_halt     (1'b0),
    .dbg_reg_addr (5'b0),
    .dbg_reg_wdata(32'b0),
    .dbg_reg_we   (1'b0),
    .dbg_reg_rdata(),
    .dbg_fetch_pc ()
  );

  // ============================================================
  // Core 1
  // ============================================================
  rv32_pipeline_top core1 (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (c1_imem_addr),
    .imem_data  (c1_imem_data),
    .dmem_addr  (c1_dmem_addr),
    .dmem_wdata (c1_dmem_wdata),
    .dmem_we    (c1_dmem_we),
    .dmem_be    (c1_dmem_be),
    .dmem_rdata (c1_dmem_rdata),
    .ext_stall    (c1_stall),
    .dmem_req     (c1_dmem_req),
    .ext_irq      (1'b0),
    .dbg_halt     (1'b0),
    .dbg_reg_addr (5'b0),
    .dbg_reg_wdata(32'b0),
    .dbg_reg_we   (1'b0),
    .dbg_reg_rdata(),
    .dbg_fetch_pc ()
  );

  // ============================================================
  // Bus Arbiter
  // ============================================================
  rv32_bus_arbiter arbiter (
    .clk          (clk),
    .rst_n        (rst_n),
    .c0_dmem_addr (c0_dmem_addr),
    .c0_dmem_wdata(c0_dmem_wdata),
    .c0_dmem_we   (c0_dmem_we),
    .c0_dmem_be   (c0_dmem_be),
    .c0_dmem_req  (c0_dmem_req),
    .c0_dmem_rdata(c0_dmem_rdata),
    .c0_stall     (c0_stall),
    .c1_dmem_addr (c1_dmem_addr),
    .c1_dmem_wdata(c1_dmem_wdata),
    .c1_dmem_we   (c1_dmem_we),
    .c1_dmem_be   (c1_dmem_be),
    .c1_dmem_req  (c1_dmem_req),
    .c1_dmem_rdata(c1_dmem_rdata),
    .c1_stall     (c1_stall),
    .dmem_addr    (dmem_addr),
    .dmem_wdata   (dmem_wdata),
    .dmem_we      (dmem_we),
    .dmem_be      (dmem_be),
    .dmem_rdata   (dmem_rdata)
  );

endmodule
