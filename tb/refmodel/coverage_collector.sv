// ============================================================================
// coverage_collector - functional coverage
// ----------------------------------------------------------------------------
//  analysis_export (bit[63:0])      : actual DUT register writes (retire monitor)
//  exec_export     (riscv_exec_item): every instruction EXECUTED by the ref model
//  sample_instr()                   : static sampling of loaded instructions
//
//  Original groups : rd_cg, op_cg, hazard_cg
//  New groups      : ls_cg     - LB/LH/LW/LBU/LHU/SB/SH/SW x byte offset, sign ext,
//                                data-address regions
//                    mext_cg   - all 8 M-ext ops x operand classes, div0/overflow
//                    trap_cg   - ECALL/EBREAK/illegal/misaligned x mstatus.MIE, MRET
//                    value_cg  - extreme write values, walking 1/0, per-reg 0/~0
//                    sys_cg    - D$ maintenance CSRs, FENCE(.I), PC address regions
// ============================================================================
class coverage_collector extends uvm_subscriber #(bit [63:0]);
    `uvm_component_utils(coverage_collector)

    uvm_analysis_imp_exec #(riscv_exec_item, coverage_collector) exec_export;

    bit [4:0]  cov_rd;
    bit [4:0]  prev_rd;
    bit [31:0] cov_instr;

    // ---- sample variables for the exec-stream groups ----
    int unsigned ls_op;          // 0 LB 1 LH 2 LW 3 LBU 4 LHU 5 SB 6 SH 7 SW
    bit [1:0]    byte_off;
    int unsigned ext_kind;       // 0 n/a 1 lb+ 2 lb- 3 lh+ 4 lh- 5 lbu>=0x80 6 lhu>=0x8000
    bit [3:0]    addr_hi;
    int unsigned mop;
    int unsigned a_cls, b_cls;   // 0 zero 1 one 2 -1 3 MIN 4 MAX 5 +other 6 -other
    int unsigned mspecial;       // 1..4 div-by-zero (DIV DIVU REM REMU) 5/6 overflow (DIV/REM)
    bit [31:0]   t_cause;
    bit          t_mie;
    bit          t_mpie;
    bit [31:0]   wval;
    bit [4:0]    wrd;
    int          onehot_pos;
    int          onezero_pos;
    int unsigned cache_op;       // 1 dflush 2 dwriteback 3 dinvalidate 4 fence 5 fence.i
    bit [3:0]    pc_hi;

    // ================= original groups =================
    covergroup rd_cg;
        option.per_instance = 1;
        RD: coverpoint cov_rd {
            bins low[]     = {[1:7]};
            bins mid[]     = {[8:15]};
            bins high[]    = {[16:31]};
        }
    endgroup

    covergroup op_cg;
        option.per_instance = 1;
        OPCODE: coverpoint cov_instr[6:0] {
            bins op_reg  = {7'b0110011};
            bins op_imm  = {7'b0010011};
            bins load    = {7'b0000011};
            bins store   = {7'b0100011};
            bins branch  = {7'b1100011};
            bins jal     = {7'b1101111};
            bins jalr    = {7'b1100111};
            bins lui     = {7'b0110111};
            bins auipc   = {7'b0010111};
            bins system  = {7'b1110011};
        }
        FUNCT3: coverpoint cov_instr[14:12];
    endgroup

    covergroup hazard_cg;
        option.per_instance = 1;
        RAW_HAZARD: coverpoint (cov_rd == prev_rd && cov_rd != 0) {
            bins no_hazard = {0};
            bins raw_hit   = {1};
        }
    endgroup

    // ================= new groups =================
    covergroup ls_cg;
        option.per_instance = 1;
        LS_OP: coverpoint ls_op {
            bins lb  = {0}; bins lh  = {1}; bins lw = {2}; bins lbu = {3};
            bins lhu = {4}; bins sb  = {5}; bins sh = {6}; bins sw  = {7};
        }
        OFFSET: coverpoint byte_off;
        OP_X_OFFSET: cross LS_OP, OFFSET {
            // misaligned halfword/word accesses trap -> covered by trap_cg instead
            ignore_bins misaligned_h = binsof(LS_OP) intersect {1, 4, 6} && binsof(OFFSET) intersect {1, 3};
            ignore_bins misaligned_w = binsof(LS_OP) intersect {2, 7}    && binsof(OFFSET) intersect {1, 2, 3};
        }
        SIGN_EXT: coverpoint ext_kind {
            bins lb_pos = {1}; bins lb_neg = {2}; bins lh_pos = {3}; bins lh_neg = {4};
            bins lbu_hi = {5}; bins lhu_hi = {6};
            ignore_bins na = {0};
        }
        ADDR_REGION: coverpoint addr_hi;            // data address bits [31:28]
    endgroup

    covergroup mext_cg;
        option.per_instance = 1;
        MOP: coverpoint mop {
            bins mul = {0}; bins mulh = {1}; bins mulhsu = {2}; bins mulhu = {3};
            bins div = {4}; bins divu = {5}; bins rem    = {6}; bins remu  = {7};
        }
        A_CLASS: coverpoint a_cls {
            bins zero = {0}; bins one = {1}; bins neg_one = {2}; bins min_int = {3};
            bins max_int = {4}; bins pos = {5}; bins neg = {6};
        }
        B_CLASS: coverpoint b_cls {
            bins zero = {0}; bins one = {1}; bins neg_one = {2}; bins min_int = {3};
            bins max_int = {4}; bins pos = {5}; bins neg = {6};
        }
        OP_X_A: cross MOP, A_CLASS;
        OP_X_B: cross MOP, B_CLASS;
        SPECIAL: coverpoint mspecial {
            bins div_by_zero[] = {[1:4]};
            bins overflow[]    = {5, 6};
            ignore_bins none   = {0};
        }
    endgroup

    covergroup trap_cg;
        option.per_instance = 1;
        CAUSE: coverpoint t_cause {
            bins illegal_instr    = {2};
            bins breakpoint       = {3};
            bins misaligned_load  = {4};
            bins misaligned_store = {6};
            bins ecall_m          = {11};
        }
        MIE_AT_TRAP: coverpoint t_mie;
        CAUSE_X_MIE: cross CAUSE, MIE_AT_TRAP;
    endgroup

    covergroup mret_cg;
        option.per_instance = 1;
        MPIE_AT_MRET: coverpoint t_mpie;           // MRET restoring MIE=0 and MIE=1
    endgroup

    covergroup value_cg;
        option.per_instance = 1;
        VALUE: coverpoint wval {
            bins zero    = {32'h0000_0000};
            bins ones    = {32'hFFFF_FFFF};
            bins min_int = {32'h8000_0000};
            bins max_int = {32'h7FFF_FFFF};
            bins alt_a   = {32'hAAAA_AAAA};
            bins alt_5   = {32'h5555_5555};
        }
        WALKING_1: coverpoint onehot_pos  { bins pos[] = {[0:31]}; }
        WALKING_0: coverpoint onezero_pos { bins pos[] = {[0:31]}; }
        RD: coverpoint wrd { bins r[] = {[1:31]}; }
        // every register written with all-zeros and all-ones (regfile toggle)
        RD_X_EXTREME: cross RD, VALUE {
            ignore_bins not_extreme = binsof(VALUE.min_int) || binsof(VALUE.max_int) ||
                                      binsof(VALUE.alt_a)   || binsof(VALUE.alt_5);
        }
    endgroup

    covergroup sys_cg;
        option.per_instance = 1;
        CACHE_OP: coverpoint cache_op {
            bins dflush = {1}; bins dwriteback = {2}; bins dinvalidate = {3};
            bins fence  = {4}; bins fence_i    = {5};
            ignore_bins none = {0};
        }
        PC_REGION: coverpoint pc_hi;               // fetch address bits [31:28]
    endgroup

    function new(string name = "coverage_collector", uvm_component parent = null);
        super.new(name, parent);
        exec_export = new("exec_export", this);
        rd_cg = new(); op_cg = new(); hazard_cg = new();
        ls_cg = new(); mext_cg = new(); trap_cg = new(); mret_cg = new();
        value_cg = new(); sys_cg = new();
        prev_rd = 0;
    endfunction

    // ---- actual DUT writes ----
    function void write(bit [63:0] t);
        prev_rd = cov_rd;
        cov_rd = t[36:32];
        rd_cg.sample();
        hazard_cg.sample();
    endfunction

    function void sample_instr(bit [31:0] instr);
        cov_instr = instr;
        op_cg.sample();
    endfunction

    static function int unsigned operand_class(bit [31:0] v);
        case (v)
            32'h0000_0000: return 0;
            32'h0000_0001: return 1;
            32'hFFFF_FFFF: return 2;
            32'h8000_0000: return 3;
            32'h7FFF_FFFF: return 4;
            default:       return v[31] ? 6 : 5;
        endcase
    endfunction

    static function int one_hot_pos(bit [31:0] v);
        if (v == 0 || (v & (v - 1)) != 0) return -1;
        for (int i = 0; i < 32; i++) if (v[i]) return i;
        return -1;
    endfunction

    // ---- executed-instruction stream (reference model) ----
    function void write_exec(riscv_exec_item it);
        bit [6:0] opc = it.instr[6:0];
        bit [2:0] f3  = it.instr[14:12];

        pc_hi    = it.pc[31:28];
        cache_op = 0;
        if (opc == 7'b1110011 && f3 == 3'b001) begin
            case (it.instr[31:20])
                12'h3A0: cache_op = 1;
                12'h3A1: cache_op = 2;
                12'h3A2: cache_op = 3;
            endcase
        end
        if (opc == 7'b0001111) cache_op = (f3 == 3'b001) ? 5 : 4;
        sys_cg.sample();

        if (it.trap) begin
            t_cause = it.cause;
            t_mie   = it.mie_before;
            trap_cg.sample();
            return;
        end

        if (it.is_mret) begin
            t_mpie = it.mpie_before;
            mret_cg.sample();
        end

        // loads / stores
        if (it.is_mem) begin
            byte_off = it.mem_addr[1:0];
            addr_hi  = it.mem_addr[31:28];
            ext_kind = 0;
            if (opc == 7'b0000011) begin
                case (f3)
                    3'b000: begin ls_op = 0; ext_kind = it.result[31] ? 2 : 1; end
                    3'b001: begin ls_op = 1; ext_kind = it.result[31] ? 4 : 3; end
                    3'b010: ls_op = 2;
                    3'b100: begin ls_op = 3; if (it.result[7])  ext_kind = 5; end
                    3'b101: begin ls_op = 4; if (it.result[15]) ext_kind = 6; end
                endcase
            end else begin
                ls_op = 5 + f3;          // SB=5 SH=6 SW=7
            end
            ls_cg.sample();
        end

        // M extension
        if (opc == 7'b0110011 && it.instr[31:25] == 7'b0000001) begin
            mop   = f3;
            a_cls = operand_class(it.rs1_val);
            b_cls = operand_class(it.rs2_val);
            mspecial = 0;
            if (f3 >= 4 && it.rs2_val == 0) mspecial = f3 - 3;               // 1..4
            else if ((f3 == 4 || f3 == 6) && it.rs1_val == 32'h8000_0000 && it.rs2_val == 32'hFFFF_FFFF)
                mspecial = (f3 == 4) ? 5 : 6;
            mext_cg.sample();
        end

        // register-write values
        if (it.wrote) begin
            wval        = it.result;
            wrd         = it.rd;
            onehot_pos  = one_hot_pos(it.result);
            onezero_pos = one_hot_pos(~it.result);
            value_cg.sample();
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COVERAGE", $sformatf("Register-write coverage:  %0.1f%%", rd_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("ALU-operation coverage:   %0.1f%%", op_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("Hazard-pattern coverage:  %0.1f%%", hazard_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("Load/store-size coverage: %0.1f%%", ls_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("M-extension coverage:     %0.1f%%", mext_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("Trap coverage:            %0.1f%%", trap_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("MRET coverage:            %0.1f%%", mret_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("Extreme-value coverage:   %0.1f%%", value_cg.get_coverage()), UVM_LOW)
        `uvm_info("COVERAGE", $sformatf("System/PC coverage:       %0.1f%%", sys_cg.get_coverage()), UVM_LOW)
    endfunction
endclass
