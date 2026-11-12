// ============================================================================
// riscv_extreme_test  (toggle-coverage closure)
// ----------------------------------------------------------------------------
//   A. every register x1..x31 written with 0xFFFFFFFF, 0, 0xAAAAAAAA, 0x55555555
//   B. R-type ALU on all pairs of {0, 1, -1, MIN, MAX, 0xAAAAAAAA, 0x55555555};
//      I-type with extreme immediates; shifts by 0/1/15/16/31
//   C. walking-one / walking-zero values through the datapath
//   D. branches on signed/unsigned extremes, max-range BEQ (+/-4 KB) and
//      JAL (+/-1 MB) offsets
//   E. loads/stores at addresses in all 16 address regions with alternating
//      bit patterns (AXI address/data + D$ tag toggles), +/-2 KB offsets
//   F. all writable CSRs toggled 0 -> ~0 -> 0xAAAAAAAA -> 0x55555555 -> 0
//   G. code executed in all 16 PC regions (fetch PC, I$ tags, branch target
//      and AUIPC result toggles), LUI/AUIPC with extreme immediates
// ============================================================================
package riscv_extreme_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    `include "uvm_macros.svh"

    class riscv_extreme_test extends riscv_prog_base_test;
        `uvm_component_utils(riscv_extreme_test)

        function new(string name = "riscv_extreme_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        // address in region k with an alternating low-bit pattern (word aligned)
        function bit [31:0] region_addr(int k);
            return {k[3:0], 28'h0} | ((k % 2) ? 32'h0AAA_AAA8 : 32'h0555_5554);
        endfunction

        virtual function void build_program();
            bit [31:0] ext [7] = '{PAT_ZERO, 32'h1, PAT_ONES, PAT_MIN, PAT_MAX, PAT_A, PAT_5};
            int        imms [7] = '{-2048, -1, 0, 1, 2047, 32'h555, -1366};
            bit [4:0]  shamts [5] = '{0, 1, 15, 16, 31};
            bit [11:0] wcsr [4] = '{CSR_MSCRATCH, CSR_MTVEC, CSR_MEPC, CSR_MTVAL};
            bit [11:0] mcsr [4] = '{CSR_MCAUSE, CSR_MIE, CSR_MIP, CSR_MSTATUS};
            int unsigned rd = 0;
            bit [31:0] p, save, tgt;

            // ---------- A. register file toggles ----------
            for (int r = 1; r < 32; r++) prog.emit(ADDI(r, 0, -1));
            for (int r = 1; r < 32; r++) prog.emit(ADDI(r, 0, 0));
            for (int r = 1; r < 32; r++) prog.li(r, (r % 2) ? PAT_A : PAT_5);
            for (int r = 1; r < 32; r++) prog.li(r, (r % 2) ? PAT_5 : PAT_A);
            for (int r = 1; r < 32; r++) prog.emit(ADDI(r, 0, 0));

            // ---------- B. ALU on extreme operand pairs ----------
            foreach (ext[i]) prog.li(i + 1, ext[i]);           // x1..x7
            for (int i = 1; i <= 7; i++)
                for (int j = 1; j <= 7; j++) begin
                    prog.emit(ADD (8 + rd % 16, i, j)); rd++;
                    prog.emit(SUB (8 + rd % 16, i, j)); rd++;
                    prog.emit(AND (8 + rd % 16, i, j)); rd++;
                    prog.emit(OR  (8 + rd % 16, i, j)); rd++;
                    prog.emit(XOR (8 + rd % 16, i, j)); rd++;
                    prog.emit(SLT (8 + rd % 16, i, j)); rd++;
                    prog.emit(SLTU(8 + rd % 16, i, j)); rd++;
                    prog.emit(SLL (8 + rd % 16, i, j)); rd++;
                    prog.emit(SRL (8 + rd % 16, i, j)); rd++;
                    prog.emit(SRA (8 + rd % 16, i, j)); rd++;
                end
            for (int i = 1; i <= 7; i++) begin
                foreach (imms[k]) begin
                    prog.emit(ADDI (8 + rd % 16, i, imms[k])); rd++;
                    prog.emit(SLTI (8 + rd % 16, i, imms[k])); rd++;
                    prog.emit(SLTIU(8 + rd % 16, i, imms[k])); rd++;
                    prog.emit(XORI (8 + rd % 16, i, imms[k])); rd++;
                    prog.emit(ORI  (8 + rd % 16, i, imms[k])); rd++;
                    prog.emit(ANDI (8 + rd % 16, i, imms[k])); rd++;
                end
                foreach (shamts[k]) begin
                    prog.emit(SLLI(8 + rd % 16, i, shamts[k])); rd++;
                    prog.emit(SRLI(8 + rd % 16, i, shamts[k])); rd++;
                    prog.emit(SRAI(8 + rd % 16, i, shamts[k])); rd++;
                end
            end

            // ---------- C. walking one / walking zero ----------
            for (int b = 0; b < 32; b++) begin
                prog.li(24, 32'h1 << b);
                prog.emit(XORI(25, 24, -1));                    // ~(1<<b)
                prog.emit(ADD (26, 24, 25));                    // = 0xFFFFFFFF
            end
            prog.li(24, 32'h1);
            for (int b = 0; b < 32; b++) begin                 // register-shift version
                prog.li(23, b);
                prog.emit(SLL(25, 24, 23));
                prog.emit(SRA(26, 4, 23));                      // MIN >>> b
            end

            // ---------- D. branches on extremes ----------
            // (x1=0 x2=1 x3=-1 x4=MIN x5=MAX x6=0xAAAAAAAA x7=0x55555555)
            foreach (ext[i]) prog.li(i + 1, ext[i]);
            prog.li(9, 0);
            for (int i = 1; i <= 7; i++)
                for (int j = 1; j <= 7; j += 2) begin
                    prog.emit(BLT (i, j, 8)); prog.emit(ADDI(9, 9, 1));
                    prog.emit(BGE (i, j, 8)); prog.emit(ADDI(9, 9, 2));
                    prog.emit(BLTU(i, j, 8)); prog.emit(ADDI(9, 9, 4));
                    prog.emit(BGEU(i, j, 8)); prog.emit(ADDI(9, 9, 8));
                    prog.emit(BEQ (i, j, 8)); prog.emit(ADDI(9, 9, 16));
                    prog.emit(BNE (i, j, 8)); prog.emit(ADDI(9, 9, 32));
                end

            // ---------- E. memory at extreme addresses / patterns ----------
            for (int k = 0; k < 16; k++) begin
                prog.li(20, region_addr(k));
                prog.li(21, (k % 2) ? PAT_5 : PAT_A);
                prog.emit(SW(21, 20, 0));
            end
            for (int k = 0; k < 16; k++) begin
                prog.li(20, region_addr(k));
                prog.emit(LW(22, 20, 0));
                prog.emit(LB(23, 20, 3));
            end
            p = 32'hFFFF_FFFC; prog.li(20, p); prog.emit(SW(3, 20, 0));    prog.emit(LW(22, 20, 0));
            p = 32'h8000_0000; prog.li(20, p); prog.emit(SW(5, 20, 0));    prog.emit(LW(22, 20, 0));
            p = 32'h7FFF_FFFC; prog.li(20, p); prog.emit(SW(4, 20, 0));    prog.emit(LW(22, 20, 0));
            p = 32'h0000_0000; prog.li(20, p); prog.emit(SW(3, 20, 0));    prog.emit(LHU(22, 20, 2));
            p = 32'h0001_0800; prog.li(20, p);                              // +/-2KB immediates
            prog.emit(SW(6, 20, -2048)); prog.emit(SW(7, 20, 2044));
            prog.emit(LW(22, 20, -2048)); prog.emit(LW(23, 20, 2044));
            prog.emit(SB(3, 20, 2047));  prog.emit(LBU(22, 20, 2047));

            // ---------- F. CSR toggles ----------
            prog.emit(CSRRW(0, CSR_MIE, 0));                    // no interrupt can be enabled
            foreach (wcsr[c]) begin
                prog.emit(CSRRW(10, wcsr[c], 3));   prog.emit(CSRR(10, wcsr[c]));  // ~0
                prog.emit(CSRRW(10, wcsr[c], 6));   prog.emit(CSRR(10, wcsr[c]));  // AAAA
                prog.emit(CSRRW(10, wcsr[c], 7));   prog.emit(CSRR(10, wcsr[c]));  // 5555
                prog.emit(CSRRW(10, wcsr[c], 0));   prog.emit(CSRR(10, wcsr[c]));  // 0
            end
            foreach (mcsr[c]) begin                             // masked CSRs
                prog.emit(CSRRS(11, mcsr[c], 3));   prog.emit(CSRR(11, mcsr[c]));
                prog.emit(CSRRC(11, mcsr[c], 6));   prog.emit(CSRR(11, mcsr[c]));
                prog.emit(CSRRW(11, mcsr[c], 0));   prog.emit(CSRR(11, mcsr[c]));
            end
            prog.emit(CSRRWI(12, CSR_MSCRATCH, 5'h1F)); prog.emit(CSRRSI(12, CSR_MSCRATCH, 5'h00));
            prog.emit(CSRRCI(12, CSR_MSCRATCH, 5'h15)); prog.emit(CSRR(12, CSR_MSCRATCH));

            // ---------- G. execute in all 16 PC regions ----------
            for (int k = 0; k < 16; k++) begin
                tgt = region_addr(k) + 32'h100;
                prog.li(13, tgt);
                prog.emit(JALR(1, 13, 0));
                save = prog.here();
                prog.org(tgt);
                prog.emit(AUIPC(14, 20'hFFFFF));                // pc - 4096
                prog.emit(JALR(0, 1, 0));
                prog.org(save);
            end
            tgt = 32'hFFFF_FFE0;                                // all-ones PC bits
            prog.li(13, tgt); prog.emit(JALR(1, 13, 0)); save = prog.here();
            prog.org(tgt); prog.emit(AUIPC(14, 20'h0)); prog.emit(JALR(0, 1, 0)); prog.org(save);
            prog.emit(LUI  (15, 20'hFFFFF)); prog.emit(LUI  (15, 20'h80000));
            prog.emit(LUI  (15, 20'h55555)); prog.emit(LUI  (15, 20'hAAAAA));
            prog.emit(AUIPC(16, 20'h80000)); prog.emit(AUIPC(16, 20'h55555)); prog.emit(AUIPC(16, 20'hAAAAA));

            // max-range JAL (+1MB-16) and BEQ (+4KB-4) round trips (placed last,
            // so the far targets land beyond the end of the main program)
            p = prog.here();
            prog.emit(JAL(1, 32'h000F_FFF0));
            save = prog.here();
            prog.org(p + 32'h000F_FFF0);
            prog.emit(JAL(0, int'(save) - int'(prog.here())));  // ~-1MB back
            prog.org(save);
            p = prog.here();
            prog.emit(BEQ(0, 0, 4092));
            save = prog.here();
            prog.org(p + 4092);
            prog.emit(BEQ(0, 0, int'(save) - int'(prog.here())));
            prog.org(save);
            prog.emit(ADDI(17, 0, 17));

            prog.halt();
        endfunction
    endclass
endpackage
