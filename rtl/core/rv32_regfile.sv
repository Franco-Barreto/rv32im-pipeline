module rv32_regfile (
//clock and reset are the heartbeat of the CPU.
// Anytime there is a rising edge, an action will happen, and the rst_n is reset, triggered when the reset button is pressed, zeroing all registers.
  input  logic        clk,
  input  logic        rst_n,

// both x1 and x2 are read in the same cycle, and as they are on different ports, they are individual reads happening parallely.
  input  logic [4:0]  rs1_addr,  //asks for the value in register 1
  output logic [31:0] rs1_data,  //responds with its value

  input  logic [4:0]  rs2_addr,  //same thing just for register 2
  output logic [31:0] rs2_data,

//One port for writing, it can say write 42 into register x1, by setting wr_en = 1, wr_addr = 5'd1, wr_data = 32'd42.
// Only one port is required as only one instruction writes back in a single issue pipeline. Wider machines can have more ports, but they are more expensive and resource consuming
  input  logic        wr_en,
  input  logic [4:0]  wr_addr,
  input  logic [31:0] wr_data
);

  // 32 registers, each 32 bits wide
  logic [31:0] registers [0:31];

  always_ff @(posedge clk or negedge rst_n) begin //always_ff describes flip flop behaviour. posedge or negedge refer to executing on rising edge or when reset goes low.
    if (!rst_n) begin
      // Reset all registers to 0
      // Synthesis tools will optimize this into a reset signal on the register file
      for (int i = 0; i < 32; i++) begin //looks like a for loop, but actually is 32 parallel reset signals
        registers[i] <= 32'b0; //<= is a non-blocking assignment, and models how all FF work: they sample their inputs all together at clock edge and update all at once. using = 
//        			(blocking) will make the process sequential, resulting in different hardware behaviour
      end
    end else if (wr_en && wr_addr != 5'b0) begin //on a normal clock edge if a write enable is on AND destination isn't x0, store value. This is how x0 stays at zero. If an 
//						   instruction tries to change it (which is legal but doesn't actually work from what I have read), it will ignore the request   
      registers[wr_addr] <= wr_data;
    end
  end

  // If we're reading the same register being written this cycle,
  // return the new value being written (not the stale stored value).
  // This is a common design choice that reduces forwarding complexity.
  always_comb begin //purely combinational logic
    if (rs1_addr == 5'b0) begin
      rs1_data = 32'b0;                     // x0 is always 0, notice blocking is used here
    end else if (wr_en && rs1_addr == wr_addr) begin
      rs1_data = wr_data;                   // write-through forward, without it, if there is a value in register[1] being written at the clock edge, it might not be read as the
//					       FF hasn't updated, so always_comb checks if someone is writing and bypasses te register array, to output directly.
    end else begin
      rs1_data = registers[rs1_addr];
    end

    // Read port 2
    if (rs2_addr == 5'b0) begin
      rs2_data = 32'b0;
    end else if (wr_en && rs2_addr == wr_addr) begin
      rs2_data = wr_data;			//identical logic just for rs2_addr/rs2_datait
    end else begin
      rs2_data = registers[rs2_addr];
    end
  end

endmodule
