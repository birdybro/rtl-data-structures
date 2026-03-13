`timescale 1ns/1ps

module priority_queue_linear_tb;

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

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    priority_queue_linear #(
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
        .count        (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_push(input logic [DATA_WIDTH-1:0] data,
                 input logic [PRIORITY_WIDTH-1:0] prio);
        @(negedge clk);
        push        = 1'b1;
        din         = data;
        priority_in = prio;
        @(posedge clk); #1;
        push = 1'b0;
    endtask

    task do_pop(output logic [DATA_WIDTH-1:0]     data,
                output logic [PRIORITY_WIDTH-1:0] prio);
        @(negedge clk);
        pop = 1'b1;
        @(posedge clk); #1;
        pop  = 1'b0;
        data = dout;
        prio = priority_out;
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
        // Test 2: Insert items with various priorities (lower = higher priority)
        //         Push in non-priority order to test sorting
        // ------------------------------------------------------------------
        do_push(8'hD0, 4'd8);   // lowest priority
        do_push(8'hB0, 4'd3);   // mid priority
        do_push(8'hA0, 4'd1);   // highest priority
        do_push(8'hC0, 4'd5);   // mid priority
        do_push(8'hE0, 4'd12);  // very low priority
        wait_cycles(1);
        if (count !== 5)
            $fatal(1, "TEST FAILED: count should be 5, got %0d", count);
        $display("Test 2 PASSED: pushed 5 items with various priorities");

        // ------------------------------------------------------------------
        // Test 3: Pop should return highest-priority (lowest numeric prio) first
        // ------------------------------------------------------------------
        last_prio = '0; // will track ascending priority
        for (int i = 0; i < 5; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at pop %0d", i);
            // dout/priority_out are combinational
            rprio = priority_out;
            rdata = dout;
            if (i > 0 && rprio < last_prio)
                $fatal(1, "TEST FAILED: priority order wrong at pop %0d: prio=%0d after prio=%0d",
                       i, rprio, last_prio);
            last_prio = rprio;
            do_pop(rdata, rprio);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after 5 pops");
        $display("Test 3 PASSED: items dequeued in priority order");

        // ------------------------------------------------------------------
        // Test 4: Push until full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++)
            do_push(8'(i), 4'(DEPTH - i)); // descending priorities
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d pushes", DEPTH);
        $display("Test 4 PASSED: push until full");

        // ------------------------------------------------------------------
        // Test 5: Overflow prevention
        // ------------------------------------------------------------------
        do_push(8'hFF, 4'd0);
        wait_cycles(1);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        $display("Test 5 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Pop all, verify monotonically increasing priority
        // ------------------------------------------------------------------
        last_prio = 4'd0;
        for (int i = 0; i < DEPTH; i++) begin
            rprio = priority_out;
            if (rprio < last_prio)
                $fatal(1, "TEST FAILED: priority not monotonic at pop %0d", i);
            last_prio = rprio;
            do_pop(rdata, rprio);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after draining");
        $display("Test 6 PASSED: monotonic priority ordering over full drain");

        // ------------------------------------------------------------------
        // Test 7: Underflow prevention
        // ------------------------------------------------------------------
        do_pop(rdata, rprio);
        wait_cycles(1);
        if (count !== 0)
            $fatal(1, "TEST FAILED: underflow changed count to %0d", count);
        $display("Test 7 PASSED: underflow prevention");

        $display("ALL TESTS PASSED: priority_queue_linear_tb");
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
