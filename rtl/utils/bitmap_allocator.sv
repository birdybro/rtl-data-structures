// =============================================================================
// bitmap_allocator.sv
// =============================================================================
// Overview:
//   Bitmap-based slot allocator. Allocates the lowest-numbered free slot using
//   a priority encoder and tracks availability with a bitmap register.
//
// Parameters:
//   NUM_SLOTS     - Total number of allocatable slots (default: 16)
//   SLOT_ID_BITS  - Width of slot ID ($clog2(NUM_SLOTS))
//
// Ports:
//   clk             - Clock
//   rst_n           - Active-low reset
//   alloc           - Pulse to allocate a slot
//   free            - Pulse to free slot free_id
//   alloc_id        - ID of allocated slot (registered, valid when alloc_valid)
//   free_id         - ID of slot to return to pool
//   alloc_valid     - High when allocation succeeded (not full)
//   full            - No free slots available
//   empty           - All slots are free
//   available_count - Number of currently free slots
//
// Timing:
//   - alloc_id is registered: available the cycle after alloc is asserted
//   - alloc_valid reflects the state at the time of alloc
//   - free takes effect the cycle after free is asserted
//
// Hardware Tradeoffs:
//   - Priority encoder is O(N) logic; fine for NUM_SLOTS <= 64
//   - For large NUM_SLOTS consider a tree-based find-first-zero
// =============================================================================

`timescale 1ns/1ps

module bitmap_allocator #(
    parameter int NUM_SLOTS    = 16,
    parameter int SLOT_ID_BITS = $clog2(NUM_SLOTS)
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      alloc,
    input  logic                      free,
    input  logic [SLOT_ID_BITS-1:0]   free_id,
    output logic [SLOT_ID_BITS-1:0]   alloc_id,
    output logic                      alloc_valid,
    output logic                      full,
    output logic                      empty,
    output logic [$clog2(NUM_SLOTS):0] available_count
);

    // -------------------------------------------------------------------------
    // free_map: 1 = free, 0 = allocated
    // -------------------------------------------------------------------------
    logic [NUM_SLOTS-1:0] free_map;

    // -------------------------------------------------------------------------
    // Priority encoder: find lowest free slot
    // -------------------------------------------------------------------------
    logic [SLOT_ID_BITS-1:0] first_free;
    logic                    any_free;

    always_comb begin
        first_free = '0;
        any_free   = 1'b0;
        for (int i = NUM_SLOTS-1; i >= 0; i--) begin
            if (free_map[i]) begin
                first_free = SLOT_ID_BITS'(i);
                any_free   = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sequential: update bitmap
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_map   <= {NUM_SLOTS{1'b1}};
            alloc_id   <= '0;
            alloc_valid <= 1'b0;
        end else begin
            alloc_valid <= 1'b0;
            if (alloc && any_free) begin
                free_map[first_free] <= 1'b0;
                alloc_id             <= first_free;
                alloc_valid          <= 1'b1;
            end
            if (free) begin
                free_map[free_id] <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational status
    // -------------------------------------------------------------------------
    always_comb begin
        full  = ~|free_map;
        empty =  &free_map;
        available_count = '0;
        for (int i = 0; i < NUM_SLOTS; i++)
            available_count = available_count + ($clog2(NUM_SLOTS)+1)'(free_map[i]);
    end

endmodule
