`timescale 1ns/1ps

module history_buffer_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int DEPTH      = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                       clk;
    logic                       rst_n;
    logic                       write_en;
    logic                       read_en;
    logic                       rewind;
    logic [DATA_WIDTH-1:0]      data_in;
    logic [$clog2(DEPTH)-1:0]   offset;
    logic [DATA_WIDTH-1:0]      data_out;
    logic                       valid_out;
    logic                       full;
    logic [$clog2(DEPTH):0]     count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    history_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .write_en  (write_en),
        .read_en   (read_en),
        .rewind    (rewind),
        .data_in   (data_in),
        .offset    (offset),
        .data_out  (data_out),
        .valid_out (valid_out),
        .full      (full),
        .count     (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_write(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        write_en = 1'b1;
        data_in  = data;
        @(posedge clk); #1;
        write_en = 1'b0;
    endtask

    // Read is combinational (offset-based, non-destructive)
    task do_read(input  logic [$clog2(DEPTH)-1:0] off,
                 output logic [DATA_WIDTH-1:0]    data,
                 output logic                     vld);
        @(negedge clk);
        read_en = 1'b1;
        offset  = off;
        @(posedge clk); #1;
        read_en = 1'b0;
        data    = data_out;
        vld     = valid_out;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rvld;

        // Reset
        rst_n    = 1'b0;
        write_en = 1'b0;
        read_en  = 1'b0;
        rewind   = 1'b0;
        data_in  = '0;
        offset   = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Empty after reset — valid_out=0, count=0
        // ------------------------------------------------------------------
        do_read(0, rdata, rvld);
        if (rvld)
            $fatal(1, "TEST FAILED: valid_out should be 0 on empty buffer");
        if (count !== 0)
            $fatal(1, "TEST FAILED: count should be 0 after reset");
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Write entries and read at offset 0 (most recent)
        // ------------------------------------------------------------------
        do_write(8'hAA);
        wait_cycles(1);
        do_read(0, rdata, rvld);
        if (!rvld)
            $fatal(1, "TEST FAILED: valid_out should be 1 after write");
        if (rdata !== 8'hAA)
            $fatal(1, "TEST FAILED: offset=0 should return most recent 0xAA, got 0x%02h", rdata);
        if (count !== 1)
            $fatal(1, "TEST FAILED: count should be 1, got %0d", count);
        $display("Test 2 PASSED: offset=0 reads most recent entry");

        // ------------------------------------------------------------------
        // Test 3: Write more entries, verify offset reads
        //         After writing [AA, BB, CC, DD], offset 0=DD, 1=CC, 2=BB, 3=AA
        // ------------------------------------------------------------------
        do_write(8'hBB);
        do_write(8'hCC);
        do_write(8'hDD);
        wait_cycles(1);

        do_read(0, rdata, rvld);
        if (!rvld || rdata !== 8'hDD)
            $fatal(1, "TEST FAILED: offset=0 should be 0xDD (newest), got 0x%02h", rdata);

        do_read(1, rdata, rvld);
        if (!rvld || rdata !== 8'hCC)
            $fatal(1, "TEST FAILED: offset=1 should be 0xCC, got 0x%02h", rdata);

        do_read(2, rdata, rvld);
        if (!rvld || rdata !== 8'hBB)
            $fatal(1, "TEST FAILED: offset=2 should be 0xBB, got 0x%02h", rdata);

        do_read(3, rdata, rvld);
        if (!rvld || rdata !== 8'hAA)
            $fatal(1, "TEST FAILED: offset=3 should be 0xAA (oldest), got 0x%02h", rdata);
        $display("Test 3 PASSED: offset reads return correct history entries");

        // ------------------------------------------------------------------
        // Test 4: Read non-destructive — reading does not change count
        // ------------------------------------------------------------------
        do_read(0, rdata, rvld);
        do_read(1, rdata, rvld);
        do_read(2, rdata, rvld);
        wait_cycles(1);
        if (count !== 4)
            $fatal(1, "TEST FAILED: reads should not change count, got %0d", count);
        $display("Test 4 PASSED: reads are non-destructive");

        // ------------------------------------------------------------------
        // Test 5: Fill buffer to DEPTH — full flag asserted
        // ------------------------------------------------------------------
        for (int i = 4; i < DEPTH; i++)
            do_write(8'(i + 0x10));
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: should be full after %0d writes", DEPTH);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", DEPTH, count);
        $display("Test 5 PASSED: buffer fills to full");

        // ------------------------------------------------------------------
        // Test 6: Write when full overwrites oldest — newest is still correct
        // ------------------------------------------------------------------
        do_write(8'hE0);
        wait_cycles(1);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overwrite should keep count at DEPTH=%0d", DEPTH);
        do_read(0, rdata, rvld);
        if (!rvld || rdata !== 8'hE0)
            $fatal(1, "TEST FAILED: newest entry should be 0xE0, got 0x%02h", rdata);
        $display("Test 6 PASSED: overwrite when full advances head");

        // ------------------------------------------------------------------
        // Test 7: Offset beyond count returns valid_out=0
        // ------------------------------------------------------------------
        // Clear buffer and write just 2 entries
        @(negedge clk); rewind = 1'b1; @(posedge clk); #1; rewind = 1'b0;
        wait_cycles(2);
        do_write(8'h11);
        do_write(8'h22);
        wait_cycles(1);
        do_read(5, rdata, rvld);  // offset 5 but only 2 entries
        if (rvld)
            $fatal(1, "TEST FAILED: valid_out should be 0 for offset beyond count");
        $display("Test 7 PASSED: out-of-range offset returns valid_out=0");

        $display("ALL TESTS PASSED: history_buffer_tb");
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
