`timescale 1ns/1ps

module tagged_lookup_table_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int TAG_WIDTH  = 8;
    parameter int DEPTH      = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                      clk;
    logic                      rst_n;
    logic                      write_en;
    logic [TAG_WIDTH-1:0]      tag_in;
    logic [DATA_WIDTH-1:0]     data_in;
    logic                      read_en;
    logic                      invalidate;
    logic [DATA_WIDTH-1:0]     data_out;
    logic                      hit;
    logic                      miss;
    logic                      full;
    logic [$clog2(DEPTH):0]    count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    tagged_lookup_table #(
        .DATA_WIDTH (DATA_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .write_en   (write_en),
        .tag_in     (tag_in),
        .data_in    (data_in),
        .read_en    (read_en),
        .invalidate (invalidate),
        .data_out   (data_out),
        .hit        (hit),
        .miss       (miss),
        .full       (full),
        .count      (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_write(input logic [TAG_WIDTH-1:0]  t,
                  input logic [DATA_WIDTH-1:0] d);
        @(negedge clk);
        write_en = 1'b1;
        tag_in   = t;
        data_in  = d;
        @(posedge clk); #1;
        write_en = 1'b0;
    endtask

    // Read result is registered — sample 1 cycle after rd_en
    task do_read(input  logic [TAG_WIDTH-1:0]  t,
                 output logic [DATA_WIDTH-1:0] d,
                 output logic                  h,
                 output logic                  m);
        @(negedge clk);
        read_en = 1'b1;
        tag_in  = t;
        @(posedge clk); #1;
        read_en = 1'b0;
        // Results are registered — wait one more cycle
        @(posedge clk); #1;
        d = data_out;
        h = hit;
        m = miss;
    endtask

    task do_invalidate(input logic [TAG_WIDTH-1:0] t);
        @(negedge clk);
        invalidate = 1'b1;
        tag_in     = t;
        @(posedge clk); #1;
        invalidate = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rhit, rmiss;

        // Reset
        rst_n      = 1'b0;
        write_en   = 1'b0;
        read_en    = 1'b0;
        invalidate = 1'b0;
        tag_in     = '0;
        data_in    = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Read miss on empty table
        // ------------------------------------------------------------------
        do_read(8'hAA, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be a miss on empty table");
        $display("Test 1 PASSED: miss on empty table");

        // ------------------------------------------------------------------
        // Test 2: Write entries and verify read hit
        // ------------------------------------------------------------------
        do_write(8'hAA, 8'h11);
        do_write(8'hBB, 8'h22);
        do_write(8'hCC, 8'h33);
        wait_cycles(1);

        do_read(8'hAA, rdata, rhit, rmiss);
        if (!rhit || rmiss)
            $fatal(1, "TEST FAILED: should be hit for tag 0xAA");
        if (rdata !== 8'h11)
            $fatal(1, "TEST FAILED: data for 0xAA should be 0x11, got 0x%02h", rdata);

        do_read(8'hBB, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'h22)
            $fatal(1, "TEST FAILED: hit/data mismatch for tag 0xBB");

        do_read(8'hCC, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'h33)
            $fatal(1, "TEST FAILED: hit/data mismatch for tag 0xCC");
        $display("Test 2 PASSED: write and read hit");

        // ------------------------------------------------------------------
        // Test 3: Read miss for non-existent tag
        // ------------------------------------------------------------------
        do_read(8'hDD, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss for tag 0xDD");
        $display("Test 3 PASSED: read miss for absent tag");

        // ------------------------------------------------------------------
        // Test 4: Invalidate an entry, then read — should miss
        // ------------------------------------------------------------------
        do_invalidate(8'hBB);
        wait_cycles(1);
        do_read(8'hBB, rdata, rhit, rmiss);
        if (rhit || !rmiss)
            $fatal(1, "TEST FAILED: should be miss after invalidating 0xBB");
        $display("Test 4 PASSED: invalidated entry returns miss");

        // ------------------------------------------------------------------
        // Test 5: Upsert (overwrite existing tag) — read gets new data
        // ------------------------------------------------------------------
        do_write(8'hAA, 8'hFF);  // update existing
        wait_cycles(1);
        do_read(8'hAA, rdata, rhit, rmiss);
        if (!rhit || rdata !== 8'hFF)
            $fatal(1, "TEST FAILED: upsert failed: expected 0xFF, got 0x%02h", rdata);
        $display("Test 5 PASSED: upsert overwrites existing entry");

        // ------------------------------------------------------------------
        // Test 6: Fill to full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++)
            do_write(8'(i + 1), 8'(i + 0x10));
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d writes", DEPTH);
        $display("Test 6 PASSED: table fills to full");

        $display("ALL TESTS PASSED: tagged_lookup_table_tb");
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
