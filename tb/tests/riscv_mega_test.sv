package riscv_mega_test_pkg;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    `include "uvm_macros.svh"
    `include "rand_program.sv"

    class riscv_mega_test extends uvm_test;
        `uvm_component_utils(riscv_mega_test)
        riscv_env env;

        function new(string name = "riscv_mega_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            bit [31:0] addr = 0;
            bit [31:0] instr;
            bit [11:0] offset;
            int i;
            super.end_of_elaboration_phase(phase);

            // Preload data at many addresses (covers multiple cache lines)
            for (i = 0; i < 256; i++)
                env.load_data(32'h00001000 + i*4, 32'hA0000000 + i*7);

            // ===== 1: Setup with varied values =====
            env.load_instr(addr, 32'h00a00093); addr += 4;  // addi x1, x0, 10
            env.load_instr(addr, 32'h00300113); addr += 4;  // addi x2, x0, 3
            env.load_instr(addr, 32'h01400193); addr += 4;  // addi x3, x0, 20
            env.load_instr(addr, 32'hfff00213); addr += 4;  // addi x4, x0, -1 (0xFFFFFFFF)
            env.load_instr(addr, 32'h00700293); addr += 4;  // addi x5, x0, 7

            // ===== 2: All R-type ALU (10 ops) =====
            env.load_instr(addr, 32'h002081b3); addr += 4;  // add
            env.load_instr(addr, 32'h40208233); addr += 4;  // sub
            env.load_instr(addr, 32'h0020f2b3); addr += 4;  // and
            env.load_instr(addr, 32'h0020e333); addr += 4;  // or
            env.load_instr(addr, 32'h0020c3b3); addr += 4;  // xor
            env.load_instr(addr, 32'h0020a433); addr += 4;  // slt
            env.load_instr(addr, 32'h0020b4b3); addr += 4;  // sltu
            env.load_instr(addr, 32'h00209533); addr += 4;  // sll
            env.load_instr(addr, 32'h0020d5b3); addr += 4;  // srl
            env.load_instr(addr, 32'h4020d633); addr += 4;  // sra

            // ===== 3: All I-type ALU (9 ops) =====
            env.load_instr(addr, 32'h00508693); addr += 4;  // addi
            env.load_instr(addr, 32'h00f0f713); addr += 4;  // andi
            env.load_instr(addr, 32'h0ff0e793); addr += 4;  // ori
            env.load_instr(addr, 32'h0010c813); addr += 4;  // xori
            env.load_instr(addr, 32'h00a0a893); addr += 4;  // slti
            env.load_instr(addr, 32'h00a0b913); addr += 4;  // sltiu
            env.load_instr(addr, 32'h00209993); addr += 4;  // slli
            env.load_instr(addr, 32'h0020da13); addr += 4;  // srli
            env.load_instr(addr, 32'h4020da93); addr += 4;  // srai

            // ===== 4: MUL/DIV/REM (5 ops) =====
            env.load_instr(addr, 32'h02208b33); addr += 4;  // mul
            env.load_instr(addr, 32'h0220cbb3); addr += 4;  // div
            env.load_instr(addr, 32'h0220ec33); addr += 4;  // rem
            env.load_instr(addr, 32'h0220dcb3); addr += 4;  // divu
            env.load_instr(addr, 32'h0220fd33); addr += 4;  // remu

            // ===== 5: LUI + AUIPC =====
            env.load_instr(addr, 32'h12345db7); addr += 4;  // lui x27
            env.load_instr(addr, 32'h00001e17); addr += 4;  // auipc x28

            // ===== 6: RAW hazards (E1 + E2 forwarding) =====
            env.load_instr(addr, 32'h00500093); addr += 4;  // addi x1, x0, 5
            env.load_instr(addr, 32'h00108113); addr += 4;  // addi x2, x1, 1 -> E1
            env.load_instr(addr, 32'h001101b3); addr += 4;  // add x3, x2, x1 -> E1
            env.load_instr(addr, 32'h00a00213); addr += 4;  // addi x4, x0, 10
            env.load_instr(addr, 32'h00420293); addr += 4;  // addi x5, x4, 4 -> E1
            env.load_instr(addr, 32'h00528333); addr += 4;  // add x6, x5, x5 -> E1
            env.load_instr(addr, 32'h006303b3); addr += 4;  // add x7, x6, x6 -> E1
            // E2 forward
            env.load_instr(addr, 32'h01e00413); addr += 4;  // addi x8, x0, 30
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop
            env.load_instr(addr, 32'h008004b3); addr += 4;  // add x9, x0, x8 -> E2
            // Mixed chain
            env.load_instr(addr, 32'h00908533); addr += 4;  // add x10, x1, x9
            env.load_instr(addr, 32'h405505b3); addr += 4;  // sub x11, x10, x5 -> E1
            env.load_instr(addr, 32'h00b56633); addr += 4;  // or x12, x10, x11
            env.load_instr(addr, 32'h00c676b3); addr += 4;  // and x13, x12, x12 -> E1

            // ===== 7: WAW =====
            env.load_instr(addr, 32'h00100713); addr += 4;
            env.load_instr(addr, 32'h00200713); addr += 4;
            env.load_instr(addr, 32'h00300713); addr += 4;

            // ===== 8: MUL/DIV hazards =====
            env.load_instr(addr, 32'h00700793); addr += 4;  // addi x15, x0, 7
            env.load_instr(addr, 32'h00400813); addr += 4;  // addi x16, x0, 4
            env.load_instr(addr, 32'h030788b3); addr += 4;  // mul x17, x15, x16
            env.load_instr(addr, 32'h01188933); addr += 4;  // add x18, x17, x17 -> stall
            env.load_instr(addr, 32'h03084933); addr += 4;  // div x18, x16, x16
            env.load_instr(addr, 32'h01290933); addr += 4;  // add x18, x18, x18 -> stall

            // ===== 9: Load/Store (8 loads + 4 stores) =====
            env.load_instr(addr, 32'h00001a37); addr += 4;  // lui x20, 1 -> 0x1000
            env.load_instr(addr, 32'h000a2a83); addr += 4;  // lw x21, 0(x20)
            env.load_instr(addr, 32'h004a2b03); addr += 4;  // lw x22, 4(x20)
            env.load_instr(addr, 32'h008a2b83); addr += 4;  // lw x23, 8(x20)
            env.load_instr(addr, 32'h00ca2c03); addr += 4;  // lw x24, 12(x20)
            env.load_instr(addr, 32'h010a2c83); addr += 4;  // lw x25, 16(x20)
            env.load_instr(addr, 32'h014a2d03); addr += 4;  // lw x26, 20(x20)
            env.load_instr(addr, 32'h018a2d83); addr += 4;  // lw x27, 24(x20)
            env.load_instr(addr, 32'h01ca2e03); addr += 4;  // lw x28, 28(x20)
            env.load_instr(addr, 32'h015a2023); addr += 4;  // sw x21, 0(x20)
            env.load_instr(addr, 32'h016a2223); addr += 4;  // sw x22, 4(x20)
            env.load_instr(addr, 32'h017a2423); addr += 4;  // sw x23, 8(x20)
            env.load_instr(addr, 32'h018a2623); addr += 4;  // sw x24, 12(x20)

            // ===== 10: Load-use hazards =====
            env.load_instr(addr, 32'h000a2a83); addr += 4;  // lw x21, 0(x20)
            env.load_instr(addr, 32'h015a8b33); addr += 4;  // add x22, x21, x21 -> load-use
            env.load_instr(addr, 32'h004a2b83); addr += 4;  // lw x23, 4(x20)
            env.load_instr(addr, 32'h017b8c33); addr += 4;  // add x24, x23, x23 -> load-use

            // ===== 11: Loads from many cache lines (cache FSM exercise) =====
            for (i = 0; i < 32; i++) begin
                offset = i * 16;
                env.load_instr(addr, {offset, 5'd20, 3'b010, 5'd29, 7'b0000011});
                addr += 4;
            end

            // Stores to many addresses
            for (i = 0; i < 16; i++) begin
                offset = i * 4;
                env.load_instr(addr, {offset[11:5], 5'd29, 5'd20, 3'b010, offset[4:0], 7'b0100011});
                addr += 4;
            end

            // Back-to-back loads
            env.load_instr(addr, 32'h000a2e83); addr += 4;
            env.load_instr(addr, 32'h004a2f03); addr += 4;
            env.load_instr(addr, 32'h008a2f83); addr += 4;
            env.load_instr(addr, 32'h01ee8eb3); addr += 4;
            env.load_instr(addr, 32'h01fe8eb3); addr += 4;

            // ===== 12: CSR instructions =====
            env.load_instr(addr, {12'h340, 5'd1, 3'b001, 5'd6, 7'b1110011}); addr += 4;  // csrrw x6, mscratch, x1
            env.load_instr(addr, {12'h340, 5'd2, 3'b010, 5'd7, 7'b1110011}); addr += 4;  // csrrs x7, mscratch, x2
            env.load_instr(addr, {12'h340, 5'd3, 3'b011, 5'd8, 7'b1110011}); addr += 4;  // csrrc x8, mscratch, x3
            env.load_instr(addr, {12'h340, 5'b11111, 3'b101, 5'd9, 7'b1110011}); addr += 4;  // csrrwi x9, mscratch, 31
            env.load_instr(addr, {12'h340, 5'b00101, 3'b110, 5'd10, 7'b1110011}); addr += 4; // csrrsi x10, mscratch, 5
            env.load_instr(addr, {12'h340, 5'b01010, 3'b111, 5'd11, 7'b1110011}); addr += 4; // csrrci x11, mscratch, 10
            // mtvec and mstatus
            env.load_instr(addr, 32'h10000093); addr += 4;  // addi x1, x0, 256
            env.load_instr(addr, {12'h305, 5'd1, 3'b001, 5'd12, 7'b1110011}); addr += 4; // csrrw x12, mtvec, x1
            env.load_instr(addr, {12'h305, 5'd0, 3'b010, 5'd13, 7'b1110011}); addr += 4; // csrrs x13, mtvec, x0 (read)
            env.load_instr(addr, {12'h300, 5'd0, 3'b010, 5'd14, 7'b1110011}); addr += 4; // csrrs x14, mstatus, x0 (read)

            // ===== 13: Branches (all 6 types, taken + not-taken) =====
            env.load_instr(addr, 32'h00500093); addr += 4;  // addi x1, x0, 5
            env.load_instr(addr, 32'h00500113); addr += 4;  // addi x2, x0, 5
            env.load_instr(addr, 32'h00a00193); addr += 4;  // addi x3, x0, 10

            // BEQ taken (5==5, skip nop)
            env.load_instr(addr, 32'h00208463); addr += 4;  // beq x1, x2, +8
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop (skipped)
            env.load_instr(addr, 32'h00100e93); addr += 4;  // addi x29, x0, 1

            // BNE taken (5!=10)
            env.load_instr(addr, 32'h00309463); addr += 4;  // bne x1, x3, +8
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop (skipped)
            env.load_instr(addr, 32'h00200e93); addr += 4;  // addi x29, x0, 2

            // BLT taken (5<10 signed)
            env.load_instr(addr, 32'h0030c463); addr += 4;  // blt x1, x3, +8
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop (skipped)
            env.load_instr(addr, 32'h00300e93); addr += 4;  // addi x29, x0, 3

            // BGE taken (10>=5 signed)
            env.load_instr(addr, 32'h0011d463); addr += 4;  // bge x3, x1, +8
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop (skipped)
            env.load_instr(addr, 32'h00400e93); addr += 4;  // addi x29, x0, 4

            // BLTU taken (5<10 unsigned)
            env.load_instr(addr, 32'h0030e463); addr += 4;  // bltu x1, x3, +8
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop (skipped)
            env.load_instr(addr, 32'h00500e93); addr += 4;  // addi x29, x0, 5

            // BGEU taken (10>=5 unsigned)
            env.load_instr(addr, 32'h0011f463); addr += 4;  // bgeu x3, x1, +8
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop (skipped)
            env.load_instr(addr, 32'h00600e93); addr += 4;  // addi x29, x0, 6

            // Not-taken branches
            env.load_instr(addr, 32'h00308463); addr += 4;  // beq x1, x3, +8 (NOT taken 5!=10)
            env.load_instr(addr, 32'h00700e93); addr += 4;  // addi x29, x0, 7 (executes)
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop

            env.load_instr(addr, 32'h00209463); addr += 4;  // bne x1, x2, +8 (NOT taken 5==5)
            env.load_instr(addr, 32'h00800e93); addr += 4;  // addi x29, x0, 8 (executes)
            env.load_instr(addr, 32'h00000013); addr += 4;  // nop

            // ===== 14: JALR =====
            env.load_instr(addr, {20'h00000, 5'd30, 7'b0010111}); addr += 4;  // auipc x30, 0
            env.load_instr(addr, 32'h00cf0f13); addr += 4;  // addi x30, x30, 12
            env.load_instr(addr, {12'h000, 5'd30, 3'b000, 5'd29, 7'b1100111}); addr += 4; // jalr x29, x30, 0
            env.load_instr(addr, 32'h00900e93); addr += 4;  // addi x29, x0, 9

            // ===== 15: Write ALL registers x1-x31 =====
            for (i = 1; i <= 31; i++) begin
                env.load_instr(addr, {12'd1, 5'd0, 3'b000, i[4:0], 7'b0010011});
                addr += 4;
            end

            // ===== 16: Random instructions (more variety) =====
            for (i = 0; i < 30; i++) begin
                if ($urandom_range(0,1) == 0) instr = rand_program::rand_rtype();
                else                          instr = rand_program::rand_itype();
                env.load_instr(addr, instr); addr += 4;
            end

            // ===== END =====
            env.load_instr(addr, 32'h0000006f);
            `uvm_info("MEGA_TEST", $sformatf("Mega test: %0d instructions", addr/4), UVM_LOW)
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #800000;  // longer run for branches + cache + CSR + div latency
            phase.drop_objection(this);
        endtask
    endclass
endpackage
