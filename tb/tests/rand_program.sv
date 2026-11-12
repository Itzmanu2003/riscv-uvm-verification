// ============================================================================
// rand_program - random instruction generators (all encodings are spec-legal)
// ----------------------------------------------------------------------------
// FIX: the previous rand_itype() produced SLLI with a random imm[11:5]
//      (e.g. 0x7F3 << 20). RV32 requires imm[11:5]==0 for SLLI, so the DUT
//      raised an illegal-instruction trap and jumped to mtvec, while the old
//      reference model treated it as a normal shift. That is why
//      riscv_mega_test ended with "22 unmatched expected" writes.
//
// The original no-argument calls  rand_program::rand_rtype() / rand_itype()
// still work; the extra arguments are optional.
// ============================================================================
class rand_program;

    // Interesting operand values (toggle / corner coverage)
    static function bit [31:0] rand_extreme_value();
        case ($urandom_range(0, 11))
            0:  return 32'h0000_0000;
            1:  return 32'hFFFF_FFFF;
            2:  return 32'h8000_0000;
            3:  return 32'h7FFF_FFFF;
            4:  return 32'hAAAA_AAAA;
            5:  return 32'h5555_5555;
            6:  return 32'h0000_0001;
            7:  return 32'h1 << $urandom_range(0, 31);        // walking one
            8:  return ~(32'h1 << $urandom_range(0, 31));     // walking zero
            default: return $urandom();
        endcase
    endfunction

    // R-type: register-register ALU + full M extension (18 ops)
    static function bit [31:0] rand_rtype(int seed_unused = 0, int unsigned rd_max = 31);
        bit [4:0]  rd, rs1, rs2;
        bit [2:0]  funct3;
        bit [6:0]  funct7;

        rd  = $urandom_range(1, rd_max);
        rs1 = $urandom_range(1, 31);  // avoid x0 as source (often 0, less interesting)
        rs2 = $urandom_range(1, 31);

        case ($urandom_range(0, 17))
            0:  begin funct3 = 3'b000; funct7 = 7'b0000000; end // ADD
            1:  begin funct3 = 3'b000; funct7 = 7'b0100000; end // SUB
            2:  begin funct3 = 3'b111; funct7 = 7'b0000000; end // AND
            3:  begin funct3 = 3'b110; funct7 = 7'b0000000; end // OR
            4:  begin funct3 = 3'b100; funct7 = 7'b0000000; end // XOR
            5:  begin funct3 = 3'b010; funct7 = 7'b0000000; end // SLT
            6:  begin funct3 = 3'b011; funct7 = 7'b0000000; end // SLTU
            7:  begin funct3 = 3'b001; funct7 = 7'b0000000; end // SLL
            8:  begin funct3 = 3'b101; funct7 = 7'b0000000; end // SRL
            9:  begin funct3 = 3'b101; funct7 = 7'b0100000; end // SRA
            10: begin funct3 = 3'b000; funct7 = 7'b0000001; end // MUL
            11: begin funct3 = 3'b001; funct7 = 7'b0000001; end // MULH
            12: begin funct3 = 3'b010; funct7 = 7'b0000001; end // MULHSU
            13: begin funct3 = 3'b011; funct7 = 7'b0000001; end // MULHU
            14: begin funct3 = 3'b100; funct7 = 7'b0000001; end // DIV
            15: begin funct3 = 3'b101; funct7 = 7'b0000001; end // DIVU
            16: begin funct3 = 3'b110; funct7 = 7'b0000001; end // REM
            default: begin funct3 = 3'b111; funct7 = 7'b0000001; end // REMU
        endcase

        return {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    endfunction

    // M-extension only
    static function bit [31:0] rand_mext(int unsigned rd_max = 31);
        bit [4:0] rd  = $urandom_range(1, rd_max);
        bit [4:0] rs1 = $urandom_range(0, 31);
        bit [4:0] rs2 = $urandom_range(0, 31);
        bit [2:0] f3  = $urandom_range(0, 7);
        return {7'b0000001, rs2, rs1, f3, rd, 7'b0110011};
    endfunction

    // I-type: register-immediate ALU (all 9 ops, full signed immediate range)
    static function bit [31:0] rand_itype(int seed_unused = 0, int unsigned rd_max = 31);
        bit [4:0]  rd, rs1;
        bit [11:0] imm;
        bit [2:0]  funct3;

        rd  = $urandom_range(1, rd_max);
        rs1 = $urandom_range(0, 31);
        imm = $urandom_range(0, 4095);            // -2048 .. +2047

        case ($urandom_range(0, 8))
            0: funct3 = 3'b000; // ADDI
            1: funct3 = 3'b111; // ANDI
            2: funct3 = 3'b110; // ORI
            3: funct3 = 3'b100; // XORI
            4: funct3 = 3'b010; // SLTI
            5: funct3 = 3'b011; // SLTIU
            6: begin funct3 = 3'b001; imm = {7'b0000000, imm[4:0]}; end // SLLI (shamt only!)
            7: begin funct3 = 3'b101; imm = {7'b0000000, imm[4:0]}; end // SRLI
            default: begin funct3 = 3'b101; imm = {7'b0100000, imm[4:0]}; end // SRAI
        endcase

        return {imm, rs1, funct3, rd, 7'b0010011};
    endfunction

    // Load relative to base_reg; offset in [-256, +252], naturally aligned
    // unless a misaligned access is requested (=> misaligned-load trap).
    static function bit [31:0] rand_load(bit [4:0] base_reg, int unsigned rd_max = 31,
                                         bit misaligned = 0);
        bit [4:0]  rd  = $urandom_range(1, rd_max);
        bit [2:0]  f3;
        int        off = int'($urandom_range(0, 508)) - 256;
        bit [11:0] imm;
        case ($urandom_range(0, 4))
            0: f3 = 3'b000;  // LB
            1: f3 = 3'b001;  // LH
            2: f3 = 3'b010;  // LW
            3: f3 = 3'b100;  // LBU
            default: f3 = 3'b101;  // LHU
        endcase
        if (misaligned) begin
            if (f3[1:0] == 2'b00) f3 = 3'b010;          // bytes are never misaligned -> use LW
            off = (off & ~3) + ((f3[1:0] == 2'b01) ? 1 : $urandom_range(1, 3));
        end else begin
            if (f3[1:0] == 2'b01) off = off & ~1;
            if (f3[1:0] == 2'b10) off = off & ~3;
        end
        imm = off[11:0];
        return {imm, base_reg, f3, rd, 7'b0000011};
    endfunction

    static function bit [31:0] rand_store(bit [4:0] base_reg, bit misaligned = 0);
        bit [4:0]  rs2 = $urandom_range(0, 31);
        bit [2:0]  f3  = $urandom_range(0, 2);         // SB SH SW
        int        off = int'($urandom_range(0, 508)) - 256;
        bit [11:0] imm;
        if (misaligned) begin
            if (f3 == 3'b000) f3 = 3'b010;
            off = (off & ~3) + ((f3 == 3'b001) ? 1 : $urandom_range(1, 3));
        end else begin
            if (f3 == 3'b001) off = off & ~1;
            if (f3 == 3'b010) off = off & ~3;
        end
        imm = off[11:0];
        return {imm[11:5], rs2, base_reg, f3, imm[4:0], 7'b0100011};
    endfunction

endclass
