package riscv_loadstore_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"

    class riscv_loadstore_test extends uvm_test;
        `uvm_component_utils(riscv_loadstore_test)
        riscv_env env;

        function new(string name = "riscv_loadstore_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            bit [31:0] addr = 0;
            super.end_of_elaboration_phase(phase);

            // Preload some data at address 0x1000 (well within cacheable range)
            env.load_data(32'h00001000, 32'hDEADBEEF);
            env.load_data(32'h00001004, 32'h12345678);
            env.load_data(32'h00001008, 32'hCAFEBABE);

            // Program: store values, load them back, compute on them
            // addi x1, x0, 42
            env.load_instr(addr, 32'h02a00093); addr += 4;
            // lui x10, 0x1       -> x10 = 0x1000 (base address for data)
            env.load_instr(addr, 32'h00001537); addr += 4;
            // sw x1, 0(x10)     -> store 42 to addr 0x1000
            env.load_instr(addr, 32'h00152023); addr += 4;
            // lw x2, 0(x10)     -> load from 0x1000, x2 should be 42
            env.load_instr(addr, 32'h00052103); addr += 4;
            // lw x3, 4(x10)     -> load from 0x1004, x3 = 0x12345678 (preloaded)
            env.load_instr(addr, 32'h00452183); addr += 4;
            // lw x4, 8(x10)     -> load from 0x1008, x4 = 0xCAFEBABE (preloaded)
            env.load_instr(addr, 32'h00852203); addr += 4;
            // add x5, x2, x3
            env.load_instr(addr, 32'h003102b3); addr += 4;
            // jal x0, 0
            env.load_instr(addr, 32'h0000006f);

            `uvm_info("LS_TEST", "Preloaded load/store test", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #100000;    // longer run for cache line fills
            phase.drop_objection(this);
        endtask
    endclass
endpackage

