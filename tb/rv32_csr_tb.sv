module rv32_csr_tb;
  import rv32_types::*;

  logic        clk;
  logic        rst_n;

  logic [31:0] imem_addr, imem_data;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic        dmem_we;
  logic [3:0]  dmem_be;

  // DUT
  rv32_pipeline_top uut (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (imem_addr),
    .imem_data  (imem_data),
    .dmem_addr  (dmem_addr),
    .dmem_wdata (dmem_wdata),
    .dmem_we    (dmem_we),
    .dmem_be    (dmem_be),
    .dmem_rdata (dmem_rdata),
    .ext_stall    (1'b0),
    .dmem_req     (),
    .ext_irq      (1'b0),
    .dbg_halt     (1'b0),
    .dbg_reg_addr (5'b0),
    .dbg_reg_wdata(32'b0),
    .dbg_reg_we   (1'b0),
    .dbg_reg_rdata(),
    .dbg_fetch_pc ()
  );

  // Instruction memory -- loads CSR test program
  logic [31:0] imem [0:1023];

  initial begin
    for (int i = 0; i < 1024; i++) imem[i] = 32'h00000013;
    $readmemh("tb/test_programs/test_csr.hex", imem);
  end

  assign imem_data = imem[imem_addr[11:2]];

  // Data memory (unused by CSR tests, but pipeline still drives it)
  logic [31:0] dmem [0:1023];

  initial begin
    for (int i = 0; i < 1024; i++) dmem[i] = 32'h0;
  end

  assign dmem_rdata = dmem[dmem_addr[11:2]];

  always_ff @(posedge clk) begin
    if (dmem_we) begin
      if (dmem_be[0]) dmem[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
      if (dmem_be[1]) dmem[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
      if (dmem_be[2]) dmem[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
      if (dmem_be[3]) dmem[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
    end
  end

  // Clock: 10ns period
  initial clk = 0;
  always #5 clk = ~clk;

  // Register access helper
  function automatic logic [31:0] reg_val(input int r);
    reg_val = uut.regfile_inst.registers[r];
  endfunction

  // Test infrastructure
  int pass_count = 0;
  int fail_count = 0;

  task check(input string name, input logic [31:0] actual, input logic [31:0] expected);
    if (actual === expected) begin
      $display("  PASS: %s = 0x%08h (expected 0x%08h)", name, actual, expected);
      pass_count++;
    end else begin
      $display("  FAIL: %s = 0x%08h (expected 0x%08h)", name, actual, expected);
      fail_count++;
    end
  endtask

  task check_range(input string name, input logic [31:0] actual,
                   input logic [31:0] lo, input logic [31:0] hi);
    if (actual >= lo && actual <= hi) begin
      $display("  PASS: %s = %0d (in range [%0d, %0d])", name, actual, lo, hi);
      pass_count++;
    end else begin
      $display("  FAIL: %s = %0d (expected range [%0d, %0d])", name, actual, lo, hi);
      fail_count++;
    end
  endtask

  initial begin
    $dumpfile("rv32_csr_tb.vcd");
    $dumpvars(0, rv32_csr_tb);

    // Reset
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    // Wait for end marker
    begin : wait_block
      int timeout;
      timeout = 0;
      while (timeout < 500) begin
        @(posedge clk);
        timeout++;
        if (reg_val(13) == 32'h000000FF) begin
          repeat (5) @(posedge clk);
          disable wait_block;
        end
      end
      $display("ERROR: Timeout -- x13 never reached 0xFF after 500 cycles");
    end

    // ============================================================
    // Test 1: Cycle counter delta
    // ============================================================
    $display("\n=== Test 1: Cycle Counter (mcycle) ===");
    check("x3  (mcycle delta)", reg_val(3), 32'd11);

    // ============================================================
    // Test 2: Instructions retired counter
    // ============================================================
    $display("\n=== Test 2: Instructions Retired (minstret) ===");
    // By the time csrrs x4 reads minstret at EX, 11 instructions have retired
    // (csrrs_x1 + 10 NOPs = 11)
    check_range("x4  (minstret)", reg_val(4), 32'd10, 32'd14);

    // ============================================================
    // Test 3: CSRRW -- write and read back
    // ============================================================
    $display("\n=== Test 3: CSRRW ===");
    check("x6  (csrrw old val)", reg_val(6), 32'd0);
    check("x7  (read back 42)",  reg_val(7), 32'd42);

    // ============================================================
    // Test 4: CSRRWI -- immediate write
    // ============================================================
    $display("\n=== Test 4: CSRRWI ===");
    check("x8  (csrrwi old=42)", reg_val(8), 32'd42);
    check("x9  (read back 15)",  reg_val(9), 32'd15);

    // ============================================================
    // Test 5: CSRRS -- set bits
    // ============================================================
    $display("\n=== Test 5: CSRRS (set bits) ===");
    check("x11 (csrrs old=0)",  reg_val(11), 32'd0);
    check("x12 (read back 3)",  reg_val(12), 32'd3);

    // ============================================================
    // Test 6: CSRRC -- clear bits
    // ============================================================
    $display("\n=== Test 6: CSRRC (clear bits) ===");
    check("x15 (csrrc old=3)",  reg_val(15), 32'd3);
    check("x16 (read back 2)",  reg_val(16), 32'd2);

    // End marker
    check("x13 (end marker)",   reg_val(13), 32'h000000FF);

    // ============================================================
    // Summary
    // ============================================================
    $display("\n========================================");
    if (fail_count == 0)
      $display("ALL %0d CSR TESTS PASSED", pass_count);
    else
      $display("FAILED: %0d/%0d tests failed", fail_count, pass_count + fail_count);
    $display("========================================\n");

    $finish;
  end

endmodule
