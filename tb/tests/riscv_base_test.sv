package riscv_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"

    class riscv_base_test extends uvm_test;
        `uvm_component_utils(riscv_base_test)
        riscv_env env;

        function new(string name = "riscv_base_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            //              ADDRESS         INSTRUCTION                    what it does
            env.load_instr(32'h00000000, 32'h00a00093); // addi x1, x0, 10   -> x1 = 10
            env.load_instr(32'h00000004, 32'h00300113); // addi x2, x0, 3    -> x2 = 3
            env.load_instr(32'h00000008, 32'h002081b3); // add  x3, x1, x2   -> x3 = 13
            env.load_instr(32'h0000000c, 32'h40208233); // sub  x4, x1, x2   -> x4 = 7
            env.load_instr(32'h00000010, 32'h0020f2b3); // and  x5, x1, x2   -> x5 = 2
            env.load_instr(32'h00000014, 32'h0020e333); // or   x6, x1, x2   -> x6 = 11
            env.load_instr(32'h00000018, 32'h0020c3b3); // xor  x7, x1, x2   -> x7 = 9
            env.load_instr(32'h0000001c, 32'h0000006f); // jal  x0, 0        -> loop
            `uvm_info("RISCV_TEST", "Preloaded program: add/sub/and/or/xor test", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            `uvm_info("RISCV_TEST", "Running multi-instruction test", UVM_LOW)
            #50000;
            phase.drop_objection(this);
        endtask
    endclass
endpackage

