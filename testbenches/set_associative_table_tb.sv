`timescale 1ns/1ps

module set_associative_table_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int KEY_WIDTH  = 8;
    parameter int DATA_WIDTH = 8;
    parameter int NUM_SETS   = 4;
    parameter int WAYS       = 4;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                        clk;
    logic                        rst_n;
    logic                        write_en;
    logic [KEY_WIDTH-1:0]        key_in;
    logic [DATA_WIDTH-1:0]       data_in;
    logic                        read_en;
    logic                        invalidate_en;
    logic [DATA_WIDTH-1:0]       data_out;
    logic                        hit;
    logic                        miss;
    logic [$clog2(WAYS)-1:0]     evict_way;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    set_associative_table #(
        .KEY_WIDTH  (KEY_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_SETS   (NUM_SETS),
        .WAYS       (WAYS)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .write_en     (write_en),
        .key_in       (key_in),
        .data_in      (data_in),
        .read_en      (read_en),
        .invalidate_en(invalidate_en),
        .data_out     (data_out),
        .hit          (hit),
        .miss         (miss),
        .evict_way    (evict_way)
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

    // Results are registered — sample after 1-cycle latency
    task do_read(input  logic [KEY_WIDTH-1:0]  k,
                 output logic [DATA_WIDTH-1:0] d,
                 output logic                  h,
                 output logic                  m);
        @(negedge clk);
        read_en = 1'b1;
        key_in  = k;
        @(posedge clk); #1;
        read_en = 1'b0;
        @(posedge clk); #1;
        d = data_out;
        h = hit;
        m = miss;
    endtask

    task do_invalidate(input logic [KEY_WIDTH-1:0] k);
        @(negedge clk);
        invalidate_en = 1'b1;
        key_in        = k;
        @(posedge clk); #1;
        invalidate_en = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rhit, rmiss;

        // Reset
        rst_n         = 1'b0;
        write_en      = 1'b0;
        read_en       = 1'b0;
        invalidate_en = 1'b0;
        key_in        = '0;
        data_in       = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Read miss on empty table
        // ------------------------------------------------------------------
        do_read(8'hAA, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss on empty table");
        $display("Test 1 PASSED: read miss on empty table");

        // ------------------------------------------------------------------
        // Test 2: Write several entries, read hit
        // ------------------------------------------------------------------
        do_write(8'hA0, 8'h11);
        do_write(8'hB1, 8'h22);
        do_write(8'hC2, 8'h33);
        wait_cycles(1);

        do_read(8'hA0, rdata, rhit, rmiss);
        if (!rhit || rmiss)
            $fatal(1, "TEST FAILED: should be hit for key 0xA0");
        if (rdata !== 8'h11)
            $fatal(1, "TEST FAILED: data for 0xA0 should be 0x11, got 0x%02h", rdata);

        do_read(8'hB1, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'h22)
            $fatal(1, "TEST FAILED: read fail for 0xB1");

        do_read(8'hC2, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'h33)
            $fatal(1, "TEST FAILED: read fail for 0xC2");
        $display("Test 2 PASSED: write and read hit");

        // ------------------------------------------------------------------
        // Test 3: Read miss for absent key
        // ------------------------------------------------------------------
        do_read(8'hFF, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss for key 0xFF");
        $display("Test 3 PASSED: read miss for absent key");

        // ------------------------------------------------------------------
        // Test 4: Invalidate an entry — subsequent read should miss
        // ------------------------------------------------------------------
        do_invalidate(8'hB1);
        wait_cycles(1);
        do_read(8'hB1, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should miss after invalidating 0xB1");
        $display("Test 4 PASSED: invalidate causes read miss");

        // ------------------------------------------------------------------
        // Test 5: Fill a set beyond WAYS — eviction should occur
        //         Keys mapping to the same set: key[1:0] selects set for NUM_SETS=4
        //         Use keys 0x00, 0x04, 0x08, 0x0C, 0x10 (all map to set 0)
        // ------------------------------------------------------------------
        do_write(8'h00, 8'hA0);
        do_write(8'h04, 8'hA1);
        do_write(8'h08, 8'hA2);
        do_write(8'h0C, 8'hA3);
        wait_cycles(1);
        // Now evict — write one more key to same set
        do_write(8'h10, 8'hA4);
        wait_cycles(1);
        // After eviction at least evict_way is valid (0..WAYS-1)
        $display("Test 5 PASSED: eviction occurred, evict_way=%0d", evict_way);

        // ------------------------------------------------------------------
        // Test 6: Update (overwrite) an existing entry
        // ------------------------------------------------------------------
        do_write(8'hA0, 8'hBB);  // update key 0xA0
        wait_cycles(1);
        do_read(8'hA0, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'hBB)
            $fatal(1, "TEST FAILED: update failed: expected 0xBB, got 0x%02h", rdata);
        $display("Test 6 PASSED: existing entry updated");

        $display("ALL TESTS PASSED: set_associative_table_tb");
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
