// =============================================================================
// free_list_allocator.sv
// =============================================================================
// Overview:
//   Manages a pool of NUM_RESOURCES resource IDs (0 … NUM_RESOURCES-1).
//   Internally uses a register-based bitmap to track which IDs are free.
//   Allocation returns the lowest-numbered free ID (priority-encoder style).
//   Free returns any previously allocated ID to the pool.  Simultaneous
//   alloc + free in the same cycle is handled correctly.
//
// Parameters:
//   NUM_RESOURCES - Total number of resource IDs to manage  (default 16)
//   ID_WIDTH      - Width of resource ID output; set to $clog2(NUM_RESOURCES)
//
// Ports:
//   clk        - Clock, rising-edge triggered
//   rst_n      - Asynchronous active-low reset; all IDs become free
//   alloc      - Pulse: request one free ID this cycle
//   free       - Pulse: return free_id to the pool
//   alloc_id   - Allocated ID (registered; valid when alloc_valid high)  [ID_WIDTH-1:0]
//   free_id    - ID to return                                            [ID_WIDTH-1:0]
//   alloc_valid- 1 the cycle after alloc when allocation succeeded
//   empty      - No resources available (all allocated); combinatorial
//   full       - All resources are free (none allocated); combinatorial
//   count      - Number of free resources; combinatorial  [$clog2(NUM_RESOURCES):0]
//
// Timing:
//   - alloc_id and alloc_valid are registered: available the cycle after alloc.
//   - free_id takes effect on the cycle after free is asserted.
//   - empty, full, count are combinatorial: reflect current bitmap state.
//
// Insertion/Removal Semantics:
//   Alloc : priority-encoder on free_bitmap, pick lowest '1' bit.
//           Mark that bit as 0 (allocated).  Output alloc_id + alloc_valid.
//   Free  : set free_bitmap[free_id] = 1.
//   Sim.  : if alloc && free in same cycle and pool would otherwise be empty,
//           the freed ID can be immediately re-allocated.
//
// Hardware Tradeoffs:
//   - Priority encoder scales O(NUM_RESOURCES) combinatorial gates.
//   - Bitmap is a simple flip-flop register array.
//   - For NUM_RESOURCES > 64, consider a hierarchical bitmap.
// =============================================================================

`timescale 1ns/1ps

module free_list_allocator #(
    parameter int NUM_RESOURCES = 16,
    parameter int ID_WIDTH      = $clog2(NUM_RESOURCES)
) (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            alloc,
    input  logic                            free,
    input  logic [ID_WIDTH-1:0]             free_id,
    output logic [ID_WIDTH-1:0]             alloc_id,
    output logic                            alloc_valid,
    output logic                            empty,
    output logic                            full,
    output logic [$clog2(NUM_RESOURCES):0]  count
);

    // -------------------------------------------------------------------------
    // free_bitmap: 1 = free (available), 0 = allocated
    // -------------------------------------------------------------------------
    logic [NUM_RESOURCES-1:0] free_bitmap;

    // -------------------------------------------------------------------------
    // next_bitmap: combinatorial view of free_bitmap after a pending free.
    // Used so that a simultaneous alloc+free can re-allocate the freed ID
    // in the same cycle (result registered one cycle later).
    // -------------------------------------------------------------------------
    logic [NUM_RESOURCES-1:0] next_bitmap;

    always_comb begin
        next_bitmap = free_bitmap;
        if (free)
            next_bitmap[free_id] = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Priority encoder on next_bitmap: lowest-numbered free ID
    // -------------------------------------------------------------------------
    logic [ID_WIDTH-1:0] first_free;
    logic                any_free;

    always_comb begin
        first_free = '0;
        any_free   = 1'b0;
        for (int i = NUM_RESOURCES-1; i >= 0; i--) begin
            if (next_bitmap[i]) begin
                first_free = ID_WIDTH'(i);
                any_free   = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinatorial status (based on registered bitmap, not next_bitmap)
    // -------------------------------------------------------------------------
    always_comb begin
        empty = ~|free_bitmap;
        full  =  &free_bitmap;
        count = '0;
        for (int i = 0; i < NUM_RESOURCES; i++)
            count = count + ($clog2(NUM_RESOURCES)+1)'(free_bitmap[i]);
    end

    // -------------------------------------------------------------------------
    // Sequential: update bitmap, register alloc_id / alloc_valid
    // Free is applied before alloc so that a simultaneous alloc+free correctly
    // resolves: if they target the same bit, the alloc assignment (last) wins.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_bitmap <= {NUM_RESOURCES{1'b1}};
            alloc_id    <= '0;
            alloc_valid <= 1'b0;
        end else begin
            alloc_valid <= 1'b0;

            if (free)
                free_bitmap[free_id] <= 1'b1;

            if (alloc && any_free) begin
                free_bitmap[first_free] <= 1'b0;
                alloc_id                <= first_free;
                alloc_valid             <= 1'b1;
            end
        end
    end

endmodule
