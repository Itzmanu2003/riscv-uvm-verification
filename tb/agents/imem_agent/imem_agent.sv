class imem_agent extends uvm_agent;
    `uvm_component_utils(imem_agent)

    imem_sequencer sqr;
    imem_driver    drv;
    imem_monitor   mon;

    function new(string name = "imem_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = imem_sequencer::type_id::create("sqr", this);
        drv = imem_driver   ::type_id::create("drv", this);
        mon = imem_monitor  ::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // connect the driver to the sequencer (standard UVM wiring)
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

