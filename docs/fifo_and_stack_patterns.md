# FIFO and Stack Patterns

This document covers every queue and stack module in `rtl/queues/` and `rtl/stacks/`.

---

## simple_fifo

### Overview

`simple_fifo` is the baseline synchronous FIFO.  Written data appears at `dout` on
the **next rising edge** after `rd_en` is asserted (registered output).  This is the
most area-efficient FIFO in the library and the right default choice when output
latency is not critical.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Bit width of each entry |
| `DEPTH` | 16 | Number of entries (any positive integer) |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Rising-edge clock |
| `rst_n` | in | 1 | Active-low asynchronous reset |
| `wr_en` | in | 1 | Write enable; ignored when `full` |
| `rd_en` | in | 1 | Read enable; ignored when `empty` |
| `din` | in | `DATA_WIDTH` | Write data |
| `dout` | out | `DATA_WIDTH` | Read data (registered) |
| `full` | out | 1 | FIFO is full |
| `empty` | out | 1 | FIFO is empty |
| `count` | out | `$clog2(DEPTH)+1` | Number of valid entries |

### Timing Diagram

```
          ___     ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___|   |___
          ____    ____
wr_en ___|    |__|    |_________________________________
       [ A  ][ B  ]
din   ___AAAA__BBBB___________________________________
                                ____
rd_en ________________________|    |__________________
                                        _______________
dout  XXXXXXXXXXXXXXXXXXXXXXXXXXXX[ A ]
          _____________________________
empty |   |                             |_____________
```

Notes:
- `dout` updates one cycle **after** `rd_en` is sampled.
- `empty` deasserts the cycle after the first write.
- Simultaneous `wr_en` + `rd_en` when `count == 1` keeps `empty` low.

### Usage Example

```systemverilog
`include "rtl/queues/simple_fifo.sv"

simple_fifo #(
    .DATA_WIDTH (16),
    .DEPTH      (128)
) u_cmd_fifo (
    .clk   (clk),
    .rst_n (rst_n),
    .wr_en (cmd_valid & ~fifo_full),
    .rd_en (consumer_ready & ~fifo_empty),
    .din   (cmd_word),
    .dout  (cmd_out),
    .full  (fifo_full),
    .empty (fifo_empty),
    .count ()
);
```

---

## showahead_fifo

### Overview

`showahead_fifo` exposes the head entry **combinationally** — `dout` reflects the
oldest entry without needing to assert `rd_en` first.  `rd_en` acts as a *consume*
signal: after it is asserted, the next entry becomes visible on `dout` immediately
(no extra read cycle).

### When to Use showahead vs. simple_fifo

| Criterion | `simple_fifo` | `showahead_fifo` |
|---|---|---|
| Output latency | 1 registered cycle | Combinational |
| Area | Smaller | Slightly larger (mux on read port) |
| Timing closure | Easier | May be critical path on dout |
| Typical use | Pipelined back-pressure | Peek-before-consume (parsers, arbiters) |

### Parameters

Same as `simple_fifo`: `DATA_WIDTH`, `DEPTH`.

### Ports

Same as `simple_fifo`.  Behaviour of `dout` differs: head entry is visible as soon
as `empty` is deasserted.

### Timing Diagram

```
          ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___
          ____    ____
wr_en ___|    |__|    |_______________________
       [ A  ][ B  ]
din   ___AAAA__BBBB___________________________
               _____________________________
dout  _______[  A  ][  A  ][  B  ][  B  ]___
                      _____
rd_en ______________|     |__________________
```

Notes:
- `dout` shows `A` **immediately** after the first write (no rd_en needed).
- After `rd_en`, `dout` transitions to `B` on the next cycle.

---

## circular_buffer

### Overview

`circular_buffer` is a ring buffer with an optional **overwrite mode**.  When
`overwrite` is asserted and the buffer is full, the oldest entry is silently
discarded to make room for the newest.  This is useful for logging, trace capture,
and sensor sliding-window averaging.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Bit width |
| `DEPTH` | 16 | Buffer capacity |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `overwrite` | in | 1 | Enable overwrite-on-full mode |
| *(all others)* | — | — | Same as `simple_fifo` |

### Overwrite Mode Explanation

```
Normal mode (overwrite=0):   Overwrite mode (overwrite=1):
  wr_en + full -> ignored      wr_en + full -> rd_ptr advances,
                                oldest entry replaced by new data
```

### Usage Example

```systemverilog
// Capture last 256 ADC samples; always overwrite oldest
circular_buffer #(
    .DATA_WIDTH (12),
    .DEPTH      (256)
) u_adc_log (
    .clk       (clk),
    .rst_n     (rst_n),
    .wr_en     (adc_valid),
    .rd_en     (host_rd),
    .overwrite (1'b1),       // always overwrite oldest
    .din       (adc_sample),
    .dout      (log_data),
    .full      (),
    .empty     (log_empty),
    .count     (log_count)
);
```

---

## mailbox_fifo

### Overview

`mailbox_fifo` adds a **per-entry valid bit** to each storage slot.  The `valid_out`
signal indicates whether the entry currently at the head of the queue was written
(as opposed to being a reset-time zero).  This allows distinguishing between "no
data ever written to this slot" and "data written but not yet consumed".

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Bit width |
| `DEPTH` | 16 | Number of entries |
| `NUM_ENTRIES` | `DEPTH` | Logical capacity override |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `push` | in | 1 | Push data into mailbox |
| `pop` | in | 1 | Pop data from mailbox |
| `din` | in | `DATA_WIDTH` | Push data |
| `dout` | out | `DATA_WIDTH` | Pop data |
| `valid_out` | out | 1 | Entry at head was validly written |
| `full` | out | 1 | No more entries can be pushed |
| `empty` | out | 1 | No valid entries |
| `count` | out | `$clog2(NUM_ENTRIES)+1` | Valid entry count |

---

## packet_fifo

### Overview

`packet_fifo` is designed for **variable-length packet** storage.  Bytes are written
with start-of-packet (`sop`) and end-of-packet (`eop`) markers.  The FIFO does not
present data on `dout` until an **entire packet** has been committed to storage.
This prevents partial packets from being forwarded.

### Commit-Pointer Architecture

The FIFO maintains two write pointers:

1. **Speculative write pointer** — advances with each byte written.
2. **Commit pointer** — advances to the speculative pointer only when `eop` is seen.

If an error occurs before `eop` (e.g., the upstream drops the packet), the
speculative pointer can be reset to the commit pointer, discarding the partial
packet without any downstream visibility.

```
          wr_ptr (speculative)
            │
  ┌─────────▼──────────────────────────────────┐
  │ [B0][B1][B2][B3] ... [Bn-1][Bn] ░░░░░░░░░  │
  └───────────────────────▲────────────────────┘
                     commit_ptr
                     (only advances on eop)
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Width of each byte |
| `DEPTH` | 256 | Total byte storage |
| `MAX_PACKET_SIZE` | 64 | Maximum bytes per packet |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `wr_en` | in | 1 | Write enable |
| `rd_en` | in | 1 | Read enable |
| `sop` | in | 1 | Start of packet on `din` |
| `eop` | in | 1 | End of packet on `din` |
| `din` | in | `DATA_WIDTH` | Write data |
| `dout` | out | `DATA_WIDTH` | Read data |
| `sop_out` | out | 1 | First byte of packet on `dout` |
| `eop_out` | out | 1 | Last byte of packet on `dout` |
| `full` | out | 1 | No room for more data |
| `empty` | out | 1 | No committed data to read |
| `packet_count` | out | `$clog2(DEPTH/MAX_PACKET_SIZE)+1` | Number of complete packets |
| `frame_valid` | out | 1 | At least one complete packet ready |

### Usage Pattern

```systemverilog
// Read only when a full packet is present
assign rd_en = frame_valid & downstream_ready;
```

---

## async_fifo

### Overview

`async_fifo` is a dual-clock FIFO for crossing clock domains.  It uses **Gray-code
counters** to synchronise read and write pointers safely across domains.

### Gray-Code CDC Explanation

Read and write pointers are each maintained as Gray-code counts.  A Gray-code
counter changes only **one bit per increment**, so even if the synchroniser samples
a transitioning value, it will read either the old or the new count — never an
impossible intermediate value.

```
Write side:           Read side:
bin_wr  → gray_wr ──► 2-FF sync ──► gray_wr_sync → bin_wr_sync
                                     (estimate of wr_ptr in rd domain)
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Word width |
| `DEPTH` | 16 | Number of entries (**must be power of 2**) |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `wr_clk` | in | 1 | Write-side clock |
| `rd_clk` | in | 1 | Read-side clock |
| `wr_rst_n` | in | 1 | Write-side reset |
| `rd_rst_n` | in | 1 | Read-side reset |
| `wr_en` / `rd_en` | in | 1 | Write / read enable |
| `din` / `dout` | in/out | `DATA_WIDTH` | Data |
| `wr_full` / `rd_empty` | out | 1 | Full / empty flags in each domain |
| `wr_count` / `rd_count` | out | `$clog2(DEPTH)+1` | Occupancy in each domain |

### Constraint Recommendations

Add a max-delay or CDC constraint to the pointer synchroniser paths:

```tcl
# Example Vivado XDC
set_max_delay -datapath_only -from [get_cells u_async_fifo/wr_ptr_gray_reg[*]] \
              -to   [get_cells u_async_fifo/wr_ptr_gray_sync_reg[*][0]] 5.0
```

---

## stack

### Overview

`stack` is a plain **LIFO** (last-in, first-out) stack.  Push adds to the top;
pop removes from the top.  `dout` reflects the current top-of-stack.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Entry width |
| `DEPTH` | 16 | Maximum entries |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `push` | in | 1 | Push `din` onto stack |
| `pop` | in | 1 | Pop top entry |
| `din` | in | `DATA_WIDTH` | Data to push |
| `dout` | out | `DATA_WIDTH` | Current top-of-stack |
| `full` / `empty` | out | 1 | Status flags |
| `count` | out | `$clog2(DEPTH)+1` | Number of entries |

---

## bounded_stack

### Overview

`bounded_stack` adds **overflow** and **underflow** detection to the basic stack.
A configurable `MAX_DEPTH` parameter (≤ `DEPTH`) sets the logical capacity.
Attempting to push beyond `MAX_DEPTH` asserts `overflow` for one cycle.
Attempting to pop an empty stack asserts `underflow` for one cycle.

### Additional Parameters

| Parameter | Default | Description |
|---|---|---|
| `MAX_DEPTH` | `DEPTH` | Logical capacity limit |

### Additional Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `overflow` | out | 1 | Push attempted when full (single-cycle pulse) |
| `underflow` | out | 1 | Pop attempted when empty (single-cycle pulse) |

### Usage — Exception Handling

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)          stack_error <= 1'b0;
    else if (overflow)   stack_error <= 1'b1;  // sticky error flag
    else if (underflow)  stack_error <= 1'b1;
end
```

---

## return_stack

### Overview

`return_stack` is a specialised LIFO designed for CPU **call/return address**
management.  Instead of generic `push`/`pop`, it exposes `call` (push `pc_in`) and
`ret` (pop to `pc_out`) — the semantic names familiar from instruction-set
architectures.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `ADDR_WIDTH` | 16 | Width of the program-counter word |
| `DEPTH` | 16 | Maximum call nesting depth |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `call` | in | 1 | Save `pc_in` (next PC after call instruction) |
| `ret` | in | 1 | Restore saved address to `pc_out` |
| `pc_in` | in | `ADDR_WIDTH` | Return address to save |
| `pc_out` | out | `ADDR_WIDTH` | Restored return address |
| `full` | out | 1 | Maximum nesting depth reached |
| `empty` | out | 1 | No saved return addresses |
| `depth` | out | `$clog2(DEPTH)+1` | Current call depth |

### CPU Integration Example

```systemverilog
return_stack #(
    .ADDR_WIDTH (32),
    .DEPTH      (8)
) u_rstack (
    .clk   (clk),
    .rst_n (rst_n),
    .call  (decode_is_call),
    .ret   (decode_is_ret),
    .pc_in (pc_plus_4),       // PC of instruction after call
    .pc_out(return_address),
    .full  (rstack_overflow),
    .empty (),
    .depth ()
);
```

---

## dual_port_stack

### Overview

`dual_port_stack` provides **two independent access ports** (A and B) to the same
storage array.  Both ports can push and pop simultaneously.  When both ports attempt
a conflicting operation in the same cycle, the `conflict` flag is asserted and the
lower-priority port (B) is stalled.

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `push_a` / `pop_a` | in | 1 | Port A push / pop |
| `din_a` / `dout_a` | in/out | `DATA_WIDTH` | Port A data |
| `push_b` / `pop_b` | in | 1 | Port B push / pop |
| `din_b` / `dout_b` | in/out | `DATA_WIDTH` | Port B data |
| `full` / `empty` | out | 1 | Shared status |
| `count` | out | `$clog2(DEPTH)+1` | Shared entry count |
| `conflict` | out | 1 | Conflicting simultaneous access this cycle |

### Conflict Handling

```
Cycle N:  push_a=1, push_b=1  -> both cannot push simultaneously
          conflict asserted
          Port A push accepted, port B push silently dropped
          -> caller must retry port B next cycle when conflict=0
```

---

## Common Patterns

### Back-pressure with `full` / `empty`

```systemverilog
// Producer side
assign wr_en = upstream_valid & ~fifo_full;
assign upstream_ready = ~fifo_full;

// Consumer side
assign rd_en = downstream_ready & ~fifo_empty;
assign downstream_valid = ~fifo_empty;
```

### FIFO as elastic buffer between pipeline stages

```systemverilog
// Stage A writes at variable rate, stage B reads at constant rate
// DEPTH should be sized for the maximum burst from A
simple_fifo #(
    .DATA_WIDTH (WORD_W),
    .DEPTH      (MAX_BURST * 2)   // 2× headroom
) u_elastic ( ... );
```
