// =============================================================================
// Module: priority_scheduler
// =============================================================================
// Overview:
//   Static-priority scheduler. Always grants the highest-priority requesting
//   client. Within the same priority level, round-robin arbitration prevents
//   starvation among equals.
//
// Parameters:
//   NUM_CLIENTS     - Number of clients (default 8)
//   PRIORITY_LEVELS - Number of distinct priority levels (default 4)
//   ID_WIDTH        - $clog2(NUM_CLIENTS)
//   PRIO_BITS       - $clog2(PRIORITY_LEVELS) bits per client priority field
//
// Ports:
//   clk         - System clock
//   rst_n       - Active-low synchronous reset
//   request     - Bitmask of requesting clients
//   priority_in - Flattened priorities: bits [(i+1)*PRIO_BITS-1 : i*PRIO_BITS]
//                 hold client i's priority (0=lowest, PRIORITY_LEVELS-1=highest)
//   grant       - One-hot grant output
//   grant_id    - Binary index of granted client
//   grant_valid - Asserted when a grant is issued
//   advance     - Pulse to advance round-robin pointer within same-priority group
//
// Timing:
//   - Outputs registered; 1-cycle latency.
//   - advance must be a single-cycle pulse.
//
// Hardware tradeoffs:
//   - Comparator tree over NUM_CLIENTS entries each PRIO_BITS wide.
//   - One RR pointer per priority level: PRIORITY_LEVELS * ID_WIDTH flip-flops.
// =============================================================================
`timescale 1ns/1ps

module priority_scheduler #(
    parameter int NUM_CLIENTS     = 8,
    parameter int PRIORITY_LEVELS = 4,
    parameter int ID_WIDTH        = $clog2(NUM_CLIENTS),
    parameter int PRIO_BITS       = $clog2(PRIORITY_LEVELS)
)(
    input  logic                                    clk,
    input  logic                                    rst_n,
    input  logic [NUM_CLIENTS-1:0]                  request,
    input  logic [NUM_CLIENTS*PRIO_BITS-1:0]        priority_in,
    output logic [NUM_CLIENTS-1:0]                  grant,
    output logic [ID_WIDTH-1:0]                     grant_id,
    output logic                                    grant_valid,
    input  logic                                    advance
);

    // Per-priority-level round-robin pointers
    logic [ID_WIDTH-1:0] rr_ptr [PRIORITY_LEVELS];

    // Unpacked priorities
    logic [PRIO_BITS-1:0] prio [NUM_CLIENTS];

    // Combinational results
    logic [NUM_CLIENTS-1:0] grant_comb;
    logic [ID_WIDTH-1:0]    grant_id_comb;
    logic                   grant_valid_comb;
    logic [PRIO_BITS-1:0]   win_prio_comb;

    // Unpack flattened priority_in
    always_comb begin
        for (int i = 0; i < NUM_CLIENTS; i++)
            prio[i] = priority_in[i*PRIO_BITS +: PRIO_BITS];
    end

    // Find highest priority level that has at least one requesting client
    always_comb begin
        grant_comb       = '0;
        grant_id_comb    = '0;
        grant_valid_comb = 1'b0;
        win_prio_comb    = '0;

        // Determine best priority among requesters
        for (int i = 0; i < NUM_CLIENTS; i++) begin
            if (request[i]) begin
                if (!grant_valid_comb || (prio[i] > win_prio_comb)) begin
                    grant_valid_comb = 1'b1;
                    win_prio_comb    = prio[i];
                end
            end
        end

        // Within winning priority level, apply round-robin
        if (grant_valid_comb) begin
            automatic logic [ID_WIDTH-1:0] ptr = rr_ptr[win_prio_comb];
            // Masked pass (after pointer)
            for (int i = NUM_CLIENTS-1; i >= 0; i--) begin
                if (request[i] && prio[i] == win_prio_comb && (i > int'(ptr))) begin
                    grant_comb    = NUM_CLIENTS'(1 << i);
                    grant_id_comb = ID_WIDTH'(i);
                end
            end
            // If no one found after ptr, wrap around
            if (!|grant_comb) begin
                for (int i = NUM_CLIENTS-1; i >= 0; i--) begin
                    if (request[i] && prio[i] == win_prio_comb) begin
                        grant_comb    = NUM_CLIENTS'(1 << i);
                        grant_id_comb = ID_WIDTH'(i);
                    end
                end
            end
        end
    end

    // Registered outputs + pointer update
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            grant       <= '0;
            grant_id    <= '0;
            grant_valid <= 1'b0;
            for (int i = 0; i < PRIORITY_LEVELS; i++)
                rr_ptr[i] <= '0;
        end else begin
            grant       <= grant_comb;
            grant_id    <= grant_id_comb;
            grant_valid <= grant_valid_comb;
            if (advance && grant_valid_comb)
                rr_ptr[win_prio_comb] <= grant_id_comb;
        end
    end

endmodule
