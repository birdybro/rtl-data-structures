`timescale 1ns / 1ps
//==============================================================================
// Module  : calendar_queue
// Project : RTL Data Structures
//
// Overview:
//   Bucket-based calendar queue for time-ordered event scheduling.  Incoming
//   events are stored in one of NUM_BUCKETS buckets selected by the low
//   BUCKET_WIDTH bits of the event timestamp (event_time[BUCKET_WIDTH-1:0]).
//   Dequeue removes the event with the earliest (smallest) timestamp in the
//   bucket that matches current_time[BUCKET_WIDTH-1:0].
//
//   The design uses a flat register array of DEPTH slots, each tagged with a
//   bucket index, a timestamp, and a valid bit.  Insertion scans for a free
//   slot (O(DEPTH) combinatorial); dequeue scans the current bucket for the
//   minimum timestamp (O(DEPTH) combinatorial).  Both complete in one clock
//   cycle.
//
// Parameters:
//   DATA_WIDTH   - Width of event data payload in bits.             Default = 8
//   TIME_WIDTH   - Width of the timestamp field in bits.            Default = 16
//   NUM_BUCKETS  - Number of time buckets; should equal 2^BUCKET_WIDTH.
//                                                                   Default = 16
//   BUCKET_WIDTH - Number of low timestamp bits used as bucket key. Default = 4
//   DEPTH        - Total event storage slots across all buckets.    Default = 64
//
// Ports:
//   clk             - Clock, rising-edge triggered.
//   rst_n           - Asynchronous active-low reset.
//   insert          - Insert request; ignored when full.
//   dequeue         - Dequeue request; ignored when empty (current bucket).
//   event_data_in   - Data payload of event to insert  [DATA_WIDTH-1:0]
//   event_time_in   - Timestamp of event to insert     [TIME_WIDTH-1:0]
//   current_time    - Current simulation/wall time     [TIME_WIDTH-1:0]
//   event_data_out  - Combinatorial earliest-event data in current bucket
//                                                       [DATA_WIDTH-1:0]
//   event_time_out  - Combinatorial earliest-event time in current bucket
//                                                       [TIME_WIDTH-1:0]
//   empty           - Asserted when the current bucket has no valid events.
//   full            - Asserted when all DEPTH storage slots are occupied.
//
// Timing:
//   insert:  free slot allocated and event written at posedge clk when !full.
//   dequeue: earliest event in current bucket removed at posedge clk when
//            !empty (current bucket).
//   event_data_out / event_time_out are combinatorial; they update
//   immediately as current_time or storage changes.
//   full and empty are combinatorial, derived from valid bits.
//
// Insertion / Removal Semantics:
//   - Bucket assignment: bucket = event_time_in[BUCKET_WIDTH-1:0].
//   - Dequeue bucket:    bucket = current_time[BUCKET_WIDTH-1:0].
//   - insert when full: silently dropped.
//   - dequeue when empty (no event in current bucket): silently dropped.
//   - Simultaneous insert && dequeue (both valid): dequeue executes first,
//     then insert fills the just-freed slot (count unchanged).
//   - Events in buckets other than the current bucket are unaffected by
//     dequeue; advancing current_time exposes the next bucket.
//
// Hardware Tradeoffs:
//   - O(DEPTH) combinatorial scan for both insert (free slot) and dequeue
//     (minimum timestamp in bucket); timing grows linearly with DEPTH.
//   - Flat storage avoids per-bucket capacity limits but costs DEPTH valid
//     bits and a full scan every cycle.
//   - For NUM_BUCKETS != 2^BUCKET_WIDTH, the bucket mapping is still by low
//     bits; ensure NUM_BUCKETS <= 2^BUCKET_WIDTH to avoid unused buckets.
//   - Storage: DEPTH * (DATA_WIDTH + TIME_WIDTH + 1) flip-flops.
//==============================================================================

module calendar_queue #(
    parameter int DATA_WIDTH   = 8,
    parameter int TIME_WIDTH   = 16,
    parameter int NUM_BUCKETS  = 16,
    parameter int BUCKET_WIDTH = 4,
    parameter int DEPTH        = 64
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    insert,
    input  logic                    dequeue,
    input  logic [DATA_WIDTH-1:0]   event_data_in,
    input  logic [TIME_WIDTH-1:0]   event_time_in,
    input  logic [TIME_WIDTH-1:0]   current_time,
    output logic [DATA_WIDTH-1:0]   event_data_out,
    output logic [TIME_WIDTH-1:0]   event_time_out,
    output logic                    empty,
    output logic                    full
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int IDX_W   = $clog2(DEPTH);        // Bits for slot index
    localparam int BKT_W   = BUCKET_WIDTH;          // Alias for readability

    // --------------------------------------------------------------------------
    // Storage arrays
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]  ev_data [0:DEPTH-1];
    logic [TIME_WIDTH-1:0]  ev_time [0:DEPTH-1];
    logic                   ev_valid[0:DEPTH-1];

    // --------------------------------------------------------------------------
    // Bucket key extraction
    // --------------------------------------------------------------------------
    logic [BKT_W-1:0] cur_bucket;
    assign cur_bucket = current_time[BKT_W-1:0];

    // --------------------------------------------------------------------------
    // Combinatorial: find earliest event in the current bucket
    // --------------------------------------------------------------------------
    logic [IDX_W-1:0]   deq_idx;       // Slot index of earliest event
    logic [TIME_WIDTH-1:0] deq_time_c; // Its timestamp (for comparison)
    logic               deq_valid_c;   // At least one event in current bucket

    always_comb begin
        deq_idx     = '0;
        deq_time_c  = '1;  // All-ones sentinel (larger than any real timestamp)
        deq_valid_c = 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            if (ev_valid[i] &&
                ev_time[i][BKT_W-1:0] == cur_bucket &&
                (!deq_valid_c || ev_time[i] < deq_time_c)) begin
                deq_idx     = IDX_W'(i);
                deq_time_c  = ev_time[i];
                deq_valid_c = 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Combinatorial: find first free slot for insertion
    // --------------------------------------------------------------------------
    logic [IDX_W-1:0]  ins_idx;     // First free slot
    logic              ins_avail;   // A free slot exists

    always_comb begin
        ins_idx   = '0;
        ins_avail = 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            if (!ev_valid[i] && !ins_avail) begin
                ins_idx   = IDX_W'(i);
                ins_avail = 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Status flags and combinatorial outputs
    // --------------------------------------------------------------------------
    assign empty          = !deq_valid_c;                // No event in cur bucket
    assign full           = !ins_avail;                  // No free slot
    assign event_data_out = deq_valid_c ? ev_data[deq_idx] : '0;
    assign event_time_out = deq_valid_c ? ev_time[deq_idx] : '0;

    // --------------------------------------------------------------------------
    // Effective operation flags
    // --------------------------------------------------------------------------
    logic do_insert, do_dequeue;
    assign do_insert  = insert  && !full;
    assign do_dequeue = dequeue && !empty;

    // --------------------------------------------------------------------------
    // Sequential logic
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                ev_valid[i] <= 1'b0;
                ev_data[i]  <= '0;
                ev_time[i]  <= '0;
            end
        end else begin
            unique case ({do_insert, do_dequeue})

                // ---- insert only ----
                2'b10: begin
                    ev_data[ins_idx]  <= event_data_in;
                    ev_time[ins_idx]  <= event_time_in;
                    ev_valid[ins_idx] <= 1'b1;
                end

                // ---- dequeue only: invalidate earliest slot in current bucket ----
                2'b01: begin
                    ev_valid[deq_idx] <= 1'b0;
                end

                // ---- simultaneous: dequeue frees a slot, then insert fills it ----
                // deq_idx is freed; a fresh scan for ins_idx would pick it up,
                // but since we execute both combinatorially, we directly write
                // into deq_idx to keep count stable (no net change).
                2'b11: begin
                    ev_data[deq_idx]  <= event_data_in;
                    ev_time[deq_idx]  <= event_time_in;
                    ev_valid[deq_idx] <= 1'b1;  // Keep valid; overwrite with new event
                end

                default: ;  // No operation

            endcase
        end
    end

endmodule
