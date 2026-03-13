`timescale 1ns / 1ps
//==============================================================================
// Module  : stack
// Project : RTL Data Structures
//
// Overview:
//   General-purpose synchronous LIFO (Last-In First-Out) stack implemented as
//   a static register file.  A single push and a single pop can both be
//   requested in the same clock cycle; the two operations are resolved as a
//   top-element replacement (count is unchanged).
//
// Parameters:
//   DATA_WIDTH - Width of each stack entry in bits.          Default = 8
//   DEPTH      - Maximum number of entries the stack holds.  Default = 16
//                Must be at least 4.  Need not be a power of 2.
//
// Ports:
//   clk   - Clock, rising-edge triggered.
//   rst_n - Asynchronous active-low reset.  All state is cleared.
//   push  - Push strobe.  When high, din is written to the top of the stack
//           on the next rising edge, provided the stack is not full.
//   pop   - Pop strobe.  When high, the top entry is removed on the next
//           rising edge, provided the stack is not empty.
//   din   - Data word to be pushed [DATA_WIDTH-1:0].
//   dout  - Registered top-of-stack word [DATA_WIDTH-1:0].  Updated one clock
//           after each push or pop.  Cleared to zero when the stack empties.
//   full  - Combinational; high when count == DEPTH.
//   empty - Combinational; high when count == 0.
//   count - Number of valid entries currently in the stack [$clog2(DEPTH):0].
//
// Timing:
//   All writes are synchronous (registered).  dout and count update on the
//   rising edge of clk one cycle after push/pop.  full and empty are derived
//   from the registered count and therefore also update one cycle later.
//
// Insertion / Removal Semantics:
//   push=1, pop=0, !full     : din written to mem[count]; count++; dout = din.
//   push=0, pop=1, !empty    : count--; dout = new top (0 if now empty).
//   push=1, pop=1, !empty    : top element replaced by din; count unchanged.
//   push=1, pop=1,  empty    : pop is a no-op; push proceeds if !full.
//   push=1,  full            : silently ignored (no overflow flag here).
//   pop=1,   empty           : silently ignored (no underflow flag here).
//
// Hardware Tradeoffs:
//   - Register-file storage: DEPTH x DATA_WIDTH flip-flops.
//   - No block-RAM inference; best suited for small stacks (DEPTH <= 64).
//   - Single read / single write port per clock cycle.
//   - Area and power scale linearly with DEPTH x DATA_WIDTH.
//   - Critical path: index arithmetic into the register mux for dout.
//   - See bounded_stack for overflow/underflow error detection.
//==============================================================================

module stack #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    push,
    input  logic                    pop,
    input  logic [DATA_WIDTH-1:0]   din,
    output logic [DATA_WIDTH-1:0]   dout,
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  count
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_W  = $clog2(DEPTH);       // bits needed to address mem
    localparam int COUNT_W = $clog2(DEPTH) + 1;   // bits to hold 0..DEPTH

    // --------------------------------------------------------------------------
    // Internal storage and state
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [COUNT_W-1:0]    count_r;

    // --------------------------------------------------------------------------
    // Combinational pointer helpers (ADDR_W-bit arithmetic – wrapping is safe
    // because each pointer is only consumed when guarded by the appropriate
    // empty/full check).
    // --------------------------------------------------------------------------
    logic [ADDR_W-1:0] push_ptr;    // index of next empty slot  (= count_r)
    logic [ADDR_W-1:0] top_ptr;     // index of current top      (= count_r - 1)
    logic [ADDR_W-1:0] below_ptr;   // index of element below top (= count_r - 2)

    assign push_ptr  = count_r[ADDR_W-1:0];
    assign top_ptr   = count_r[ADDR_W-1:0] - 1'b1;
    assign below_ptr = count_r[ADDR_W-1:0] - 2'b10;

    // --------------------------------------------------------------------------
    // Status flags
    // --------------------------------------------------------------------------
    assign full  = (count_r == COUNT_W'(DEPTH));
    assign empty = (count_r == '0);
    assign count = count_r;

    // --------------------------------------------------------------------------
    // Stack control – single always_ff for count, dout, and memory
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : stack_ctrl
        if (!rst_n) begin
            count_r <= '0;
            dout    <= '0;
        end else begin
            if (push && !pop && !full) begin
                // ----- Push only -----
                mem[push_ptr] <= din;
                count_r       <= count_r + 1'b1;
                dout          <= din;

            end else if (pop && !push && !empty) begin
                // ----- Pop only -----
                count_r <= count_r - 1'b1;
                // Reveal the element beneath the popped top; zero if now empty.
                dout    <= (count_r >= COUNT_W'(2)) ? mem[below_ptr] : '0;

            end else if (push && pop) begin
                if (!empty) begin
                    // ----- Simultaneous push + pop: replace top (count unchanged) -----
                    mem[top_ptr] <= din;
                    dout         <= din;
                end else if (!full) begin
                    // Stack is empty; pop is a no-op, push proceeds.
                    mem[push_ptr] <= din;
                    count_r       <= count_r + 1'b1;
                    dout          <= din;
                end
                // push + pop + full + empty cannot occur simultaneously.
            end
            // All other combinations (push+full, pop+empty) are silently ignored.
        end
    end

endmodule
