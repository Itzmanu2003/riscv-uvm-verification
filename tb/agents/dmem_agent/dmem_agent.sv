class dmem_agent extends uvm_agent;
    `uvm_component_utils(dmem_agent)

    dmem_sequencer sqr;
    dmem_driver    drv;
    dmem_monitor   mon;

    function new(string name = "dmem_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = dmem_sequencer::type_id::create("sqr", this);
        drv = dmem_driver::type_id::create("drv", this);
        mon = dmem_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
