// =============================================================================
// tagged_lookup_example.sv  –  Example: Tagged Lookup Table Usage
// =============================================================================
// Demonstrates a simple key-value store using tagged_lookup_table with a
// scoreboard_allocator to track outstanding lookups.
//
// Use case: Each lookup request is assigned a scoreboard tag. When the lookup
// completes (hit or miss), the tag is freed.
//
// Flow:
//   1. Lookup request arrives (lookup_req + lookup_key).
//   2. scoreboard_allocator issues a unique tag for this in-flight lookup.
//   3. tagged_lookup_table is queried with the key.
//   4. On the next cycle the result (hit/miss + data) is registered.
//   5. The scoreboard tag is freed so a new request can occupy that slot.
//
// Insert flow:
//   1. insert_req + insert_key + insert_data are presented.
//   2. tagged_lookup_table stores the key->data mapping.
//
// Instantiates: tagged_lookup_table, scoreboard_allocator
//
// Ports:
//   clk, rst_n
//   lookup_key[7:0]    – key to look up
//   lookup_req         – request a lookup this cycle
//   insert_key[7:0]    – key to insert
//   insert_data[7:0]   – data for inserted key
//   insert_req         – request an insert this cycle
//   lookup_hit         – lookup found the key
//   lookup_miss        – lookup did not find the key
//   lookup_data[7:0]   – returned data on hit
//   req_tag[3:0]       – assigned scoreboard tag for this lookup
//   tag_valid          – tag was successfully assigned
// =============================================================================

`timescale 1ns/1ps

`include "../rtl/associative/tagged_lookup_table.sv"
`include "../rtl/priority/scoreboard_allocator.sv"

module tagged_lookup_example #(
    parameter int KEY_WIDTH   = 8,
    parameter int DATA_WIDTH  = 8,
    parameter int TABLE_DEPTH = 16,
    parameter int NUM_TAGS    = 16,
    parameter int TAG_WIDTH   = 4
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Lookup interface
    input  logic [KEY_WIDTH-1:0]    lookup_key,
    input  logic                    lookup_req,

    // Insert interface
    input  logic [KEY_WIDTH-1:0]    insert_key,
    input  logic [DATA_WIDTH-1:0]   insert_data,
    input  logic                    insert_req,

    // Lookup result (registered, one cycle after lookup_req)
    output logic                    lookup_hit,
    output logic                    lookup_miss,
    output logic [DATA_WIDTH-1:0]   lookup_data,

    // Scoreboard tracking
    output logic [TAG_WIDTH-1:0]    req_tag,
    output logic                    tag_valid
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic                    tlt_hit;
    logic                    tlt_miss;
    logic [DATA_WIDTH-1:0]   tlt_data_out;
    logic                    tlt_full;

    logic [TAG_WIDTH-1:0]    sb_alloc_tag;
    logic                    sb_alloc_valid;
    logic                    sb_full;

    // -------------------------------------------------------------------------
    // scoreboard_allocator
    // -------------------------------------------------------------------------
    // Allocate a tag when a lookup is requested and there is space.
    // Free the tag one cycle later when the result is registered.
    // -------------------------------------------------------------------------
    logic free_tag_en;
    logic [TAG_WIDTH-1:0] free_tag_r;

    scoreboard_allocator #(
        .NUM_ENTRIES (NUM_TAGS),
        .TAG_WIDTH   (TAG_WIDTH)
    ) u_sb (
        .clk        (clk),
        .rst_n      (rst_n),
        .alloc      (lookup_req & sb_alloc_valid),
        .free       (free_tag_en),
        .alloc_tag  (sb_alloc_tag),
        .free_tag   (free_tag_r),
        .alloc_valid(sb_alloc_valid),
        .full       (sb_full)
    );

    // -------------------------------------------------------------------------
    // tagged_lookup_table
    // -------------------------------------------------------------------------
    // Insert new key-data pairs when insert_req is asserted.
    // Read (lookup) with lookup_key when lookup_req is asserted.
    // The tag stored in the table is the key itself (KEY_WIDTH == TAG_WIDTH
    // here; in a real system you might widen TAG_WIDTH as needed).
    // -------------------------------------------------------------------------
    tagged_lookup_table #(
        .DATA_WIDTH (DATA_WIDTH),
        .TAG_WIDTH  (KEY_WIDTH),
        .DEPTH      (TABLE_DEPTH)
    ) u_tlt (
        .clk        (clk),
        .rst_n      (rst_n),
        .write_en   (insert_req),
        .tag_in     (insert_key),
        .data_in    (insert_data),
        .read_en    (lookup_req),
        .data_out   (tlt_data_out),
        .hit        (tlt_hit),
        .miss       (tlt_miss),
        .invalidate (1'b0),
        .full       (tlt_full),
        .count      ()
    );

    // -------------------------------------------------------------------------
    // Result pipeline register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_hit  <= 1'b0;
            lookup_miss <= 1'b0;
            lookup_data <= '0;
            free_tag_en <= 1'b0;
            free_tag_r  <= '0;
        end else begin
            lookup_hit  <= tlt_hit;
            lookup_miss <= tlt_miss;
            lookup_data <= tlt_data_out;

            // Free the scoreboard tag one cycle after allocation
            free_tag_en <= lookup_req & sb_alloc_valid;
            free_tag_r  <= sb_alloc_tag;
        end
    end

    // -------------------------------------------------------------------------
    // Output tag assignment
    // -------------------------------------------------------------------------
    assign req_tag   = sb_alloc_tag;
    assign tag_valid = lookup_req & sb_alloc_valid;

endmodule
