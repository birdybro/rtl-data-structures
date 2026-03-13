`timescale 1ns / 1ps
//==============================================================================
// Module  : priority_queue_heap
// Project : RTL Data Structures
//
// Overview:
//   Synchronous min-priority queue implemented as a binary min-heap stored in
//   a register array.  Push (insert) adds the new element at the end of the
//   heap and sifts it upward toward the root over multiple clock cycles.  Pop
//   (dequeue) removes the root (minimum priority), moves the last element to
//   the root, and sifts it downward.  While a sift operation is in progress
//   the busy signal is asserted; push and pop are ignored when busy.
//
//   Lower numeric priority value = higher logical priority (min-heap ordering).
//   The current minimum is always visible combinatorially at dout/priority_out.
//
// Parameters:
//   DATA_WIDTH     - Width of each data payload in bits.       Default = 8
//   PRIORITY_WIDTH - Width of the priority key in bits.        Default = 4
//   DEPTH          - Maximum heap capacity (entries).          Default = 16
//
// Ports:
//   clk          - Clock, rising-edge triggered.
//   rst_n        - Asynchronous active-low reset.
//   push         - Enqueue request.  Ignored when full or busy.
//   pop          - Dequeue request.  Ignored when empty or busy.
//   din          - Data payload to enqueue        [DATA_WIDTH-1:0]
//   priority_in  - Priority of the new entry      [PRIORITY_WIDTH-1:0]
//   dout         - Combinatorial root data output [DATA_WIDTH-1:0]
//   priority_out - Combinatorial root priority    [PRIORITY_WIDTH-1:0]
//   full         - Asserted when count == DEPTH.
//   empty        - Asserted when count == 0.
//   count        - Number of valid entries         [$clog2(DEPTH):0]
//   busy         - High while a sift operation is in progress.
//
// Timing:
//   push/pop captured at posedge clk when respective conditions allow.
//   busy goes high on the cycle after push/pop (when sifting is needed) and
//   falls on the cycle the sift completes.
//   dout/priority_out reflect heap[0] combinatorially; they may glitch during
//   sift operations and should only be sampled when !busy.
//
// Insertion / Removal Semantics:
//   - push when !full && !busy: appends element, starts SIFT_UP (if count > 0).
//   - pop  when !empty && !busy: captures root output, moves last element to
//     root, decrements count, starts SIFT_DOWN (if new count > 1).
//   - push or pop while busy: silently ignored; caller must poll busy.
//   - Simultaneous push && pop: push takes priority.
//
// Hardware Tradeoffs:
//   - O(log N) latency for push/pop: at most ceil(log2(DEPTH)) busy cycles.
//   - One swap per clock cycle during sift (two array reads + two writes).
//   - Storage: DEPTH * (DATA_WIDTH + PRIORITY_WIDTH) flip-flops.
//   - Critical path: two priority comparisons + mux for best-child selection.
//   - Area roughly proportional to DEPTH * (DATA_WIDTH + PRIORITY_WIDTH).
//   - Throughput: one push or pop accepted every ~log2(DEPTH)+1 cycles.
//==============================================================================

module priority_queue_heap #(
    parameter int DATA_WIDTH     = 8,
    parameter int PRIORITY_WIDTH = 4,
    parameter int DEPTH          = 16
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        push,
    input  logic                        pop,
    input  logic [DATA_WIDTH-1:0]       din,
    input  logic [PRIORITY_WIDTH-1:0]   priority_in,
    output logic [DATA_WIDTH-1:0]       dout,
    output logic [PRIORITY_WIDTH-1:0]   priority_out,
    output logic                        full,
    output logic                        empty,
    output logic [$clog2(DEPTH):0]      count,
    output logic                        busy
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int IDX_W = $clog2(DEPTH);   // Bits to index 0..DEPTH-1
    localparam int CNT_W = IDX_W + 1;       // Bits to hold count 0..DEPTH

    // --------------------------------------------------------------------------
    // State encoding
    // --------------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE       = 2'd0,
        SIFT_UP    = 2'd1,
        SIFT_DOWN  = 2'd2
    } state_t;

    state_t state;

    // --------------------------------------------------------------------------
    // Heap storage
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]      heap_data [0:DEPTH-1];
    logic [PRIORITY_WIDTH-1:0]  heap_prio [0:DEPTH-1];
    logic [CNT_W-1:0]           count_r;
    logic [IDX_W-1:0]           sift_idx;  // Current node being sifted

    // --------------------------------------------------------------------------
    // Combinatorial sift helpers (recomputed every cycle from sift_idx)
    // --------------------------------------------------------------------------
    logic [IDX_W-1:0]   s_parent;           // Parent of sift_idx
    logic [IDX_W+1:0]   s_left_ext;         // 2*sift_idx+1 (extended width)
    logic [IDX_W+1:0]   s_right_ext;        // 2*sift_idx+2 (extended width)
    logic [IDX_W-1:0]   s_left;             // Truncated left-child index
    logic [IDX_W-1:0]   s_right;            // Truncated right-child index
    logic [IDX_W-1:0]   s_best;             // Best (lower priority) child
    logic               s_has_left;
    logic               s_has_right;

    always_comb begin
        // Parent: floor((idx-1)/2).  Garbage when sift_idx==0 but never used then.
        s_parent    = (sift_idx - 1'b1) >> 1;

        // Child indices; use IDX_W+2 bits to prevent overflow when sift_idx
        // is near DEPTH-1 (e.g. 2*15+2 = 32 for DEPTH=16, needs 6 bits).
        s_left_ext  = {1'b0, sift_idx, 1'b0} + {{(IDX_W+1){1'b0}}, 1'b1};
        s_right_ext = {1'b0, sift_idx, 1'b0} + {{IDX_W{1'b0}}, 2'b10};
        s_left      = s_left_ext[IDX_W-1:0];
        s_right     = s_right_ext[IDX_W-1:0];

        // Valid child flags: compare extended index against count
        s_has_left  = (s_left_ext  < {1'b0, count_r});
        s_has_right = (s_right_ext < {1'b0, count_r});

        // Best child = child with the lower priority value (min-heap)
        s_best = s_left;   // default; safe even if s_has_left is false
        if (s_has_left && s_has_right) begin
            s_best = (heap_prio[s_right] < heap_prio[s_left]) ? s_right : s_left;
        end
    end

    // --------------------------------------------------------------------------
    // Status flags
    // --------------------------------------------------------------------------
    assign full  = (count_r == CNT_W'(DEPTH));
    assign empty = (count_r == '0);
    assign count = count_r;
    assign busy  = (state != IDLE);

    // --------------------------------------------------------------------------
    // Combinatorial root output (showahead)
    // --------------------------------------------------------------------------
    assign dout         = empty ? '0 : heap_data[0];
    assign priority_out = empty ? '1 : heap_prio[0];

    // --------------------------------------------------------------------------
    // Main state machine
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            count_r  <= '0;
            sift_idx <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                heap_data[i] <= '0;
                heap_prio[i] <= '1;
            end
        end else begin
            unique case (state)

                // ------------------------------------------------------------------
                IDLE: begin
                    if (push && !full) begin
                        // Insert new element at the end of the heap
                        heap_data[count_r[IDX_W-1:0]] <= din;
                        heap_prio[count_r[IDX_W-1:0]] <= priority_in;
                        count_r  <= count_r + 1'b1;
                        sift_idx <= count_r[IDX_W-1:0];  // Index just written
                        if (count_r > '0) state <= SIFT_UP;
                        // count_r == 0 means first element; no sift needed
                    end else if (pop && !empty) begin
                        // Replace root with last element, then sift down
                        heap_data[0] <= heap_data[count_r[IDX_W-1:0] - 1'b1];
                        heap_prio[0] <= heap_prio[count_r[IDX_W-1:0] - 1'b1];
                        count_r  <= count_r - 1'b1;
                        sift_idx <= '0;
                        // Start sift-down only if at least two elements remain
                        if (count_r > CNT_W'(1)) state <= SIFT_DOWN;
                    end
                end

                // ------------------------------------------------------------------
                SIFT_UP: begin
                    if (sift_idx == '0) begin
                        // Reached the root; heap property restored
                        state <= IDLE;
                    end else if (heap_prio[sift_idx] < heap_prio[s_parent]) begin
                        // Child priority < parent priority: swap and continue up
                        heap_prio[sift_idx]  <= heap_prio[s_parent];
                        heap_prio[s_parent]  <= heap_prio[sift_idx];
                        heap_data[sift_idx]  <= heap_data[s_parent];
                        heap_data[s_parent]  <= heap_data[sift_idx];
                        sift_idx             <= s_parent;
                    end else begin
                        // Heap property satisfied; done
                        state <= IDLE;
                    end
                end

                // ------------------------------------------------------------------
                SIFT_DOWN: begin
                    if (!s_has_left) begin
                        // No children; heap property satisfied
                        state <= IDLE;
                    end else if (heap_prio[s_best] < heap_prio[sift_idx]) begin
                        // Best child has lower priority value: swap and continue down
                        heap_prio[sift_idx] <= heap_prio[s_best];
                        heap_prio[s_best]   <= heap_prio[sift_idx];
                        heap_data[sift_idx] <= heap_data[s_best];
                        heap_data[s_best]   <= heap_data[sift_idx];
                        sift_idx            <= s_best;
                    end else begin
                        // Heap property satisfied; done
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
