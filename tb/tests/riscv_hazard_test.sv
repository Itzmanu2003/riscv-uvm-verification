package riscv_hazard_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"

    class riscv_hazard_test extends uvm_test;
        `uvm_component_utils(riscv_hazard_test)
        riscv_env env;

        function new(string name = "riscv_hazard_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            bit [31:0] addr = 0;
            bit [11:0] offset;
            int i;
            super.end_of_elaboration_phase(phase);

            // Preload data for load-use tests
            for (i = 0; i < 64; i++)
                env.load_data(32'h00001000 + i*4, 32'h10000000 + i*100);

            // ===== PART 1: RAW hazards — E1 forwarding =====
            env.load_instr(addr, 32'h00500093); addr += 4;  // addi x1, x0, 5
            env.load_instr(addr, 32'h00108113); addr += 4;  // addi x2, x1, 1     -> x2=6
            env.load_instr(addr, 32'h001101b3); addr += 4;  // add  x3, x2, x1    -> x3=11

            // RAW: triple chain (E1 forward each step)
            env.load_instr(addr, 32'h00a00213); addr += 4;  // addi x4, x0, 10
            env.load_instr(addr, 32'h00420293); addr += 4;  // addi x5, x4, 4     -> x5=14
            env.load_instr(addr, 32'h00528333); addr += 4;  // add  x6, x5, x5    -> x6=28
            env.load_instr(addr, 32'h006303b3); addr += 4;  // add  x7, x6, x6    -> x7=56

            // RAW: E2 forwarding (1 NOP gap)
            env.load_instr(addr, 32'h01e00413); addr += 4;  // addi x8, x0, 30
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop
            env.load_instr(addr, 32'h008004b3); addr += 4;  // add  x9, x0, x8    -> x9=30

            // RAW: SUB uses ADD result
            env.load_instr(addr, 32'h00908533); addr += 4;  // add  x10, x1, x9   -> x10=35
            env.load_instr(addr, 32'h405505b3); addr += 4;  // sub  x11, x10, x5  -> x11=21

            // RAW: logical ops with dependency
            env.load_instr(addr, 32'h00b56633); addr += 4;  // or   x12, x10, x11
            env.load_instr(addr, 32'h00c676b3); addr += 4;  // and  x13, x12, x12

            // ===== PART 2: WAW — same register 3x =====
            env.load_instr(addr, 32'h00100713); addr += 4;  // addi x14, x0, 1
            env.load_instr(addr, 32'h00200713); addr += 4;  // addi x14, x0, 2
            env.load_instr(addr, 32'h00300713); addr += 4;  // addi x14, x0, 3

            // ===== PART 3: MUL/DIV with dependencies =====
            env.load_instr(addr, 32'h00700793); addr += 4;  // addi x15, x0, 7
            env.load_instr(addr, 32'h00400813); addr += 4;  // addi x16, x0, 4
            env.load_instr(addr, 32'h030788b3); addr += 4;  // mul  x17, x15, x16 -> 28
            env.load_instr(addr, 32'h01188933); addr += 4;  // add  x18, x17, x17 -> 56

            // DIV dependency (long latency)
            env.load_instr(addr, 32'h03084933); addr += 4;  // div  x18, x16, x16 -> 1
            env.load_instr(addr, 32'h01290933); addr += 4;  // add  x18, x18, x18 -> 2

            // ===== PART 4: Load-use hazard (pipeline stall) =====
            env.load_instr(addr, 32'h00001a37); addr += 4;  // lui x20, 1 -> 0x1000
            env.load_instr(addr, 32'h000a2a83); addr += 4;  // lw x21, 0(x20)
            env.load_instr(addr, 32'h015a8b33); addr += 4;  // add x22, x21, x21  -> load-use!

            env.load_instr(addr, 32'h004a2b83); addr += 4;  // lw x23, 4(x20)
            env.load_instr(addr, 32'h017b8c33); addr += 4;  // add x24, x23, x23  -> load-use!

            env.load_instr(addr, 32'h008a2c83); addr += 4;  // lw x25, 8(x20)
            env.load_instr(addr, 32'h019ccd33); addr += 4;  // sub x26, x25, x25  -> load-use -> 0

            // ===== PART 5: Stores (exercises write path, no forwarding issues) =====
            env.load_instr(addr, 32'h015a0023); addr += 4;  // sw x21, 0(x20)
            env.load_instr(addr, 32'h017a0223); addr += 4;  // sw x23, 4(x20)

            // ===== PART 6: Loads from many cache lines (cache FSM coverage) =====
            for (i = 0; i < 16; i++) begin
                offset = i * 16;
                env.load_instr(addr, {offset, 5'd20, 3'b010, 5'd27, 7'b0000011});
                addr += 4;
            end

            // ===== PART 7: Stores to many addresses =====
            for (i = 0; i < 8; i++) begin
                offset = i * 4;
                env.load_instr(addr, {offset[11:5], 5'd27, 5'd20, 3'b010, offset[4:0], 7'b0100011});
                addr += 4;
            end

            // ===== PART 8: Back-to-back loads + use =====
            env.load_instr(addr, 32'h000a2e83); addr += 4;  // lw x29, 0(x20)
            env.load_instr(addr, 32'h004a2f03); addr += 4;  // lw x30, 4(x20)
            env.load_instr(addr, 32'h008a2f83); addr += 4;  // lw x31, 8(x20)
            env.load_instr(addr, 32'h01ee8eb3); addr += 4;  // add x29, x29, x30
            env.load_instr(addr, 32'h01fe8eb3); addr += 4;  // add x29, x29, x31

            // ===== End =====
            env.load_instr(addr, 32'h0000006f);

            `uvm_info("HAZARD_TEST", $sformatf("Hazard test: %0d instructions", addr/4), UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #300000;
            phase.drop_objection(this);
        endtask
    endclass
endpackage


