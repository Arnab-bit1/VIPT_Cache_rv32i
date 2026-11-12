module cpu_system_top (
    input logic clk,
    input logic rst_n,
    output logic [31:0] debug_pc,
    output logic [31:0] debug_dmem_addr,
    output logic [31:0] debug_dmem_wdata, // Driven by CPU Regfile/Forwarding (ex_ma_op2)
    output logic debug_dmem_we,
    output logic [31:0] cpu_rdata,
    output logic ext_mem_read_req,
    output logic [12:0] ext_mem_read_addr,
    input  logic [31:0] ext_mem_read_data,
    input  logic ext_mem_read_valid,
    output logic ext_mem_write_req,
    output logic [12:0] ext_mem_write_addr,
    output logic [31:0] ext_mem_write_data,
    input  logic ext_mem_write_done,
    output wr, dmem_wr, imem_wr, d_req, d_we
);

    logic [31:0] pc;
    logic [31:0] imem_data;
    logic imem_waitrequest;

    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [31:0] dmem_rdata;
    logic dmem_we;
    logic dmem_req;
    logic cache_busy;
    logic dmem_waitrequest;

    logic cpu_waitrequest;
    logic branch_taken;

    assign dmem_waitrequest = dmem_req && cache_busy;
    assign cpu_waitrequest  = imem_waitrequest | dmem_waitrequest;
    assign wr = cpu_waitrequest;
    assign dmem_wr = dmem_waitrequest;
    assign imem_wr = imem_waitrequest;
    assign d_req = dmem_req;
    assign d_we = dmem_we;

    logic pw_mem_req;
    logic [31:0] pw_mem_addr;
    logic [31:0] pw_mem_rdata;
    logic pw_mem_rvalid;

    logic cache_mm_read_req;
    logic [12:0] cache_mm_raddr;
    logic [31:0] cache_mm_rdata;
    logic cache_mm_rvalid;

    logic cache_mm_write_req;
    logic [12:0] cache_mm_waddr;
    logic [31:0] cache_mm_wdata;
    logic cache_mm_wdone;

    assign cpu_rdata = dmem_rdata;
    assign debug_pc         = pc;
    assign debug_dmem_addr  = dmem_addr;
    assign debug_dmem_wdata = dmem_wdata;
    assign debug_dmem_we    = dmem_we;

    pipelined_processor CPU (
        .clk1(clk),
        .rst(~rst_n),

        // Instruction memory bus
        .imem_addr(pc),
        .imem_data(imem_data),

        // Data memory bus
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we),
        .mem_req(dmem_req),
        .dmem_rdata(dmem_rdata),
        .branch_taken(branch_taken),

        // Diagnostics / Stall
        .pc_out(),
        .alu_res(),
        .isStall(),
        .waitrequest (cpu_waitrequest)
    );

    instruction_memory_wrapper #(
        .DEPTH(1024)
    ) IMEM (
        .clk(clk),
        .rst_n(rst_n),
        .stall(dmem_waitrequest),
        .pc(pc),
        .instruction(imem_data),
        .waitrequest(imem_waitrequest),
        .branch_taken(branch_taken)
    );

    vipt_cache CACHE (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_request(dmem_req),
        .cpu_ack(~dmem_req),
        .store_req(dmem_we),
        .va(dmem_addr),
        .cpu_wdata(dmem_wdata),
        .cpu_rdata(dmem_rdata),
        .cache_busy(cache_busy),
        .cache_hit(),
        .cpu_done(),
        .cache_done(),
        .cache_fault(),
        .updated_pt(20'b0),

        .pw_mem_req(pw_mem_req),
        .pw_mem_addr(pw_mem_addr),
        .pw_mem_rdata (pw_mem_rdata),
        .pw_mem_rvalid(pw_mem_rvalid),
        .mm_read_req(cache_mm_read_req),
        .mm_raddr(cache_mm_raddr),
        .mm_rdata(cache_mm_rdata),
        .mm_rvalid(cache_mm_rvalid),
        .mm_write_req(ext_mem_write_req),
        .mm_waddr(ext_mem_write_addr),
        .mm_wdata(ext_mem_write_data),
        .mm_wdone(ext_mem_write_done)
    );

    mem_arbiter ARBITER (
        .clk(clk),
        .rst_n(rst_n),

        .m0_req(pw_mem_req),
        .m0_addr(pw_mem_addr[14:2]),
        .m0_rdata (pw_mem_rdata),
        .m0_rvalid(pw_mem_rvalid),


        .m1_req(cache_mm_read_req),
        .m1_addr(cache_mm_raddr),
        .m1_burst_lock(cache_mm_read_req),
        .m1_rdata(cache_mm_rdata),
        .m1_rvalid(cache_mm_rvalid),
        .mem_read_req(ext_mem_read_req),
        .mem_read_addr(ext_mem_read_addr),
        .mem_read_data(ext_mem_read_data),
        .mem_read_valid(ext_mem_read_valid)
    );

    // main_memory MEM (
    //     .clk(clk),
    //     .rst_n(rst_n),

    //     // Read port (driven by arbiter)
    //     .read_req (arb_mem_read_req),
    //     .read_addr(arb_mem_read_addr),
    //     .read_data (mem_rdata),
    //     .read_valid (mem_rvalid),

    //     // Write port (driven by cache write-through)
    //     .write_req  (cache_mm_write_req),
    //     .write_addr (cache_mm_waddr),
    //     .write_data (cache_mm_wdata),
    //     .write_done (cache_mm_wdone)
    // );

endmodule
