`timescale 1ns / 1ps
//==============================================================================
// Module  : priority_queue_linear
// Project : RTL Data Structures
//
// Overview:
//   Synchronous priority queue backed by a dense register array.  A priority
//   encoder scans all valid entries to locate the element with the lowest
//   numeric priority value (highest logical priority) on every cycle.  Pushes
//   append to the end of the array in O(1) time.  Pops remove the minimum-
//   priority entry and compact the array in O(DEPTH) time (one clock cycle,
//   with the compaction logic unrolled by the synthesizer).  dout and
//   priority_out are combinatorial "showahead" outputs that always reflect
//   the current highest-priority element.
//
// Parameters:
//   DATA_WIDTH     - Width of each data payload in bits.       Default = 8
//   PRIORITY_WIDTH - Width of the priority field in bits.      Default = 4
//   DEPTH          - Maximum number of entries.                Default = 16
//
// Ports:
//   clk          - Clock, rising-edge triggered.
//   rst_n        - Asynchronous active-low reset.
//   push         - Enqueue request; ignored when full.
//   pop          - Dequeue request; ignored when empty.
//   din          - Data word to enqueue         [DATA_WIDTH-1:0]
//   priority_in  - Priority of the new entry    [PRIORITY_WIDTH-1:0]
//   dout         - Combinatorial highest-priority data output [DATA_WIDTH-1:0]
//   priority_out - Combinatorial highest-priority value       [PRIORITY_WIDTH-1:0]
//   full         - Asserted when count == DEPTH.
//   empty        - Asserted when count == 0.
//   count        - Number of valid entries       [$clog2(DEPTH):0]
//
// Timing:
//   push: din/priority_in captured at posedge clk when push && !full.
//   pop : minimum-priority entry removed at posedge clk when pop && !empty.
//   dout / priority_out are purely combinatorial; they update immediately as
//   the register array changes (no pipeline latency).
//   full / empty / count are registered and update one cycle after push/pop.
//
// Insertion / Removal Semantics:
//   - Lower numeric priority value = higher logical priority (min-priority).
//   - push is silently dropped when full.
//   - pop is silently dropped when empty.
//   - Simultaneous push && pop (both valid): the current minimum entry is
//     removed, the array is compacted, and the new element is appended at the
//     vacated position; count is unchanged.
//   - When multiple entries share the minimum priority, the one at the lowest
//     storage index is selected (FIFO ordering among equal-priority entries).
//
// Hardware Tradeoffs:
//   - O(1) push: simple pointer append, one write port.
//   - O(N) combinatorial priority encoder for dout/pop index.  For DEPTH=16
//     this is a small chain of comparators; timing grows linearly with DEPTH.
//   - O(N) compaction on pop: synthesizer unrolls the shift loop into DEPTH
//     parallel 2-to-1 muxes, so pop completes in exactly one clock cycle.
//   - Storage: DEPTH * (DATA_WIDTH + PRIORITY_WIDTH) flip-flops.
//   - No block-RAM inference; optimised for small, shallow queues.
//==============================================================================

module priority_queue_linear #(
    parameter int DATA_WIDTH     = 8,
    parameter int PRIORITY_WIDTH = 4,
    parameter int DEPTH          = 16
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        push,
    input  logic                        pop,
    input  logic [DATA_WIDTH-1:0]       din,
    input  logic [PRIORITY_WIDTH-1:0]   priority_in,
    output logic [DATA_WIDTH-1:0]       dout,
    output logic [PRIORITY_WIDTH-1:0]   priority_out,
    output logic                        full,
    output logic                        empty,
    output logic [$clog2(DEPTH):0]      count
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int IDX_W   = $clog2(DEPTH);       // Bits to index 0..DEPTH-1
    localparam int CNT_W   = IDX_W + 1;           // Bits to hold 0..DEPTH

    // --------------------------------------------------------------------------
    // Internal storage (dense array, always packed from index 0)
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]      data_mem [0:DEPTH-1];
    logic [PRIORITY_WIDTH-1:0]  prio_mem [0:DEPTH-1];
    logic [CNT_W-1:0]           count_r;

    // --------------------------------------------------------------------------
    // Status flags
    // --------------------------------------------------------------------------
    assign full  = (count_r == CNT_W'(DEPTH));
    assign empty = (count_r == '0);
    assign count = count_r;

    // --------------------------------------------------------------------------
    // Combinatorial priority encoder: locate minimum-priority entry
    // --------------------------------------------------------------------------
    logic [IDX_W-1:0]        min_idx;
    logic [PRIORITY_WIDTH-1:0] min_prio_val;

    always_comb begin
        min_idx      = '0;
        min_prio_val = '1;  // All-ones = largest numeric value (sentinel)
        for (int i = 0; i < DEPTH; i++) begin
            if (IDX_W'(i) < count_r[IDX_W-1:0]) begin  // Only consider valid entries
                if (prio_mem[i] < min_prio_val) begin
                    min_prio_val = prio_mem[i];
                    min_idx      = IDX_W'(i);
                end
            end
        end
    end

    // Showahead outputs: always show the current highest-priority item.
    // Undefined (zero) when queue is empty.
    assign dout         = empty ? '0 : data_mem[min_idx];
    assign priority_out = empty ? '1 : prio_mem[min_idx];

    // --------------------------------------------------------------------------
    // Push / pop sequencer
    // --------------------------------------------------------------------------
    logic do_push, do_pop;
    assign do_push = push & ~full;
    assign do_pop  = pop  & ~empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_r <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                data_mem[i] <= '0;
                prio_mem[i] <= '1;
            end
        end else begin
            unique case ({do_push, do_pop})

                // ---- push only: append at the end ----
                2'b10: begin
                    data_mem[count_r[IDX_W-1:0]] <= din;
                    prio_mem[count_r[IDX_W-1:0]] <= priority_in;
                    count_r <= count_r + 1'b1;
                end

                // ---- pop only: remove min, compact array ----
                2'b01: begin
                    // Shift all entries above min_idx down by one position.
                    // The synthesizer unrolls this into parallel muxes.
                    for (int i = 0; i < DEPTH - 1; i++) begin
                        if (IDX_W'(i) >= min_idx &&
                            IDX_W'(i) < count_r[IDX_W-1:0] - 1'b1) begin
                            data_mem[i] <= data_mem[i+1];
                            prio_mem[i] <= prio_mem[i+1];
                        end
                    end
                    count_r <= count_r - 1'b1;
                end

                // ---- simultaneous push + pop: replace min entry, count unchanged ----
                2'b11: begin
                    // Compact the array just as in pop-only, then overwrite
                    // the last slot with the new element (non-blocking semantics
                    // ensure data_mem[count_r-1] reads the pre-shift value).
                    for (int i = 0; i < DEPTH - 1; i++) begin
                        if (IDX_W'(i) >= min_idx &&
                            IDX_W'(i) < count_r[IDX_W-1:0] - 1'b1) begin
                            data_mem[i] <= data_mem[i+1];
                            prio_mem[i] <= prio_mem[i+1];
                        end
                    end
                    data_mem[count_r[IDX_W-1:0] - 1'b1] <= din;
                    prio_mem[count_r[IDX_W-1:0] - 1'b1] <= priority_in;
                    // count_r unchanged
                end

                default: ;  // No operation

            endcase
        end
    end

endmodule
