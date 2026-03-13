# rtl-data-structures

> A professional open-source **SystemVerilog** library of hardware-oriented data structures for FPGA and ASIC design.

## Overview

This library provides fully synthesizable, parameterized RTL implementations of classical computer science data structures adapted for hardware use. Each module is vendor-neutral, lint-friendly, and designed for easy integration into larger RTL designs.

## Repository Structure

```
rtl-data-structures/
├── rtl/
│   ├── queues/          # FIFOs and queue variants
│   ├── stacks/          # LIFO stacks
│   ├── priority/        # Priority queues and heaps
│   ├── associative/     # CAM, hash tables, lookup tables
│   ├── filters/         # Bloom filters and membership tests
│   ├── schedulers/      # Round-robin, priority, DRR schedulers
│   └── utils/           # Bitset, allocators, pools
├── examples/            # Synthesizable example designs
├── testbenches/         # SystemVerilog testbenches
├── docs/                # Detailed documentation
└── scripts/             # Helper scripts
```

## Module Summary

### Queues and FIFOs (`rtl/queues/`)

| Module | Description |
|--------|-------------|
| `simple_fifo` | Synchronous FIFO with registered output |
| `showahead_fifo` | FIFO with combinational (show-ahead) output |
| `circular_buffer` | Ring buffer with optional overwrite mode |
| `mailbox_fifo` | FIFO with per-entry valid bits |
| `packet_fifo` | Packet-aware FIFO; output only when full packet received |
| `async_fifo` | Dual-clock FIFO with Gray-code CDC |

### Stacks (`rtl/stacks/`)

| Module | Description |
|--------|-------------|
| `stack` | Standard LIFO stack |
| `bounded_stack` | Stack with overflow/underflow detection |
| `return_stack` | Call-return address stack for CPU designs |
| `dual_port_stack` | Two-port stack with arbitration |

### Priority Structures (`rtl/priority/`)

| Module | Description |
|--------|-------------|
| `priority_queue_linear` | Linear-scan priority queue; O(1) insert, O(N) dequeue |
| `priority_queue_heap` | Heap-based priority queue with busy handshake |
| `binary_heap` | Generic min/max binary heap |
| `min_heap` | Min-heap wrapper |
| `max_heap` | Max-heap wrapper |
| `calendar_queue` | Bucket-based calendar queue for event scheduling |
| `scoreboard_allocator` | Tag allocator for in-flight operation tracking |

### Associative Structures (`rtl/associative/`)

| Module | Description |
|--------|-------------|
| `content_addressable_memory` | Parallel-search CAM |
| `tagged_lookup_table` | Tag+data cache-style lookup table |
| `hash_table_fixed` | Fixed hash table with chained buckets |
| `set_associative_table` | N-way set-associative table with PLRU |
| `free_list_allocator` | Bitmap-based resource ID allocator |

### Filters and Probabilistic Structures (`rtl/filters/`)

| Module | Description |
|--------|-------------|
| `bloom_filter` | Probabilistic membership filter |
| `counting_bloom_filter` | Bloom filter with deletion support |
| `membership_filter` | Exact membership using direct-mapped bitmap |
| `signature_match_table` | Parallel signature matching |

### Scheduling Structures (`rtl/schedulers/`)

| Module | Description |
|--------|-------------|
| `round_robin_scheduler` | Fair round-robin arbitration |
| `priority_scheduler` | Static priority with per-level round-robin |
| `aging_scheduler` | Priority scheduler with aging for starvation prevention |
| `deficit_round_robin_scheduler` | DRR scheduler for variable-size fairness |
| `token_bucket_shaper` | Token bucket rate limiter |
| `credit_pool_manager` | Per-flow credit management |

### Utility Structures (`rtl/utils/`)

| Module | Description |
|--------|-------------|
| `bitset` | Hardware bitset with set/clear/test/popcount |
| `bitmap_allocator` | Bitmap-based slot allocator |
| `free_queue` | Pre-loaded FIFO for resource ID management |
| `resource_pool` | Bitmap allocator with metadata storage |
| `index_allocator` | Linked-list free-list index allocator |
| `history_buffer` | Circular history buffer with offset access |

## Design Philosophy

These are **hardware data structures**, not software containers:

- **Deterministic latency**: Every operation completes in a fixed or bounded number of cycles
- **Synthesizable**: No dynamic memory, no software recursion, no vendor-specific constructs
- **Parameterized**: Widths and depths are all parameters; adapt to any use case
- **Vendor neutral**: Pure synthesizable SystemVerilog; works with any FPGA/ASIC flow

## Coding Conventions

- **Module names**: `snake_case`
- **Parameters**: `UPPER_CASE`
- **Clock**: `clk` (rising-edge)
- **Reset**: `rst_n` (active-low, asynchronous)
- **Types**: `logic` only (no `reg`/`wire`)
- **Sequential**: `always_ff @(posedge clk or negedge rst_n)`
- **Combinational**: `always_comb`

## Quick Start

Include any module directly:

```systemverilog
`include "rtl/queues/simple_fifo.sv"

simple_fifo #(
    .DATA_WIDTH (8),
    .DEPTH      (64)
) u_fifo (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (wr_en),
    .rd_en  (rd_en),
    .din    (din),
    .dout   (dout),
    .full   (fifo_full),
    .empty  (fifo_empty),
    .count  (fifo_count)
);
```

## Examples

See `examples/` for complete synthesizable example designs:

| Example | Description |
|---------|-------------|
| `task_scheduler.sv` | Task dispatcher using priority queue |
| `packet_buffer_system.sv` | Packet FIFO + buffer ID allocator |
| `bloom_filter_system.sv` | Bloom pre-filter + CAM exact match |
| `resource_allocator.sv` | Bitmap allocator + free queue |
| `tagged_lookup_example.sv` | Key-value store with scoreboard |

## Documentation

See `docs/` for detailed documentation:

- [Overview](docs/overview.md)
- [FIFO and Stack Patterns](docs/fifo_and_stack_patterns.md)
- [Priority Structures](docs/priority_structures.md)
- [Associative Structures](docs/associative_structures.md)
- [Probabilistic Structures](docs/probabilistic_structures.md)
- [Scheduler Patterns](docs/scheduler_patterns.md)

## License

See [LICENSE](LICENSE) for details.
