`timescale 1ns / 1ps
//==============================================================================
// Module  : packet_fifo
// Overview: Synchronous packet-aware FIFO.  Data words are written one word at
//           a time together with sop (start-of-packet) and eop (end-of-packet)
//           sideband signals.  A complete packet only becomes available for
//           reading after its end-of-packet word has been written; partial
//           in-flight packets are hidden from the read side.  This prevents a
//           reader from seeing an incomplete packet in streaming protocols such
//           as Ethernet, PCIe TLP, or AXI4-Stream.
//
//           The FIFO uses a unified data memory that stores words plus their sop
//           and eop flags.  A separate commit pointer marks how far committed
//           (complete) packets extend; the visible read depth is bounded by this
//           pointer so the write-side tentative region is never exposed.
//
// Parameters:
//   DATA_WIDTH      - Width of each data word in bits                (default: 8)
//   DEPTH           - Total word-level storage capacity              (default: 256)
//                     DEPTH need not be a power of 2; explicit pointer wrap
//                     comparison is used throughout.
//   MAX_PACKET_SIZE - Maximum words per packet; used only to size packet_count
//                     (default: 64)
//
// Ports:
//   clk          - Clock input, rising-edge triggered
//   rst_n        - Asynchronous active-low reset
//   wr_en        - Write enable; stores {eop,sop,din} when !full
//   rd_en        - Read enable; advances read pointer when frame_valid && !empty
//   sop          - Start-of-packet flag accompanying din on write
//   eop          - End-of-packet flag accompanying din on write; committing this
//                  word increments packet_count
//   din          - Data input  [DATA_WIDTH-1:0]
//   dout         - Registered data output [DATA_WIDTH-1:0]
//   sop_out      - Registered SOP flag corresponding to the word on dout
//   eop_out      - Registered EOP flag corresponding to the word on dout
//   full         - Asserted when word-level storage is full
//   empty        - Asserted when no committed words remain
//   packet_count - Number of complete packets available for reading
//                  [$clog2(DEPTH/MAX_PACKET_SIZE):0]
//   frame_valid  - Asserted when at least one complete packet is available
//                  (packet_count > 0); rd_en is only honoured when frame_valid
//
// Timing:
//   Write  : din/sop/eop captured at posedge clk when wr_en && !full.
//            On the same edge, if eop is asserted, commit_ptr advances and
//            packet_count increments.
//   Read   : dout/sop_out/eop_out registered at posedge clk when rd_en &&
//            frame_valid; 1-cycle read latency.
//
// Insertion / Removal Semantics:
//   - Writes are silently dropped when full.
//   - rd_en is ignored when frame_valid is deasserted (no complete packet).
//   - When the reader consumes a word whose eop_out is high, packet_count
//     decrements; frame_valid deasserts once packet_count reaches 0.
//   - Partial (uncommitted) packet words occupy memory but are invisible to the
//     reader; they count toward the full condition.
//
// Hardware Tradeoffs:
//   - Commit pointer decouples write-side tentative region from read-side view,
//     adding one pointer register and one adder.
//   - packet_count width is conservatively sized to hold up to
//     DEPTH/MAX_PACKET_SIZE complete packets simultaneously.
//   - DEPTH need not be a power of 2; explicit pointer wrap comparison is used,
//     and the full condition is tracked with a separate count register.
//   - sop_out/eop_out allow the reader to detect packet boundaries in-band.
//==============================================================================

module packet_fifo #(
    parameter int DATA_WIDTH      = 8,
    parameter int DEPTH           = 256,
    parameter int MAX_PACKET_SIZE = 64
) (
    input  logic                                         clk,
    input  logic                                         rst_n,
    input  logic                                         wr_en,
    input  logic                                         rd_en,
    input  logic                                         sop,
    input  logic                                         eop,
    input  logic [DATA_WIDTH-1:0]                        din,
    output logic [DATA_WIDTH-1:0]                        dout,
    output logic                                         sop_out,
    output logic                                         eop_out,
    output logic                                         full,
    output logic                                         empty,
    output logic [$clog2(DEPTH/MAX_PACKET_SIZE):0]       packet_count,
    output logic                                         frame_valid
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_WIDTH   = $clog2(DEPTH);
    localparam int COUNT_WIDTH  = ADDR_WIDTH + 1;
    localparam int PKT_CNT_W    = $clog2(DEPTH / MAX_PACKET_SIZE) + 1;
    localparam logic [ADDR_WIDTH-1:0] PTR_MAX = ADDR_WIDTH'(DEPTH - 1);

    // Memory word: {eop, sop, data}
    localparam int MEM_WIDTH = DATA_WIDTH + 2;

    // --------------------------------------------------------------------------
    // Memory and pointers
    // --------------------------------------------------------------------------
    logic [MEM_WIDTH-1:0]  mem [0:DEPTH-1];

    logic [ADDR_WIDTH-1:0] wr_ptr;       // next write location
    logic [ADDR_WIDTH-1:0] commit_ptr;   // boundary of last committed (full) packet
    logic [ADDR_WIDTH-1:0] rd_ptr;       // next read location

    logic [COUNT_WIDTH-1:0] word_count;  // total words written but not yet read
    logic [PKT_CNT_W-1:0]   pkt_count_r;

    // --------------------------------------------------------------------------
    // Control signals
    // --------------------------------------------------------------------------
    logic do_write;
    logic do_read;
    logic do_commit;    // eop on a valid write — commit this packet

    // --------------------------------------------------------------------------
    // Flag outputs
    // --------------------------------------------------------------------------
    assign full         = (word_count == COUNT_WIDTH'(DEPTH));
    assign empty        = (rd_ptr == commit_ptr);   // no committed words to read
    assign frame_valid  = (pkt_count_r != '0);
    assign packet_count = pkt_count_r;

    assign do_write  = wr_en & ~full;
    assign do_commit = do_write & eop;
    assign do_read   = rd_en & frame_valid & ~empty;

    // EOP flag of the word currently at the read pointer (used to decrement pkt count)
    logic eop_consumed;
    assign eop_consumed = do_read & mem[rd_ptr][MEM_WIDTH-1];

    // --------------------------------------------------------------------------
    // Write path: capture word and advance write pointer
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (do_write) begin
            mem[wr_ptr] <= {eop, sop, din};
            wr_ptr      <= (wr_ptr == PTR_MAX) ? '0 : wr_ptr + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Commit pointer: advances to wr_ptr+1 when a complete packet (eop) is written
    // Equivalently, after the write, commit_ptr = new wr_ptr.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            commit_ptr <= '0;
        end else if (do_commit) begin
            // The committed boundary is the position after the eop word
            commit_ptr <= (wr_ptr == PTR_MAX) ? '0 : wr_ptr + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Read path: registered output; rd_en only honoured when frame_valid
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr  <= '0;
            dout    <= '0;
            sop_out <= 1'b0;
            eop_out <= 1'b0;
        end else if (do_read) begin
            {eop_out, sop_out, dout} <= mem[rd_ptr];
            rd_ptr <= (rd_ptr == PTR_MAX) ? '0 : rd_ptr + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Word occupancy counter (includes uncommitted in-flight words)
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_count <= '0;
        end else begin
            unique case ({do_write, do_read})
                2'b10:   word_count <= word_count + 1'b1;
                2'b01:   word_count <= word_count - 1'b1;
                default: ;
            endcase
        end
    end

    // --------------------------------------------------------------------------
    // Packet counter: increments on eop write, decrements when reader passes eop
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_count_r <= '0;
        end else begin
            unique case ({do_commit, eop_consumed})
                2'b10:   pkt_count_r <= pkt_count_r + 1'b1;
                2'b01:   pkt_count_r <= pkt_count_r - 1'b1;
                default: ;
            endcase
        end
    end

endmodule
