`timescale 1ns / 1ps
//==============================================================================
// Module  : binary_heap
// Project : RTL Data Structures
//
// Overview:
//   Parameterised synchronous binary heap stored in a register array.  The
//   heap ordering is selectable at elaboration time: MIN_HEAP=1 produces a
//   min-heap (smallest key at root); MIN_HEAP=0 produces a max-heap (largest
//   key at root).  Insert places the new element at the end of the heap and
//   sifts it upward; remove_top removes the root, moves the last element to
//   the root, and sifts it downward.  Each sift step is one clock cycle;
//   the busy output is asserted throughout multi-cycle sift operations.
//
//   key_out / data_out are combinatorial outputs that continuously expose the
//   current root of the heap.  They should only be sampled when !busy.
//
// Parameters:
//   DATA_WIDTH - Width of each data payload in bits.          Default = 8
//   KEY_WIDTH  - Width of the ordering key in bits.           Default = 8
//   DEPTH      - Maximum number of heap entries.              Default = 16
//   MIN_HEAP   - 1 = min-heap (smallest key at root);         Default = 1
//                0 = max-heap (largest  key at root).
//
// Ports:
//   clk        - Clock, rising-edge triggered.
//   rst_n      - Asynchronous active-low reset.
//   insert     - Insert request.  Ignored when full or busy.
//   remove_top - Remove-root request.  Ignored when empty or busy.
//   key_in     - Key of element to insert             [KEY_WIDTH-1:0]
//   data_in    - Data payload of element to insert    [DATA_WIDTH-1:0]
//   key_out    - Combinatorial root key               [KEY_WIDTH-1:0]
//   data_out   - Combinatorial root data              [DATA_WIDTH-1:0]
//   full       - Asserted when count == DEPTH.
//   empty      - Asserted when count == 0.
//   count      - Number of valid entries               [$clog2(DEPTH):0]
//   busy       - High while a sift operation is in progress.
//
// Timing:
//   insert / remove_top captured at posedge clk when conditions allow.
//   busy is registered; it goes high on the cycle after insert/remove_top
//   initiates a sift, and falls on the cycle the sift completes.
//   key_out / data_out track heap[0] combinatorially (zero when empty).
//
// Insertion / Removal Semantics:
//   - insert when !full && !busy: writes element, starts SIFT_UP if count > 0.
//   - remove_top when !empty && !busy: exposes current root, moves last element
//     to root, decrements count, starts SIFT_DOWN if new count > 1.
//   - insert && remove_top simultaneously: insert takes priority.
//   - Operations while busy are silently dropped; caller must poll busy.
//
// Hardware Tradeoffs:
//   - O(log N) latency: at most ceil(log2(DEPTH)) busy cycles per operation.
//   - One register-swap per busy cycle; two read + two write ports required.
//   - MIN_HEAP is a static parameter: the synthesizer folds the comparison
//     constant, so there is no runtime mux on the heap ordering direction.
//   - Storage: DEPTH * (KEY_WIDTH + DATA_WIDTH) flip-flops.
//   - For DEPTH=16 this is ≤4 busy cycles; for DEPTH=1024 ≤10 cycles.
//   - See min_heap / max_heap for convenient single-direction wrappers.
//==============================================================================

module binary_heap #(
    parameter int DATA_WIDTH = 8,
    parameter int KEY_WIDTH  = 8,
    parameter int DEPTH      = 16,
    parameter int MIN_HEAP   = 1   // 1 = min-heap, 0 = max-heap
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    insert,
    input  logic                    remove_top,
    input  logic [KEY_WIDTH-1:0]    key_in,
    input  logic [DATA_WIDTH-1:0]   data_in,
    output logic [KEY_WIDTH-1:0]    key_out,
    output logic [DATA_WIDTH-1:0]   data_out,
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  count,
    output logic                    busy
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int IDX_W = $clog2(DEPTH);   // Bits to address 0..DEPTH-1
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
    logic [KEY_WIDTH-1:0]   key_mem  [0:DEPTH-1];
    logic [DATA_WIDTH-1:0]  data_mem [0:DEPTH-1];
    logic [CNT_W-1:0]       count_r;
    logic [IDX_W-1:0]       sift_idx;

    // --------------------------------------------------------------------------
    // Combinatorial sift helpers
    // --------------------------------------------------------------------------
    logic [IDX_W-1:0]  s_parent;
    logic [IDX_W+1:0]  s_left_ext;    // 2*sift_idx+1 (IDX_W+2 bits, no overflow)
    logic [IDX_W+1:0]  s_right_ext;   // 2*sift_idx+2
    logic [IDX_W-1:0]  s_left;
    logic [IDX_W-1:0]  s_right;
    logic [IDX_W-1:0]  s_best;
    logic              s_has_left;
    logic              s_has_right;
    logic              s_cmp_up;    // True when sift_idx should swap with parent (SIFT_UP)
    logic              s_cmp_down;  // True when s_best should swap with sift_idx (SIFT_DOWN)

    always_comb begin
        s_parent    = (sift_idx - 1'b1) >> 1;
        s_left_ext  = {1'b0, sift_idx, 1'b0} + {{(IDX_W+1){1'b0}}, 1'b1};
        s_right_ext = {1'b0, sift_idx, 1'b0} + {{IDX_W{1'b0}}, 2'b10};
        s_left      = s_left_ext[IDX_W-1:0];
        s_right     = s_right_ext[IDX_W-1:0];
        s_has_left  = (s_left_ext  < {1'b0, count_r});
        s_has_right = (s_right_ext < {1'b0, count_r});

        // Default best child = left; override with right if right is "better"
        s_best = s_left;
        if (s_has_left && s_has_right) begin
            if (MIN_HEAP[0]) begin
                s_best = (key_mem[s_right] < key_mem[s_left]) ? s_right : s_left;
            end else begin
                s_best = (key_mem[s_right] > key_mem[s_left]) ? s_right : s_left;
            end
        end

        // Sift-up comparison: is the current node "better" than its parent?
        s_cmp_up = MIN_HEAP[0] ? (key_mem[sift_idx] < key_mem[s_parent])
                                : (key_mem[sift_idx] > key_mem[s_parent]);

        // Sift-down comparison: is the best child "better" than the current node?
        s_cmp_down = MIN_HEAP[0] ? (key_mem[s_best] < key_mem[sift_idx])
                                 : (key_mem[s_best] > key_mem[sift_idx]);
    end

    // --------------------------------------------------------------------------
    // Status flags and combinatorial outputs
    // --------------------------------------------------------------------------
    assign full     = (count_r == CNT_W'(DEPTH));
    assign empty    = (count_r == '0);
    assign count    = count_r;
    assign busy     = (state != IDLE);
    assign key_out  = empty ? '0 : key_mem[0];
    assign data_out = empty ? '0 : data_mem[0];

    // --------------------------------------------------------------------------
    // Main state machine
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            count_r  <= '0;
            sift_idx <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                key_mem[i]  <= '0;
                data_mem[i] <= '0;
            end
        end else begin
            unique case (state)

                // ------------------------------------------------------------------
                IDLE: begin
                    if (insert && !full) begin
                        // Append new element; sift up if not the first entry
                        key_mem[count_r[IDX_W-1:0]]  <= key_in;
                        data_mem[count_r[IDX_W-1:0]] <= data_in;
                        sift_idx <= count_r[IDX_W-1:0];
                        count_r  <= count_r + 1'b1;
                        if (count_r > '0) state <= SIFT_UP;
                    end else if (remove_top && !empty) begin
                        // Move last element to root; sift down if more than 1 entry
                        key_mem[0]  <= key_mem[count_r[IDX_W-1:0] - 1'b1];
                        data_mem[0] <= data_mem[count_r[IDX_W-1:0] - 1'b1];
                        count_r  <= count_r - 1'b1;
                        sift_idx <= '0;
                        if (count_r > CNT_W'(1)) state <= SIFT_DOWN;
                    end
                end

                // ------------------------------------------------------------------
                SIFT_UP: begin
                    if (sift_idx == '0) begin
                        state <= IDLE;
                    end else if (s_cmp_up) begin
                        key_mem[sift_idx]   <= key_mem[s_parent];
                        key_mem[s_parent]   <= key_mem[sift_idx];
                        data_mem[sift_idx]  <= data_mem[s_parent];
                        data_mem[s_parent]  <= data_mem[sift_idx];
                        sift_idx            <= s_parent;
                    end else begin
                        state <= IDLE;
                    end
                end

                // ------------------------------------------------------------------
                SIFT_DOWN: begin
                    if (!s_has_left) begin
                        state <= IDLE;
                    end else if (s_cmp_down) begin
                        key_mem[sift_idx]  <= key_mem[s_best];
                        key_mem[s_best]    <= key_mem[sift_idx];
                        data_mem[sift_idx] <= data_mem[s_best];
                        data_mem[s_best]   <= data_mem[sift_idx];
                        sift_idx           <= s_best;
                    end else begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
