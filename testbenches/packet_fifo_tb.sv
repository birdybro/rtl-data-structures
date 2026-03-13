`timescale 1ns/1ps

module packet_fifo_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int CLK_PERIOD      = 10;
    parameter int DATA_WIDTH      = 8;
    parameter int DEPTH           = 64;
    parameter int MAX_PACKET_SIZE = 8;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic                                    clk;
    logic                                    rst_n;
    logic                                    wr_en;
    logic                                    rd_en;
    logic                                    sop;
    logic                                    eop;
    logic [DATA_WIDTH-1:0]                   din;
    logic [DATA_WIDTH-1:0]                   dout;
    logic                                    sop_out;
    logic                                    eop_out;
    logic                                    full;
    logic                                    empty;
    logic [$clog2(DEPTH/MAX_PACKET_SIZE):0]  packet_count;
    logic                                    frame_valid;

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    packet_fifo #(
        .DATA_WIDTH      (DATA_WIDTH),
        .DEPTH           (DEPTH),
        .MAX_PACKET_SIZE (MAX_PACKET_SIZE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (wr_en),
        .rd_en        (rd_en),
        .sop          (sop),
        .eop          (eop),
        .din          (din),
        .dout         (dout),
        .sop_out      (sop_out),
        .eop_out      (eop_out),
        .full         (full),
        .empty        (empty),
        .packet_count (packet_count),
        .frame_valid  (frame_valid)
    );

    // -------------------------------------------------------------------------
    // Tasks / helper functions
    // -------------------------------------------------------------------------
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // Write a single word with given sop/eop flags
    task write_word(
        input logic [DATA_WIDTH-1:0] data,
        input logic s, e
    );
        @(negedge clk);
        wr_en = 1'b1;
        din   = data;
        sop   = s;
        eop   = e;
        @(posedge clk); #1;
        wr_en = 1'b0;
        sop   = 1'b0;
        eop   = 1'b0;
    endtask

    // Write a multi-word packet
    task write_packet(
        input logic [DATA_WIDTH-1:0] pkt [],
        input int                    len
    );
        for (int i = 0; i < len; i++) begin
            write_word(pkt[i],
                       i == 0,          // sop
                       i == (len - 1)); // eop
        end
    endtask

    task read_word(output logic [DATA_WIDTH-1:0] data);
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
        logic [DATA_WIDTH-1:0] pkt1[];
        logic [DATA_WIDTH-1:0] pkt2[];

        // Reset
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        sop   = 1'b0;
        eop   = 1'b0;
        din   = '0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait_cycles(2);

        // ------------------------------------------------------------------
        // Test 1: Reset state — frame_valid and empty
        // ------------------------------------------------------------------
        if (frame_valid)
            $fatal(1, "TEST FAILED: frame_valid should be 0 after reset");
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after reset");
        if (packet_count !== 0)
            $fatal(1, "TEST FAILED: packet_count should be 0 after reset");
        $display("Test 1 PASSED: reset state correct");

        // ------------------------------------------------------------------
        // Test 2: Partial packet (sop without eop) — frame_valid must stay 0
        // ------------------------------------------------------------------
        write_word(8'hA1, 1'b1, 1'b0); // sop only
        write_word(8'hA2, 1'b0, 1'b0); // middle byte
        wait_cycles(2);
        if (frame_valid)
            $fatal(1, "TEST FAILED: frame_valid should stay 0 for incomplete packet");
        if (packet_count !== 0)
            $fatal(1, "TEST FAILED: packet_count should stay 0 for incomplete packet");
        $display("Test 2 PASSED: partial packet does not raise frame_valid");

        // ------------------------------------------------------------------
        // Test 3: Complete packet (add eop) — frame_valid goes high
        // ------------------------------------------------------------------
        write_word(8'hA3, 1'b0, 1'b1); // eop
        wait_cycles(2);
        if (!frame_valid)
            $fatal(1, "TEST FAILED: frame_valid should be 1 after complete packet");
        if (packet_count < 1)
            $fatal(1, "TEST FAILED: packet_count should be >= 1 after complete packet");
        $display("Test 3 PASSED: complete packet raises frame_valid");

        // ------------------------------------------------------------------
        // Test 4: Read the complete packet, verify sop_out/eop_out
        // ------------------------------------------------------------------
        read_word(rdata);
        if (rdata !== 8'hA1)
            $fatal(1, "TEST FAILED: first byte should be 0xA1, got 0x%02h", rdata);
        if (!sop_out)
            $fatal(1, "TEST FAILED: sop_out should be 1 at first byte");
        read_word(rdata);
        if (rdata !== 8'hA2)
            $fatal(1, "TEST FAILED: second byte should be 0xA2, got 0x%02h", rdata);
        read_word(rdata);
        if (rdata !== 8'hA3)
            $fatal(1, "TEST FAILED: third byte should be 0xA3, got 0x%02h", rdata);
        if (!eop_out)
            $fatal(1, "TEST FAILED: eop_out should be 1 at last byte");
        wait_cycles(2);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after reading packet");
        $display("Test 4 PASSED: packet read with correct sop_out/eop_out");

        // ------------------------------------------------------------------
        // Test 5: Two packets back-to-back; frame_valid stays high until all drained
        // ------------------------------------------------------------------
        // Packet A: 3 bytes
        write_word(8'hB1, 1'b1, 1'b0);
        write_word(8'hB2, 1'b0, 1'b0);
        write_word(8'hB3, 1'b0, 1'b1);
        // Packet B: 2 bytes (single-word sop+eop)
        write_word(8'hC1, 1'b1, 1'b0);
        write_word(8'hC2, 1'b0, 1'b1);
        wait_cycles(2);
        if (!frame_valid)
            $fatal(1, "TEST FAILED: frame_valid should be 1 with two complete packets");
        if (packet_count < 2)
            $fatal(1, "TEST FAILED: packet_count should be >= 2, got %0d", packet_count);
        // Drain both packets
        for (int i = 0; i < 5; i++) read_word(rdata);
        wait_cycles(2);
        if (!empty)
            $fatal(1, "TEST FAILED: should be empty after draining 2 packets");
        $display("Test 5 PASSED: two back-to-back packets");

        // ------------------------------------------------------------------
        // Test 6: Single-word packet (sop and eop simultaneously)
        // ------------------------------------------------------------------
        write_word(8'hDD, 1'b1, 1'b1);
        wait_cycles(2);
        if (!frame_valid)
            $fatal(1, "TEST FAILED: frame_valid should be 1 for single-word packet");
        read_word(rdata);
        if (rdata !== 8'hDD)
            $fatal(1, "TEST FAILED: single-word packet data should be 0xDD, got 0x%02h", rdata);
        if (!sop_out || !eop_out)
            $fatal(1, "TEST FAILED: sop_out and eop_out should both be 1 for single-word packet");
        $display("Test 6 PASSED: single-word packet (sop+eop)");

        $display("ALL TESTS PASSED: packet_fifo_tb");
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
