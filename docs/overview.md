# rtl-data-structures — Library Overview

## Introduction

**rtl-data-structures** is a professional, open-source SystemVerilog library that provides
synthesizable, parameterized implementations of classical computer-science data structures
adapted for hardware (FPGA / ASIC) design.

Software data structures rely on dynamic memory, pointers, and runtime recursion — none of which
map efficiently to RTL.  This library re-implements those same *concepts* in a way that:

- uses only static storage arrays sized at elaboration time,
- completes every operation in a **deterministic, bounded number of clock cycles**,
- is **vendor-neutral** (no Xilinx/Intel/Cadence primitives),
- follows a single, consistent coding style throughout.

---

## Repository Structure

```
rtl-data-structures/
├── rtl/
│   ├── queues/          # FIFOs, ring buffers, packet FIFOs, async FIFO
│   ├── stacks/          # LIFO stacks (plain, bounded, return, dual-port)
│   ├── priority/        # Priority queues, heaps, calendar queue, scoreboard
│   ├── associative/     # CAM, hash table, set-associative table, lookup table
│   ├── filters/         # Bloom filter, counting bloom, membership filter
│   ├── schedulers/      # Round-robin, DRR, priority, aging, token-bucket
│   └── utils/           # Bitset, bitmap allocator, free-queue, resource pool
├── examples/            # Complete synthesizable example designs
├── testbenches/         # SystemVerilog testbenches
├── docs/                # Detailed reference documentation
└── scripts/             # Helper scripts
```

---

## Design Philosophy

### Hardware-Oriented, Not Software Containers

Every module in this library is designed with hardware constraints in mind:

| Software container | RTL equivalent concern |
|--------------------|------------------------|
| `std::queue<T>` with dynamic growth | Fixed-depth FIFO; DEPTH is a compile-time parameter |
| `std::priority_queue` with heap sift | Multi-cycle sift with `busy` handshake |
| `std::unordered_map` with chaining | Fixed hash table; NUM_BUCKETS × SLOTS_PER_BUCKET |
| Bloom filter with arbitrary array | FILTER_SIZE bits; NUM_HASH hash functions hardwired |

### Deterministic Latency

Every operation completes in a **fixed or bounded** number of cycles:

| Module class | Insert latency | Lookup / dequeue latency |
|---|---|---|
| FIFOs / stacks | 1 cycle | 1 cycle (registered) or 0 (showahead) |
| Linear priority queue | 1 cycle | 1 cycle (head always valid) |
| Heap priority queue | 1 cycle (triggers sift) | multi-cycle (busy asserted) |
| CAM / tagged lookup | 1 cycle | 1 cycle |
| Bloom filter | 1 cycle | combinational |
| Schedulers | N/A | 1 cycle grant |

### Synthesizability

No module uses:
- `new` / `delete` / `malloc`
- recursive functions
- `$display` / `$monitor` (except inside `` `ifndef SYNTHESIS `` guards in testbenches)
- vendor-specific IP macros

---

## Coding Conventions

| Convention | Rule |
|---|---|
| Module names | `snake_case` |
| Parameters | `UPPER_CASE` |
| Clock | `clk` (rising-edge triggered) |
| Reset | `rst_n` (active-low, **asynchronous**) |
| Types | `logic` only — no `reg` or `wire` |
| Sequential blocks | `always_ff @(posedge clk or negedge rst_n)` |
| Combinational blocks | `always_comb` |
| Timescale | `` `timescale 1ns/1ps `` in every file |
| Include guard | `ifndef` / `define` macro at top of every file |

### Reset pattern used throughout the library

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // synchronous state reset to known values
        count <= '0;
        full  <= 1'b0;
        empty <= 1'b1;
    end else begin
        // normal operation
    end
end
```

---

## Quick Start

### 1. Clone / copy the module you need

All modules are self-contained `.sv` files with no library-level package dependencies.
Simply `\`include` the file directly into your design:

```systemverilog
`timescale 1ns/1ps
`include "rtl/queues/simple_fifo.sv"

module my_design (
    input  logic       clk, rst_n,
    input  logic       wr_en, rd_en,
    input  logic [7:0] din,
    output logic [7:0] dout,
    output logic       full, empty
);

    simple_fifo #(
        .DATA_WIDTH (8),
        .DEPTH      (64)
    ) u_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (wr_en),
        .rd_en (rd_en),
        .din   (din),
        .dout  (dout),
        .full  (full),
        .empty (empty),
        .count ()        // unused
    );

endmodule
```

### 2. Parameterize to your use case

Every width and depth is a parameter.  Change them at instantiation:

```systemverilog
// 32-bit wide, 512-entry deep FIFO
simple_fifo #(
    .DATA_WIDTH (32),
    .DEPTH      (512)
) u_wide_fifo ( ... );
```

### 3. Connect only the ports you need

Unused output ports can be left unconnected (tie to `()`).
Unused input ports should be tied to their safe default (`1'b0` for
enables, appropriate constants for data inputs).

---

## Module Listing by Category

### Queues and FIFOs (`rtl/queues/`)

| Module | Key Parameters | Description |
|---|---|---|
| `simple_fifo` | `DATA_WIDTH`, `DEPTH` | Synchronous FIFO with registered output |
| `showahead_fifo` | `DATA_WIDTH`, `DEPTH` | FIFO with combinational (show-ahead) output |
| `circular_buffer` | `DATA_WIDTH`, `DEPTH` | Ring buffer with optional overwrite mode |
| `mailbox_fifo` | `DATA_WIDTH`, `DEPTH`, `NUM_ENTRIES` | Per-entry valid-bit FIFO |
| `packet_fifo` | `DATA_WIDTH`, `DEPTH`, `MAX_PACKET_SIZE` | Packet-aware FIFO; only outputs complete packets |
| `async_fifo` | `DATA_WIDTH`, `DEPTH` | Dual-clock FIFO with Gray-code CDC |

### Stacks (`rtl/stacks/`)

| Module | Key Parameters | Description |
|---|---|---|
| `stack` | `DATA_WIDTH`, `DEPTH` | Standard LIFO stack |
| `bounded_stack` | `DATA_WIDTH`, `DEPTH`, `MAX_DEPTH` | Stack with overflow/underflow detection |
| `return_stack` | `ADDR_WIDTH`, `DEPTH` | Call-return address stack for CPU designs |
| `dual_port_stack` | `DATA_WIDTH`, `DEPTH` | Two-port stack with conflict detection |

### Priority Structures (`rtl/priority/`)

| Module | Key Parameters | Description |
|---|---|---|
| `priority_queue_linear` | `DATA_WIDTH`, `PRIORITY_WIDTH`, `DEPTH` | Linear-scan PQ; O(1) push, O(N) pop |
| `priority_queue_heap` | `DATA_WIDTH`, `PRIORITY_WIDTH`, `DEPTH` | Heap-based PQ with `busy` handshake |
| `binary_heap` | `DATA_WIDTH`, `KEY_WIDTH`, `DEPTH`, `MIN_HEAP` | Generic min/max binary heap |
| `min_heap` | `DATA_WIDTH`, `KEY_WIDTH`, `DEPTH` | Min-heap convenience wrapper |
| `max_heap` | `DATA_WIDTH`, `KEY_WIDTH`, `DEPTH` | Max-heap convenience wrapper |
| `calendar_queue` | `DATA_WIDTH`, `TIME_WIDTH`, `NUM_BUCKETS`, `DEPTH` | Bucket-based calendar queue |
| `scoreboard_allocator` | `NUM_ENTRIES`, `TAG_WIDTH` | Tag allocator for in-flight tracking |

### Associative Structures (`rtl/associative/`)

| Module | Key Parameters | Description |
|---|---|---|
| `content_addressable_memory` | `KEY_WIDTH`, `DATA_WIDTH`, `DEPTH` | Parallel-search CAM |
| `tagged_lookup_table` | `TAG_WIDTH`, `DATA_WIDTH`, `DEPTH` | Tag+data cache-style lookup |
| `hash_table_fixed` | `KEY_WIDTH`, `DATA_WIDTH`, `NUM_BUCKETS`, `SLOTS_PER_BUCKET` | Fixed hash table with chaining |
| `set_associative_table` | `KEY_WIDTH`, `DATA_WIDTH`, `NUM_SETS`, `WAYS` | N-way set-associative with PLRU |
| `free_list_allocator` | `NUM_RESOURCES`, `ID_WIDTH` | Bitmap-based resource ID allocator |

### Filters and Probabilistic Structures (`rtl/filters/`)

| Module | Key Parameters | Description |
|---|---|---|
| `bloom_filter` | `KEY_WIDTH`, `FILTER_SIZE`, `NUM_HASH` | Probabilistic membership filter |
| `counting_bloom_filter` | `KEY_WIDTH`, `FILTER_SIZE`, `NUM_HASH`, `COUNT_BITS` | Bloom filter with deletion |
| `membership_filter` | `KEY_WIDTH`, `TABLE_SIZE` | Exact membership via direct-mapped bitmap |
| `signature_match_table` | `SIG_WIDTH`, `NUM_ENTRIES`, `DATA_WIDTH` | Parallel signature matching |

### Scheduling Structures (`rtl/schedulers/`)

| Module | Key Parameters | Description |
|---|---|---|
| `round_robin_scheduler` | `NUM_CLIENTS` | Fair round-robin arbitration |
| `priority_scheduler` | `NUM_CLIENTS`, `PRIORITY_LEVELS` | Static priority with per-level RR |
| `aging_scheduler` | `NUM_CLIENTS`, `MAX_AGE`, `BASE_PBITS` | Priority with aging for starvation prevention |
| `deficit_round_robin_scheduler` | `NUM_CLIENTS`, `QUANTUM_BITS` | DRR for variable-length fairness |
| `token_bucket_shaper` | `TOKEN_BITS`, `RATE_BITS`, `BURST_BITS` | Token bucket rate limiter |
| `credit_pool_manager` | `NUM_FLOWS`, `CREDIT_BITS` | Per-flow credit management |

### Utility Structures (`rtl/utils/`)

| Module | Key Parameters | Description |
|---|---|---|
| `bitset` | `SIZE` | Hardware bitset with set/clear/test/popcount |
| `bitmap_allocator` | `NUM_SLOTS`, `SLOT_ID_BITS` | Bitmap-based slot allocator |
| `free_queue` | `DATA_WIDTH`, `DEPTH` | Pre-loaded FIFO for resource ID management |
| `resource_pool` | `NUM_RESOURCES`, `METADATA_WIDTH` | Bitmap allocator with metadata storage |
| `index_allocator` | `NUM_INDICES`, `INDEX_WIDTH` | Linked-list free-list index allocator |
| `history_buffer` | `DATA_WIDTH`, `DEPTH` | Circular history buffer with offset access |

---

## Getting Started Examples

See the `examples/` directory for complete, synthesizable designs:

| File | Modules used | Demonstrates |
|---|---|---|
| `task_scheduler.sv` | `priority_queue_linear` | Task dispatch by priority |
| `packet_buffer_system.sv` | `packet_fifo`, `free_list_allocator` | Packet buffer ID management |
| `bloom_filter_system.sv` | `bloom_filter`, `content_addressable_memory` | Two-stage membership pipeline |
| `resource_allocator.sv` | `bitmap_allocator`, `free_queue` | Fair resource pool management |
| `tagged_lookup_example.sv` | `tagged_lookup_table`, `scoreboard_allocator` | Key-value store with tag tracking |

---

## Detailed Documentation

| Document | Contents |
|---|---|
| [fifo_and_stack_patterns.md](fifo_and_stack_patterns.md) | All queue and stack modules |
| [priority_structures.md](priority_structures.md) | Priority queues, heaps, scoreboard |
| [associative_structures.md](associative_structures.md) | CAM, hash tables, lookup tables |
| [probabilistic_structures.md](probabilistic_structures.md) | Bloom filters and membership tests |
| [scheduler_patterns.md](scheduler_patterns.md) | All scheduler modules |
