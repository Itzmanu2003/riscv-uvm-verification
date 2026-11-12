package riscv_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import imem_agent_pkg::*;
    import dmem_agent_pkg::*;
    import refmodel_pkg::*;

    `include "virtual_sequencer.sv"

    class riscv_env extends uvm_env;
        `uvm_component_utils(riscv_env)

        imem_agent              imem_agt;
        dmem_agent              dmem_agt;
        reference_model         ref_model;
        retire_monitor          ret_mon;
        riscv_scoreboard        sb;
        coverage_collector      cov;
        riscv_virtual_sequencer v_sqr;
        virtual retire_if       rst_vif;     // only used to see rst_n

        function new(string name = "riscv_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            imem_agt  = imem_agent::type_id::create("imem_agt", this);
            dmem_agt  = dmem_agent::type_id::create("dmem_agt", this);
            ref_model = reference_model::type_id::create("ref_model", this);
            ret_mon   = retire_monitor::type_id::create("ret_mon", this);
            sb        = riscv_scoreboard::type_id::create("sb", this);
            cov       = coverage_collector::type_id::create("cov", this);
            v_sqr     = riscv_virtual_sequencer::type_id::create("v_sqr", this);
            if (!uvm_config_db#(virtual retire_if)::get(this, "", "retire_vif", rst_vif))
                `uvm_fatal("RISCV_ENV", "No retire_vif set")
            `uvm_info("RISCV_ENV", "build_phase: full env with virtual sequencer", UVM_LOW)
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            ref_model.expected_ap.connect(sb.expected_export);
            ret_mon.actual_ap.connect(sb.actual_export);
            ret_mon.actual_ap.connect(cov.analysis_export);
            ref_model.exec_ap.connect(cov.exec_export);   // executed-instruction coverage
            // Connect virtual sequencer to sub-sequencers
            v_sqr.imem_sqr = imem_agt.sqr;
            v_sqr.dmem_sqr = dmem_agt.sqr;
        endfunction

        // Mid-run reset handling: when the DUT comes out of a reset that was
        // NOT the power-on reset, flush the scoreboard and restart the
        // reference model with the memory contents as they are now.
        task run_phase(uvm_phase phase);
            if (rst_vif.rst_n !== 1'b1) @(posedge rst_vif.rst_n);   // power-on reset
            forever begin
                @(negedge rst_vif.rst_n);
                `uvm_info("RISCV_ENV", "Mid-run reset asserted", UVM_MEDIUM)
                @(posedge rst_vif.rst_n);
                sb.flush_for_reset();
                ref_model.restart(dmem_agt.drv.mem);
            end
        endtask

        function void load_instr(bit [31:0] addr, bit [31:0] instr);
            imem_agt.drv.load_instr(addr, instr);
            ref_model.load_instr(addr, instr);
            cov.sample_instr(instr);
        endfunction

        function void load_data(bit [31:0] addr, bit [31:0] data);
            dmem_agt.drv.load_data(addr, data);
            ref_model.load_data(addr, data);
        endfunction

    endclass
endpackage
