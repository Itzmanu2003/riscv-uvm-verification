package riscv_muldiv_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"

    class riscv_muldiv_test extends uvm_test;
        `uvm_component_utils(riscv_muldiv_test)
        riscv_env env;

        function new(string name = "riscv_muldiv_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            bit [31:0] addr = 0;
            super.end_of_elaboration_phase(phase);
            // setup: x1=12, x2=4
            env.load_instr(addr, 32'h00c00093); addr += 4; // addi x1, x0, 12
            env.load_instr(addr, 32'h00400113); addr += 4; // addi x2, x0, 4
            // M-extension ops (funct7=0000001)
            env.load_instr(addr, 32'h022081b3); addr += 4; // mul  x3, x1, x2  -> 48
            env.load_instr(addr, 32'h0220c233); addr += 4; // div  x4, x1, x2  -> 3
            env.load_instr(addr, 32'h0220e2b3); addr += 4; // rem  x5, x1, x2  -> 0
            env.load_instr(addr, 32'h0000006f);            // jal x0, 0
            `uvm_info("MULDIV_TEST", "Preloaded mul/div/rem test", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #50000;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
