`timescale 1ns/1ps

module binary_heap_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int KEY_WIDTH  = 8;
    parameter int DEPTH      = 8;
    parameter int MIN_HEAP   = 1;   // 1 = min-heap, 0 = max-heap

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   insert;
    logic                   remove_top;
    logic [KEY_WIDTH-1:0]   key_in;
    logic [DATA_WIDTH-1:0]  data_in;
    logic [KEY_WIDTH-1:0]   key_out;
    logic [DATA_WIDTH-1:0]  data_out;
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
    binary_heap #(
        .DATA_WIDTH (DATA_WIDTH),
        .KEY_WIDTH  (KEY_WIDTH),
        .DEPTH      (DEPTH),
        .MIN_HEAP   (MIN_HEAP)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .insert     (insert),
        .remove_top (remove_top),
        .key_in     (key_in),
        .data_in    (data_in),
        .key_out    (key_out),
        .data_out   (data_out),
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

    task do_remove(output logic [KEY_WIDTH-1:0]  k,
                   output logic [DATA_WIDTH-1:0] d);
        wait_not_busy;
        @(negedge clk);
        remove_top = 1'b1;
        @(posedge clk); #1;
        remove_top = 1'b0;
        k          = key_out;
        d          = data_out;
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
        remove_top = 1'b0;
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
        // Test 2: Insert elements in non-sorted order
        // ------------------------------------------------------------------
        do_insert(8'd10, 8'hAA);
        do_insert(8'd3,  8'hBB);   // should become min
        do_insert(8'd7,  8'hCC);
        do_insert(8'd1,  8'hDD);   // should become new min
        do_insert(8'd5,  8'hEE);
        wait_cycles(1);
        if (count !== 5)
            $fatal(1, "TEST FAILED: count should be 5, got %0d", count);
        $display("Test 2 PASSED: 5 elements inserted");

        // ------------------------------------------------------------------
        // Test 3: Remove all and verify min-heap ordering (keys ascending)
        // ------------------------------------------------------------------
        last_key = 8'd0;
        for (int i = 0; i < 5; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at remove %0d", i);
            do_remove(rkey, rdata);
            if (rkey < last_key)
                $fatal(1, "TEST FAILED: min-heap order violated at pop %0d: key=%0d after %0d",
                       i, rkey, last_key);
            last_key = rkey;
        end
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after 5 removes");
        $display("Test 3 PASSED: min-heap ordering verified");

        // ------------------------------------------------------------------
        // Test 4: Verify key_out / data_out pairing is correct for known sequence
        // ------------------------------------------------------------------
        do_insert(8'd20, 8'hF1);
        do_insert(8'd5,  8'hF2);
        do_insert(8'd15, 8'hF3);
        // Min should be key=5, data=0xF2
        do_remove(rkey, rdata);
        if (rkey !== 8'd5)
            $fatal(1, "TEST FAILED: min key should be 5, got %0d", rkey);
        if (rdata !== 8'hF2)
            $fatal(1, "TEST FAILED: min data should be 0xF2, got 0x%02h", rdata);
        $display("Test 4 PASSED: key/data pairing correct");

        // ------------------------------------------------------------------
        // Test 5: Fill to full
        // ------------------------------------------------------------------
        // Drain remaining entries first
        while (!empty) do_remove(rkey, rdata);
        for (int i = 0; i < DEPTH; i++)
            do_insert(8'(i + 1), 8'(i));
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d inserts", DEPTH);
        $display("Test 5 PASSED: fill to full");

        // ------------------------------------------------------------------
        // Test 6: Overflow prevention
        // ------------------------------------------------------------------
        wait_not_busy;
        @(negedge clk); insert = 1; key_in = 8'hFF; data_in = 8'hFF;
        @(posedge clk); #1; insert = 0;
        wait_not_busy;
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        $display("Test 6 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 7: Full drain in order
        // ------------------------------------------------------------------
        last_key = 8'd0;
        for (int i = 0; i < DEPTH; i++) begin
            do_remove(rkey, rdata);
            if (rkey < last_key)
                $fatal(1, "TEST FAILED: heap order violated at drain %0d", i);
            last_key = rkey;
        end
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after full drain");
        $display("Test 7 PASSED: full heap drain in correct order");

        $display("ALL TESTS PASSED: binary_heap_tb");
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
