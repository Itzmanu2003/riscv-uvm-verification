
interface axi4_if #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter ID_W   = 4
) (
    input logic clk,
    input logic rst_n
);
    // Write Address channel
    logic [ID_W-1:0]     awid;
    logic [ADDR_W-1:0]   awaddr;
    logic [7:0]          awlen;
    logic [2:0]          awsize;
    logic [1:0]          awburst;
    logic                awvalid;
    logic                awready;

    // Write Data channel
    logic [DATA_W-1:0]   wdata;
    logic [DATA_W/8-1:0] wstrb;
    logic                wlast;
    logic                wvalid;
    logic                wready;

    // Write Response channel
    logic [ID_W-1:0]     bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    // Read Address channel
    logic [ID_W-1:0]     arid;
    logic [ADDR_W-1:0]   araddr;
    logic [7:0]          arlen;
    logic [2:0]          arsize;
    logic [1:0]          arburst;
    logic                arvalid;
    logic                arready;

    // Read Data channel
    logic [ID_W-1:0]     rid;
    logic [DATA_W-1:0]   rdata;
    logic [1:0]          rresp;
    logic                rlast;
    logic                rvalid;
    logic                rready;
endinterface
