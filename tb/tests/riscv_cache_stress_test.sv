// ============================================================================
// riscv_cache_stress_test
// ----------------------------------------------------------------------------
// D$ = 2-way, 256 sets, 32B lines  -> set index = addr[12:5], tag = addr[31:13]
// I$ = 2-way, 256 sets, 32B lines
//
//   1. 6 tags x 4 sets, dirty lines   -> LOOKUP->EVICT->EVICT_WAIT->REFILL
//   2. read back in reverse order     -> dirty evictions on loads, data check
//   3. byte/half store misses         -> REFILL->WRITE
//   4. CSR 0x3A1 writeback (dirty and clean line), CSR 0x3A2 invalidate,
//      reload from memory             -> WRITEBACK->EVICT / WRITEBACK->LOOKUP,
//                                        EVICT_WAIT->LOOKUP, INVALIDATE
//   5. 16 dirty lines + CSR 0x3A0 flush, then invalidate+reload every line
//                                     -> FLUSH_ADDR/FLUSH/EVICT/EVICT_WAIT->FLUSH_ADDR,
//                                        FLUSH->LOOKUP; proves flush hit memory
//   6. write->read same word/line back to back (D$ accept hazard logic)
//   7. FENCE / FENCE.I (I$ LOOKUP->FLUSH) and I$ conflict misses by jumping
//      to code blocks that alias the same I$ set
// Every reload is a register write, so the scoreboard proves data integrity
// through the AXI write channel (which no previous test exercised).
// Tags use extreme bit patterns -> tag RAM / AXI address toggle coverage.
// ============================================================================
package riscv_cache_stress_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    `include "uvm_macros.svh"

    class riscv_cache_stress_test extends riscv_prog_base_test;
        `uvm_component_utils(riscv_cache_stress_test)

        // 19-bit tags with extreme patterns, 8-bit set indexes
        bit [18:0] tags [6] = '{19'h00000, 19'h7FFFF, 19'h2AAAA, 19'h55555, 19'h40000, 19'h00001};
        bit [7:0]  sets [4] = '{8'h01, 8'h55, 8'hAA, 8'hFE};

        function new(string name = "riscv_cache_stress_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function bit [31:0] line_addr(bit [18:0] tag, bit [7:0] set);
            return {tag, set, 5'b0};
        endfunction

        virtual function void build_program();
            bit [31:0] a;
            bit [31:0] blk;

            // preload memory behind every line we will touch
            foreach (sets[s]) foreach (tags[t]) begin
                a = line_addr(tags[t], sets[s]);
                for (int w = 0; w < 8; w++) prog.data(a + w*4, {8'hD0 + t[7:0], sets[s], 8'h00, w[7:0]});
            end

            // ---------- 1. dirty fills with conflicts ----------
            foreach (sets[s]) foreach (tags[t]) begin
                prog.li(20, line_addr(tags[t], sets[s]));
                prog.li(21, {4'hC, t[3:0], sets[s], 16'hBEEF});
                prog.emit(SW(21, 20, 0));
                prog.emit(SB(21, 20, 29));
                prog.emit(SH(21, 20, 14));
            end

            // ---------- 2. reverse-order read back ----------
            foreach (sets[s]) for (int t = 5; t >= 0; t--) begin
                prog.li(20, line_addr(tags[t], sets[s]));
                prog.emit(LW (5, 20, 0));
                prog.emit(LBU(6, 20, 29));
                prog.emit(LH (7, 20, 14));
                prog.emit(LW (8, 20, 28));
                prog.emit(LW (9, 20, 4));               // untouched word: comes from memory/refill
            end

            // ---------- 3. narrow store misses (cold lines) ----------
            prog.li(22, 32'h0003_3660);                  // same set (0xB3), 3 different tags
            prog.li(23, 32'h0005_3660);
            prog.li(24, 32'h0007_3660);
            prog.li(10, 32'h8765_4321);
            prog.emit(SB(10, 22, 3));
            prog.emit(SH(10, 23, 6));
            prog.emit(SB(10, 24, 0));                    // evicts a dirty line
            prog.emit(LW(11, 22, 0)); prog.emit(LW(11, 23, 4)); prog.emit(LW(11, 24, 0));

            // ---------- 4. single-line writeback / invalidate ----------
            prog.li(20, 32'h0000_4000);
            prog.li(21, 32'hCAFE_F00D);
            prog.emit(SW(21, 20, 0));
            prog.emit(CSRRW(0, CSR_DWRITEBACK, 20));     // dirty -> written back
            prog.emit(CSRRW(0, CSR_DWRITEBACK, 20));     // already clean
            prog.emit(CSRRW(0, CSR_DINVALIDATE, 20));
            prog.emit(LW(12, 20, 0));                    // refill: must see CAFEF00D from memory
            prog.emit(CSRRW(0, CSR_DINVALIDATE, 20));    // invalidate a clean line
            prog.emit(LW(12, 20, 0));
            prog.li(20, 32'h0000_4800);
            prog.emit(CSRRW(13, CSR_DWRITEBACK, 20));    // line not in cache; rd gets 0
            prog.emit(CSRRW(13, CSR_DINVALIDATE, 20));

            // ---------- 5. full flush with many dirty lines ----------
            for (int k = 0; k < 16; k++) begin
                prog.li(20, 32'h0012_0000 + k*32);
                prog.li(21, 32'hF1A5_0000 + k);
                prog.emit(SW(21, 20, 0));
                prog.emit(SW(21, 20, 28));
            end
            prog.emit(CSRRW(14, CSR_DFLUSH, 0));
            for (int k = 0; k < 16; k++) begin
                prog.li(20, 32'h0012_0000 + k*32);
                prog.emit(CSRRW(0, CSR_DINVALIDATE, 20));
                prog.emit(LW(15, 20, 0));                // re-read from memory
                prog.emit(LW(16, 20, 28));
            end
            prog.emit(CSRRW(14, CSR_DFLUSH, 0));         // flush with nothing dirty

            // ---------- 6. write -> read hazards ----------
            prog.li(20, 32'h0000_5000);
            prog.li(21, 32'h0BAD_C0DE);
            prog.emit(SW(21, 20, 0)); prog.emit(LW(17, 20, 0));    // same word
            prog.emit(SB(17, 20, 1)); prog.emit(LW(18, 20, 0));
            prog.emit(SW(21, 20, 4)); prog.emit(LW(19, 20, 8));    // same line, other word
            prog.emit(SH(21, 20, 8)); prog.emit(LHU(19, 20, 8));
            prog.emit(SW(21, 20, 12)); prog.emit(SW(17, 20, 16)); prog.emit(LW(5, 20, 12)); prog.emit(LW(6, 20, 16));

            // ---------- 7. fences + I$ conflicts ----------
            prog.emit(FENCE());
            prog.emit(FENCE_I());                        // I$ flush, refetch from here
            prog.emit(ADDI(7, 0, 7));
            // three code blocks that alias the same I$ set as the call site
            blk = prog.here();
            for (int b = 1; b <= 3; b++) begin
                bit [31:0] target = (blk & 32'h0000_1FFF) + b * 32'h0001_0000 + 32'h0000_2000;
                bit [31:0] save;
                prog.li(25, target);
                prog.emit(JALR(1, 25, 0));
                save = prog.here();
                prog.org(target);
                prog.emit(ADDI(26, 0, b));
                prog.emit(JALR(0, 1, 0));
                prog.org(save);
            end
            prog.emit(FENCE_I());
            prog.emit(ADDI(8, 0, 8));

            prog.halt();
        endfunction
    endclass
endpackage
