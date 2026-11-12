class dmem_seq_item extends uvm_sequence_item;
    rand bit [31:0] addr;
    rand bit [7:0]  burst_len;
    rand bit [31:0] rdata;
    rand bit [31:0] wdata;
    rand bit [3:0]  wstrb;
    rand bit [1:0]  resp;

    `uvm_object_utils_begin(dmem_seq_item)
        `uvm_field_int(addr,      UVM_ALL_ON)
        `uvm_field_int(burst_len, UVM_ALL_ON)
        `uvm_field_int(rdata,     UVM_ALL_ON)
        `uvm_field_int(wdata,     UVM_ALL_ON)
        `uvm_field_int(wstrb,     UVM_ALL_ON)
        `uvm_field_int(resp,      UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "dmem_seq_item");
        super.new(name);
    endfunction
endclass

