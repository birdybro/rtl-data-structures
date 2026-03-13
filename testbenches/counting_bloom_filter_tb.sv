`timescale 1ns/1ps

module counting_bloom_filter_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int KEY_WIDTH   = 8;
    parameter int FILTER_SIZE = 16;
    parameter int NUM_HASH    = 3;
    parameter int COUNT_BITS  = 4;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                  clk;
    logic                  rst_n;
    logic                  insert;
    logic                  remove;
    logic                  query;
    logic                  clear;
    logic [KEY_WIDTH-1:0]  key_in;
    logic                  present;
    logic                  not_present;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    counting_bloom_filter #(
        .KEY_WIDTH   (KEY_WIDTH),
        .FILTER_SIZE (FILTER_SIZE),
        .NUM_HASH    (NUM_HASH),
        .COUNT_BITS  (COUNT_BITS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .insert      (insert),
        .remove      (remove),
        .query       (query),
        .clear       (clear),
        .key_in      (key_in),
        .present     (present),
        .not_present (not_present)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_insert(input logic [KEY_WIDTH-1:0] k);
        @(negedge clk);
        insert = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        insert = 1'b0;
    endtask

    task do_remove(input logic [KEY_WIDTH-1:0] k);
        @(negedge clk);
        remove = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        remove = 1'b0;
    endtask

    // Query result is registered (1-cycle latency)
    task do_query(input  logic [KEY_WIDTH-1:0] k,
                  output logic                 pres,
                  output logic                 npres);
        @(negedge clk);
        query  = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        query = 1'b0;
        @(posedge clk); #1;
        pres  = present;
        npres = not_present;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic pres, npres;

        // Reset
        rst_n  = 1'b0;
        insert = 1'b0;
        remove = 1'b0;
        query  = 1'b0;
        clear  = 1'b0;
        key_in = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Query on empty filter — not_present
        // ------------------------------------------------------------------
        do_query(8'hAA, pres, npres);
        if (pres || !npres)
            $fatal(1, "TEST FAILED: empty filter should return not_present");
        $display("Test 1 PASSED: not_present on empty filter");

        // ------------------------------------------------------------------
        // Test 2: Insert key and query — must return present (no false negatives)
        // ------------------------------------------------------------------
        do_insert(8'hAA);
        wait_cycles(2);
        do_query(8'hAA, pres, npres);
        if (!pres)
            $fatal(1, "TEST FAILED: false negative after insert of 0xAA");
        $display("Test 2 PASSED: no false negative after insert");

        // ------------------------------------------------------------------
        // Test 3: Remove key and query — should return not_present
        //         (counting filter allows deletion)
        // ------------------------------------------------------------------
        do_remove(8'hAA);
        wait_cycles(2);
        do_query(8'hAA, pres, npres);
        if (!npres)
            $fatal(1, "TEST FAILED: should be not_present after removing 0xAA");
        $display("Test 3 PASSED: not_present after remove");

        // ------------------------------------------------------------------
        // Test 4: Multiple inserts of same key — then multiple removes
        //         Key should remain present until all copies removed
        // ------------------------------------------------------------------
        do_insert(8'hBB);
        do_insert(8'hBB);
        do_insert(8'hBB);
        wait_cycles(2);
        do_query(8'hBB, pres, npres);
        if (!pres)
            $fatal(1, "TEST FAILED: should be present after 3 inserts of 0xBB");

        do_remove(8'hBB); wait_cycles(2);
        do_query(8'hBB, pres, npres);
        if (!pres)
            $fatal(1, "TEST FAILED: should still be present after 1 of 3 removes");

        do_remove(8'hBB); wait_cycles(2);
        do_query(8'hBB, pres, npres);
        if (!pres)
            $fatal(1, "TEST FAILED: should still be present after 2 of 3 removes");

        do_remove(8'hBB); wait_cycles(2);
        do_query(8'hBB, pres, npres);
        if (!npres)
            $fatal(1, "TEST FAILED: should be not_present after all 3 removes of 0xBB");
        $display("Test 4 PASSED: multiple insert/remove counting correct");

        // ------------------------------------------------------------------
        // Test 5: Insert multiple keys, verify all present
        // ------------------------------------------------------------------
        do_insert(8'h01);
        do_insert(8'h02);
        do_insert(8'h03);
        do_insert(8'h04);
        wait_cycles(2);
        for (int i = 1; i <= 4; i++) begin
            do_query(8'(i), pres, npres);
            if (!pres)
                $fatal(1, "TEST FAILED: false negative for key 0x%02h", i);
        end
        $display("Test 5 PASSED: multiple keys inserted, all present");

        // ------------------------------------------------------------------
        // Test 6: Clear — all keys return not_present
        // ------------------------------------------------------------------
        @(negedge clk); clear = 1'b1; @(posedge clk); #1; clear = 1'b0;
        wait_cycles(2);
        for (int i = 1; i <= 4; i++) begin
            do_query(8'(i), pres, npres);
            if (!npres)
                $fatal(1, "TEST FAILED: should be not_present after clear for key 0x%02h", i);
        end
        $display("Test 6 PASSED: clear removes all entries");

        // ------------------------------------------------------------------
        // Test 7: present and not_present mutually exclusive
        // ------------------------------------------------------------------
        do_insert(8'hCC);
        wait_cycles(2);
        do_query(8'hCC, pres, npres);
        if (pres === npres)
            $fatal(1, "TEST FAILED: present and not_present must be mutually exclusive");
        $display("Test 7 PASSED: present/not_present mutually exclusive");

        $display("ALL TESTS PASSED: counting_bloom_filter_tb");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #100000;
        $fatal(1, "TIMEOUT: simulation exceeded limit");
    end

endmodule
