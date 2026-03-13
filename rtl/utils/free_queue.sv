// =============================================================================
// free_queue.sv
// =============================================================================
// Overview:
//   FIFO queue for free resource tracking. At reset (or clear), the queue is
//   pre-loaded with all resource IDs 0..DEPTH-1. Consumers dequeue IDs to
//   acquire resources and enqueue IDs to release them.
//
// Parameters:
//   DATA_WIDTH  - Width of each entry (default: 8)
//   DEPTH       - Number of entries / resource IDs (default: 16)
//
// Ports:
//   clk     - Clock
//   rst_n   - Active-low reset
//   enqueue - Pulse to enqueue din (return resource)
//   dequeue - Pulse to dequeue -> dout (acquire resource)
//   clear   - Synchronous re-initialization with IDs 0..DEPTH-1
//   din     - Data to enqueue
//   dout    - Data at head of queue (combinational)
//   full    - Queue is full
//   empty   - Queue is empty
//   count   - Number of entries currently in queue
//
// Timing:
//   - dout is combinational from head of RAM
//   - enqueue/dequeue effects are registered
//   - clear resets pointers and reloads IDs in one cycle (uses init ROM)
//
// Insertion/Removal:
//   - enqueue when !full; dequeue when !empty
//   - Simultaneous enqueue+dequeue is supported
//
// Hardware Tradeoffs:
//   - Uses a circular FIFO with registered read/write pointers
//   - Init ROM is a simple combinational decode of index
// =============================================================================

`timescale 1ns/1ps

module free_queue #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    enqueue,
    input  logic                    dequeue,
    input  logic                    clear,
    input  logic [DATA_WIDTH-1:0]   din,
    output logic [DATA_WIDTH-1:0]   dout,
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(DEPTH):0]  count
);

    localparam int PTR_W = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0]      wr_ptr, rd_ptr;
    logic [$clog2(DEPTH):0] count_r;

    // -----------------------------------------------------------------------
    // Combinational outputs
    // -----------------------------------------------------------------------
    assign dout  = mem[rd_ptr];
    assign full  = (count_r == DEPTH[$clog2(DEPTH):0]);
    assign empty = (count_r == '0);
    assign count = count_r;

    // -----------------------------------------------------------------------
    // Sequential logic
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            count_r <= DEPTH[$clog2(DEPTH):0];
            for (int i = 0; i < DEPTH; i++)
                mem[i] <= DATA_WIDTH'(i);
        end else begin
            if (enqueue && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (dequeue && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            // Update count
            case ({enqueue && !full, dequeue && !empty})
                2'b10:   count_r <= count_r + 1'b1;
                2'b01:   count_r <= count_r - 1'b1;
                default: count_r <= count_r;
            endcase
        end
    end

endmodule
