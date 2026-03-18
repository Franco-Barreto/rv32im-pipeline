module rv32_fetch 
  import rv32_types::*; //Pulls the shared package
(
  input  logic        clk,	//As stated in the last file, heartbeat of the CPU
  input  logic        rst_n,

  input  logic        stall,        // These functions are from the hazard unit. Stall means a load-use hazard detected and to hold everything for a cycle.
  input  logic        flush,        // Flush refers to when a bad instruction is fetched, and we get rid of it.

  input  logic        branch_taken, // Execute stage. When ex resolved a branch or jump and discovers pipeline on the wrong path, it asserts a branch_taken
  input  logic [31:0] branch_target,// The correct address is then put on branch_target

  output logic [31:0] imem_addr,    // Goes out to instruction memory
  input  logic [31:0] imem_data,    // comes back with the 32 bit instruction at the address

  output if_id_reg_t  if_id_out	    // The struct that carries everything decode needs: PC, PC+4, instruction word and valid bit
);

  // Program Counter
  logic [31:0] pc_reg;
  logic [31:0] pc_next;

  always_comb begin		// Priority MUX, the order of the if/else if/else chain matters; Purely combinational, no clock or memory.
    if (branch_taken) begin	// First priority, if execute says go to X, go to X regardless of active stall or other conditions.
      pc_next = branch_target;
    end else if (stall) begin	//Second priority, if hazard unit detects a load-use dependency, fetch holds PC in place
      pc_next = pc_reg;         // hold current PC again next cycle
    end else begin
      pc_next = pc_reg + 32'd4;  // normal: advance to next instruction
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin //Sequential logic, having memory and updates only on clock edges. Only a rising clock or it dropping triggers changes.
    if (!rst_n) begin
      pc_reg <= 32'h0000_0000;   // reset vector, first instruction address fetched. Points to a bootloader on a real SoC
    end else begin
      pc_reg <= pc_next;	 // During normal operation, latches wherever mux decides. <= is a non-blocking assignment, preventing race conditions
    end
  end

  assign imem_addr = pc_reg;	// Continuous assignment: instruction memory address is always whatever the PC holds

  always_comb begin
    if (flush || branch_taken) begin		// Occurs when flush or branch_taken is high, and injects a bubble.
      if_id_out.pc          = 32'b0;		
      if_id_out.pc_plus4    = 32'b0;		
      if_id_out.instruction = 32'h0000_0013;	//The instruction will become 32'h0000_0013, encoding addi x0, x0, 0. 0 is added to the 0 register and writes back to the zero register, the valid bit goes to 1'b0
      if_id_out.valid       = 1'b0;		// Tells decode to ignore, as it's a bubble
    end else begin				// The normal path sends four things downstream
      if_id_out.pc          = pc_reg;		// Used so the decode stage knows where the instruction is from
      if_id_out.pc_plus4    = pc_reg + 32'd4;	// JAL and JALR need to save the return address. Addtionally, RISC-V instructions are 4 bits wide, hence the next instruction is at PC+4
      if_id_out.instruction = imem_data;	// Raw 32-bit instruction word that decode will open to extract opcodes, register addresses and immediates.
      if_id_out.valid       = 1'b1;		// Tells downstream stages the instruction is real and to process
    end
  end

endmodule
