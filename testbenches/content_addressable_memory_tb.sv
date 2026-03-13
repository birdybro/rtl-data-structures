`timescale 1ns/1ps

module content_addressable_memory_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int KEY_WIDTH  = 8;
    parameter int DEPTH      = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                         clk;
    logic                         rst_n;
    logic                         write_en;
    logic [KEY_WIDTH-1:0]         key_in;
    logic [DATA_WIDTH-1:0]        data_in;
    logic                         lookup_en;
    logic [DATA_WIDTH-1:0]        match_data;
    logic [$clog2(DEPTH)-1:0]     match_index;
    logic                         match_found;
    logic                         match_multiple;
    logic                         flush;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    content_addressable_memory #(
        .DATA_WIDTH (DATA_WIDTH),
        .KEY_WIDTH  (KEY_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .write_en       (write_en),
        .key_in         (key_in),
        .data_in        (data_in),
        .lookup_en      (lookup_en),
        .match_data     (match_data),
        .match_index    (match_index),
        .match_found    (match_found),
        .match_multiple (match_multiple),
        .flush          (flush)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_write(input logic [KEY_WIDTH-1:0]  k,
                  input logic [DATA_WIDTH-1:0] d);
        @(negedge clk);
        write_en = 1'b1;
        key_in   = k;
        data_in  = d;
        @(posedge clk); #1;
        write_en = 1'b0;
    endtask

    task do_lookup(input  logic [KEY_WIDTH-1:0]  k,
                   output logic [DATA_WIDTH-1:0] d,
                   output logic                  found,
                   output logic                  multi);
        @(negedge clk);
        lookup_en = 1'b1;
        key_in    = k;
        @(posedge clk); #1;
        lookup_en = 1'b0;
        d     = match_data;
        found = match_found;
        multi = match_multiple;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rfound, rmulti;

        // Reset
        rst_n     = 1'b0;
        write_en  = 1'b0;
        lookup_en = 1'b0;
        flush     = 1'b0;
        key_in    = '0;
        data_in   = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Lookup on empty CAM — no match
        // ------------------------------------------------------------------
        do_lookup(8'hAA, rdata, rfound, rmulti);
        wait_cycles(1);
        if (match_found)
            $fatal(1, "TEST FAILED: match_found should be 0 on empty CAM");
        $display("Test 1 PASSED: no match on empty CAM");

        // ------------------------------------------------------------------
        // Test 2: Write entries and lookup with correct key
        // ------------------------------------------------------------------
        do_write(8'hAA, 8'h11);
        do_write(8'hBB, 8'h22);
        do_write(8'hCC, 8'h33);
        wait_cycles(1);

        do_lookup(8'hAA, rdata, rfound, rmulti);
        wait_cycles(1);
        if (!match_found)
            $fatal(1, "TEST FAILED: match_found should be 1 for key 0xAA");
        if (match_data !== 8'h11)
            $fatal(1, "TEST FAILED: match_data should be 0x11, got 0x%02h", match_data);
        if (match_multiple)
            $fatal(1, "TEST FAILED: match_multiple should be 0 for unique key 0xAA");

        do_lookup(8'hBB, rdata, rfound, rmulti);
        wait_cycles(1);
        if (!match_found || match_data !== 8'h22)
            $fatal(1, "TEST FAILED: lookup for 0xBB failed");

        do_lookup(8'hCC, rdata, rfound, rmulti);
        wait_cycles(1);
        if (!match_found || match_data !== 8'h33)
            $fatal(1, "TEST FAILED: lookup for 0xCC failed");
        $display("Test 2 PASSED: write and lookup correct");

        // ------------------------------------------------------------------
        // Test 3: Lookup with non-existent key — no match
        // ------------------------------------------------------------------
        do_lookup(8'hDD, rdata, rfound, rmulti);
        wait_cycles(1);
        if (match_found)
            $fatal(1, "TEST FAILED: match_found should be 0 for missing key 0xDD");
        $display("Test 3 PASSED: no match for non-existent key");

        // ------------------------------------------------------------------
        // Test 4: Flush — all entries cleared, lookups return no match
        // ------------------------------------------------------------------
        @(negedge clk); flush = 1'b1; @(posedge clk); #1; flush = 1'b0;
        wait_cycles(2);

        do_lookup(8'hAA, rdata, rfound, rmulti);
        wait_cycles(1);
        if (match_found)
            $fatal(1, "TEST FAILED: match_found should be 0 after flush");
        do_lookup(8'hBB, rdata, rfound, rmulti);
        wait_cycles(1);
        if (match_found)
            $fatal(1, "TEST FAILED: 0xBB should not be found after flush");
        $display("Test 4 PASSED: flush clears all entries");

        // ------------------------------------------------------------------
        // Test 5: Fill all DEPTH slots
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++)
            do_write(8'(i + 1), 8'(i + 0x10));
        wait_cycles(2);
        // Verify a few random lookups
        do_lookup(8'h01, rdata, rfound, rmulti);
        wait_cycles(1);
        if (!match_found)
            $fatal(1, "TEST FAILED: key 0x01 should be found after filling");
        if (match_data !== 8'h10)
            $fatal(1, "TEST FAILED: data for key 0x01 should be 0x10, got 0x%02h", match_data);
        $display("Test 5 PASSED: fill all DEPTH=%0d slots", DEPTH);

        $display("ALL TESTS PASSED: content_addressable_memory_tb");
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
