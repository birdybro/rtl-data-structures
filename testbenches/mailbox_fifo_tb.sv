`timescale 1ns/1ps

module mailbox_fifo_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int DATA_WIDTH  = 8;
    parameter int DEPTH       = 8;
    parameter int NUM_ENTRIES = DEPTH;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                            clk;
    logic                            rst_n;
    logic                            push;
    logic                            pop;
    logic [DATA_WIDTH-1:0]           din;
    logic [DATA_WIDTH-1:0]           dout;
    logic                            full;
    logic                            empty;
    logic [$clog2(NUM_ENTRIES):0]    count;
    logic                            valid_out;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    mailbox_fifo #(
        .DATA_WIDTH  (DATA_WIDTH),
        .DEPTH       (DEPTH),
        .NUM_ENTRIES (NUM_ENTRIES)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .push      (push),
        .pop       (pop),
        .din       (din),
        .dout      (dout),
        .full      (full),
        .empty     (empty),
        .count     (count),
        .valid_out (valid_out)
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
        // Test 1: After reset — empty, valid_out low
        // ------------------------------------------------------------------
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after reset");
        if (valid_out)
            $fatal(1, "TEST FAILED: valid_out should be 0 when empty");
        $display("Test 1 PASSED: empty and valid_out=0 after reset");

        // ------------------------------------------------------------------
        // Test 2: Push one entry — valid_out goes high, dout is visible
        // ------------------------------------------------------------------
        do_push(8'hA5);
        #1; // let combinational settle
        if (!valid_out)
            $fatal(1, "TEST FAILED: valid_out should be 1 after push");
        if (dout !== 8'hA5)
            $fatal(1, "TEST FAILED: dout should be 0xA5, got 0x%02h", dout);
        if (count !== 1)
            $fatal(1, "TEST FAILED: count should be 1, got %0d", count);
        $display("Test 2 PASSED: push sets valid_out and dout");

        // ------------------------------------------------------------------
        // Test 3: Pop that entry — valid_out goes low again
        // ------------------------------------------------------------------
        do_pop(rdata);
        #1;
        if (rdata !== 8'hA5)
            $fatal(1, "TEST FAILED: popped value should be 0xA5, got 0x%02h", rdata);
        if (valid_out)
            $fatal(1, "TEST FAILED: valid_out should be 0 after draining");
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after pop");
        $display("Test 3 PASSED: pop clears valid_out when empty");

        // ------------------------------------------------------------------
        // Test 4: Push until full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (full)
                $fatal(1, "TEST FAILED: full too early at i=%0d", i);
            do_push(8'(i + 1));
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d pushes", DEPTH);
        if (count !== NUM_ENTRIES)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", NUM_ENTRIES, count);
        $display("Test 4 PASSED: push until full");

        // ------------------------------------------------------------------
        // Test 5: Overflow prevention
        // ------------------------------------------------------------------
        do_push(8'hFF);
        wait_cycles(1);
        if (count !== NUM_ENTRIES)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        $display("Test 5 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Pop all in FIFO order, valid_out tracks non-empty state
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (!valid_out)
                $fatal(1, "TEST FAILED: valid_out should be 1 at pop %0d", i);
            do_pop(rdata);
            if (rdata !== 8'(i + 1))
                $fatal(1, "TEST FAILED: FIFO order broken: expected %0d got %0d", i+1, rdata);
        end
        #1;
        if (valid_out)
            $fatal(1, "TEST FAILED: valid_out should be 0 after draining");
        $display("Test 6 PASSED: pop all in FIFO order, valid_out tracks");

        // ------------------------------------------------------------------
        // Test 7: Underflow prevention
        // ------------------------------------------------------------------
        do_pop(rdata);
        wait_cycles(1);
        if (count !== 0)
            $fatal(1, "TEST FAILED: underflow changed count to %0d", count);
        $display("Test 7 PASSED: underflow prevention");

        // ------------------------------------------------------------------
        // Test 8: Simultaneous push+pop
        // ------------------------------------------------------------------
        do_push(8'hDE);
        do_push(8'hAD);
        wait_cycles(1);
        @(negedge clk);
        push = 1'b1; pop = 1'b1; din = 8'hBE;
        @(posedge clk); #1;
        push = 1'b0; pop = 1'b0;
        wait_cycles(1);
        if (count !== 2)
            $fatal(1, "TEST FAILED: simultaneous push+pop changed count to %0d", count);
        $display("Test 8 PASSED: simultaneous push+pop");

        $display("ALL TESTS PASSED: mailbox_fifo_tb");
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
