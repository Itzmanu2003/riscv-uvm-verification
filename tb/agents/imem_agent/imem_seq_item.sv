class imem_seq_item extends uvm_sequence_item;

    // --- Request side (what the DUT asks for) ---
    rand bit [31:0] addr;        // fetch address (ARADDR)
    rand bit [7:0]  burst_len;   // number of beats - 1 (ARLEN)

    // --- Response side (what we drive back) ---
    rand bit [31:0] rdata;       // instruction word returned (RDATA)
    rand bit [1:0]  resp;        // OKAY / SLVERR / DECERR (RRESP)

    `uvm_object_utils_begin(imem_seq_item)
        `uvm_field_int(addr,      UVM_ALL_ON)
        `uvm_field_int(burst_len, UVM_ALL_ON)
        `uvm_field_int(rdata,     UVM_ALL_ON)
        `uvm_field_int(resp,      UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "imem_seq_item");
        super.new(name);
    endfunction

endclass

