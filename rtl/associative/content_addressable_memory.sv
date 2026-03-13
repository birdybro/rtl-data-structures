// =============================================================================
// content_addressable_memory.sv
// =============================================================================
//
// Overview:
//   A fully associative Content Addressable Memory (CAM). All stored entries
//   are searched in parallel on every lookup cycle. The module returns the
//   lowest-index match and flags whether multiple matches exist.
//
// Parameters:
//   DATA_WIDTH  - Width of data payload per entry (default 8)
//   KEY_WIDTH   - Width of search/write key (default 8)
//   DEPTH       - Number of CAM entries (default 16)
//
// Ports:
//   clk          - Clock (rising-edge triggered)
//   rst_n        - Active-low synchronous reset
//   write_en     - Write key_in/data_in to the next free slot (1 cycle)
//   lookup_en    - Perform parallel key comparison (combinational result)
//   key_in       - Key to write or search
//   data_in      - Data payload to write
//   match_data   - Data payload of the first (lowest-index) matching entry
//   match_index  - Index of the first matching entry
//   match_found  - Asserted when at least one match exists
//   match_multiple - Asserted when more than one entry matches key_in
//   flush        - Synchronous clear of all entries (takes effect next cycle)
//
// Timing:
//   - lookup_en result (match_*) is combinational within the same cycle.
//   - write_en takes effect on the next rising edge.
//   - flush takes effect on the next rising edge.
//
// Insertion/Removal Semantics:
//   - Write: scans for the lowest-index invalid slot and writes there.
//     If no free slot exists the write is silently dropped (check full flag
//     via count == DEPTH externally if needed).
//   - There is no explicit single-entry remove; use flush to clear all.
//
// Hardware Tradeoffs:
//   - Parallel comparators scale as O(DEPTH * KEY_WIDTH) in area.
//   - Priority encoder for first-match adds O(DEPTH) logic.
//   - Suitable for small DEPTH; for large tables use hash or TCAM.
//
// =============================================================================
`timescale 1ns/1ps

module content_addressable_memory #(
    parameter int DATA_WIDTH = 8,
    parameter int KEY_WIDTH  = 8,
    parameter int DEPTH      = 16
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Write interface
    input  logic                          write_en,
    input  logic [KEY_WIDTH-1:0]          key_in,
    input  logic [DATA_WIDTH-1:0]         data_in,

    // Lookup interface
    input  logic                          lookup_en,
    output logic [DATA_WIDTH-1:0]         match_data,
    output logic [$clog2(DEPTH)-1:0]      match_index,
    output logic                          match_found,
    output logic                          match_multiple,

    // Control
    input  logic                          flush
);

    // -------------------------------------------------------------------------
    // Storage arrays
    // -------------------------------------------------------------------------
    logic [KEY_WIDTH-1:0]  cam_keys   [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] cam_data   [0:DEPTH-1];
    logic                  cam_valid  [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Parallel match vector (combinational)
    // -------------------------------------------------------------------------
    logic [DEPTH-1:0] match_vec;

    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            match_vec[i] = cam_valid[i] & lookup_en & (cam_keys[i] == key_in);
        end
    end

    // -------------------------------------------------------------------------
    // First-match priority encoder
    // -------------------------------------------------------------------------
    logic [$clog2(DEPTH)-1:0] first_match_idx;
    logic                     any_match;

    always_comb begin
        first_match_idx = '0;
        any_match       = 1'b0;
        for (int i = DEPTH-1; i >= 0; i--) begin
            if (match_vec[i]) begin
                first_match_idx = $clog2(DEPTH)'(i);
                any_match       = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Multiple-match detection
    // -------------------------------------------------------------------------
    logic [DEPTH-1:0] match_vec_no_first;
    logic             multi_match;

    always_comb begin
        match_vec_no_first = match_vec;
        if (any_match)
            match_vec_no_first[first_match_idx] = 1'b0;
        multi_match = |match_vec_no_first;
    end

    // -------------------------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------------------------
    assign match_found    = any_match;
    assign match_index    = first_match_idx;
    assign match_multiple = multi_match;
    assign match_data     = cam_data[first_match_idx];

    // -------------------------------------------------------------------------
    // Next-free-slot encoder for writes
    // -------------------------------------------------------------------------
    logic [$clog2(DEPTH)-1:0] free_slot;
    logic                     slot_available;

    always_comb begin
        free_slot      = '0;
        slot_available = 1'b0;
        for (int i = DEPTH-1; i >= 0; i--) begin
            if (!cam_valid[i]) begin
                free_slot      = $clog2(DEPTH)'(i);
                slot_available = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sequential storage update
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n || flush) begin
            for (int i = 0; i < DEPTH; i++) begin
                cam_valid[i] <= 1'b0;
                cam_keys[i]  <= '0;
                cam_data[i]  <= '0;
            end
        end else if (write_en && slot_available) begin
            cam_keys [free_slot] <= key_in;
            cam_data [free_slot] <= data_in;
            cam_valid[free_slot] <= 1'b1;
        end
    end

endmodule
