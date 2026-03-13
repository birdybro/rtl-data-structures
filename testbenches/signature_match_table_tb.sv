`timescale 1ns/1ps

module signature_match_table_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int SIG_WIDTH   = 16;
    parameter int NUM_ENTRIES = 8;
    parameter int DATA_WIDTH  = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   insert;
    logic                   lookup;
    logic                   clear_entry;
    logic [SIG_WIDTH-1:0]   sig_in;
    logic [DATA_WIDTH-1:0]  data_in;
    logic [DATA_WIDTH-1:0]  data_out;
    logic                   match;
    logic                   no_match;
    logic                   full;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    signature_match_table #(
        .SIG_WIDTH   (SIG_WIDTH),
        .NUM_ENTRIES (NUM_ENTRIES),
        .DATA_WIDTH  (DATA_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .insert      (insert),
        .lookup      (lookup),
        .clear_entry (clear_entry),
        .sig_in      (sig_in),
        .data_in     (data_in),
        .data_out    (data_out),
        .match       (match),
        .no_match    (no_match),
        .full        (full)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_insert(input logic [SIG_WIDTH-1:0]  sig,
                   input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        insert   = 1'b1;
        sig_in   = sig;
        data_in  = data;
        @(posedge clk); #1;
        insert = 1'b0;
    endtask

    // Results are registered (1-cycle latency)
    task do_lookup(input  logic [SIG_WIDTH-1:0]  sig,
                   output logic [DATA_WIDTH-1:0] data,
                   output logic                  m,
                   output logic                  nm);
        @(negedge clk);
        lookup = 1'b1;
        sig_in = sig;
        @(posedge clk); #1;
        lookup = 1'b0;
        @(posedge clk); #1;
        data = data_out;
        m    = match;
        nm   = no_match;
    endtask

    task do_clear(input logic [SIG_WIDTH-1:0] sig);
        @(negedge clk);
        clear_entry = 1'b1;
        sig_in      = sig;
        @(posedge clk); #1;
        clear_entry = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rm, rnm;

        // Reset
        rst_n       = 1'b0;
        insert      = 1'b0;
        lookup      = 1'b0;
        clear_entry = 1'b0;
        sig_in      = '0;
        data_in     = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Lookup on empty table — no_match
        // ------------------------------------------------------------------
        do_lookup(16'hAAAA, rdata, rm, rnm);
        if (rm || !rnm)
            $fatal(1, "TEST FAILED: empty table should return no_match");
        $display("Test 1 PASSED: no_match on empty table");

        // ------------------------------------------------------------------
        // Test 2: Insert signatures and lookup match
        // ------------------------------------------------------------------
        do_insert(16'hAAAA, 8'h11);
        do_insert(16'hBBBB, 8'h22);
        do_insert(16'hCCCC, 8'h33);
        wait_cycles(1);

        do_lookup(16'hAAAA, rdata, rm, rnm);
        if (!rm || rnm)
            $fatal(1, "TEST FAILED: should match sig 0xAAAA");
        if (rdata !== 8'h11)
            $fatal(1, "TEST FAILED: data for 0xAAAA should be 0x11, got 0x%02h", rdata);

        do_lookup(16'hBBBB, rdata, rm, rnm);
        if (!rm || rdata !== 8'h22)
            $fatal(1, "TEST FAILED: lookup fail for 0xBBBB");

        do_lookup(16'hCCCC, rdata, rm, rnm);
        if (!rm || rdata !== 8'h33)
            $fatal(1, "TEST FAILED: lookup fail for 0xCCCC");
        $display("Test 2 PASSED: insert and lookup match");

        // ------------------------------------------------------------------
        // Test 3: Lookup no_match for absent signature
        // ------------------------------------------------------------------
        do_lookup(16'hDDDD, rdata, rm, rnm);
        if (rm || !rnm)
            $fatal(1, "TEST FAILED: should be no_match for absent sig 0xDDDD");
        $display("Test 3 PASSED: no_match for absent signature");

        // ------------------------------------------------------------------
        // Test 4: match and no_match are mutually exclusive
        // ------------------------------------------------------------------
        do_lookup(16'hAAAA, rdata, rm, rnm);
        if (rm === rnm)
            $fatal(1, "TEST FAILED: match and no_match must be mutually exclusive");
        do_lookup(16'hDDDD, rdata, rm, rnm);
        if (rm === rnm)
            $fatal(1, "TEST FAILED: match and no_match must be mutually exclusive (miss)");
        $display("Test 4 PASSED: match/no_match mutually exclusive");

        // ------------------------------------------------------------------
        // Test 5: clear_entry — subsequent lookup returns no_match
        // ------------------------------------------------------------------
        do_clear(16'hBBBB);
        wait_cycles(1);
        do_lookup(16'hBBBB, rdata, rm, rnm);
        if (rm || !rnm)
            $fatal(1, "TEST FAILED: should be no_match after clear_entry of 0xBBBB");
        // Other entries should still match
        do_lookup(16'hAAAA, rdata, rm, rnm);
        if (!rm)
            $fatal(1, "TEST FAILED: 0xAAAA should still match after clearing 0xBBBB");
        $display("Test 5 PASSED: clear_entry works, others unaffected");

        // ------------------------------------------------------------------
        // Test 6: Fill to full
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_ENTRIES; i++)
            do_insert(16'(i + 1), 8'(i + 0x10));
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d inserts", NUM_ENTRIES);
        $display("Test 6 PASSED: table fills to full");

        $display("ALL TESTS PASSED: signature_match_table_tb");
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
