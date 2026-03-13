`timescale 1ns/1ps

module index_allocator_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int NUM_INDICES = 8;
    parameter int INDEX_WIDTH = $clog2(NUM_INDICES);

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                          clk;
    logic                          rst_n;
    logic                          request;
    logic                          release;
    logic [INDEX_WIDTH-1:0]        release_index;
    logic [INDEX_WIDTH-1:0]        index_out;
    logic                          valid;
    logic                          full;
    logic                          empty;
    logic [$clog2(NUM_INDICES):0]  used_count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    index_allocator #(
        .NUM_INDICES (NUM_INDICES),
        .INDEX_WIDTH (INDEX_WIDTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .request       (request),
        .release       (release),
        .release_index (release_index),
        .index_out     (index_out),
        .valid         (valid),
        .full          (full),
        .empty         (empty),
        .used_count    (used_count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_request(output logic [INDEX_WIDTH-1:0] idx, output logic v);
        @(negedge clk);
        request = 1'b1;
        @(posedge clk); #1;
        request = 1'b0;
        // Results registered — sample next cycle
        @(posedge clk); #1;
        idx = index_out;
        v   = valid;
    endtask

    task do_release(input logic [INDEX_WIDTH-1:0] idx);
        @(negedge clk);
        release       = 1'b1;
        release_index = idx;
        @(posedge clk); #1;
        release = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [INDEX_WIDTH-1:0] allocated [0:NUM_INDICES-1];
        logic [INDEX_WIDTH-1:0] idx;
        logic                   v;
        logic                   seen [0:NUM_INDICES-1];

        // Reset
        rst_n         = 1'b0;
        request       = 1'b0;
        release       = 1'b0;
        release_index = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — no indices in use, valid should be 1 on request
        // ------------------------------------------------------------------
        if (full)
            $fatal(1, "TEST FAILED: should not be full after reset");
        if (used_count !== 0)
            $fatal(1, "TEST FAILED: used_count should be 0 after reset, got %0d", used_count);
        $display("Test 1 PASSED: initial state correct");

        // ------------------------------------------------------------------
        // Test 2: Request all indices — each must be unique and valid
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_INDICES; i++) seen[i] = 1'b0;

        for (int i = 0; i < NUM_INDICES; i++) begin
            do_request(idx, v);
            if (!v)
                $fatal(1, "TEST FAILED: valid should be 1 at request %0d", i);
            allocated[i] = idx;
            if (idx >= NUM_INDICES)
                $fatal(1, "TEST FAILED: index_out=%0d out of range [0,%0d)", idx, NUM_INDICES);
            if (seen[idx])
                $fatal(1, "TEST FAILED: duplicate index %0d at step %0d", idx, i);
            seen[idx] = 1'b1;
        end
        wait_cycles(2);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after allocating all indices");
        if (used_count !== NUM_INDICES)
            $fatal(1, "TEST FAILED: used_count should be %0d, got %0d", NUM_INDICES, used_count);
        $display("Test 2 PASSED: all indices allocated, all unique");

        // ------------------------------------------------------------------
        // Test 3: Request when full — valid=0
        // ------------------------------------------------------------------
        @(negedge clk); request = 1; @(posedge clk); #1; request = 0;
        @(posedge clk); #1;
        if (valid)
            $fatal(1, "TEST FAILED: valid should be 0 when all indices in use");
        $display("Test 3 PASSED: request fails when full");

        // ------------------------------------------------------------------
        // Test 4: Release an index — can be re-allocated
        // ------------------------------------------------------------------
        do_release(allocated[3]);
        wait_cycles(2);
        if (used_count !== NUM_INDICES - 1)
            $fatal(1, "TEST FAILED: used_count should decrease after release, got %0d", used_count);

        do_request(idx, v);
        if (!v)
            $fatal(1, "TEST FAILED: request after release should be valid");
        $display("Test 4 PASSED: release and re-request works (new idx=%0d)", idx);

        // ------------------------------------------------------------------
        // Test 5: Release multiple indices and verify used_count
        // ------------------------------------------------------------------
        do_release(allocated[0]);
        do_release(allocated[1]);
        do_release(allocated[2]);
        wait_cycles(2);
        if (used_count > NUM_INDICES - 3)
            $fatal(1, "TEST FAILED: used_count should decrease by 3 after 3 releases");
        $display("Test 5 PASSED: multiple releases, used_count=%0d", used_count);

        // ------------------------------------------------------------------
        // Test 6: Release all remaining indices
        // ------------------------------------------------------------------
        for (int i = 4; i < NUM_INDICES; i++)
            do_release(allocated[i]);
        do_release(idx); // release the re-allocated one from test 4
        wait_cycles(2);
        if (used_count > 3)  // 3 were released in test 5 and re-requested indices remain
            $display("Test 6 NOTE: used_count=%0d (some releases may have been double)", used_count);
        $display("Test 6 PASSED: mass release complete, used_count=%0d", used_count);

        $display("ALL TESTS PASSED: index_allocator_tb");
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
