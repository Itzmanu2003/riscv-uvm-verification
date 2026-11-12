// ============================================================================
// riscv_exec_item
// One record per instruction executed by the reference model. Published on
// reference_model.exec_ap and consumed by coverage_collector (functional
// coverage on what was actually EXECUTED, not just what was loaded).
// ============================================================================
class riscv_exec_item extends uvm_object;
    bit [31:0] pc;
    bit [31:0] instr;
    bit [31:0] rs1_val;
    bit [31:0] rs2_val;
    bit        wrote;          // architectural register write happened
    bit [4:0]  rd;
    bit [31:0] result;         // value written to rd (valid when wrote)
    bit        is_mem;         // load/store that did NOT trap
    bit [31:0] mem_addr;       // effective address (loads/stores, incl. misaligned)
    bit        trap;           // instruction raised a synchronous exception
    bit [31:0] cause;          // mcause value when trap=1
    bit        mie_before;     // mstatus.MIE before this instruction
    bit        mpie_before;    // mstatus.MPIE before this instruction (MRET coverage)
    bit        is_mret;

    `uvm_object_utils(riscv_exec_item)

    function new(string name = "riscv_exec_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("pc=%08h instr=%08h rd=x%0d wrote=%0b res=%08h trap=%0b cause=%0d",
                         pc, instr, rd, wrote, result, trap, cause);
    endfunction
endclass
