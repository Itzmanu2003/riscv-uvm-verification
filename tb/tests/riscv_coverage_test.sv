package riscv_coverage_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"

    class riscv_coverage_test extends uvm_test;
        `uvm_component_utils(riscv_coverage_test)
        riscv_env env;

        function new(string name = "riscv_coverage_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            bit [31:0] addr = 0;
            int i;
            super.end_of_elaboration_phase(phase);

            // Preload data at many addresses (forces cache line fills + evictions)
            for (i = 0; i < 64; i++)
                env.load_data(32'h00001000 + i*4, 32'hA0000000 + i);

            // ===== Section 1: Setup registers with varied values =====
            env.load_instr(addr, 32'h00a00093); addr += 4;  // addi x1, x0, 10
            env.load_instr(addr, 32'h00300113); addr += 4;  // addi x2, x0, 3
            env.load_instr(addr, 32'h01400193); addr += 4;  // addi x3, x0, 20
            env.load_instr(addr, 32'hfff00213); addr += 4;  // addi x4, x0, -1 (0xFFFFFFFF)
            env.load_instr(addr, 32'h00000293); addr += 4;  // addi x5, x0, 0

            // ===== Section 2: All R-type ALU ops =====
            env.load_instr(addr, 32'h002081b3); addr += 4;  // add  x3, x1, x2
            env.load_instr(addr, 32'h40208233); addr += 4;  // sub  x4, x1, x2
            env.load_instr(addr, 32'h0020f2b3); addr += 4;  // and  x5, x1, x2
            env.load_instr(addr, 32'h0020e333); addr += 4;  // or   x6, x1, x2
            env.load_instr(addr, 32'h0020c3b3); addr += 4;  // xor  x7, x1, x2
            env.load_instr(addr, 32'h0020a433); addr += 4;  // slt  x8, x1, x2
            env.load_instr(addr, 32'h0020b4b3); addr += 4;  // sltu x9, x1, x2
            env.load_instr(addr, 32'h00209533); addr += 4;  // sll  x10, x1, x2
            env.load_instr(addr, 32'h0020d5b3); addr += 4;  // srl  x11, x1, x2
            env.load_instr(addr, 32'h4020d633); addr += 4;  // sra  x12, x1, x2

            // ===== Section 3: All I-type ALU ops =====
            env.load_instr(addr, 32'h00508693); addr += 4;  // addi  x13, x1, 5
            env.load_instr(addr, 32'h00f0f713); addr += 4;  // andi  x14, x1, 15
            env.load_instr(addr, 32'h0ff0e793); addr += 4;  // ori   x15, x1, 255
            env.load_instr(addr, 32'h0010c813); addr += 4;  // xori  x16, x1, 1
            env.load_instr(addr, 32'h00a0a893); addr += 4;  // slti  x17, x1, 10
            env.load_instr(addr, 32'h00a0b913); addr += 4;  // sltiu x18, x1, 10
            env.load_instr(addr, 32'h00209993); addr += 4;  // slli  x19, x1, 2
            env.load_instr(addr, 32'h0020da13); addr += 4;  // srli  x20, x1, 2
            env.load_instr(addr, 32'h4020da93); addr += 4;  // srai  x21, x1, 2

            // ===== Section 4: MUL/DIV =====
            env.load_instr(addr, 32'h02208b33); addr += 4;  // mul   x22, x1, x2
            env.load_instr(addr, 32'h0220cbb3); addr += 4;  // div   x23, x1, x2
            env.load_instr(addr, 32'h0220ec33); addr += 4;  // rem   x24, x1, x2
            env.load_instr(addr, 32'h0220dcb3); addr += 4;  // divu  x25, x1, x2
            env.load_instr(addr, 32'h0220fd33); addr += 4;  // remu  x26, x1, x2

            // ===== Section 5: LUI + AUIPC =====
            env.load_instr(addr, 32'h12345db7); addr += 4;  // lui   x27, 0x12345
            env.load_instr(addr, 32'h00001e17); addr += 4;  // auipc x28, 1

            // ===== Section 6: Load/store (exercises data cache + LSU) =====
            // lui x29, 1  -> x29 = 0x1000 (data base address)
            env.load_instr(addr, 32'h00001eb7); addr += 4;
            // Multiple loads from different addresses (fills cache lines)
            env.load_instr(addr, 32'h000ea083); addr += 4;  // lw x1, 0(x29)
            env.load_instr(addr, 32'h004ea103); addr += 4;  // lw x2, 4(x29)
            env.load_instr(addr, 32'h008ea183); addr += 4;  // lw x3, 8(x29)
            env.load_instr(addr, 32'h00cea203); addr += 4;  // lw x4, 12(x29)
            env.load_instr(addr, 32'h010ea283); addr += 4;  // lw x5, 16(x29)
            env.load_instr(addr, 32'h014ea303); addr += 4;  // lw x6, 20(x29)
            env.load_instr(addr, 32'h018ea383); addr += 4;  // lw x7, 24(x29)
            env.load_instr(addr, 32'h01cea403); addr += 4;  // lw x8, 28(x29)
            // Stores (writes back to memory — exercises write path)
            env.load_instr(addr, 32'h001ea023); addr += 4;  // sw x1, 0(x29)
            env.load_instr(addr, 32'h002ea223); addr += 4;  // sw x2, 4(x29)
            env.load_instr(addr, 32'h003ea423); addr += 4;  // sw x3, 8(x29)
            env.load_instr(addr, 32'h004ea623); addr += 4;  // sw x4, 12(x29)
            // More loads from different cache lines (force evictions)
            env.load_instr(addr, 32'h040ea483); addr += 4;  // lw x9, 64(x29)
            env.load_instr(addr, 32'h080ea503); addr += 4;  // lw x10, 128(x29)
            env.load_instr(addr, 32'h0c0ea583); addr += 4;  // lw x11, 192(x29)

            // ===== Section 7: Write to remaining registers x12-x31 =====
            for (i = 12; i <= 31; i++) begin
                env.load_instr(addr, {12'd1, 5'd1, 3'b000, i[4:0], 7'b0010011}); // addi x<i>, x1, 1
                addr += 4;
            end

            // ===== End: infinite loop =====
            env.load_instr(addr, 32'h0000006f);

            `uvm_info("COV_TEST", "Comprehensive coverage test loaded", UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #200000;  // long run for cache activity
            phase.drop_objection(this);
        endtask
    endclass
endpackage

