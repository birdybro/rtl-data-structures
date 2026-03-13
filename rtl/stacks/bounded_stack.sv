`timescale 1ns / 1ps
//==============================================================================
// Module  : bounded_stack
// Project : RTL Data Structures
//
// Overview:
//   Synchronous LIFO stack with a configurable logical depth limit and
//   registered overflow / underflow error flags.  MAX_DEPTH allows the stack
//   capacity to be restricted below the physical storage size (DEPTH),
//   providing headroom reservation or runtime-partitioned shared stacks.
//
//   Overflow and underflow flags are single-cycle pulses: they are set on the
//   clock edge when the illegal condition is detected and automatically cleared
//   on the very next clock edge (i.e., they mirror the registered version of
//   the illegal-access condition).
//
// Parameters:
//   DATA_WIDTH - Width of each stack entry in bits.                Default = 8
//   DEPTH      - Physical storage depth (number of memory entries). Default = 16
//                Must be at least 4.  Need not be a power of 2.
//   MAX_DEPTH  - Logical capacity limit; triggers full when count reaches
//                MAX_DEPTH.  Must satisfy 1 <= MAX_DEPTH <= DEPTH. Default = DEPTH
//
// Ports:
//   clk       - Clock, rising-edge triggered.
//   rst_n     - Asynchronous active-low reset.  All state is cleared.
//   push      - Push strobe.  Attempts to write din to the top of the stack.
//   pop       - Pop strobe.  Attempts to remove the top element.
//   din       - Data word to be pushed [DATA_WIDTH-1:0].
//   dout      - Registered top-of-stack word [DATA_WIDTH-1:0].  Cleared to
//               zero when the stack empties.
//   full      - Combinational; high when count == MAX_DEPTH.
//   empty     - Combinational; high when count == 0.
//   overflow  - Registered single-cycle pulse; high the cycle after a push was
//               attempted while the stack was full.
//   underflow - Registered single-cycle pulse; high the cycle after a pop was
//               attempted while the stack was empty.
//   count     - Number of valid entries currently in the stack [$clog2(DEPTH):0].
//
// Timing:
//   All writes are synchronous (registered).  dout and count update one cycle
//   after push/pop.  overflow and underflow are registered: they appear one
//   cycle after the erroneous access and are automatically cleared the cycle
//   after that (single-cycle pulse duration).
//
// Insertion / Removal Semantics:
//   push=1, pop=0, !full      : din written to top; count++; dout = din.
//   push=0, pop=1, !empty     : count--; dout = new top (0 if now empty).
//   push=1, pop=1, !empty     : top replaced by din; count unchanged.
//   push=1, pop=1,  empty     : pop is a no-op; push proceeds if !full.
//   push=1, full              : ignored; overflow pulse asserted next cycle.
//   pop=1,  empty             : ignored; underflow pulse asserted next cycle.
//   push=1, pop=1, full, !empty : top replaced (overflow NOT asserted – the
//                                 simultaneous pop makes room logically).
//
// Hardware Tradeoffs:
//   - Physical register file: DEPTH x DATA_WIDTH flip-flops.
//   - MAX_DEPTH adds one comparator versus the basic stack.
//   - Overflow/underflow flags are two extra 1-bit registers with simple
//     combinational drive – negligible area overhead.
//   - For applications that only need full-depth protection, tie MAX_DEPTH=DEPTH
//     (the default) and the MAX_DEPTH comparator will be optimised away.
//==============================================================================

module bounded_stack #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16,
    parameter int MAX_DEPTH  = DEPTH   // logical capacity, <= DEPTH
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    push,
    input  logic                    pop,
    input  logic [DATA_WIDTH-1:0]   din,
    output logic [DATA_WIDTH-1:0]   dout,
    output logic                    full,
    output logic                    empty,
    output logic                    overflow,
    output logic                    underflow,
    output logic [$clog2(DEPTH):0]  count
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_W   = $clog2(DEPTH);
    localparam int COUNT_W  = $clog2(DEPTH) + 1;

    // Width-matched constants for comparisons
    localparam logic [COUNT_W-1:0] MAX_CNT  = COUNT_W'(MAX_DEPTH);
    localparam logic [COUNT_W-1:0] ZERO_CNT = '0;

    // --------------------------------------------------------------------------
    // Internal storage and state
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [COUNT_W-1:0]    count_r;

    // --------------------------------------------------------------------------
    // Combinational pointer helpers
    // --------------------------------------------------------------------------
    logic [ADDR_W-1:0] push_ptr;
    logic [ADDR_W-1:0] top_ptr;
    logic [ADDR_W-1:0] below_ptr;

    assign push_ptr  = count_r[ADDR_W-1:0];
    assign top_ptr   = count_r[ADDR_W-1:0] - 1'b1;
    assign below_ptr = count_r[ADDR_W-1:0] - 2'b10;

    // --------------------------------------------------------------------------
    // Status flags (combinational, derived from registered count)
    // --------------------------------------------------------------------------
    assign full  = (count_r == MAX_CNT);
    assign empty = (count_r == ZERO_CNT);
    assign count = count_r;

    // --------------------------------------------------------------------------
    // Overflow / underflow detection (registered single-cycle pulses)
    //   overflow  – push attempted on a stack that was already at MAX_DEPTH
    //               AND the pop does not simultaneously free a slot.
    //   underflow – pop attempted on an empty stack.
    // The flags mirror the registered erroneous-access condition; they are
    // automatically cleared the following cycle because the condition ceases.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : error_flags
        if (!rst_n) begin
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            // Overflow: push requested, stack full, and no simultaneous pop to
            // relieve the pressure.
            overflow  <= push && full  && !(pop && !empty);
            // Underflow: pop requested and stack is empty.
            underflow <= pop  && empty;
        end
    end

    // --------------------------------------------------------------------------
    // Stack control
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
                dout    <= (count_r >= COUNT_W'(2)) ? mem[below_ptr] : '0;

            end else if (push && pop) begin
                if (!empty) begin
                    // ----- Simultaneous push + pop: replace top -----
                    // Logically the pop frees a slot so push always succeeds
                    // regardless of full; no overflow is signalled.
                    mem[top_ptr] <= din;
                    dout         <= din;
                end else if (!full) begin
                    // Stack empty – pop is a no-op, push proceeds.
                    mem[push_ptr] <= din;
                    count_r       <= count_r + 1'b1;
                    dout          <= din;
                end
                // push + pop + full + empty: both are illegal, flags handled above.
            end
        end
    end

endmodule
