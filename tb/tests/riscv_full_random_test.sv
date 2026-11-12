// ============================================================================
// riscv_full_random_test
// ----------------------------------------------------------------------------
// Constrained-random program mixing every instruction class the reference
// model supports:  R/I ALU, full M-ext, LB/LH/LW/LBU/LHU/SB/SH/SW on three
// base pointers that alias the same D$ sets (=> random evictions), ECALL /
// EBREAK / misaligned accesses (=> traps through a standard handler),
// D$ writeback(+invalidate) / flush, FENCE.I, short forward branches.
//
// Register usage:  x1..x23 random destinations, x24..x26 base pointers,
//                  x27..x30 trap-handler scratch, x31 temp
// Plusargs: +RAND_INSTRS=<n> (default 400)
// Run with several seeds:  +ntb_random_seed=<s>
// ============================================================================
package riscv_full_random_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    `include "uvm_macros.svh"

    class riscv_full_random_test extends riscv_prog_base_test;
        `uvm_component_utils(riscv_full_random_test)

        localparam bit [31:0] HANDLER = 32'h0000_F000;
        bit [31:0] bases [3] = '{32'h0000_2000, 32'h5555_6000, 32'hAAAA_A000};  // same D$ sets
        int unsigned n_instr = 400;

        function new(string name = "riscv_full_random_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_program();
            int unsigned v;
            if ($value$plusargs("RAND_INSTRS=%d", v)) n_instr = v;

            emit_trap_handler(HANDLER);
            set_mtvec(HANDLER);

            // data windows [-256, +256) around each base
            foreach (bases[b])
                for (int off = -256; off < 256; off += 4)
                    prog.data(bases[b] + off, rand_program::rand_extreme_value());

            foreach (bases[b]) prog.li(24 + b, bases[b]);
            for (int r = 1; r <= 23; r++) prog.li(r, rand_program::rand_extreme_value());
            prog.li(31, rand_program::rand_extreme_value());
            if ($urandom_range(0, 1)) prog.emit(CSRRSI(0, CSR_MSTATUS, 5'd8));   // random MIE

            for (int unsigned i = 0; i < n_instr; i++) begin
                int unsigned sel  = $urandom_range(0, 99);
                bit [4:0]    base = 24 + $urandom_range(0, 2);
                if      (sel < 25) prog.emit(rand_program::rand_rtype(0, 23));
                else if (sel < 43) prog.emit(rand_program::rand_itype(0, 23));
                else if (sel < 55) prog.emit(rand_program::rand_mext(23));
                else if (sel < 69) prog.emit(rand_program::rand_load(base, 23));
                else if (sel < 81) prog.emit(rand_program::rand_store(base));
                else if (sel < 84) prog.emit(LUI($urandom_range(1, 23), $urandom()));
                else if (sel < 86) prog.emit(AUIPC($urandom_range(1, 23), $urandom()));
                else if (sel < 88) prog.emit($urandom_range(0, 1) ? ECALL() : EBREAK());
                else if (sel < 90) prog.emit($urandom_range(0, 1) ? rand_program::rand_load(base, 23, 1)
                                                                 : rand_program::rand_store(base, 1));
                else if (sel < 92) begin                       // D$ maintenance on a base line
                    case ($urandom_range(0, 2))
                        0: prog.emit(CSRRW(0, CSR_DWRITEBACK, base));
                        1: begin prog.emit(CSRRW(0, CSR_DWRITEBACK, base));      // clean first,
                                 prog.emit(CSRRW(0, CSR_DINVALIDATE, base)); end // then drop
                        default: prog.emit(CSRRW(0, CSR_DFLUSH, 0));
                    endcase
                end
                else if (sel < 93) prog.emit(FENCE_I());
                else begin                                     // short forward branch
                    bit [4:0] rs1 = $urandom_range(0, 31);
                    bit [4:0] rs2 = $urandom_range(0, 31);
                    case ($urandom_range(0, 5))
                        0: prog.emit(BEQ (rs1, rs2, 8));
                        1: prog.emit(BNE (rs1, rs2, 8));
                        2: prog.emit(BLT (rs1, rs2, 8));
                        3: prog.emit(BGE (rs1, rs2, 8));
                        4: prog.emit(BLTU(rs1, rs2, 8));
                        default: prog.emit(BGEU(rs1, rs2, 8));
                    endcase
                    prog.emit(rand_program::rand_itype(0, 23));        // maybe skipped
                end
            end

            prog.halt();
        endfunction
    endclass
endpackage
