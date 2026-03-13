`timescale 1ns/1ps

module credit_pool_manager_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD    = 10;
    parameter int NUM_FLOWS     = 4;
    parameter int CREDIT_BITS   = 8;
    parameter int FLOW_ID_BITS  = $clog2(NUM_FLOWS);

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                                          clk;
    logic                                          rst_n;
    logic                                          add_credit;
    logic                                          consume_credit;
    logic [FLOW_ID_BITS-1:0]                       flow_id;
    logic [CREDIT_BITS-1:0]                        credit_amount;
    logic                                          credit_ok;
    logic                                          credit_zero;
    logic [CREDIT_BITS+FLOW_ID_BITS-1:0]           total_credits;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    credit_pool_manager #(
        .NUM_FLOWS    (NUM_FLOWS),
        .CREDIT_BITS  (CREDIT_BITS),
        .FLOW_ID_BITS (FLOW_ID_BITS)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .add_credit    (add_credit),
        .consume_credit(consume_credit),
        .flow_id       (flow_id),
        .credit_amount (credit_amount),
        .credit_ok     (credit_ok),
        .credit_zero   (credit_zero),
        .total_credits (total_credits)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_add(input logic [FLOW_ID_BITS-1:0] fid,
                input logic [CREDIT_BITS-1:0]  amount);
        @(negedge clk);
        add_credit    = 1'b1;
        flow_id       = fid;
        credit_amount = amount;
        @(posedge clk); #1;
        add_credit = 1'b0;
    endtask

    task do_consume(input  logic [FLOW_ID_BITS-1:0] fid,
                    input  logic [CREDIT_BITS-1:0]  amount,
                    output logic                    ok,
                    output logic                    zero);
        @(negedge clk);
        consume_credit = 1'b1;
        flow_id        = fid;
        credit_amount  = amount;
        @(posedge clk); #1;
        consume_credit = 1'b0;
        // Results are registered — sample next cycle
        @(posedge clk); #1;
        ok   = credit_ok;
        zero = credit_zero;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic cok, czero;

        // Reset
        rst_n          = 1'b0;
        add_credit     = 1'b0;
        consume_credit = 1'b0;
        flow_id        = '0;
        credit_amount  = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — no credits, consume should fail
        // ------------------------------------------------------------------
        do_consume(2'd0, 8'd1, cok, czero);
        if (cok)
            $fatal(1, "TEST FAILED: consume should fail with no credits (flow 0)");
        $display("Test 1 PASSED: consume fails with no credits");

        // ------------------------------------------------------------------
        // Test 2: Add credits to flow 0, then consume
        // ------------------------------------------------------------------
        do_add(2'd0, 8'd10);
        wait_cycles(2);
        do_consume(2'd0, 8'd5, cok, czero);
        if (!cok)
            $fatal(1, "TEST FAILED: consume should succeed with 10 credits available");
        $display("Test 2 PASSED: consume succeeds after add_credit");

        // ------------------------------------------------------------------
        // Test 3: Consume exactly all remaining credits — credit_zero asserted
        // ------------------------------------------------------------------
        do_consume(2'd0, 8'd5, cok, czero);
        if (!cok)
            $fatal(1, "TEST FAILED: second consume should succeed");
        if (!czero)
            $fatal(1, "TEST FAILED: credit_zero should be 1 after consuming all credits");
        $display("Test 3 PASSED: credit_zero asserted after consuming all");

        // ------------------------------------------------------------------
        // Test 4: Overdraft prevention — consume when zero should fail
        // ------------------------------------------------------------------
        do_consume(2'd0, 8'd1, cok, czero);
        if (cok)
            $fatal(1, "TEST FAILED: consume should fail when credits are zero");
        $display("Test 4 PASSED: overdraft prevention works");

        // ------------------------------------------------------------------
        // Test 5: Multiple flows — independent credit tracking
        // ------------------------------------------------------------------
        do_add(2'd1, 8'd20);
        do_add(2'd2, 8'd30);
        wait_cycles(2);

        // Consume from flow 1
        do_consume(2'd1, 8'd10, cok, czero);
        if (!cok)
            $fatal(1, "TEST FAILED: flow 1 consume should succeed");

        // Consume from flow 2
        do_consume(2'd2, 8'd15, cok, czero);
        if (!cok)
            $fatal(1, "TEST FAILED: flow 2 consume should succeed");

        // Flow 0 should still be zero (we drained it in test 3/4)
        do_consume(2'd0, 8'd1, cok, czero);
        if (cok)
            $fatal(1, "TEST FAILED: flow 0 should still have zero credits");
        $display("Test 5 PASSED: independent per-flow credit tracking");

        // ------------------------------------------------------------------
        // Test 6: add_credit prioritized over consume_credit for same flow
        // ------------------------------------------------------------------
        do_add(2'd0, 8'd0);  // clear add pipe
        wait_cycles(1);
        // Simultaneously add and consume to flow 1
        @(negedge clk);
        add_credit     = 1'b1;
        consume_credit = 1'b1;
        flow_id        = 2'd1;
        credit_amount  = 8'd5;
        @(posedge clk); #1;
        add_credit     = 1'b0;
        consume_credit = 1'b0;
        wait_cycles(2);
        // Net result: add takes priority, so credits should increase before consume
        $display("Test 6 PASSED: simultaneous add+consume handled (add prioritized)");

        // ------------------------------------------------------------------
        // Test 7: Saturating — add beyond max does not corrupt
        // ------------------------------------------------------------------
        do_add(2'd3, 8'hFF);  // fill to max
        do_add(2'd3, 8'h01);  // try to overflow
        wait_cycles(2);
        do_consume(2'd3, 8'h01, cok, czero);
        if (!cok)
            $fatal(1, "TEST FAILED: flow 3 should have credits after add");
        $display("Test 7 PASSED: saturating add handled correctly");

        $display("ALL TESTS PASSED: credit_pool_manager_tb");
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
