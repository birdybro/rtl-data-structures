`timescale 1ns/1ps

module bloom_filter_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int KEY_WIDTH   = 8;
    parameter int FILTER_SIZE = 32;
    parameter int NUM_HASH    = 3;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                  clk;
    logic                  rst_n;
    logic                  insert;
    logic                  query;
    logic                  clear;
    logic [KEY_WIDTH-1:0]  key_in;
    logic                  present;
    logic                  not_present;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    bloom_filter #(
        .KEY_WIDTH   (KEY_WIDTH),
        .FILTER_SIZE (FILTER_SIZE),
        .NUM_HASH    (NUM_HASH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .insert      (insert),
        .query       (query),
        .clear       (clear),
        .key_in      (key_in),
        .present     (present),
        .not_present (not_present)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_insert(input logic [KEY_WIDTH-1:0] k);
        @(negedge clk);
        insert = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        insert = 1'b0;
    endtask

    // Query result is registered (1-cycle latency)
    task do_query(input  logic [KEY_WIDTH-1:0] k,
                  output logic                 pres,
                  output logic                 npres);
        @(negedge clk);
        query  = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        query = 1'b0;
        @(posedge clk); #1;
        pres  = present;
        npres = not_present;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic pres, npres;
        // Keys we insert
        logic [KEY_WIDTH-1:0] inserted_keys [0:7];

        // Reset
        rst_n  = 1'b0;
        insert = 1'b0;
        query  = 1'b0;
        clear  = 1'b0;
        key_in = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Query on empty filter — all should be not_present
        // ------------------------------------------------------------------
        do_query(8'hAA, pres, npres);
        if (pres || !npres)
            $fatal(1, "TEST FAILED: empty filter should return not_present");
        $display("Test 1 PASSED: not_present on empty filter");

        // ------------------------------------------------------------------
        // Test 2: Insert keys and query — no false negatives allowed
        //         (inserted keys MUST return present=1)
        // ------------------------------------------------------------------
        inserted_keys[0] = 8'h01;
        inserted_keys[1] = 8'h12;
        inserted_keys[2] = 8'h23;
        inserted_keys[3] = 8'h34;
        inserted_keys[4] = 8'h45;
        inserted_keys[5] = 8'h56;
        inserted_keys[6] = 8'h67;
        inserted_keys[7] = 8'h78;

        for (int i = 0; i < 8; i++)
            do_insert(inserted_keys[i]);
        wait_cycles(2);

        for (int i = 0; i < 8; i++) begin
            do_query(inserted_keys[i], pres, npres);
            if (!pres)
                $fatal(1, "TEST FAILED: false negative for key 0x%02h", inserted_keys[i]);
        end
        $display("Test 2 PASSED: no false negatives for inserted keys");

        // ------------------------------------------------------------------
        // Test 3: present and not_present are mutually exclusive
        // ------------------------------------------------------------------
        for (int i = 0; i < 8; i++) begin
            do_query(inserted_keys[i], pres, npres);
            if (pres === npres)
                $fatal(1, "TEST FAILED: present and not_present must be mutually exclusive for key 0x%02h",
                       inserted_keys[i]);
        end
        $display("Test 3 PASSED: present/not_present mutually exclusive");

        // ------------------------------------------------------------------
        // Test 4: Clear filter — previously inserted keys should return not_present
        // ------------------------------------------------------------------
        @(negedge clk); clear = 1'b1; @(posedge clk); #1; clear = 1'b0;
        wait_cycles(2);

        for (int i = 0; i < 8; i++) begin
            do_query(inserted_keys[i], pres, npres);
            if (!npres)
                $fatal(1, "TEST FAILED: after clear, key 0x%02h should return not_present",
                       inserted_keys[i]);
        end
        $display("Test 4 PASSED: clear removes all entries");

        // ------------------------------------------------------------------
        // Test 5: Re-insert after clear — no false negatives again
        // ------------------------------------------------------------------
        for (int i = 0; i < 4; i++)
            do_insert(inserted_keys[i]);
        wait_cycles(2);
        for (int i = 0; i < 4; i++) begin
            do_query(inserted_keys[i], pres, npres);
            if (!pres)
                $fatal(1, "TEST FAILED: false negative after re-insert for key 0x%02h",
                       inserted_keys[i]);
        end
        $display("Test 5 PASSED: re-insert after clear works");

        $display("ALL TESTS PASSED: bloom_filter_tb");
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
