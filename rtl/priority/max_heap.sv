`timescale 1ns / 1ps
//==============================================================================
// Module  : max_heap
// Project : RTL Data Structures
//
// Overview:
//   Convenience wrapper around binary_heap that permanently selects max-heap
//   ordering (MIN_HEAP=0).  The element with the largest key is always at the
//   root and is returned by remove_max.  Port names are renamed to reflect
//   maximum-extraction semantics; all behaviour, timing, and busy semantics are
//   identical to binary_heap with MIN_HEAP=0.
//
// Parameters:
//   DATA_WIDTH - Width of each data payload in bits.          Default = 8
//   KEY_WIDTH  - Width of the ordering key in bits.           Default = 8
//   DEPTH      - Maximum number of heap entries.              Default = 16
//
// Ports:
//   clk        - Clock, rising-edge triggered.
//   rst_n      - Asynchronous active-low reset.
//   insert     - Insert request.  Ignored when full or busy.
//   remove_max - Remove-maximum request.  Ignored when empty or busy.
//   key_in     - Key of element to insert                [KEY_WIDTH-1:0]
//   data_in    - Data payload of element to insert       [DATA_WIDTH-1:0]
//   max_key    - Combinatorial maximum key at the root   [KEY_WIDTH-1:0]
//   max_data   - Combinatorial maximum data at the root  [DATA_WIDTH-1:0]
//   full       - Asserted when count == DEPTH.
//   empty      - Asserted when count == 0.
//   count      - Number of valid entries                  [$clog2(DEPTH):0]
//   busy       - High while a sift operation is in progress.
//
// Timing:
//   All timing identical to binary_heap; see binary_heap for details.
//   max_key / max_data track the heap root combinatorially.
//
// Insertion / Removal Semantics:
//   - Inserts element; sifts up to maintain max-heap property.
//   - remove_max extracts and discards the element with the globally largest
//     key; new maximum is visible at max_key / max_data on the same cycle that
//     busy falls (after the sift-down completes).
//   - See binary_heap for full edge-case documentation.
//
// Hardware Tradeoffs:
//   - Zero additional logic vs. binary_heap; this module is purely structural.
//   - Synthesis tools will flatten the hierarchy unless preserve_hierarchy is
//     set; resource usage identical to an equivalent direct instantiation.
//==============================================================================

module max_heap #(
    parameter int DATA_WIDTH = 8,
    parameter int KEY_WIDTH  = 8,
    parameter int DEPTH      = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    insert,
    input  logic                    remove_max,
    input  logic [KEY_WIDTH-1:0]    key_in,
    input  logic [DATA_WIDTH-1:0]   data_in,
    output logic [KEY_WIDTH-1:0]    max_key,
    output logic [DATA_WIDTH-1:0]   max_data,
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  count,
    output logic                    busy
);

    // --------------------------------------------------------------------------
    // Instantiate binary_heap with MIN_HEAP=0 (max-heap)
    // --------------------------------------------------------------------------
    binary_heap #(
        .DATA_WIDTH ( DATA_WIDTH ),
        .KEY_WIDTH  ( KEY_WIDTH  ),
        .DEPTH      ( DEPTH      ),
        .MIN_HEAP   ( 0          )
    ) u_heap (
        .clk        ( clk        ),
        .rst_n      ( rst_n      ),
        .insert     ( insert     ),
        .remove_top ( remove_max ),
        .key_in     ( key_in     ),
        .data_in    ( data_in    ),
        .key_out    ( max_key    ),
        .data_out   ( max_data   ),
        .full       ( full       ),
        .empty      ( empty      ),
        .count      ( count      ),
        .busy       ( busy       )
    );

endmodule
