module mem_arbiter (
    input logic clk,
    input logic rst_n,

    // Master 0: Page Table Walker (High Priority)
    input logic m0_req,
    input logic [12:0] m0_addr,
    output logic [31:0] m0_rdata,
    output logic m0_rvalid,

    // Master 1: Cache Refill (Low Priority)
    input logic m1_req,
    input logic [12:0] m1_addr,
    input logic m1_burst_lock,
    output logic [31:0] m1_rdata,
    output logic m1_rvalid,

    // Backing Main Memory Port
    output logic mem_read_req,
    output logic [12:0] mem_read_addr,
    input logic [31:0] mem_read_data,
    input logic mem_read_valid
);

    typedef enum logic [1:0] {
        IDLE,
        WAIT_M0,
        WAIT_M1
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            mem_read_req <= 1'b0;
            mem_read_addr <= 10'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (m0_req) begin
                        mem_read_req <= 1'b1;
                        mem_read_addr <= m0_addr;
                        state <= WAIT_M0;
                    end else if (m1_req) begin
                        mem_read_req <= 1'b1;
                        mem_read_addr <= m1_addr;
                        state <= WAIT_M1;
                    end else begin
                        mem_read_req <= 1'b0;
                    end
                end

                WAIT_M0: begin
                    mem_read_req <= 1'b0;
                    if (mem_read_valid) begin
                        state <= IDLE;
                    end
                end

                WAIT_M1: begin
                    mem_read_req <= 1'b0;
                    if (mem_read_valid) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign m0_rdata = mem_read_data;
    assign m0_rvalid = mem_read_valid && (state == WAIT_M0);

    assign m1_rdata = mem_read_data;
    assign m1_rvalid = mem_read_valid && (state == WAIT_M1);
endmodule
