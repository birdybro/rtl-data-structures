`timescale 1ns/1ps

module showahead_fifo_tb;

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
    showahead_fifo #(
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

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] saved_dout;

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
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Write one entry and verify dout appears WITHOUT rd_en
        //         (show-ahead / look-ahead property)
        // ------------------------------------------------------------------
        @(negedge clk);
        wr_en = 1'b1;
        din   = 8'hA5;
        @(posedge clk); #1;
        wr_en = 1'b0;
        // Give combinational logic a moment to settle
        #1;
        if (empty)
            $fatal(1, "TEST FAILED: FIFO should not be empty after write");
        if (dout !== 8'hA5)
            $fatal(1, "TEST FAILED: showahead dout should be 0xA5 without rd_en, got 0x%02h", dout);
        $display("Test 2 PASSED: dout shows head without rd_en");

        // ------------------------------------------------------------------
        // Test 3: Write more entries; dout must stay at head (0xA5)
        // ------------------------------------------------------------------
        @(negedge clk);
        wr_en = 1'b1;
        din   = 8'hB6;
        @(posedge clk); #1;
        wr_en = 1'b0; #1;
        @(negedge clk);
        wr_en = 1'b1;
        din   = 8'hC7;
        @(posedge clk); #1;
        wr_en = 1'b0; #1;
        if (dout !== 8'hA5)
            $fatal(1, "TEST FAILED: dout changed from head after additional writes, got 0x%02h", dout);
        $display("Test 3 PASSED: dout stable at head after more writes");

        // ------------------------------------------------------------------
        // Test 4: rd_en advances to next entry
        // ------------------------------------------------------------------
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk); #1;
        rd_en = 1'b0; #1;
        if (dout !== 8'hB6)
            $fatal(1, "TEST FAILED: after rd_en dout should be 0xB6, got 0x%02h", dout);
        $display("Test 4 PASSED: rd_en advances dout to next head");

        // ------------------------------------------------------------------
        // Test 5: Write until full
        // ------------------------------------------------------------------
        // FIFO has 1 entry (0xB6 not yet consumed + 0xC7) -> 2 entries
        // Fill remaining DEPTH-2 slots
        for (int i = 0; i < (DEPTH - 2); i++) begin
            @(negedge clk);
            wr_en = 1'b1;
            din   = 8'(i + 10);
            @(posedge clk); #1;
            wr_en = 1'b0;
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: FIFO should be full");
        $display("Test 5 PASSED: write until full");

        // ------------------------------------------------------------------
        // Test 6: Overflow prevention
        // ------------------------------------------------------------------
        saved_dout = dout;
        @(negedge clk);
        wr_en = 1'b1;
        din   = 8'hFF;
        @(posedge clk); #1;
        wr_en = 1'b0; #1;
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow changed count to %0d", count);
        if (dout !== saved_dout)
            $fatal(1, "TEST FAILED: overflow changed dout");
        $display("Test 6 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 7: Read until empty
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at read %0d", i);
            @(negedge clk);
            rd_en = 1'b1;
            @(posedge clk); #1;
            rd_en = 1'b0; #1;
        end
        if (!empty)
            $fatal(1, "TEST FAILED: FIFO should be empty after draining");
        $display("Test 7 PASSED: read until empty");

        // ------------------------------------------------------------------
        // Test 8: Simultaneous read+write keeps count stable
        // ------------------------------------------------------------------
        @(negedge clk); wr_en = 1; din = 8'h11; @(posedge clk); #1; wr_en = 0;
        @(negedge clk); wr_en = 1; din = 8'h22; @(posedge clk); #1; wr_en = 0;
        wait_cycles(1);
        @(negedge clk);
        wr_en = 1'b1;
        rd_en = 1'b1;
        din   = 8'h33;
        @(posedge clk); #1;
        wr_en = 1'b0;
        rd_en = 1'b0;
        wait_cycles(1);
        if (count !== 2)
            $fatal(1, "TEST FAILED: simultaneous rd+wr changed count, got %0d", count);
        $display("Test 8 PASSED: simultaneous read+write");

        $display("ALL TESTS PASSED: showahead_fifo_tb");
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
