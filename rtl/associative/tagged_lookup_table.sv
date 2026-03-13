// =============================================================================
// tagged_lookup_table.sv
// =============================================================================
//
// Overview:
//   A cache-like associative lookup table where each entry stores a tag, data
//   payload, and a valid bit. Lookups compare the incoming tag against all
//   stored tags in parallel and return the associated data on a hit.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload per entry (default 8)
//   TAG_WIDTH   - Width of the lookup tag (default 8)
//   DEPTH       - Number of table entries (default 16)
//
// Ports:
//   clk        - Clock (rising-edge triggered)
//   rst_n      - Active-low synchronous reset
//   write_en   - Write data_in at the slot selected by tag_in (upsert)
//   read_en    - Lookup tag_in; data_out/hit/miss valid next cycle
//   invalidate - Remove the entry whose tag equals tag_in
//   tag_in     - Tag for write, read, or invalidate operation
//   data_in    - Data payload to store on write_en
//   data_out   - Data payload returned on a read hit (registered)
//   hit        - Registered: asserted the cycle after a read_en hit
//   miss       - Registered: asserted the cycle after a read_en miss
//   full       - Combinational: no free slots remain
//   count      - Combinational: number of valid entries currently stored
//
// Timing:
//   - write_en, invalidate take effect on next rising edge.
//   - read_en result (hit/miss/data_out) is registered; valid one cycle later.
//
// Insertion/Removal Semantics:
//   - Write: if tag already present, update data in-place; otherwise use the
//     lowest-index free slot.  If table is full and tag not present, write is
//     dropped.
//   - Invalidate: clears the entry whose tag matches tag_in, if any.
//
// Hardware Tradeoffs:
//   - Parallel tag comparators: O(DEPTH * TAG_WIDTH) area.
//   - Pop-count for `count` output adds O(DEPTH) adder chain.
//   - Fully associative; no set indexing—suitable for small DEPTH.
//
// =============================================================================
`timescale 1ns/1ps

module tagged_lookup_table #(
    parameter int DATA_WIDTH = 8,
    parameter int TAG_WIDTH  = 8,
    parameter int DEPTH      = 16
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // Write interface
    input  logic                      write_en,
    input  logic [TAG_WIDTH-1:0]      tag_in,
    input  logic [DATA_WIDTH-1:0]     data_in,

    // Read interface
    input  logic                      read_en,
    output logic [DATA_WIDTH-1:0]     data_out,
    output logic                      hit,
    output logic                      miss,

    // Invalidate interface
    input  logic                      invalidate,

    // Status
    output logic                      full,
    output logic [$clog2(DEPTH):0]    count
);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------
    logic [TAG_WIDTH-1:0]  tbl_tags  [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] tbl_data  [0:DEPTH-1];
    logic                  tbl_valid [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Combinational tag-match vectors
    // -------------------------------------------------------------------------
    logic [DEPTH-1:0] tag_match;   // entry exists with this tag
    logic [DEPTH-1:0] free_mask;   // entry is free

    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            tag_match[i] = tbl_valid[i] & (tbl_tags[i] == tag_in);
            free_mask[i] = ~tbl_valid[i];
        end
    end

    // -------------------------------------------------------------------------
    // Priority encoders: first tag match, first free slot
    // -------------------------------------------------------------------------
    logic [$clog2(DEPTH)-1:0] match_idx;
    logic                     any_tag_match;
    logic [$clog2(DEPTH)-1:0] free_idx;
    logic                     any_free;

    always_comb begin
        match_idx     = '0;
        any_tag_match = 1'b0;
        free_idx      = '0;
        any_free      = 1'b0;
        for (int i = DEPTH-1; i >= 0; i--) begin
            if (tag_match[i]) begin
                match_idx     = $clog2(DEPTH)'(i);
                any_tag_match = 1'b1;
            end
            if (free_mask[i]) begin
                free_idx = $clog2(DEPTH)'(i);
                any_free = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Count and full
    // -------------------------------------------------------------------------
    always_comb begin
        count = '0;
        for (int i = 0; i < DEPTH; i++)
            count = count + ($clog2(DEPTH)+1)'(tbl_valid[i]);
        full = (count == ($clog2(DEPTH)+1)'(DEPTH));
    end

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                tbl_valid[i] <= 1'b0;
                tbl_tags[i]  <= '0;
                tbl_data[i]  <= '0;
            end
            hit      <= 1'b0;
            miss     <= 1'b0;
            data_out <= '0;
        end else begin
            // Default: clear read outputs
            hit  <= 1'b0;
            miss <= 1'b0;

            // Write (upsert): update existing or insert into free slot
            if (write_en) begin
                if (any_tag_match) begin
                    tbl_data[match_idx] <= data_in;
                end else if (any_free) begin
                    tbl_tags [free_idx] <= tag_in;
                    tbl_data [free_idx] <= data_in;
                    tbl_valid[free_idx] <= 1'b1;
                end
            end

            // Invalidate: clear entry matching tag
            if (invalidate && any_tag_match) begin
                tbl_valid[match_idx] <= 1'b0;
            end

            // Read lookup
            if (read_en) begin
                if (any_tag_match) begin
                    data_out <= tbl_data[match_idx];
                    hit      <= 1'b1;
                end else begin
                    data_out <= '0;
                    miss     <= 1'b1;
                end
            end
        end
    end

endmodule
