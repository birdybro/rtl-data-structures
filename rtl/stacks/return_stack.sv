`timescale 1ns / 1ps
//==============================================================================
// Module  : return_stack
// Project : RTL Data Structures
//
// Overview:
//   Specialised synchronous LIFO stack for storing subroutine / function
//   return addresses, mirroring the call-stack mechanism found in processor
//   micro-architectures.  On a CALL instruction the current program counter
//   (or link address) is pushed; on a RETURN instruction the most-recently
//   saved address is popped and presented on pc_out, allowing the processor
//   to resume execution at the correct point.
//
//   Internally the module is a register-file-based LIFO identical in structure
//   to the generic stack, but with CPU-centric port names and a word width
//   parameterised by ADDR_WIDTH rather than DATA_WIDTH.
//
// Parameters:
//   ADDR_WIDTH - Width of each return address entry in bits. Default = 16
//                Typically set to match the processor's PC width.
//   DEPTH      - Maximum call-nesting depth (number of saved addresses).
//                Default = 16.  Must be at least 4.  Need not be a power of 2.
//
// Ports:
//   clk    - Clock, rising-edge triggered.
//   rst_n  - Asynchronous active-low reset.  All state is cleared.
//   call   - Push strobe.  When high, pc_in is saved onto the return stack on
//            the next rising edge, provided the stack is not full.
//   ret    - Pop strobe.  When high, the most-recently saved address is
//            removed and appears on pc_out on the next rising edge, provided
//            the stack is not empty.
//   pc_in  - Return address (link address) to save [ADDR_WIDTH-1:0].
//   pc_out - Registered return address retrieved by ret [ADDR_WIDTH-1:0].
//            Cleared to zero when the stack empties.  Holds its last value
//            between pops.
//   full   - Combinational; high when depth == DEPTH.  Further calls are
//            silently dropped (no hardware exception in this module).
//   empty  - Combinational; high when depth == 0.  Returns are silently
//            dropped when empty.
//   depth  - Number of saved return addresses currently on the stack
//            [$clog2(DEPTH):0].
//
// Timing:
//   All writes are synchronous.  pc_out and depth update one clock after call
//   or ret.  full and empty are derived from the registered depth counter.
//
// Insertion / Removal Semantics:
//   call=1, ret=0, !full   : pc_in pushed; depth++; pc_out = pc_in.
//   call=0, ret=1, !empty  : depth--; pc_out = new top (0 if now empty).
//   call=1, ret=1, !empty  : top replaced by pc_in; depth unchanged.
//                            Models a tail-call optimisation or interrupt-
//                            return-then-call sequence.
//   call=1, ret=1,  empty  : ret is a no-op; call proceeds if !full.
//   call=1,  full          : silently ignored.
//   ret=1,   empty         : silently ignored.
//
// Hardware Tradeoffs:
//   - Register-file storage: DEPTH x ADDR_WIDTH flip-flops.
//   - A depth of 16 with ADDR_WIDTH=32 consumes 512 flip-flops.
//   - Single push / single pop per clock cycle.
//   - No overflow or underflow detection; add bounded_stack semantics if
//     hardware exception signalling is required.
//   - For processors with hardware return-address prediction, this module can
//     serve as the architectural reference model for the speculative RAS.
//==============================================================================

module return_stack #(
    parameter int ADDR_WIDTH = 16,
    parameter int DEPTH      = 16
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     call,
    input  logic                     ret,
    input  logic [ADDR_WIDTH-1:0]    pc_in,
    output logic [ADDR_WIDTH-1:0]    pc_out,
    output logic                     full,
    output logic                     empty,
    output logic [$clog2(DEPTH):0]   depth
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_W  = $clog2(DEPTH);
    localparam int COUNT_W = $clog2(DEPTH) + 1;

    // --------------------------------------------------------------------------
    // Internal storage and state
    // --------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] mem [0:DEPTH-1];
    logic [COUNT_W-1:0]    depth_r;

    // --------------------------------------------------------------------------
    // Combinational pointer helpers
    // --------------------------------------------------------------------------
    logic [ADDR_W-1:0] push_ptr;    // slot to write on call  (= depth_r)
    logic [ADDR_W-1:0] top_ptr;     // current top slot index (= depth_r - 1)
    logic [ADDR_W-1:0] below_ptr;   // one below top          (= depth_r - 2)

    assign push_ptr  = depth_r[ADDR_W-1:0];
    assign top_ptr   = depth_r[ADDR_W-1:0] - 1'b1;
    assign below_ptr = depth_r[ADDR_W-1:0] - 2'b10;

    // --------------------------------------------------------------------------
    // Status flags
    // --------------------------------------------------------------------------
    assign full  = (depth_r == COUNT_W'(DEPTH));
    assign empty = (depth_r == '0);
    assign depth = depth_r;

    // --------------------------------------------------------------------------
    // Return-stack control
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : rs_ctrl
        if (!rst_n) begin
            depth_r <= '0;
            pc_out  <= '0;
        end else begin
            if (call && !ret && !full) begin
                // ----- CALL: push return address -----
                mem[push_ptr] <= pc_in;
                depth_r       <= depth_r + 1'b1;
                pc_out        <= pc_in;

            end else if (ret && !call && !empty) begin
                // ----- RETURN: pop return address -----
                depth_r <= depth_r - 1'b1;
                // Expose the next-lower address; zero if the stack is now empty.
                pc_out  <= (depth_r >= COUNT_W'(2)) ? mem[below_ptr] : '0;

            end else if (call && ret) begin
                if (!empty) begin
                    // ----- Simultaneous CALL + RET: replace top address -----
                    // Models tail-call: return destination is overwritten with
                    // the new callee's link address; nesting depth unchanged.
                    mem[top_ptr] <= pc_in;
                    pc_out       <= pc_in;
                end else if (!full) begin
                    // Stack empty – ret is a no-op, call proceeds.
                    mem[push_ptr] <= pc_in;
                    depth_r       <= depth_r + 1'b1;
                    pc_out        <= pc_in;
                end
            end
            // call+full or ret+empty: silently ignored.
        end
    end

endmodule
