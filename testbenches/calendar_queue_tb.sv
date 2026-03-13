`timescale 1ns/1ps

module calendar_queue_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD   = 10;
    parameter int DATA_WIDTH   = 8;
    parameter int TIME_WIDTH   = 16;
    parameter int NUM_BUCKETS  = 8;
    parameter int BUCKET_WIDTH = 3;  // log2(NUM_BUCKETS)
    parameter int DEPTH        = 32;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   insert;
    logic                   dequeue;
    logic [DATA_WIDTH-1:0]  event_data_in;
    logic [TIME_WIDTH-1:0]  event_time_in;
    logic [TIME_WIDTH-1:0]  current_time;
    logic [DATA_WIDTH-1:0]  event_data_out;
    logic [TIME_WIDTH-1:0]  event_time_out;
    logic                   empty;
    logic                   full;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    calendar_queue #(
        .DATA_WIDTH   (DATA_WIDTH),
        .TIME_WIDTH   (TIME_WIDTH),
        .NUM_BUCKETS  (NUM_BUCKETS),
        .BUCKET_WIDTH (BUCKET_WIDTH),
        .DEPTH        (DEPTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .insert         (insert),
        .dequeue        (dequeue),
        .event_data_in  (event_data_in),
        .event_time_in  (event_time_in),
        .current_time   (current_time),
        .event_data_out (event_data_out),
        .event_time_out (event_time_out),
        .empty          (empty),
        .full           (full)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_insert(input logic [DATA_WIDTH-1:0] data,
                   input logic [TIME_WIDTH-1:0] etime);
        @(negedge clk);
        insert        = 1'b1;
        event_data_in = data;
        event_time_in = etime;
        @(posedge clk); #1;
        insert = 1'b0;
    endtask

    task do_dequeue(output logic [DATA_WIDTH-1:0] data,
                    output logic [TIME_WIDTH-1:0] etime);
        @(negedge clk);
        dequeue = 1'b1;
        @(posedge clk); #1;
        dequeue = 1'b0;
        data    = event_data_out;
        etime   = event_time_out;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic [TIME_WIDTH-1:0] rtime;
        logic [TIME_WIDTH-1:0] last_time;

        // Reset
        rst_n         = 1'b0;
        insert        = 1'b0;
        dequeue       = 1'b0;
        event_data_in = '0;
        event_time_in = '0;
        current_time  = 16'd0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Empty after reset
        // ------------------------------------------------------------------
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after reset");
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Insert events at time 0 — simple dequeue
        // ------------------------------------------------------------------
        current_time = 16'd0;
        do_insert(8'hAA, 16'd0);
        do_insert(8'hBB, 16'd0);
        wait_cycles(1);
        if (empty)
            $fatal(1, "TEST FAILED: should not be empty after insert");

        do_dequeue(rdata, rtime);
        if (rtime !== 16'd0)
            $fatal(1, "TEST FAILED: dequeued event time should be 0, got %0d", rtime);
        do_dequeue(rdata, rtime);
        $display("Test 2 PASSED: insert and dequeue at current_time=0");

        // ------------------------------------------------------------------
        // Test 3: Insert events with various times, dequeue in time order
        //         Advance current_time and verify events come out in order
        // ------------------------------------------------------------------
        current_time = 16'd0;
        do_insert(8'hD4, 16'd4);
        do_insert(8'hD2, 16'd2);
        do_insert(8'hD1, 16'd1);
        do_insert(8'hD3, 16'd3);
        wait_cycles(2);

        // Advance time and dequeue each event in order
        current_time = 16'd1;
        wait_cycles(1);
        do_dequeue(rdata, rtime);
        if (rtime !== 16'd1)
            $fatal(1, "TEST FAILED: expected time=1, got %0d", rtime);
        if (rdata !== 8'hD1)
            $fatal(1, "TEST FAILED: expected data=0xD1 at t=1, got 0x%02h", rdata);

        current_time = 16'd2;
        wait_cycles(1);
        do_dequeue(rdata, rtime);
        if (rtime !== 16'd2)
            $fatal(1, "TEST FAILED: expected time=2, got %0d", rtime);

        current_time = 16'd3;
        wait_cycles(1);
        do_dequeue(rdata, rtime);
        if (rtime !== 16'd3)
            $fatal(1, "TEST FAILED: expected time=3, got %0d", rtime);

        current_time = 16'd4;
        wait_cycles(1);
        do_dequeue(rdata, rtime);
        if (rtime !== 16'd4)
            $fatal(1, "TEST FAILED: expected time=4, got %0d", rtime);

        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after dequeuing all events");
        $display("Test 3 PASSED: events dequeued in time order");

        // ------------------------------------------------------------------
        // Test 4: Insert multiple events in the same bucket, dequeue all
        // ------------------------------------------------------------------
        current_time = 16'd10;
        for (int i = 0; i < 4; i++)
            do_insert(8'(i + 1), 16'd10);
        wait_cycles(2);
        for (int i = 0; i < 4; i++) begin
            if (empty)
                $fatal(1, "TEST FAILED: empty too early at dequeue %0d", i);
            do_dequeue(rdata, rtime);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after draining all");
        $display("Test 4 PASSED: multiple events in same bucket");

        // ------------------------------------------------------------------
        // Test 5: Full detection
        // ------------------------------------------------------------------
        current_time = 16'd100;
        for (int i = 0; i < DEPTH; i++) begin
            if (full)
                $fatal(1, "TEST FAILED: full too early at insert %0d", i);
            do_insert(8'(i), 16'(100 + i));
        end
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d inserts", DEPTH);
        $display("Test 5 PASSED: full detection");

        $display("ALL TESTS PASSED: calendar_queue_tb");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #200000;
        $fatal(1, "TIMEOUT: simulation exceeded limit");
    end

endmodule
