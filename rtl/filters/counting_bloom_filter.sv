// =============================================================================
// counting_bloom_filter.sv
// =============================================================================
// Overview:
//   Counting Bloom filter - each cell holds a saturating counter instead of a
//   single bit, enabling element deletion. Probabilistic: no false negatives,
//   possible false positives.
//
// Parameters:
//   KEY_WIDTH   - Width of input key (default: 8)
//   FILTER_SIZE - Number of counter cells (default: 32)
//   NUM_HASH    - Number of independent hash functions (default: 3)
//   COUNT_BITS  - Bits per counter cell (default: 4, max count = 2^COUNT_BITS-1)
//
// Ports:
//   clk         - Clock (rising edge)
//   rst_n       - Active-low synchronous reset
//   insert      - Pulse: increment counters at all hash positions
//   remove      - Pulse: decrement counters (saturate at 0)
//   query       - Pulse: check if all hash position counters > 0
//   clear       - Pulse: reset all counters to 0
//   key_in      - Key to operate on
//   present     - Registered: possibly present (all counters > 0)
//   not_present - Registered: definitely absent (at least one counter == 0)
//
// Timing:
//   All outputs register one cycle after the operation pulse.
//
// Insertion/Removal Semantics:
//   insert: for each i, cells[h_i(key)] = min(cells[h_i(key)]+1, MAX_COUNT)
//   remove: for each i, cells[h_i(key)] = max(cells[h_i(key)]-1, 0)
//   Note: removing a key never inserted can corrupt the filter.
//
// Hardware Tradeoffs:
//   Area = FILTER_SIZE * COUNT_BITS flip-flops.
//   Increasing COUNT_BITS reduces counter overflow (false positive from wrap).
//   4-bit counters rarely saturate for typical workloads.
// =============================================================================

`timescale 1ns/1ps

module counting_bloom_filter #(
    parameter int KEY_WIDTH   = 8,
    parameter int FILTER_SIZE = 32,
    parameter int NUM_HASH    = 3,
    parameter int COUNT_BITS  = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 insert,
    input  logic                 remove,
    input  logic                 query,
    input  logic                 clear,
    input  logic [KEY_WIDTH-1:0] key_in,
    output logic                 present,
    output logic                 not_present
);

    localparam int ADDR_W     = $clog2(FILTER_SIZE);
    localparam int MAX_COUNT  = (1 << COUNT_BITS) - 1;

    localparam logic [KEY_WIDTH-1:0] PRIMES [0:7] = '{
        KEY_WIDTH'(31), KEY_WIDTH'(37), KEY_WIDTH'(41), KEY_WIDTH'(43),
        KEY_WIDTH'(47), KEY_WIDTH'(53), KEY_WIDTH'(59), KEY_WIDTH'(61)
    };

    // Counter array
    logic [COUNT_BITS-1:0] cells [0:FILTER_SIZE-1];

    // Hash indices
    logic [ADDR_W-1:0] hash_idx [0:NUM_HASH-1];

    generate
        genvar i;
        for (i = 0; i < NUM_HASH; i++) begin : gen_hash
            localparam int PROD_W = KEY_WIDTH + 8;
            logic [PROD_W-1:0] product;
            always_comb begin
                product     = (PROD_W'(key_in)) * (PROD_W'(PRIMES[i]));
                hash_idx[i] = ADDR_W'(product % ADDR_W'(FILTER_SIZE));
            end
        end
    endgenerate

    // Query check (combinational)
    logic query_hit;
    always_comb begin
        query_hit = 1'b1;
        for (int j = 0; j < NUM_HASH; j++)
            if (cells[hash_idx[j]] == '0) query_hit = 1'b0;
    end

    // Sequential update
    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            for (int k = 0; k < FILTER_SIZE; k++) cells[k] <= '0;
            present     <= 1'b0;
            not_present <= 1'b0;
        end else begin
            present     <= 1'b0;
            not_present <= 1'b0;

            if (insert) begin
                for (int j = 0; j < NUM_HASH; j++) begin
                    if (cells[hash_idx[j]] != COUNT_BITS'(MAX_COUNT))
                        cells[hash_idx[j]] <= cells[hash_idx[j]] + 1'b1;
                end
            end

            if (remove) begin
                for (int j = 0; j < NUM_HASH; j++) begin
                    if (cells[hash_idx[j]] != '0)
                        cells[hash_idx[j]] <= cells[hash_idx[j]] - 1'b1;
                end
            end

            if (query) begin
                present     <= query_hit;
                not_present <= ~query_hit;
            end
        end
    end

endmodule
