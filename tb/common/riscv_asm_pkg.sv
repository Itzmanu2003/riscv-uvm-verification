// ============================================================================
// riscv_asm_pkg
// ----------------------------------------------------------------------------
// Tiny RV32IM + Zicsr assembler used by the directed / random tests, plus a
// "program image" container (riscv_program) that tests fill and then load
// into the env (imem driver + reference model + dmem driver).
//
// No UVM dependency - can be reused by any SV testbench.
//
//   import riscv_asm_pkg::*;
//   riscv_program p = new();
//   p.li(5, 32'h8000_0000);          // lui/addi pair (or single addi)
//   p.emit(LB(6, 5, -1));            // lb  x6, -1(x5)
//   p.emit(MULHSU(7, 5, 6));         // mulhsu x7, x5, x6
//   p.emit(ECALL());
// ============================================================================
package riscv_asm_pkg;

    // ------------------------------------------------------------------
    // Architectural constants
    // ------------------------------------------------------------------
    localparam bit [11:0] CSR_MSTATUS     = 12'h300;
    localparam bit [11:0] CSR_MISA        = 12'h301;
    localparam bit [11:0] CSR_MIE         = 12'h304;
    localparam bit [11:0] CSR_MTVEC       = 12'h305;
    localparam bit [11:0] CSR_MSCRATCH    = 12'h340;
    localparam bit [11:0] CSR_MEPC        = 12'h341;
    localparam bit [11:0] CSR_MCAUSE      = 12'h342;
    localparam bit [11:0] CSR_MTVAL       = 12'h343;
    localparam bit [11:0] CSR_MIP         = 12'h344;
    localparam bit [11:0] CSR_MHARTID     = 12'hF14;
    // ultraembedded/riscv custom cache-maintenance CSRs (CSRRW only, see riscv_lsu.v)
    localparam bit [11:0] CSR_DFLUSH      = 12'h3A0;  // flush (write back + keep) whole D$
    localparam bit [11:0] CSR_DWRITEBACK  = 12'h3A1;  // write back line containing rs1
    localparam bit [11:0] CSR_DINVALIDATE = 12'h3A2;  // invalidate line containing rs1

    localparam bit [31:0] CAUSE_ILLEGAL_INSTR    = 32'd2;
    localparam bit [31:0] CAUSE_BREAKPOINT       = 32'd3;
    localparam bit [31:0] CAUSE_MISALIGNED_LOAD  = 32'd4;
    localparam bit [31:0] CAUSE_MISALIGNED_STORE = 32'd6;
    localparam bit [31:0] CAUSE_ECALL_M          = 32'd11;

    // Handy extreme data patterns (toggle coverage)
    localparam bit [31:0] PAT_ZERO = 32'h0000_0000;
    localparam bit [31:0] PAT_ONES = 32'hFFFF_FFFF;
    localparam bit [31:0] PAT_MIN  = 32'h8000_0000;
    localparam bit [31:0] PAT_MAX  = 32'h7FFF_FFFF;
    localparam bit [31:0] PAT_A    = 32'hAAAA_AAAA;
    localparam bit [31:0] PAT_5    = 32'h5555_5555;

    // ------------------------------------------------------------------
    // Raw encoders
    // ------------------------------------------------------------------
    function automatic bit [31:0] enc_r(bit [6:0] f7, bit [4:0] rs2, bit [4:0] rs1,
                                        bit [2:0] f3, bit [4:0] rd, bit [6:0] op);
        return {f7, rs2, rs1, f3, rd, op};
    endfunction

    function automatic bit [31:0] enc_i(int imm, bit [4:0] rs1, bit [2:0] f3,
                                        bit [4:0] rd, bit [6:0] op);
        bit [11:0] i12 = imm[11:0];
        return {i12, rs1, f3, rd, op};
    endfunction

    function automatic bit [31:0] enc_s(int imm, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] f3);
        bit [11:0] i12 = imm[11:0];
        return {i12[11:5], rs2, rs1, f3, i12[4:0], 7'b0100011};
    endfunction

    function automatic bit [31:0] enc_b(int off, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] f3);
        bit [12:0] o = off[12:0];
        return {o[12], o[10:5], rs2, rs1, f3, o[4:1], o[11], 7'b1100011};
    endfunction

    function automatic bit [31:0] enc_u(bit [19:0] imm20, bit [4:0] rd, bit [6:0] op);
        return {imm20, rd, op};
    endfunction

    function automatic bit [31:0] enc_j(int off, bit [4:0] rd);
        bit [20:0] o = off[20:0];
        return {o[20], o[10:1], o[11], o[19:12], rd, 7'b1101111};
    endfunction

    // ------------------------------------------------------------------
    // RV32I
    // ------------------------------------------------------------------
    function automatic bit [31:0] LUI  (bit [4:0] rd, bit [19:0] imm20); return enc_u(imm20, rd, 7'b0110111); endfunction
    function automatic bit [31:0] AUIPC(bit [4:0] rd, bit [19:0] imm20); return enc_u(imm20, rd, 7'b0010111); endfunction
    function automatic bit [31:0] JAL  (bit [4:0] rd, int off);          return enc_j(off, rd); endfunction
    function automatic bit [31:0] JALR (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b000, rd, 7'b1100111); endfunction

    function automatic bit [31:0] BEQ (bit [4:0] rs1, bit [4:0] rs2, int off); return enc_b(off, rs2, rs1, 3'b000); endfunction
    function automatic bit [31:0] BNE (bit [4:0] rs1, bit [4:0] rs2, int off); return enc_b(off, rs2, rs1, 3'b001); endfunction
    function automatic bit [31:0] BLT (bit [4:0] rs1, bit [4:0] rs2, int off); return enc_b(off, rs2, rs1, 3'b100); endfunction
    function automatic bit [31:0] BGE (bit [4:0] rs1, bit [4:0] rs2, int off); return enc_b(off, rs2, rs1, 3'b101); endfunction
    function automatic bit [31:0] BLTU(bit [4:0] rs1, bit [4:0] rs2, int off); return enc_b(off, rs2, rs1, 3'b110); endfunction
    function automatic bit [31:0] BGEU(bit [4:0] rs1, bit [4:0] rs2, int off); return enc_b(off, rs2, rs1, 3'b111); endfunction

    function automatic bit [31:0] LB (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b000, rd, 7'b0000011); endfunction
    function automatic bit [31:0] LH (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b001, rd, 7'b0000011); endfunction
    function automatic bit [31:0] LW (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b010, rd, 7'b0000011); endfunction
    function automatic bit [31:0] LBU(bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b100, rd, 7'b0000011); endfunction
    function automatic bit [31:0] LHU(bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b101, rd, 7'b0000011); endfunction
    // NOTE: store argument order follows assembly syntax:  sb rs2, imm(rs1)
    function automatic bit [31:0] SB (bit [4:0] rs2, bit [4:0] rs1, int imm); return enc_s(imm, rs2, rs1, 3'b000); endfunction
    function automatic bit [31:0] SH (bit [4:0] rs2, bit [4:0] rs1, int imm); return enc_s(imm, rs2, rs1, 3'b001); endfunction
    function automatic bit [31:0] SW (bit [4:0] rs2, bit [4:0] rs1, int imm); return enc_s(imm, rs2, rs1, 3'b010); endfunction

    function automatic bit [31:0] ADDI (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b000, rd, 7'b0010011); endfunction
    function automatic bit [31:0] SLTI (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b010, rd, 7'b0010011); endfunction
    function automatic bit [31:0] SLTIU(bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b011, rd, 7'b0010011); endfunction
    function automatic bit [31:0] XORI (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b100, rd, 7'b0010011); endfunction
    function automatic bit [31:0] ORI  (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b110, rd, 7'b0010011); endfunction
    function automatic bit [31:0] ANDI (bit [4:0] rd, bit [4:0] rs1, int imm); return enc_i(imm, rs1, 3'b111, rd, 7'b0010011); endfunction
    function automatic bit [31:0] SLLI (bit [4:0] rd, bit [4:0] rs1, bit [4:0] sh); return enc_r(7'b0000000, sh, rs1, 3'b001, rd, 7'b0010011); endfunction
    function automatic bit [31:0] SRLI (bit [4:0] rd, bit [4:0] rs1, bit [4:0] sh); return enc_r(7'b0000000, sh, rs1, 3'b101, rd, 7'b0010011); endfunction
    function automatic bit [31:0] SRAI (bit [4:0] rd, bit [4:0] rs1, bit [4:0] sh); return enc_r(7'b0100000, sh, rs1, 3'b101, rd, 7'b0010011); endfunction

    function automatic bit [31:0] ADD (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011); endfunction
    function automatic bit [31:0] SUB (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011); endfunction
    function automatic bit [31:0] SLL (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b001, rd, 7'b0110011); endfunction
    function automatic bit [31:0] SLT (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011); endfunction
    function automatic bit [31:0] SLTU(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b011, rd, 7'b0110011); endfunction
    function automatic bit [31:0] XOR (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011); endfunction
    function automatic bit [31:0] SRL (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b101, rd, 7'b0110011); endfunction
    function automatic bit [31:0] SRA (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0100000, rs2, rs1, 3'b101, rd, 7'b0110011); endfunction
    function automatic bit [31:0] OR  (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011); endfunction
    function automatic bit [31:0] AND (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011); endfunction

    // ------------------------------------------------------------------
    // RV32M
    // ------------------------------------------------------------------
    function automatic bit [31:0] MUL   (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b000, rd, 7'b0110011); endfunction
    function automatic bit [31:0] MULH  (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b001, rd, 7'b0110011); endfunction
    function automatic bit [31:0] MULHSU(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b010, rd, 7'b0110011); endfunction
    function automatic bit [31:0] MULHU (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b011, rd, 7'b0110011); endfunction
    function automatic bit [31:0] DIV   (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b100, rd, 7'b0110011); endfunction
    function automatic bit [31:0] DIVU  (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b101, rd, 7'b0110011); endfunction
    function automatic bit [31:0] REM   (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b110, rd, 7'b0110011); endfunction
    function automatic bit [31:0] REMU  (bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2); return enc_r(7'b0000001, rs2, rs1, 3'b111, rd, 7'b0110011); endfunction

    // M-extension op by index 0..7 (funct3 order: MUL MULH MULHSU MULHU DIV DIVU REM REMU)
    function automatic bit [31:0] MEXT(int unsigned f3, bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2);
        return enc_r(7'b0000001, rs2, rs1, f3[2:0], rd, 7'b0110011);
    endfunction

    // ------------------------------------------------------------------
    // System / Zicsr / Zifencei
    // ------------------------------------------------------------------
    function automatic bit [31:0] ECALL  (); return 32'h0000_0073; endfunction
    function automatic bit [31:0] EBREAK (); return 32'h0010_0073; endfunction
    function automatic bit [31:0] MRET   (); return 32'h3020_0073; endfunction
    function automatic bit [31:0] FENCE  (); return 32'h0FF0_000F; endfunction
    function automatic bit [31:0] FENCE_I(); return 32'h0000_100F; endfunction
    function automatic bit [31:0] NOP    (); return 32'h0000_0013; endfunction

    function automatic bit [31:0] CSRRW (bit [4:0] rd, bit [11:0] csr, bit [4:0] rs1); return {csr, rs1, 3'b001, rd, 7'b1110011}; endfunction
    function automatic bit [31:0] CSRRS (bit [4:0] rd, bit [11:0] csr, bit [4:0] rs1); return {csr, rs1, 3'b010, rd, 7'b1110011}; endfunction
    function automatic bit [31:0] CSRRC (bit [4:0] rd, bit [11:0] csr, bit [4:0] rs1); return {csr, rs1, 3'b011, rd, 7'b1110011}; endfunction
    function automatic bit [31:0] CSRRWI(bit [4:0] rd, bit [11:0] csr, bit [4:0] uimm); return {csr, uimm, 3'b101, rd, 7'b1110011}; endfunction
    function automatic bit [31:0] CSRRSI(bit [4:0] rd, bit [11:0] csr, bit [4:0] uimm); return {csr, uimm, 3'b110, rd, 7'b1110011}; endfunction
    function automatic bit [31:0] CSRRCI(bit [4:0] rd, bit [11:0] csr, bit [4:0] uimm); return {csr, uimm, 3'b111, rd, 7'b1110011}; endfunction
    function automatic bit [31:0] CSRR  (bit [4:0] rd, bit [11:0] csr);                return CSRRS(rd, csr, 5'd0); endfunction

    // ==================================================================
    // riscv_program : sparse instruction + data image built by a test
    // ==================================================================
    class riscv_program;
        bit [31:0] imem [bit [31:0]];
        bit [31:0] dmem [bit [31:0]];
        bit [31:0] pc;

        function new(bit [31:0] start_pc = 32'h0);
            pc = start_pc;
        endfunction

        // Move the emit pointer (start a new code block somewhere else)
        function void org(bit [31:0] addr);
            pc = addr;
        endfunction

        function bit [31:0] here();
            return pc;
        endfunction

        function void emit(bit [31:0] instr);
            if (imem.exists(pc))
                $display("riscv_program: WARNING overwriting instruction at 0x%08h", pc);
            imem[pc] = instr;
            pc += 4;
        endfunction

        // Re-write an already emitted word (used to resolve forward branches)
        function void patch(bit [31:0] addr, bit [31:0] instr);
            imem[addr] = instr;
        endfunction

        // Reserve one slot for a forward branch/jump; returns its address
        function bit [31:0] reserve();
            bit [31:0] a = pc;
            emit(NOP());
            return a;
        endfunction

        // Load any 32-bit constant: LUI (+ADDI) - handles the ADDI sign carry
        function void li(bit [4:0] rd, bit [31:0] value);
            bit [31:0] lo = {{20{value[11]}}, value[11:0]};
            bit [31:0] hi = value - lo;
            if (hi != 0) begin
                emit(LUI(rd, hi[31:12]));
                if (lo != 0) emit(ADDI(rd, rd, int'(lo)));
            end else begin
                emit(ADDI(rd, 5'd0, int'(lo)));
            end
        endfunction

        // End-of-program marker the reference model recognises (jal x0, 0)
        function void halt();
            emit(JAL(5'd0, 0));
        endfunction

        function void data(bit [31:0] addr, bit [31:0] value);
            dmem[{addr[31:2], 2'b00}] = value;
        endfunction

        function int unsigned num_instr();
            return imem.num();
        endfunction
    endclass

endpackage
