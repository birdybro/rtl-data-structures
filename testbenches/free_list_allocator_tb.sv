`timescale 1ns/1ps

module free_list_allocator_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD    = 10;
    parameter int NUM_RESOURCES = 8;
    parameter int ID_WIDTH      = $clog2(NUM_RESOURCES);  // = 3

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                            clk;
    logic                            rst_n;
    logic                            alloc;
    logic                            free;
    logic [ID_WIDTH-1:0]             free_id;
    logic [ID_WIDTH-1:0]             alloc_id;
    logic                            alloc_valid;
    logic                            empty;
    logic                            full;
    logic [$clog2(NUM_RESOURCES):0]  count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    free_list_allocator #(
        .NUM_RESOURCES (NUM_RESOURCES)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .alloc       (alloc),
        .free        (free),
        .free_id     (free_id),
        .alloc_id    (alloc_id),
        .alloc_valid (alloc_valid),
        .empty       (empty),
        .full        (full),
        .count       (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_alloc(output logic [ID_WIDTH-1:0] id, output logic valid);
        @(negedge clk);
        alloc = 1'b1;
        @(posedge clk); #1;
        alloc = 1'b0;
        // alloc_id is registered — sample after one more edge
        @(posedge clk); #1;
        id    = alloc_id;
        valid = alloc_valid;
    endtask

    task do_free(input logic [ID_WIDTH-1:0] id);
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
        logic [ID_WIDTH-1:0] allocated [0:NUM_RESOURCES-1];
        logic [ID_WIDTH-1:0] aid;
        logic                avalid;
        logic                seen [0:NUM_RESOURCES-1];

        // Reset
        rst_n   = 1'b0;
        alloc   = 1'b0;
        free    = 1'b0;
        free_id = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: After reset — free list full, alloc_valid=1
        // ------------------------------------------------------------------
        if (!full)
            $fatal(1, "TEST FAILED: free list should be full after reset (all IDs available)");
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after reset");
        if (empty)
            $fatal(1, "TEST FAILED: should not be empty after reset");
        $display("Test 1 PASSED: initial state correct after reset");

        // ------------------------------------------------------------------
        // Test 2: Allocate all resources — IDs must be unique
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_RESOURCES; i++) seen[i] = 1'b0;

        for (int i = 0; i < NUM_RESOURCES; i++) begin
            if (!alloc_valid)
                $fatal(1, "TEST FAILED: alloc_valid should be 1 at alloc %0d", i);
            @(negedge clk);
            alloc = 1'b1;
            @(posedge clk); #1;
            alloc        = 1'b0;
            allocated[i] = alloc_id;
            wait_cycles(1);
            if (seen[allocated[i]])
                $fatal(1, "TEST FAILED: duplicate alloc_id %0d at step %0d",
                       allocated[i], i);
            seen[allocated[i]] = 1'b1;
        end
        wait_cycles(2);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty (all allocated)");
        if (alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 0 when all allocated");
        $display("Test 2 PASSED: all %0d IDs allocated, all unique", NUM_RESOURCES);

        // ------------------------------------------------------------------
        // Test 3: Alloc when empty — should be ignored
        // ------------------------------------------------------------------
        @(negedge clk); alloc = 1; @(posedge clk); #1; alloc = 0;
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: empty should still be set after over-alloc");
        $display("Test 3 PASSED: over-alloc ignored when empty");

        // ------------------------------------------------------------------
        // Test 4: Free one ID, then re-allocate
        // ------------------------------------------------------------------
        do_free(allocated[0]);
        wait_cycles(1);
        if (empty)
            $fatal(1, "TEST FAILED: should not be empty after freeing one ID");
        if (!alloc_valid)
            $fatal(1, "TEST FAILED: alloc_valid should be 1 after free");

        @(negedge clk); alloc = 1; @(posedge clk); #1; alloc = 0;
        wait_cycles(2);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty again after re-alloc");
        $display("Test 4 PASSED: free and re-allocate");

        // ------------------------------------------------------------------
        // Test 5: Free all and verify count returns to NUM_RESOURCES
        // ------------------------------------------------------------------
        for (int i = 1; i < NUM_RESOURCES; i++)
            do_free(allocated[i]);
        // Also free the one allocated in test 4 (it was allocated[0])
        do_free(allocated[0]);
        wait_cycles(2);
        if (count !== NUM_RESOURCES)
            $fatal(1, "TEST FAILED: count should be %0d after freeing all, got %0d",
                   NUM_RESOURCES, count);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after freeing all");
        $display("Test 5 PASSED: all IDs freed, count=%0d", count);

        $display("ALL TESTS PASSED: free_list_allocator_tb");
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
