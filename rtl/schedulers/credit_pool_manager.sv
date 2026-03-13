// =============================================================================
// Module: credit_pool_manager
// =============================================================================
// Overview:
//   Per-flow credit tracker. Supports atomic add and consume operations on
//   any flow identified by flow_id. Prevents overdraft: consume is only
//   committed when sufficient credits exist (credit_ok asserted). If both
//   add_credit and consume_credit are asserted simultaneously for the same
//   flow, add takes priority before consume in the same cycle.
//
// Parameters:
//   NUM_FLOWS      - Number of independent flows (default 8)
//   CREDIT_BITS    - Width of per-flow credit counter (default 16)
//   FLOW_ID_BITS   - $clog2(NUM_FLOWS)
//
// Ports:
//   clk            - System clock
//   rst_n          - Active-low synchronous reset
//   add_credit     - Pulse: add credit_amount credits to flow flow_id
//   consume_credit - Pulse: deduct credit_amount from flow flow_id if sufficient
//   flow_id        - Target flow index
//   credit_amount  - Amount to add or consume
//   credit_ok      - Registered: consume was accepted (sufficient credits existed)
//   credit_zero    - Registered: selected flow has zero credits after update
//   total_credits  - Registered: concatenation of flow_id and its credit balance
//                    [CREDIT_BITS+FLOW_ID_BITS-1 : CREDIT_BITS] = flow_id
//                    [CREDIT_BITS-1 : 0]                         = balance
//
// Timing:
//   - Credit update takes effect on the next rising edge.
//   - credit_ok / credit_zero / total_credits are registered (1-cycle latency).
//
// Hardware tradeoffs:
//   - NUM_FLOWS * CREDIT_BITS flip-flops for credit storage.
//   - Single read-modify-write port; no simultaneous multi-flow updates.
//   - Single adder/subtractor shared for add and consume.
// =============================================================================
`timescale 1ns/1ps

module credit_pool_manager #(
    parameter int NUM_FLOWS    = 8,
    parameter int CREDIT_BITS  = 16,
    parameter int FLOW_ID_BITS = $clog2(NUM_FLOWS)
)(
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        add_credit,
    input  logic                        consume_credit,
    input  logic [FLOW_ID_BITS-1:0]     flow_id,
    input  logic [CREDIT_BITS-1:0]      credit_amount,
    output logic                        credit_ok,
    output logic                        credit_zero,
    output logic [CREDIT_BITS+FLOW_ID_BITS-1:0] total_credits
);

    logic [CREDIT_BITS-1:0] pool [NUM_FLOWS];

    // Combinational
    logic [CREDIT_BITS-1:0] cur_balance;
    logic [CREDIT_BITS-1:0] after_add;
    logic [CREDIT_BITS-1:0] after_consume;
    logic                   credit_ok_comb;
    logic                   credit_zero_comb;

    always_comb begin
        cur_balance = pool[flow_id];

        // Add credits (saturate at max)
        if (add_credit) begin
            automatic logic [CREDIT_BITS:0] sum;
            sum = {1'b0, cur_balance} + {1'b0, credit_amount};
            after_add = sum[CREDIT_BITS] ? '1 : sum[CREDIT_BITS-1:0];
        end else begin
            after_add = cur_balance;
        end

        // Consume credits (no overdraft)
        credit_ok_comb = consume_credit & (after_add >= credit_amount);
        if (credit_ok_comb)
            after_consume = after_add - credit_amount;
        else
            after_consume = after_add;

        credit_zero_comb = (after_consume == '0);
    end

    // Registered outputs and credit store
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            credit_ok    <= 1'b0;
            credit_zero  <= 1'b0;
            total_credits <= '0;
            for (int i = 0; i < NUM_FLOWS; i++)
                pool[i] <= '0;
        end else begin
            if (add_credit || (consume_credit && credit_ok_comb))
                pool[flow_id] <= after_consume;

            credit_ok    <= credit_ok_comb;
            credit_zero  <= credit_zero_comb;
            total_credits <= {flow_id, after_consume};
        end
    end

endmodule
