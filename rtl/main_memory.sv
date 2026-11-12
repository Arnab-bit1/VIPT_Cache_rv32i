module main_memory (
    input  logic clk,
    input  logic rst_n,

    input  logic read_req,
    input  logic [12:0] read_addr,
    output logic [31:0] read_data,
    output logic read_valid,

    input  logic write_req,
    input  logic [12:0] write_addr,
    input  logic [31:0] write_data,
    output logic write_done
);

    logic [31:0] mem [8192];

    always @(posedge clk) begin
        read_valid <= 0;
        write_done <= 0;
        if(!rst_n) begin
            read_data <= 0;
            read_valid <= 0;
            write_done <= 0;
        end

        else if(read_req) begin
            read_data <= mem[read_addr];
            read_valid <= 1;
        end

        else if(write_req) begin
            mem[write_addr] <= write_data;
            write_done <= 1;
        end

        else begin
            read_data <= 0;
            read_valid <= 0;
            write_done <= 0;
        end
    end

endmodule
