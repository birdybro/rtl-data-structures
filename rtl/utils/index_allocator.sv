// =============================================================================
// index_allocator.sv
// =============================================================================
// Overview:
//   Index allocator using a pointer-based singly-linked free list. Each entry
//   in the next_free array holds the index of the next free slot. A head
//   pointer tracks the first available index.
//
// Parameters:
//   NUM_INDICES  - Total number of indices (default: 16)
//   INDEX_WIDTH  - Width of each index ($clog2(NUM_INDICES))
//
// Ports:
//   clk           - Clock
//   rst_n         - Active-low reset
//   request       - Pulse to request a free index
//   release       - Pulse to return release_index to pool
//   index_out     - Allocated index (registered)
//   release_index - Index being returned
//   valid         - Allocation succeeded (registered)
//   full          - No indices available
//   empty         - All indices are free
//   used_count    - Number of currently allocated indices
//
// Timing:
//   - index_out and valid are registered: available cycle after request
//   - release takes effect the cycle after it is asserted
//
// Insertion/Removal:
//   - On request: head index returned; head advances to next_free[head]
//   - On release: released index inserted at head of list
//
// Hardware Tradeoffs:
//   - O(1) alloc and free; constant latency regardless of NUM_INDICES
//   - next_free array is a small register file
// =============================================================================

`timescale 1ns/1ps

module index_allocator #(
    parameter int NUM_INDICES = 16,
    parameter int INDEX_WIDTH = $clog2(NUM_INDICES)
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          request,
    input  logic                          release,
    input  logic [INDEX_WIDTH-1:0]        release_index,
    output logic [INDEX_WIDTH-1:0]        index_out,
    output logic                          valid,
    output logic                          full,
    output logic                          empty,
    output logic [$clog2(NUM_INDICES):0]  used_count
);

    // -----------------------------------------------------------------------
    // Free list: next_free[i] = next index in chain after i
    // Sentinel: INDEX_WIDTH'(NUM_INDICES-1) with next pointing to itself
    //           when list is exhausted (tracked via free_count).
    // -----------------------------------------------------------------------
    logic [INDEX_WIDTH-1:0] next_free [0:NUM_INDICES-1];
    logic [INDEX_WIDTH-1:0] head;
    logic [$clog2(NUM_INDICES):0] free_count;

    assign full       = (free_count == '0);
    assign empty      = (free_count == NUM_INDICES[$clog2(NUM_INDICES):0]);
    assign used_count = NUM_INDICES[$clog2(NUM_INDICES):0] - free_count;

    // -----------------------------------------------------------------------
    // Sequential
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head       <= '0;
            free_count <= NUM_INDICES[$clog2(NUM_INDICES):0];
            index_out  <= '0;
            valid      <= 1'b0;
            // Build initial linked list: 0->1->2->...->N-1
            for (int i = 0; i < NUM_INDICES; i++)
                next_free[i] <= INDEX_WIDTH'(i + 1);
        end else begin
            valid <= 1'b0;

            if (request && !full) begin
                index_out          <= head;
                head               <= next_free[head];
                free_count         <= free_count - 1'b1;
                valid              <= 1'b1;
            end

            if (release && !empty) begin
                next_free[release_index] <= (request && !full) ? next_free[head] : head;
                head                     <= release_index;
                free_count               <= free_count + 1'b1;
            end
        end
    end

endmodule
