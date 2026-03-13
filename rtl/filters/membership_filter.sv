// =============================================================================
// membership_filter.sv
// =============================================================================
// Overview:
//   Exact membership filter using a direct-mapped bit array. The key is used
//   directly as an index into a bitmap of TABLE_SIZE bits. No false positives
//   or false negatives. Requires KEY_WIDTH == $clog2(TABLE_SIZE).
//
// Parameters:
//   KEY_WIDTH  - Width of the key; must equal $clog2(TABLE_SIZE) (default: 8)
//   TABLE_SIZE - Number of entries in the bitmap (default: 256)
//
// Ports:
//   clk        - Clock (rising edge)
//   rst_n      - Active-low synchronous reset
//   insert     - Pulse: mark key_in as member
//   remove     - Pulse: mark key_in as non-member
//   query      - Pulse: check membership of key_in
//   clear      - Pulse: remove all members
//   key_in     - Key to operate on
//   member     - Registered: key is a member
//   not_member - Registered: key is not a member
//   full       - Combinational: all entries occupied
//   count      - Combinational: number of current members
//
// Timing:
//   insert/remove/clear: effect visible the next cycle.
//   query:  member/not_member valid the cycle after query is asserted.
//   full, count: combinational, always current.
//
// Insertion/Removal Semantics:
//   insert: bitmap[key_in] = 1
//   remove: bitmap[key_in] = 0
//   Inserting an already-present key is idempotent.
//   Removing an absent key is idempotent.
//
// Hardware Tradeoffs:
//   Area = TABLE_SIZE flip-flops + $clog2(TABLE_SIZE)+1 bit popcount adder tree.
//   1-cycle latency for all operations.
//   Scales only to practical KEY_WIDTH values (<=16 typically).
// =============================================================================

`timescale 1ns/1ps

module membership_filter #(
    parameter int KEY_WIDTH  = 8,
    parameter int TABLE_SIZE = 256
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          insert,
    input  logic                          remove,
    input  logic                          query,
    input  logic                          clear,
    input  logic [KEY_WIDTH-1:0]          key_in,
    output logic                          member,
    output logic                          not_member,
    output logic                          full,
    output logic [$clog2(TABLE_SIZE):0]   count
);

    // Bitmap storage
    logic [TABLE_SIZE-1:0] bitmap;

    // Popcount (adder tree synthesised by tool)
    always_comb begin
        count = '0;
        for (int k = 0; k < TABLE_SIZE; k++)
            count = count + ($clog2(TABLE_SIZE)+1)'(bitmap[k]);
    end

    assign full = (count == ($clog2(TABLE_SIZE)+1)'(TABLE_SIZE));

    // Sequential operations
    always_ff @(posedge clk) begin
        if (!rst_n || clear) begin
            bitmap     <= '0;
            member     <= 1'b0;
            not_member <= 1'b0;
        end else begin
            member     <= 1'b0;
            not_member <= 1'b0;

            if (insert) bitmap[key_in] <= 1'b1;
            if (remove) bitmap[key_in] <= 1'b0;

            if (query) begin
                if (insert && (key_in == key_in)) begin
                    // If inserting the same key, it will be present next cycle
                    member     <= 1'b1;
                    not_member <= 1'b0;
                end else if (remove) begin
                    member     <= 1'b0;
                    not_member <= 1'b1;
                end else begin
                    member     <= bitmap[key_in];
                    not_member <= ~bitmap[key_in];
                end
            end
        end
    end

endmodule
