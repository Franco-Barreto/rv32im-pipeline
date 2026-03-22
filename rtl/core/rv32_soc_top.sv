// rv32_soc_top.sv -- Top-Level SoC
// Wires the RV32IM pipeline through L1 caches, AXI4-Lite master,
// AXI interconnect, and all peripherals (memory, UART, GPIO, timer)

module rv32_soc_top #(
  parameter CLK_FREQ    = 125_000_000,
  parameter BAUD_RATE   = 115_200,
  parameter GPIO_WIDTH  = 4,
  parameter IMEM_INIT   = "none"   // hex file for instruction memory init
)(
  input  logic                   clk,
  input  logic                   rst_n,

  // External I/O
  output logic                   uart_tx,
  output logic [GPIO_WIDTH-1:0]  gpio_out,
  input  logic [GPIO_WIDTH-1:0]  gpio_in,
  output logic                   timer_irq
);

  // ============================================================
  // Pipeline <-> Cache signals
  // ============================================================
  logic [31:0] pipe_imem_addr, pipe_imem_data;
  logic [31:0] pipe_dmem_addr, pipe_dmem_wdata, pipe_dmem_rdata;
  logic        pipe_dmem_we;
  logic [3:0]  pipe_dmem_be;

  // Cache stall signals
  logic icache_stall, dcache_stall;
  // Combined stall fed to pipeline (active when either cache misses)
  logic cache_stall;
  assign cache_stall = icache_stall || dcache_stall;

  // ============================================================
  // CPU Pipeline
  // ============================================================
  rv32_pipeline_top pipeline (
    .clk       (clk),
    .rst_n     (rst_n),
    .imem_addr (pipe_imem_addr),
    .imem_data (pipe_imem_data),
    .dmem_addr (pipe_dmem_addr),
    .dmem_wdata(pipe_dmem_wdata),
    .dmem_we   (pipe_dmem_we),
    .dmem_be   (pipe_dmem_be),
    .dmem_rdata(pipe_dmem_rdata),
    .ext_stall    (cache_stall),
    .dmem_req     (),
    .ext_irq      (1'b0),
    .dbg_halt     (1'b0),
    .dbg_reg_addr (5'b0),
    .dbg_reg_wdata(32'b0),
    .dbg_reg_we   (1'b0),
    .dbg_reg_rdata(),
    .dbg_fetch_pc ()
  );

  // ============================================================
  // I-Cache
  // ============================================================
  logic        ic_mem_req;
  logic [31:0] ic_mem_addr;
  logic [31:0] ic_mem_rdata;
  logic        ic_mem_valid;

  rv32_icache icache (
    .clk       (clk),
    .rst_n     (rst_n),
    .cpu_addr  (pipe_imem_addr),
    .cpu_req   (1'b1),            // fetch always requesting
    .cpu_rdata (pipe_imem_data),
    .cpu_stall (icache_stall),
    .mem_req   (ic_mem_req),
    .mem_addr  (ic_mem_addr),
    .mem_rdata (ic_mem_rdata),
    .mem_valid (ic_mem_valid)
  );

  // ============================================================
  // D-Cache
  // ============================================================
  logic        dc_mem_req, dc_mem_we;
  logic [31:0] dc_mem_addr, dc_mem_wdata, dc_mem_rdata;
  logic [3:0]  dc_mem_be;
  logic        dc_mem_valid, dc_mem_ready;

  rv32_dcache dcache (
    .clk       (clk),
    .rst_n     (rst_n),
    .cpu_addr  (pipe_dmem_addr),
    .cpu_wdata (pipe_dmem_wdata),
    .cpu_be    (pipe_dmem_be),
    .cpu_we    (pipe_dmem_we),
    .cpu_req   (pipe_dmem_we || (pipe_dmem_addr != 32'b0)), // simplified req
    .cpu_rdata (pipe_dmem_rdata),
    .cpu_stall (dcache_stall),
    .mem_req   (dc_mem_req),
    .mem_we    (dc_mem_we),
    .mem_addr  (dc_mem_addr),
    .mem_wdata (dc_mem_wdata),
    .mem_be    (dc_mem_be),
    .mem_rdata (dc_mem_rdata),
    .mem_valid (dc_mem_valid),
    .mem_ready (dc_mem_ready)
  );

  // ============================================================
  // AXI4-Lite Master (arbitrates I-Cache and D-Cache)
  // ============================================================
  logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
  logic [3:0]  m_wstrb;
  logic [1:0]  m_bresp, m_rresp;
  logic        m_awvalid, m_awready, m_wvalid, m_wready;
  logic        m_bvalid, m_bready;
  logic        m_arvalid, m_arready, m_rvalid, m_rready;

  rv32_axi_master axi_master (
    .clk            (clk),
    .rst_n          (rst_n),
    // I-Cache port
    .ic_req         (ic_mem_req),
    .ic_addr        (ic_mem_addr),
    .ic_rdata       (ic_mem_rdata),
    .ic_valid       (ic_mem_valid),
    // D-Cache port
    .dc_req         (dc_mem_req),
    .dc_we          (dc_mem_we),
    .dc_addr        (dc_mem_addr),
    .dc_wdata       (dc_mem_wdata),
    .dc_be          (dc_mem_be),
    .dc_rdata       (dc_mem_rdata),
    .dc_valid       (dc_mem_valid),
    .dc_ready       (dc_mem_ready),
    // AXI4-Lite master
    .m_axi_awaddr   (m_awaddr),
    .m_axi_awvalid  (m_awvalid),
    .m_axi_awready  (m_awready),
    .m_axi_awprot   (),
    .m_axi_wdata    (m_wdata),
    .m_axi_wstrb    (m_wstrb),
    .m_axi_wvalid   (m_wvalid),
    .m_axi_wready   (m_wready),
    .m_axi_bresp    (m_bresp),
    .m_axi_bvalid   (m_bvalid),
    .m_axi_bready   (m_bready),
    .m_axi_araddr   (m_araddr),
    .m_axi_arvalid  (m_arvalid),
    .m_axi_arready  (m_arready),
    .m_axi_arprot   (),
    .m_axi_rdata    (m_rdata),
    .m_axi_rresp    (m_rresp),
    .m_axi_rvalid   (m_rvalid),
    .m_axi_rready   (m_rready)
  );

  // ============================================================
  // AXI Interconnect (1 master -> 4 slaves)
  // ============================================================
  // Slave 0: Memory
  logic [31:0] s0_awaddr, s0_wdata, s0_araddr, s0_rdata;
  logic [3:0]  s0_wstrb;
  logic [1:0]  s0_bresp, s0_rresp;
  logic        s0_awvalid, s0_awready, s0_wvalid, s0_wready;
  logic        s0_bvalid, s0_bready;
  logic        s0_arvalid, s0_arready, s0_rvalid, s0_rready;

  // Slave 1: UART
  logic [31:0] s1_awaddr, s1_wdata, s1_araddr, s1_rdata;
  logic [3:0]  s1_wstrb;
  logic [1:0]  s1_bresp, s1_rresp;
  logic        s1_awvalid, s1_awready, s1_wvalid, s1_wready;
  logic        s1_bvalid, s1_bready;
  logic        s1_arvalid, s1_arready, s1_rvalid, s1_rready;

  // Slave 2: GPIO
  logic [31:0] s2_awaddr, s2_wdata, s2_araddr, s2_rdata;
  logic [3:0]  s2_wstrb;
  logic [1:0]  s2_bresp, s2_rresp;
  logic        s2_awvalid, s2_awready, s2_wvalid, s2_wready;
  logic        s2_bvalid, s2_bready;
  logic        s2_arvalid, s2_arready, s2_rvalid, s2_rready;

  // Slave 3: Timer
  logic [31:0] s3_awaddr, s3_wdata, s3_araddr, s3_rdata;
  logic [3:0]  s3_wstrb;
  logic [1:0]  s3_bresp, s3_rresp;
  logic        s3_awvalid, s3_awready, s3_wvalid, s3_wready;
  logic        s3_bvalid, s3_bready;
  logic        s3_arvalid, s3_arready, s3_rvalid, s3_rready;

  rv32_axi_interconnect axi_xbar (
    .clk            (clk),
    .rst_n          (rst_n),
    // Master port (from AXI master)
    .s_axi_awaddr   (m_awaddr),  .s_axi_awvalid  (m_awvalid), .s_axi_awready  (m_awready),
    .s_axi_wdata    (m_wdata),   .s_axi_wstrb    (m_wstrb),
    .s_axi_wvalid   (m_wvalid),  .s_axi_wready   (m_wready),
    .s_axi_bresp    (m_bresp),   .s_axi_bvalid   (m_bvalid),  .s_axi_bready   (m_bready),
    .s_axi_araddr   (m_araddr),  .s_axi_arvalid  (m_arvalid), .s_axi_arready  (m_arready),
    .s_axi_rdata    (m_rdata),   .s_axi_rresp    (m_rresp),
    .s_axi_rvalid   (m_rvalid),  .s_axi_rready   (m_rready),
    // Slave 0: Memory
    .m0_axi_awaddr  (s0_awaddr), .m0_axi_awvalid (s0_awvalid),.m0_axi_awready (s0_awready),
    .m0_axi_wdata   (s0_wdata),  .m0_axi_wstrb   (s0_wstrb),
    .m0_axi_wvalid  (s0_wvalid), .m0_axi_wready  (s0_wready),
    .m0_axi_bresp   (s0_bresp),  .m0_axi_bvalid  (s0_bvalid), .m0_axi_bready  (s0_bready),
    .m0_axi_araddr  (s0_araddr), .m0_axi_arvalid (s0_arvalid),.m0_axi_arready (s0_arready),
    .m0_axi_rdata   (s0_rdata),  .m0_axi_rresp   (s0_rresp),
    .m0_axi_rvalid  (s0_rvalid), .m0_axi_rready  (s0_rready),
    // Slave 1: UART
    .m1_axi_awaddr  (s1_awaddr), .m1_axi_awvalid (s1_awvalid),.m1_axi_awready (s1_awready),
    .m1_axi_wdata   (s1_wdata),  .m1_axi_wstrb   (s1_wstrb),
    .m1_axi_wvalid  (s1_wvalid), .m1_axi_wready  (s1_wready),
    .m1_axi_bresp   (s1_bresp),  .m1_axi_bvalid  (s1_bvalid), .m1_axi_bready  (s1_bready),
    .m1_axi_araddr  (s1_araddr), .m1_axi_arvalid (s1_arvalid),.m1_axi_arready (s1_arready),
    .m1_axi_rdata   (s1_rdata),  .m1_axi_rresp   (s1_rresp),
    .m1_axi_rvalid  (s1_rvalid), .m1_axi_rready  (s1_rready),
    // Slave 2: GPIO
    .m2_axi_awaddr  (s2_awaddr), .m2_axi_awvalid (s2_awvalid),.m2_axi_awready (s2_awready),
    .m2_axi_wdata   (s2_wdata),  .m2_axi_wstrb   (s2_wstrb),
    .m2_axi_wvalid  (s2_wvalid), .m2_axi_wready  (s2_wready),
    .m2_axi_bresp   (s2_bresp),  .m2_axi_bvalid  (s2_bvalid), .m2_axi_bready  (s2_bready),
    .m2_axi_araddr  (s2_araddr), .m2_axi_arvalid (s2_arvalid),.m2_axi_arready (s2_arready),
    .m2_axi_rdata   (s2_rdata),  .m2_axi_rresp   (s2_rresp),
    .m2_axi_rvalid  (s2_rvalid), .m2_axi_rready  (s2_rready),
    // Slave 3: Timer
    .m3_axi_awaddr  (s3_awaddr), .m3_axi_awvalid (s3_awvalid),.m3_axi_awready (s3_awready),
    .m3_axi_wdata   (s3_wdata),  .m3_axi_wstrb   (s3_wstrb),
    .m3_axi_wvalid  (s3_wvalid), .m3_axi_wready  (s3_wready),
    .m3_axi_bresp   (s3_bresp),  .m3_axi_bvalid  (s3_bvalid), .m3_axi_bready  (s3_bready),
    .m3_axi_araddr  (s3_araddr), .m3_axi_arvalid (s3_arvalid),.m3_axi_arready (s3_arready),
    .m3_axi_rdata   (s3_rdata),  .m3_axi_rresp   (s3_rresp),
    .m3_axi_rvalid  (s3_rvalid), .m3_axi_rready  (s3_rready)
  );

  // ============================================================
  // Slave 0: AXI BRAM Memory Controller
  // ============================================================
  // Unified memory for instructions (0x0000_0000) and data (0x0001_0000)
  // 128KB = 32K words
  logic [31:0] mem_bram [0:32767];

  initial begin
    for (int i = 0; i < 32768; i++) mem_bram[i] = 32'h00000013; // NOP
    if (IMEM_INIT != "none")
      $readmemh(IMEM_INIT, mem_bram);
  end

  // AXI BRAM slave -- single-cycle read/write
  logic s0_ar_done;
  logic [31:0] s0_rd_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0_ar_done <= 1'b0;
      s0_rd_data <= 32'b0;
    end else begin
      if (s0_rvalid && s0_rready)
        s0_ar_done <= 1'b0;
      if (s0_arvalid && s0_arready) begin
        s0_ar_done <= 1'b1;
        s0_rd_data <= mem_bram[s0_araddr[16:2]];
      end
    end
  end

  assign s0_arready = !s0_ar_done;
  assign s0_rdata   = s0_rd_data;
  assign s0_rresp   = 2'b00;
  assign s0_rvalid  = s0_ar_done;

  // Write channel
  logic s0_aw_done, s0_w_done;
  logic [31:0] s0_wr_addr_reg, s0_wr_data_reg;
  logic [3:0]  s0_wr_strb_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0_aw_done    <= 1'b0;
      s0_w_done     <= 1'b0;
      s0_wr_addr_reg <= 32'b0;
      s0_wr_data_reg <= 32'b0;
      s0_wr_strb_reg <= 4'b0;
    end else begin
      if (s0_bvalid && s0_bready) begin
        s0_aw_done <= 1'b0;
        s0_w_done  <= 1'b0;
      end
      if (s0_awvalid && s0_awready) begin
        s0_aw_done     <= 1'b1;
        s0_wr_addr_reg <= s0_awaddr;
      end
      if (s0_wvalid && s0_wready) begin
        s0_w_done      <= 1'b1;
        s0_wr_data_reg <= s0_wdata;
        s0_wr_strb_reg <= s0_wstrb;
      end
      // Commit write
      if (s0_aw_done && s0_w_done && !(s0_bvalid && s0_bready)) begin
        if (s0_wr_strb_reg[0]) mem_bram[s0_wr_addr_reg[16:2]][7:0]   <= s0_wr_data_reg[7:0];
        if (s0_wr_strb_reg[1]) mem_bram[s0_wr_addr_reg[16:2]][15:8]  <= s0_wr_data_reg[15:8];
        if (s0_wr_strb_reg[2]) mem_bram[s0_wr_addr_reg[16:2]][23:16] <= s0_wr_data_reg[23:16];
        if (s0_wr_strb_reg[3]) mem_bram[s0_wr_addr_reg[16:2]][31:24] <= s0_wr_data_reg[31:24];
      end
    end
  end

  assign s0_awready = !s0_aw_done;
  assign s0_wready  = !s0_w_done;
  assign s0_bresp   = 2'b00;
  assign s0_bvalid  = s0_aw_done && s0_w_done;

  // ============================================================
  // Slave 1: UART
  // ============================================================
  uart_tx #(
    .CLK_FREQ  (CLK_FREQ),
    .BAUD_RATE (BAUD_RATE)
  ) uart_inst (
    .clk            (clk),
    .rst_n          (rst_n),
    .tx             (uart_tx),
    .s_axi_awaddr   (s1_awaddr), .s_axi_awvalid  (s1_awvalid), .s_axi_awready  (s1_awready),
    .s_axi_wdata    (s1_wdata),  .s_axi_wstrb    (s1_wstrb),
    .s_axi_wvalid   (s1_wvalid), .s_axi_wready   (s1_wready),
    .s_axi_bresp    (s1_bresp),  .s_axi_bvalid   (s1_bvalid),  .s_axi_bready   (s1_bready),
    .s_axi_araddr   (s1_araddr), .s_axi_arvalid  (s1_arvalid), .s_axi_arready  (s1_arready),
    .s_axi_rdata    (s1_rdata),  .s_axi_rresp    (s1_rresp),
    .s_axi_rvalid   (s1_rvalid), .s_axi_rready   (s1_rready)
  );

  // ============================================================
  // Slave 2: GPIO
  // ============================================================
  gpio #(
    .WIDTH (GPIO_WIDTH)
  ) gpio_inst (
    .clk            (clk),
    .rst_n          (rst_n),
    .gpio_out       (gpio_out),
    .gpio_in        (gpio_in),
    .s_axi_awaddr   (s2_awaddr), .s_axi_awvalid  (s2_awvalid), .s_axi_awready  (s2_awready),
    .s_axi_wdata    (s2_wdata),  .s_axi_wstrb    (s2_wstrb),
    .s_axi_wvalid   (s2_wvalid), .s_axi_wready   (s2_wready),
    .s_axi_bresp    (s2_bresp),  .s_axi_bvalid   (s2_bvalid),  .s_axi_bready   (s2_bready),
    .s_axi_araddr   (s2_araddr), .s_axi_arvalid  (s2_arvalid), .s_axi_arready  (s2_arready),
    .s_axi_rdata    (s2_rdata),  .s_axi_rresp    (s2_rresp),
    .s_axi_rvalid   (s2_rvalid), .s_axi_rready   (s2_rready)
  );

  // ============================================================
  // Slave 3: Timer
  // ============================================================
  timer timer_inst (
    .clk            (clk),
    .rst_n          (rst_n),
    .timer_irq      (timer_irq),
    .s_axi_awaddr   (s3_awaddr), .s_axi_awvalid  (s3_awvalid), .s_axi_awready  (s3_awready),
    .s_axi_wdata    (s3_wdata),  .s_axi_wstrb    (s3_wstrb),
    .s_axi_wvalid   (s3_wvalid), .s_axi_wready   (s3_wready),
    .s_axi_bresp    (s3_bresp),  .s_axi_bvalid   (s3_bvalid),  .s_axi_bready   (s3_bready),
    .s_axi_araddr   (s3_araddr), .s_axi_arvalid  (s3_arvalid), .s_axi_arready  (s3_arready),
    .s_axi_rdata    (s3_rdata),  .s_axi_rresp    (s3_rresp),
    .s_axi_rvalid   (s3_rvalid), .s_axi_rready   (s3_rready)
  );

endmodule
