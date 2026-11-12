// ============================================================================
// riscv_trap_test
// ----------------------------------------------------------------------------
// Synchronous exceptions + MRET:
//   * ECALL (mcause 11), EBREAK (3)
//   * misaligned LH/LHU/LW (4) and SH/SW (6)        - mtval = faulting address
//   * illegal instructions (2) of many flavours      - mtval = instruction bits
//   * each trap taken once with mstatus.MIE=0 and once with MIE=1
//     (checks MPIE/MIE/MPP stacking and MRET restore)
//   * a far-away second handler that skips 2 instructions (mepc += 8)
//   * traps right behind DIV/MUL/loads/taken branches (pipeline flush with
//     long-latency work in flight), an ECALL loop
//   * software read/write of mepc/mcause/mtval, MRET without a trap
// Every handler CSR read lands in a register, so the scoreboard checks
// mcause / mepc / mtval / mstatus of every single trap.
// Targets: riscv_csr / riscv_csr_regfile exception paths, pipe_ctrl flush,
//          riscv_lsu misaligned detection, trap_cg / mret_cg.
// ============================================================================
package riscv_trap_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    `include "uvm_macros.svh"

    class riscv_trap_test extends riscv_prog_base_test;
        `uvm_component_utils(riscv_trap_test)

        localparam bit [31:0] HANDLER  = 32'h0000_2000;
        localparam bit [31:0] HANDLER2 = 32'h8000_1000;   // far handler (PC high bits)

        function new(string name = "riscv_trap_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        // Illegal encodings (none of them is decoded by the DUT)
        function void emit_illegal_set();
            prog.emit(32'h0000_0000);                                           // all zeros
            prog.emit(32'hFFFF_FFFF);                                           // all ones
            prog.emit({7'b0000010, 5'd2, 5'd1, 3'b000, 5'd9, 7'b0110011});      // OP funct7=0x02
            prog.emit({7'b0100000, 5'd3, 5'd1, 3'b001, 5'd9, 7'b0010011});      // SLLI funct7=0x20
            prog.emit({12'h000,    5'd6, 3'b011, 5'd9, 7'b0000011});            // LD (RV64 only)
            prog.emit({7'b0000000, 5'd1, 5'd6, 3'b011, 5'd0, 7'b0100011});      // SD (RV64 only)
            prog.emit({7'b0000000, 5'd1, 5'd1, 3'b010, 5'b01000, 7'b1100011});  // BRANCH funct3=2
            prog.emit({12'h000,    5'd1, 3'b001, 5'd9, 7'b1100111});            // JALR funct3=1
            prog.emit({12'h300,    5'd0, 3'b100, 5'd9, 7'b1110011});            // SYSTEM funct3=4
            prog.emit({12'h000,    5'd0, 3'b010, 5'd0, 7'b0001111});            // MISC-MEM funct3=2
            prog.emit(32'h0000_000B);                                           // custom-0 opcode
        endfunction

        // One of every trap cause
        function void emit_trap_set();
            prog.emit(ECALL());
            prog.emit(EBREAK());
            prog.emit(LH (7, 6, 1));          // misaligned loads  (x6 = aligned base)
            prog.emit(LHU(7, 6, 3));
            prog.emit(LW (7, 6, 2));
            prog.emit(LW (7, 6, 1));
            prog.emit(LW (7, 6, 3));
            prog.emit(SH (5, 6, 1));          // misaligned stores
            prog.emit(SH (5, 6, 3));
            prog.emit(SW (5, 6, 1));
            prog.emit(SW (5, 6, 2));
            prog.emit(SW (5, 6, 3));
            emit_illegal_set();
            prog.emit(ADD(8, 7, 0));          // x7 must be untouched by the faulting loads
            prog.emit(LW (9, 6, 0));          // ...and memory untouched by faulting stores
        endfunction

        virtual function void build_program();
            bit [31:0] loop_top;

            emit_trap_handler(HANDLER);

            // second handler: record cause/epc, skip faulting instr + the next one
            prog.org(HANDLER2);
            prog.emit(CSRR(R_MCAUSE, CSR_MCAUSE));
            prog.emit(CSRR(R_MEPC,   CSR_MEPC));
            prog.emit(ADDI(R_MEPC, R_MEPC, 8));
            prog.emit(CSRRW(5'd0, CSR_MEPC, R_MEPC));
            prog.emit(MRET());
            prog.org(32'h0);

            prog.data(32'h0000_3000, 32'hCAFE_F00D);
            prog.data(32'h0000_3004, 32'h1357_9BDF);

            set_mtvec(HANDLER);
            prog.li(5, 32'hA5A5_5A5A);
            prog.li(6, 32'h0000_3000);
            prog.li(7, 32'h0000_1234);

            // ---------- A: all causes with MIE = 0 ----------
            emit_trap_set();
            prog.emit(CSRR(9, CSR_MSTATUS));                 // after MRET: MIE=0 MPIE=1 MPP=0

            // ---------- B: all causes with MIE = 1 ----------
            prog.emit(CSRRSI(0, CSR_MSTATUS, 5'd8));         // MIE=1 (no interrupt sources)
            prog.emit(CSRR(9, CSR_MSTATUS));
            emit_trap_set();
            prog.emit(CSRR(9, CSR_MSTATUS));                 // MIE restored to 1 by MRET
            prog.emit(CSRRCI(0, CSR_MSTATUS, 5'd8));

            // ---------- C: far handler, mepc += 8 ----------
            set_mtvec(HANDLER2, 31);
            prog.li(10, 0); prog.li(11, 0);
            prog.emit(ECALL());
            prog.emit(ADDI(10, 10, 1));                      // skipped
            prog.emit(ADDI(11, 11, 1));                      // executed
            prog.emit(EBREAK());
            prog.emit(ADDI(10, 10, 1));                      // skipped
            prog.emit(ADDI(11, 11, 1));
            prog.emit(LW(12, 6, 2));                         // misaligned
            prog.emit(ADDI(10, 10, 1));                      // skipped
            prog.emit(ADDI(11, 11, 1));
            set_mtvec(HANDLER, 31);

            // ---------- D: traps next to long-latency / control-flow ----------
            prog.li(13, 32'h7FFF_FFF1); prog.li(14, 32'hFFFF_FFFD);
            prog.emit(DIV (12, 13, 14)); prog.emit(ECALL());           // div completes first
            prog.emit(MUL (12, 12, 12)); prog.emit(EBREAK());
            prog.emit(MULHU(15, 13, 14)); prog.emit(LH(16, 6, 1));     // mulhu + misaligned
            prog.emit(LW  (15, 6, 4));   prog.emit(ECALL());
            prog.emit(ADD (16, 15, 15));                               // use after trap return
            prog.emit(BEQ (0, 0, 8));    prog.emit(NOP());  prog.emit(ECALL());  // trap at branch target
            prog.emit(JAL (1, 8));       prog.emit(NOP());  prog.emit(EBREAK()); // trap at jump target
            prog.emit(SW  (13, 6, 8));   prog.emit(SB(14, 6, 9));  prog.emit(32'h0000_0000);
            prog.emit(LW  (17, 6, 8));                                 // stores before trap committed
            // ECALL loop
            prog.li(18, 5);
            loop_top = prog.here();
            prog.emit(ECALL());
            prog.emit(ADDI(18, 18, -1));
            prog.emit(BNE (18, 0, int'(loop_top) - int'(prog.here())));

            // ---------- E: software access to trap CSRs, MRET without trap ----------
            prog.li(19, 32'hFFFF_FFFF);
            prog.emit(CSRRW(20, CSR_MEPC,   19)); prog.emit(CSRR(20, CSR_MEPC));
            prog.emit(CSRRW(20, CSR_MCAUSE, 19)); prog.emit(CSRR(20, CSR_MCAUSE));   // masked 0x8000000F
            prog.emit(CSRRW(20, CSR_MTVAL,  19)); prog.emit(CSRR(20, CSR_MTVAL));
            prog.emit(CSRRW(20, CSR_MCAUSE, 0));  prog.emit(CSRRW(20, CSR_MTVAL, 0));
            // MRET with MPIE=1 and with MPIE=0, to an address computed in software
            for (int k = 0; k < 2; k++) begin
                prog.li(21, 32'h80);
                if (k == 0) prog.emit(CSRRS(0, CSR_MSTATUS, 21));     // MPIE=1
                else        prog.emit(CSRRC(0, CSR_MSTATUS, 21));     // MPIE=0
                prog.emit(AUIPC(22, 0));
                prog.emit(ADDI(22, 22, 20));                           // -> after the skipped addi
                prog.emit(CSRRW(0, CSR_MEPC, 22));
                prog.emit(MRET());
                prog.emit(ADDI(23, 0, 77));                            // skipped by MRET
                prog.emit(CSRR(24, CSR_MSTATUS));                      // MIE = old MPIE
                prog.emit(CSRRCI(0, CSR_MSTATUS, 5'd8));
            end
            prog.emit(CSRR(25, CSR_MISA));
            prog.emit(CSRR(26, CSR_MHARTID));

            prog.halt();
        endfunction
    endclass
endpackage
