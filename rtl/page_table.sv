//PAGE WALKER

module page_table (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [19:0] vpn,
    input  logic        comparison_done,
    output logic [19:0] ppn,
    output logic        done,
    output logic        fault,
    output logic        mem_req,
    output logic [31:0] mem_addr,
    input  logic [31:0] mem_rdata,
    input  logic        mem_rvalid,
    output logic        busy
);

    logic [19:0] vpn_reg;

    //localparam IDLE = 'd0, L1_REQUEST = 'd1, L1_WAIT = 'd2, L2_REQUEST = 'd3, L2_WAIT = 'd4;

    typedef enum logic [2:0] {IDLE,
    L1_REQUEST,
    L1_WAIT,
    L2_REQUEST,
    L2_WAIT,
    DONE} state_t;

    logic [31:0] l1_pte_addr, l2_pte_addr;
    logic [31:0] ptbr = 32'b0;
    logic [19:0] l2_ppn;

    state_t state;

    always_comb begin
        l1_pte_addr = ptbr + {vpn[19:10], 2'b00};
        l2_pte_addr = {l2_ppn[19:0], vpn_reg[9:0], 2'b00};
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            vpn_reg <= 0;
            state <= IDLE;
            mem_addr <= 0;
            done <= 0;
            fault <= 0;
            ppn <= 0;
            done <= 0;
            mem_req <= 0;
        end

        else begin
            case(state)
                IDLE: begin
                    fault <= 0;
                    if(start) begin
                        vpn_reg <= vpn;
                        busy <= 1;
                        state <= L1_REQUEST;
                    end
                    else begin
                        state <= IDLE;
                        busy <= 0;
                    end
                end

                L1_REQUEST: begin
                    mem_req <= 1;
                    mem_addr <= l1_pte_addr;
                    state <= L1_WAIT;
                end

                L1_WAIT: begin
                    mem_req <= 1'b0;
                    if (mem_rvalid) begin
                        if (!mem_rdata[0]) begin
                            fault <= 1'b1;
                            ppn   <= 20'd0;
                            done  <= 1'b1;
                            state <= DONE;
                        end else if (mem_rdata[1] == 1'b0 && mem_rdata[3] == 1'b0) begin
                            fault  <= 1'b0;
                            l2_ppn <= mem_rdata[29:10]; // Standard SV32 PPN field
                            state  <= L2_REQUEST;
                        end else begin
                            fault <= 1'b1;
                            done  <= 1'b1;
                            state <= DONE;
                        end
                    end
                end


                L2_REQUEST: begin
                    mem_req <= 1;
                    mem_addr <= l2_pte_addr;
                    state <= L2_WAIT;
                end

                L2_WAIT: begin
                    mem_req <= 1'b0;
                    if (mem_rvalid) begin
                        done <= 1'b1;
                        // Leaf check: V=1 (bit 0) and (R=1 (bit 1) or X=1 (bit 3))
                        if (!mem_rdata[0] || (mem_rdata[1] == 1'b0 && mem_rdata[3] == 1'b0)) begin
                            fault <= 1'b1;
                            ppn   <= 20'd0;
                            state <= DONE;
                        end else begin
                            fault <= 1'b0;
                            ppn   <= mem_rdata[29:10]; // Final physical frame number
                            state <= DONE;
                        end
                    end
                end

                DONE: begin
                    if(comparison_done) begin
                        state <= IDLE;
                        done <= 0;
                        busy <= 0;
                    end
                    else begin
                        state <= DONE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
