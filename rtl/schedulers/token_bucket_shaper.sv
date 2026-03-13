// =============================================================================
// Module: token_bucket_shaper
// =============================================================================
// Overview:
//   Token bucket rate limiter / traffic shaper. On each 'tick' pulse,
//   fill_rate tokens are added to the bucket (capped at burst_size). When
//   'consume' is pulsed and tokens are available, one token is removed and
//   'allow' is asserted. Simultaneous tick+consume is handled atomically.
//
// Parameters:
//   TOKEN_BITS - Width of token counter (default 16)
//   RATE_BITS  - Width of fill_rate input (default 8)
//   BURST_BITS - Width of burst_size input (default 16)
//
// Ports:
//   clk        - System clock
//   rst_n      - Active-low synchronous reset
//   tick       - Clock-enable pulse: add fill_rate tokens
//   consume    - Pulse: request to consume one token
//   token_count- Current number of tokens in the bucket
//   fill_rate  - Tokens added per tick
//   burst_size - Maximum token bucket depth (caps token_count)
//   allow      - High when consume is accepted (tokens > 0)
//   full       - High when token_count == burst_size
//   empty      - High when token_count == 0
//
// Timing:
//   - token_count updated each cycle; allow is registered (1-cycle latency).
//   - tick and consume may be asserted simultaneously.
//
// Hardware tradeoffs:
//   - Single TOKEN_BITS counter with saturation logic.
//   - Comparators for full/empty/allow flags.
// =============================================================================
`timescale 1ns/1ps

module token_bucket_shaper #(
    parameter int TOKEN_BITS = 16,
    parameter int RATE_BITS  = 8,
    parameter int BURST_BITS = 16
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    tick,
    input  logic                    consume,
    input  logic [RATE_BITS-1:0]    fill_rate,
    input  logic [BURST_BITS-1:0]   burst_size,
    output logic [TOKEN_BITS-1:0]   token_count,
    output logic                    allow,
    output logic                    full,
    output logic                    empty
);

    localparam int CALC_BITS = TOKEN_BITS + 1; // extra bit for overflow detection

    logic [CALC_BITS-1:0] tokens_next;
    logic                 allow_comb;

    // Combinational next-token calculation
    always_comb begin
        automatic logic [CALC_BITS-1:0] after_fill;
        automatic logic [CALC_BITS-1:0] after_consume;

        // Add fill_rate on tick
        after_fill = tick ? (CALC_BITS'(token_count) + CALC_BITS'(fill_rate))
                          :  CALC_BITS'(token_count);

        // Cap at burst_size
        if (after_fill > CALC_BITS'(burst_size))
            after_fill = CALC_BITS'(burst_size);

        // Consume one token if requested and available
        allow_comb = consume & (after_fill > '0);
        after_consume = allow_comb ? (after_fill - 1'b1) : after_fill;

        tokens_next = after_consume;
    end

    // Registered state
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            token_count <= '0;
            allow       <= 1'b0;
        end else begin
            token_count <= tokens_next[TOKEN_BITS-1:0];
            allow       <= allow_comb;
        end
    end

    assign full  = (token_count == TOKEN_BITS'(burst_size));
    assign empty = (token_count == '0);

endmodule
