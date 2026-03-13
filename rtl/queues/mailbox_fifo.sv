`timescale 1ns / 1ps
//==============================================================================
// Module  : mailbox_fifo
// Overview: Synchronous FIFO with per-entry valid bits, modelling a hardware
//           mailbox.  Each storage slot carries an explicit valid flag that is
//           set on push and cleared on pop.  The valid_out port lets the
//           consumer confirm that the head entry contains meaningful data before
//           consuming it, supporting producer/consumer handshake patterns where
//           a slot may need to be inspected (peeked) without being consumed.
//
//           Entries are stored in a circular array of NUM_ENTRIES slots.  push
//           writes to the tail slot; pop advances the head pointer and clears
//           the valid bit of the consumed slot.  dout always shows the head slot
//           combinatorially (show-ahead style), and valid_out reflects whether
//           that head slot is occupied.
//
// Parameters:
//   DATA_WIDTH  - Width of each data word in bits                  (default: 8)
//   DEPTH       - Structural depth alias (not directly used)        (default: 16)
//   NUM_ENTRIES - Actual number of storage slots; defaults to DEPTH (default: DEPTH)
//
// Ports:
//   clk       - Clock input, rising-edge triggered
//   rst_n     - Asynchronous active-low reset
//   push      - Write enable; stores din in tail slot when !full
//   pop       - Read enable; invalidates head slot and advances head when !empty
//   din       - Data input  [DATA_WIDTH-1:0]
//   dout      - Combinational data output from head slot [DATA_WIDTH-1:0]
//   full      - Asserted when all NUM_ENTRIES slots are valid
//   empty     - Asserted when no slots are valid
//   count     - Number of valid entries [$clog2(NUM_ENTRIES):0]
//   valid_out - Asserted when the head slot (dout) contains valid data; consumers
//               should check this before using dout
//
// Timing:
//   Push : din is written and valid bit set at posedge clk when push && !full.
//   Pop  : head slot valid bit cleared and head pointer advanced at posedge clk
//          when pop && !empty.
//   dout / valid_out are combinational outputs — zero latency from memory.
//
// Insertion / Removal Semantics:
//   - Push is silently dropped when full.
//   - Pop is ignored when empty.
//   - Simultaneous push && pop when both are valid: count unchanged.
//   - valid_out == 0 when empty; dout shows mem contents but must not be used.
//
// Hardware Tradeoffs:
//   - Per-entry valid bits add NUM_ENTRIES flip-flops but enable the mailbox
//     handshake semantics without extra control logic.
//   - Show-ahead dout avoids a pipeline bubble on the read side.
//   - NUM_ENTRIES is independent of DEPTH for flexibility (e.g., override to
//     a non-power-of-2 value without changing DATA_WIDTH/DEPTH defaults).
//==============================================================================

module mailbox_fifo #(
    parameter int DATA_WIDTH  = 8,
    parameter int DEPTH       = 16,
    parameter int NUM_ENTRIES = DEPTH
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        push,
    input  logic                        pop,
    input  logic [DATA_WIDTH-1:0]       din,
    output logic [DATA_WIDTH-1:0]       dout,
    output logic                        full,
    output logic                        empty,
    output logic [$clog2(NUM_ENTRIES):0] count,
    output logic                        valid_out
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_WIDTH  = $clog2(NUM_ENTRIES);
    localparam int COUNT_WIDTH = $clog2(NUM_ENTRIES) + 1;
    localparam logic [ADDR_WIDTH-1:0] PTR_MAX = ADDR_WIDTH'(NUM_ENTRIES - 1);

    // --------------------------------------------------------------------------
    // Storage arrays
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem   [0:NUM_ENTRIES-1];
    logic                  valid [0:NUM_ENTRIES-1];

    // --------------------------------------------------------------------------
    // Pointers and occupancy
    // --------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]  head;          // read / pop pointer
    logic [ADDR_WIDTH-1:0]  tail;          // write / push pointer
    logic [COUNT_WIDTH-1:0] count_r;

    logic do_push;
    logic do_pop;

    // --------------------------------------------------------------------------
    // Outputs
    // --------------------------------------------------------------------------
    assign full      = (count_r == COUNT_WIDTH'(NUM_ENTRIES));
    assign empty     = (count_r == '0);
    assign count     = count_r;

    // Show-ahead: head entry data and its valid flag are always visible
    assign dout      = mem[head];
    assign valid_out = valid[head];

    assign do_push = push & ~full;
    assign do_pop  = pop  & ~empty;

    // --------------------------------------------------------------------------
    // Push: write data into tail slot and advance tail pointer
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tail <= '0;
        end else if (do_push) begin
            mem[tail] <= din;
            tail      <= (tail == PTR_MAX) ? '0 : tail + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Pop: advance head pointer
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= '0;
        end else if (do_pop) begin
            head <= (head == PTR_MAX) ? '0 : head + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Valid bit array — single driver block covering reset, push, and pop
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                valid[i] <= 1'b0;
            end
        end else begin
            if (do_push)
                valid[tail] <= 1'b1;
            if (do_pop)
                valid[head] <= 1'b0;
        end
    end

    // --------------------------------------------------------------------------
    // Occupancy counter
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_r <= '0;
        end else begin
            unique case ({do_push, do_pop})
                2'b10:   count_r <= count_r + 1'b1;
                2'b01:   count_r <= count_r - 1'b1;
                default: ;
            endcase
        end
    end

endmodule
