// =============================================================================
// bitset.sv
// =============================================================================
// Overview:
//   A hardware bitset supporting individual bit set, clear, toggle, and test
//   operations, along with aggregate signals (any_set, all_set, popcount).
//
// Parameters:
//   SIZE        - Number of bits in the bitset (default: 32)
//
// Ports:
//   clk         - Clock input
//   rst_n       - Active-low synchronous reset
//   set_bit     - Pulse high to set bit at bit_index
//   clear_bit   - Pulse high to clear bit at bit_index
//   toggle_bit  - Pulse high to toggle bit at bit_index
//   test_bit    - Combinationally reads bit at bit_index -> bit_out
//   clear_all   - Synchronous clear of all bits
//   bit_index   - Index of target bit [$clog2(SIZE)-1:0]
//   bit_out     - Combinational output of tested bit
//   bit_vector  - Full bitset register visible to external logic
//   any_set     - High if any bit is set
//   all_set     - High if all bits are set
//   count       - Popcount: number of set bits
//
// Timing:
//   - set/clear/toggle/clear_all take effect on the next rising clock edge
//   - test_bit / bit_out are purely combinational
//   - Priority: clear_all > clear_bit > set_bit > toggle_bit
//
// Hardware Tradeoffs:
//   - Popcount uses a combinational adder tree (O(log N) depth)
//   - For large SIZE, consider pipelining the count output
// =============================================================================

`timescale 1ns/1ps

module bitset #(
    parameter int SIZE = 32
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic                        set_bit,
    input  logic                        clear_bit,
    input  logic                        toggle_bit,
    input  logic                        test_bit,
    input  logic                        clear_all,
    input  logic [$clog2(SIZE)-1:0]     bit_index,
    output logic                        bit_out,
    output logic [SIZE-1:0]             bit_vector,
    output logic                        any_set,
    output logic                        all_set,
    output logic [$clog2(SIZE):0]       count
);

    // -------------------------------------------------------------------------
    // Internal register
    // -------------------------------------------------------------------------
    logic [SIZE-1:0] bits_r;

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bits_r <= '0;
        end else if (clear_all) begin
            bits_r <= '0;
        end else begin
            if (clear_bit)
                bits_r[bit_index] <= 1'b0;
            else if (set_bit)
                bits_r[bit_index] <= 1'b1;
            else if (toggle_bit)
                bits_r[bit_index] <= ~bits_r[bit_index];
        end
    end

    // -------------------------------------------------------------------------
    // Combinational outputs
    // -------------------------------------------------------------------------
    always_comb begin
        bit_vector = bits_r;
        bit_out    = bits_r[bit_index];
        any_set    = |bits_r;
        all_set    = &bits_r;

        // Popcount via summation
        count = '0;
        for (int i = 0; i < SIZE; i++) begin
            count = count + ($clog2(SIZE)+1)'(bits_r[i]);
        end
    end

endmodule
