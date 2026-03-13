`timescale 1ns / 1ps
//==============================================================================
// Module  : async_fifo
// Overview: Dual-clock asynchronous FIFO using Gray-code pointer synchronization.
//           Data is written in the wr_clk domain and read in the rd_clk domain.
//           Each domain maintains its own binary counter; the counter is converted
//           to Gray code before being passed through a 2-stage synchronizer into
//           the opposite clock domain.  Gray code guarantees that only one bit
//           changes per pointer increment, eliminating multi-bit metastability
//           capture errors.
//
//           Full is detected in the write domain by comparing the next write
//           Gray pointer against the synchronized read Gray pointer using the
//           standard Cummings inversion test on the top two bits.
//           Empty is detected in the read domain by comparing the read Gray
//           pointer directly against the synchronized write Gray pointer.
//
//           DEPTH MUST be a power of 2 for the Gray code full/empty detection
//           to work correctly.  A parameter check assertion enforces this.
//
// Parameters:
//   DATA_WIDTH - Width of each data word in bits            (default: 8)
//   DEPTH      - Number of entries; MUST be a power of 2   (default: 16)
//
// Ports:
//   wr_clk   - Write-domain clock (rising-edge triggered)
//   rd_clk   - Read-domain clock  (rising-edge triggered)
//   wr_rst_n - Asynchronous active-low reset for write domain
//   rd_rst_n - Asynchronous active-low reset for read domain
//   wr_en    - Write enable; stores din when asserted and !wr_full
//   rd_en    - Read enable; registers dout when asserted and !rd_empty
//   din      - Data input  [DATA_WIDTH-1:0]
//   dout     - Registered data output [DATA_WIDTH-1:0]
//   wr_full  - Write-domain full flag; writes are dropped when asserted
//   rd_empty - Read-domain empty flag; reads are ignored when asserted
//   wr_count - Approximate number of entries from write domain's perspective
//              [$clog2(DEPTH):0]
//   rd_count - Approximate number of entries from read domain's perspective
//              [$clog2(DEPTH):0]
//
// Timing:
//   Write: din captured in write domain at posedge wr_clk when wr_en && !wr_full.
//   Read : dout updated in read domain at posedge rd_clk when rd_en && !rd_empty.
//   Synchronization latency: 2 rd_clk cycles for wr_ptr to appear in rd domain;
//                            2 wr_clk cycles for rd_ptr to appear in wr domain.
//   wr_count and rd_count are approximate due to synchronization latency.
//
// Insertion / Removal Semantics:
//   - wr_full is conservative (may assert before truly full due to sync delay).
//   - rd_empty is conservative (may stay asserted briefly after data is written).
//   - These conservative behaviours are correct and safe.
//
// Hardware Tradeoffs:
//   - 2-stage synchronizers add 2 cycles of cross-domain latency per pointer.
//   - Gray code restricts DEPTH to powers of 2.
//   - Memory is shared between domains; ensure the synthesis tool infers an
//     asynchronous-read RAM (distributed RAM / register file), not block RAM
//     with registered outputs, to avoid additional cross-domain timing issues.
//   - wr_count / rd_count are computed by converting the synchronized opposite-
//     domain Gray pointer back to binary and subtracting; they may be off by up
//     to one due to in-flight synchronization.
//
// Reference: Clifford E. Cummings, "Simulation and Synthesis Techniques for
//            Asynchronous FIFO Design", SNUG 2002.
//==============================================================================

module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16    // MUST be a power of 2
) (
    input  logic                   wr_clk,
    input  logic                   rd_clk,
    input  logic                   wr_rst_n,
    input  logic                   rd_rst_n,
    input  logic                   wr_en,
    input  logic                   rd_en,
    input  logic [DATA_WIDTH-1:0]  din,
    output logic [DATA_WIDTH-1:0]  dout,
    output logic                   wr_full,
    output logic                   rd_empty,
    output logic [$clog2(DEPTH):0] wr_count,
    output logic [$clog2(DEPTH):0] rd_count
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int PTR_WIDTH  = ADDR_WIDTH + 1;   // extra MSB for full/empty

    // --------------------------------------------------------------------------
    // Parameter check: DEPTH must be a power of 2
    // --------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $error("async_fifo: DEPTH=%0d is not a power of 2. Gray code sync requires power-of-2 depth.", DEPTH);
            $finish;
        end
    end
    // synthesis translate_on

    // --------------------------------------------------------------------------
    // Shared memory — written in wr_clk domain, read in rd_clk domain.
    // Synthesis should infer distributed/asynchronous-read RAM.
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // --------------------------------------------------------------------------
    // Write-domain signals
    // --------------------------------------------------------------------------
    logic [PTR_WIDTH-1:0] wr_ptr_bin;         // binary write pointer
    logic [PTR_WIDTH-1:0] wr_ptr_gray;        // Gray-coded write pointer
    logic [PTR_WIDTH-1:0] wr_ptr_gray_next;   // Gray code of (wr_ptr_bin + 1)

    // Synchronized read pointer (2 FF stages, write domain)
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] rd_ptr_gray_sync1;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] rd_ptr_gray_sync2;

    // --------------------------------------------------------------------------
    // Read-domain signals
    // --------------------------------------------------------------------------
    logic [PTR_WIDTH-1:0] rd_ptr_bin;         // binary read pointer
    logic [PTR_WIDTH-1:0] rd_ptr_gray;        // Gray-coded read pointer

    // Synchronized write pointer (2 FF stages, read domain)
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] wr_ptr_gray_sync1;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] wr_ptr_gray_sync2;

    // --------------------------------------------------------------------------
    // Gray code functions
    // --------------------------------------------------------------------------
    // Binary to Gray: G[n] = B[n] ^ B[n+1]
    function automatic logic [PTR_WIDTH-1:0] bin2gray;
        input logic [PTR_WIDTH-1:0] bin;
        return bin ^ (bin >> 1);
    endfunction

    // Gray to Binary: B[MSB] = G[MSB]; B[i] = B[i+1] ^ G[i]
    function automatic logic [PTR_WIDTH-1:0] gray2bin;
        input logic [PTR_WIDTH-1:0] gray;
        logic [PTR_WIDTH-1:0] bin;
        begin
            bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (int i = PTR_WIDTH-2; i >= 0; i--) begin
                bin[i] = bin[i+1] ^ gray[i];
            end
            return bin;
        end
    endfunction

    // --------------------------------------------------------------------------
    // Write pointer — binary and Gray, registered in write domain
    // --------------------------------------------------------------------------
    assign wr_ptr_gray_next = bin2gray(wr_ptr_bin + 1'b1);

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= '0;
            wr_ptr_gray <= '0;
        end else if (wr_en && !wr_full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
            wr_ptr_bin                      <= wr_ptr_bin  + 1'b1;
            wr_ptr_gray                     <= wr_ptr_gray_next;
        end
    end

    // --------------------------------------------------------------------------
    // Synchronize write Gray pointer into read domain (2-stage)
    // --------------------------------------------------------------------------
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // --------------------------------------------------------------------------
    // Read pointer — binary and Gray, registered in read domain
    // --------------------------------------------------------------------------
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= '0;
            rd_ptr_gray <= '0;
            dout        <= '0;
        end else if (rd_en && !rd_empty) begin
            dout        <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
            rd_ptr_bin  <= rd_ptr_bin  + 1'b1;
            rd_ptr_gray <= bin2gray(rd_ptr_bin + 1'b1);
        end
    end

    // --------------------------------------------------------------------------
    // Synchronize read Gray pointer into write domain (2-stage)
    // --------------------------------------------------------------------------
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= '0;
            rd_ptr_gray_sync2 <= '0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // --------------------------------------------------------------------------
    // Full flag — write domain
    // The FIFO is full when the next write pointer (in Gray code) has its top
    // two bits inverted relative to the synchronized read pointer, while all
    // lower bits match.  This detects exactly DEPTH items in flight.
    // --------------------------------------------------------------------------
    assign wr_full = (wr_ptr_gray_next ==
                      {~rd_ptr_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
                        rd_ptr_gray_sync2[PTR_WIDTH-3:0]});

    // --------------------------------------------------------------------------
    // Empty flag — read domain
    // The FIFO is empty when read and (synchronized) write Gray pointers match.
    // --------------------------------------------------------------------------
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

    // --------------------------------------------------------------------------
    // Approximate counts
    // wr_count: items in the FIFO from the write domain's perspective.
    //           Computed as wr_ptr_bin minus the synchronized rd_ptr (binary).
    // rd_count: items in the FIFO from the read domain's perspective.
    //           Computed as the synchronized wr_ptr (binary) minus rd_ptr_bin.
    // Both use the PTR_WIDTH binary values; the lower ADDR_WIDTH+1 bits give the
    // correct modular difference for count purposes.
    // --------------------------------------------------------------------------
    logic [PTR_WIDTH-1:0] rd_ptr_bin_in_wr;   // rd ptr reconstructed in wr domain
    logic [PTR_WIDTH-1:0] wr_ptr_bin_in_rd;   // wr ptr reconstructed in rd domain

    assign rd_ptr_bin_in_wr = gray2bin(rd_ptr_gray_sync2);
    assign wr_ptr_bin_in_rd = gray2bin(wr_ptr_gray_sync2);

    assign wr_count = PTR_WIDTH'(wr_ptr_bin - rd_ptr_bin_in_wr);
    assign rd_count = PTR_WIDTH'(wr_ptr_bin_in_rd - rd_ptr_bin);

endmodule
