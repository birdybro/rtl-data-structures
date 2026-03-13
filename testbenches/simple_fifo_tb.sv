`timescale 1ns/1ps

module simple_fifo_tb;

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
    logic                   wr_en;
    logic                   rd_en;
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
    simple_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (wr_en),
        .rd_en (rd_en),
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

    task write_word(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        wr_en = 1'b1;
        din   = data;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
    endtask

    task read_word(output logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        #1;
        rd_en = 1'b0;
        data  = dout;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;

        // Reset
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Empty check after reset
        // ------------------------------------------------------------------
        if (!empty)
            $fatal(1, "TEST FAILED: FIFO should be empty after reset");
        if (count !== 0)
            $fatal(1, "TEST FAILED: count should be 0 after reset, got %0d", count);
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Write until full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (full)
                $fatal(1, "TEST FAILED: FIFO full too early at i=%0d", i);
            write_word(8'(i + 1));
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: FIFO should be full after %0d writes", DEPTH);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", DEPTH, count);
        $display("Test 2 PASSED: write until full");

        // ------------------------------------------------------------------
        // Test 3: Overflow prevention — write when full should be ignored
        // ------------------------------------------------------------------
        @(negedge clk);
        wr_en = 1'b1;
        din   = 8'hFF;
        @(posedge clk); #1;
        wr_en = 1'b0;
        wait_cycles(1);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow write changed count to %0d", count);
        $display("Test 3 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 4: Read until empty, verify FIFO (first-in first-out) order
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: FIFO empty too early at i=%0d", i);
            read_word(rdata);
            if (rdata !== 8'(i + 1))
                $fatal(1, "TEST FAILED: expected %0d, got %0d at read %0d", i+1, rdata, i);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: FIFO should be empty after reading all entries");
        $display("Test 4 PASSED: FIFO order and read until empty");

        // ------------------------------------------------------------------
        // Test 5: Underflow prevention — read when empty should be ignored
        // ------------------------------------------------------------------
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk); #1;
        rd_en = 1'b0;
        wait_cycles(1);
        if (count !== 0)
            $fatal(1, "TEST FAILED: underflow read changed count to %0d", count);
        $display("Test 5 PASSED: underflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Simultaneous read and write (count stays the same)
        // ------------------------------------------------------------------
        write_word(8'hAA);
        write_word(8'hBB);
        wait_cycles(1);
        @(negedge clk);
        wr_en = 1'b1;
        rd_en = 1'b1;
        din   = 8'hCC;
        @(posedge clk); #1;
        wr_en = 1'b0;
        rd_en = 1'b0;
        if (count !== 2)
            $fatal(1, "TEST FAILED: simultaneous rd+wr changed count from 2, got %0d", count);
        $display("Test 6 PASSED: simultaneous read+write");

        $display("ALL TESTS PASSED: simple_fifo_tb");
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
