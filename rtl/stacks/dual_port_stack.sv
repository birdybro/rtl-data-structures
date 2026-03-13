`timescale 1ns / 1ps
//==============================================================================
// Module  : dual_port_stack
// Project : RTL Data Structures
//
// Overview:
//   Synchronous LIFO stack with two independent access ports (A and B) that
//   share the same register-file storage.  Each port can push or pop
//   independently in any given clock cycle.  A hardware arbiter resolves
//   simultaneous conflicting accesses and asserts the conflict output flag.
//
//   Port A always has priority over Port B when both ports attempt the same
//   class of operation (both push, or both pop) in the same cycle.
//
//   Non-conflicting cross-port operations (one port pushes while the other
//   pops) are both honoured in the same cycle: the pop captures the current
//   top element and the push writes to the (logically freed) top slot, leaving
//   the element count unchanged.
//
// Parameters:
//   DATA_WIDTH - Width of each stack entry in bits.          Default = 8
//   DEPTH      - Maximum number of entries the stack holds.  Default = 16
//                Must be at least 4.  Need not be a power of 2.
//
// Ports:
//   clk      - Clock, rising-edge triggered.
//   rst_n    - Asynchronous active-low reset.  All state is cleared.
//
//   push_a   - Port A push strobe.
//   pop_a    - Port A pop strobe.
//   din_a    - Port A data input  [DATA_WIDTH-1:0].
//   dout_a   - Port A registered data output [DATA_WIDTH-1:0].  Updated when
//              port A successfully pops.  Holds last value between pops.
//
//   push_b   - Port B push strobe.
//   pop_b    - Port B pop strobe.
//   din_b    - Port B data input  [DATA_WIDTH-1:0].
//   dout_b   - Port B registered data output [DATA_WIDTH-1:0].  Updated when
//              port B successfully pops.  Holds last value between pops.
//
//   full     - Combinational; high when count == DEPTH.
//   empty    - Combinational; high when count == 0.
//   count    - Number of valid entries currently in the stack [$clog2(DEPTH):0].
//   conflict - Combinational; high when both ports request the same operation
//              class in the same cycle (both push, or both pop).  Port B's
//              request is suppressed; Port A proceeds.
//
// Timing:
//   All writes are synchronous.  dout_a, dout_b, and count update one cycle
//   after the corresponding operation.  full, empty, and conflict are
//   combinational, derived from the registered count and input port signals.
//
// Arbitration Rules (resolved combinationally before the clock edge):
//   push_a && push_b (conflict)     : only push_a is executed; push_b dropped.
//   pop_a  && pop_b  (conflict)     : only pop_a is executed;  pop_b  dropped;
//                                     dout_a gets the top; dout_b unchanged.
//   push_a && pop_b  (no conflict)  : both execute; pop_b captures old top,
//                                     push_a writes din_a to the freed slot;
//                                     count unchanged.
//   pop_a  && push_b (no conflict)  : both execute; pop_a captures old top,
//                                     push_b writes din_b to the freed slot;
//                                     count unchanged.
//   Same-port push+pop (push_x && pop_x): push takes priority; pop is ignored.
//
//   All operations are further gated by the full / empty flags:
//   a push on a full stack (with no simultaneous pop) is silently dropped.
//   a pop on an empty stack is silently dropped.
//
// Insertion / Removal Semantics:
//   Effective port operations (after arbitration and full/empty gating) are
//   computed combinationally.  At most one net push and one net pop can occur
//   per clock cycle.
//
// Hardware Tradeoffs:
//   - Register-file storage: DEPTH x DATA_WIDTH flip-flops (shared).
//   - Arbitration logic: small combinational priority mux, negligible area.
//   - Single physical write port; simultaneous push+pop uses read-modify-write
//     on the same top-of-stack slot (no dual-write-port memory required).
//   - Two separate dout registers (one per port) add DATA_WIDTH flip-flops.
//   - For high-throughput designs consider a banked or ping-pong stack instead.
//==============================================================================

module dual_port_stack #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Port A
    input  logic                    push_a,
    input  logic                    pop_a,
    input  logic [DATA_WIDTH-1:0]   din_a,
    output logic [DATA_WIDTH-1:0]   dout_a,

    // Port B
    input  logic                    push_b,
    input  logic                    pop_b,
    input  logic [DATA_WIDTH-1:0]   din_b,
    output logic [DATA_WIDTH-1:0]   dout_b,

    // Shared status
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  count,
    output logic                    conflict
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_W  = $clog2(DEPTH);
    localparam int COUNT_W = $clog2(DEPTH) + 1;

    // --------------------------------------------------------------------------
    // Internal storage and state
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [COUNT_W-1:0]    count_r;

    // --------------------------------------------------------------------------
    // Combinational pointer helpers
    // --------------------------------------------------------------------------
    logic [ADDR_W-1:0] push_ptr;    // next empty slot    (= count_r)
    logic [ADDR_W-1:0] top_ptr;     // current top index  (= count_r - 1)
    logic [ADDR_W-1:0] below_ptr;   // below-top index    (= count_r - 2)

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
    // Arbitration (combinational)
    //
    // Conflict: both ports request the same operation class simultaneously.
    // Port A wins; Port B's conflicting request is suppressed.
    //
    // Same-port simultaneous push+pop: push takes priority over pop on that
    // port (pop is suppressed for the offending port only).
    //
    // Effective signals after arbitration (before full/empty gating):
    //   eff_push_a – port A push will proceed
    //   eff_push_b – port B push will proceed (blocked if push_a also active)
    //   eff_pop_a  – port A pop  will proceed (blocked if push_a also active
    //                on same port)
    //   eff_pop_b  – port B pop  will proceed (blocked if push_b, pop_a, or
    //                push_a && pop_b=conflict scenarios apply)
    // --------------------------------------------------------------------------
    logic eff_push_a, eff_push_b, eff_pop_a, eff_pop_b;

    always_comb begin : arbitrate
        // Conflict flag: both ports request the same class
        conflict = (push_a && push_b) || (pop_a && pop_b);

        // Same-port: push wins over pop on each port
        eff_push_a = push_a;
        eff_pop_a  = pop_a  && !push_a;   // suppress pop_a if push_a active

        // Port B push: blocked if port A is also pushing (conflict, A wins)
        eff_push_b = push_b && !push_a;

        // Port B pop: blocked if push_b active on same port, OR if pop_a is
        // active (conflict, A wins)
        eff_pop_b  = pop_b  && !push_b && !pop_a;
    end

    // --------------------------------------------------------------------------
    // Derive net operation for this cycle (at most one push, one pop)
    //
    // net_push   – a push will actually occur
    // net_pop    – a pop will actually occur
    // push_data  – data to be pushed (A has priority)
    // pop_to_a   – the pop result goes to port A's output register
    // pop_to_b   – the pop result goes to port B's output register
    // --------------------------------------------------------------------------
    logic                  net_push, net_pop;
    logic [DATA_WIDTH-1:0] push_data;
    logic                  pop_to_a, pop_to_b;

    always_comb begin : net_ops
        // Push: A has priority (eff_push_b already has !push_a)
        net_push  = (eff_push_a && !full) || (eff_push_b && !full);
        push_data = eff_push_a ? din_a : din_b;

        // Pop: A has priority (eff_pop_b already has !pop_a)
        net_pop   = (eff_pop_a && !empty) || (eff_pop_b && !empty);
        pop_to_a  = eff_pop_a && !empty;
        pop_to_b  = eff_pop_b && !empty;
    end

    // --------------------------------------------------------------------------
    // Stack control
    //
    // Four mutually-exclusive effective scenarios after gating:
    //   1. push only       – write push_data to push_ptr; count++
    //   2. pop  only       – count--; expose new top
    //   3. push + pop      – replace top with push_data; count unchanged
    //                        (pop frees a slot so push always succeeds here)
    //   4. no operation    – count and memory unchanged
    //
    // dout_a updates only when pop_to_a; dout_b only when pop_to_b.
    // When push+pop: the pop captures the old top before the push overwrites it.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : stack_ctrl
        if (!rst_n) begin
            count_r <= '0;
            dout_a  <= '0;
            dout_b  <= '0;
        end else begin
            unique case ({net_push, net_pop})

                2'b10: begin
                    // ----- Push only -----
                    mem[push_ptr] <= push_data;
                    count_r       <= count_r + 1'b1;
                end

                2'b01: begin
                    // ----- Pop only -----
                    count_r <= count_r - 1'b1;
                    if (pop_to_a)
                        dout_a <= mem[top_ptr];
                    if (pop_to_b)
                        dout_b <= mem[top_ptr];
                end

                2'b11: begin
                    // ----- Simultaneous push + pop -----
                    // Pop captures the current top; push overwrites that slot.
                    // count_r is unchanged (pop decrements, push increments).
                    if (pop_to_a)
                        dout_a <= mem[top_ptr];   // capture old top for A
                    if (pop_to_b)
                        dout_b <= mem[top_ptr];   // capture old top for B
                    mem[top_ptr] <= push_data;    // overwrite with new push data
                end

                default: ; // No operation

            endcase
        end
    end

endmodule
