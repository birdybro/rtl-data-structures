`timescale 1ns/1ps

module circular_buffer_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD = 10;
    parameter int DATA_WIDTH = 8;
    parameter int DEPTH      = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   wr_en;
    logic                   rd_en;
    logic                   overwrite;
    logic [DATA_WIDTH-1:0]  din;
    logic [DATA_WIDTH-1:0]  dout;
    logic                   full;
    logic                   empty;
    logic [$clog2(DEPTH):0] count;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    circular_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (wr_en),
        .rd_en     (rd_en),
        .overwrite (overwrite),
        .din       (din),
        .dout      (dout),
        .full      (full),
        .empty     (empty),
        .count     (count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    task do_write(input logic [DATA_WIDTH-1:0] data, input logic ovwr);
        @(negedge clk);
        wr_en     = 1'b1;
        din       = data;
        overwrite = ovwr;
        @(posedge clk); #1;
        wr_en = 1'b0;
    endtask

    task do_read(output logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk); #1;
        rd_en = 1'b0;
        data  = dout;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [DATA_WIDTH-1:0] rdata;

        // Reset
        rst_n     = 1'b0;
        wr_en     = 1'b0;
        rd_en     = 1'b0;
        overwrite = 1'b0;
        din       = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Empty after reset
        // ------------------------------------------------------------------
        if (!empty || count !== 0)
            $fatal(1, "TEST FAILED: should be empty after reset");
        $display("Test 1 PASSED: empty after reset");

        // ------------------------------------------------------------------
        // Test 2: Normal write/read — FIFO order, no overwrite
        // ------------------------------------------------------------------
        for (int i = 1; i <= 4; i++)
            do_write(8'(i), 1'b0);
        wait_cycles(1);
        if (count !== 4)
            $fatal(1, "TEST FAILED: count should be 4, got %0d", count);
        for (int i = 1; i <= 4; i++) begin
            do_read(rdata);
            if (rdata !== 8'(i))
                $fatal(1, "TEST FAILED: expected %0d got %0d", i, rdata);
        end
        wait_cycles(1);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after reading all");
        $display("Test 2 PASSED: normal write/read FIFO order");

        // ------------------------------------------------------------------
        // Test 3: Fill to full (no overwrite)
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++)
            do_write(8'(i + 1), 1'b0);
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: buffer should be full");
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: count should be %0d, got %0d", DEPTH, count);
        $display("Test 3 PASSED: fill to full");

        // ------------------------------------------------------------------
        // Test 4: Overflow prevention without overwrite flag
        // ------------------------------------------------------------------
        do_write(8'hFF, 1'b0);
        wait_cycles(1);
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overflow without overwrite changed count to %0d", count);
        $display("Test 4 PASSED: overflow prevention without overwrite");

        // Drain
        for (int i = 0; i < DEPTH; i++) do_read(rdata);
        wait_cycles(1);

        // ------------------------------------------------------------------
        // Test 5: Overwrite mode — write when full overwrites oldest entry
        //         Fill with 1..DEPTH, then overwrite with 0xFF, 0xEE
        //         Head should advance (oldest discarded)
        // ------------------------------------------------------------------
        for (int i = 1; i <= DEPTH; i++)
            do_write(8'(i), 1'b0);
        wait_cycles(1);
        if (!full)
            $fatal(1, "TEST FAILED: buffer should be full before overwrite test");

        // Write 2 more entries with overwrite enabled
        do_write(8'hAA, 1'b1);
        do_write(8'hBB, 1'b1);
        wait_cycles(1);
        // Count should stay at DEPTH (circular overwrote oldest)
        if (count !== DEPTH)
            $fatal(1, "TEST FAILED: overwrite mode changed count to %0d", count);
        // The oldest entries (1, 2) were overwritten; head should now be 3
        do_read(rdata);
        if (rdata !== 8'h03)
            $fatal(1, "TEST FAILED: after 2 overwrites head should be 3, got 0x%02h", rdata);
        do_read(rdata);
        if (rdata !== 8'h04)
            $fatal(1, "TEST FAILED: second entry should be 4, got 0x%02h", rdata);
        // Skip to end, last two should be 0xAA and 0xBB
        for (int i = 4; i < DEPTH; i++) do_read(rdata);  // read entries 5..DEPTH
        do_read(rdata);
        if (rdata !== 8'hAA)
            $fatal(1, "TEST FAILED: second-to-last should be 0xAA, got 0x%02h", rdata);
        do_read(rdata);
        if (rdata !== 8'hBB)
            $fatal(1, "TEST FAILED: last should be 0xBB, got 0x%02h", rdata);
        $display("Test 5 PASSED: overwrite mode discards oldest entries");

        // ------------------------------------------------------------------
        // Test 6: Simultaneous read+write keeps count stable
        // ------------------------------------------------------------------
        do_write(8'hDE, 1'b0);
        do_write(8'hAD, 1'b0);
        wait_cycles(1);
        @(negedge clk);
        wr_en = 1'b1; rd_en = 1'b1; din = 8'hBE;
        @(posedge clk); #1;
        wr_en = 1'b0; rd_en = 1'b0;
        wait_cycles(1);
        if (count !== 2)
            $fatal(1, "TEST FAILED: simultaneous rd+wr changed count to %0d", count);
        $display("Test 6 PASSED: simultaneous read+write");

        $display("ALL TESTS PASSED: circular_buffer_tb");
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
