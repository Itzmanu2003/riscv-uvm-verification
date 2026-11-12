package refmodel_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `uvm_analysis_imp_decl(_expected)
    `uvm_analysis_imp_decl(_actual)
    `uvm_analysis_imp_decl(_exec)

    `include "riscv_exec_item.sv"
    `include "reference_model.sv"
    `include "retire_monitor.sv"
    `include "scoreboard.sv"
    `include "coverage_collector.sv"
endpackage
