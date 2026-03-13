// =============================================================================
// Module: deficit_round_robin_scheduler
// =============================================================================
// Overview:
//   Deficit Round Robin (DRR) scheduler. Each client maintains a deficit
//   counter. When a client's turn arrives, its quantum is added to its deficit.
//   The client is served (grant asserted) if deficit >= packet_size; packet_size
//   is then subtracted. This gives weighted fair queuing with variable-size
//   packets.
//
// Parameters:
//   NUM_CLIENTS  - Number of clients (default 8)
//   QUANTUM_BITS - Width of per-client quantum and deficit counter (default 8)
//   ID_WIDTH     - $clog2(NUM_CLIENTS)
//
// Ports:
//   clk         - System clock
//   rst_n       - Active-low synchronous reset
//   request     - Bitmask: bit[i]=1 client i has packets to send
//   quantum     - Flattened per-client quanta (NUM_CLIENTS * QUANTUM_BITS wide)
//   packet_size - Size of next packet for current client (QUANTUM_BITS wide)
//   grant       - Single bit: current client is granted to send
//   grant_id    - Binary index of currently-served client
//   grant_valid - High when a valid client is being served
//   advance     - Pulse: move to next client in RR order
//
// Timing:
//   - Deficit update and round-robin pointer advance occur on advance pulse.
//   - grant/grant_id/grant_valid are registered.
//
// Hardware tradeoffs:
//   - NUM_CLIENTS * QUANTUM_BITS flip-flops for deficit counters.
//   - One RR pointer of ID_WIDTH bits.
//   - Single adder/subtractor for deficit arithmetic.
// =============================================================================
`timescale 1ns/1ps

module deficit_round_robin_scheduler #(
    parameter int NUM_CLIENTS  = 8,
    parameter int QUANTUM_BITS = 8,
    parameter int ID_WIDTH     = $clog2(NUM_CLIENTS)
)(
    input  logic                                    clk,
    input  logic                                    rst_n,
    input  logic [NUM_CLIENTS-1:0]                  request,
    input  logic [NUM_CLIENTS*QUANTUM_BITS-1:0]     quantum,
    input  logic [QUANTUM_BITS-1:0]                 packet_size,
    output logic                                    grant,
    output logic [ID_WIDTH-1:0]                     grant_id,
    output logic                                    grant_valid,
    input  logic                                    advance
);

    // Deficit counters (one extra bit to avoid overflow)
    logic [QUANTUM_BITS:0] deficit [NUM_CLIENTS];
    logic [QUANTUM_BITS-1:0] q    [NUM_CLIENTS];

    // Round-robin pointer
    logic [ID_WIDTH-1:0] ptr_q;

    // Combinational
    logic                   grant_comb;
    logic [ID_WIDTH-1:0]    grant_id_comb;
    logic                   grant_valid_comb;

    // Unpack quanta
    always_comb begin
        for (int i = 0; i < NUM_CLIENTS; i++)
            q[i] = quantum[i*QUANTUM_BITS +: QUANTUM_BITS];
    end

    // Find next requesting client starting from ptr_q
    always_comb begin
        grant_comb       = 1'b0;
        grant_id_comb    = ptr_q;
        grant_valid_comb = 1'b0;

        // Scan from ptr_q upward, then wrap
        for (int i = 0; i < NUM_CLIENTS; i++) begin
            automatic int idx = (int'(ptr_q) + i) % NUM_CLIENTS;
            if (!grant_valid_comb && request[idx]) begin
                grant_valid_comb = 1'b1;
                grant_id_comb    = ID_WIDTH'(idx);
                // Grant if deficit meets packet_size
                grant_comb = (deficit[idx] >= {1'b0, packet_size}) ? 1'b1 : 1'b0;
            end
        end
    end

    // Deficit update and pointer advance
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            grant       <= 1'b0;
            grant_id    <= '0;
            grant_valid <= 1'b0;
            ptr_q       <= '0;
            for (int i = 0; i < NUM_CLIENTS; i++)
                deficit[i] <= '0;
        end else begin
            grant       <= grant_comb;
            grant_id    <= grant_id_comb;
            grant_valid <= grant_valid_comb;

            if (advance && grant_valid_comb) begin
                automatic int idx = int'(grant_id_comb);
                if (grant_comb) begin
                    // Add quantum then subtract packet_size
                    deficit[idx] <= deficit[idx] + {1'b0, q[idx]} - {1'b0, packet_size};
                end else begin
                    // No grant this round: just add quantum, advance pointer
                    deficit[idx] <= deficit[idx] + {1'b0, q[idx]};
                end
                // Advance RR pointer to next client
                ptr_q <= ID_WIDTH'((int'(grant_id_comb) + 1) % NUM_CLIENTS);
            end
        end
    end

endmodule
