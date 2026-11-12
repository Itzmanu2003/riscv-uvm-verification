class imem_driver extends uvm_driver #(imem_seq_item);
    `uvm_component_utils(imem_driver)

    // handle to the physical AXI interface (instruction bus)
    virtual axi4_if vif;

    // backing memory: address -> instruction word
    bit [31:0] mem [bit [31:0]];

    function new(string name = "imem_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "imem_vif", vif))
            `uvm_fatal("IMEM_DRV", "No virtual interface set for imem_driver")
    endfunction

    task run_phase(uvm_phase phase);
        // Initialise the response signals to idle
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        vif.rlast   <= 1'b0;
        vif.rresp   <= 2'b00;
        vif.rdata   <= 32'h0;

        forever begin
            @(posedge vif.clk);

            // Stay idle while in reset
            if (!vif.rst_n) begin
                vif.arready <= 1'b0;
                vif.rvalid  <= 1'b0;
                continue;
            end

            // ---- Phase A: accept a read-address request from the DUT ----
            vif.arready <= 1'b1;
            // wait for the handshake: DUT asserts arvalid AND we assert arready
            // (abandon the wait if reset is asserted)
            do @(posedge vif.clk); while (!(vif.arvalid && vif.arready) && vif.rst_n);
            if (!vif.rst_n) continue;

            begin
                bit [31:0]   base_addr = vif.araddr;
                int unsigned len       = vif.arlen;   // beats = len + 1
                vif.arready <= 1'b0;

                // ---- Phase B: return len+1 instruction words ----
                for (int unsigned beat = 0; beat <= len; beat++) begin
                    bit [31:0] a = base_addr + beat*4;
                    vif.rvalid <= 1'b1;
                    vif.rlast  <= (beat == len);
                    vif.rresp  <= 2'b00;  // OKAY
                    // return the instruction if we have it, else a NOP (ADDI x0,x0,0)
                    vif.rdata  <= mem.exists(a) ? mem[a] : 32'h00000013;
                    // wait for the DUT to accept this beat (rvalid && rready)
                    do @(posedge vif.clk); while (!(vif.rvalid && vif.rready) && vif.rst_n);
                    if (!vif.rst_n) break;      // mid-burst reset: drop the rest of the burst
                end
                vif.rvalid <= 1'b0;
                vif.rlast  <= 1'b0;
            end
        end
    endtask

    // Preload one instruction into the responder memory
    function void load_instr(bit [31:0] addr, bit [31:0] instr);
        mem[addr] = instr;
    endfunction

endclass

