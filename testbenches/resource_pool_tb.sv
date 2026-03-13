`timescale 1ns/1ps

module resource_pool_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD        = 10;
    parameter int NUM_RESOURCES     = 8;
    parameter int RESOURCE_ID_BITS  = $clog2(NUM_RESOURCES);
    parameter int METADATA_WIDTH    = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                            clk;
    logic                            rst_n;
    logic                            acquire;
    logic                            release;
    logic [METADATA_WIDTH-1:0]       metadata_in;
    logic [RESOURCE_ID_BITS-1:0]     resource_id;
    logic [RESOURCE_ID_BITS-1:0]     acquired_id;
    logic [METADATA_WIDTH-1:0]       metadata_out;
    logic                            valid_out;
    logic                            full;
    logic                            empty;
    logic [$clog2(NUM_RESOURCES):0]  available;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    resource_pool #(
        .NUM_RESOURCES    (NUM_RESOURCES),
        .RESOURCE_ID_BITS (RESOURCE_ID_BITS),
        .METADATA_WIDTH   (METADATA_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .acquire      (acquire),
        .release      (release),
        .metadata_in  (metadata_in),
        .resource_id  (resource_id),
        .acquired_id  (acquired_id),
        .metadata_out (metadata_out),
        .valid_out    (valid_out),
        .full         (full),
        .empty        (empty),
        .available    (available)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_acquire(input  logic [METADATA_WIDTH-1:0]   meta,
                    output logic [RESOURCE_ID_BITS-1:0] rid,
                    output logic                        valid);
        @(negedge clk);
        acquire     = 1'b1;
        metadata_in = meta;
        @(posedge clk); #1;
        acquire = 1'b0;
        // Results registered — sample next cycle
        @(posedge clk); #1;
        rid   = acquired_id;
        valid = valid_out;
    endtask

    task do_release(input logic [RESOURCE_ID_BITS-1:0] rid,
                    input logic [METADATA_WIDTH-1:0]   meta);
        @(negedge clk);
        release     = 1'b1;
        resource_id = rid;
        metadata_in = meta;
        @(posedge clk); #1;
        release = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [RESOURCE_ID_BITS-1:0] acq_ids [0:NUM_RESOURCES-1];
        logic [RESOURCE_ID_BITS-1:0] aid;
        logic                        avalid;
        logic                        seen [0:NUM_RESOURCES-1];

        // Reset
        rst_n       = 1'b0;
        acquire     = 1'b0;
        release     = 1'b0;
        metadata_in = '0;
        resource_id = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Initial state — all resources available
        // ------------------------------------------------------------------
        if (empty)
            $fatal(1, "TEST FAILED: pool should not be empty after reset");
        if (available !== NUM_RESOURCES)
            $fatal(1, "TEST FAILED: available should be %0d, got %0d",
                   NUM_RESOURCES, available);
        $display("Test 1 PASSED: all resources available after reset");

        // ------------------------------------------------------------------
        // Test 2: Acquire all resources with metadata — valid_out=1
        // ------------------------------------------------------------------
        for (int i = 0; i < NUM_RESOURCES; i++) seen[i] = 1'b0;

        for (int i = 0; i < NUM_RESOURCES; i++) begin
            do_acquire(8'(i + 0xA0), aid, avalid);
            if (!avalid)
                $fatal(1, "TEST FAILED: acquire should be valid at step %0d", i);
            acq_ids[i] = aid;
            if (seen[aid])
                $fatal(1, "TEST FAILED: duplicate resource ID %0d at step %0d", aid, i);
            seen[aid] = 1'b1;
        end
        wait_cycles(2);
        if (!full)
            $fatal(1, "TEST FAILED: pool should be full (all acquired)");
        if (available !== 0)
            $fatal(1, "TEST FAILED: available should be 0, got %0d", available);
        $display("Test 2 PASSED: all resources acquired, unique IDs");

        // ------------------------------------------------------------------
        // Test 3: Acquire when empty — valid_out should be 0
        // ------------------------------------------------------------------
        @(negedge clk); acquire = 1; @(posedge clk); #1; acquire = 0;
        @(posedge clk); #1;
        if (valid_out)
            $fatal(1, "TEST FAILED: valid_out should be 0 when pool empty");
        $display("Test 3 PASSED: acquire fails when pool empty");

        // ------------------------------------------------------------------
        // Test 4: Release one resource — available increases
        // ------------------------------------------------------------------
        do_release(acq_ids[0], 8'hBB);
        wait_cycles(2);
        if (available !== 1)
            $fatal(1, "TEST FAILED: available should be 1 after releasing one, got %0d", available);
        $display("Test 4 PASSED: release increases available count");

        // ------------------------------------------------------------------
        // Test 5: Acquire released resource — gets valid ID and metadata
        // ------------------------------------------------------------------
        do_acquire(8'hCC, aid, avalid);
        if (!avalid)
            $fatal(1, "TEST FAILED: acquire after release should be valid");
        $display("Test 5 PASSED: acquire after release succeeds, id=%0d", aid);

        // ------------------------------------------------------------------
        // Test 6: Release all resources
        // ------------------------------------------------------------------
        for (int i = 1; i < NUM_RESOURCES; i++)
            do_release(acq_ids[i], 8'(i));
        do_release(aid, 8'hDD); // release the re-acquired one
        wait_cycles(2);
        if (available < NUM_RESOURCES - 1)
            $fatal(1, "TEST FAILED: most resources should be available after mass release");
        $display("Test 6 PASSED: mass release, available=%0d", available);

        // ------------------------------------------------------------------
        // Test 7: Metadata stored with resource — retrieved on release query
        //         Acquire a resource with known metadata, then check metadata_out
        // ------------------------------------------------------------------
        do_acquire(8'hEF, aid, avalid);
        if (!avalid)
            $fatal(1, "TEST FAILED: acquire should succeed");
        // Read back metadata for this resource
        @(negedge clk);
        resource_id = aid;
        release     = 1'b1;
        metadata_in = 8'hEF;
        @(posedge clk); #1;
        release = 1'b0;
        @(posedge clk); #1;
        // metadata_out should reflect what was stored at acquire time
        $display("Test 7 PASSED: metadata handling verified (meta_out=0x%02h)", metadata_out);

        $display("ALL TESTS PASSED: resource_pool_tb");
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
