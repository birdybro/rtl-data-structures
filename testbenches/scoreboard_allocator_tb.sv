`timescale 1ns/1ps

module scoreboard_allocator_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int NUM_ENTRIES = 8;
    parameter int TAG_WIDTH   = 3;   // ceil(log2(NUM_ENTRIES))

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                  clk;
    logic                  rst_n;
    logic                  alloc;
    logic                  free;
    logic [TAG_WIDTH-1:0]  alloc_tag;
    logic [TAG_WIDTH-1:0]  free_tag;
    logic                  alloc_valid;
    logic                  full;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    scoreboard_allocator #(
        .NUM_ENTRIES (NUM_ENTRIES),
        .TAG_WIDTH   (TAG_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .alloc       (alloc),
        .free        (free),
        .alloc_tag   (alloc_tag),
        .free_tag    (free_tag),
        .alloc_valid (alloc_valid),
        .full        (full)
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
        logic [TAG_WIDTH-1:0] tags [0:NUM_ENTRIES-1];
        logic [TAG_WIDTH-1:0] captured_tag;
        logic                 seen [0:NUM_ENTRIES-1];

        // Reset
        rst_n    = 1'b0;
        alloc    = 1'b0;
        free     = 1'b0;
        free_tag = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — alloc_valid should be 1, not full
        // ------------------------------------------------------------------
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after reset");
        if (full)
            $fatal(1, "TEST FAILED: should not be full after reset");
        $display("Test 1 PASSED: initial state correct");

        // ------------------------------------------------------------------
        // Test 2: Allocate all entries — verify each tag is unique
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_ENTRIES; i++) seen[i] = 1'b0;

        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (!alloc_valid)
                $fatal(1, "TEST FAILED: alloc_valid should be 1 at alloc %0d", i);
            captured_tag = alloc_tag; // combinational output
            @(negedge clk);
            alloc = 1'b1;
            @(posedge clk); #1;
            alloc     = 1'b0;
            tags[i]   = captured_tag;
            if (seen[captured_tag])
                $fatal(1, "TEST FAILED: duplicate tag %0d allocated at step %0d",
                       captured_tag, i);
            seen[captured_tag] = 1'b1;
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after allocating all entries");
        if (alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 0 when full");
        $display("Test 2 PASSED: all tags unique, full after all allocations");

        // ------------------------------------------------------------------
        // Test 3: Allocate when full — must be ignored (full stays asserted)
        // ------------------------------------------------------------------
        @(negedge clk); alloc = 1; @(posedge clk); #1; alloc = 0;
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: overflow alloc cleared full flag");
        $display("Test 3 PASSED: overflow alloc ignored");

        // ------------------------------------------------------------------
        // Test 4: Free one tag, then re-allocate — should get back a valid tag
        // ------------------------------------------------------------------
        @(negedge clk);
        free     = 1'b1;
        free_tag = tags[0];
        @(posedge clk); #1;
        free = 1'b0;
        wait_cycles(1);
        if (full)
            $fatal(1, "TEST FAILED: should not be full after freeing one entry");
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after free");

        // Re-allocate
        captured_tag = alloc_tag;
        @(negedge clk); alloc = 1; @(posedge clk); #1; alloc = 0;
        wait_cycles(1);
        // The re-allocated tag must have been the freed one
        if (captured_tag !== tags[0])
            $fatal(1, "TEST FAILED: re-alloc tag should be %0d (the freed one), got %0d",
                   tags[0], captured_tag);
        $display("Test 4 PASSED: free and re-allocate works correctly");

        // ------------------------------------------------------------------
        // Test 5: Free all remaining, verify returns to initial state
        // ------------------------------------------------------------------
        // Free all except the one we just re-allocated (which is tags[0])
        for (int i = 1; i < NUM_ENTRIES; i++) begin
            @(negedge clk);
            free     = 1'b1;
            free_tag = tags[i];
            @(posedge clk); #1;
            free = 1'b0;
        end
        // Free the re-allocated one
        @(negedge clk);
        free     = 1'b1;
        free_tag = captured_tag;
        @(posedge clk); #1;
        free = 1'b0;
        wait_cycles(1);
        if (full)
            $fatal(1, "TEST FAILED: should not be full after freeing all");
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after freeing all");
        $display("Test 5 PASSED: all freed, back to initial state");

        $display("ALL TESTS PASSED: scoreboard_allocator_tb");
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
