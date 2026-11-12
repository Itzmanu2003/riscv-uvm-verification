// ============================================================================
// riscv_byte_half_test
// ----------------------------------------------------------------------------
// LB / LH / LBU / LHU / SB / SH (and LW/SW cross-checks):
//   1. every load type at every legal byte offset over sign-sensitive patterns
//   2. SB to each byte lane (0x00/0x7F/0x80/0xFF) + LW/LB/LBU read-back
//   3. SH to both halves (0x0000/0x7FFF/0x8000/0xFFFF) + LW/LH/LHU read-back
//   4. store->load forwarding / load-use hazards with narrow accesses
//   5. negative offsets
//   6. partial-store cache MISSES (REFILL->WRITE with byte strobes) followed by
//      dirty eviction and reload -> checks the AXI WSTRB merge end-to-end
//   7. sign-extended loads feeding ALU and branches
// Targets: riscv_lsu (mem_xb/xh/ls paths), dcache byte-enable writes,
//          dcache_core REFILL->WRITE / EVICT arcs, ls_cg functional coverage.
// ============================================================================
package riscv_byte_half_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    `include "uvm_macros.svh"

    class riscv_byte_half_test extends riscv_prog_base_test;
        `uvm_component_utils(riscv_byte_half_test)

        function new(string name = "riscv_byte_half_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_program();
            bit [31:0] D  = 32'h0000_3000;      // pattern area
            bit [31:0] pats [8] = '{32'h80FF_7F01, 32'h8000_7FFF, 32'hFFFF_0000, 32'h0123_4567,
                                    32'hDEAD_BEEF, 32'h7F80_FF00, 32'h0000_0080, 32'h0000_8000};
            bit [31:0] lane_vals [4] = '{32'h0000_0000, 32'h0000_007F, 32'hFFFF_FF80, 32'hFFFF_FFFF};
            bit [31:0] half_vals [5] = '{32'h0000_0000, 32'h0000_7FFF, 32'hFFFF_8000, 32'hFFFF_FFFF, 32'h0000_1234};
            bit [31:0] A;

            foreach (pats[w]) prog.data(D + w*4, pats[w]);

            prog.li(20, D);
            // ---------- 1. all load flavours / offsets ----------
            foreach (pats[w]) begin
                for (int off = 0; off < 4; off++) begin
                    prog.emit(LB (5, 20, w*4 + off));
                    prog.emit(LBU(6, 20, w*4 + off));
                end
                prog.emit(LH (7, 20, w*4));     prog.emit(LH (7, 20, w*4 + 2));
                prog.emit(LHU(8, 20, w*4));     prog.emit(LHU(8, 20, w*4 + 2));
                prog.emit(LW (9, 20, w*4));
            end

            // ---------- 2. SB to every lane ----------
            prog.li(21, D + 32'h40);                       // scratch word
            prog.li(10, lane_vals[0]); prog.li(11, lane_vals[1]);
            prog.li(12, lane_vals[2]); prog.li(13, lane_vals[3]);
            prog.li(14, 32'h1122_3344); prog.emit(SW(14, 21, 0));
            for (int lane = 0; lane < 4; lane++) begin
                for (int v = 10; v <= 13; v++) begin
                    prog.emit(SB(v[4:0], 21, lane));
                    prog.emit(LW (15, 21, 0));
                    prog.emit(LB (16, 21, lane));
                    prog.emit(LBU(17, 21, lane));
                end
            end

            // ---------- 3. SH to both halves ----------
            prog.li(22, D + 32'h44);
            foreach (half_vals[k]) begin
                prog.li(18, half_vals[k]);
                prog.emit(SH(18, 22, 0));
                prog.emit(SH(18, 22, 2));
                prog.emit(LW (15, 22, 0));
                prog.emit(LH (16, 22, 0));
                prog.emit(LHU(17, 22, 2));
                prog.emit(ADDI(18, 18, 7));                // vary the other half
                prog.emit(SH(18, 22, 2));
                prog.emit(LW (15, 22, 0));
            end

            // ---------- 4. forwarding / load-use with narrow accesses ----------
            prog.li(23, D + 32'h48);
            prog.emit(SB(12, 23, 1));  prog.emit(LB (5, 23, 1));     // SB -> LB same byte
            prog.emit(ADD(6, 5, 5));                                 // load-use on sign-extended byte
            prog.emit(SH(12, 23, 2));  prog.emit(LW (7, 23, 0));     // SH -> LW
            prog.emit(SW(11, 23, 4));  prog.emit(LB (8, 23, 4));     // SW -> LB
            prog.emit(LBU(9, 23, 1));  prog.emit(SUB(9, 0, 9));      // LBU load-use
            prog.emit(LH (5, 23, 2));  prog.emit(SB(5, 23, 7));      // load -> store data dependency
            prog.emit(LW (6, 23, 4));
            prog.emit(LHU(7, 23, 2));  prog.emit(SH(7, 23, 4));  prog.emit(LH(8, 23, 4));

            // ---------- 5. negative offsets ----------
            prog.li(24, D + 32'h100);
            prog.emit(SW(13, 24, -4)); prog.emit(SW(11, 24, -8));
            for (int off = 1; off <= 8; off++) begin
                prog.emit(LB (5, 24, -off));
                prog.emit(LBU(6, 24, -off));
            end
            prog.emit(LH (7, 24, -2)); prog.emit(LHU(8, 24, -6));
            prog.emit(SB(10, 24, -3)); prog.emit(SH(12, 24, -6)); prog.emit(LW(9, 24, -4)); prog.emit(LW(9, 24, -8));

            // ---------- 6. partial-store misses + eviction + reload ----------
            // three lines with the same D$ index (addr[12:5]) and different tags
            A = 32'h0001_0400;
            for (int t = 0; t < 4; t++) prog.data(A + t*32'h2000, 32'hA5A5_0000 + t);
            prog.li(25, A);
            prog.li(26, A + 32'h2000);
            prog.li(27, A + 32'h4000);
            prog.li(28, A + 32'h6000);
            prog.emit(SB(12, 25, 1));                // miss -> refill -> byte write
            prog.emit(SH(11, 26, 2));                // miss -> refill -> half write
            prog.emit(SB(10, 27, 3));                // evicts a dirty line
            prog.emit(SH(12, 28, 0));                // evicts another dirty line
            prog.emit(LW(5, 25, 0));                 // reload merged words from memory
            prog.emit(LW(6, 26, 0));
            prog.emit(LW(7, 27, 0));
            prog.emit(LW(8, 28, 0));
            prog.emit(LBU(9, 25, 1)); prog.emit(LH(9, 26, 2)); prog.emit(LB(9, 27, 3)); prog.emit(LHU(9, 28, 0));

            // ---------- 7. sign-extended loads feeding ALU/branches ----------
            prog.emit(LB(5, 20, 1));                 // 0x7F -> +127
            prog.emit(LB(6, 20, 2));                 // 0xFF -> -1
            prog.emit(BLT(6, 5, 8));                 // taken (-1 < 127)
            prog.emit(ADDI(7, 0, 111));              // skipped
            prog.emit(LBU(7, 20, 2));                // 0xFF -> 255
            prog.emit(BLTU(5, 7, 8));                // taken (127 < 255)
            prog.emit(ADDI(8, 0, 222));              // skipped
            prog.emit(LH(8, 20, 4 + 2));             // 0x8000 -> negative
            prog.emit(SLT(9, 8, 0));                 // 1
            prog.emit(SRAI(10, 8, 4));
            prog.emit(LHU(11, 20, 4 + 2));
            prog.emit(SRLI(12, 11, 4));

            prog.halt();
        endfunction
    endclass
endpackage
