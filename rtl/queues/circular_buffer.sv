`timescale 1ns / 1ps
//==============================================================================
// Module  : circular_buffer
// Overview: Synchronous circular / ring buffer with optional overwrite mode.
//           In normal mode (overwrite=0) the buffer behaves like a standard FIFO:
//           writes are dropped when full.  In overwrite mode (overwrite=1) a
//           write when full automatically advances the read pointer, discarding
//           the oldest entry and replacing it with the new data — the buffer
//           always contains the most recent DEPTH entries.
//
// Parameters:
//   DATA_WIDTH - Width of each data word in bits            (default: 8)
//   DEPTH      - Number of entries the buffer can hold      (default: 16)
//                DEPTH need not be a power of 2.
//
// Ports:
//   clk       - Clock input, rising-edge triggered
//   rst_n     - Asynchronous active-low reset
//   wr_en     - Write enable
//   rd_en     - Read enable; advances read pointer, registers dout when !empty
//   overwrite - When high and the buffer is full, oldest data is silently
//               overwritten; when low, writes to a full buffer are dropped
//   din       - Data input  [DATA_WIDTH-1:0]
//   dout      - Registered data output [DATA_WIDTH-1:0]
//   full      - Asserted when the buffer holds DEPTH entries
//   empty     - Asserted when the buffer holds 0 entries
//   count     - Number of valid entries currently stored [$clog2(DEPTH):0]
//
// Timing:
//   Write  : din is captured at posedge clk when wr_en && (!full || overwrite).
//   Read   : dout is updated at posedge clk when rd_en && !empty (1-cycle latency).
//   Overwrite: when wr_en && full && overwrite, wr_ptr and rd_ptr both advance
//              at posedge clk; count remains DEPTH.
//
// Insertion / Removal Semantics:
//   overwrite=0 (FIFO mode):
//     - Writes silently dropped when full.
//   overwrite=1 (ring buffer mode):
//     - Write always succeeds; if full, rd_ptr is advanced along with wr_ptr so
//       the oldest entry is discarded.  Count stays at DEPTH.
//   Simultaneous wr_en && rd_en when !full && !empty: both take effect, count
//   remains unchanged.
//
// Hardware Tradeoffs:
//   - Overwrite logic adds a mux and conditional rd_ptr advance.
//   - Registered output adds 1 cycle read latency; see showahead_fifo for zero
//     latency at the cost of a combinational output path.
//   - Memory maps to flip-flops or inferred BRAM depending on DEPTH and tool.
//==============================================================================

module circular_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   wr_en,
    input  logic                   rd_en,
    input  logic                   overwrite,
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

    // Decoded operation qualifiers
    logic do_write;       // Write occurs (including overwrite)
    logic do_overwrite;   // Overwrite specifically: write into full buffer
    logic do_read;        // Normal read: rd_en and not empty

    // --------------------------------------------------------------------------
    // Derived control signals
    // --------------------------------------------------------------------------
    assign full        = (count_r == COUNT_WIDTH'(DEPTH));
    assign empty       = (count_r == '0);
    assign count       = count_r;

    assign do_overwrite = wr_en & full & overwrite;
    assign do_write     = wr_en & (~full | overwrite);   // write succeeds
    assign do_read      = rd_en & ~empty & ~do_overwrite; // explicit consumer read

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
    // Read pointer + registered output
    // Advances either on explicit read or on overwrite (oldest entry evicted).
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            dout   <= '0;
        end else begin
            if (do_read) begin
                dout   <= mem[rd_ptr];
                rd_ptr <= (rd_ptr == PTR_MAX) ? '0 : rd_ptr + 1'b1;
            end else if (do_overwrite) begin
                // Oldest entry evicted; advance rd_ptr without updating dout
                rd_ptr <= (rd_ptr == PTR_MAX) ? '0 : rd_ptr + 1'b1;
            end
        end
    end

    // --------------------------------------------------------------------------
    // Occupancy counter
    // Overwrite: count stays at DEPTH (one in, one silently out).
    // Normal simultaneous R+W: count unchanged.
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_r <= '0;
        end else begin
            unique case ({do_write & ~do_overwrite, do_read})
                2'b10:   count_r <= count_r + 1'b1;
                2'b01:   count_r <= count_r - 1'b1;
                default: ;   // overwrite (count stays DEPTH) or no-op or simultaneous
            endcase
        end
    end

endmodule
