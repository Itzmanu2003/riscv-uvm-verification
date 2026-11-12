class retire_monitor extends uvm_monitor;
    `uvm_component_utils(retire_monitor)

    virtual retire_if vif;

    // broadcasts each ACTUAL register write to the scoreboard
    uvm_analysis_port #(bit [63:0]) actual_ap;

    function new(string name = "retire_monitor", uvm_component parent = null);
        super.new(name, parent);
        actual_ap = new("actual_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual retire_if)::get(this, "", "retire_vif", vif))
            `uvm_fatal("RETIRE_MON", "No retire_if set")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (vif.rst_n && (vif.rd != 5'd0)) begin
                `uvm_info("RETIRE_MON",$sformatf("ACTUAL: x%0d <= 0x%08h (%0d)", vif.rd, vif.rd_value, vif.rd_value),UVM_LOW)
                actual_ap.write({27'b0, vif.rd, vif.rd_value});
            end
        end
    endtask

endclass

