// =============================================================================
// set_associative_table.sv
// =============================================================================
// Overview:
//   N-way set-associative lookup table, similar to a CPU data cache.  Each
//   incoming key is split into a set-index (lower LOG_SETS bits) and a tag
//   (upper bits).  All WAYS entries within the selected set are compared in
//   parallel on every read.  On a write, if the set has a free (invalid) way,
//   the data is placed there; otherwise the Pseudo-LRU (PLRU) victim way is
//   evicted.  A compact PLRU bit-tree per set (WAYS-1 bits) tracks the
//   least-recently-used way without the full counter overhead of true LRU.
//
// Parameters:
//   KEY_WIDTH   - Total key width in bits                  (default 8)
//   DATA_WIDTH  - Data payload width in bits               (default 8)
//   NUM_SETS    - Number of sets; must be power of 2       (default 8)
//   WAYS        - Number of ways per set; must be power of 2, >= 2 (default 4)
//
// Ports:
//   clk          - Clock, rising-edge triggered
//   rst_n        - Asynchronous active-low reset
//   write_en     - Write key_in/data_in into the table
//   read_en      - Lookup key_in; result available next cycle
//   invalidate_en- Remove entry matching key_in
//   key_in       - Key to write/read/invalidate  [KEY_WIDTH-1:0]
//   data_in      - Data to write                 [DATA_WIDTH-1:0]
//   data_out     - Read result (registered)      [DATA_WIDTH-1:0]
//   hit          - Registered: 1 when read_en found key_in
//   miss         - Registered: 1 when read_en did not find key_in
//   evict_way    - Registered: index of the evicted way on write  [$clog2(WAYS)-1:0]
//
// Timing:
//   - All commands (write_en, read_en, invalidate_en) are captured on the
//     rising edge of clk.
//   - hit, miss, data_out, evict_way are registered outputs, valid one cycle
//     after the corresponding command.
//
// Insertion/Removal Semantics:
//   Write  : Compute set index and tag from key_in.
//            If any way in the set is invalid, write to the lowest invalid way.
//            Else evict the PLRU victim way and write there.
//            Update PLRU bits to mark the written way as most-recently used.
//   Read   : Parallel compare key_in tag against all valid ways in the set.
//            On hit: return data_out, assert hit.  Update PLRU to MRU.
//            On miss: assert miss.
//   Invalidate: Parallel compare; clear valid bit of matching way(s).
//
// Hardware Tradeoffs:
//   - Parallel comparators: WAYS * TAG_WIDTH gates per set; scales with WAYS.
//   - PLRU tree: WAYS-1 bits per set, O(1) update, O(1) victim select.
//   - Full true-LRU would need log2(WAYS!) bits per set.
//   - Storage: NUM_SETS * WAYS * (1 + TAG_WIDTH + DATA_WIDTH) flip-flops.
// =============================================================================

`timescale 1ns/1ps

module set_associative_table #(
    parameter int KEY_WIDTH  = 8,
    parameter int DATA_WIDTH = 8,
    parameter int NUM_SETS   = 8,
    parameter int WAYS       = 4
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        write_en,
    input  logic                        read_en,
    input  logic                        invalidate_en,
    input  logic [KEY_WIDTH-1:0]        key_in,
    input  logic [DATA_WIDTH-1:0]       data_in,
    output logic [DATA_WIDTH-1:0]       data_out,
    output logic                        hit,
    output logic                        miss,
    output logic [$clog2(WAYS)-1:0]     evict_way
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int LOG_SETS  = $clog2(NUM_SETS);
    localparam int TAG_WIDTH = (KEY_WIDTH > LOG_SETS) ? (KEY_WIDTH - LOG_SETS) : 1;
    localparam int WAY_BITS  = $clog2(WAYS);
    localparam int LOG_WAYS  = $clog2(WAYS);

    // -------------------------------------------------------------------------
    // Storage arrays
    // -------------------------------------------------------------------------
    logic                             valid    [NUM_SETS-1:0][WAYS-1:0];
    logic [TAG_WIDTH-1:0]             tag_mem  [NUM_SETS-1:0][WAYS-1:0];
    logic [DATA_WIDTH-1:0]            data_mem [NUM_SETS-1:0][WAYS-1:0];

    // PLRU binary tree: WAYS-1 bits per set.
    // Nodes are 1-indexed (1..WAYS-1); stored at index node-1.
    // Bit = 0: LRU resides in left  subtree (go left  to find victim).
    // Bit = 1: LRU resides in right subtree (go right to find victim).
    logic [WAYS-2:0]                  plru_bits [NUM_SETS-1:0];

    // -------------------------------------------------------------------------
    // Set index and tag extraction (continuous assignment avoids parametric
    // part-select limitations in procedural blocks)
    // -------------------------------------------------------------------------
    logic [LOG_SETS-1:0]  set_idx;
    logic [TAG_WIDTH-1:0] tag_in;

    assign set_idx = LOG_SETS'(key_in);
    assign tag_in  = TAG_WIDTH'(key_in >> LOG_SETS);

    // -------------------------------------------------------------------------
    // Parallel hit detection: compare tag against all valid ways in set_idx
    // -------------------------------------------------------------------------
    logic [WAYS-1:0] way_hit_vec;

    always_comb begin
        for (int w = 0; w < WAYS; w++)
            way_hit_vec[w] = valid[set_idx][w] && (tag_mem[set_idx][w] == tag_in);
    end

    // Priority encoder: lowest-index hit way
    logic [WAY_BITS-1:0] hit_way;
    logic                any_hit;

    always_comb begin
        hit_way = '0;
        any_hit = 1'b0;
        for (int w = WAYS-1; w >= 0; w--) begin
            if (way_hit_vec[w]) begin
                hit_way = WAY_BITS'(w);
                any_hit = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Free (invalid) way finder: lowest-index invalid way in set_idx
    // -------------------------------------------------------------------------
    logic [WAY_BITS-1:0] free_way;
    logic                any_free;

    always_comb begin
        free_way = '0;
        any_free = 1'b0;
        for (int w = WAYS-1; w >= 0; w--) begin
            if (!valid[set_idx][w]) begin
                free_way = WAY_BITS'(w);
                any_free = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // PLRU victim selection: traverse the binary tree from root to leaf.
    // Nodes 1-indexed; left child = 2*k, right child = 2*k+1.
    // At each node follow the PLRU bit to find the LRU leaf (victim way).
    // After LOG_WAYS levels the leaf index minus WAYS gives the victim way.
    // -------------------------------------------------------------------------
    logic [WAY_BITS-1:0] plru_victim;

    always_comb begin : plru_victim_sel
        int nd;
        nd = 1;
        for (int lv = 0; lv < LOG_WAYS; lv++) begin
            if (plru_bits[set_idx][nd-1] == 1'b0)
                nd = nd * 2;        // left child  -> LRU is in left subtree
            else
                nd = nd * 2 + 1;    // right child -> LRU is in right subtree
        end
        plru_victim = WAY_BITS'(nd - WAYS);
    end

    // -------------------------------------------------------------------------
    // Write-way selection: free way if available, otherwise PLRU victim
    // -------------------------------------------------------------------------
    logic [WAY_BITS-1:0] write_way;

    always_comb
        write_way = any_free ? free_way : plru_victim;

    // -------------------------------------------------------------------------
    // PLRU update function.
    // Walk from the accessed way's leaf back to the root.  At each internal
    // node on the path:
    //   - If we arrived from the left child  (even node): set bit = 1
    //     (left subtree just used; right subtree is now LRU).
    //   - If we arrived from the right child (odd  node): set bit = 0
    //     (right subtree just used; left subtree is now LRU).
    // -------------------------------------------------------------------------
    function automatic logic [WAYS-2:0] plru_update(
        input logic [WAYS-2:0]     old_plru,
        input logic [WAY_BITS-1:0] accessed_way
    );
        automatic logic [WAYS-2:0] new_plru;
        automatic int              nd;
        automatic int              parent;
        new_plru = old_plru;
        nd       = int'(accessed_way) + WAYS;   // 1-indexed leaf
        for (int lv = 0; lv < LOG_WAYS; lv++) begin
            parent = nd / 2;
            // Even nd = left child of parent; odd nd = right child.
            if ((nd & 1) == 0)
                new_plru[parent-1] = 1'b1;  // left used -> right is now LRU
            else
                new_plru[parent-1] = 1'b0;  // right used -> left is now LRU
            nd = parent;
        end
        return new_plru;
    endfunction

    // -------------------------------------------------------------------------
    // Sequential: write, read (with PLRU update), invalidate
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < NUM_SETS; s++) begin
                plru_bits[s] <= '0;
                for (int w = 0; w < WAYS; w++) begin
                    valid[s][w]    <= 1'b0;
                    tag_mem[s][w]  <= '0;
                    data_mem[s][w] <= '0;
                end
            end
            data_out  <= '0;
            hit       <= 1'b0;
            miss      <= 1'b0;
            evict_way <= '0;
        end else begin
            hit       <= 1'b0;
            miss      <= 1'b0;
            data_out  <= '0;
            evict_way <= '0;

            if (write_en) begin
                valid[set_idx][write_way]    <= 1'b1;
                tag_mem[set_idx][write_way]  <= tag_in;
                data_mem[set_idx][write_way] <= data_in;
                plru_bits[set_idx]           <= plru_update(plru_bits[set_idx], write_way);
                evict_way                    <= write_way;
            end

            if (read_en) begin
                if (any_hit) begin
                    data_out          <= data_mem[set_idx][hit_way];
                    hit               <= 1'b1;
                    plru_bits[set_idx] <= plru_update(plru_bits[set_idx], hit_way);
                end else begin
                    miss <= 1'b1;
                end
            end

            if (invalidate_en) begin
                for (int w = 0; w < WAYS; w++) begin
                    if (way_hit_vec[w])
                        valid[set_idx][w] <= 1'b0;
                end
            end
        end
    end

endmodule
