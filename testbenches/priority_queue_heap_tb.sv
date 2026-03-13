`timescale 1ns/1ps

module priority_queue_heap_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD     = 10;
    parameter int DATA_WIDTH     = 8;
    parameter int PRIORITY_WIDTH = 4;
    parameter int DEPTH          = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                         clk;
    logic                         rst_n;
    logic                         push;
    logic                         pop;
    logic [DATA_WIDTH-1:0]        din;
    logic [PRIORITY_WIDTH-1:0]    priority_in;
    logic [DATA_WIDTH-1:0]        dout;
    logic [PRIORITY_WIDTH-1:0]    priority_out;
    logic                         full;
    logic                         empty;
    logic [$clog2(DEPTH):0]       count;
    logic                         busy;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    priority_queue_heap #(
        .DATA_WIDTH     (DATA_WIDTH),
        .PRIORITY_WIDTH (PRIORITY_WIDTH),
        .DEPTH          (DEPTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .push         (push),
        .pop          (pop),
        .din          (din),
        .priority_in  (priority_in),
        .dout         (dout),
        .priority_out (priority_out),
        .full         (full),
        .empty        (empty),
        .count        (count),
        .busy         (busy)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // Wait until not busy
    task wait_not_busy;
        @(posedge clk); #1;
        while (busy) @(posedge clk); #1;
    endtask

    task do_push(input logic [DATA_WIDTH-1:0] data,
                 input logic [PRIORITY_WIDTH-1:0] prio);
        wait_not_busy;
        @(negedge clk);
        push        = 1'b1;
        din         = data;
        priority_in = prio;
        @(posedge clk); #1;
        push = 1'b0;
        wait_not_busy;
    endtask

    task do_pop(output logic [DATA_WIDTH-1:0]     data,
                output logic [PRIORITY_WIDTH-1:0] prio);
        wait_not_busy;
        @(negedge clk);
        pop = 1'b1;
        @(posedge clk); #1;
        pop  = 1'b0;
        data = dout;
        prio = priority_out;
        wait_not_busy;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0]     rdata;
        logic [PRIORITY_WIDTH-1:0] rprio;
        logic [PRIORITY_WIDTH-1:0] last_prio;

        // Reset
        rst_n       = 1'b0;
        push        = 1'b0;
        pop         = 1'b0;
        din         = '0;
        priority_in = '0;
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
        // Test 2: Insert 5 items with varying priorities, verify no busy
        //         violations (we wait for busy==0 before each operation)
        // ------------------------------------------------------------------
        do_push(8'hD0, 4'd8);
        do_push(8'hB0, 4'd3);
        do_push(8'hA0, 4'd1);   // highest priority (min-heap)
        do_push(8'hC0, 4'd5);
        do_push(8'hE0, 4'd12);
        wait_cycles(1);
        if (count !== 5)
            $fatal(1, "TEST FAILED: count should be 5, got %0d", count);
        $display("Test 2 PASSED: inserted 5 items");

        // ------------------------------------------------------------------
        // Test 3: Pop all — should come out in ascending priority order (min-heap)
        // ------------------------------------------------------------------
        last_prio = 4'd0;
        for (int i = 0; i < 5; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at pop %0d", i);
            do_pop(rdata, rprio);
            if (rprio < last_prio)
                $fatal(1, "TEST FAILED: priority not monotone at pop %0d: got %0d after %0d",
                       i, rprio, last_prio);
            last_prio = rprio;
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after 5 pops");
        $display("Test 3 PASSED: items popped in min-heap priority order");

        // ------------------------------------------------------------------
        // Test 4: Push until full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++)
            do_push(8'(i), 4'(i));
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d pushes", DEPTH);
        $display("Test 4 PASSED: push until full");

        // ------------------------------------------------------------------
        // Test 5: Overflow prevention (busy must be 0 before we try)
        // ------------------------------------------------------------------
        wait_not_busy;
        @(negedge clk); push = 1; din = 8'hFF; priority_in = 4'd0;
        @(posedge clk); #1; push = 0;
        wait_not_busy;
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        $display("Test 5 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Pop all in order
        // ------------------------------------------------------------------
        last_prio = 4'd0;
        for (int i = 0; i < DEPTH; i++) begin
            do_pop(rdata, rprio);
            if (rprio < last_prio)
                $fatal(1, "TEST FAILED: priority not monotone at drain pop %0d", i);
            last_prio = rprio;
        end
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after drain");
        $display("Test 6 PASSED: full drain in priority order");

        $display("ALL TESTS PASSED: priority_queue_heap_tb");
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
