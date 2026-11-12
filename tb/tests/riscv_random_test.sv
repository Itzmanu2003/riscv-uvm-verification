package riscv_random_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"
    `include "rand_program.sv"

    class riscv_random_test extends uvm_test;
        `uvm_component_utils(riscv_random_test)
        riscv_env env;

        function new(string name = "riscv_random_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            bit [31:0] addr = 0;
            bit [31:0] instr;
            super.end_of_elaboration_phase(phase);

            // Setup: seed registers with non-zero values
            env.load_instr(addr, 32'h00a00093); addr += 4; // addi x1, x0, 10
            env.load_instr(addr, 32'h01400113); addr += 4; // addi x2, x0, 20
            env.load_instr(addr, 32'h00500193); addr += 4; // addi x3, x0, 5

            // Write to ALL registers x4..x31 (ensures register coverage)
            for (int rd = 4; rd <= 31; rd++) begin
                instr = {12'd1, 5'd1, 3'b000, rd[4:0], 7'b0010011}; // addi x<rd>, x1, 1
                env.load_instr(addr, instr); addr += 4;
            end

            // Include a LUI (covers that opcode bin)
            env.load_instr(addr, {20'h12345, 5'd5, 7'b0110111}); addr += 4;

            // 20 random R/I-type instructions (including MUL/DIV now)
            for (int i = 0; i < 20; i++) begin
                if ($urandom_range(0,1) == 0) instr = rand_program::rand_rtype();
                else                          instr = rand_program::rand_itype();
                env.load_instr(addr, instr); addr += 4;
            end

            // End: infinite loop
            env.load_instr(addr, 32'h0000006f);

            `uvm_info("RAND_TEST", "Coverage-optimized random program loaded", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #80000;
            phase.drop_objection(this);
        endtask
    endclass
endpackage
