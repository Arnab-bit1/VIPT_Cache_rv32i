`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.06.2025 13:37:45
// Design Name: 
// Module Name: pipelined_processor
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pipelined_processor(
    input clk1, rst,
    output [31:0] imem_addr,
    input  [31:0] imem_data,
    output [31:0] dmem_addr,
    output [31:0] dmem_wdata,
    output dmem_we,
    output mem_req,
    input  [31:0] dmem_rdata,
    output [31:0] pc_out,
    output [31:0] alu_res,
    output isStall,
    input waitrequest,
    output branch_taken
    );

    reg isBranchTaken;
    reg b_cond;
    reg [31:0] branchPC;
    reg [31:0] pc;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg [31:0] of_ex_inst, of_ex_op2;
    reg [31:0] Reg [0:31];
    reg [31:0] if_of_pc, if_of_inst;
    reg [31:0] of_ex_pc;
    reg [31:0] branch_offset;
    reg [3:0] ALUOp;
    reg [4:0] of_ex_rs1_num, of_ex_rs2_num, of_ex_rd_num; 
    reg of_ex_isImmediate, ex_ma_isImmediate, ma_rw_isImmediate;
    reg isSt, isImmediate, isLd;
    reg [31:0] imm;
    reg [31:0] ex_ma_pc, ex_ma_inst, ex_ma_aluResult, ex_ma_op2;
    reg [31:0] aluResult;
    reg isUBranch, isBeq, isBneq;
    reg [3:0] of_ex_aluSignals;
    reg of_ex_isUBranch;
    reg of_ex_ld, of_ex_st, ex_ma_ld, ex_ma_st;
    reg [31:0] branch_target;
    reg [31:0] of_ex_branch_target;
    reg [31:0] mar, mdr, ldResult;
    reg [31:0] ma_rw_pc, ma_rw_ldResult, ma_rw_aluResult, ma_rw_inst;
    reg ma_rw_isSt, ma_rw_isLd;
    reg isWb, of_ex_isWb, ex_ma_isWb, ma_rw_isWb;
    reg [31:0] data;
    reg stall;
    reg [31:0] forward_a, forward_b;
    reg [31:0] store_data;
    integer k;

    assign branch_taken = isBranchTaken;

    // Standard RISC-V Base Opcodes (Bits 6:0)
    parameter OP_R_TYPE  = 7'b0110011; // ADD, SUB, MUL, AND, OR, XOR
    parameter OP_I_TYPE  = 7'b0010011; // ADDI, ANDI, ORI
    parameter OP_LOAD    = 7'b0000011; // LW (LD)
    parameter OP_STORE   = 7'b0100011; // SW (ST)
    parameter OP_BRANCH  = 7'b1100011; // BEQ, BNEQ
    parameter OP_JAL     = 7'b1101111; // Unconditional Jump (B)
    parameter OP_LUI = 7'b0110111; // LUI Opcode

    // Funct3 Codes (Bits 14:12) to tell instructions apart
    parameter F3_ADD_SUB = 3'b000;
    parameter F3_MUL     = 3'b000; // Requires funct7 = 0000001 (M-Extension)
    parameter F3_XOR     = 3'b100;
    parameter F3_OR      = 3'b110;
    parameter F3_AND     = 3'b111;
    parameter F3_BEQ     = 3'b000;
    parameter F3_BNE     = 3'b001;

    // Funct7 Codes (Bits 31:25) to separate ADD from SUB
    parameter F7_ADD     = 7'b0000000;
    parameter F7_SUB     = 7'b0100000;
    parameter F7_MUL     = 7'b0000001; 

    // Your existing ALU and Type parameters can stay exactly as they are!
    parameter R_TYPE = 2'b00, MEM_TYPE = 2'b01, B_TYPE = 2'b11;
    parameter ALU_ADD = 4'b0000, ALU_SUB = 4'b0001, ALU_MUL = 4'b0010, ALU_AND = 4'b0011, ALU_OR = 4'b0100, ALU_XOR = 4'b0101, NOP = 4'b0110;
              
    
    assign imem_addr = pc;
    //IF Stage
    always @ (posedge clk1 or posedge rst)
    begin
        if(rst) begin
            pc <= 32'h0001_0000;
            if_of_pc <= 32'h0000;
            if_of_inst <= 32'h0000;
        end
        else if(!(stall || waitrequest)) begin
            if(isBranchTaken) begin
                pc <= branchPC;
                if_of_inst <= 32'h0000_0013;
                if_of_pc <= 0;
            end
            else begin
                pc <= pc + 4'b0100;
                if_of_pc <= pc;
                if_of_inst <= imem_data;
            end

        end
    end

    //OF Stage (Decoder)
    always @ (*)
    begin
        isImmediate = 1'b0;
        isSt = 1'b0;
        isLd = 1'b0;
        imm = 32'h0000;
        isUBranch = 1'b0;
        isBeq = 1'b0;
        isBneq = 1'b0;
        isWb = 1'b0;
        ALUOp = NOP;
        case(if_of_inst[6:0]) // Slice the bottom 7 bits!
        
        OP_R_TYPE: begin
            isSt = 0; isImmediate = 0; isWb = 1;
            // Now check funct3 and funct7 to know which R-Type it is
            if (if_of_inst[14:12] == F3_ADD_SUB) begin
                if (if_of_inst[31:25] == F7_SUB) 
                    ALUOp = ALU_SUB; // It's a SUB
                else if (if_of_inst[31:25] == F7_MUL)
                    ALUOp = ALU_MUL; // It's a MUL (M-Extension)
                else 
                    ALUOp = ALU_ADD; // It's an ADD
            end
            else if (if_of_inst[14:12] == F3_AND) ALUOp = ALU_AND;
            else if (if_of_inst[14:12] == F3_OR)  ALUOp = ALU_OR;
            else if (if_of_inst[14:12] == F3_XOR) ALUOp = ALU_XOR;
        end

        OP_I_TYPE: begin
            isSt = 0; isImmediate = 1; isWb = 1; 
            imm = {{20{if_of_inst[31]}}, if_of_inst[31:20]}; // Standard RISC-V I-Type Immediate
            
            if (if_of_inst[14:12] == F3_ADD_SUB) ALUOp = ALU_ADD; // ADDI
            else if (if_of_inst[14:12] == F3_AND) ALUOp = ALU_AND; // ANDI
            else if (if_of_inst[14:12] == F3_OR)  ALUOp = ALU_OR;  // ORI
        end

        OP_LOAD: begin
            isSt = 0; isLd = 1; isImmediate = 1; isWb = 1; 
            imm = {{20{if_of_inst[31]}}, if_of_inst[31:20]}; 
            ALUOp = ALU_ADD; 
        end

        OP_STORE: begin
            isSt = 1; isImmediate = 1; 
            imm = {{20{if_of_inst[31]}}, if_of_inst[31:25], if_of_inst[11:7]}; // S-Type Immediate format
            ALUOp = ALU_ADD;
        end

        OP_BRANCH: begin
            isUBranch = 0; isImmediate = 0; 
            imm = {{20{if_of_inst[31]}}, if_of_inst[7], if_of_inst[30:25], if_of_inst[11:8], 1'b0}; // B-Type Immediate format
            ALUOp = ALU_SUB; // Subtract to compare
            if (if_of_inst[14:12] == F3_BEQ) isBeq = 1;
            else if (if_of_inst[14:12] == F3_BNE) isBneq = 1;
        end

        OP_JAL: begin
            isUBranch = 1; isImmediate = 1; 
            imm = {{12{if_of_inst[31]}}, if_of_inst[19:12], if_of_inst[20], if_of_inst[30:21], 1'b0}; // J-Type Immediate format
            ALUOp = NOP; 
        end
        
        OP_LUI: begin
            isSt = 0; isImmediate = 1; isWb = 1;
            // U-Type Immediate extraction
            imm = {if_of_inst[31:12], 12'b0}; 
            ALUOp = ALU_ADD;
        end

    endcase
        branch_target = if_of_pc + imm;
    end
    
    //OF/EX Pipeline Register
    always @ (posedge clk1 or posedge rst)
    begin
        if(rst) begin
            of_ex_inst <= 32'b0;
            of_ex_rs1_num <= 5'b0;
            of_ex_rs2_num <= 5'b0;
            of_ex_rd_num <= 5'b0;
            of_ex_op2 <= 32'b0;
            of_ex_aluSignals <= 4'b0;
            of_ex_pc <= 32'b0;
            of_ex_branch_target <= 32'b0;
            of_ex_isImmediate <= 1'b0;
            of_ex_isUBranch <= 1'b0;
            of_ex_ld <= 1'b0;
            of_ex_st <= 1'b0;
            of_ex_isWb <= 1'b0;
        end
        else if (waitrequest) begin
            // FREEZE: Do absolutely nothing. Hold all current values.
        end
        else if (isBranchTaken) begin 
            of_ex_inst <= 32'b0;
            of_ex_rs1_num <= 5'b0;
            of_ex_rs2_num <= 5'b0;
            of_ex_rd_num <= 5'b0;
            of_ex_op2 <= 32'b0;
            of_ex_aluSignals <= 4'b0;
            of_ex_pc <= 32'b0;
            of_ex_branch_target <= 32'b0;
            of_ex_isImmediate <= 1'b0;
            of_ex_isUBranch <= 1'b0;
            of_ex_ld <= 1'b0;
            of_ex_st <= 1'b0;
            of_ex_isWb <= 1'b0;
        end
        else if (stall) begin
            // FREEZE: Internal Load-Use Hazard. Hold state.
        end
        else begin
            of_ex_ld <= isLd;
            of_ex_st <= isSt;
            of_ex_inst <= if_of_inst;
            of_ex_aluSignals <= ALUOp;
            of_ex_isUBranch <= isUBranch;
            of_ex_isImmediate <= isImmediate;
            of_ex_rs1_num <= if_of_inst[19:15]; 
            of_ex_rs2_num <= if_of_inst[24:20];
            of_ex_rd_num  <= if_of_inst[11:7];
            of_ex_pc <= if_of_pc;
            of_ex_branch_target <= branch_target;
            of_ex_isWb <= isWb;
            if(isImmediate)
               of_ex_op2 <= imm;
            else
                of_ex_op2 <= Reg[if_of_inst[24:20]];
        end 
    end
    
    //EX Stage
    always@(*)
    begin
        
        
        operand_a = Reg[of_ex_rs1_num];
        operand_b = Reg[of_ex_rs2_num];
        
        stall = 1'b0;
        if (ex_ma_ld && (ex_ma_inst[11:7] != 5'b0) && ((ex_ma_inst[11:7] == of_ex_rs1_num) || (ex_ma_inst[11:7] == of_ex_rs2_num)))
            stall = 1'b1;
            
        forward_a = operand_a;
        forward_b = operand_b;
        
        if (ex_ma_isWb && (ex_ma_inst[11:7] != 5'b0) && (ex_ma_inst[11:7] == of_ex_rs1_num))
            forward_a = ex_ma_aluResult;
        else if (ma_rw_isWb && (ma_rw_inst[11:7] != 5'b0) && (ma_rw_inst[11:7] == of_ex_rs1_num))
            forward_a = data;
            
        if (ex_ma_isWb && (ex_ma_inst[11:7] != 5'b0) && (ex_ma_inst[11:7] == of_ex_rs2_num))
            forward_b = ex_ma_aluResult;
        else if (ma_rw_isWb && (ma_rw_inst[11:7] != 5'b0) && (ma_rw_inst[11:7] == of_ex_rs2_num))
            forward_b = data;
            
        store_data = forward_b;
            
        if(of_ex_isImmediate)
            forward_b = of_ex_op2;
        
        case(of_ex_aluSignals)
            ALU_ADD: aluResult = forward_a + forward_b;
            ALU_SUB: aluResult = forward_a - forward_b;
            ALU_MUL: aluResult = forward_a * forward_b;
            ALU_AND: aluResult = forward_a & forward_b;
            ALU_OR: aluResult = forward_a | forward_b;
            ALU_XOR: aluResult = forward_a ^ forward_b;
            default: aluResult = 32'b0;
        endcase
        
        isBranchTaken = (of_ex_isUBranch) || 
                        ((of_ex_inst[6:0] == OP_BRANCH) && (of_ex_inst[14:12] == F3_BEQ) && (aluResult == 0)) || 
                        ((of_ex_inst[6:0] == OP_BRANCH) && (of_ex_inst[14:12] == F3_BNE) && (aluResult != 0));
        branchPC = of_ex_branch_target;
    end
    
    //EX/MEM Pipeline Register
    always@(posedge clk1 or posedge rst)
    begin
        if(rst) begin
            ex_ma_inst <= 32'b0;
            ex_ma_op2 <= 32'b0;
            ex_ma_aluResult <= 32'b0;
            ex_ma_pc <= 32'b0;
            ex_ma_isImmediate <= 1'b0;
            ex_ma_ld <= 1'b0;
            ex_ma_st <= 1'b0;
            ex_ma_isWb <= 1'b0;
        end
        else if (waitrequest) begin
        
        end
        else if(stall) begin
            ex_ma_inst <= 32'b0;
            ex_ma_op2 <= 32'b0;
            ex_ma_aluResult <= 32'b0;
            ex_ma_pc <= 32'b0;
            ex_ma_isImmediate <= 1'b0;
            ex_ma_ld <= 1'b0;
            ex_ma_st <= 1'b0;
            ex_ma_isWb <= 1'b0;
        end
        else begin
            
            ex_ma_inst <= of_ex_inst;
            ex_ma_pc <= of_ex_pc;
            ex_ma_aluResult <= aluResult;
            if(of_ex_st)
                ex_ma_op2 <= store_data;
            else
                ex_ma_op2 <= of_ex_op2;
            ex_ma_isImmediate <= of_ex_isImmediate;
            ex_ma_ld <= of_ex_ld;
            ex_ma_st <= of_ex_st;
            ex_ma_isWb <= of_ex_isWb;
        end
    end
    
    //MEM Stage
    
    assign dmem_addr  = ex_ma_aluResult; 
    assign dmem_wdata = ex_ma_op2;       
    assign dmem_we    = ex_ma_st;
    
    // Read the result from the external memory
    always @ (*) begin
        
        if(ex_ma_ld)
            ldResult = dmem_rdata;
        else
            ldResult = 32'b0;
    end
    
    //MEM/WB Pipeline Register
    always @ (posedge clk1 or posedge rst)
    begin
        if(rst) begin
            ma_rw_ldResult <= 32'b0;
            ma_rw_pc <= 32'b0;
            ma_rw_aluResult <= 32'b0;
            ma_rw_inst <= 32'b0;
            ma_rw_isImmediate <= 1'b0;
            ma_rw_isLd <= 1'b0;
            ma_rw_isSt <= 1'b0;
            ma_rw_isWb <= 1'b0;
        end
        else if (waitrequest) begin
           
        end
        else begin
            ma_rw_pc <= ex_ma_pc;
            ma_rw_inst <= ex_ma_inst;
            ma_rw_aluResult <= ex_ma_aluResult;
            ma_rw_ldResult <= ldResult;
            ma_rw_isImmediate <= ex_ma_isImmediate;
            ma_rw_isSt <= ex_ma_st;
            ma_rw_isLd <= ex_ma_ld;
            ma_rw_isWb <= ex_ma_isWb;
        end
    end
    
    //WB Stage
    always @ (*)
    begin
        if(ma_rw_isLd)
            data = ma_rw_ldResult;
        else
            data = ma_rw_aluResult;
    end
    
    always @ (posedge clk1 or posedge rst)
    begin
        if(rst) begin
            for(k=0; k <= 31; k=k+1)
            begin
                Reg[k] <= 32'b0;
            end
        end
        else begin
            if(ma_rw_isWb && (ma_rw_inst[11:7] != 5'd0))
            begin
                Reg[ma_rw_inst[11:7]] <= data;
            end
        end
    end

    assign alu_res = aluResult;
    assign pc_out = pc;
    assign isStall = stall || waitrequest;
    assign mem_req = ex_ma_ld | ex_ma_st;
endmodule
