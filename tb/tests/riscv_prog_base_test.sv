// ============================================================================
// riscv_prog_base_test
// ----------------------------------------------------------------------------
// Base class for the program-driven tests added for code-coverage closure.
//   * derived tests override build_program() and fill `prog` (riscv_program)
//     using the riscv_asm_pkg mnemonics instead of hand-written hex
//   * the image is loaded into imem/dmem drivers + reference model
//   * end of test is DRAIN based: the test finishes when the reference model
//     has reached the end of the program AND the scoreboard has matched every
//     predicted write (+ a short quiet period), with a watchdog timeout.
//     -> no more guessing "#800000" run lengths.
//
// Plusargs:  +RISCV_TIMEOUT_NS=<n>   watchdog (default 3,000,000 ns)
// ============================================================================
package riscv_prog_base_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    `include "uvm_macros.svh"
    `include "rand_program.sv"

    // Register conventions used by the standard trap handler
    localparam bit [4:0] R_MCAUSE  = 5'd27;
    localparam bit [4:0] R_MEPC    = 5'd28;
    localparam bit [4:0] R_MTVAL   = 5'd29;
    localparam bit [4:0] R_MSTATUS = 5'd30;

    class riscv_prog_base_test extends uvm_test;
        `uvm_component_utils(riscv_prog_base_test)

        riscv_env     env;
        riscv_program prog;

        int unsigned timeout_ns   = 3_000_000;
        int unsigned quiet_ns     = 2_000;     // extra time after drain (catch stray writes)

        function new(string name = "riscv_prog_base_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            int unsigned v;
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
            if ($value$plusargs("RISCV_TIMEOUT_NS=%d", v)) timeout_ns = v;
        endfunction

        // -------- to be overridden --------
        virtual function void build_program();
            prog.li(1, 32'd42);
            prog.halt();
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            prog = new();
            build_program();
            foreach (prog.imem[a]) env.load_instr(a, prog.imem[a]);
            foreach (prog.dmem[a]) env.load_data(a, prog.dmem[a]);
            `uvm_info(get_type_name(), $sformatf("Program loaded: %0d instructions, %0d data words",
                      prog.imem.num(), prog.dmem.num()), UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            fork
                begin : drain
                    pre_drain();
                    while (!(env.ref_model.done && env.sb.pending_expected() == 0)) #100;
                    #(quiet_ns);
                    `uvm_info(get_type_name(), $sformatf("Drained at %0t", $time), UVM_LOW)
                end
                begin : watchdog
                    #(timeout_ns);
                    `uvm_error(get_type_name(), $sformatf(
                        "Watchdog timeout after %0d ns: ref_done=%0b, %0d writes still pending",
                        timeout_ns, env.ref_model.done, env.sb.pending_expected()))
                end
            join_any
            disable fork;
            phase.drop_objection(this);
        endtask

        // Hook: runs before the drain wait (inside the watchdog). Derived
        // tests use it to do something while the program runs.
        virtual task pre_drain();
        endtask

        // ==============================================================
        // Program-building helpers shared by derived tests
        // ==============================================================

        // Standard M-mode trap handler at `addr`:
        //   x27=mcause x28=mepc x29=mtval x30=mstatus ; mepc += 4 ; mret
        // Every CSR read is a register write -> checked by the scoreboard.
        function void emit_trap_handler(bit [31:0] addr);
            bit [31:0] save = prog.here();
            prog.org(addr);
            prog.emit(CSRR(R_MCAUSE,  CSR_MCAUSE));
            prog.emit(CSRR(R_MEPC,    CSR_MEPC));
            prog.emit(CSRR(R_MTVAL,   CSR_MTVAL));
            prog.emit(CSRR(R_MSTATUS, CSR_MSTATUS));
            prog.emit(ADDI(R_MEPC, R_MEPC, 4));
            prog.emit(CSRRW(5'd0, CSR_MEPC, R_MEPC));
            prog.emit(MRET());
            prog.org(save);
        endfunction

        // mtvec <= addr (uses `tmp`)
        function void set_mtvec(bit [31:0] addr, bit [4:0] tmp = 5'd31);
            prog.li(tmp, addr);
            prog.emit(CSRRW(5'd0, CSR_MTVEC, tmp));
        endfunction
    endclass
endpackage
