// =============================================================================
// resource_pool.sv
// =============================================================================
// Overview:
//   Resource pool combining a bitmap allocator with a metadata SRAM. On
//   acquire, the lowest-numbered free resource ID is returned together with
//   its metadata storage slot. On release, the slot is freed and metadata
//   cleared.
//
// Parameters:
//   NUM_RESOURCES    - Total resources in pool (default: 16)
//   RESOURCE_ID_BITS - Width of resource ID ($clog2(NUM_RESOURCES))
//   METADATA_WIDTH   - Width of per-resource metadata (default: 8)
//
// Ports:
//   clk          - Clock
//   rst_n        - Active-low reset
//   acquire      - Pulse to acquire a resource
//   release      - Pulse to release resource_id
//   metadata_in  - Metadata to store on acquire
//   resource_id  - Resource ID to release (input) / acquired ID (output)
//   metadata_out - Metadata associated with acquired resource (registered)
//   valid_out    - Acquire succeeded
//   full         - No resources available
//   empty        - All resources are free
//   available    - Count of free resources
//
// Timing:
//   - resource_id and metadata_out are registered (available cycle after acquire)
//   - valid_out is registered
//
// Hardware Tradeoffs:
//   - Metadata SRAM is a simple register file (suitable for small pools)
//   - For large pools use BRAM/SRAM with 1-cycle read latency
// =============================================================================

`timescale 1ns/1ps

module resource_pool #(
    parameter int NUM_RESOURCES    = 16,
    parameter int RESOURCE_ID_BITS = $clog2(NUM_RESOURCES),
    parameter int METADATA_WIDTH   = 8
) (
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           acquire,
    input  logic                           release,
    input  logic [METADATA_WIDTH-1:0]      metadata_in,
    input  logic [RESOURCE_ID_BITS-1:0]    resource_id,   // ID to release
    output logic [RESOURCE_ID_BITS-1:0]    acquired_id,   // ID just acquired
    output logic [METADATA_WIDTH-1:0]      metadata_out,
    output logic                           valid_out,
    output logic                           full,
    output logic                           empty,
    output logic [$clog2(NUM_RESOURCES):0] available
);

    // -----------------------------------------------------------------------
    // Bitmap: 1=free, 0=allocated
    // -----------------------------------------------------------------------
    logic [NUM_RESOURCES-1:0] free_map;

    // Priority encoder
    logic [RESOURCE_ID_BITS-1:0] first_free;
    logic                        any_free;

    always_comb begin
        first_free = '0;
        any_free   = 1'b0;
        for (int i = NUM_RESOURCES-1; i >= 0; i--) begin
            if (free_map[i]) begin
                first_free = RESOURCE_ID_BITS'(i);
                any_free   = 1'b1;
            end
        end
    end

    // Metadata register file
    logic [METADATA_WIDTH-1:0] meta_mem [0:NUM_RESOURCES-1];

    // -----------------------------------------------------------------------
    // Sequential
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_map    <= {NUM_RESOURCES{1'b1}};
            acquired_id <= '0;
            metadata_out <= '0;
            valid_out   <= 1'b0;
            for (int i = 0; i < NUM_RESOURCES; i++)
                meta_mem[i] <= '0;
        end else begin
            valid_out <= 1'b0;
            if (acquire && any_free) begin
                free_map[first_free]  <= 1'b0;
                meta_mem[first_free]  <= metadata_in;
                acquired_id           <= first_free;
                metadata_out          <= metadata_in;
                valid_out             <= 1'b1;
            end
            if (release) begin
                free_map[resource_id] <= 1'b1;
                meta_mem[resource_id] <= '0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Combinational status
    // -----------------------------------------------------------------------
    always_comb begin
        full  = ~|free_map;
        empty =  &free_map;
        available = '0;
        for (int i = 0; i < NUM_RESOURCES; i++)
            available = available + ($clog2(NUM_RESOURCES)+1)'(free_map[i]);
    end

endmodule
