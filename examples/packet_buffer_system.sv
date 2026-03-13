// =============================================================================
// packet_buffer_system.sv  –  Example: Packet Buffering with Allocator
// =============================================================================
// Shows a system where incoming packet bytes are stored in a packet_fifo.
// A free_list_allocator assigns buffer IDs to packets as they arrive.
// When a complete packet is received (eop asserted), a buffer ID is allocated
// and stored alongside the packet metadata.
//
// When a packet is consumed from the output (rd_en + eop_out), the buffer ID
// is freed back to the allocator.
//
// Instantiates: packet_fifo, free_list_allocator
//
// Interface:
//   clk, rst_n
//   -- Ingress --
//   rx_data[7:0]   – incoming byte
//   rx_valid       – rx_data is valid this cycle
//   rx_sop         – first byte of new packet
//   rx_eop         – last byte of current packet
//   -- Egress --
//   tx_ready       – downstream is ready to consume a byte
//   tx_data[7:0]   – outgoing byte
//   tx_valid       – tx_data is valid
//   tx_sop         – first byte of packet on tx side
//   tx_eop         – last byte of packet on tx side
//   tx_buf_id[2:0] – buffer ID associated with current egress packet
//   -- Status --
//   buf_full       – no free buffer IDs remain
//   buf_empty      – all buffer IDs are free (no packets in flight)
//   fifo_full      – packet FIFO is full
//   packets_ready  – at least one complete packet is buffered
// =============================================================================

`timescale 1ns/1ps

`include "../rtl/queues/packet_fifo.sv"
`include "../rtl/associative/free_list_allocator.sv"

module packet_buffer_system #(
    parameter int DATA_WIDTH       = 8,
    parameter int FIFO_DEPTH       = 256,
    parameter int MAX_PACKET_SIZE  = 64,
    parameter int NUM_BUFFERS      = 8,
    parameter int BUF_ID_WIDTH     = 3    // log2(NUM_BUFFERS)
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Ingress (write side)
    input  logic [DATA_WIDTH-1:0]   rx_data,
    input  logic                    rx_valid,
    input  logic                    rx_sop,
    input  logic                    rx_eop,

    // Egress (read side)
    input  logic                    tx_ready,
    output logic [DATA_WIDTH-1:0]   tx_data,
    output logic                    tx_valid,
    output logic                    tx_sop,
    output logic                    tx_eop,
    output logic [BUF_ID_WIDTH-1:0] tx_buf_id,

    // Status
    output logic                    buf_full,
    output logic                    buf_empty,
    output logic                    fifo_full,
    output logic                    packets_ready
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic                    fifo_empty;
    logic                    fifo_wr_en;
    logic                    fifo_rd_en;
    logic                    eop_out_w;
    logic                    sop_out_w;
    logic [DATA_WIDTH-1:0]   fifo_dout;
    logic [$clog2(FIFO_DEPTH/MAX_PACKET_SIZE):0] pkt_count;

    logic                    alloc_valid;
    logic [BUF_ID_WIDTH-1:0] alloc_id;
    logic                    do_alloc;
    logic                    do_free;

    // Tracks which buffer ID was assigned to the currently-egressing packet
    logic [BUF_ID_WIDTH-1:0] active_buf_id;

    // -------------------------------------------------------------------------
    // packet_fifo
    // -------------------------------------------------------------------------
    // Write only when rx_valid and not full.
    // Read only when downstream is ready and a complete packet is available.
    // -------------------------------------------------------------------------
    assign fifo_wr_en = rx_valid & ~fifo_full;
    assign fifo_rd_en = tx_ready & ~fifo_empty & packets_ready;

    packet_fifo #(
        .DATA_WIDTH     (DATA_WIDTH),
        .DEPTH          (FIFO_DEPTH),
        .MAX_PACKET_SIZE(MAX_PACKET_SIZE)
    ) u_pkt_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (fifo_wr_en),
        .rd_en        (fifo_rd_en),
        .sop          (rx_sop),
        .eop          (rx_eop),
        .din          (rx_data),
        .dout         (fifo_dout),
        .sop_out      (sop_out_w),
        .eop_out      (eop_out_w),
        .full         (fifo_full),
        .empty        (fifo_empty),
        .packet_count (pkt_count),
        .frame_valid  (packets_ready)
    );

    // -------------------------------------------------------------------------
    // free_list_allocator
    // -------------------------------------------------------------------------
    // Allocate a buffer ID when a complete packet is committed to the FIFO
    // (ingress EOP and not full).
    // Free the buffer ID when the last byte of a packet exits (egress EOP).
    // -------------------------------------------------------------------------
    assign do_alloc = fifo_wr_en & rx_eop & alloc_valid;
    assign do_free  = fifo_rd_en & eop_out_w;

    free_list_allocator #(
        .NUM_RESOURCES (NUM_BUFFERS),
        .ID_WIDTH      (BUF_ID_WIDTH)
    ) u_fla (
        .clk        (clk),
        .rst_n      (rst_n),
        .alloc      (do_alloc),
        .free       (do_free),
        .free_id    (active_buf_id),
        .alloc_id   (alloc_id),
        .alloc_valid(alloc_valid),
        .empty      (buf_empty),
        .full       (buf_full),
        .count      ()
    );

    // -------------------------------------------------------------------------
    // Track active buffer ID for the current egress packet
    // -------------------------------------------------------------------------
    // Capture the allocated ID at the start of each new egress packet.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_buf_id <= '0;
        end else if (fifo_rd_en & sop_out_w) begin
            // New packet starts on the egress side; latch the most-recently
            // allocated ID.  In a real system this would come from a metadata
            // queue that pairs each buffer ID with its packet.
            active_buf_id <= alloc_id;
        end
    end

    // -------------------------------------------------------------------------
    // Egress outputs
    // -------------------------------------------------------------------------
    assign tx_data   = fifo_dout;
    assign tx_valid  = fifo_rd_en;
    assign tx_sop    = sop_out_w & fifo_rd_en;
    assign tx_eop    = eop_out_w & fifo_rd_en;
    assign tx_buf_id = active_buf_id;

endmodule
