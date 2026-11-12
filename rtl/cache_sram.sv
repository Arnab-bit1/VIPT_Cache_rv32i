module cache_sram (
    input logic clk,
    input logic rst_n,
    input logic mem_req,
    input logic we,
    input logic [9:0] addr_in,
    input logic [31:0] data_in,
    output logic mem_valid,
    output logic mem_wvalid,
    output logic [31:0] data_out
);

    logic bank_sel0, bank_sel_q;
    logic [8:0] bank_addr;
    assign bank_sel0 = addr_in[9];
    assign bank_addr = addr_in[8:0];

    logic web0;
    assign web0 = ~(mem_req && we);

    logic [3:0] wmask0 = (mem_req && we)? 4'b1111: 4'b0000;
    logic csb0_b0 = ~(mem_req && (bank_sel0 == 1'b0));
    logic csb0_b1 = ~(mem_req && (bank_sel0 == 1'b1));

    logic [31:0] dout0, dout1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_valid <= 0;
            mem_wvalid <= 0;
            bank_sel_q <= 0;
        end

        else begin
            mem_valid <= mem_req && !we;
            mem_wvalid <= mem_req && we;
            if(mem_req && !we) begin
                bank_sel_q <= bank_sel0;
            end
        end

    end

    `ifdef SYNTHESIS
    // ================================================================
    // Physical Hard Macros (Active during Yosys / OpenLane Synthesis)
    // ================================================================
    wire csb0_b0 = ~(mem_req && (bank_sel == 1'b0));
    wire csb0_b1 = ~(mem_req && (bank_sel == 1'b1));
    wire web0    = ~(mem_req && we);
    wire [3:0] wmask0 = (mem_req && we) ? 4'b1111 : 4'b0000;

    wire [31:0] dout0_b0;
    wire [31:0] dout0_b1;

    assign data_out = bank_sel_q ? dout0_b1 : dout0_b0;

    sky130_sram_2kbyte_1rw1r_32x512_8 BANK0 (
        .clk0   (clk),
        .csb0   (csb0_b0),
        .web0   (web0),
        .wmask0 (wmask0),
        .addr0  (bank_addr),
        .din0   (data_in),
        .dout0  (dout0_b0),
        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (9'd0),
        .dout1  ()
    );

    sky130_sram_2kbyte_1rw1r_32x512_8 BANK1 (
        .clk0   (clk),
        .csb0   (csb0_b1),
        .web0   (web0),
        .wmask0 (wmask0),
        .addr0  (bank_addr),
        .din0   (data_in),
        .dout0  (dout0_b1),
        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (9'd0),
        .dout1  ()
    );

`else
    // ================================================================
    // Behavioral Model (Active during Vivado / Icarus / Verilator)
    // Accurately models 1-cycle synchronous read latency without races
    // ================================================================
    reg [31:0] bank0_mem [0:511];
    reg [31:0] bank1_mem [0:511];
    reg [31:0] dout0_b0;
    reg [31:0] dout0_b1;

    always_ff @(posedge clk) begin
        if (mem_req && (bank_sel0 == 1'b0)) begin
            if (we) begin
                bank0_mem[bank_addr] <= data_in;
            end else begin
                dout0_b0 <= bank0_mem[bank_addr];
            end
        end

        if (mem_req && (bank_sel0 == 1'b1)) begin
            if (we) begin
                bank1_mem[bank_addr] <= data_in;
            end else begin
                dout0_b1 <= bank1_mem[bank_addr];
            end
        end
    end

    assign data_out = bank_sel_q ? dout0_b1 : dout0_b0;

`endif

endmodule
