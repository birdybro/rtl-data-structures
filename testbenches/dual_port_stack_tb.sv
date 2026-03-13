`timescale 1ns/1ps

module dual_port_stack_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int DEPTH      = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   push_a;
    logic                   pop_a;
    logic [DATA_WIDTH-1:0]  din_a;
    logic [DATA_WIDTH-1:0]  dout_a;
    logic                   push_b;
    logic                   pop_b;
    logic [DATA_WIDTH-1:0]  din_b;
    logic [DATA_WIDTH-1:0]  dout_b;
    logic                   full;
    logic                   empty;
    logic [$clog2(DEPTH):0] count;
    logic                   conflict;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    dual_port_stack #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .push_a   (push_a),
        .pop_a    (pop_a),
        .din_a    (din_a),
        .dout_a   (dout_a),
        .push_b   (push_b),
        .pop_b    (pop_b),
        .din_b    (din_b),
        .dout_b   (dout_b),
        .full     (full),
        .empty    (empty),
        .count    (count),
        .conflict (conflict)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata_a, rdata_b;

        // Reset
        rst_n  = 1'b0;
        push_a = 1'b0; pop_a = 1'b0; din_a = '0;
        push_b = 1'b0; pop_b = 1'b0; din_b = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Reset state
        // ------------------------------------------------------------------
        if (!empty || conflict || count !== 0)
            $fatal(1, "TEST FAILED: invalid initial state");
        $display("Test 1 PASSED: initial state correct");

        // ------------------------------------------------------------------
        // Test 2: Push via port A, pop via port A — LIFO order
        // ------------------------------------------------------------------
        @(negedge clk); push_a = 1; din_a = 8'hA1; @(posedge clk); #1; push_a = 0;
        @(negedge clk); push_a = 1; din_a = 8'hA2; @(posedge clk); #1; push_a = 0;
        @(negedge clk); push_a = 1; din_a = 8'hA3; @(posedge clk); #1; push_a = 0;
        wait_cycles(1);
        if (count !== 3)
            $fatal(1, "TEST FAILED: count should be 3 after 3 pushes from A, got %0d", count);

        @(negedge clk); pop_a = 1; @(posedge clk); #1; pop_a = 0; rdata_a = dout_a;
        if (rdata_a !== 8'hA3)
            $fatal(1, "TEST FAILED: LIFO: expected 0xA3, got 0x%02h", rdata_a);
        @(negedge clk); pop_a = 1; @(posedge clk); #1; pop_a = 0; rdata_a = dout_a;
        if (rdata_a !== 8'hA2)
            $fatal(1, "TEST FAILED: LIFO: expected 0xA2, got 0x%02h", rdata_a);
        @(negedge clk); pop_a = 1; @(posedge clk); #1; pop_a = 0; rdata_a = dout_a;
        if (rdata_a !== 8'hA1)
            $fatal(1, "TEST FAILED: LIFO: expected 0xA1, got 0x%02h", rdata_a);
        wait_cycles(1);
        if (!empty) $fatal(1, "TEST FAILED: should be empty");
        $display("Test 2 PASSED: port A push/pop LIFO order");

        // ------------------------------------------------------------------
        // Test 3: Push via port B, pop via port B — LIFO order
        // ------------------------------------------------------------------
        @(negedge clk); push_b = 1; din_b = 8'hB1; @(posedge clk); #1; push_b = 0;
        @(negedge clk); push_b = 1; din_b = 8'hB2; @(posedge clk); #1; push_b = 0;
        wait_cycles(1);
        @(negedge clk); pop_b = 1; @(posedge clk); #1; pop_b = 0; rdata_b = dout_b;
        if (rdata_b !== 8'hB2)
            $fatal(1, "TEST FAILED: LIFO via B: expected 0xB2, got 0x%02h", rdata_b);
        @(negedge clk); pop_b = 1; @(posedge clk); #1; pop_b = 0; rdata_b = dout_b;
        if (rdata_b !== 8'hB1)
            $fatal(1, "TEST FAILED: LIFO via B: expected 0xB1, got 0x%02h", rdata_b);
        $display("Test 3 PASSED: port B push/pop LIFO order");

        // ------------------------------------------------------------------
        // Test 4: Simultaneous push from both ports — count increases by 2
        // ------------------------------------------------------------------
        wait_cycles(1);
        @(negedge clk);
        push_a = 1; din_a = 8'hC1;
        push_b = 1; din_b = 8'hC2;
        @(posedge clk); #1;
        push_a = 0; push_b = 0;
        wait_cycles(1);
        if (count !== 2)
            $fatal(1, "TEST FAILED: dual push should yield count=2, got %0d", count);
        $display("Test 4 PASSED: simultaneous push from both ports");

        // ------------------------------------------------------------------
        // Test 5: Conflict detection — both ports push+pop simultaneously
        //         Port A is prioritized; conflict should be flagged
        // ------------------------------------------------------------------
        @(negedge clk);
        push_a = 1; din_a = 8'hD1;
        push_b = 1; din_b = 8'hD2;
        pop_a  = 1;
        @(posedge clk); #1;
        push_a = 0; push_b = 0; pop_a = 0;
        wait_cycles(1);
        if (!conflict)
            $fatal(1, "TEST FAILED: conflict should be flagged on simultaneous conflicting ops");
        $display("Test 5 PASSED: conflict detected on simultaneous conflicting operations");

        // ------------------------------------------------------------------
        // Test 6: Fill to full from both ports, verify full flag
        // ------------------------------------------------------------------
        // Drain first
        while (!empty) begin
            @(negedge clk); pop_a = 1; @(posedge clk); #1; pop_a = 0;
        end
        wait_cycles(2);
        // Fill with alternating ports
        for (int i = 0; i < DEPTH/2; i++) begin
            @(negedge clk);
            push_a = 1; din_a = 8'(i*2);
            push_b = 1; din_b = 8'(i*2+1);
            @(posedge clk); #1;
            push_a = 0; push_b = 0;
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after dual-port fill");
        $display("Test 6 PASSED: stack full after dual-port fill");

        $display("ALL TESTS PASSED: dual_port_stack_tb");
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
