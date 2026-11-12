class dmem_monitor extends uvm_monitor;
    `uvm_component_utils(dmem_monitor)

    virtual axi4_if vif;
    uvm_analysis_port #(dmem_seq_item) ap;

    function new(string name = "dmem_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "dmem_vif", vif))
            `uvm_fatal("DMEM_MON", "No virtual interface set for dmem_monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_reads();
            monitor_writes();
        join
    endtask

    task monitor_reads();
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) continue;
            if (vif.arvalid && vif.arready) begin
                automatic bit [31:0] base_addr = vif.araddr;
                automatic int unsigned len = vif.arlen;
                for (int unsigned beat = 0; beat <= len; beat++) begin
                    dmem_seq_item tr = dmem_seq_item::type_id::create("tr");
                    do @(posedge vif.clk); while (!(vif.rvalid && vif.rready) && vif.rst_n);
                    if (!vif.rst_n) break;    // reset: stop following this burst
                    tr.addr  = base_addr + beat*4;
                    tr.rdata = vif.rdata;
                    tr.resp  = vif.rresp;
                    ap.write(tr);
                    `uvm_info("DMEM_MON", $sformatf("READ: addr=0x%08h data=0x%08h", tr.addr, tr.rdata), UVM_HIGH)
                end
            end
        end
    endtask

    task monitor_writes();
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) continue;
            if (vif.awvalid && vif.awready) begin
                automatic bit [31:0] base_addr = vif.awaddr;
                automatic int unsigned len = vif.awlen;
                for (int unsigned beat = 0; beat <= len; beat++) begin
                    dmem_seq_item tr = dmem_seq_item::type_id::create("tr");
                    do @(posedge vif.clk); while (!(vif.wvalid && vif.wready) && vif.rst_n);
                    if (!vif.rst_n) break;    // reset: stop following this burst
                    tr.addr  = base_addr + beat*4;
                    tr.wdata = vif.wdata;
                    tr.wstrb = vif.wstrb;
                    ap.write(tr);
                    `uvm_info("DMEM_MON", $sformatf("WRITE: addr=0x%08h data=0x%08h", tr.addr, tr.wdata), UVM_HIGH)
                end
            end
        end
    endtask

endclass

