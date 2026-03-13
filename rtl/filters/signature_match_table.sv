// =============================================================================
// signature_match_table.sv
// =============================================================================
// Overview:
//   Associative table that stores (signature, data) pairs and performs parallel
//   lookup. All stored signatures are compared simultaneously against sig_in;
//   the lowest-index match wins (priority encoder). Used in pattern matching,
//   packet classification, and cache tag arrays.
//
// Parameters:
//   SIG_WIDTH   - Width of each signature in bits (default: 16)
//   NUM_ENTRIES - Number of (signature, data) slots (default: 16)
//   DATA_WIDTH  - Width of associated data payload (default: 8)
//
// Ports:
//   clk         - Clock (rising edge)
//   rst_n       - Active-low synchronous reset
//   insert      - Pulse: store {sig_in, data_in} in first free slot
//   lookup      - Pulse: search for sig_in; drives match/no_match/data_out
//   clear_entry - Pulse: invalidate the entry matching sig_in
//   sig_in      - Signature to insert, lookup, or clear
//   data_in     - Data payload to store on insert
//   data_out    - Registered data payload of matching entry on lookup
//   match       - Registered: lookup found a match
//   no_match    - Registered: lookup found no match
//   full        - Combinational: all NUM_ENTRIES slots are occupied
//
// Timing:
//   insert:      effect (valid bit set) visible the cycle after insert pulse.
//   lookup:      match/no_match/data_out valid the cycle after lookup pulse.
//   clear_entry: effect visible the cycle after clear_entry pulse.
//   full:        combinational, always reflects current state.
//
// Insertion Semantics:
//   Writes to the lowest-indexed invalid slot. If the table is full, insert
//   is silently dropped (caller should check 'full' before asserting insert).
//
// Removal Semantics:
//   clear_entry searches for sig_in (parallel compare) and clears valid bit of
//   the first matching entry. Does nothing if sig_in is not present.
//
// Hardware Tradeoffs:
//   Area = NUM_ENTRIES * (SIG_WIDTH + DATA_WIDTH + 1) flip-flops +
//          NUM_ENTRIES parallel comparators.
//   Lookup latency: 1 cycle (registered outputs).
//   Increasing NUM_ENTRIES increases area and may impact timing due to the
//   priority encoder depth (log2(NUM_ENTRIES) levels).
// =============================================================================

`timescale 1ns/1ps

module signature_match_table #(
    parameter int SIG_WIDTH   = 16,
    parameter int NUM_ENTRIES = 16,
    parameter int DATA_WIDTH  = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    insert,
    input  logic                    lookup,
    input  logic                    clear_entry,
    input  logic [SIG_WIDTH-1:0]    sig_in,
    input  logic [DATA_WIDTH-1:0]   data_in,
    output logic [DATA_WIDTH-1:0]   data_out,
    output logic                    match,
    output logic                    no_match,
    output logic                    full
);

    localparam int ENTRY_IDX_W = $clog2(NUM_ENTRIES);

    // Storage arrays
    logic [SIG_WIDTH-1:0]  sigs  [0:NUM_ENTRIES-1];
    logic [DATA_WIDTH-1:0] data  [0:NUM_ENTRIES-1];
    logic                  valid [0:NUM_ENTRIES-1];

    // -------------------------------------------------------------------------
    // Combinational parallel compare
    // -------------------------------------------------------------------------
    logic hit_vec   [0:NUM_ENTRIES-1]; // which entries match sig_in
    logic free_vec  [0:NUM_ENTRIES-1]; // which entries are free

    always_comb begin
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            hit_vec[i]  = valid[i] && (sigs[i] == sig_in);
            free_vec[i] = ~valid[i];
        end
    end

    // full: no free slots
    always_comb begin
        full = 1'b1;
        for (int i = 0; i < NUM_ENTRIES; i++)
            if (free_vec[i]) full = 1'b0;
    end

    // Priority encoder: first (lowest index) hit
    logic                   hit_any;
    logic [ENTRY_IDX_W-1:0] hit_idx;
    always_comb begin
        hit_any = 1'b0;
        hit_idx = '0;
        for (int i = NUM_ENTRIES-1; i >= 0; i--) begin
            if (hit_vec[i]) begin
                hit_any = 1'b1;
                hit_idx = ENTRY_IDX_W'(i);
            end
        end
    end

    // Priority encoder: first free slot for insert
    logic                   free_any;
    logic [ENTRY_IDX_W-1:0] free_idx;
    always_comb begin
        free_any = 1'b0;
        free_idx = '0;
        for (int i = NUM_ENTRIES-1; i >= 0; i--) begin
            if (free_vec[i]) begin
                free_any = 1'b1;
                free_idx = ENTRY_IDX_W'(i);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                valid[i] <= 1'b0;
                sigs[i]  <= '0;
                data[i]  <= '0;
            end
            match    <= 1'b0;
            no_match <= 1'b0;
            data_out <= '0;
        end else begin
            match    <= 1'b0;
            no_match <= 1'b0;

            // Insert into first free slot
            if (insert && free_any) begin
                sigs[free_idx]  <= sig_in;
                data[free_idx]  <= data_in;
                valid[free_idx] <= 1'b1;
            end

            // Clear entry by signature
            if (clear_entry && hit_any) begin
                valid[hit_idx] <= 1'b0;
            end

            // Lookup
            if (lookup) begin
                if (hit_any) begin
                    match    <= 1'b1;
                    no_match <= 1'b0;
                    data_out <= data[hit_idx];
                end else begin
                    match    <= 1'b0;
                    no_match <= 1'b1;
                    data_out <= '0;
                end
            end
        end
    end

endmodule
