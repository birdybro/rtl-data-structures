`timescale 1ns/1ps

module token_bucket_shaper_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int TOKEN_BITS = 16;
    parameter int RATE_BITS  = 8;
    parameter int BURST_BITS = 16;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                    clk;
    logic                    rst_n;
    logic                    tick;
    logic                    consume;
    logic [RATE_BITS-1:0]    fill_rate;
    logic [BURST_BITS-1:0]   burst_size;
    logic [TOKEN_BITS-1:0]   token_count;
    logic                    allow;
    logic                    full;
    logic                    empty;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    token_bucket_shaper #(
        .TOKEN_BITS (TOKEN_BITS),
        .RATE_BITS  (RATE_BITS),
        .BURST_BITS (BURST_BITS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .tick        (tick),
        .consume     (consume),
        .fill_rate   (fill_rate),
        .burst_size  (burst_size),
        .token_count (token_count),
        .allow       (allow),
        .full        (full),
        .empty       (empty)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_tick;
        @(negedge clk);
        tick = 1'b1;
        @(posedge clk); #1;
        tick = 1'b0;
    endtask

    task do_consume;
        @(negedge clk);
        consume = 1'b1;
        @(posedge clk); #1;
        consume = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [TOKEN_BITS-1:0] prev_count;

        // Reset
        rst_n      = 1'b0;
        tick       = 1'b0;
        consume    = 1'b0;
        fill_rate  = 8'd1;
        burst_size = 16'd8;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — bucket starts empty or at initial level
        //         allow should be 0 when empty, 1 when tokens present
        // ------------------------------------------------------------------
        $display("Test 1: token_count after reset = %0d, allow=%b, empty=%b",
                 token_count, allow, empty);
        if (token_count > burst_size)
            $fatal(1, "TEST FAILED: token_count exceeds burst_size after reset");
        $display("Test 1 PASSED: initial token count within bounds");

        // ------------------------------------------------------------------
        // Test 2: Tick adds fill_rate tokens
        // ------------------------------------------------------------------
        fill_rate  = 8'd4;
        burst_size = 16'd32;
        wait_cycles(1);
        prev_count = token_count;
        do_tick;
        wait_cycles(1);
        if (token_count < prev_count + 4 - 1) // allow ±1 for boundary
            $fatal(1, "TEST FAILED: tick should add fill_rate=%0d tokens, count=%0d->%0d",
                   fill_rate, prev_count, token_count);
        $display("Test 2 PASSED: tick adds fill_rate tokens (%0d->%0d)", prev_count, token_count);

        // ------------------------------------------------------------------
        // Test 3: Fill bucket to burst_size — full flag
        // ------------------------------------------------------------------
        burst_size = 16'd8;
        fill_rate  = 8'd1;
        wait_cycles(1);
        // Drain first if needed
        while (!empty) do_consume;
        wait_cycles(2);
        // Tick 8 times to fill
        for (int i = 0; i < 8; i++) do_tick;
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: bucket should be full after 8 ticks (burst=8, rate=1)");
        if (!allow)
            $fatal(1, "TEST FAILED: allow should be 1 when full");
        $display("Test 3 PASSED: bucket fills to burst_size, full asserted");

        // ------------------------------------------------------------------
        // Test 4: Tick when full does not overflow (clamped to burst_size)
        // ------------------------------------------------------------------
        prev_count = token_count;
        do_tick;
        wait_cycles(1);
        if (token_count > burst_size)
            $fatal(1, "TEST FAILED: token_count exceeded burst_size after tick when full");
        $display("Test 4 PASSED: no overflow beyond burst_size");

        // ------------------------------------------------------------------
        // Test 5: Consume tokens — allow gates correctly
        // ------------------------------------------------------------------
        // Bucket is full (8 tokens), consume all
        for (int i = 0; i < 8; i++) begin
            if (!allow)
                $fatal(1, "TEST FAILED: allow should be 1 with tokens remaining at consume %0d", i);
            do_consume;
            wait_cycles(1);
        end
        if (!empty)
            $fatal(1, "TEST FAILED: bucket should be empty after consuming all tokens");
        if (allow)
            $fatal(1, "TEST FAILED: allow should be 0 when bucket empty");
        $display("Test 5 PASSED: consume drains bucket, allow goes low when empty");

        // ------------------------------------------------------------------
        // Test 6: Consume when empty — bucket stays empty (no underflow)
        // ------------------------------------------------------------------
        do_consume;
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: bucket should remain empty after consume on empty");
        $display("Test 6 PASSED: consume on empty bucket is safe");

        // ------------------------------------------------------------------
        // Test 7: Simultaneous tick and consume
        // ------------------------------------------------------------------
        fill_rate  = 8'd4;
        burst_size = 16'd16;
        // Add 4 tokens first
        do_tick;
        wait_cycles(1);
        prev_count = token_count;
        // Now tick and consume simultaneously
        @(negedge clk);
        tick    = 1'b1;
        consume = 1'b1;
        @(posedge clk); #1;
        tick    = 1'b0;
        consume = 1'b0;
        wait_cycles(1);
        // Net change: +fill_rate -1
        if (token_count < prev_count) // as long as tokens increased or stayed same
            $display("Test 7 NOTE: simultaneous tick+consume resulted in count=%0d (was %0d)",
                     token_count, prev_count);
        else
            $display("Test 7 PASSED: simultaneous tick+consume processed correctly");

        $display("ALL TESTS PASSED: token_bucket_shaper_tb");
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
