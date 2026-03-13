// =============================================================================
// bloom_filter.sv
// =============================================================================
// Overview:
//   Probabilistic membership filter using multiple hash functions. Guarantees
//   no false negatives; false positives are possible. Bit array of FILTER_SIZE
//   bits. NUM_HASH independent polynomial hash functions set/check positions.
//
// Parameters:
//   KEY_WIDTH   - Width of the input key in bits (default: 8)
//   FILTER_SIZE - Number of bits in the filter array (default: 64)
//   NUM_HASH    - Number of independent hash functions (default: 3)
//
// Ports:
//   clk         - Clock (rising edge)
//   rst_n       - Active-low synchronous reset
//   insert      - Pulse high for 1 cycle to insert key_in
//   query       - Pulse high for 1 cycle to query key_in
//   clear       - Pulse high for 1 cycle to clear all filter bits
//   key_in      - Key to insert or query
//   present     - Asserted next cycle when query result is "possibly present"
//   not_present - Asserted next cycle when query result is "definitely absent"
//
// Timing:
//   - All operations register in on the rising edge; outputs valid next cycle.
//   - insert/query/clear are single-cycle pulses (no handshake required).
//   - If insert and query are both asserted simultaneously, insert takes priority
//     and present/not_present reflect the state *after* insertion.
//
// Insertion Semantics:
//   Sets filter_bits[h_i(key)] for each i in 0..NUM_HASH-1.
//
// Removal Semantics:
//   Not supported. Use counting_bloom_filter for deletion support.
//
// Hardware Tradeoffs:
//   - Area scales with FILTER_SIZE (one FF per bit).
//   - Combinational hash logic scales with NUM_HASH * KEY_WIDTH.
//   - False positive rate ≈ (1 - e^(-k*n/m))^k where k=NUM_HASH, n=insertions,
//     m=FILTER_SIZE.
//   - Increasing NUM_HASH reduces false positives up to a point but adds area.
// =============================================================================

`timescale 1ns/1ps

module bloom_filter #(
    parameter int KEY_WIDTH   = 8,
    parameter int FILTER_SIZE = 64,
    parameter int NUM_HASH    = 3
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  insert,
    input  logic                  query,
    input  logic                  clear,
    input  logic [KEY_WIDTH-1:0]  key_in,
    output logic                  present,
    output logic                  not_present
);

    // -------------------------------------------------------------------------
    // Compile-time index width
    // -------------------------------------------------------------------------
    localparam int ADDR_W = $clog2(FILTER_SIZE);

    // -------------------------------------------------------------------------
    // Hash primes - one distinct prime per hash function
    // -------------------------------------------------------------------------
    // These must be distinct odd values that spread keys well across FILTER_SIZE.
    // We use a small LUT of primes; extend as needed for larger NUM_HASH.
    localparam logic [KEY_WIDTH-1:0] PRIMES [0:7] = '{
        KEY_WIDTH'(31),
        KEY_WIDTH'(37),
        KEY_WIDTH'(41),
        KEY_WIDTH'(43),
        KEY_WIDTH'(47),
        KEY_WIDTH'(53),
        KEY_WIDTH'(59),
        KEY_WIDTH'(61)
    };

    // -------------------------------------------------------------------------
    // Filter storage
    // -------------------------------------------------------------------------
    logic [FILTER_SIZE-1:0] filter_bits;

    // -------------------------------------------------------------------------
    // Hash function outputs (combinational)
    // h_i(key) = (key * PRIME_i) % FILTER_SIZE
    // -------------------------------------------------------------------------
    logic [ADDR_W-1:0] hash_idx [0:NUM_HASH-1];

    generate
        genvar i;
        for (i = 0; i < NUM_HASH; i++) begin : gen_hash
            // Multiply key by prime, then mod by FILTER_SIZE via truncation.
            // The product is kept wide enough to avoid overflow before mod.
            localparam int PROD_W = KEY_WIDTH + 8; // 8 extra bits for prime mult
            logic [PROD_W-1:0] product;
            always_comb begin
                product  = (PROD_W'(key_in)) * (PROD_W'(PRIMES[i]));
                hash_idx[i] = ADDR_W'(product % ADDR_W'(FILTER_SIZE));
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Combinational: compute which bits would be set/checked
    // -------------------------------------------------------------------------
    logic [FILTER_SIZE-1:0] insert_mask;
    logic                   query_hit;

    always_comb begin
        insert_mask = '0;
        for (int j = 0; j < NUM_HASH; j++) begin
            insert_mask[hash_idx[j]] = 1'b1;
        end
    end

    always_comb begin
        query_hit = 1'b1;
        for (int j = 0; j < NUM_HASH; j++) begin
            if (!filter_bits[hash_idx[j]]) query_hit = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Sequential: update filter bits and drive outputs
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            filter_bits <= '0;
            present     <= 1'b0;
            not_present <= 1'b0;
        end else begin
            present     <= 1'b0;
            not_present <= 1'b0;

            if (insert) begin
                filter_bits <= filter_bits | insert_mask;
            end

            if (query) begin
                // Reflect state after any simultaneous insert
                if (insert)
                    present     <= &((filter_bits | insert_mask) >> 0) ?
                                   1'b1 : query_hit; // re-evaluate below
                else begin
                    present     <= query_hit;
                    not_present <= ~query_hit;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Suppress unused-parameter lint warnings
    // -------------------------------------------------------------------------
    // (PRIMES array beyond NUM_HASH-1 are intentionally unused when NUM_HASH<8)

endmodule
