`timescale 1ns / 1ps
//==============================================================================
// Module  : showahead_fifo
// Overview: Synchronous FIFO with combinational (show-ahead) output.  The head
//           of the queue is always driven combinatorially onto dout from the
//           internal memory without requiring rd_en to be asserted first.  This
//           allows the consumer to inspect the next entry before deciding to
//           pop it.  rd_en advances the read pointer on the rising clock edge.
//
// Parameters:
//   DATA_WIDTH - Width of each data word in bits            (default: 8)
//   DEPTH      - Number of entries the FIFO can hold        (default: 16)
//                DEPTH need not be a power of 2.
//
// Ports:
//   clk   - Clock input, rising-edge triggered
//   rst_n - Asynchronous active-low reset
//   wr_en - Write enable; captures din into FIFO when asserted and !full
//   rd_en - Read enable; advances read pointer on the next rising edge when !empty
//   din   - Data input  [DATA_WIDTH-1:0]
//   dout  - Combinational data output — always shows mem[rd_ptr] [DATA_WIDTH-1:0]
//   full  - Asserted when FIFO occupancy equals DEPTH
//   empty - Asserted when FIFO occupancy equals 0
//   count - Number of valid entries currently in the FIFO [$clog2(DEPTH):0]
//
// Timing:
//   Write  : din is captured at posedge clk when wr_en && !full.
//   Output : dout is combinatorially derived from mem[rd_ptr] — zero read latency.
//   Pointer: rd_ptr advances at posedge clk when rd_en && !empty.
//   full / empty / count are registered and valid after the clock edge.
//
// Insertion / Removal Semantics:
//   - The head word is visible on dout as soon as it is in the FIFO (empty=0).
//   - Asserting rd_en while !empty discards the current head entry on the next
//     clock edge; dout then immediately reflects the next entry.
//   - Writes are silently dropped when full.
//   - dout is undefined (mem contents) when empty is asserted; consumers must
//     check the empty flag before using dout.
//
// Hardware Tradeoffs:
//   - Zero read latency enables single-cycle pass-through pipelines.
//   - The combinational read path from memory to dout may be timing-critical for
//     large or deeply pipelined designs; prefer simple_fifo in those cases.
//   - Memory is a flat array; synthesis typically infers distributed RAM or FFs.
//   - Non-power-of-2 depths supported via explicit wrap comparison.
//==============================================================================

module showahead_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   wr_en,
    input  logic                   rd_en,
    input  logic [DATA_WIDTH-1:0]  din,
    output logic [DATA_WIDTH-1:0]  dout,
    output logic                   full,
    output logic                   empty,
    output logic [$clog2(DEPTH):0] count
);

    // --------------------------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------------------------
    localparam int ADDR_WIDTH  = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH) + 1;
    localparam logic [ADDR_WIDTH-1:0] PTR_MAX = ADDR_WIDTH'(DEPTH - 1);

    // --------------------------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]  mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0]  wr_ptr;
    logic [ADDR_WIDTH-1:0]  rd_ptr;
    logic [COUNT_WIDTH-1:0] count_r;

    logic                   do_write;
    logic                   do_read;

    // --------------------------------------------------------------------------
    // Flag / count outputs
    // --------------------------------------------------------------------------
    assign do_write = wr_en & ~full;
    assign do_read  = rd_en & ~empty;

    assign full  = (count_r == COUNT_WIDTH'(DEPTH));
    assign empty = (count_r == '0);
    assign count = count_r;

    // --------------------------------------------------------------------------
    // Show-ahead output: combinatorially exposes the head of queue
    // --------------------------------------------------------------------------
    assign dout = mem[rd_ptr];

    // --------------------------------------------------------------------------
    // Write pointer + memory write
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (do_write) begin
            mem[wr_ptr] <= din;
            wr_ptr      <= (wr_ptr == PTR_MAX) ? '0 : wr_ptr + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Read pointer advance (no output register — dout is combinational)
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end else if (do_read) begin
            rd_ptr <= (rd_ptr == PTR_MAX) ? '0 : rd_ptr + 1'b1;
        end
    end

    // --------------------------------------------------------------------------
    // Occupancy counter
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_r <= '0;
        end else begin
            unique case ({do_write, do_read})
                2'b10:   count_r <= count_r + 1'b1;
                2'b01:   count_r <= count_r - 1'b1;
                default: ;   // 00 or simultaneous 11: count unchanged
            endcase
        end
    end

endmodule
