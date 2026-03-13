`timescale 1ns/1ps

module min_heap_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int KEY_WIDTH  = 8;
    parameter int DEPTH      = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   insert;
    logic                   remove_min;
    logic [KEY_WIDTH-1:0]   key_in;
    logic [DATA_WIDTH-1:0]  data_in;
    logic [KEY_WIDTH-1:0]   min_key;
    logic [DATA_WIDTH-1:0]  min_data;
    logic                   full;
    logic                   empty;
    logic [$clog2(DEPTH):0] count;
    logic                   busy;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    min_heap #(
        .DATA_WIDTH (DATA_WIDTH),
        .KEY_WIDTH  (KEY_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .insert     (insert),
        .remove_min (remove_min),
        .key_in     (key_in),
        .data_in    (data_in),
        .min_key    (min_key),
        .min_data   (min_data),
        .full       (full),
        .empty      (empty),
        .count      (count),
        .busy       (busy)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task wait_not_busy;
        @(posedge clk); #1;
        while (busy) begin @(posedge clk); #1; end
    endtask

    task do_insert(input logic [KEY_WIDTH-1:0]  k,
                   input logic [DATA_WIDTH-1:0] d);
        wait_not_busy;
        @(negedge clk);
        insert  = 1'b1;
        key_in  = k;
        data_in = d;
        @(posedge clk); #1;
        insert = 1'b0;
        wait_not_busy;
    endtask

    task do_remove_min(output logic [KEY_WIDTH-1:0]  k,
                       output logic [DATA_WIDTH-1:0] d);
        wait_not_busy;
        @(negedge clk);
        remove_min = 1'b1;
        @(posedge clk); #1;
        remove_min = 1'b0;
        k          = min_key;
        d          = min_data;
        wait_not_busy;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [KEY_WIDTH-1:0]  rkey;
        logic [DATA_WIDTH-1:0] rdata;
        logic [KEY_WIDTH-1:0]  last_key;

        // Reset
        rst_n      = 1'b0;
        insert     = 1'b0;
        remove_min = 1'b0;
        key_in     = '0;
        data_in    = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Empty after reset
        // ------------------------------------------------------------------
        if (!empty || count !== 0)
            $fatal(1, "TEST FAILED: should be empty after reset");
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Insert in reverse order, verify minimum extracted first
        // ------------------------------------------------------------------
        // Keys: 9, 6, 3, 1, 4, 7, 2, 8 — minimum should be 1
        do_insert(8'd9, 8'h90);
        do_insert(8'd6, 8'h60);
        do_insert(8'd3, 8'h30);
        do_insert(8'd1, 8'h10);   // minimum
        do_insert(8'd4, 8'h40);
        wait_cycles(1);
        if (count !== 5)
            $fatal(1, "TEST FAILED: count should be 5, got %0d", count);
        $display("Test 2 PASSED: 5 elements inserted");

        // ------------------------------------------------------------------
        // Test 3: Remove all — keys must come out in ascending order
        // ------------------------------------------------------------------
        last_key = 8'd0;
        for (int i = 0; i < 5; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at remove %0d", i);
            do_remove_min(rkey, rdata);
            if (rkey < last_key)
                $fatal(1, "TEST FAILED: min-heap violated at pop %0d: key=%0d after key=%0d",
                       i, rkey, last_key);
            last_key = rkey;
        end
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after removing all");
        $display("Test 3 PASSED: minimum always extracted first");

        // ------------------------------------------------------------------
        // Test 4: Verify exact minimum on a known sequence
        // ------------------------------------------------------------------
        do_insert(8'd50, 8'hA0);
        do_insert(8'd10, 8'hB0);  // min
        do_insert(8'd30, 8'hC0);
        do_remove_min(rkey, rdata);
        if (rkey !== 8'd10)
            $fatal(1, "TEST FAILED: minimum should be 10, got %0d", rkey);
        if (rdata !== 8'hB0)
            $fatal(1, "TEST FAILED: min data should be 0xB0, got 0x%02h", rdata);
        $display("Test 4 PASSED: exact minimum value verified");

        // ------------------------------------------------------------------
        // Test 5: Fill to full, drain in order
        // ------------------------------------------------------------------
        while (!empty) do_remove_min(rkey, rdata);
        for (int i = DEPTH; i >= 1; i--)
            do_insert(8'(i), 8'(i));
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d inserts", DEPTH);

        last_key = 8'd0;
        for (int i = 0; i < DEPTH; i++) begin
            do_remove_min(rkey, rdata);
            if (rkey < last_key)
                $fatal(1, "TEST FAILED: ordering violated at drain %0d", i);
            last_key = rkey;
        end
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after full drain");
        $display("Test 5 PASSED: fill then drain in ascending order");

        // ------------------------------------------------------------------
        // Test 6: Overflow prevention
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) do_insert(8'(i+1), 8'(i));
        wait_not_busy;
        @(negedge clk); insert = 1; key_in = 8'd0; data_in = 8'hFF;
        @(posedge clk); #1; insert = 0;
        wait_not_busy;
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        $display("Test 6 PASSED: overflow prevention");

        $display("ALL TESTS PASSED: min_heap_tb");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #500000;
        $fatal(1, "TIMEOUT: simulation exceeded limit");
    end

endmodule
