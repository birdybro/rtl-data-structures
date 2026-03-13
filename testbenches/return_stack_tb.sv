`timescale 1ns/1ps

module return_stack_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int ADDR_WIDTH  = 16;
    parameter int DEPTH       = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                    clk;
    logic                    rst_n;
    logic                    call;
    logic                    ret;
    logic [ADDR_WIDTH-1:0]   pc_in;
    logic [ADDR_WIDTH-1:0]   pc_out;
    logic                    full;
    logic                    empty;
    logic [$clog2(DEPTH):0]  depth;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    return_stack #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .call   (call),
        .ret    (ret),
        .pc_in  (pc_in),
        .pc_out (pc_out),
        .full   (full),
        .empty  (empty),
        .depth  (depth)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_call(input logic [ADDR_WIDTH-1:0] addr);
        @(negedge clk);
        call  = 1'b1;
        pc_in = addr;
        @(posedge clk); #1;
        call = 1'b0;
    endtask

    task do_ret(output logic [ADDR_WIDTH-1:0] addr);
        @(negedge clk);
        ret = 1'b1;
        @(posedge clk); #1;
        ret  = 1'b0;
        addr = pc_out;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [ADDR_WIDTH-1:0] returned_pc;
        logic [ADDR_WIDTH-1:0] call_addrs [0:DEPTH-1];

        // Reset
        rst_n = 1'b0;
        call  = 1'b0;
        ret   = 1'b0;
        pc_in = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Empty after reset
        // ------------------------------------------------------------------
        if (!empty || depth !== 0)
            $fatal(1, "TEST FAILED: should be empty after reset, depth=%0d", depth);
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Single call/return cycle
        // ------------------------------------------------------------------
        do_call(16'h1234);
        wait_cycles(1);
        if (empty)
            $fatal(1, "TEST FAILED: stack should not be empty after call");
        if (depth !== 1)
            $fatal(1, "TEST FAILED: depth should be 1, got %0d", depth);
        do_ret(returned_pc);
        if (returned_pc !== 16'h1234)
            $fatal(1, "TEST FAILED: returned PC should be 0x1234, got 0x%04h", returned_pc);
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after ret");
        $display("Test 2 PASSED: single call/return");

        // ------------------------------------------------------------------
        // Test 3: Nested calls — LIFO return order
        // ------------------------------------------------------------------
        call_addrs[0] = 16'hAB01;
        call_addrs[1] = 16'hAB02;
        call_addrs[2] = 16'hAB03;
        call_addrs[3] = 16'hAB04;

        for (int i = 0; i < 4; i++)
            do_call(call_addrs[i]);
        wait_cycles(1);
        if (depth !== 4)
            $fatal(1, "TEST FAILED: depth should be 4, got %0d", depth);

        // Returns should come back in reverse order
        for (int i = 3; i >= 0; i--) begin
            do_ret(returned_pc);
            if (returned_pc !== call_addrs[i])
                $fatal(1, "TEST FAILED: LIFO order broken at %0d: expected 0x%04h got 0x%04h",
                       i, call_addrs[i], returned_pc);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after all returns");
        $display("Test 3 PASSED: nested calls return in correct LIFO order");

        // ------------------------------------------------------------------
        // Test 4: Fill to full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (full)
                $fatal(1, "TEST FAILED: full too early at call %0d", i);
            do_call(16'(i + 0x100));
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d calls", DEPTH);
        $display("Test 4 PASSED: fill to full");

        // ------------------------------------------------------------------
        // Test 5: Call when full — overflow should be ignored
        // ------------------------------------------------------------------
        do_call(16'hDEAD);
        wait_cycles(1);
        if (depth !== DEPTH)
            $fatal(1, "TEST FAILED: overflow call changed depth to %0d", depth);
        $display("Test 5 PASSED: overflow call ignored");

        // ------------------------------------------------------------------
        // Test 6: Return when empty — underflow should be ignored
        // ------------------------------------------------------------------
        // First drain the stack
        for (int i = 0; i < DEPTH; i++) do_ret(returned_pc);
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after draining");
        do_ret(returned_pc);
        wait_cycles(1);
        if (depth !== 0)
            $fatal(1, "TEST FAILED: underflow ret changed depth to %0d", depth);
        $display("Test 6 PASSED: underflow ret ignored");

        // ------------------------------------------------------------------
        // Test 7: Simultaneous call+ret replaces top address
        // ------------------------------------------------------------------
        do_call(16'h1111);
        do_call(16'h2222);
        wait_cycles(1);
        // Simultaneously call (push 0x3333) and ret (pop 0x2222)
        @(negedge clk);
        call  = 1'b1;
        ret   = 1'b1;
        pc_in = 16'h3333;
        @(posedge clk); #1;
        call = 1'b0;
        ret  = 1'b0;
        wait_cycles(1);
        if (depth !== 2)
            $fatal(1, "TEST FAILED: depth should still be 2 after call+ret, got %0d", depth);
        // Top should be 0x3333 (the call)
        do_ret(returned_pc);
        if (returned_pc !== 16'h3333)
            $fatal(1, "TEST FAILED: top should be 0x3333, got 0x%04h", returned_pc);
        $display("Test 7 PASSED: simultaneous call+ret replaces top");

        $display("ALL TESTS PASSED: return_stack_tb");
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
