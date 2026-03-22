module rv32_memory
  import rv32_types::*;
(
  input  ex_mem_reg_t  ex_mem_in,

  // Data memory interface
  output logic [31:0]  dmem_addr,
  output logic [31:0]  dmem_wdata,
  output logic         dmem_we,
  output logic [3:0]   dmem_be,
  input  logic [31:0]  dmem_rdata,

  // Output to MEM/WB register
  output mem_wb_reg_t  mem_wb_out
);

  assign dmem_addr = ex_mem_in.alu_result;
  assign dmem_we   = ex_mem_in.ctrl.mem_write && ex_mem_in.valid;

  // Store data alignment and byte enables
  always_comb begin
    dmem_wdata = 32'b0;
    dmem_be    = 4'b0000;

    if (ex_mem_in.ctrl.mem_write) begin
      case (ex_mem_in.ctrl.mem_width)
        MEM_BYTE, MEM_BYTE_U: begin
          case (ex_mem_in.alu_result[1:0])
            2'b00: begin dmem_be = 4'b0001; dmem_wdata[7:0]   = ex_mem_in.rs2_data[7:0]; end
            2'b01: begin dmem_be = 4'b0010; dmem_wdata[15:8]  = ex_mem_in.rs2_data[7:0]; end
            2'b10: begin dmem_be = 4'b0100; dmem_wdata[23:16] = ex_mem_in.rs2_data[7:0]; end
            2'b11: begin dmem_be = 4'b1000; dmem_wdata[31:24] = ex_mem_in.rs2_data[7:0]; end
          endcase
        end
        MEM_HALF, MEM_HALF_U: begin
          case (ex_mem_in.alu_result[1])
            1'b0: begin dmem_be = 4'b0011; dmem_wdata[15:0]  = ex_mem_in.rs2_data[15:0]; end
            1'b1: begin dmem_be = 4'b1100; dmem_wdata[31:16] = ex_mem_in.rs2_data[15:0]; end
          endcase
        end
        MEM_WORD: begin
          dmem_be    = 4'b1111;
          dmem_wdata = ex_mem_in.rs2_data;
        end
        default: begin
          dmem_be    = 4'b0000;
          dmem_wdata = 32'b0;
        end
      endcase
    end
  end

  // Load data extraction and sign extension
  logic [31:0] load_data;
  logic [7:0]  byte_sel;
  logic [15:0] half_sel;

  always_comb begin
    // Byte selection
    case (ex_mem_in.alu_result[1:0])
      2'b00: byte_sel = dmem_rdata[7:0];
      2'b01: byte_sel = dmem_rdata[15:8];
      2'b10: byte_sel = dmem_rdata[23:16];
      2'b11: byte_sel = dmem_rdata[31:24];
    endcase

    // Halfword selection
    case (ex_mem_in.alu_result[1])
      1'b0: half_sel = dmem_rdata[15:0];
      1'b1: half_sel = dmem_rdata[31:16];
    endcase

    // Sign/zero extension
    case (ex_mem_in.ctrl.mem_width)
      MEM_BYTE:   load_data = {{24{byte_sel[7]}}, byte_sel};
      MEM_BYTE_U: load_data = {24'b0, byte_sel};
      MEM_HALF:   load_data = {{16{half_sel[15]}}, half_sel};
      MEM_HALF_U: load_data = {16'b0, half_sel};
      MEM_WORD:   load_data = dmem_rdata;
      default:    load_data = dmem_rdata;
    endcase
  end

  // Output to MEM/WB register
  always_comb begin
    mem_wb_out.pc_plus4   = ex_mem_in.pc_plus4;
    mem_wb_out.alu_result = ex_mem_in.alu_result;
    mem_wb_out.mem_data   = load_data;
    mem_wb_out.rd_addr    = ex_mem_in.rd_addr;
    mem_wb_out.ctrl       = ex_mem_in.ctrl;
    mem_wb_out.valid      = ex_mem_in.valid;
  end

endmodule
