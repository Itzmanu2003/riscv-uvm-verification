class riscv_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(riscv_virtual_sequencer)

    // Handles to the sub-sequencers (for coordinated sequences)
    imem_sequencer imem_sqr;
    dmem_sequencer dmem_sqr;

    function new(string name = "riscv_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
