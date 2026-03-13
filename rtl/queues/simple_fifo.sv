`timescale 1ns / 1ps
//==============================================================================
// Module  : simple_fifo
// Overview: Standard synchronous FIFO with registered (clocked) output.
//           Data is written on the rising clock edge when wr_en is asserted and
//           the FIFO is not full.  Data is read on the rising clock edge when
//           rd_en is asserted and the FIFO is not empty; dout updates one cycle
//           after rd_en is sampled (registered output).  Simultaneous read and
//           write when neither full nor empty leave the count unchanged.
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
//   rd_en - Read enable; advances read pointer and registers dout when !empty
//   din   - Data input  [DATA_WIDTH-1:0]
//   dout  - Registered data output [DATA_WIDTH-1:0]
//   full  - Asserted when FIFO occupancy equals DEPTH
//   empty - Asserted when FIFO occupancy equals 0
//   count - Number of valid entries currently in the FIFO [$clog2(DEPTH):0]
//
// Timing:
//   Write: din captured at posedge clk when wr_en && !full
//   Read : dout updated at posedge clk when rd_en && !empty (1-cycle latency)
//   full/empty/count are registered and reflect the state after the current edge.
//
// Insertion / Removal Semantics:
//   - Writes are silently dropped when full is asserted.
//   - Reads are ignored (dout retains last value) when empty is asserted.
//   - Simultaneous wr_en && rd_en when both operations are valid: count unchanged.
//
// Hardware Tradeoffs:
//   - Registered output adds 1 cycle read latency but relaxes output timing.
//   - Memory maps to flip-flops for shallow FIFOs or inferred BRAM for deep ones.
//   - Separate count register gives O(1) occupancy query at the cost of one adder.
//   - Non-power-of-2 depths use explicit pointer wrap comparison (no mask trick).
//==============================================================================

module simple_fifo #(
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
    // Maximum pointer value for wrap detection
    localparam logic [ADDR_WIDTH-1:0] PTR_MAX = ADDR_WIDTH'(DEPTH - 1);

    // --------------------------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]   mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0]   wr_ptr;
    logic [ADDR_WIDTH-1:0]   rd_ptr;
    logic [COUNT_WIDTH-1:0]  count_r;

    logic                    do_write;
    logic                    do_read;

    // --------------------------------------------------------------------------
    // Flag and count outputs
    // --------------------------------------------------------------------------
    assign do_write = wr_en & ~full;
    assign do_read  = rd_en & ~empty;

    assign full  = (count_r == COUNT_WIDTH'(DEPTH));
    assign empty = (count_r == '0);
    assign count = count_r;

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
    // --------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            dout   <= '0;
        end else if (do_read) begin
            dout   <= mem[rd_ptr];
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
