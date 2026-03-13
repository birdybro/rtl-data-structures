`timescale 1ns/1ps

module bounded_stack_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int DEPTH      = 16;
    parameter int MAX_DEPTH  = 8;   // logical limit smaller than storage

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
    logic                   overflow;
    logic                   underflow;
    logic [$clog2(DEPTH):0] count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    bounded_stack #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH),
        .MAX_DEPTH  (MAX_DEPTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .push      (push),
        .pop       (pop),
        .din       (din),
        .dout      (dout),
        .full      (full),
        .empty     (empty),
        .overflow  (overflow),
        .underflow (underflow),
        .count     (count)
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

        // Reset
        rst_n = 1'b0;
        push  = 1'b0;
        pop   = 1'b0;
        din   = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Initial state
        // ------------------------------------------------------------------
        if (!empty || overflow || underflow || count !== 0)
            $fatal(1, "TEST FAILED: invalid initial state");
        $display("Test 1 PASSED: initial state correct");

        // ------------------------------------------------------------------
        // Test 2: Push up to MAX_DEPTH — no overflow
        // ------------------------------------------------------------------
        for (int i = 0; i < MAX_DEPTH; i++) begin
            do_push(8'(i + 1));
            wait_cycles(1);
            if (overflow)
                $fatal(1, "TEST FAILED: unexpected overflow at push %0d", i);
        end
        if (!full)
            $fatal(1, "TEST FAILED: should be full at MAX_DEPTH=%0d", MAX_DEPTH);
        if (count !== MAX_DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", MAX_DEPTH, count);
        $display("Test 2 PASSED: push to MAX_DEPTH without overflow");

        // ------------------------------------------------------------------
        // Test 3: Push beyond MAX_DEPTH — overflow must pulse
        // ------------------------------------------------------------------
        do_push(8'hFF);
        wait_cycles(1);
        if (!overflow)
            $fatal(1, "TEST FAILED: overflow should be 1 when pushing past MAX_DEPTH");
        if (count !== MAX_DEPTH)
            $fatal(1, "TEST FAILED: count changed on overflow push, got %0d", count);
        $display("Test 3 PASSED: overflow detected on push past MAX_DEPTH");

        // Overflow should be a pulse, not sticky
        wait_cycles(1);
        if (overflow)
            $fatal(1, "TEST FAILED: overflow should clear after one cycle (no push)");
        $display("Test 3b PASSED: overflow pulse is non-sticky");

        // ------------------------------------------------------------------
        // Test 4: LIFO order on pop
        // ------------------------------------------------------------------
        for (int i = MAX_DEPTH-1; i >= 0; i--) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at pop %0d", i);
            do_pop(rdata);
            if (rdata !== 8'(i + 1))
                $fatal(1, "TEST FAILED: LIFO order wrong: expected %0d got %0d", i+1, rdata);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after popping all");
        $display("Test 4 PASSED: LIFO order correct");

        // ------------------------------------------------------------------
        // Test 5: Pop from empty — underflow must pulse
        // ------------------------------------------------------------------
        do_pop(rdata);
        wait_cycles(1);
        if (!underflow)
            $fatal(1, "TEST FAILED: underflow should be 1 when popping empty stack");
        if (count !== 0)
            $fatal(1, "TEST FAILED: count changed on underflow pop, got %0d", count);
        $display("Test 5 PASSED: underflow detected on pop from empty");

        // Underflow should be a pulse
        wait_cycles(1);
        if (underflow)
            $fatal(1, "TEST FAILED: underflow should clear after one cycle (no pop)");
        $display("Test 5b PASSED: underflow pulse is non-sticky");

        // ------------------------------------------------------------------
        // Test 6: Multiple overflow cycles
        // ------------------------------------------------------------------
        for (int i = 0; i < MAX_DEPTH; i++) do_push(8'(i));
        for (int i = 0; i < 3; i++) begin
            do_push(8'hAB);
            wait_cycles(1);
            if (!overflow)
                $fatal(1, "TEST FAILED: overflow not asserted on repeated overflow push %0d", i);
        end
        $display("Test 6 PASSED: repeated overflow pushes all flagged");

        $display("ALL TESTS PASSED: bounded_stack_tb");
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
