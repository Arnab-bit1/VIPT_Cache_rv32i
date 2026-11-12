module mmu_controller(
    input clk, rst_n,
    input cpu_request,
    input [19:0] vpn_in,
    input ack,
    output logic [19:0] mmu_ppn,        //MISSING
    output logic fault,
    output logic done,
    input  logic [31:0] pw_mem_rdata,
    input  logic pw_mem_rvalid,
    output logic pw_mem_req,
    output logic [31:0] pw_mem_addr
);
    logic tlb_hit, pw_start, pw_done, pw_fault;
    logic tlb_update;
    logic [19:0] tlb_ppn;
    logic [19:0] vpn_reg;
    logic [19:0] pw_ppn;
    logic [19:0] updated_ppn;
    logic tlb_update_valid;

    mmu_table TLB (.clk(clk),
    .rst_n(rst_n),
    .hit(tlb_hit),
    .vpn(vpn_reg),
    .update(tlb_update),
    .update_valid(tlb_update_valid),
    .updated_ppn(updated_ppn),
    .cs(1'b1),
    .ppn(tlb_ppn));

    page_table PAGE_WALKER (
    .clk(clk),
    .rst_n(rst_n),
    .start(pw_start),
    .vpn(vpn_reg),
    .ppn(pw_ppn),
    .done(pw_done),
    .comparison_done(ack),
    .fault(pw_fault),

    .mem_req(pw_mem_req),
    .mem_addr(pw_mem_addr),
    .mem_rdata(pw_mem_rdata),
    .mem_rvalid(pw_mem_rvalid)
);

    typedef enum logic [3:0]
    {IDLE,
    TLB_LOOKUP,
    TLB_CHECK,
    WALK_START,
    WALK_WAIT,
    TLB_REFILL,
    TL_DONE,
    PAGE_FAULT} state_t;

    state_t state;

    always_ff @(posedge clk) begin : main
        if(!rst_n) begin
            pw_start <= 0;
            state <= IDLE;
            done <= 0;
            mmu_ppn <= 0;
            fault <= 0;
            pw_start <= 0;
            tlb_update <= 0;
            tlb_update_valid <= 0;
            vpn_reg <= 0;
            updated_ppn <= 0;
        end

        else begin
            case(state)
                IDLE: begin
                    done <= 0;
                    fault <= 0;
                    if(cpu_request) begin
                        state <= TLB_LOOKUP;
                        vpn_reg <= vpn_in;
                    end
                end

                TLB_LOOKUP: begin
                    state <= TLB_CHECK;
                end

                TLB_CHECK: begin
                    if(tlb_hit) begin
                        state <= TL_DONE;
                        done <= 1;
                        mmu_ppn <= tlb_ppn;         //IN CASE OF TLB HIT, TAKE PPN FROM TLB ITSELF
                    end

                    else begin
                        state <= WALK_START;
                    end
                end

                WALK_START: begin
                    pw_start <= 1;
                    state <= WALK_WAIT;
                end

                WALK_WAIT: begin
                    pw_start <= 0;
                    if(pw_done) begin
                        if(pw_fault) begin
                            state <= PAGE_FAULT;
                            mmu_ppn <= 0;
                            fault <= 1;
                        end

                        else begin
                            state <= TLB_REFILL;
                            updated_ppn <= pw_ppn;
                            mmu_ppn <= pw_ppn;              //OUTPUT PPN FROM PAGE WALKER
                            tlb_update <= 1;
                            tlb_update_valid <= 1;
                        end

                    end

                    else
                        state <= WALK_WAIT;
                end

                PAGE_FAULT: begin
                    if(ack) begin
                        state <= IDLE; //maybee??
                        fault <= 0;
                    end
                    else
                        state <= PAGE_FAULT;
                end

                TLB_REFILL: begin
                    tlb_update <= 0;
                    tlb_update_valid <= 0;
                    done <= 1;
                    state <= TL_DONE;
                end

                TL_DONE: begin
                    if(ack) begin
                        done <= 0;
                        state <= IDLE;
                    end
                    else
                        state <= TL_DONE;
                end

                default: state <= IDLE;
            endcase
        end
    end : main

endmodule
