// =============================================================================
// bloom_filter_system.sv  –  Example: Membership Check System
// =============================================================================
// Demonstrates a membership-check pipeline that uses a bloom_filter as a fast
// pre-filter. Items that pass the bloom filter are forwarded to an exact-match
// stage (content_addressable_memory). Items that fail the bloom filter are
// rejected immediately.
//
// Instantiates: bloom_filter, content_addressable_memory
//
// Pipeline:
//   Stage 0: Input key arrives
//   Stage 1: Bloom filter query result (combinatorial present/not_present)
//   Stage 2: If bloom says "present", forward to CAM for exact check
//
// Ports:
//   clk, rst_n
//   key_in[7:0]      – search key
//   query_valid      – key_in is valid this cycle
//   add_entry        – add key_in + data_in to both filter and CAM
//   data_in[7:0]     – data associated with key
//   result_valid     – result pipeline output is valid
//   result_hit       – exact CAM hit
//   result_data[7:0] – data from CAM on hit
//   bloom_reject     – bloom filter said "not present"; result_valid also set
// =============================================================================

`timescale 1ns/1ps

`include "../rtl/filters/bloom_filter.sv"
`include "../rtl/associative/content_addressable_memory.sv"

module bloom_filter_system #(
    parameter int KEY_WIDTH   = 8,
    parameter int DATA_WIDTH  = 8,
    parameter int FILTER_SIZE = 64,
    parameter int NUM_HASH    = 3,
    parameter int CAM_DEPTH   = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Query / insert interface
    input  logic [KEY_WIDTH-1:0]    key_in,
    input  logic                    query_valid,
    input  logic                    add_entry,
    input  logic [DATA_WIDTH-1:0]   data_in,

    // Pipeline result (registered, one cycle after query_valid)
    output logic                    result_valid,
    output logic                    result_hit,
    output logic [DATA_WIDTH-1:0]   result_data,
    output logic                    bloom_reject
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic bloom_present;
    logic bloom_not_present;

    logic cam_match_found;
    logic [DATA_WIDTH-1:0] cam_match_data;

    // Pipeline stage 1 registers
    logic                    s1_valid;
    logic [KEY_WIDTH-1:0]    s1_key;
    logic                    s1_bloom_present;

    // -------------------------------------------------------------------------
    // bloom_filter
    // -------------------------------------------------------------------------
    // insert  – set bits for add_entry
    // query   – check bits for query_valid or add_entry (simultaneous query
    //           on insert is fine; we gate lookup_en below)
    // -------------------------------------------------------------------------
    bloom_filter #(
        .KEY_WIDTH   (KEY_WIDTH),
        .FILTER_SIZE (FILTER_SIZE),
        .NUM_HASH    (NUM_HASH)
    ) u_bloom (
        .clk         (clk),
        .rst_n       (rst_n),
        .insert      (add_entry),
        .query       (query_valid),
        .clear       (1'b0),
        .key_in      (key_in),
        .present     (bloom_present),
        .not_present (bloom_not_present)
    );

    // -------------------------------------------------------------------------
    // Pipeline stage 1: register bloom result and key
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid         <= 1'b0;
            s1_key           <= '0;
            s1_bloom_present <= 1'b0;
        end else begin
            s1_valid         <= query_valid;
            s1_key           <= key_in;
            s1_bloom_present <= bloom_present;
        end
    end

    // -------------------------------------------------------------------------
    // content_addressable_memory
    // -------------------------------------------------------------------------
    // Write new entries when add_entry is asserted.
    // Look up the key from stage 1 only when bloom said "present" to avoid
    // unnecessary CAM power consumption on definite misses.
    // -------------------------------------------------------------------------
    content_addressable_memory #(
        .KEY_WIDTH  (KEY_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (CAM_DEPTH)
    ) u_cam (
        .clk           (clk),
        .rst_n         (rst_n),
        .write_en      (add_entry),
        .key_in        (s1_bloom_present ? s1_key : key_in),
        .data_in       (data_in),
        .lookup_en     (s1_valid & s1_bloom_present),
        .match_data    (cam_match_data),
        .match_index   (),
        .match_found   (cam_match_found),
        .match_multiple(),
        .flush         (1'b0)
    );

    // -------------------------------------------------------------------------
    // Pipeline stage 2: register CAM result
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_valid  <= 1'b0;
            result_hit    <= 1'b0;
            result_data   <= '0;
            bloom_reject  <= 1'b0;
        end else begin
            result_valid <= s1_valid;
            bloom_reject <= s1_valid & ~s1_bloom_present;

            if (s1_valid & s1_bloom_present) begin
                result_hit  <= cam_match_found;
                result_data <= cam_match_data;
            end else begin
                result_hit  <= 1'b0;
                result_data <= '0;
            end
        end
    end

endmodule
