interface retire_if (input logic clk, input logic rst_n);
    logic [4:0]  rd;         // destination register number
    logic [31:0] rd_value;   // value written
    // (rd != 0) means a real write happened
endinterface
