// ============================================================================
// riscv_mext_test
// ----------------------------------------------------------------------------
// Full RV32M: MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//   1. exhaustive operand-class sweep: 8 ops x 7 rs1 classes x 7 rs2 classes
//      classes = {0, 1, -1, INT_MIN, INT_MAX, +other, -other}
//      -> includes div-by-zero and INT_MIN / -1 overflow for DIV and REM
//   2. dependency chains (mul->mul, mul->alu, div->mul, mulh->div) to hit the
//      multiplier bypass / divider stall logic in the pipeline
//   3. randomized operands drawn from extreme values (seed dependent)
// Targets: riscv_multiplier, riscv_divider, riscv_pipe_ctrl stalls, mext_cg.
// ============================================================================
package riscv_mext_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    `include "uvm_macros.svh"

    class riscv_mext_test extends riscv_prog_base_test;
        `uvm_component_utils(riscv_mext_test)

        int unsigned num_random = 64;

        function new(string name = "riscv_mext_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_program();
            bit [31:0] vals [7] = '{32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF, 32'h8000_0000,
                                    32'h7FFF_FFFF, 32'h1234_5678, 32'hFEDC_BA98};
            int unsigned cnt = 0;

            // x1..x7 = {0, 1, -1, INT_MIN, INT_MAX, +pos, -neg}
            foreach (vals[i]) prog.li(i + 1, vals[i]);

            // ---------- 1. sweep ----------
            for (int op = 0; op < 8; op++)
                for (int i = 0; i < 7; i++)
                    for (int j = 0; j < 7; j++) begin
                        prog.emit(MEXT(op, 8 + (cnt % 16), i + 1, j + 1));
                        cnt++;
                    end

            // ---------- 2. dependency chains ----------
            prog.li(24, 32'h0001_0003);
            prog.li(25, 32'hFFFF_FFF9);                      // -7
            prog.emit(MUL   (26, 24, 25));
            prog.emit(ADD   (27, 26, 26));                   // mul -> alu (bypass)
            prog.emit(MULH  (28, 26, 24));                   // mul -> mul
            prog.emit(MULHSU(29, 28, 25));
            prog.emit(DIV   (30, 29, 25));                   // mul -> div
            prog.emit(MUL   (31, 30, 30));                   // div -> mul
            prog.emit(REM   (26, 31, 24));
            prog.emit(DIVU  (27, 26, 25));
            prog.emit(REMU  (28, 27, 24));
            prog.emit(MULHU (29, 28, 25));
            prog.emit(SUB   (30, 29, 28));
            // back-to-back independent long-latency ops
            prog.emit(DIV (8, 6, 2));  prog.emit(DIVU(9, 6, 2));
            prog.emit(REM (10, 7, 6)); prog.emit(REMU(11, 7, 6));
            prog.emit(MUL (12, 8, 9)); prog.emit(MULH(13, 10, 11));
            // divide immediately consumed by a branch
            prog.emit(DIV (14, 4, 3));                       // INT_MIN / -1 -> overflow = INT_MIN
            prog.emit(BLT (14, 0, 8));                       // taken
            prog.emit(ADDI(15, 0, 99));                      // skipped
            prog.emit(REM (15, 4, 1));                       // rem by zero -> rs1
            // mul result used as load address offset base
            prog.li(16, 32'h0000_0800);
            prog.emit(MUL (17, 16, 2));                      // 0x800 * 1
            prog.emit(SW  (5, 17, 0));
            prog.emit(LW  (18, 17, 0));

            // ---------- 3. random operands / ops ----------
            for (int r = 1; r <= 7; r++) prog.li(r, rand_program::rand_extreme_value());
            for (int k = 0; k < num_random; k++) begin
                bit [4:0] rs1 = $urandom_range(1, 7);
                bit [4:0] rs2 = $urandom_range(1, 7);
                prog.emit(MEXT($urandom_range(0, 7), 8 + (k % 16), rs1, rs2));
            end

            prog.halt();
        endfunction
    endclass
endpackage
