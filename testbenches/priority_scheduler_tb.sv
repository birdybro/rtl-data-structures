`timescale 1ns/1ps

module priority_scheduler_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD      = 10;
    parameter int NUM_CLIENTS     = 4;
    parameter int PRIORITY_LEVELS = 4;
    parameter int ID_WIDTH        = $clog2(NUM_CLIENTS);
    parameter int PRIO_BITS       = $clog2(PRIORITY_LEVELS);

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                                    clk;
    logic                                    rst_n;
    logic [NUM_CLIENTS-1:0]                  request;
    logic [NUM_CLIENTS*PRIO_BITS-1:0]        priority_in;
    logic [NUM_CLIENTS-1:0]                  grant;
    logic [ID_WIDTH-1:0]                     grant_id;
    logic                                    grant_valid;
    logic                                    advance;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    priority_scheduler #(
        .NUM_CLIENTS     (NUM_CLIENTS),
        .PRIORITY_LEVELS (PRIORITY_LEVELS),
        .ID_WIDTH        (ID_WIDTH),
        .PRIO_BITS       (PRIO_BITS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (request),
        .priority_in (priority_in),
        .grant       (grant),
        .grant_id    (grant_id),
        .grant_valid (grant_valid),
        .advance     (advance)
    );

    // Helper: pack per-client priorities into flat vector
    // priority_in[i*PRIO_BITS +: PRIO_BITS] = priority of client i
    function automatic logic [NUM_CLIENTS*PRIO_BITS-1:0] pack_prio(
        input logic [PRIO_BITS-1:0] p0, p1, p2, p3);
        pack_prio = {p3, p2, p1, p0};
    endfunction

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
        // Reset
        rst_n       = 1'b0;
        request     = '0;
        priority_in = '0;
        advance     = 1'b0;
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
        // Test 2: All clients request with different priorities
        //         Higher numeric priority = higher importance (lower number wins)
        //         Client 2 has priority 0 (highest), others have priority 3
        // ------------------------------------------------------------------
        request     = 4'b1111;
        // client 0=prio3, client 1=prio3, client 2=prio0 (highest), client 3=prio3
        priority_in = pack_prio(2'b11, 2'b11, 2'b00, 2'b11);
        wait_cycles(2);
        if (!grant_valid)
            $fatal(1, "TEST FAILED: grant_valid should be 1");
        if (grant_id !== 2)
            $fatal(1, "TEST FAILED: client 2 (highest priority) should win, got %0d", grant_id);
        $display("Test 2 PASSED: highest priority client wins");

        // ------------------------------------------------------------------
        // Test 3: After client 2 is served, next highest priority gets grant
        //         Client 1 has priority 1, clients 0,3 have priority 3
        // ------------------------------------------------------------------
        do_advance;
        priority_in = pack_prio(2'b11, 2'b01, 2'b10, 2'b11);
        // client 0=prio3, client 1=prio1, client 2=prio2, client 3=prio3
        wait_cycles(2);
        if (!grant_valid)
            $fatal(1, "TEST FAILED: grant_valid should be 1");
        if (grant_id !== 1)
            $fatal(1, "TEST FAILED: client 1 (priority 1) should win, got %0d", grant_id);
        $display("Test 3 PASSED: second highest priority served next");

        // ------------------------------------------------------------------
        // Test 4: Equal priority — round-robin within same priority level
        //         All clients with same priority, all requesting
        // ------------------------------------------------------------------
        priority_in = pack_prio(2'b01, 2'b01, 2'b01, 2'b01);
        request     = 4'b1111;
        do_advance;
        wait_cycles(2);
        begin
            logic seen [0:NUM_CLIENTS-1];
            for (int i = 0; i < NUM_CLIENTS; i++) seen[i] = 1'b0;
            for (int i = 0; i < NUM_CLIENTS; i++) begin
                if (!grant_valid)
                    $fatal(1, "TEST FAILED: grant_valid should be 1 at step %0d", i);
                seen[grant_id] = 1'b1;
                do_advance;
                wait_cycles(1);
            end
            for (int i = 0; i < NUM_CLIENTS; i++) begin
                if (!seen[i])
                    $fatal(1, "TEST FAILED: client %0d never got grant in equal-priority round", i);
            end
        end
        $display("Test 4 PASSED: round-robin within same priority level");

        // ------------------------------------------------------------------
        // Test 5: Requesting client with lower priority does not preempt higher
        // ------------------------------------------------------------------
        request     = 4'b1001;  // clients 0 and 3 request
        priority_in = pack_prio(2'b00, 2'b11, 2'b11, 2'b11);
        // client 0 has priority 0 (highest)
        wait_cycles(2);
        if (grant_id !== 0)
            $fatal(1, "TEST FAILED: client 0 (prio 0) should win over client 3 (prio 3), got %0d",
                   grant_id);
        $display("Test 5 PASSED: lower priority client does not preempt");

        $display("ALL TESTS PASSED: priority_scheduler_tb");
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
