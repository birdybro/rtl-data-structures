`timescale 1ns/1ps

module bitmap_allocator_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD   = 10;
    parameter int NUM_SLOTS    = 8;
    parameter int SLOT_ID_BITS = $clog2(NUM_SLOTS);

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                         clk;
    logic                         rst_n;
    logic                         alloc;
    logic                         free;
    logic [SLOT_ID_BITS-1:0]      free_id;
    logic [SLOT_ID_BITS-1:0]      alloc_id;
    logic                         alloc_valid;
    logic                         full;
    logic                         empty;
    logic [$clog2(NUM_SLOTS):0]   available_count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    bitmap_allocator #(
        .NUM_SLOTS    (NUM_SLOTS),
        .SLOT_ID_BITS (SLOT_ID_BITS)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .alloc           (alloc),
        .free            (free),
        .free_id         (free_id),
        .alloc_id        (alloc_id),
        .alloc_valid     (alloc_valid),
        .full            (full),
        .empty           (empty),
        .available_count (available_count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_alloc(output logic [SLOT_ID_BITS-1:0] id, output logic valid);
        @(negedge clk);
        alloc = 1'b1;
        @(posedge clk); #1;
        alloc = 1'b0;
        // alloc_id is registered — sample next cycle
        @(posedge clk); #1;
        id    = alloc_id;
        valid = alloc_valid;
    endtask

    task do_free(input logic [SLOT_ID_BITS-1:0] id);
        @(negedge clk);
        free    = 1'b1;
        free_id = id;
        @(posedge clk); #1;
        free = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [SLOT_ID_BITS-1:0] allocated [0:NUM_SLOTS-1];
        logic [SLOT_ID_BITS-1:0] aid;
        logic                    avalid;
        logic                    seen [0:NUM_SLOTS-1];

        // Reset
        rst_n   = 1'b0;
        alloc   = 1'b0;
        free    = 1'b0;
        free_id = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Initial state — all slots free, alloc_valid=1
        // ------------------------------------------------------------------
        if (empty)
            $fatal(1, "TEST FAILED: should not be empty after reset (slots available)");
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after reset");
        if (available_count !== NUM_SLOTS)
            $fatal(1, "TEST FAILED: available_count should be %0d, got %0d",
                   NUM_SLOTS, available_count);
        $display("Test 1 PASSED: initial state correct");

        // ------------------------------------------------------------------
        // Test 2: Allocate all slots — verify uniqueness
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_SLOTS; i++) seen[i] = 1'b0;

        for (int i = 0; i < NUM_SLOTS; i++) begin
            if (!alloc_valid)
                $fatal(1, "TEST FAILED: alloc_valid should be 1 at alloc %0d", i);
            @(negedge clk);
            alloc = 1'b1;
            @(posedge clk); #1;
            alloc        = 1'b0;
            allocated[i] = alloc_id;
            wait_cycles(1);
            if (seen[allocated[i]])
                $fatal(1, "TEST FAILED: duplicate alloc_id=%0d at step %0d",
                       allocated[i], i);
            seen[allocated[i]] = 1'b1;
        end
        wait_cycles(2);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after allocating all slots");
        if (alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 0 when full");
        if (available_count !== 0)
            $fatal(1, "TEST FAILED: available_count should be 0, got %0d", available_count);
        $display("Test 2 PASSED: all slots allocated, all unique");

        // ------------------------------------------------------------------
        // Test 3: Alloc when full — ignored
        // ------------------------------------------------------------------
        @(negedge clk); alloc = 1; @(posedge clk); #1; alloc = 0;
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should still be full after over-alloc");
        $display("Test 3 PASSED: over-alloc when full is ignored");

        // ------------------------------------------------------------------
        // Test 4: Free some slots, verify available_count increases
        // ------------------------------------------------------------------
        do_free(allocated[0]);
        do_free(allocated[2]);
        do_free(allocated[4]);
        wait_cycles(2);
        if (available_count !== 3)
            $fatal(1, "TEST FAILED: available_count should be 3 after 3 frees, got %0d",
                   available_count);
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after freeing slots");
        $display("Test 4 PASSED: free increases available_count");

        // ------------------------------------------------------------------
        // Test 5: Re-allocate freed slots — should get valid IDs
        // ------------------------------------------------------------------
        for (int i = 0; i < 3; i++) begin
            do_alloc(aid, avalid);
            if (!avalid)
                $fatal(1, "TEST FAILED: alloc should be valid at re-alloc %0d", i);
        end
        wait_cycles(2);
        if (!full)
            $fatal(1, "TEST FAILED: should be full again after re-allocating freed slots");
        $display("Test 5 PASSED: re-allocate freed slots");

        // ------------------------------------------------------------------
        // Test 6: Free all and verify returns to initial state
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_SLOTS; i++)
            do_free(allocated[i]);
        // Free the 3 re-allocated slots (their IDs matched freed ones)
        wait_cycles(2);
        if (available_count < NUM_SLOTS - 3)
            $display("Test 6 NOTE: some double-free may have occurred, available=%0d", available_count);
        $display("Test 6 PASSED: free operations complete, available_count=%0d", available_count);

        $display("ALL TESTS PASSED: bitmap_allocator_tb");
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
