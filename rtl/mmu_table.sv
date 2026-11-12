//TRANSLATION BUFFER

module mmu_table (
    input cs, clk, rst_n,
    input [19:0] vpn,
    output reg [19:0] ppn,
    output reg hit,
    input update,
    input [19:0] updated_ppn,
    input update_valid
);

    reg [37:0] lut [4];
    reg [1:0] lut_rank [4];

    reg [3:0] valid_bits;


    always_comb begin : valid_update
        valid_bits = {lut[0][37], lut[1][37], lut[2][37], lut[3][37]};
    end

    always @(posedge clk) begin : lut_lookup
        if(!rst_n) begin
            lut_rank[0] <= 2'd0;
            lut_rank[1] <= 2'd1;
            lut_rank[2] <= 2'd2;
            lut_rank[3] <= 2'd3;

            lut[0] <= 0;
            lut[1] <= 0;
            lut[2] <= 0;
            lut[3] <= 0;
            hit <= 0;
        end
        else if(cs) begin
            hit <= 0;
            if(update) begin
                casez (valid_bits)
                    4'b1111: begin
                        //replacement logic
                        if(update_valid) begin
                            if(lut_rank[0] == 2'b00) begin
                                lut[0][37] <= 1;
                                lut[0][36:20] <= vpn;
                                lut[0][19:0] <= updated_ppn;
                                lut_rank[0] <= 2'd3;
                                lut_rank[1] <= lut_rank[1] - 1;
                                lut_rank[2] <= lut_rank[2] - 1;
                                lut_rank[3] <= lut_rank[3] - 1;
                            end

                            else if (lut_rank[1] == 2'b00) begin
                                lut[1][37] <= 1;
                                lut[1][36:20] <= vpn;
                                lut[1][19:0] <= updated_ppn;
                                lut_rank[1] <= 2'd3;
                                lut_rank[0] <= lut_rank[0] - 1;
                                lut_rank[2] <= lut_rank[2] - 1;
                                lut_rank[3] <= lut_rank[3] - 1;
                            end

                            else if (lut_rank[2] == 2'b00) begin
                                lut[2][37] <= 1;
                                lut[2][36:20] <= vpn;
                                lut[2][19:0] <= updated_ppn;
                                lut_rank[2] <= 2'd3;
                                lut_rank[0] <= lut_rank[0] - 1;
                                lut_rank[1] <= lut_rank[1] - 1;
                                lut_rank[3] <= lut_rank[3] - 1;
                            end

                            else begin
                                lut[3][37] <= 1;
                                lut[3][36:20] <= vpn;
                                lut[3][19:0] <= updated_ppn;
                                lut_rank[3] <= 2'd3;
                                lut_rank[0] <= lut_rank[0] - 1;
                                lut_rank[1] <= lut_rank[1] - 1;
                                lut_rank[2] <= lut_rank[2] - 1;
                            end

                        end
                     end
                    4'b0???: begin
                        if(update_valid) begin
                            lut_rank[0] <= 2'b11;
                            // if(lut_rank[1] > lut_rank[0]) begin
                            //     lut_rank[1] <= lut_rank[1] - 1;
                            // end

                            // if(lut_rank[2] > lut_rank[0]) begin
                            //     lut_rank[2] <= lut_rank[2] - 1;
                            // end

                            // if(lut_rank[3] > lut_rank[0]) begin
                            //     lut_rank[3] <= lut_rank[3] - 1;
                            // end
                            lut[0][37] <= 1;
                            lut[0][36:20] <= vpn;
                            lut[0][19:0] <= updated_ppn;
                        end
                    end
                    4'b10??: begin
                        if(update_valid) begin
                            lut_rank[1] <= 2'b11;
                            lut_rank[0] <= 2'b10;
                            // if(lut_rank[0] > lut_rank[1]) begin
                            //     lut_rank[0] <= lut_rank[0] - 1;
                            // end

                            // if(lut_rank[2] > lut_rank[1]) begin
                            //     lut_rank[2] <= lut_rank[2] - 1;
                            // end

                            // if(lut_rank[3] > lut_rank[1]) begin
                            //     lut_rank[3] <= lut_rank[3] - 1;
                            // end
                            lut[1][37] <= 1;
                            lut[1][36:20] <= vpn;
                            lut[1][19:0] <= updated_ppn;
                        end
                    end
                    4'b110?: begin
                        if(update_valid) begin
                            lut_rank[2] <= 2'b11;
                            lut_rank[1] <= 2'b10;
                            lut_rank[0] <= 2'b01;
                            // lut_rank[2] <= 2'b11;
                            // if(lut_rank[0] > lut_rank[2]) begin
                            //     lut_rank[0] <= lut_rank[0] - 1;
                            // end

                            // if(lut_rank[1] > lut_rank[2]) begin
                            //     lut_rank[1] <= lut_rank[1] - 1;
                            // end

                            // if(lut_rank[3] > lut_rank[2]) begin
                            //     lut_rank[3] <= lut_rank[3] - 1;
                            // end
                            lut[2][37] <= 1;
                            lut[2][36:20] <= vpn;
                            lut[2][19:0] <= updated_ppn;
                        end
                    end
                    4'b1110: begin
                        if(update_valid) begin
                            lut_rank[3] <= 2'b11;
                            lut_rank[2] <= 2'b10;
                            lut_rank[1] <= 2'b01;
                            lut_rank[0] <= 2'b00;
                            // if(lut_rank[0] > lut_rank[3]) begin
                            //     lut_rank[0] <= lut_rank[0] - 1;
                            // end

                            // if(lut_rank[1] > lut_rank[3]) begin
                            //     lut_rank[1] <= lut_rank[1] - 1;
                            // end

                            // if(lut_rank[2] > lut_rank[3]) begin
                            //     lut_rank[2] <= lut_rank[2] - 1;
                            // end
                            lut[3][37] <= 1;
                            lut[3][36:20] <= vpn;
                            lut[3][19:0] <= updated_ppn;
                        end
                    end
                endcase

            end

            else begin
                if(lut[0][37] && lut[0][36:20] == vpn) begin
                    ppn <= lut[0][19:0];
                    hit <= 1;
                    lut_rank[0] <= 2'b11;
                    for(int i = 0; i <= 3; i++) begin
                        if (lut_rank[i] > lut_rank[0]) begin
                            lut_rank[i] <= lut_rank[i] - 1;
                        end
                    end
                end

                else if(lut[1][37] && lut[1][36:20] == vpn) begin
                    ppn <= lut[1][19:0];
                    hit <= 1;
                    lut_rank[1] <= 2'b11;
                    for(int i = 0; i <= 3; i++) begin
                        if (lut_rank[i] > lut_rank[1]) begin
                            lut_rank[i] <= lut_rank[i] - 1;
                        end
                    end
                end

                else if(lut[2][37] && lut[2][36:20] == vpn) begin
                    ppn <= lut[2][19:0];
                    hit <= 1;
                    lut_rank[2] <= 2'b11;
                    for(int i = 0; i <= 3; i++) begin
                        if (lut_rank[i] > lut_rank[2]) begin
                            lut_rank[i] <= lut_rank[i] - 1;
                        end
                    end
                end

                else if(lut[3][37] && lut[3][36:20] == vpn) begin
                    ppn <= lut[3][19:0];
                    hit <= 1;
                    lut_rank[3] <= 2'b11;
                    for(int i = 0; i <= 3; i++) begin
                        if (lut_rank[i] > lut_rank[3]) begin
                            lut_rank[i] <= lut_rank[i] - 1;
                        end
                    end
                end

                else begin
                    ppn <= 0;
                    hit <= 0;
                end
            end

        end

        else begin
            hit <= 0;
            ppn <= 0;
        end
    end
endmodule

//38 -> 1 + 17 + 20
//37:0 -> 37, 36:20, 19:0
