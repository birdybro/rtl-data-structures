`timescale 1ns / 1ps
//==============================================================================
// Module  : scoreboard_allocator
// Project : RTL Data Structures
//
// Overview:
//   Tag-based scoreboard allocator for tracking in-flight operations.  A
//   fixed-size bitmap records which tags are currently allocated.  On each
//   clock cycle a caller may request a new tag (alloc) and/or release an
//   existing tag (free).  The combinatorial priority encoder always presents
//   the lowest-numbered free tag at alloc_tag; alloc_valid indicates whether
//   any free tag is available.  The allocation is committed (bitmap updated)
//   on the rising clock edge when alloc is asserted.
//
// Parameters:
//   NUM_ENTRIES - Total number of tags managed (bitmap width).  Default = 16
//   TAG_WIDTH   - Width of tag identifiers.                     Default = 4
//                 Must satisfy 2^TAG_WIDTH >= NUM_ENTRIES.
//
// Ports:
//   clk        - Clock, rising-edge triggered.
//   rst_n      - Asynchronous active-low reset; all tags freed on reset.
//   alloc      - Allocation request; allocates alloc_tag when alloc_valid.
//   free       - Free request; marks free_tag as available.
//   alloc_tag  - Combinatorial lowest-numbered free tag [TAG_WIDTH-1:0]
//   free_tag   - Tag to be released [TAG_WIDTH-1:0]
//   alloc_valid- High when at least one free tag exists (alloc can proceed).
//   full       - High when all tags are allocated (no free tag available).
//
// Timing:
//   alloc: bitmap updated (tag marked allocated) at posedge clk when alloc &&
//          alloc_valid.  alloc_tag and alloc_valid reflect the state BEFORE the
//          current clock edge (combinatorial showahead).
//   free:  bitmap updated (tag marked free) at posedge clk when free.
//   Simultaneous alloc && free: both operations execute atomically; if both
//   target the same tag the net effect is that the tag remains allocated
//   (alloc wins over free for the same tag).
//   full and alloc_valid are combinatorial, derived from the bitmap register.
//
// Insertion / Removal Semantics:
//   - alloc when !alloc_valid (full): silently ignored; alloc_tag is undefined.
//   - free with a tag that is already free: silently accepted (idempotent).
//   - free_tag must be < NUM_ENTRIES; values >= NUM_ENTRIES are ignored.
//   - Tags are allocated in order of increasing index (first-fit, lowest tag
//     first) to keep allocation deterministic and easy to verify.
//
// Hardware Tradeoffs:
//   - O(NUM_ENTRIES) combinatorial priority encoder for alloc_tag; for
//     NUM_ENTRIES=16 this is a small chain.  Timing grows logarithmically
//     with a tree-reduction encoder but is implemented linearly here for
//     clarity.
//   - Storage: NUM_ENTRIES flip-flops (the allocated bitmap).
//   - Full detection is a NOR reduction of the bitmap (~allocated == 0).
//   - alloc and free are each a single bit-set/clear, O(1) logic.
//   - Suitable for out-of-order execution engines, TLB miss queues, DMA
//     descriptor rings, and any structure requiring unique in-flight IDs.
//==============================================================================

module scoreboard_allocator #(
    parameter int NUM_ENTRIES = 16,
    parameter int TAG_WIDTH   = 4
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    alloc,
    input  logic                    free,
    output logic [TAG_WIDTH-1:0]    alloc_tag,
    input  logic [TAG_WIDTH-1:0]    free_tag,
    output logic                    alloc_valid,
    output logic                    full
);

    // --------------------------------------------------------------------------
    // Allocated bitmap: bit i is 1 when tag i is in use
    // --------------------------------------------------------------------------
    logic [NUM_ENTRIES-1:0] allocated;

    // --------------------------------------------------------------------------
    // Combinatorial priority encoder: find lowest-numbered free tag
    // --------------------------------------------------------------------------
    always_comb begin
        alloc_tag   = '0;
        alloc_valid = 1'b0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (!allocated[i] && !alloc_valid) begin
                alloc_tag   = TAG_WIDTH'(i);
                alloc_valid = 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Status flags (combinatorial)
    // --------------------------------------------------------------------------
    assign full = (allocated == {NUM_ENTRIES{1'b1}});

    // --------------------------------------------------------------------------
    // Bitmap update
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            allocated <= '0;
        end else begin
            // Free first so simultaneous alloc+free on the same tag is
            // resolved as allocated (alloc writes after free in the same edge).
            if (free && (free_tag < TAG_WIDTH'(NUM_ENTRIES))) begin
                allocated[free_tag] <= 1'b0;
            end
            // Allocate lowest free tag when requested and available
            if (alloc && alloc_valid) begin
                allocated[alloc_tag] <= 1'b1;
            end
        end
    end

endmodule
