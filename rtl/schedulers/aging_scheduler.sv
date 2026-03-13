// =============================================================================
// Module: aging_scheduler
// =============================================================================
// Overview:
//   Aging-based priority scheduler that prevents starvation. Each requesting
//   client accumulates an age counter every cycle it is not served. The
//   effective priority is (base_priority + age), clamped to MAX_AGE. The client
//   with the highest effective priority is granted. On grant, its age resets.
//
// Parameters:
//   NUM_CLIENTS  - Number of clients (default 8)
//   MAX_AGE      - Maximum age counter value (default 15)
//   AGE_BITS     - Bits for age counter; should satisfy 2^AGE_BITS-1 >= MAX_AGE
//   ID_WIDTH     - $clog2(NUM_CLIENTS)
//   BASE_PBITS   - Bits per base-priority field (default 2 = 4 levels)
//
// Ports:
//   clk          - System clock
//   rst_n        - Active-low synchronous reset
//   request      - Bitmask of requesting clients
//   base_prio_in - Flattened base priorities (NUM_CLIENTS * BASE_PBITS wide)
//   grant        - One-hot grant output
//   grant_id     - Binary index of granted client
//   grant_valid  - Asserted when a grant is issued
//   advance      - Pulse: commit the current grant, reset winner's age
//
// Timing:
//   - Age counters increment every clock while request[i]=1 and no grant.
//   - Outputs registered; 1-cycle grant latency.
//
// Hardware tradeoffs:
//   - NUM_CLIENTS * AGE_BITS flip-flops for age state.
//   - Adder + comparator tree across NUM_CLIENTS for effective-priority selection.
// =============================================================================
`timescale 1ns/1ps

module aging_scheduler #(
    parameter int NUM_CLIENTS = 8,
    parameter int MAX_AGE     = 15,
    parameter int AGE_BITS    = 4,
    parameter int ID_WIDTH    = $clog2(NUM_CLIENTS),
    parameter int BASE_PBITS  = 2
)(
    input  logic                                    clk,
    input  logic                                    rst_n,
    input  logic [NUM_CLIENTS-1:0]                  request,
    input  logic [NUM_CLIENTS*BASE_PBITS-1:0]       base_prio_in,
    output logic [NUM_CLIENTS-1:0]                  grant,
    output logic [ID_WIDTH-1:0]                     grant_id,
    output logic                                    grant_valid,
    input  logic                                    advance
);

    localparam int EFF_BITS = AGE_BITS + BASE_PBITS + 1; // effective priority width

    logic [AGE_BITS-1:0]   age      [NUM_CLIENTS];
    logic [BASE_PBITS-1:0] base_p   [NUM_CLIENTS];
    logic [EFF_BITS-1:0]   eff_prio [NUM_CLIENTS];

    logic [NUM_CLIENTS-1:0] grant_comb;
    logic [ID_WIDTH-1:0]    grant_id_comb;
    logic                   grant_valid_comb;
    logic [EFF_BITS-1:0]    best_eff;

    // Unpack base priorities
    always_comb begin
        for (int i = 0; i < NUM_CLIENTS; i++)
            base_p[i] = base_prio_in[i*BASE_PBITS +: BASE_PBITS];
    end

    // Compute effective priorities
    always_comb begin
        for (int i = 0; i < NUM_CLIENTS; i++)
            eff_prio[i] = EFF_BITS'(base_p[i]) + EFF_BITS'(age[i]);
    end

    // Select winner: highest effective priority among requesters
    always_comb begin
        grant_comb       = '0;
        grant_id_comb    = '0;
        grant_valid_comb = 1'b0;
        best_eff         = '0;

        for (int i = 0; i < NUM_CLIENTS; i++) begin
            if (request[i]) begin
                if (!grant_valid_comb || eff_prio[i] > best_eff) begin
                    grant_valid_comb = 1'b1;
                    best_eff         = eff_prio[i];
                    grant_comb       = NUM_CLIENTS'(1 << i);
                    grant_id_comb    = ID_WIDTH'(i);
                end
            end
        end
    end

    // Age counters and registered outputs
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            grant       <= '0;
            grant_id    <= '0;
            grant_valid <= 1'b0;
            for (int i = 0; i < NUM_CLIENTS; i++)
                age[i] <= '0;
        end else begin
            grant       <= grant_comb;
            grant_id    <= grant_id_comb;
            grant_valid <= grant_valid_comb;

            for (int i = 0; i < NUM_CLIENTS; i++) begin
                if (advance && grant_valid_comb && (ID_WIDTH'(i) == grant_id_comb)) begin
                    age[i] <= '0;
                end else if (request[i] && age[i] < AGE_BITS'(MAX_AGE)) begin
                    age[i] <= age[i] + 1'b1;
                end
            end
        end
    end

endmodule
