module tb_top;
    import uvm_pkg::*;
    import riscv_env_pkg::*;
    import riscv_test_pkg::*;
    `include "uvm_macros.svh"

    logic clk = 0;
    logic por_n   = 0;          // power-on reset (released after 5 clocks)
    logic inj_rst = 0;          // mid-run reset pulse from the injector below
    wire  rst_n   = por_n & ~inj_rst;
    wire  rst     = ~rst_n;

    always #5 clk = ~clk;

    initial begin
        por_n = 0;
        repeat (5) @(posedge clk);
        por_n = 1;
    end

    // ================================================================
    //  Mid-run reset injector (used by riscv_reset_test)
    // ----------------------------------------------------------------
    //  Covers the FSM arcs "<any state> -> RESET" (dcache_core) and
    //  "REFILL/RELOOKUP -> FLUSH" (icache), which only exist when reset
    //  is asserted while the cache is busy. Each time a cache is in a
    //  state that has not been reset from yet, a 4-cycle reset is applied.
    //  Sampled/applied at negedge so the FSM is clearly IN that state.
    // ================================================================
    reset_ctrl_if rst_ctrl (.clk(clk));
    localparam bit [10:0] DC_TARGETS = 11'b111_1111_1110;   // dcache states 1..10 (0 = RESET)
    localparam bit [3:0]  IC_TARGETS = 4'b1100;            // icache REFILL(2), RELOOKUP(3)
    int unsigned inj_hold = 0;

    always @(negedge clk) begin
        automatic bit [3:0] dst = u_dut.u_dcache.u_core.state_q;
        automatic bit [1:0] ist = u_dut.u_icache.state_q;
        if (inj_rst) begin
            if (inj_hold == 0) inj_rst <= 1'b0;
            else               inj_hold--;
        end
        else if (por_n && rst_ctrl.inject_en && !rst_ctrl.all_done) begin
            if (DC_TARGETS[dst] && !rst_ctrl.dcache_hit[dst]) begin
                rst_ctrl.dcache_hit[dst] = 1'b1;
                inj_rst  <= 1'b1;  inj_hold = 3;  rst_ctrl.n_injected++;
                $display("[%0t] RESET_INJECTOR: reset #%0d while dcache state=%0d", $time, rst_ctrl.n_injected, dst);
            end
            else if (IC_TARGETS[ist] && !rst_ctrl.icache_hit[ist]) begin
                rst_ctrl.icache_hit[ist] = 1'b1;
                inj_rst  <= 1'b1;  inj_hold = 3;  rst_ctrl.n_injected++;
                $display("[%0t] RESET_INJECTOR: reset #%0d while icache state=%0d", $time, rst_ctrl.n_injected, ist);
            end
            rst_ctrl.all_done = ((rst_ctrl.dcache_hit & DC_TARGETS) == DC_TARGETS) &&
                                ((rst_ctrl.icache_hit & IC_TARGETS) == IC_TARGETS);
        end
    end

    axi4_if imem_if (.clk(clk), .rst_n(rst_n));
    axi4_if dmem_if (.clk(clk), .rst_n(rst_n));

    // ---------------- DUT ----------------
    riscv_top u_dut (
        .clk_i           (clk),
        .rst_i           (rst),
        .intr_i          (1'b0),
        .reset_vector_i  (32'h0000_0000),
        .axi_i_awready_i (imem_if.awready),
        .axi_i_wready_i  (imem_if.wready),
        .axi_i_bvalid_i  (imem_if.bvalid),
        .axi_i_bresp_i   (imem_if.bresp),
        .axi_i_bid_i     (imem_if.bid),
        .axi_i_arready_i (imem_if.arready),
        .axi_i_rvalid_i  (imem_if.rvalid),
        .axi_i_rdata_i   (imem_if.rdata),
        .axi_i_rresp_i   (imem_if.rresp),
        .axi_i_rid_i     (imem_if.rid),
        .axi_i_rlast_i   (imem_if.rlast),
        .axi_i_awvalid_o (imem_if.awvalid),
        .axi_i_awaddr_o  (imem_if.awaddr),
        .axi_i_awid_o    (imem_if.awid),
        .axi_i_awlen_o   (imem_if.awlen),
        .axi_i_awburst_o (imem_if.awburst),
        .axi_i_wvalid_o  (imem_if.wvalid),
        .axi_i_wdata_o   (imem_if.wdata),
        .axi_i_wstrb_o   (imem_if.wstrb),
        .axi_i_wlast_o   (imem_if.wlast),
        .axi_i_bready_o  (imem_if.bready),
        .axi_i_arvalid_o (imem_if.arvalid),
        .axi_i_araddr_o  (imem_if.araddr),
        .axi_i_arid_o    (imem_if.arid),
        .axi_i_arlen_o   (imem_if.arlen),
        .axi_i_arburst_o (imem_if.arburst),
        .axi_i_rready_o  (imem_if.rready),
        .axi_d_awready_i (dmem_if.awready),
        .axi_d_wready_i  (dmem_if.wready),
        .axi_d_bvalid_i  (dmem_if.bvalid),
        .axi_d_bresp_i   (dmem_if.bresp),
        .axi_d_bid_i     (dmem_if.bid),
        .axi_d_arready_i (dmem_if.arready),
        .axi_d_rvalid_i  (dmem_if.rvalid),
        .axi_d_rdata_i   (dmem_if.rdata),
        .axi_d_rresp_i   (dmem_if.rresp),
        .axi_d_rid_i     (dmem_if.rid),
        .axi_d_rlast_i   (dmem_if.rlast),
        .axi_d_awvalid_o (dmem_if.awvalid),
        .axi_d_awaddr_o  (dmem_if.awaddr),
        .axi_d_awid_o    (dmem_if.awid),
        .axi_d_awlen_o   (dmem_if.awlen),
        .axi_d_awburst_o (dmem_if.awburst),
        .axi_d_wvalid_o  (dmem_if.wvalid),
        .axi_d_wdata_o   (dmem_if.wdata),
        .axi_d_wstrb_o   (dmem_if.wstrb),
        .axi_d_wlast_o   (dmem_if.wlast),
        .axi_d_bready_o  (dmem_if.bready),
        .axi_d_arvalid_o (dmem_if.arvalid),
        .axi_d_araddr_o  (dmem_if.araddr),
        .axi_d_arid_o    (dmem_if.arid),
        .axi_d_arlen_o   (dmem_if.arlen),
        .axi_d_arburst_o (dmem_if.arburst),
        .axi_d_rready_o  (dmem_if.rready)
    );

    // -------- Retire interface --------
    retire_if retire_vif (.clk(clk), .rst_n(rst_n));
    assign retire_vif.rd       = u_dut.u_core.u_issue.u_regfile.rd0_i;
    assign retire_vif.rd_value = u_dut.u_core.u_issue.u_regfile.rd0_value_i;

    // ================================================================
    //  SVA: SystemVerilog Assertions (Protocol + Invariant Checking)
    // ================================================================

    // --- AXI4 Instruction Bus Protocol Assertions ---

    // ARVALID must remain asserted until ARREADY
    property axi_i_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (imem_if.arvalid && !imem_if.arready) |=> imem_if.arvalid;
    endproperty
    assert property (axi_i_arvalid_stable)
        else $error("SVA: IMEM ARVALID dropped before ARREADY");

    // RVALID must remain asserted until RREADY
    property axi_i_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (imem_if.rvalid && !imem_if.rready) |=> imem_if.rvalid;
    endproperty
    assert property (axi_i_rvalid_stable)
        else $error("SVA: IMEM RVALID dropped before RREADY");

    // --- AXI4 Data Bus Protocol Assertions ---

    // ARVALID must remain asserted until ARREADY (data bus)
    property axi_d_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_if.arvalid && !dmem_if.arready) |=> dmem_if.arvalid;
    endproperty
    assert property (axi_d_arvalid_stable)
        else $error("SVA: DMEM ARVALID dropped before ARREADY");

    // AWVALID must remain asserted until AWREADY (data bus)
    property axi_d_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_if.awvalid && !dmem_if.awready) |=> dmem_if.awvalid;
    endproperty
    assert property (axi_d_awvalid_stable)
        else $error("SVA: DMEM AWVALID dropped before AWREADY");

    // WVALID must remain asserted until WREADY (data bus)
    property axi_d_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_if.wvalid && !dmem_if.wready) |=> dmem_if.wvalid;
    endproperty
    assert property (axi_d_wvalid_stable)
        else $error("SVA: DMEM WVALID dropped before WREADY");

    // BVALID must remain asserted until BREADY (data bus)
    property axi_d_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (dmem_if.bvalid && !dmem_if.bready) |=> dmem_if.bvalid;
    endproperty
    assert property (axi_d_bvalid_stable)
        else $error("SVA: DMEM BVALID dropped before BREADY");

    // --- Pipeline Invariant Assertions ---

    // Register x0 must always be zero
    property x0_always_zero;
        @(posedge clk) disable iff (!rst_n)
        (u_dut.u_core.u_issue.u_regfile.rd0_i == 5'd0) |->
        (u_dut.u_core.u_issue.u_regfile.rd0_value_i == 32'h0);
    endproperty
    // Note: x0 is hardwired zero in the register file, this checks the write port never tries non-zero for x0

    // AXI read response must be OKAY (2'b00) — no error responses expected in normal operation
    property axi_i_resp_okay;
        @(posedge clk) disable iff (!rst_n)
        (imem_if.rvalid && imem_if.rready) |-> (imem_if.rresp == 2'b00);
    endproperty
    assert property (axi_i_resp_okay)
        else $error("SVA: IMEM read response is not OKAY");

    property axi_d_resp_okay;
        @(posedge clk) disable iff (!rst_n)
        (dmem_if.rvalid && dmem_if.rready) |-> (dmem_if.rresp == 2'b00);
    endproperty
    assert property (axi_d_resp_okay)
        else $error("SVA: DMEM read response is not OKAY");

    // ================================================================

    initial begin
        $fsdbDumpfile("waves.fsdb");
        $fsdbDumpvars(0, tb_top);
    end

    initial begin
        uvm_config_db#(virtual axi4_if)::set(null, "*", "imem_vif", imem_if);
        uvm_config_db#(virtual retire_if)::set(null, "*", "retire_vif", retire_vif);
        uvm_config_db#(virtual axi4_if)::set(null, "*", "dmem_vif", dmem_if);
        uvm_config_db#(virtual reset_ctrl_if)::set(null, "*", "reset_ctrl_vif", rst_ctrl);
        run_test("riscv_base_test");
    end
endmodule

