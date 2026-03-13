`timescale 1ns/1ps

module stack_tb;

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
    logic                   push;
    logic                   pop;
    logic [DATA_WIDTH-1:0]  din;
    logic [DATA_WIDTH-1:0]  dout;
    logic                   full;
    logic                   empty;
    logic [$clog2(DEPTH):0] count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    stack #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .push  (push),
        .pop   (pop),
        .din   (din),
        .dout  (dout),
        .full  (full),
        .empty (empty),
        .count (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_push(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        push = 1'b1;
        din  = data;
        @(posedge clk); #1;
        push = 1'b0;
    endtask

    task do_pop(output logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        pop = 1'b1;
        @(posedge clk); #1;
        pop  = 1'b0;
        data = dout;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic [DATA_WIDTH-1:0] pushed [0:DEPTH-1];

        // Reset
        rst_n = 1'b0;
        push  = 1'b0;
        pop   = 1'b0;
        din   = '0;
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
        // Test 2: Push until full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (full)
                $fatal(1, "TEST FAILED: full too early at push %0d", i);
            pushed[i] = 8'(i + 1);
            do_push(pushed[i]);
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: stack should be full after %0d pushes", DEPTH);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", DEPTH, count);
        $display("Test 2 PASSED: push until full");

        // ------------------------------------------------------------------
        // Test 3: Overflow prevention
        // ------------------------------------------------------------------
        do_push(8'hFF);
        wait_cycles(1);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        $display("Test 3 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 4: LIFO order — pop must come out in reverse push order
        // ------------------------------------------------------------------
        for (int i = DEPTH-1; i >= 0; i--) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at pop %0d", i);
            do_pop(rdata);
            if (rdata !== pushed[i])
                $fatal(1, "TEST FAILED: LIFO order broken at %0d: expected %0d got %0d",
                       i, pushed[i], rdata);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after popping all");
        $display("Test 4 PASSED: LIFO order verified");

        // ------------------------------------------------------------------
        // Test 5: Underflow prevention
        // ------------------------------------------------------------------
        do_pop(rdata);
        wait_cycles(1);
        if (count !== 0)
            $fatal(1, "TEST FAILED: underflow changed count to %0d", count);
        $display("Test 5 PASSED: underflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Simultaneous push+pop replaces top without changing count
        // ------------------------------------------------------------------
        do_push(8'hAA);
        do_push(8'hBB);
        wait_cycles(1);
        @(negedge clk);
        push = 1'b1; pop = 1'b1; din = 8'hCC;
        @(posedge clk); #1;
        push = 1'b0; pop = 1'b0;
        wait_cycles(1);
        if (count !== 2)
            $fatal(1, "TEST FAILED: simultaneous push+pop changed count to %0d", count);
        // The top should now be 0xCC (new push replaced old top 0xBB)
        do_pop(rdata);
        if (rdata !== 8'hCC)
            $fatal(1, "TEST FAILED: after push+pop top should be 0xCC, got 0x%02h", rdata);
        $display("Test 6 PASSED: simultaneous push+pop replaces top");

        // ------------------------------------------------------------------
        // Test 7: After popping 0xCC, bottom should still be 0xAA
        // ------------------------------------------------------------------
        do_pop(rdata);
        if (rdata !== 8'hAA)
            $fatal(1, "TEST FAILED: bottom should be 0xAA, got 0x%02h", rdata);
        $display("Test 7 PASSED: bottom element preserved after push+pop");

        $display("ALL TESTS PASSED: stack_tb");
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
