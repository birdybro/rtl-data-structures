`timescale 1ns/1ps

module round_robin_scheduler_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD  = 10;
    parameter int NUM_CLIENTS = 4;
    parameter int ID_WIDTH    = $clog2(NUM_CLIENTS);

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                    clk;
    logic                    rst_n;
    logic [NUM_CLIENTS-1:0]  request;
    logic [NUM_CLIENTS-1:0]  grant;
    logic                    grant_valid;
    logic [ID_WIDTH-1:0]     grant_id;
    logic                    advance;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    round_robin_scheduler #(
        .NUM_CLIENTS (NUM_CLIENTS),
        .ID_WIDTH    (ID_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (request),
        .grant       (grant),
        .grant_valid (grant_valid),
        .grant_id    (grant_id),
        .advance     (advance)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_advance;
        @(negedge clk);
        advance = 1'b1;
        @(posedge clk); #1;
        advance = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        int grant_order [0:NUM_CLIENTS*2-1];
        int g;

        // Reset
        rst_n   = 1'b0;
        request = '0;
        advance = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: No requests — grant_valid should be 0
        // ------------------------------------------------------------------
        request = 4'b0000;
        wait_cycles(2);
        if (grant_valid)
            $fatal(1, "TEST FAILED: grant_valid should be 0 with no requests");
        $display("Test 1 PASSED: no grant when no requests");

        // ------------------------------------------------------------------
        // Test 2: Single client requests — always gets grant
        // ------------------------------------------------------------------
        request = 4'b0001;  // only client 0
        wait_cycles(2);
        if (!grant_valid)
            $fatal(1, "TEST FAILED: grant_valid should be 1 with one request");
        if (grant_id !== 0)
            $fatal(1, "TEST FAILED: grant_id should be 0, got %0d", grant_id);
        do_advance;
        wait_cycles(1);
        if (grant_id !== 0)
            $fatal(1, "TEST FAILED: single client should keep getting grant");
        $display("Test 2 PASSED: single client always granted");

        // ------------------------------------------------------------------
        // Test 3: All clients request — verify round-robin rotation
        //         Each client should get exactly one grant per cycle
        // ------------------------------------------------------------------
        request = 4'b1111;  // all clients request
        wait_cycles(2);

        // Record NUM_CLIENTS*2 grants to verify rotation
        for (int i = 0; i < NUM_CLIENTS * 2; i++) begin
            if (!grant_valid)
                $fatal(1, "TEST FAILED: grant_valid should be 1 at step %0d", i);
            grant_order[i] = grant_id;
            do_advance;
            wait_cycles(1);
        end

        // Check each client gets a turn (at least once in first NUM_CLIENTS grants)
        begin
            logic seen [0:NUM_CLIENTS-1];
            for (int i = 0; i < NUM_CLIENTS; i++) seen[i] = 1'b0;
            for (int i = 0; i < NUM_CLIENTS; i++) seen[grant_order[i]] = 1'b1;
            for (int i = 0; i < NUM_CLIENTS; i++) begin
                if (!seen[i])
                    $fatal(1, "TEST FAILED: client %0d never got a grant in first round", i);
            end
        end

        // Verify second round matches first round (fairness)
        for (int i = 0; i < NUM_CLIENTS; i++) begin
            if (grant_order[i] !== grant_order[i + NUM_CLIENTS])
                $fatal(1, "TEST FAILED: round-robin not periodic at step %0d", i);
        end
        $display("Test 3 PASSED: round-robin rotation verified");

        // ------------------------------------------------------------------
        // Test 4: Selective requests — only some clients, verify skip
        //         Clients 1 and 3 request, 0 and 2 do not
        // ------------------------------------------------------------------
        request = 4'b1010;  // clients 1 and 3
        wait_cycles(2);
        for (int i = 0; i < 4; i++) begin
            if (!grant_valid)
                $fatal(1, "TEST FAILED: grant_valid should be 1 at step %0d", i);
            g = grant_id;
            if (g !== 1 && g !== 3)
                $fatal(1, "TEST FAILED: non-requesting client %0d got grant", g);
            do_advance;
            wait_cycles(1);
        end
        $display("Test 4 PASSED: only requesting clients get grants");

        // ------------------------------------------------------------------
        // Test 5: Grant held until advance
        // ------------------------------------------------------------------
        request = 4'b1111;
        wait_cycles(3);
        begin
            int first_grant;
            first_grant = grant_id;
            wait_cycles(3); // no advance
            if (grant_id !== first_grant)
                $fatal(1, "TEST FAILED: grant changed without advance signal");
        end
        $display("Test 5 PASSED: grant held stable without advance");

        $display("ALL TESTS PASSED: round_robin_scheduler_tb");
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
