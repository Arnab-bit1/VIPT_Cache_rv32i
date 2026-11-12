module instruction_memory_wrapper #(
    parameter DEPTH = 1024
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] pc,
    output wire [31:0] instruction,
    output reg waitrequest,
    input wire branch_taken,
    input wire stall
);

    reg [31:0] rom [0:DEPTH-1];

    reg state;
    localparam FETCH = 1'b0;
    localparam VALID = 1'b1;

    reg [31:0] instruction_reg;
    assign instruction = instruction_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instruction_reg <= 32'h0000_0013;
        end else if (branch_taken) begin
            instruction_reg <= 32'h0000_0013;
        end else if (!stall && (state == FETCH)) begin
            instruction_reg <= rom[pc[11:2]];
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= FETCH;
            waitrequest <= 1'b1;
        end else if (!stall) begin
            case (state)
                FETCH: begin
                    state       <= VALID;
                    waitrequest <= 1'b0;
                end
                VALID: begin
                    state       <= FETCH;
                    waitrequest <= 1'b1;
                end
            endcase
        end
    end

endmodule
