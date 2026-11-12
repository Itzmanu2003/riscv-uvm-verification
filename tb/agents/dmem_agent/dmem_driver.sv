class dmem_driver extends uvm_driver #(dmem_seq_item);
    `uvm_component_utils(dmem_driver)

    virtual axi4_if vif;
    bit [31:0] mem [bit [31:0]];  // backing memory

    function new(string name = "dmem_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "dmem_vif", vif))
            `uvm_fatal("DMEM_DRV", "No virtual interface set for dmem_driver")
    endfunction

    function void load_data(bit [31:0] addr, bit [31:0] data);
        mem[addr] = data;
    endfunction

    task run_phase(uvm_phase phase);
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        vif.rlast   <= 1'b0;
        vif.rresp   <= 2'b00;
        vif.rdata   <= 32'h0;
        vif.awready <= 1'b0;
        vif.wready  <= 1'b0;
        vif.bvalid  <= 1'b0;
        vif.bresp   <= 2'b00;

        fork
            handle_reads();
            handle_writes();
        join
    endtask

    // Handle read requests (loads)
    task handle_reads();
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) begin
                vif.arready <= 1'b0;
                vif.rvalid  <= 1'b0;
                continue;
            end

            vif.arready <= 1'b1;
            if (vif.arvalid && vif.arready) begin
                automatic bit [31:0] base_addr = vif.araddr;
                automatic int unsigned len = vif.arlen;
                vif.arready <= 1'b0;

                for (int unsigned beat = 0; beat <= len; beat++) begin
                    automatic bit [31:0] a = base_addr + beat*4;
                    vif.rvalid <= 1'b1;
                    vif.rlast  <= (beat == len);
                    vif.rresp  <= 2'b00;
                    vif.rdata  <= mem.exists(a) ? mem[a] : 32'h0;
                    do @(posedge vif.clk); while (!(vif.rvalid && vif.rready) && vif.rst_n);
                    if (!vif.rst_n) break;      // mid-burst reset: drop the rest of the burst
                end
                vif.rvalid <= 1'b0;
                vif.rlast  <= 1'b0;
            end
        end
    endtask

    // Handle write requests (stores)
    task handle_writes();
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) begin
                vif.awready <= 1'b0;
                vif.wready  <= 1'b0;
                vif.bvalid  <= 1'b0;
                continue;
            end

            vif.awready <= 1'b1;
            if (vif.awvalid && vif.awready) begin
                automatic bit [31:0] base_addr = vif.awaddr;
                automatic int unsigned len = vif.awlen;
                vif.awready <= 1'b0;

                // Accept write data beats
                for (int unsigned beat = 0; beat <= len; beat++) begin
                    vif.wready <= 1'b1;
                    do @(posedge vif.clk); while (!(vif.wvalid && vif.wready) && vif.rst_n);
                    if (!vif.rst_n) break;      // mid-burst reset: beats not yet sent are lost
                    begin
                        automatic bit [31:0] a = base_addr + beat*4;
                        // Apply write strobes
                        if (vif.wstrb[0]) mem[a][7:0]   = vif.wdata[7:0];
                        if (vif.wstrb[1]) mem[a][15:8]  = vif.wdata[15:8];
                        if (vif.wstrb[2]) mem[a][23:16] = vif.wdata[23:16];
                        if (vif.wstrb[3]) mem[a][31:24] = vif.wdata[31:24];
                    end
                end
                vif.wready <= 1'b0;
                if (!vif.rst_n) continue;

                // Send write response
                vif.bvalid <= 1'b1;
                vif.bresp  <= 2'b00;
                do @(posedge vif.clk); while (!(vif.bvalid && vif.bready) && vif.rst_n);
                vif.bvalid <= 1'b0;
            end
        end
    endtask

endclass

