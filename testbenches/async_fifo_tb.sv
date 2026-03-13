`timescale 1ns/1ps

module async_fifo_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int WR_CLK_PERIOD = 10;   // 100 MHz write clock
    parameter int RD_CLK_PERIOD = 13;   // ~77 MHz read clock
    parameter int DATA_WIDTH    = 8;
    parameter int DEPTH         = 16;   // must be power-of-2

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                   wr_clk;
    logic                   rd_clk;
    logic                   wr_rst_n;
    logic                   rd_rst_n;
    logic                   wr_en;
    logic                   rd_en;
    logic [DATA_WIDTH-1:0]  din;
    logic [DATA_WIDTH-1:0]  dout;
    logic                   wr_full;
    logic                   rd_empty;
    logic [$clog2(DEPTH):0] wr_count;
    logic [$clog2(DEPTH):0] rd_count;

    // -------------------------------------------------------------------------
    // Clock generation — two independent clocks
    // -------------------------------------------------------------------------
    initial wr_clk = 0;
    always #(WR_CLK_PERIOD/2) wr_clk = ~wr_clk;

    initial rd_clk = 0;
    always #(RD_CLK_PERIOD/2) rd_clk = ~rd_clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .wr_clk   (wr_clk),
        .rd_clk   (rd_clk),
        .wr_rst_n (wr_rst_n),
        .rd_rst_n (rd_rst_n),
        .wr_en    (wr_en),
        .rd_en    (rd_en),
        .din      (din),
        .dout     (dout),
        .wr_full  (wr_full),
        .rd_empty (rd_empty),
        .wr_count (wr_count),
        .rd_count (rd_count)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wr_wait(input int n);
        repeat (n) @(posedge wr_clk);
    endtask

    task rd_wait(input int n);
        repeat (n) @(posedge rd_clk);
    endtask

    task do_write(input logic [DATA_WIDTH-1:0] data);
        @(negedge wr_clk);
        wr_en = 1'b1;
        din   = data;
        @(posedge wr_clk); #1;
        wr_en = 1'b0;
    endtask

    task do_read(output logic [DATA_WIDTH-1:0] data);
        @(negedge rd_clk);
        rd_en = 1'b1;
        @(posedge rd_clk); #1;
        rd_en = 1'b0;
        data  = dout;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] read_data [0:DEPTH-1];

    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        int                    num_to_write;

        // Assert both resets simultaneously
        wr_rst_n = 1'b0;
        rd_rst_n = 1'b0;
        wr_en    = 1'b0;
        rd_en    = 1'b0;
        din      = '0;

        repeat (8) @(posedge wr_clk);
        repeat (8) @(posedge rd_clk);

        @(negedge wr_clk); wr_rst_n = 1'b1;
        @(negedge rd_clk); rd_rst_n = 1'b1;

        wr_wait(4);
        rd_wait(4);

        // ------------------------------------------------------------------
        // Test 1: Both domains idle after reset
        // ------------------------------------------------------------------
        if (!rd_empty)
            $fatal(1, "TEST FAILED: rd_empty should be 1 after reset");
        if (wr_full)
            $fatal(1, "TEST FAILED: wr_full should be 0 after reset");
        $display("Test 1 PASSED: correct state after reset");

        // ------------------------------------------------------------------
        // Test 2: Write DEPTH/2 words into FIFO from write domain
        // ------------------------------------------------------------------
        num_to_write = DEPTH / 2;
        for (int i = 0; i < num_to_write; i++)
            do_write(8'(i + 1));
        wr_wait(4);
        $display("Test 2 PASSED: wrote %0d words", num_to_write);

        // ------------------------------------------------------------------
        // Test 3: Allow CDC to propagate, then read and verify FIFO order
        // ------------------------------------------------------------------
        // Wait several read-clock cycles for Gray-code synchronizers
        rd_wait(10);
        if (rd_empty)
            $fatal(1, "TEST FAILED: rd_empty should be 0 after writing and waiting");

        for (int i = 0; i < num_to_write; i++) begin
            if (rd_empty)
                $fatal(1, "TEST FAILED: rd_empty too early at read %0d", i);
            do_read(rdata);
            read_data[i] = rdata;
        end
        // Verify order
        for (int i = 0; i < num_to_write; i++) begin
            if (read_data[i] !== 8'(i + 1))
                $fatal(1, "TEST FAILED: FIFO order wrong at %0d: expected %0d got %0d",
                       i, i+1, read_data[i]);
        end
        rd_wait(6);
        if (!rd_empty)
            $fatal(1, "TEST FAILED: rd_empty should be 1 after draining");
        $display("Test 3 PASSED: FIFO order correct across clock domains");

        // ------------------------------------------------------------------
        // Test 4: Fill the FIFO to full
        // ------------------------------------------------------------------
        for (int i = 0; i < DEPTH; i++)
            do_write(8'(i + 0x10));
        wr_wait(6);
        if (!wr_full)
            $fatal(1, "TEST FAILED: wr_full should be 1 after writing DEPTH words");
        $display("Test 4 PASSED: wr_full asserted when full");

        // ------------------------------------------------------------------
        // Test 5: Overflow prevention while full
        // ------------------------------------------------------------------
        do_write(8'hFF); // should be ignored
        wr_wait(2);
        if (wr_count !== DEPTH)
            $fatal(1, "TEST FAILED: wr_count should be %0d, got %0d", DEPTH, wr_count);
        $display("Test 5 PASSED: overflow prevention");

        // ------------------------------------------------------------------
        // Test 6: Drain the full FIFO from read domain
        // ------------------------------------------------------------------
        rd_wait(10); // wait for CDC
        for (int i = 0; i < DEPTH; i++) begin
            if (rd_empty)
                $fatal(1, "TEST FAILED: rd_empty too early during drain at %0d", i);
            do_read(rdata);
            read_data[i] = rdata;
        end
        // Verify order
        for (int i = 0; i < DEPTH; i++) begin
            if (read_data[i] !== 8'(i + 0x10))
                $fatal(1, "TEST FAILED: drain order wrong at %0d: expected 0x%02h got 0x%02h",
                       i, i+0x10, read_data[i]);
        end
        rd_wait(6);
        if (!rd_empty)
            $fatal(1, "TEST FAILED: should be empty after draining DEPTH entries");
        $display("Test 6 PASSED: drained full FIFO correctly");

        // ------------------------------------------------------------------
        // Test 7: Concurrent writes and reads with different clock rates
        // ------------------------------------------------------------------
        // Start writing and reading simultaneously
        fork
            begin : writer
                for (int i = 0; i < 8; i++) begin
                    @(negedge wr_clk);
                    wr_en = 1'b1;
                    din   = 8'(i + 0xA0);
                    @(posedge wr_clk); #1;
                    wr_en = 1'b0;
                    wr_wait(1); // pace the writer
                end
            end
            begin : reader
                rd_wait(5); // small head start for writes
                for (int i = 0; i < 8; i++) begin
                    // Wait until data is available
                    while (rd_empty) @(posedge rd_clk);
                    do_read(rdata);
                    if (rdata !== 8'(i + 0xA0))
                        $fatal(1, "TEST FAILED: concurrent order wrong: expected 0x%02h got 0x%02h",
                               i+0xA0, rdata);
                    rd_wait(2);
                end
            end
        join
        $display("Test 7 PASSED: concurrent cross-domain operation");

        $display("ALL TESTS PASSED: async_fifo_tb");
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
