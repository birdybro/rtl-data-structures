// =============================================================================
// hash_table_fixed.sv
// =============================================================================
// Overview:
//   Fixed-size hash table with open addressing via chaining (multiple slots
//   per bucket). The hash function uses XOR-folding of the key bits to select
//   one of NUM_BUCKETS buckets. Each bucket holds SLOTS_PER_BUCKET entries.
//   All slots within the selected bucket are checked in parallel on every
//   lookup/remove, giving single-cycle operation.
//
// Parameters:
//   KEY_WIDTH        - Width of the lookup key in bits (default 8)
//   DATA_WIDTH       - Width of the data payload in bits (default 8)
//   NUM_BUCKETS      - Number of hash buckets; must be a power of 2 (default 16)
//   SLOTS_PER_BUCKET - Number of chained slots per bucket (default 4)
//
// Ports:
//   clk        - Clock (rising-edge triggered)
//   rst_n      - Asynchronous active-low reset
//   insert     - Pulse high for one cycle to insert key_in/data_in
//   lookup     - Pulse high for one cycle to search for key_in
//   remove     - Pulse high for one cycle to delete entry for key_in
//   key_in     - Key to insert / lookup / remove
//   data_in    - Data written on insert
//   data_out   - Data returned on a successful lookup (registered)
//   hit        - Asserted the cycle after a lookup/remove when key was found
//   miss       - Asserted the cycle after a lookup/remove when key was absent
//   full       - Asserted when every bucket has at least one full set of slots
//                 (combinational; conservatively indicates capacity pressure)
//   collision  - Asserted the cycle after an insert when the target bucket had
//                 no free slot (insert was dropped)
//
// Timing:
//   - Insert, lookup, remove are all initiated on the rising edge of clk.
//   - hit, miss, collision, data_out are registered outputs; results are
//     visible one cycle after the command pulse.
//
// Insertion / Removal Semantics:
//   Insert : hash key_in -> bucket index, scan slots for first invalid slot,
//            write (valid=1, key, data) there. If all slots are occupied the
//            insert is silently dropped and collision is raised.
//   Lookup : hash key_in -> bucket index, parallel-compare key_in against all
//            valid slots, return data_out of the matching slot; hit/miss set.
//   Remove : same parallel compare as lookup; matching slot is invalidated.
//
// Hardware Tradeoffs:
//   - Increasing SLOTS_PER_BUCKET reduces collisions at the cost of wider
//     parallel comparators and more flip-flop storage per bucket.
//   - NUM_BUCKETS must be a power of two for the XOR-fold hash to be simple.
//   - No dynamic memory; all storage is register-based -> area grows linearly
//     with NUM_BUCKETS * SLOTS_PER_BUCKET.
// =============================================================================

`timescale 1ns/1ps

module hash_table_fixed #(
    parameter int KEY_WIDTH        = 8,
    parameter int DATA_WIDTH       = 8,
    parameter int NUM_BUCKETS      = 16,
    parameter int SLOTS_PER_BUCKET = 4
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Commands (mutually exclusive; undefined behaviour if >1 asserted together)
    input  logic                    insert,
    input  logic                    lookup,
    input  logic                    remove,

    // Key / data
    input  logic [KEY_WIDTH-1:0]    key_in,
    input  logic [DATA_WIDTH-1:0]   data_in,
    output logic [DATA_WIDTH-1:0]   data_out,

    // Status (registered, valid one cycle after command)
    output logic                    hit,
    output logic                    miss,
    output logic                    full,
    output logic                    collision
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int BUCKET_BITS = $clog2(NUM_BUCKETS);

    // -------------------------------------------------------------------------
    // Storage arrays
    // -------------------------------------------------------------------------
    logic                  valid [NUM_BUCKETS-1:0][SLOTS_PER_BUCKET-1:0];
    logic [KEY_WIDTH-1:0]  keys  [NUM_BUCKETS-1:0][SLOTS_PER_BUCKET-1:0];
    logic [DATA_WIDTH-1:0] data  [NUM_BUCKETS-1:0][SLOTS_PER_BUCKET-1:0];

    // -------------------------------------------------------------------------
    // Hash function: XOR-fold key into BUCKET_BITS
    // -------------------------------------------------------------------------
    function automatic logic [BUCKET_BITS-1:0] hash_key(input logic [KEY_WIDTH-1:0] k);
        logic [BUCKET_BITS-1:0] h;
        integer i;
        h = '0;
        for (i = 0; i < KEY_WIDTH; i++) begin
            h[i % BUCKET_BITS] ^= k[i];
        end
        return h;
    endfunction

    // -------------------------------------------------------------------------
    // Combinational decode
    // -------------------------------------------------------------------------
    logic [BUCKET_BITS-1:0]           bucket_idx;
    logic [SLOTS_PER_BUCKET-1:0]      slot_match;      // which slots match key_in
    logic [SLOTS_PER_BUCKET-1:0]      slot_invalid;    // which slots are free
    logic [$clog2(SLOTS_PER_BUCKET):0] first_free_slot; // index of first free slot
    logic any_match;
    logic any_free;
    logic bucket_full_comb;

    always_comb begin
        bucket_idx = hash_key(key_in);

        for (int s = 0; s < SLOTS_PER_BUCKET; s++) begin
            slot_match[s]   = valid[bucket_idx][s] && (keys[bucket_idx][s] == key_in);
            slot_invalid[s] = ~valid[bucket_idx][s];
        end

        any_match = |slot_match;
        any_free  = |slot_invalid;
        bucket_full_comb = ~any_free;

        // Priority encoder: lowest free slot
        first_free_slot = '0;
        for (int s = SLOTS_PER_BUCKET-1; s >= 0; s--) begin
            if (slot_invalid[s])
                first_free_slot = $clog2(SLOTS_PER_BUCKET)'(s);
        end
    end

    // -------------------------------------------------------------------------
    // 'full' flag: all buckets are full (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        full = 1'b1;
        for (int b = 0; b < NUM_BUCKETS; b++) begin
            for (int s = 0; s < SLOTS_PER_BUCKET; s++) begin
                if (!valid[b][s])
                    full = 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Registered outputs and state update
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit       <= 1'b0;
            miss      <= 1'b0;
            collision <= 1'b0;
            data_out  <= '0;
            for (int b = 0; b < NUM_BUCKETS; b++) begin
                for (int s = 0; s < SLOTS_PER_BUCKET; s++) begin
                    valid[b][s] <= 1'b0;
                    keys [b][s] <= '0;
                    data [b][s] <= '0;
                end
            end
        end else begin
            // Default: de-assert single-cycle status flags
            hit       <= 1'b0;
            miss      <= 1'b0;
            collision <= 1'b0;

            if (insert) begin
                if (any_match) begin
                    // Key already present – update data in place
                    for (int s = 0; s < SLOTS_PER_BUCKET; s++) begin
                        if (slot_match[s])
                            data[bucket_idx][s] <= data_in;
                    end
                    hit <= 1'b1;
                end else if (any_free) begin
                    valid[bucket_idx][first_free_slot[$clog2(SLOTS_PER_BUCKET)-1:0]] <= 1'b1;
                    keys [bucket_idx][first_free_slot[$clog2(SLOTS_PER_BUCKET)-1:0]] <= key_in;
                    data [bucket_idx][first_free_slot[$clog2(SLOTS_PER_BUCKET)-1:0]] <= data_in;
                end else begin
                    collision <= 1'b1;
                end
            end else if (lookup) begin
                if (any_match) begin
                    hit <= 1'b1;
                    for (int s = 0; s < SLOTS_PER_BUCKET; s++) begin
                        if (slot_match[s])
                            data_out <= data[bucket_idx][s];
                    end
                end else begin
                    miss <= 1'b1;
                end
            end else if (remove) begin
                if (any_match) begin
                    hit <= 1'b1;
                    for (int s = 0; s < SLOTS_PER_BUCKET; s++) begin
                        if (slot_match[s])
                            valid[bucket_idx][s] <= 1'b0;
                    end
                end else begin
                    miss <= 1'b1;
                end
            end
        end
    end

endmodule
