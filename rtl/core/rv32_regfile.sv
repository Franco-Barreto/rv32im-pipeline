// rv32_regfile.sv — 32x32-bit Register File
// Two combinational read ports (for rs1 and rs2 in decode stage).
// One synchronous write port (from writeback stage).
// Register x0 is hardwired to zero per RISC-V spec.
//
// Read-during-write behavior: if the writeback stage writes to the same
// register that decode is reading, the NEW value is forwarded. This avoids
// a one-cycle stale read and simplifies the hazard unit.

module rv32_regfile (
  input  logic        clk,
  input  logic        rst_n,

  // Read port 1 (rs1)
  input  logic [4:0]  rs1_addr,
  output logic [31:0] rs1_data,

  // Read port 2 (rs2)
  input  logic [4:0]  rs2_addr,
  output logic [31:0] rs2_data,

  // Write port (from writeback stage)
  input  logic        wr_en,
  input  logic [4:0]  wr_addr,
  input  logic [31:0] wr_data
);

  // 32 registers, each 32 bits wide
  logic [31:0] registers [0:31];

  // Synchronous write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all registers to 0
      // Synthesis tools will optimize this into a reset signal on the register file
      for (int i = 0; i < 32; i++) begin
        registers[i] <= 32'b0;
      end
    end else if (wr_en && wr_addr != 5'b0) begin
      // Write to any register except x0
      registers[wr_addr] <= wr_data;
    end
  end

  // Combinational read with write-through forwarding
  // If we're reading the same register being written this cycle,
  // return the new value being written (not the stale stored value).
  // This is a common design choice that reduces forwarding complexity.
  always_comb begin
    // Read port 1
    if (rs1_addr == 5'b0) begin
      rs1_data = 32'b0;                     // x0 is always 0
    end else if (wr_en && rs1_addr == wr_addr) begin
      rs1_data = wr_data;                   // write-through forward
    end else begin
      rs1_data = registers[rs1_addr];
    end

    // Read port 2
    if (rs2_addr == 5'b0) begin
      rs2_data = 32'b0;
    end else if (wr_en && rs2_addr == wr_addr) begin
      rs2_data = wr_data;
    end else begin
      rs2_data = registers[rs2_addr];
    end
  end

endmodule
