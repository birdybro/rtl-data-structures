// =============================================================================
// history_buffer.sv
// =============================================================================
// Overview:
//   Circular history buffer storing the most recent DEPTH entries. The newest
//   entry is always at offset 0; oldest at offset count-1. Reads are
//   non-destructive. When full, new writes silently overwrite the oldest entry.
//
// Parameters:
//   DATA_WIDTH - Width of each entry (default: 8)
//   DEPTH      - Maximum history depth (default: 16)
//
// Ports:
//   clk      - Clock
//   rst_n    - Active-low reset
//   write_en - Push data_in as newest entry
//   read_en  - Read entry at offset from newest (combinational via data_out)
//   rewind   - Moves read pointer to oldest entry (synchronous)
//   data_in  - Data to write
//   data_out - Data at requested offset
//   offset   - Read offset from newest (0 = newest)
//   valid_out - High when offset is within valid history
//   full     - Buffer holds DEPTH entries
//   count    - Number of valid entries
//
// Timing:
//   - write_en effect is registered; data_out is combinational
//   - rewind is registered
//
// Insertion/Removal:
//   - write_en always succeeds; overwrites oldest when full
//   - read_en is non-destructive; offset selects among valid entries
//
// Hardware Tradeoffs:
//   - Head pointer arithmetic maps offset to physical address
//   - For large DEPTH consider inferring a BRAM (add read-latency pipeline)
// =============================================================================

`timescale 1ns/1ps

module history_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       write_en,
    input  logic                       read_en,
    input  logic                       rewind,
    input  logic [DATA_WIDTH-1:0]      data_in,
    input  logic [$clog2(DEPTH)-1:0]   offset,
    output logic [DATA_WIDTH-1:0]      data_out,
    output logic                       valid_out,
    output logic                       full,
    output logic [$clog2(DEPTH):0]     count
);

    localparam int PTR_W = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0]      head;       // points to next write slot
    logic [$clog2(DEPTH):0] count_r;

    assign full  = (count_r == DEPTH[$clog2(DEPTH):0]);
    assign count = count_r;

    // -----------------------------------------------------------------------
    // Sequential
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head    <= '0;
            count_r <= '0;
            for (int i = 0; i < DEPTH; i++)
                mem[i] <= '0;
        end else begin
            if (write_en) begin
                mem[head] <= data_in;
                head      <= head + 1'b1;
                if (!full)
                    count_r <= count_r + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Combinational read: offset 0 = newest = head-1
    // -----------------------------------------------------------------------
    always_comb begin
        logic [PTR_W-1:0] rd_addr;
        // newest is at head-1; offset moves backward
        rd_addr   = head - 1'b1 - PTR_W'(offset);
        valid_out = (offset < count_r[$clog2(DEPTH)-1:0]) ||
                    (count_r == DEPTH[$clog2(DEPTH):0]);
        data_out  = (read_en && valid_out) ? mem[rd_addr] : '0;
    end

endmodule
