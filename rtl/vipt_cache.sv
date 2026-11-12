module vipt_cache (
    input logic clk, rst_n, cpu_request,
    input logic cpu_ack,
    input logic [31:0] va,
    input logic [31:0] cpu_wdata,
    input logic [19:0] updated_pt,
    output logic [31:0] cpu_rdata,
    output logic cache_hit,
    output logic cpu_done,
    output logic cache_done, cache_fault,
    output logic [3:0] mem_req,
    input logic [31:0] pw_mem_rdata,
    input logic pw_mem_rvalid,
    input logic store_req,
    output logic pw_mem_req,
    output logic [31:0] pw_mem_addr,
    output logic cache_busy,
    input logic [31:0] mm_rdata,
    output logic [31:0] mm_wdata,
    output logic [12:0] mm_raddr,
    output logic [12:0] mm_waddr,
    input logic mm_rvalid,
    input logic mm_wdone,
    output logic mm_read_req,
    output logic mm_write_req
);

    logic valid_mem [64][4];
    logic [3:0] valid_bits;
    logic [19:0] vpn;
    logic [5:0] set_index;
    logic [5:0] byte_offset;
    logic [19:0] tlb_ppn_reg;
    logic [3:0] hit_way, hit_way_reg;
    logic [1:0] lru [64][4];
    logic [3:0] word_count;
    logic [1:0] data_way;

    logic [3:0] word_offset;

    logic mmu_done, mmu_fault;
    logic [3:0] refill_addr;

    //DATA SRAM SIGNALS
    logic [3:0] sram_we;
    logic [31:0] sram_data [4];
    logic [31:0] sram_data_out [4];
    logic [3:0] sram_valid;
    logic [9:0] sram_addr [4];
    logic [3:0] sram_wvalid;

    //TAG SRAM SIGNALS
    logic [3:0] tag_we;
    logic [19:0] tag_data[4];
    logic [3:0] tag_valid;
    logic [6:0] tag_addr[4];
    logic [3:0] tag_req;
    logic [3:0] tag_wvalid;
    logic [31:0] cpu_rdata_reg;

    //MAIN MEMORY SIGNALS

    logic [4:0] req_word;    // 0 to 16: tracks words requested from main memory
    logic [4:0] write_word;  // 0 to 16: tracks words written to SRAM

    assign vpn = va[31:12];
    assign set_index = va[11:6];
    assign byte_offset = va[5:0];
    assign cache_hit = |hit_way;
    assign cpu_rdata = cpu_rdata_reg;

    mmu_controller CTRL (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_request(cpu_request),
        .vpn_in(vpn),
        .ack(cpu_ack),
        .done(mmu_done),
        .fault(mmu_fault),
        .mmu_ppn(tlb_ppn_reg),

        .pw_mem_req(pw_mem_req),
        .pw_mem_addr(pw_mem_addr),
        .pw_mem_rdata(pw_mem_rdata),
        .pw_mem_rvalid(pw_mem_rvalid)
    );

    cache_sram SRAM_W0 (.clk(clk), .rst_n(rst_n), .addr_in(sram_addr[0]), .mem_valid(sram_valid[0]),
    .data_out(sram_data_out[0]), .mem_req(mem_req[0]), .we(sram_we[0]), .data_in(sram_data[0]),
    .mem_wvalid(sram_wvalid[0]));

    cache_sram SRAM_W1 (.clk(clk), .rst_n(rst_n), .addr_in(sram_addr[1]), .mem_valid(sram_valid[1]),
    .data_out(sram_data_out[1]), .mem_req(mem_req[1]), .we(sram_we[1]), .data_in(sram_data[1]),
    .mem_wvalid(sram_wvalid[1]));

    cache_sram SRAM_W2 (.clk(clk), .rst_n(rst_n), .addr_in(sram_addr[2]), .mem_valid(sram_valid[2]),
    .data_out(sram_data_out[2]), .mem_req(mem_req[2]), .we(sram_we[2]), .data_in(sram_data[2]),
    .mem_wvalid(sram_wvalid[2]));

    cache_sram SRAM_W3 (.clk(clk), .rst_n(rst_n), .addr_in(sram_addr[3]), .mem_valid(sram_valid[3]),
    .data_out(sram_data_out[3]), .mem_req(mem_req[3]), .we(sram_we[3]), .data_in(sram_data[3]),
    .mem_wvalid(sram_wvalid[3]));

    tag_sram TAG_W0 (.clk(clk), .rst_n(rst_n), .tag_we(tag_we[0]), .tag_addr(tag_addr[0]),
    .tag_valid(tag_valid[0]), .tag_wvalid(tag_wvalid[0]), .tag_req(tag_req[0]), .tag(tag_data[0]),
    .updated_tag(tlb_ppn_reg));

    tag_sram TAG_W1 (.clk(clk), .rst_n(rst_n), .tag_we(tag_we[1]), .tag_addr(tag_addr[1]),
    .tag_valid(tag_valid[1]), .tag_wvalid(tag_wvalid[1]), .tag_req(tag_req[1]), .tag(tag_data[1]),
    .updated_tag(tlb_ppn_reg));

    tag_sram TAG_W2 (.clk(clk), .rst_n(rst_n), .tag_we(tag_we[2]), .tag_addr(tag_addr[2]),
    .tag_valid(tag_valid[2]), .tag_wvalid(tag_wvalid[2]), .tag_req(tag_req[2]), .tag(tag_data[2]),
    .updated_tag(tlb_ppn_reg));

    tag_sram TAG_W3 (.clk(clk), .rst_n(rst_n), .tag_we(tag_we[3]), .tag_addr(tag_addr[3]),
    .tag_valid(tag_valid[3]), .tag_wvalid(tag_wvalid[3]), .tag_req(tag_req[3]), .tag(tag_data[3]),
    .updated_tag(tlb_ppn_reg));

    typedef enum logic [3:0] {
        IDLE,
        MMU_LOOKUP,
        FAULT,
        SRAM_READ_WAIT,
        MAIN_MEM_READ,
        MAIN_MEM_WRITE,
        TAG_WAIT,
        WRITE_WAIT,
        DONE,
        REFILL
    } state_t;

    state_t state;

    typedef enum logic [1:0] {
        FILL_REQ_MEM,   // Ask main memory for word
        FILL_WAIT_MEM,  // Wait for main memory read data
        FILL_WRITE_SRAM // Write word to SRAM and wait for SRAM confirmation
    } fill_step_t;

    fill_step_t fill_step;
    logic [3:0] fill_word; // Tracks words 0 to 15

    always @(posedge clk) begin
        cpu_done <= 0;
        if(!rst_n) begin
            state <= IDLE;
            cache_fault <= 0;
            cache_done <= 0;
            cpu_done <= 0;
            mem_req <= 0;
            word_count <= 0;
            tag_we <= 4'b0;
            tag_req <= 0;
            mm_read_req <= 0;
            mm_write_req <= 0;
            mm_raddr <= 0;
            mm_wdata <= 0;
            mm_waddr <= 0;

            for(int i = 0; i < 64; i++) begin
                lru[i][0] <= 2'b00;
                lru[i][1] <= 2'b01;
                lru[i][2] <= 2'b10;
                lru[i][3] <= 2'b11;
                valid_mem[i][0] <= 0;
                valid_mem[i][1] <= 0;
                valid_mem[i][2] <= 0;
                valid_mem[i][3] <= 0;
            end

        end

        else begin
            case (state)
                IDLE: begin
                    cache_fault <= 0;
                    cache_done <= 0;
                    if(cpu_request) begin
                        tag_req <= 4'b1111;
                        tag_we <= 4'b0000;
                        tag_addr[0] <= set_index;
                        tag_addr[1] <= set_index;
                        tag_addr[2] <= set_index;
                        tag_addr[3] <= set_index;
                        state <= MMU_LOOKUP;
                    end
                end

                MMU_LOOKUP: begin
                    if (mmu_fault) begin
                        state <= FAULT;
                        cache_fault <= 1;
                    end

                    else if (mmu_done && tag_valid == 4'b1111) begin
                        if(cache_hit && store_req) begin
                            mm_read_req <= 0;
                            mm_write_req <= 1;
                            mm_waddr <= {tlb_ppn_reg[2:0], set_index, word_offset};
                            mm_wdata <= cpu_wdata;

                            case(hit_way)
                            4'b0001: begin
                                mem_req <= 4'b0001;
                                sram_we <= 4'b0001;
                                sram_addr[0] <= {set_index, word_offset};
                                sram_data[0] <= cpu_wdata;
                            end

                            4'b0010: begin
                                mem_req <= 4'b0010;
                                sram_we <= 4'b0010;
                                sram_addr[1] <= {set_index, word_offset};
                                sram_data[1] <= cpu_wdata;
                            end

                            4'b0100: begin
                                mem_req <= 4'b0100;
                                sram_we <= 4'b0100;
                                sram_addr[2] <= {set_index, word_offset};
                                sram_data[2] <= cpu_wdata;
                            end

                            4'b1000: begin
                                mem_req <= 4'b1000;
                                sram_we <= 4'b1000;
                                sram_addr[3] <= {set_index, word_offset};
                                sram_data[3] <= cpu_wdata;
                            end

                            default: begin  end
                            endcase

                            state <= WRITE_WAIT;
                        end
                        else if(cache_hit && !store_req) begin
                            hit_way_reg <= hit_way;
                            mem_req <= 4'b1111;
                            sram_we <= 4'b0000;

                            sram_addr[0] <= {set_index, word_offset};
                            sram_addr[1] <= {set_index, word_offset};
                            sram_addr[2] <= {set_index, word_offset};
                            sram_addr[3] <= {set_index, word_offset};

                            state <= SRAM_READ_WAIT;
                        end

                        else if(!cache_hit && !store_req) begin
                            state       <= REFILL;
                            fill_step   <= FILL_REQ_MEM;
                            fill_word   <= 4'd0;
                            mm_read_req <= 1'b0;
                        end

                        else begin
                            state <= MAIN_MEM_WRITE;
                            mm_write_req <= 1;
                            mm_read_req <= 0;
                            mm_waddr <= {tlb_ppn_reg[2:0], set_index, word_offset};
                            mm_wdata <= cpu_wdata;
                        end
                    end

                    else begin
                        state <= MMU_LOOKUP;
                    end

                end

                SRAM_READ_WAIT: begin
                    if(sram_valid == 4'b1111) begin
                        mem_req <= 4'b0000;
                        cache_done <= 1;
                        state <= DONE;

                        if(hit_way_reg[0]) begin
                            cpu_rdata_reg <= sram_data_out[0];
                            cpu_done <= 1;
                        end
                        else if(hit_way_reg[1]) begin
                            cpu_rdata_reg <= sram_data_out[1];
                            cpu_done <= 1;
                        end
                        else if(hit_way_reg[2]) begin
                            cpu_rdata_reg <= sram_data_out[2];
                            cpu_done <= 1;
                        end
                        else if(hit_way_reg[3]) begin
                            cpu_rdata_reg <= sram_data_out[3];
                            cpu_done <= 1;
                        end
                    end

                    else begin
                        state <= SRAM_READ_WAIT;
                    end
                end

                WRITE_WAIT: begin
                    if(|sram_wvalid && mm_wdone) begin
                        sram_we <= 0;
                        mm_write_req <= 0;
                        mm_waddr <= 0;
                        mem_req <= 0;
                        cache_busy <= 0;
                        state <= DONE;
                        cache_done <= 1;
                    end

                    else begin
                        state <= WRITE_WAIT;
                    end
                end

                MAIN_MEM_READ: begin
                    if(mm_rvalid) begin
                        state <= REFILL; //START REFILLING NOW
                        cpu_rdata_reg <= mm_rdata;
                    end

                    else begin
                        state <= MAIN_MEM_READ;
                    end
                end

                MAIN_MEM_WRITE: begin
                    if(mm_wdone) begin
                        cache_done <= 1;
                        state <= DONE;
                    end
                end

                FAULT: begin
                    if(cpu_ack) begin
                        cache_fault <= 0;
                        state <= IDLE;
                    end

                    else begin
                        state <= FAULT;
                    end
                end

                REFILL: begin
                case (fill_step)

                    FILL_REQ_MEM: begin
                        mm_read_req <= 1'b1;
                        mm_raddr <= {tlb_ppn_reg[2:0], set_index, fill_word};
                        sram_we     <= 4'b0000;
                        mem_req     <= 4'b0000;
                        fill_step   <= FILL_WAIT_MEM;
                    end

                    FILL_WAIT_MEM: begin
                        mm_read_req <= 1'b0; // De-assert pulse
                        if (mm_rvalid) begin
                            // EARLY RESTART
                            if (fill_word == word_offset) begin
                                cpu_rdata_reg <= mm_rdata;
                                cpu_done      <= 1'b1;
                            end

                            casez (valid_bits)
                                4'b0???: begin
                                    sram_we[0]   <= 1'b1;
                                    mem_req[0]   <= 1'b1;
                                    sram_addr[0] <= {set_index, fill_word};
                                    sram_data[0] <= mm_rdata;
                                end
                                4'b10??: begin
                                    sram_we[1]   <= 1'b1;
                                    mem_req[1]   <= 1'b1;
                                    sram_addr[1] <= {set_index, fill_word};
                                    sram_data[1] <= mm_rdata;
                                end
                                4'b110?: begin
                                    sram_we[2]   <= 1'b1;
                                    mem_req[2]   <= 1'b1;
                                    sram_addr[2] <= {set_index, fill_word};
                                    sram_data[2] <= mm_rdata;
                                end
                                4'b1110: begin
                                    sram_we[3]   <= 1'b1;
                                    mem_req[3]   <= 1'b1;
                                    sram_addr[3] <= {set_index, fill_word};
                                    sram_data[3] <= mm_rdata;
                                end
                                default: begin // 4'b1111: LRU replacement
                                    // Write to whichever way has lru == 2'b00
                                    if (lru[set_index][0] == 2'b00) begin
                                        sram_we[0] <= 1'b1; mem_req[0] <= 1'b1;
                                        sram_addr[0] <= {set_index, fill_word}; sram_data[0] <= mm_rdata;
                                    end else if (lru[set_index][1] == 2'b00) begin
                                        sram_we[1] <= 1'b1; mem_req[1] <= 1'b1;
                                        sram_addr[1] <= {set_index, fill_word}; sram_data[1] <= mm_rdata;
                                    end else if (lru[set_index][2] == 2'b00) begin
                                        sram_we[2] <= 1'b1; mem_req[2] <= 1'b1;
                                        sram_addr[2] <= {set_index, fill_word}; sram_data[2] <= mm_rdata;
                                    end else begin
                                        sram_we[3] <= 1'b1; mem_req[3] <= 1'b1;
                                        sram_addr[3] <= {set_index, fill_word}; sram_data[3] <= mm_rdata;
                                    end
                                end
                            endcase

                            fill_step <= FILL_WRITE_SRAM;
                        end
                    end

                    FILL_WRITE_SRAM: begin
                        if (|sram_wvalid) begin
                            sram_we <= 4'b0000;
                            mem_req <= 4'b0000;

                            if (fill_word == 4'd15) begin
                                // All 16 words safely in SRAM -> Update tags
                                casez (valid_bits)
                                    4'b0???: begin
                                        tag_req[0] <= 1'b1;
                                        tag_we[0] <= 1'b1;
                                        tag_addr[0] <= set_index;
                                        valid_mem[set_index][0] <= 1'b1; 
                                        lru[set_index][0] <= 2'b11;
                                    end
                                    4'b10??: begin
                                        tag_req[1] <= 1'b1; 
                                        tag_we[1] <= 1'b1; 
                                        tag_addr[1] <= set_index;
                                        valid_mem[set_index][1] <= 1'b1; 
                                        lru[set_index][1] <= 2'b11;
                                        lru[set_index][0] <= 2'b10;
                                    end
                                    4'b110?: begin
                                        tag_req[2] <= 1'b1; 
                                        tag_we[2] <= 1'b1; 
                                        tag_addr[2] <= set_index;
                                        valid_mem[set_index][2] <= 1'b1; 
                                        lru[set_index][2] <= 2'b11;
                                        lru[set_index][0] <= 2'b01; lru[set_index][1] <= 2'b10;
                                    end
                                    4'b1110: begin
                                        tag_req[3] <= 1'b1; tag_we[3] <= 1'b1; tag_addr[3] <= set_index;
                                        valid_mem[set_index][3] <= 1'b1; lru[set_index][3] <= 2'b11;
                                        lru[set_index][0] <= 2'b00; lru[set_index][1] <= 2'b01; lru[set_index][2] <= 2'b10;
                                    end
                                    default: begin
                                        // Replacement tag updates
                                        if (lru[set_index][0] == 2'b00) begin
                                            tag_req[0] <= 1'b1; tag_we[0] <= 1'b1; tag_addr[0] <= set_index;
                                            lru[set_index][0] <= 2'b11;
                                            lru[set_index][1] <= lru[set_index][1] - 1;
                                            lru[set_index][2] <= lru[set_index][2] - 1;
                                            lru[set_index][3] <= lru[set_index][3] - 1;
                                        end else if (lru[set_index][1] == 2'b00) begin
                                            tag_req[1] <= 1'b1; tag_we[1] <= 1'b1; tag_addr[1] <= set_index;
                                            lru[set_index][1] <= 2'b11;
                                            lru[set_index][0] <= lru[set_index][0] - 1;
                                            lru[set_index][2] <= lru[set_index][2] - 1;
                                            lru[set_index][3] <= lru[set_index][3] - 1;
                                        end else if (lru[set_index][2] == 2'b00) begin
                                            tag_req[2] <= 1'b1; tag_we[2] <= 1'b1; tag_addr[2] <= set_index;
                                            lru[set_index][2] <= 2'b11;
                                            lru[set_index][0] <= lru[set_index][0] - 1;
                                            lru[set_index][1] <= lru[set_index][1] - 1;
                                            lru[set_index][3] <= lru[set_index][3] - 1;
                                        end else begin
                                            tag_req[3] <= 1'b1; tag_we[3] <= 1'b1; tag_addr[3] <= set_index;
                                            lru[set_index][3] <= 2'b11;
                                            lru[set_index][0] <= lru[set_index][0] - 1;
                                            lru[set_index][1] <= lru[set_index][1] - 1;
                                            lru[set_index][2] <= lru[set_index][2] - 1;
                                        end
                                    end
                                endcase
                                state <= TAG_WAIT;
                            end else begin
                                // Move to the next word
                                fill_word <= fill_word + 4'd1;
                                fill_step <= FILL_REQ_MEM;
                            end
                        end
                    end

                endcase
            end

                TAG_WAIT: begin
                    if(|tag_wvalid) begin
                        cache_done <= 1;
                        state <= DONE;
                    end
                end

                DONE: begin
                    cache_done <= 0;
                    cpu_done   <= 0;

                    if(cpu_request) begin
                        tag_req <= 4'b1111;
                        tag_we  <= 4'b0000;

                        tag_addr[0] <= set_index;
                        tag_addr[1] <= set_index;
                        tag_addr[2] <= set_index;
                        tag_addr[3] <= set_index;

                        state <= MMU_LOOKUP;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    always_comb begin
        hit_way[0] = valid_mem[set_index][0] &&
                    (tag_data[0] == tlb_ppn_reg);

        hit_way[1] = valid_mem[set_index][1] &&
                    (tag_data[1] == tlb_ppn_reg);

        hit_way[2] = valid_mem[set_index][2] &&
                    (tag_data[2] == tlb_ppn_reg);

        hit_way[3] = valid_mem[set_index][3] &&
                    (tag_data[3] == tlb_ppn_reg);
    end

    always_comb begin
        valid_bits = {valid_mem[set_index][0],
                    valid_mem[set_index][1],
                    valid_mem[set_index][2],
                    valid_mem[set_index][3]};
    end

    always_comb begin
        if(hit_way[0])
            data_way = 2'b0;

        else if(hit_way[1])
            data_way = 2'b01;

        else if(hit_way[2])
            data_way = 2'b10;

        else
            data_way = 2'b11;
    end

    always_comb begin
        if (state == IDLE) begin
            cache_busy = cpu_request;
        end
        else if (state == DONE) begin
            cache_busy = 0;
        end
        else begin
            cache_busy = 1;
        end
    end
    assign word_offset = byte_offset[5:2];

endmodule
