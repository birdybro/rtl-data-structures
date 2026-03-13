# Priority Structures

This document covers every priority-queue, heap, and tag-management module in
`rtl/priority/`.

---

## priority_queue_linear

### Overview

`priority_queue_linear` stores up to `DEPTH` entries, each with an associated
priority value.  On every cycle the module scans all stored entries and presents
the **highest-priority** (lowest numeric priority value) entry at the `dout` /
`priority_out` outputs.

### Complexity

| Operation | Latency | Hardware cost |
|---|---|---|
| `push` | 1 cycle | Write to next free slot |
| `pop` | 1 cycle (result already at outputs) | Full scan to find next minimum |
| Peek | Combinational | Always valid when `!empty` |

Because the scan is fully parallel (implemented as a priority encoder), the
output is always valid after one clock cycle of propagation.  The trade-off is
that this module is **O(N) in area** — every extra entry requires one more
comparator in the scan tree.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Payload width |
| `PRIORITY_WIDTH` | 4 | Priority field width (lower = higher priority) |
| `DEPTH` | 16 | Maximum entries |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` / `rst_n` | in | 1 | Clock / active-low reset |
| `push` | in | 1 | Add entry (`din`, `priority_in`) |
| `pop` | in | 1 | Remove current head entry |
| `din` | in | `DATA_WIDTH` | Payload to push |
| `priority_in` | in | `PRIORITY_WIDTH` | Priority of pushed entry |
| `dout` | out | `DATA_WIDTH` | Payload of highest-priority entry |
| `priority_out` | out | `PRIORITY_WIDTH` | Priority of head entry |
| `full` / `empty` | out | 1 | Status flags |
| `count` | out | `$clog2(DEPTH)+1` | Number of valid entries |

### Timing Diagram

```
          ___     ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___|   |___

push  ____XXXXXXXXX_________________________________
         [P=3,D=A][P=1,D=B]
                              ____
pop   _______________________|    |___________________

             _____________________________________________
dout  XXXXXXX[   B (P=1)  ][   B (P=1)   ][  A (P=3) ]
```

Notes:
- `dout` and `priority_out` are registered; they reflect the minimum-priority
  entry that was valid at the previous rising edge.
- `pop` removes the current head; the next-highest entry becomes visible on the
  following cycle.

### Usage

```systemverilog
priority_queue_linear #(
    .DATA_WIDTH     (8),
    .PRIORITY_WIDTH (4),
    .DEPTH          (32)
) u_pq (
    .clk          (clk),
    .rst_n        (rst_n),
    .push         (task_submit & ~full),
    .pop          (dispatch & ~empty),
    .din          (task_id),
    .priority_in  (task_prio),
    .dout         (next_task_id),
    .priority_out (next_task_prio),
    .full         (full),
    .empty        (empty),
    .count        ()
);
```

### When to Use

Use `priority_queue_linear` when:
- `DEPTH` ≤ 32 (linear scan is fast in hardware at small depths),
- push/pop happen every cycle (no multi-cycle sift delay),
- deterministic single-cycle dequeue is required.

For deeper queues (> 32 entries) consider `priority_queue_heap` to save area.

---

## priority_queue_heap

### Overview

`priority_queue_heap` implements a binary min-heap.  Push inserts in O(log N)
cycles (sift-up); pop removes the minimum in O(log N) cycles (sift-down).
During the sift operation the `busy` output is asserted — the caller must wait
before issuing the next `push` or `pop`.

### Busy Handshake

```
          ___     ___     ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___|   |___|   |___
          ____
push  ___|    |_____________________________________________________
                    ___________________________________________
busy  _____________|                                           |____
                                                               ^^^^
                                                          safe to push/pop again
```

Callers should qualify pushes and pops with `~busy`:

```systemverilog
assign do_push = new_entry_valid & ~pq_full & ~pq_busy;
assign do_pop  = need_min        & ~pq_empty & ~pq_busy;
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Payload width |
| `PRIORITY_WIDTH` | 4 | Priority field width |
| `DEPTH` | 16 | Maximum entries |

### Ports

Same as `priority_queue_linear` with the addition of:

| Port | Dir | Width | Description |
|---|---|---|---|
| `busy` | out | 1 | Sift in progress; no new push/pop accepted |

### Comparison: linear vs. heap

| | `priority_queue_linear` | `priority_queue_heap` |
|---|---|---|
| Push latency | 1 cycle | 1 + O(log N) cycles |
| Pop latency | 1 cycle | 1 + O(log N) cycles |
| Area (comparators) | O(N) | O(log N) |
| Throughput | 1 op/cycle | 1 op / O(log N) cycles |
| Best for | N ≤ 32 | N > 32 |

---

## binary_heap

### Overview

`binary_heap` is the generic underlying heap used by `min_heap` and `max_heap`.
The `MIN_HEAP` parameter selects whether the minimum (1) or maximum (0) key is
always at the top.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Satellite data width |
| `KEY_WIDTH` | 8 | Comparison key width |
| `DEPTH` | 16 | Maximum entries |
| `MIN_HEAP` | 1 | 1 = min-heap, 0 = max-heap |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `insert` | in | 1 | Insert (`key_in`, `data_in`) |
| `remove_top` | in | 1 | Remove root (min or max) |
| `key_in` / `data_in` | in | — | Insert payload |
| `key_out` / `data_out` | out | — | Root entry (min/max) |
| `full` / `empty` / `count` | out | — | Status |
| `busy` | out | 1 | Sift in progress |

### Multi-cycle Sift Visualisation (DEPTH=7)

```
Insert key=2 into existing heap: root=1, children={3,5}, ...

Cycle 0: Write key=2 to next free leaf position
Cycle 1: Compare key=2 with parent; swap if smaller
Cycle 2: Compare with new parent; stop when parent <= child
Cycle 3: busy deasserts; heap property restored
```

---

## min_heap

### Overview

`min_heap` is a convenience wrapper around `binary_heap` with `MIN_HEAP=1`.
The minimum key is always at the root and returned on `min_key` / `min_data`.

### Ports (differences from binary_heap)

| Port | Description |
|---|---|
| `remove_min` | Remove the minimum entry |
| `min_key` | Current minimum key |
| `min_data` | Satellite data for minimum entry |

---

## max_heap

### Overview

`max_heap` is a convenience wrapper around `binary_heap` with `MIN_HEAP=0`.
The maximum key is always at the root.

### Ports (differences from binary_heap)

| Port | Description |
|---|---|
| `remove_max` | Remove the maximum entry |
| `max_key` | Current maximum key |
| `max_data` | Satellite data for maximum entry |

---

## calendar_queue

### Overview

`calendar_queue` is a **bucket-based time scheduler**.  Events are inserted with
an absolute `event_time_in` and stored in a bucket corresponding to
`(event_time mod NUM_BUCKETS)`.  The module dequeues the event from the bucket
whose time matches (or precedes) `current_time`.

This structure is efficient for **dense, near-future** event schedules (e.g.,
network packet scheduling, simulation event queues).

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Event payload width |
| `TIME_WIDTH` | 16 | Absolute time width |
| `NUM_BUCKETS` | 16 | Number of time buckets (`BUCKET_WIDTH = $clog2(NUM_BUCKETS)`) |
| `BUCKET_WIDTH` | 4 | Bits used to index a bucket |
| `DEPTH` | 64 | Total event storage across all buckets |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `insert` | in | 1 | Insert event |
| `dequeue` | in | 1 | Dequeue next due event |
| `event_data_in` | in | `DATA_WIDTH` | Event payload |
| `event_time_in` | in | `TIME_WIDTH` | Scheduled time |
| `current_time` | in | `TIME_WIDTH` | Current simulation/wall time |
| `event_data_out` | out | `DATA_WIDTH` | Dequeued event data |
| `event_time_out` | out | `TIME_WIDTH` | Dequeued event time |
| `empty` / `full` | out | 1 | Status flags |

### Usage

```systemverilog
calendar_queue #(
    .DATA_WIDTH  (16),
    .TIME_WIDTH  (32),
    .NUM_BUCKETS (64),
    .BUCKET_WIDTH(6),
    .DEPTH       (256)
) u_cq (
    .clk           (clk),
    .rst_n         (rst_n),
    .insert        (schedule_en),
    .dequeue       (dispatch_en & ~cq_empty),
    .event_data_in (event_payload),
    .event_time_in (sched_time),
    .current_time  (cycle_counter),
    .event_data_out(due_event),
    .event_time_out(due_time),
    .empty         (cq_empty),
    .full          (cq_full)
);
```

---

## scoreboard_allocator

### Overview

`scoreboard_allocator` manages a pool of **unique transaction tags** for tracking
in-flight operations.  A new tag is issued (`alloc_tag`) each time `alloc` is
asserted, until all `NUM_ENTRIES` tags are in use (`full`).  Tags are returned
with `free` + `free_tag`.

This is the hardware equivalent of a software *semaphore* combined with a *tag
ID generator*.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_ENTRIES` | 16 | Maximum in-flight operations |
| `TAG_WIDTH` | 4 | Width of each tag (`TAG_WIDTH >= $clog2(NUM_ENTRIES)`) |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `alloc` | in | 1 | Request a new tag |
| `free` | in | 1 | Return a tag |
| `alloc_tag` | out | `TAG_WIDTH` | Allocated tag (valid when `alloc_valid`) |
| `free_tag` | in | `TAG_WIDTH` | Tag being returned |
| `alloc_valid` | out | 1 | A tag was successfully allocated |
| `full` | out | 1 | All tags in use; allocation stalls |

### Timing Diagram

```
          ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___
          ____    ____
alloc ___|    |__|    |___________________________
alloc_valid ___________________________
               _______________
                   (tag=0)  (tag=1)
                                           ____
free  _____________________________________|    |__
free_tag ________________________________[  0  ]___
```

### Typical Use: Out-of-Order Memory Accesses

```systemverilog
// Issue a memory request
logic [TAG_W-1:0] txn_tag;
logic             tag_ok;

scoreboard_allocator #(
    .NUM_ENTRIES (MAX_OUTSTANDING),
    .TAG_WIDTH   (TAG_W)
) u_sb (
    .clk        (clk),
    .rst_n      (rst_n),
    .alloc      (mem_req_valid & ~sb_full),
    .free       (mem_resp_valid),
    .alloc_tag  (txn_tag),
    .free_tag   (mem_resp_tag),
    .alloc_valid(tag_ok),
    .full       (sb_full)
);

// Tag travels with the request
assign mem_req_tag = txn_tag;
```

### Relationship to Other Modules

- `scoreboard_allocator` allocates *tags* (IDs with no associated metadata).
- `resource_pool` allocates *IDs with metadata storage* (use when you need to
  store per-request data alongside the tag).
- `free_list_allocator` allocates from a bitmap; IDs may be non-sequential.
