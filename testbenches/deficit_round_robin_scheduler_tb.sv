`timescale 1ns/1ps

module deficit_round_robin_scheduler_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD   = 10;
    parameter int NUM_CLIENTS  = 4;
    parameter int QUANTUM_BITS = 8;
    parameter int ID_WIDTH     = $clog2(NUM_CLIENTS);

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                                    clk;
    logic                                    rst_n;
    logic [NUM_CLIENTS-1:0]                  request;
    logic [NUM_CLIENTS*QUANTUM_BITS-1:0]     quantum;
    logic [QUANTUM_BITS-1:0]                 packet_size;
    logic                                    grant;
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
    deficit_round_robin_scheduler #(
        .NUM_CLIENTS  (NUM_CLIENTS),
        .QUANTUM_BITS (QUANTUM_BITS),
        .ID_WIDTH     (ID_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .request     (request),
        .quantum     (quantum),
        .packet_size (packet_size),
        .grant       (grant),
        .grant_id    (grant_id),
        .grant_valid (grant_valid),
        .advance     (advance)
    );

    // Helper: pack per-client quantum values
    function automatic logic [NUM_CLIENTS*QUANTUM_BITS-1:0] pack_quantum(
        input logic [QUANTUM_BITS-1:0] q0, q1, q2, q3);
        pack_quantum = {q3, q2, q1, q0};
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
        quantum     = '0;
        packet_size = 8'd1;
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
        // Test 2: Single client with large quantum — gets repeated grants
        // ------------------------------------------------------------------
        request     = 4'b0001;  // only client 0
        quantum     = pack_quantum(8'd4, 8'd4, 8'd4, 8'd4);
        packet_size = 8'd1;
        wait_cycles(2);
        for (int i = 0; i < 4; i++) begin
            if (!grant_valid)
                $fatal(1, "TEST FAILED: grant_valid should be 1 at step %0d", i);
            if (grant_id !== 0)
                $fatal(1, "TEST FAILED: client 0 should get grant, got %0d", grant_id);
            do_advance;
            wait_cycles(1);
        end
        $display("Test 2 PASSED: single client gets repeated grants");

        // ------------------------------------------------------------------
        // Test 3: All clients with equal quanta and packet size — round-robin
        // ------------------------------------------------------------------
        request     = 4'b1111;
        quantum     = pack_quantum(8'd4, 8'd4, 8'd4, 8'd4);
        packet_size = 8'd4;  // packet_size equals quantum → one grant per round
        wait_cycles(2);
        begin
            logic seen [0:NUM_CLIENTS-1];
            for (int i = 0; i < NUM_CLIENTS; i++) seen[i] = 1'b0;
            for (int i = 0; i < NUM_CLIENTS * 2; i++) begin
                if (!grant_valid)
                    $fatal(1, "TEST FAILED: grant_valid should be 1 at step %0d", i);
                seen[grant_id] = 1'b1;
                do_advance;
                wait_cycles(1);
            end
            for (int i = 0; i < NUM_CLIENTS; i++) begin
                if (!seen[i])
                    $fatal(1, "TEST FAILED: client %0d never got a grant", i);
            end
        end
        $display("Test 3 PASSED: equal-quantum DRR distributes fairly");

        // ------------------------------------------------------------------
        // Test 4: Different quanta — larger quantum client gets more grants
        //         client 0: quantum=2, client 1: quantum=4
        //         With packet_size=1: client 1 should get ~2x grants as client 0
        // ------------------------------------------------------------------
        request     = 4'b0011;  // clients 0 and 1
        quantum     = pack_quantum(8'd4, 8'd2, 8'd0, 8'd0);
        // client 0 = quantum 2, client 1 = quantum 4
        packet_size = 8'd1;
        wait_cycles(2);
        begin
            int cnt [0:NUM_CLIENTS-1];
            for (int i = 0; i < NUM_CLIENTS; i++) cnt[i] = 0;
            // Run for enough cycles to observe proportionality
            for (int i = 0; i < 12; i++) begin
                if (grant_valid) cnt[grant_id]++;
                do_advance;
                wait_cycles(1);
            end
            $display("Test 4: grant counts — client0=%0d, client1=%0d (expected ~1:2 ratio)",
                     cnt[0], cnt[1]);
            if (cnt[1] <= cnt[0])
                $fatal(1, "TEST FAILED: client 1 (larger quantum) should get more grants");
        end
        $display("Test 4 PASSED: larger quantum client receives more grants");

        // ------------------------------------------------------------------
        // Test 5: Client that just became active still gets fair start
        //         (deficit counter from previous round persists)
        // ------------------------------------------------------------------
        request = 4'b0000;
        wait_cycles(2);
        request = 4'b0001;  // client 0 re-activates
        wait_cycles(2);
        if (!grant_valid)
            $fatal(1, "TEST FAILED: re-activated client should get grant");
        $display("Test 5 PASSED: re-activated client gets grant");

        $display("ALL TESTS PASSED: deficit_round_robin_scheduler_tb");
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
