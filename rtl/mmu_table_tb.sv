`timescale 1ns/1ps

module mmu_table_tb;

    reg         cs;
    reg         clk;
    reg         rst_n;
    reg [16:0]  vpn;

    wire [19:0] ppn;
    wire        hit;

    reg         update;
    reg [19:0]  updated_ppn;
    reg         update_valid;

    mmu_table dut (
        .cs(cs),
        .clk(clk),
        .rst_n(rst_n),
        .vpn(vpn),
        .ppn(ppn),
        .hit(hit),
        .update(update),
        .updated_ppn(updated_ppn),
        .update_valid(update_valid)
    );

    // Clock: 10 ns period
    always #5 clk = ~clk;

    task lookup(input [16:0] test_vpn);
        begin
            @(negedge clk);
            cs = 1;
            update = 0;
            update_valid = 0;
            vpn = test_vpn;

            @(posedge clk);
            #1;

            if (hit)
                $display("[%0t] LOOKUP VPN=%h : HIT, PPN=%h",
                         $time, test_vpn, ppn);
            else
                $display("[%0t] LOOKUP VPN=%h : MISS",
                         $time, test_vpn);

            cs = 0;
        end
    endtask

    task lookup_expect_hit(
        input [16:0] test_vpn,
        input [19:0] expected_ppn
    );
        begin
            @(negedge clk);
            cs = 1;
            update = 0;
            update_valid = 0;
            vpn = test_vpn;

            @(posedge clk);
            #1;

            if (hit && ppn == expected_ppn)
                $display("[%0t] PASS: VPN=%h -> PPN=%h",
                         $time, test_vpn, ppn);
            else
                $display("[%0t] FAIL: VPN=%h expected PPN=%h, got PPN=%h hit=%b",
                         $time, test_vpn, expected_ppn, ppn, hit);

            cs = 0;
        end
    endtask

    task lookup_expect_miss(input [16:0] test_vpn);
        begin
            @(negedge clk);
            cs = 1;
            update = 0;
            update_valid = 0;
            vpn = test_vpn;

            @(posedge clk);
            #1;

            if (!hit)
                $display("[%0t] PASS: VPN=%h correctly MISSed",
                         $time, test_vpn);
            else
                $display("[%0t] FAIL: VPN=%h unexpectedly HIT, PPN=%h",
                         $time, test_vpn, ppn);

            cs = 0;
        end
    endtask

    task insert(
        input [16:0] new_vpn,
        input [19:0] new_ppn
    );
        begin
            @(negedge clk);
            cs = 1;
            update = 1;
            update_valid = 1;
            vpn = new_vpn;
            updated_ppn = new_ppn;

            @(posedge clk);
            #1;

            $display("[%0t] INSERT: VPN=%h -> PPN=%h",
                     $time, new_vpn, new_ppn);

            cs = 0;
            update = 0;
            update_valid = 0;
        end
    endtask
    
    task check_ranks;
        integer i, j;
        reg duplicate;
    
        begin
            duplicate = 0;
    
            for (i = 0; i < 4; i = i + 1) begin
                if (dut.lut_rank[i] > 3)
                    duplicate = 1;
    
                for (j = i + 1; j < 4; j = j + 1) begin
                    if (dut.lut_rank[i] == dut.lut_rank[j])
                        duplicate = 1;
                end
            end
    
            if (duplicate) begin
                $display("[%0t] FAIL: INVALID LRU STATE!", $time);
                $display("       Ranks = %d %d %d %d",
                    dut.lut_rank[0],
                    dut.lut_rank[1],
                    dut.lut_rank[2],
                    dut.lut_rank[3]);
            end
            else begin
                $display("[%0t] PASS: LRU state = %d %d %d %d",
                    $time,
                    dut.lut_rank[0],
                    dut.lut_rank[1],
                    dut.lut_rank[2],
                    dut.lut_rank[3]);
            end
        end
    endtask
    
    task access_and_check(input [16:0] test_vpn);
        begin
            @(negedge clk);
    
            cs = 1;
            update = 0;
            update_valid = 0;
            vpn = test_vpn;
    
            @(posedge clk);
            #1;
    
            if (!hit)
                $display("[%0t] FAIL: VPN=%h unexpectedly MISSed",
                         $time, test_vpn);
            else
                $display("[%0t] HIT: VPN=%h", $time, test_vpn);
    
            check_ranks();
    
            cs = 0;
        end
    endtask
    
    


    initial begin

        clk = 0;
        cs = 0;
        rst_n = 0;
        vpn = 0;
        update = 0;
        updated_ppn = 0;
        update_valid = 0;

        $display("\n========================================");
        $display("        MMU TABLE TESTBENCH");
        $display("========================================\n");


        // ------------------------------------------------------------
        // RESET
        // ------------------------------------------------------------

        $display("---- RESET ----");

        #12;
        rst_n = 1;

        #2;

        // ------------------------------------------------------------
        // TEST 1: Empty table should MISS
        // ------------------------------------------------------------

        $display("\n---- TEST 1: EMPTY TABLE ----");

        lookup_expect_miss(17'h00100);


        // ------------------------------------------------------------
        // TEST 2: Insert first translation
        // ------------------------------------------------------------

        $display("\n---- TEST 2: INSERT ENTRY A ----");

        insert(17'h00100, 20'hABCDE);

        lookup_expect_hit(
            17'h00100,
            20'hABCDE
        );


        // ------------------------------------------------------------
        // TEST 3: Insert remaining three entries
        // ------------------------------------------------------------

        $display("\n---- TEST 3: FILL TABLE ----");

        insert(17'h00200, 20'h11111);
        insert(17'h00300, 20'h22222);
        insert(17'h00400, 20'h33333);


        // ------------------------------------------------------------
        // TEST 4: Verify all four entries
        // ------------------------------------------------------------

        $display("\n---- TEST 4: VERIFY ALL ENTRIES ----");

        lookup_expect_hit(17'h00100, 20'hABCDE);
        lookup_expect_hit(17'h00200, 20'h11111);
        lookup_expect_hit(17'h00300, 20'h22222);
        lookup_expect_hit(17'h00400, 20'h33333);


        // ------------------------------------------------------------
        // TEST 5: Access pattern for LRU
        //
        // This should make VPN 00200 the LRU depending on
        // the current filling/access behavior.
        // ------------------------------------------------------------

        $display("\n---- TEST 5: LRU ACCESS PATTERN ----");

        lookup_expect_hit(17'h00100, 20'hABCDE);
        lookup_expect_hit(17'h00300, 20'h22222);
        lookup_expect_hit(17'h00400, 20'h33333);


        // ------------------------------------------------------------
        // TEST 6: Insert fifth entry
        //
        // After the accesses above, VPN 00200 should be the
        // least recently used entry.
        // ------------------------------------------------------------

        $display("\n---- TEST 6: FORCE REPLACEMENT ----");

        insert(17'h00500, 20'h44444);


        // ------------------------------------------------------------
        // TEST 7: Verify new entry
        // ------------------------------------------------------------

        $display("\n---- TEST 7: VERIFY NEW ENTRY ----");

        lookup_expect_hit(
            17'h00500,
            20'h44444
        );


        // ------------------------------------------------------------
        // TEST 8: Verify old LRU entry was evicted
        // ------------------------------------------------------------

        $display("\n---- TEST 8: VERIFY EVICTION ----");

        lookup_expect_miss(17'h00200);


        // ------------------------------------------------------------
        // TEST 9: Verify other entries survived
        // ------------------------------------------------------------

        $display("\n---- TEST 9: VERIFY SURVIVORS ----");

        lookup_expect_hit(17'h00100, 20'hABCDE);
        lookup_expect_hit(17'h00300, 20'h22222);
        lookup_expect_hit(17'h00400, 20'h33333);


        $display("\n========================================");
        $display("             TEST COMPLETE");
        $display("========================================\n");
        
        $display("\n---- RESET BEFORE LRU STRESS TEST ----");

        @(negedge clk);
        rst_n = 0;
        
        @(posedge clk);
        #1;
        
        rst_n = 1;
        
        insert(17'h00100, 20'hABCDE);
        insert(17'h00200, 20'h11111);
        insert(17'h00300, 20'h22222);
        insert(17'h00400, 20'h33333);
        
        $display("\n========================================");
        $display("       LRU RANK STRESS TEST");
        $display("========================================");
        
        // Initial state
        check_ranks();
        
        // Access A
        access_and_check(17'h00100);
        
        // Access B
        access_and_check(17'h00200);
        
        // Access C
        access_and_check(17'h00300);
        
        // Access D
        access_and_check(17'h00400);
        
        // Access A again
        access_and_check(17'h00100);
        
        // Access D again
        access_and_check(17'h00400);
        
        // Access B again
        access_and_check(17'h00200);
        
        // Access C again
        access_and_check(17'h00300);
        
        // Access B again
        access_and_check(17'h00200);
        
        // Access A again
        access_and_check(17'h00100);
        
        // Access C again
        access_and_check(17'h00300);
        
        // Access D again
        access_and_check(17'h00400);

        #30;
        $finish;
    end

endmodule