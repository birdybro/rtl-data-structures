`timescale 1ns/1ps

module membership_filter_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int KEY_WIDTH  = 8;
    parameter int TABLE_SIZE = 64;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                           clk;
    logic                           rst_n;
    logic                           insert;
    logic                           remove;
    logic                           query;
    logic                           clear;
    logic [KEY_WIDTH-1:0]           key_in;
    logic                           member;
    logic                           not_member;
    logic                           full;
    logic [$clog2(TABLE_SIZE):0]    count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    membership_filter #(
        .KEY_WIDTH  (KEY_WIDTH),
        .TABLE_SIZE (TABLE_SIZE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .insert     (insert),
        .remove     (remove),
        .query      (query),
        .clear      (clear),
        .key_in     (key_in),
        .member     (member),
        .not_member (not_member),
        .full       (full),
        .count      (count)
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

    // Results are registered (1-cycle latency)
    task do_query(input  logic [KEY_WIDTH-1:0] k,
                  output logic                 mem,
                  output logic                 nmem);
        @(negedge clk);
        query  = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        query = 1'b0;
        @(posedge clk); #1;
        mem  = member;
        nmem = not_member;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic mem, nmem;

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
        // Test 1: Query on empty filter — all not_member (exact filter, no false positives)
        // ------------------------------------------------------------------
        do_query(8'hAA, mem, nmem);
        if (mem || !nmem)
            $fatal(1, "TEST FAILED: empty filter should return not_member");
        if (count !== 0)
            $fatal(1, "TEST FAILED: count should be 0 after reset");
        $display("Test 1 PASSED: not_member on empty filter");

        // ------------------------------------------------------------------
        // Test 2: Insert keys and verify membership
        // ------------------------------------------------------------------
        do_insert(8'hAA);
        do_insert(8'hBB);
        do_insert(8'hCC);
        wait_cycles(2);
        if (count !== 3)
            $fatal(1, "TEST FAILED: count should be 3 after 3 inserts, got %0d", count);

        do_query(8'hAA, mem, nmem);
        if (!mem || nmem)
            $fatal(1, "TEST FAILED: 0xAA should be member");

        do_query(8'hBB, mem, nmem);
        if (!mem || nmem)
            $fatal(1, "TEST FAILED: 0xBB should be member");

        do_query(8'hCC, mem, nmem);
        if (!mem || nmem)
            $fatal(1, "TEST FAILED: 0xCC should be member");
        $display("Test 2 PASSED: inserted keys are members");

        // ------------------------------------------------------------------
        // Test 3: Non-inserted key must return not_member (exact filter)
        // ------------------------------------------------------------------
        do_query(8'hDD, mem, nmem);
        if (mem || !nmem)
            $fatal(1, "TEST FAILED: 0xDD should not be member (exact filter)");
        $display("Test 3 PASSED: non-inserted key is not_member");

        // ------------------------------------------------------------------
        // Test 4: Remove a key — subsequent query returns not_member
        // ------------------------------------------------------------------
        do_remove(8'hBB);
        wait_cycles(2);
        if (count !== 2)
            $fatal(1, "TEST FAILED: count should be 2 after remove, got %0d", count);
        do_query(8'hBB, mem, nmem);
        if (mem || !nmem)
            $fatal(1, "TEST FAILED: 0xBB should not be member after remove");
        // 0xAA and 0xCC should still be members
        do_query(8'hAA, mem, nmem);
        if (!mem)
            $fatal(1, "TEST FAILED: 0xAA should still be member after removing 0xBB");
        $display("Test 4 PASSED: remove and re-query");

        // ------------------------------------------------------------------
        // Test 5: member and not_member are mutually exclusive
        // ------------------------------------------------------------------
        do_query(8'hAA, mem, nmem);
        if (mem === nmem)
            $fatal(1, "TEST FAILED: member and not_member must be mutually exclusive");
        do_query(8'hBB, mem, nmem);
        if (mem === nmem)
            $fatal(1, "TEST FAILED: member and not_member must be mutually exclusive");
        $display("Test 5 PASSED: member/not_member mutually exclusive");

        // ------------------------------------------------------------------
        // Test 6: Clear — all keys return not_member
        // ------------------------------------------------------------------
        @(negedge clk); clear = 1'b1; @(posedge clk); #1; clear = 1'b0;
        wait_cycles(2);
        if (count !== 0)
            $fatal(1, "TEST FAILED: count should be 0 after clear, got %0d", count);
        do_query(8'hAA, mem, nmem);
        if (mem || !nmem)
            $fatal(1, "TEST FAILED: 0xAA should not be member after clear");
        do_query(8'hCC, mem, nmem);
        if (mem || !nmem)
            $fatal(1, "TEST FAILED: 0xCC should not be member after clear");
        $display("Test 6 PASSED: clear empties the filter");

        // ------------------------------------------------------------------
        // Test 7: Insert enough keys to check full flag
        // ------------------------------------------------------------------
        for (int i = 0; i < TABLE_SIZE; i++)
            do_insert(8'(i & 8'hFF));
        wait_cycles(2);
        if (!full)
            $fatal(1, "TEST FAILED: filter should be full after inserting TABLE_SIZE keys");
        $display("Test 7 PASSED: full flag asserted at capacity");

        $display("ALL TESTS PASSED: membership_filter_tb");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #200000;
        $fatal(1, "TIMEOUT: simulation exceeded limit");
    end

endmodule
