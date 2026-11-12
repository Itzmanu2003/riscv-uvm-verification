// ============================================================================
// reset_ctrl_if - lets a test switch on the mid-run reset injector in tb_top
// and see its progress. Default: injector OFF (all other tests unaffected).
// ============================================================================
interface reset_ctrl_if (input logic clk);
    bit          inject_en  = 0;    // test sets 1 to start injecting resets
    bit [10:0]   dcache_hit = 0;    // dcache_core states already reset "from"
    bit [3:0]    icache_hit = 0;    // icache states already reset "from"
    int unsigned n_injected = 0;    // number of resets applied
    bit          all_done   = 0;    // every target state has been hit
endinterface
