`timescale 1ns/1ps

module hash_table_fixed_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD       = 10;
    parameter int KEY_WIDTH        = 8;
    parameter int DATA_WIDTH       = 8;
    parameter int NUM_BUCKETS      = 8;
    parameter int SLOTS_PER_BUCKET = 4;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   insert;
    logic                   lookup;
    logic                   remove;
    logic [KEY_WIDTH-1:0]   key_in;
    logic [DATA_WIDTH-1:0]  data_in;
    logic [DATA_WIDTH-1:0]  data_out;
    logic                   hit;
    logic                   miss;
    logic                   full;
    logic                   collision;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    hash_table_fixed #(
        .KEY_WIDTH        (KEY_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .NUM_BUCKETS      (NUM_BUCKETS),
        .SLOTS_PER_BUCKET (SLOTS_PER_BUCKET)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .insert    (insert),
        .lookup    (lookup),
        .remove    (remove),
        .key_in    (key_in),
        .data_in   (data_in),
        .data_out  (data_out),
        .hit       (hit),
        .miss      (miss),
        .full      (full),
        .collision (collision)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_insert(input logic [KEY_WIDTH-1:0]  k,
                   input logic [DATA_WIDTH-1:0] d);
        @(negedge clk);
        insert  = 1'b1;
        key_in  = k;
        data_in = d;
        @(posedge clk); #1;
        insert = 1'b0;
    endtask

    // Lookup result is registered (1-cycle latency)
    task do_lookup(input  logic [KEY_WIDTH-1:0]  k,
                   output logic [DATA_WIDTH-1:0] d,
                   output logic                  h,
                   output logic                  m);
        @(negedge clk);
        lookup = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        lookup = 1'b0;
        @(posedge clk); #1;
        d = data_out;
        h = hit;
        m = miss;
    endtask

    task do_remove(input logic [KEY_WIDTH-1:0] k);
        @(negedge clk);
        remove = 1'b1;
        key_in = k;
        @(posedge clk); #1;
        remove = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rhit, rmiss;

        // Reset
        rst_n   = 1'b0;
        insert  = 1'b0;
        lookup  = 1'b0;
        remove  = 1'b0;
        key_in  = '0;
        data_in = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Lookup miss on empty table
        // ------------------------------------------------------------------
        do_lookup(8'hAA, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss on empty table");
        $display("Test 1 PASSED: lookup miss on empty table");

        // ------------------------------------------------------------------
        // Test 2: Insert and lookup hit
        // ------------------------------------------------------------------
        do_insert(8'hAA, 8'h11);
        do_insert(8'hBB, 8'h22);
        do_insert(8'hCC, 8'h33);
        wait_cycles(1);

        do_lookup(8'hAA, rdata, rhit, rmiss);
        if (!rhit || rmiss)
            $fatal(1, "TEST FAILED: should be hit for key 0xAA");
        if (rdata !== 8'h11)
            $fatal(1, "TEST FAILED: data for 0xAA should be 0x11, got 0x%02h", rdata);

        do_lookup(8'hBB, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'h22)
            $fatal(1, "TEST FAILED: lookup fail for 0xBB");

        do_lookup(8'hCC, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'h33)
            $fatal(1, "TEST FAILED: lookup fail for 0xCC");
        $display("Test 2 PASSED: insert and lookup hit");

        // ------------------------------------------------------------------
        // Test 3: Lookup miss for non-inserted key
        // ------------------------------------------------------------------
        do_lookup(8'hDD, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss for key 0xDD");
        $display("Test 3 PASSED: lookup miss for absent key");

        // ------------------------------------------------------------------
        // Test 4: Remove key and verify miss afterwards
        // ------------------------------------------------------------------
        do_remove(8'hBB);
        wait_cycles(1);
        do_lookup(8'hBB, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss after removing 0xBB");
        $display("Test 4 PASSED: remove then lookup miss");

        // ------------------------------------------------------------------
        // Test 5: Re-insert removed key with new data
        // ------------------------------------------------------------------
        do_insert(8'hBB, 8'hBB);
        wait_cycles(1);
        do_lookup(8'hBB, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'hBB)
            $fatal(1, "TEST FAILED: re-insert and lookup fail for 0xBB");
        $display("Test 5 PASSED: re-insert after remove");

        // ------------------------------------------------------------------
        // Test 6: Collision detection — insert keys that hash to same bucket
        //         Keys 0x00 and 0x08 hash to the same bucket (XOR-fold with
        //         NUM_BUCKETS=8 → bucket = key[2:0] XOR key[5:3])
        //         Fill one bucket to get collision
        // ------------------------------------------------------------------
        // Insert SLOTS_PER_BUCKET keys that share the same bucket (key % NUM_BUCKETS == 0)
        for (int i = 0; i < SLOTS_PER_BUCKET; i++)
            do_insert(8'(i * NUM_BUCKETS), 8'(i));
        wait_cycles(2);
        // One more to the same bucket — should trigger collision
        do_insert(8'(SLOTS_PER_BUCKET * NUM_BUCKETS), 8'hFF);
        wait_cycles(1);
        if (!collision)
            $fatal(1, "TEST FAILED: collision should be flagged on bucket overflow");
        $display("Test 6 PASSED: collision detected on bucket overflow");

        $display("ALL TESTS PASSED: hash_table_fixed_tb");
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
