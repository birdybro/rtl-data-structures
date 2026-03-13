// =============================================================================
// resource_allocator.sv  –  Example: Resource Allocation System
// =============================================================================
// Combines a bitmap_allocator (for fast slot allocation) with a free_queue
// (for maintaining a FIFO order of returned resources for fairness).
// Shows how to use both structures together for a complete resource management
// system.
//
// Architecture:
//   - bitmap_allocator tracks which slots are in-use / available.
//   - free_queue holds returned resource IDs in FIFO order so that recently
//     released IDs are re-issued last (maximising reuse distance / fairness).
//   - On request_alloc: dequeue the oldest free ID from free_queue and ask
//     bitmap_allocator to mark it allocated.
//   - On do_release:   free the slot in bitmap_allocator and enqueue the ID
//     into free_queue for later re-issue.
//
// Instantiates: bitmap_allocator, free_queue
//
// Ports:
//   clk, rst_n
//   request_alloc    – request to allocate a resource
//   release_id[3:0]  – resource ID to release
//   do_release       – pulse to release resource
//   alloc_id[3:0]    – allocated resource ID
//   alloc_valid      – allocation was successful
//   pool_empty       – no resources available
//   pool_full        – all resources free (none allocated)
//   available[4:0]   – number of available resources
// =============================================================================

`timescale 1ns/1ps

`include "../rtl/utils/bitmap_allocator.sv"
`include "../rtl/utils/free_queue.sv"

module resource_allocator #(
    parameter int NUM_SLOTS    = 16,
    parameter int ID_BITS      = 4    // must equal $clog2(NUM_SLOTS)
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Allocation interface
    input  logic                   request_alloc,
    output logic [ID_BITS-1:0]     alloc_id,
    output logic                   alloc_valid,

    // Release interface
    input  logic [ID_BITS-1:0]     release_id,
    input  logic                   do_release,

    // Status
    output logic                   pool_empty,
    output logic                   pool_full,
    output logic [$clog2(NUM_SLOTS):0] available
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic [ID_BITS-1:0]  fq_dout;       // front of the free queue
    logic                fq_empty;
    logic                fq_full;
    logic [$clog2(NUM_SLOTS):0] fq_count;

    logic                bm_alloc_valid;
    logic                bm_full;
    logic                bm_empty;

    // Can allocate only when the free queue is non-empty
    logic do_alloc;

    // -------------------------------------------------------------------------
    // Allocation control
    // -------------------------------------------------------------------------
    assign do_alloc    = request_alloc & ~fq_empty;
    assign alloc_valid = do_alloc & bm_alloc_valid;
    assign alloc_id    = fq_dout;
    assign pool_empty  = fq_empty;

    // -------------------------------------------------------------------------
    // free_queue
    // -------------------------------------------------------------------------
    // Pre-loaded at reset with IDs 0..NUM_SLOTS-1 (handled internally by the
    // free_queue reset sequence).  IDs are dequeued on allocation and
    // re-enqueued on release.
    // -------------------------------------------------------------------------
    free_queue #(
        .DATA_WIDTH (ID_BITS),
        .DEPTH      (NUM_SLOTS)
    ) u_fq (
        .clk     (clk),
        .rst_n   (rst_n),
        .enqueue (do_release),
        .dequeue (do_alloc),
        .clear   (1'b0),
        .din     (release_id),
        .dout    (fq_dout),
        .full    (fq_full),
        .empty   (fq_empty),
        .count   (fq_count)
    );

    // -------------------------------------------------------------------------
    // bitmap_allocator
    // -------------------------------------------------------------------------
    // Tracks which IDs are currently in-use.  It is driven by the same alloc
    // and free signals, using the IDs sourced from the free_queue.
    // -------------------------------------------------------------------------
    bitmap_allocator #(
        .NUM_SLOTS    (NUM_SLOTS),
        .SLOT_ID_BITS (ID_BITS)
    ) u_bm (
        .clk             (clk),
        .rst_n           (rst_n),
        .alloc           (do_alloc),
        .free            (do_release),
        .free_id         (release_id),
        .alloc_id        (),           // free_queue drives alloc_id above
        .alloc_valid     (bm_alloc_valid),
        .full            (bm_full),
        .empty           (bm_empty),
        .available_count (available)
    );

    assign pool_full = bm_empty;  // bm_empty means no slots are allocated

endmodule
