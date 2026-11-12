// ============================================================================
// riscv_scoreboard - in-order comparison of register writes
// ----------------------------------------------------------------------------
// The DUT (ultraembedded/riscv) is a single-issue, in-order pipeline with a
// single register-file write port, so register writes retire in program
// order. Any rd OR data mismatch is therefore a real failure.
//
// (The previous version silently dropped an expected entry whenever the rd
//  did not match - that masked real divergences, e.g. riscv_mega_test was
//  ending with 22 unmatched expected writes and still reporting 0 FAIL.)
// ============================================================================
class riscv_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(riscv_scoreboard)

    uvm_analysis_imp_expected #(bit [63:0], riscv_scoreboard) expected_export;
    uvm_analysis_imp_actual   #(bit [63:0], riscv_scoreboard) actual_export;

    bit [63:0] expected_q [$];
    bit [63:0] actual_q   [$];

    int pass_count = 0;
    int fail_count = 0;
    int n_resets   = 0;

    function new(string name = "riscv_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        expected_export = new("expected_export", this);
        actual_export   = new("actual_export", this);
    endfunction

    function void write_expected(bit [63:0] t);
        expected_q.push_back(t);
        compare();
    endfunction

    function void write_actual(bit [63:0] t);
        actual_q.push_back(t);
        compare();
    endfunction

    // Number of predicted writes the DUT has not produced yet
    function int unsigned pending_expected();
        return expected_q.size();
    endfunction

    // Mid-run DUT reset: whatever was in flight is discarded on both sides
    function void flush_for_reset();
        n_resets++;
        `uvm_info("SCOREBOARD", $sformatf("Reset #%0d: discarding %0d expected / %0d actual in-flight writes",
                  n_resets, expected_q.size(), actual_q.size()), UVM_LOW)
        expected_q.delete();
        actual_q.delete();
    endfunction

    function void compare();
        bit [63:0] exp_val, act_val;
        bit [4:0]  exp_rd, act_rd;
        bit [31:0] exp_data, act_data;

        while (expected_q.size() > 0 && actual_q.size() > 0) begin
            exp_val  = expected_q.pop_front();
            act_val  = actual_q.pop_front();
            exp_rd   = exp_val[36:32];
            act_rd   = act_val[36:32];
            exp_data = exp_val[31:0];
            act_data = act_val[31:0];

            if (exp_rd == act_rd && exp_data == act_data) begin
                pass_count++;
                `uvm_info("SCOREBOARD",
                    $sformatf("PASS: x%0d expected=%0d actual=%0d", act_rd, exp_data, act_data),
                    UVM_LOW)
            end
            else begin
                fail_count++;
                `uvm_error("SCOREBOARD",
                    $sformatf("FAIL #%0d (check %0d): expected x%0d=0x%08h  actual x%0d=0x%08h",
                              fail_count, pass_count + fail_count, exp_rd, exp_data, act_rd, act_data))
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (expected_q.size() > 0)
            `uvm_error("SCOREBOARD",
                $sformatf("%0d expected register writes never retired by the DUT (first: x%0d=0x%08h) - DUT hung/diverged or test too short",
                          expected_q.size(), expected_q[0][36:32], expected_q[0][31:0]))
        if (actual_q.size() > 0)
            `uvm_error("SCOREBOARD",
                $sformatf("%0d unexpected DUT register writes (first: x%0d=0x%08h)",
                          actual_q.size(), actual_q[0][36:32], actual_q[0][31:0]))
        `uvm_info("SCOREBOARD",
            $sformatf("=== SCOREBOARD SUMMARY: %0d PASS, %0d FAIL === (mid-run resets: %0d)", pass_count,
                      fail_count + (expected_q.size() > 0) + (actual_q.size() > 0), n_resets),
            UVM_LOW)
    endfunction

endclass
