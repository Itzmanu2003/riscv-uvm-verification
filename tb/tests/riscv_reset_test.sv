// ============================================================================
// riscv_reset_test  (FSM reset-arc coverage + reset-recovery check)
// ----------------------------------------------------------------------------
// Runs the cache-stress program and switches on the reset injector in tb_top.
// The injector pulses reset once while the D$ controller is in each of its
// 10 non-reset states and while the I$ is in REFILL and RELOOKUP, covering
// the 12 "<state> -> reset" FSM arcs that normal tests can never reach.
//
// After every reset:
//   * drivers abandon any half-finished AXI burst (reset-aware drivers)
//   * the env flushes the scoreboard and restarts the reference model from
//     PC 0 with the memory contents as they really are (dirty cache lines
//     are legitimately lost by a reset)
// After the LAST reset the program must run to completion with 0 mismatches
// -> proves the core + caches recover cleanly from reset in any state.
// ============================================================================
package riscv_reset_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_asm_pkg::*;
    import riscv_prog_base_pkg::*;
    import riscv_cache_stress_test_pkg::*;
    `include "uvm_macros.svh"

    class riscv_reset_test extends riscv_cache_stress_test;
        `uvm_component_utils(riscv_reset_test)

        virtual reset_ctrl_if rst_ctrl;

        function new(string name = "riscv_reset_test", uvm_component parent = null);
            super.new(name, parent);
            timeout_ns = 10_000_000;
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual reset_ctrl_if)::get(this, "", "reset_ctrl_vif", rst_ctrl))
                `uvm_fatal("RESET_TEST", "No reset_ctrl_vif in config_db")
        endfunction

        virtual task pre_drain();
            rst_ctrl.inject_en = 1;
            `uvm_info("RESET_TEST", "Reset injector enabled", UVM_LOW)
            wait (rst_ctrl.all_done);
            rst_ctrl.inject_en = 0;
            wait (env.rst_vif.rst_n === 1'b1);        // last pulse released
            #100;                                      // let the env restart the model
            `uvm_info("RESET_TEST", $sformatf("All %0d reset targets hit (dcache=%b icache=%b); final run continues",
                      rst_ctrl.n_injected, rst_ctrl.dcache_hit, rst_ctrl.icache_hit), UVM_LOW)
        endtask

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            if (!rst_ctrl.all_done)
                `uvm_error("RESET_TEST", $sformatf("Not all reset targets were reached: dcache=%b icache=%b",
                           rst_ctrl.dcache_hit, rst_ctrl.icache_hit))
        endfunction
    endclass
endpackage
