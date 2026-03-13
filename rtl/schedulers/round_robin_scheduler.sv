// =============================================================================
// Module: round_robin_scheduler
// =============================================================================
// Overview:
//   Rotating round-robin arbiter. A rotating pointer tracks the last-served
//   client; the next grant starts searching after that client, wrapping around.
//   The grant is held until 'advance' is pulsed, at which point the pointer
//   advances and a new winner is selected on the next cycle.
//
// Parameters:
//   NUM_CLIENTS - Number of clients competing for service (default 8)
//   ID_WIDTH    - Width of grant_id; auto-derived as $clog2(NUM_CLIENTS)
//
// Ports:
//   clk        - System clock (rising-edge triggered)
//   rst_n      - Active-low synchronous reset
//   request    - Bitmask: bit[i]=1 means client i is requesting service
//   grant      - One-hot grant output
//   grant_valid- High when at least one client is granted
//   grant_id   - Binary index of the granted client
//   advance    - Pulse: move pointer past current winner, re-arbitrate next cycle
//
// Timing:
//   - grant/grant_id/grant_valid are registered; latency = 1 cycle after request.
//   - advance must be a single-cycle pulse.
//
// Fairness:
//   - Strict round-robin order; each client gets at most one grant per round.
//
// Hardware tradeoffs:
//   - O(NUM_CLIENTS) logic for the masked-priority tree.
//   - Pointer register: $clog2(NUM_CLIENTS) bits.
// =============================================================================
`timescale 1ns/1ps

module round_robin_scheduler #(
    parameter int NUM_CLIENTS = 8,
    parameter int ID_WIDTH    = $clog2(NUM_CLIENTS)
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [NUM_CLIENTS-1:0]  request,
    output logic [NUM_CLIENTS-1:0]  grant,
    output logic                    grant_valid,
    output logic [ID_WIDTH-1:0]     grant_id,
    input  logic                    advance
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]    ptr_q;          // last-served pointer (registered)
    logic [NUM_CLIENTS-1:0] masked_req;     // requests after applying mask
    logic [NUM_CLIENTS-1:0] grant_comb;     // combinational grant
    logic                   grant_valid_comb;
    logic [ID_WIDTH-1:0]    grant_id_comb;

    // -------------------------------------------------------------------------
    // Masked priority: consider only clients *after* the pointer first,
    // then fall back to the full request vector (wrap-around).
    // -------------------------------------------------------------------------
    always_comb begin : mask_logic
        // Build mask: set bits > ptr_q
        logic [NUM_CLIENTS-1:0] mask;
        for (int i = 0; i < NUM_CLIENTS; i++) begin
            mask[i] = (i > int'(ptr_q)) ? 1'b1 : 1'b0;
        end
        masked_req = request & mask;
    end

    // -------------------------------------------------------------------------
    // Priority encoder on masked_req; fall back to full request if empty
    // -------------------------------------------------------------------------
    always_comb begin : arb_logic
        grant_comb       = '0;
        grant_id_comb    = '0;
        grant_valid_comb = 1'b0;

        // Try masked window first
        if (|masked_req) begin
            for (int i = NUM_CLIENTS-1; i >= 0; i--) begin
                if (masked_req[i]) begin
                    grant_comb       = NUM_CLIENTS'(1 << i);
                    grant_id_comb    = ID_WIDTH'(i);
                    grant_valid_comb = 1'b1;
                end
            end
        end else if (|request) begin
            // Wrap-around: lowest-indexed requesting client
            for (int i = NUM_CLIENTS-1; i >= 0; i--) begin
                if (request[i]) begin
                    grant_comb       = NUM_CLIENTS'(1 << i);
                    grant_id_comb    = ID_WIDTH'(i);
                    grant_valid_comb = 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            grant       <= '0;
            grant_valid <= 1'b0;
            grant_id    <= '0;
            ptr_q       <= '0;
        end else begin
            grant       <= grant_comb;
            grant_valid <= grant_valid_comb;
            grant_id    <= grant_id_comb;
            if (advance && grant_valid_comb)
                ptr_q <= grant_id_comb;
        end
    end

endmodule
