`timescale 1ns/1ps

module bitset_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int SIZE       = 16;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                        clk;
    logic                        rst_n;
    logic                        set_bit;
    logic                        clear_bit;
    logic                        toggle_bit;
    logic                        test_bit;
    logic                        clear_all;
    logic [$clog2(SIZE)-1:0]     bit_index;
    logic                        bit_out;
    logic [SIZE-1:0]             bit_vector;
    logic                        any_set;
    logic                        all_set;
    logic [$clog2(SIZE):0]       count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    bitset #(
        .SIZE (SIZE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .set_bit    (set_bit),
        .clear_bit  (clear_bit),
        .toggle_bit (toggle_bit),
        .test_bit   (test_bit),
        .clear_all  (clear_all),
        .bit_index  (bit_index),
        .bit_out    (bit_out),
        .bit_vector (bit_vector),
        .any_set    (any_set),
        .all_set    (all_set),
        .count      (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_set(input logic [$clog2(SIZE)-1:0] idx);
        @(negedge clk);
        set_bit   = 1'b1;
        bit_index = idx;
        @(posedge clk); #1;
        set_bit = 1'b0;
    endtask

    task do_clear(input logic [$clog2(SIZE)-1:0] idx);
        @(negedge clk);
        clear_bit = 1'b1;
        bit_index = idx;
        @(posedge clk); #1;
        clear_bit = 1'b0;
    endtask

    task do_toggle(input logic [$clog2(SIZE)-1:0] idx);
        @(negedge clk);
        toggle_bit = 1'b1;
        bit_index  = idx;
        @(posedge clk); #1;
        toggle_bit = 1'b0;
    endtask

    task do_clear_all;
        @(negedge clk);
        clear_all = 1'b1;
        @(posedge clk); #1;
        clear_all = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Reset
        rst_n      = 1'b0;
        set_bit    = 1'b0;
        clear_bit  = 1'b0;
        toggle_bit = 1'b0;
        test_bit   = 1'b0;
        clear_all  = 1'b0;
        bit_index  = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — all bits clear
        // ------------------------------------------------------------------
        if (any_set || count !== 0 || bit_vector !== '0)
            $fatal(1, "TEST FAILED: all bits should be 0 after reset");
        $display("Test 1 PASSED: all bits clear after reset");

        // ------------------------------------------------------------------
        // Test 2: Set individual bits, verify bit_vector and count
        // ------------------------------------------------------------------
        do_set(4'd0);
        wait_cycles(1);
        if (!bit_vector[0])
            $fatal(1, "TEST FAILED: bit 0 should be set");
        if (count !== 1)
            $fatal(1, "TEST FAILED: count should be 1, got %0d", count);
        if (!any_set)
            $fatal(1, "TEST FAILED: any_set should be 1");

        do_set(4'd5);
        wait_cycles(1);
        if (!bit_vector[5])
            $fatal(1, "TEST FAILED: bit 5 should be set");
        if (count !== 2)
            $fatal(1, "TEST FAILED: count should be 2, got %0d", count);

        do_set(4'd15);
        wait_cycles(1);
        if (!bit_vector[15])
            $fatal(1, "TEST FAILED: bit 15 should be set");
        if (count !== 3)
            $fatal(1, "TEST FAILED: count should be 3, got %0d", count);
        $display("Test 2 PASSED: set bits and count correct");

        // ------------------------------------------------------------------
        // Test 3: test_bit (combinational) — verify bit_out reflects current bit
        // ------------------------------------------------------------------
        @(negedge clk);
        test_bit  = 1'b1;
        bit_index = 4'd5;
        #1;
        if (!bit_out)
            $fatal(1, "TEST FAILED: test_bit for set bit 5 should return 1");
        bit_index = 4'd3; #1;
        if (bit_out)
            $fatal(1, "TEST FAILED: test_bit for unset bit 3 should return 0");
        @(posedge clk); #1;
        test_bit = 1'b0;
        $display("Test 3 PASSED: test_bit combinational query");

        // ------------------------------------------------------------------
        // Test 4: Clear a bit
        // ------------------------------------------------------------------
        do_clear(4'd5);
        wait_cycles(1);
        if (bit_vector[5])
            $fatal(1, "TEST FAILED: bit 5 should be 0 after clear");
        if (count !== 2)
            $fatal(1, "TEST FAILED: count should be 2 after clearing bit 5, got %0d", count);
        $display("Test 4 PASSED: clear_bit works");

        // ------------------------------------------------------------------
        // Test 5: Toggle bit
        // ------------------------------------------------------------------
        // bit 0 is set — toggle should clear it
        do_toggle(4'd0);
        wait_cycles(1);
        if (bit_vector[0])
            $fatal(1, "TEST FAILED: bit 0 should be 0 after toggle");
        if (count !== 1)
            $fatal(1, "TEST FAILED: count should be 1, got %0d", count);

        // bit 0 is now clear — toggle should set it
        do_toggle(4'd0);
        wait_cycles(1);
        if (!bit_vector[0])
            $fatal(1, "TEST FAILED: bit 0 should be 1 after second toggle");
        if (count !== 2)
            $fatal(1, "TEST FAILED: count should be 2, got %0d", count);
        $display("Test 5 PASSED: toggle_bit works");

        // ------------------------------------------------------------------
        // Test 6: Set all bits — all_set asserted
        // ------------------------------------------------------------------
        for (int i = 0; i < SIZE; i++)
            do_set($clog2(SIZE)'(i));
        wait_cycles(1);
        if (!all_set)
            $fatal(1, "TEST FAILED: all_set should be 1 when all bits set");
        if (count !== SIZE)
            $fatal(1, "TEST FAILED: count should be %0d when all set, got %0d", SIZE, count);
        $display("Test 6 PASSED: all_set asserted when all bits set");

        // ------------------------------------------------------------------
        // Test 7: clear_all — all bits cleared in one operation
        // ------------------------------------------------------------------
        do_clear_all;
        wait_cycles(1);
        if (any_set || count !== 0 || bit_vector !== '0 || all_set)
            $fatal(1, "TEST FAILED: clear_all should reset all bits");
        $display("Test 7 PASSED: clear_all clears all bits");

        $display("ALL TESTS PASSED: bitset_tb");
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
