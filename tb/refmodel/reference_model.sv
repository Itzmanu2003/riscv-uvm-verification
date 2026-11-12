// ============================================================================
// reference_model - instruction-level golden model (RV32IM + Zicsr + M-mode traps)
// ----------------------------------------------------------------------------
// Executes the preloaded program and publishes every architectural register
// write on expected_ap (format {27'b0, rd, value}) for the in-order scoreboard.
//
// Supported:
//   * RV32I   : all ALU/branch/jump/LUI/AUIPC, LB/LH/LW/LBU/LHU, SB/SH/SW
//   * RV32M   : MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
//               (div-by-zero and MIN/-1 overflow per the ISA spec)
//   * Zicsr   : CSRRW/S/C(+I) on the CSRs implemented by riscv_csr_regfile.v
//               with SUPPORT_SUPER=0 (incl. write masks). Unimplemented CSRs
//               read as 0 and ignore writes (DUT behaviour - no trap).
//   * Traps   : ECALL (cause 11), EBREAK (3), illegal instruction (2),
//               misaligned load (4) / store (6); MRET.
//               mepc/mcause/mtval/mstatus(MIE,MPIE,MPP) updated exactly as the
//               DUT's CSR file does; next PC = mtvec (direct mode).
//   * FENCE / FENCE.I / D$ maintenance CSRs (0x3A0-0x3A2): no architectural effect.
//
// Program end: a self-loop (e.g. "jal x0, 0") or a PC with no instruction.
// Mid-run DUT reset: the env calls restart(), the program re-runs from PC 0.
// ============================================================================
class reference_model extends uvm_component;
    `uvm_component_utils(reference_model)

    // ---------------- architectural state ----------------
    bit [31:0] regs [32];
    bit [31:0] imem [bit [31:0]];
    bit [31:0] dmem [bit [31:0]];          // word store, key = {addr[31:2],2'b00}

    // Implemented machine-mode CSRs (riscv_csr_regfile.v, SUPPORT_SUPER=0)
    bit [31:0] csr_mstatus, csr_mtvec, csr_mepc, csr_mcause, csr_mtval;
    bit [31:0] csr_mscratch, csr_mie, csr_mip;

    localparam bit [31:0] IRQ_MASK    = 32'h0000_0AAA;   // `IRQ_MASK in riscv_defs.v
    localparam bit [31:0] MCAUSE_MASK = 32'h8000_000F;
    localparam bit [31:0] MISA_VALUE  = 32'h4000_1100;   // RV32 | I | M
    localparam int        SR_MIE      = 3;
    localparam int        SR_MPIE     = 7;
    localparam bit [31:0] CAUSE_ILLEGAL          = 32'd2;
    localparam bit [31:0] CAUSE_BREAKPOINT       = 32'd3;
    localparam bit [31:0] CAUSE_MISALIGNED_LOAD  = 32'd4;
    localparam bit [31:0] CAUSE_MISALIGNED_STORE = 32'd6;
    localparam bit [31:0] CAUSE_ECALL_M          = 32'd11;

    // ---------------- TLM ----------------
    uvm_analysis_port #(bit [63:0])      expected_ap;   // -> scoreboard
    uvm_analysis_port #(riscv_exec_item) exec_ap;       // -> functional coverage

    // ---------------- control / statistics ----------------
    bit [31:0]   next_pc;
    int unsigned max_steps = 20000;      // override with +REF_MAX_STEPS=<n>
    bit          done;                   // set when the program has finished
    event        done_ev;
    int unsigned n_steps, n_writes, n_traps, n_mret;
    int unsigned n_restarts;
    bit          restart_pending;
    int unsigned trap_hist [int unsigned];

    function new(string name = "reference_model", uvm_component parent = null);
        super.new(name, parent);
        expected_ap = new("expected_ap", this);
        exec_ap     = new("exec_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        int unsigned v;
        super.build_phase(phase);
        foreach (regs[i]) regs[i] = 32'h0;
        csr_mstatus = 0; csr_mtvec = 0; csr_mepc = 0; csr_mcause = 0;
        csr_mtval   = 0; csr_mscratch = 0; csr_mie = 0; csr_mip = 0;
        if ($value$plusargs("REF_MAX_STEPS=%d", v)) max_steps = v;
    endfunction

    function void load_instr(bit [31:0] addr, bit [31:0] instr);
        imem[addr] = instr;
    endfunction

    function void load_data(bit [31:0] addr, bit [31:0] data);
        dmem[{addr[31:2], 2'b00}] = data;
    endfunction

    task run_phase(uvm_phase phase);
        #3000;
        forever begin
            run_program();
            done = 1;
            -> done_ev;
            `uvm_info("REF_MODEL", $sformatf("Program finished: %0d instructions, %0d reg writes, %0d traps, %0d mret",
                      n_steps, n_writes, n_traps, n_mret), UVM_LOW)
            wait (restart_pending);              // only a mid-run reset brings us back
        end
    endtask

    // Execute from the reset vector until the program ends. A restart()
    // (DUT reset in the middle of the run) sends the PC back to 0.
    task run_program();
        bit [31:0] pc = 32'h0;
        bit [31:0] instr;
        int unsigned run_steps = 0;
        restart_pending = 0;
        done = 0;
        forever begin
            if (restart_pending) begin
                restart_pending = 0;
                pc = 32'h0;
                run_steps = 0;
            end
            if (!imem.exists(pc)) begin
                `uvm_info("REF_MODEL", $sformatf("No instruction at pc=0x%08h - program end", pc), UVM_MEDIUM)
                break;
            end
            instr = imem[pc];
            predict(pc, instr);
            n_steps++;
            run_steps++;
            if (next_pc == pc) break;                  // self-loop: end of program
            if (run_steps >= max_steps) begin
                `uvm_warning("REF_MODEL", $sformatf("Step limit %0d reached at pc=0x%08h", max_steps, pc))
                break;
            end
            pc = next_pc;
            #10;
        end
    endtask

    // Called by the env when the DUT comes out of a MID-RUN reset:
    // architectural state back to reset values, data memory = what the
    // memory model really holds now (dirty cache lines were lost by the reset).
    function void restart(bit [31:0] mem_now [bit [31:0]]);
        foreach (regs[i]) regs[i] = 32'h0;
        csr_mstatus = 0; csr_mtvec = 0; csr_mepc = 0; csr_mcause = 0;
        csr_mtval   = 0; csr_mscratch = 0; csr_mie = 0; csr_mip = 0;
        dmem.delete();
        foreach (mem_now[a]) dmem[a] = mem_now[a];
        n_restarts++;
        done = 0;
        restart_pending = 1;
        `uvm_info("REF_MODEL", $sformatf("Restart #%0d after mid-run DUT reset (%0d memory words reloaded)",
                  n_restarts, dmem.num()), UVM_LOW)
    endfunction

    // =================================================================
    // Helpers
    // =================================================================

    // Spec-legal RV32IM + Zicsr + Zifencei + M-mode system encodings.
    // Anything else raises an illegal-instruction trap.
    function bit is_legal(bit [31:0] instr);
        bit [6:0] op = instr[6:0];
        bit [2:0] f3 = instr[14:12];
        bit [6:0] f7 = instr[31:25];
        case (op)
            7'b0110111, 7'b0010111, 7'b1101111: return 1;             // LUI AUIPC JAL
            7'b1100111: return (f3 == 3'b000);                         // JALR
            7'b1100011: return (f3 != 3'b010 && f3 != 3'b011);         // BRANCH
            7'b0000011: return (f3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101});
            7'b0100011: return (f3 inside {3'b000, 3'b001, 3'b010});
            7'b0010011: begin                                          // OP-IMM
                if (f3 == 3'b001) return (f7 == 7'b0000000);           // SLLI
                if (f3 == 3'b101) return (f7 == 7'b0000000 || f7 == 7'b0100000);
                return 1;
            end
            7'b0110011: return (f7 == 7'b0000000 || f7 == 7'b0000001 ||
                                (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101)));
            7'b0001111: return (f3 == 3'b000 || f3 == 3'b001);         // FENCE / FENCE.I
            7'b1110011: begin                                          // SYSTEM
                if (f3 != 3'b000 && f3 != 3'b100) return 1;            // CSR*
                return (instr == 32'h0000_0073 ||                      // ECALL
                        instr == 32'h0010_0073 ||                      // EBREAK
                        instr == 32'h3020_0073 ||                      // MRET
                        instr == 32'h1050_0073);                       // WFI (no-op)
            end
            default: return 0;
        endcase
    endfunction

    function bit [31:0] csr_read(bit [11:0] addr);
        case (addr)
            12'h300: return csr_mstatus;
            12'h301: return MISA_VALUE;
            12'h304: return csr_mie & IRQ_MASK;
            12'h305: return csr_mtvec;
            12'h340: return csr_mscratch;
            12'h341: return csr_mepc;
            12'h342: return csr_mcause & MCAUSE_MASK;
            12'h343: return csr_mtval;
            12'h344: return csr_mip & IRQ_MASK;
            12'hF14: return 32'h0;                       // mhartid (CORE_ID = 0)
            12'hC00, 12'hC01, 12'hC81: begin             // mcycle/mtime(h): not predictable
                `uvm_warning("REF_MODEL", $sformatf("Read of free-running counter CSR 0x%03h is not predicted", addr))
                return 32'h0;
            end
            default: return 32'h0;                       // unimplemented CSR
        endcase
    endfunction

    function void csr_write(bit [11:0] addr, bit [31:0] data);
        case (addr)
            12'h300: csr_mstatus  = data;
            12'h304: csr_mie      = data & IRQ_MASK;
            12'h305: csr_mtvec    = data;
            12'h340: csr_mscratch = data;
            12'h341: csr_mepc     = data;
            12'h342: csr_mcause   = data & MCAUSE_MASK;
            12'h343: csr_mtval    = data;
            12'h344: csr_mip      = data & IRQ_MASK;
            default: ;                                   // read-only / unimplemented
        endcase
    endfunction

    // Enter machine-mode trap handler; returns the handler PC
    function bit [31:0] take_trap(bit [31:0] pc, bit [31:0] cause, bit [31:0] tval);
        csr_mstatus[SR_MPIE]  = csr_mstatus[SR_MIE];
        csr_mstatus[12:11]    = 2'b11;                   // MPP = M
        csr_mstatus[SR_MIE]   = 1'b0;
        csr_mepc              = pc;
        csr_mcause            = cause & MCAUSE_MASK;
        csr_mtval             = tval;
        n_traps++;
        trap_hist[cause]++;
        `uvm_info("REF_MODEL", $sformatf("TRAP: cause=%0d pc=0x%08h tval=0x%08h -> mtvec=0x%08h",
                  cause, pc, tval, csr_mtvec), UVM_MEDIUM)
        return csr_mtvec;
    endfunction

    function bit [31:0] mem_read_word(bit [31:0] addr);
        bit [31:0] wa = {addr[31:2], 2'b00};
        return dmem.exists(wa) ? dmem[wa] : 32'h0;
    endfunction

    function void mem_write(bit [31:0] addr, bit [31:0] data, int unsigned size);
        bit [31:0] wa = {addr[31:2], 2'b00};
        bit [31:0] w  = dmem.exists(wa) ? dmem[wa] : 32'h0;
        for (int unsigned i = 0; i < size; i++) begin
            int unsigned lane = addr[1:0] + i;
            w[lane*8 +: 8] = data[i*8 +: 8];
        end
        dmem[wa] = w;
    endfunction

    // =================================================================
    // Instruction semantics
    // =================================================================
    function void predict(bit [31:0] pc, bit [31:0] instr);
        bit [6:0]  opcode = instr[6:0];
        bit [4:0]  rd     = instr[11:7];
        bit [2:0]  funct3 = instr[14:12];
        bit [4:0]  rs1    = instr[19:15];
        bit [4:0]  rs2    = instr[24:20];
        bit [6:0]  funct7 = instr[31:25];
        bit [31:0] imm_i  = {{20{instr[31]}}, instr[31:20]};
        bit [31:0] imm_s  = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        bit [31:0] imm_b  = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
        bit [31:0] imm_j  = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
        bit [31:0] a      = regs[rs1];
        bit [31:0] b      = regs[rs2];
        int        sa     = a;            // signed views (avoid $signed() inside ?: - see note)
        int        sb     = b;
        int        simm   = imm_i;
        bit [31:0] result = 0;
        bit        wrote  = 0;
        bit [31:0] mem_addr = 0;
        bit [31:0] word;
        bit [11:0] csr_addr;
        bit [31:0] csr_old, csr_src;
        int unsigned size;
        longint    sprod;
        bit [63:0] uprod;
        riscv_exec_item it;

        // NOTE: never mix $signed(x) with an unsigned operand inside ?: or an
        // expression - SV then evaluates the whole thing unsigned (this is why
        // the previous model got SRA/SRAI/DIV/REM wrong for negative operands).

        it = riscv_exec_item::type_id::create("it");
        it.pc = pc; it.instr = instr; it.rs1_val = a; it.rs2_val = b;
        it.mie_before  = csr_mstatus[SR_MIE];
        it.mpie_before = csr_mstatus[SR_MPIE];

        next_pc = pc + 4;

        if (!is_legal(instr)) begin
            next_pc = take_trap(pc, CAUSE_ILLEGAL, instr);   // DUT reports opcode in mtval
            finish_step(it, 1, CAUSE_ILLEGAL, rd, result, 0);
            return;
        end

        case (opcode)
            // ---------------------------------------------------- OP-IMM
            7'b0010011: begin
                case (funct3)
                    3'b000: result = a + imm_i;
                    3'b010: result = (sa < simm) ? 32'd1 : 32'd0;
                    3'b011: result = (a < imm_i) ? 32'd1 : 32'd0;
                    3'b100: result = a ^ imm_i;
                    3'b110: result = a | imm_i;
                    3'b111: result = a & imm_i;
                    3'b001: result = a << instr[24:20];
                    3'b101: begin
                        if (instr[30]) begin int t; t = sa >>> instr[24:20]; result = t; end
                        else            result = a >> instr[24:20];
                    end
                endcase
                wrote = 1;
            end
            // ---------------------------------------------------- OP / M-ext
            7'b0110011: begin
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: result = a * b;                                 // MUL
                        3'b001: begin sprod = longint'(sa) * longint'(sb);      // MULH
                                      result = sprod[63:32]; end
                        3'b010: begin sprod = longint'(sa) * longint'({32'b0, b}); // MULHSU
                                      result = sprod[63:32]; end
                        3'b011: begin uprod = 64'(a) * 64'(b);                  // MULHU
                                      result = uprod[63:32]; end
                        3'b100: begin                                           // DIV
                            if (b == 0)                                   result = 32'hFFFF_FFFF;
                            else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) result = 32'h8000_0000;
                            else begin int q; q = sa / sb; result = q; end
                        end
                        3'b101: result = (b == 0) ? 32'hFFFF_FFFF : (a / b);    // DIVU
                        3'b110: begin                                           // REM
                            if (b == 0)                                   result = a;
                            else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) result = 32'h0;
                            else begin int r; r = sa % sb; result = r; end
                        end
                        3'b111: result = (b == 0) ? a : (a % b);                // REMU
                    endcase
                end else begin
                    case (funct3)
                        3'b000: result = (funct7 == 7'b0100000) ? (a - b) : (a + b);
                        3'b001: result = a << b[4:0];
                        3'b010: result = (sa < sb) ? 32'd1 : 32'd0;
                        3'b011: result = (a < b) ? 32'd1 : 32'd0;
                        3'b100: result = a ^ b;
                        3'b101: begin
                            if (funct7 == 7'b0100000) begin int t; t = sa >>> b[4:0]; result = t; end
                            else                      result = a >> b[4:0];
                        end
                        3'b110: result = a | b;
                        3'b111: result = a & b;
                    endcase
                end
                wrote = 1;
            end
            // ---------------------------------------------------- LOAD
            7'b0000011: begin
                mem_addr = a + imm_i;
                size = (funct3[1:0] == 2'b00) ? 1 : (funct3[1:0] == 2'b01) ? 2 : 4;
                if ((size == 2 && mem_addr[0]) || (size == 4 && mem_addr[1:0] != 2'b00)) begin
                    next_pc = take_trap(pc, CAUSE_MISALIGNED_LOAD, mem_addr);
                    it.mem_addr = mem_addr;
                    finish_step(it, 1, CAUSE_MISALIGNED_LOAD, rd, result, 0);
                    return;
                end
                word = mem_read_word(mem_addr) >> (8 * mem_addr[1:0]);
                case (funct3)
                    3'b000: result = {{24{word[7]}},  word[7:0]};     // LB
                    3'b001: result = {{16{word[15]}}, word[15:0]};    // LH
                    3'b010: result = word;                            // LW
                    3'b100: result = {24'b0, word[7:0]};              // LBU
                    3'b101: result = {16'b0, word[15:0]};             // LHU
                endcase
                wrote = 1;
                it.is_mem = 1;
            end
            // ---------------------------------------------------- STORE
            7'b0100011: begin
                mem_addr = a + imm_s;
                size = (funct3 == 3'b000) ? 1 : (funct3 == 3'b001) ? 2 : 4;
                if ((size == 2 && mem_addr[0]) || (size == 4 && mem_addr[1:0] != 2'b00)) begin
                    next_pc = take_trap(pc, CAUSE_MISALIGNED_STORE, mem_addr);
                    it.mem_addr = mem_addr;
                    finish_step(it, 1, CAUSE_MISALIGNED_STORE, rd, result, 0);
                    return;
                end
                mem_write(mem_addr, b, size);
                it.is_mem = 1;
            end
            // ---------------------------------------------------- BRANCH
            7'b1100011: begin
                bit taken;
                case (funct3)
                    3'b000: taken = (a == b);
                    3'b001: taken = (a != b);
                    3'b100: taken = (sa <  sb);
                    3'b101: taken = (sa >= sb);
                    3'b110: taken = (a <  b);
                    3'b111: taken = (a >= b);
                    default: taken = 0;
                endcase
                if (taken) next_pc = pc + imm_b;
            end
            7'b0110111: begin result = {instr[31:12], 12'b0};      wrote = 1; end  // LUI
            7'b0010111: begin result = pc + {instr[31:12], 12'b0}; wrote = 1; end  // AUIPC
            7'b1101111: begin                                                       // JAL
                result = pc + 4; wrote = 1;
                next_pc = pc + imm_j;
            end
            7'b1100111: begin                                                       // JALR
                result = pc + 4; wrote = 1;
                next_pc = (a + imm_i) & ~32'h1;
            end
            7'b0001111: ;                                                           // FENCE / FENCE.I
            // ---------------------------------------------------- SYSTEM
            7'b1110011: begin
                if (funct3 == 3'b000) begin
                    if (instr == 32'h0000_0073) begin                 // ECALL (M-mode)
                        next_pc = take_trap(pc, CAUSE_ECALL_M, 32'h0);
                        finish_step(it, 1, CAUSE_ECALL_M, rd, result, 0);
                        return;
                    end
                    if (instr == 32'h0010_0073) begin                 // EBREAK
                        next_pc = take_trap(pc, CAUSE_BREAKPOINT, 32'h0);
                        finish_step(it, 1, CAUSE_BREAKPOINT, rd, result, 0);
                        return;
                    end
                    if (instr == 32'h3020_0073) begin                 // MRET
                        csr_mstatus[SR_MIE]  = csr_mstatus[SR_MPIE];
                        csr_mstatus[SR_MPIE] = 1'b1;
                        csr_mstatus[12:11]   = 2'b00;                // DUT sets MPP=U on MRET
                        next_pc = csr_mepc;
                        n_mret++;
                        it.is_mret = 1;
                    end
                    // WFI: no-op
                end else begin
                    csr_addr = instr[31:20];
                    csr_old  = csr_read(csr_addr);
                    csr_src  = funct3[2] ? {27'b0, rs1} : a;         // *I forms use zimm
                    case (funct3[1:0])
                        2'b01: csr_write(csr_addr, csr_src);                          // RW
                        2'b10: if (rs1 != 0) csr_write(csr_addr, csr_old | csr_src);  // RS
                        2'b11: if (rs1 != 0) csr_write(csr_addr, csr_old & ~csr_src); // RC
                    endcase
                    result = csr_old;
                    wrote  = 1;
                end
            end
            default: ;
        endcase

        it.mem_addr = mem_addr;
        finish_step(it, 0, 0, rd, result, wrote);
    endfunction

    // Commit register write, publish expected value + exec record
    function void finish_step(riscv_exec_item it, bit trap, bit [31:0] cause,
                              bit [4:0] rd, bit [31:0] result, bit wrote);
        it.trap  = trap;
        it.cause = cause;
        it.rd    = rd;
        if (wrote && rd != 0) begin
            regs[rd]  = result;
            it.wrote  = 1;
            it.result = result;
            n_writes++;
            `uvm_info("REF_MODEL",
                $sformatf("EXPECT: x%0d <= 0x%08h (%0d)  [pc=0x%08h]", rd, result, result, it.pc), UVM_LOW)
            expected_ap.write({27'b0, rd, result});
        end
        exec_ap.write(it);
    endfunction


    function void report_phase(uvm_phase phase);
        string s = "";
        super.report_phase(phase);
        foreach (trap_hist[c]) s = {s, $sformatf(" cause%0d=%0d", c, trap_hist[c])};
        `uvm_info("REF_MODEL", $sformatf("Summary: steps=%0d writes=%0d traps=%0d (%s ) mret=%0d restarts=%0d",
                  n_steps, n_writes, n_traps, s, n_mret, n_restarts), UVM_LOW)
    endfunction
endclass
