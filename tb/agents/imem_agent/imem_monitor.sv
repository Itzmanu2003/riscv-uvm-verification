class imem_monitor extends uvm_monitor;
    `uvm_component_utils(imem_monitor)

    // handle to the physical AXI interface
    virtual axi4_if vif;

    // analysis port - broadcasts observed fetch transactions outward
    uvm_analysis_port #(imem_seq_item) ap;

    function new(string name = "imem_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "imem_vif", vif))
            `uvm_fatal("IMEM_MON", "No virtual interface set for imem_monitor")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) continue;

            // Detect an accepted read-address request
            if (vif.arvalid && vif.arready) begin
                bit [31:0]   base_addr = vif.araddr;
                int unsigned len       = vif.arlen;

                // Capture each returned data beat
                for (int unsigned beat = 0; beat <= len; beat++) begin
                    imem_seq_item tr = imem_seq_item::type_id::create("tr");
                    // wait for the data beat handshake
                    do @(posedge vif.clk); while (!(vif.rvalid && vif.rready) && vif.rst_n);
                    if (!vif.rst_n) break;    // reset: stop following this burst
                    tr.addr      = base_addr + beat*4;
                    tr.rdata     = vif.rdata;
                    tr.resp      = vif.rresp;
                    tr.burst_len = len;
                    ap.write(tr);   // broadcast the observed transaction
                    `uvm_info("IMEM_MON",
                        $sformatf("Fetch: addr=0x%08h  data=0x%08h", tr.addr, tr.rdata),
                        UVM_HIGH)
                end
            end
        end
    endtask

endclass

