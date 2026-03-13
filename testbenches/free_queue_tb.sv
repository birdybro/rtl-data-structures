`timescale 1ns/1ps

module free_queue_tb;

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
    logic                   enqueue;
    logic                   dequeue;
    logic                   clear;
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
    free_queue #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .enqueue (enqueue),
        .dequeue (dequeue),
        .clear   (clear),
        .din     (din),
        .dout    (dout),
        .full    (full),
        .empty   (empty),
        .count   (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_enqueue(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        enqueue = 1'b1;
        din     = data;
        @(posedge clk); #1;
        enqueue = 1'b0;
    endtask

    task do_dequeue(output logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        dequeue = 1'b1;
        @(posedge clk); #1;
        dequeue = 1'b0;
        data    = dout;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic [DATA_WIDTH-1:0] dequeued [0:DEPTH-1];

        // Reset
        rst_n   = 1'b0;
        enqueue = 1'b0;
        dequeue = 1'b0;
        clear   = 1'b0;
        din     = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — pre-loaded with IDs 0..DEPTH-1, not empty
        //         (free_queue is pre-loaded with all free IDs)
        // ------------------------------------------------------------------
        if (empty)
            $fatal(1, "TEST FAILED: free_queue should NOT be empty after reset (pre-loaded)");
        if (!full)
            $fatal(1, "TEST FAILED: free_queue should be full after reset (all IDs available)");
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d after reset, got %0d", DEPTH, count);
        $display("Test 1 PASSED: pre-loaded with %0d IDs after reset", DEPTH);

        // ------------------------------------------------------------------
        // Test 2: Dequeue all entries — should get IDs 0..DEPTH-1 in order
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at dequeue %0d", i);
            // dout is combinational — read before dequeue
            dequeued[i] = dout;
            do_dequeue(rdata);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after dequeuing all");
        if (count !== 0)
            $fatal(1, "TEST FAILED: count should be 0, got %0d", count);

        // Verify the IDs are 0..DEPTH-1 (order may vary but must be a permutation)
        begin
            logic seen [0:DEPTH-1];
            for (int i = 0; i < DEPTH; i++) seen[i] = 1'b0;
            for (int i = 0; i < DEPTH; i++) begin
                if (dequeued[i] >= DEPTH)
                    $fatal(1, "TEST FAILED: dequeued ID %0d out of range [0,%0d)",
                           dequeued[i], DEPTH);
                if (seen[dequeued[i]])
                    $fatal(1, "TEST FAILED: duplicate ID %0d dequeued", dequeued[i]);
                seen[dequeued[i]] = 1'b1;
            end
        end
        $display("Test 2 PASSED: all DEPTH=%0d IDs dequeued, all unique", DEPTH);

        // ------------------------------------------------------------------
        // Test 3: Dequeue from empty — count stays 0
        // ------------------------------------------------------------------
        do_dequeue(rdata);
        wait_cycles(1);
        if (count !== 0)
            $fatal(1, "TEST FAILED: underflow dequeue changed count to %0d", count);
        $display("Test 3 PASSED: dequeue from empty safe");

        // ------------------------------------------------------------------
        // Test 4: Enqueue IDs back in — available again
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (full)
                $fatal(1, "TEST FAILED: full too early at enqueue %0d", i);
            do_enqueue(8'(i));
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after enqueuing all back");
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", DEPTH, count);
        $display("Test 4 PASSED: enqueue all IDs back");

        // ------------------------------------------------------------------
        // Test 5: Enqueue overflow prevention
        // ------------------------------------------------------------------
        do_enqueue(8'hFF);
        wait_cycles(1);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow enqueue changed count to %0d", count);
        $display("Test 5 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Clear operation — resets queue
        // ------------------------------------------------------------------
        // Drain half
        for (int i = 0; i < DEPTH/2; i++) do_dequeue(rdata);
        wait_cycles(1);
        // Now clear
        @(negedge clk); clear = 1'b1; @(posedge clk); #1; clear = 1'b0;
        wait_cycles(2);
        if (!empty || count !== 0)
            $fatal(1, "TEST FAILED: after clear should be empty, count=%0d", count);
        $display("Test 6 PASSED: clear empties the queue");

        // ------------------------------------------------------------------
        // Test 7: Simultaneous enqueue+dequeue — count stays the same
        // ------------------------------------------------------------------
        do_enqueue(8'h01);
        do_enqueue(8'h02);
        wait_cycles(1);
        @(negedge clk);
        enqueue = 1'b1; dequeue = 1'b1; din = 8'h03;
        @(posedge clk); #1;
        enqueue = 1'b0; dequeue = 1'b0;
        wait_cycles(1);
        if (count !== 2)
            $fatal(1, "TEST FAILED: simultaneous en+de changed count to %0d", count);
        $display("Test 7 PASSED: simultaneous enqueue+dequeue keeps count stable");

        $display("ALL TESTS PASSED: free_queue_tb");
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
