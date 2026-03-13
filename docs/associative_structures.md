# Associative Structures

This document covers every associative and lookup module in `rtl/associative/`.

---

## content_addressable_memory

### Overview

A **Content-Addressable Memory (CAM)** is the hardware inverse of a traditional
RAM: instead of addressing by location, you address by *content*.  Given a search
key, the CAM returns the data stored alongside it (if any) after a parallel
comparison across all entries.

This implementation performs a **fully parallel search** — all entries are compared
with `key_in` in the same clock cycle.  The result is available one cycle later as
a registered output.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `KEY_WIDTH` | 8 | Width of the search key |
| `DATA_WIDTH` | 8 | Width of associated payload |
| `DEPTH` | 16 | Number of CAM entries |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` / `rst_n` | in | 1 | Clock / reset |
| `write_en` | in | 1 | Write `key_in` + `data_in` into CAM |
| `key_in` | in | `KEY_WIDTH` | Key to write or search |
| `data_in` | in | `DATA_WIDTH` | Data to write |
| `lookup_en` | in | 1 | Perform a lookup on `key_in` |
| `match_data` | out | `DATA_WIDTH` | Data from first matching entry |
| `match_index` | out | `$clog2(DEPTH)` | Index of first match |
| `match_found` | out | 1 | At least one match found |
| `match_multiple` | out | 1 | More than one entry matches `key_in` |
| `flush` | in | 1 | Invalidate all entries |

### Timing Diagram

```
          ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___
          ___________
write_en |           |_____________________________
key=0xAB, data=0x42

                              ___________
lookup_en __________________|           |__________
key=0xAB
                                          __________
match_found _____________________________|
match_data  XXXXXXXXXXXXXXXXXXXXXXXXXX[0x42]
```

### match_multiple Flag

`match_multiple` is asserted when two or more entries share the same key.  This
indicates a table inconsistency (duplicate insert) and can be used to trigger an
error response or a flush.

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)             cam_error <= 1'b0;
    else if (match_multiple) cam_error <= 1'b1;
end
```

### Usage Example

```systemverilog
content_addressable_memory #(
    .KEY_WIDTH  (48),   // 48-bit MAC address
    .DATA_WIDTH (8),    // output port number
    .DEPTH      (64)
) u_mac_cam (
    .clk           (clk),
    .rst_n         (rst_n),
    .write_en      (learn_en),
    .key_in        (frame_src_mac),
    .data_in       (ingress_port),
    .lookup_en     (fwd_lookup_en),
    .match_data    (egress_port),
    .match_index   (),
    .match_found   (dst_known),
    .match_multiple(),
    .flush         (flush_table)
);
```

### Area Scaling

Area grows **linearly** with `DEPTH` because each entry has its own key comparator.
For large tables (> 64 entries) consider `hash_table_fixed` or
`set_associative_table` which trade exactness for smaller area.

---

## tagged_lookup_table

### Overview

`tagged_lookup_table` is a **cache-style** key-value store.  Each slot stores a
`(tag, data, valid)` triple.  A lookup (`read_en`) searches for a matching `tag_in`
and returns `hit` / `miss` plus the associated data.

Unlike a CAM, which uses fully parallel comparison, this module uses a **sequential
scan** of the valid entries.  For small depths (≤ 16) the scan completes in a
single cycle via a priority-encoder tree.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `TAG_WIDTH` | 8 | Tag (key) width |
| `DATA_WIDTH` | 8 | Payload width |
| `DEPTH` | 16 | Number of slots |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `write_en` | in | 1 | Insert `(tag_in, data_in)` |
| `tag_in` | in | `TAG_WIDTH` | Tag for write or lookup |
| `data_in` | in | `DATA_WIDTH` | Data to insert |
| `read_en` | in | 1 | Perform lookup on `tag_in` |
| `data_out` | out | `DATA_WIDTH` | Matched data (valid when `hit`) |
| `hit` / `miss` | out | 1 | Lookup outcome |
| `invalidate` | in | 1 | Invalidate all entries |
| `full` | out | 1 | No free slots for new insertions |
| `count` | out | `$clog2(DEPTH)+1` | Number of valid entries |

### Differences vs. CAM

| Feature | `content_addressable_memory` | `tagged_lookup_table` |
|---|---|---|
| Lookup style | Fully parallel | Sequential scan |
| Write replaces existing? | Yes (by key) | Inserts new slot |
| match_multiple detection | Yes | No |
| Invalidate all | `flush` | `invalidate` |
| Typical use | Forwarding tables | Small caches, TLBs |

---

## hash_table_fixed

### Overview

`hash_table_fixed` implements a **fixed-size hash table** with **open chaining**
(multiple slots per bucket).  The key is hashed using XOR-fold to select a bucket.
If a collision occurs, the entry is placed in the next free slot within the same
bucket (up to `SLOTS_PER_BUCKET`).

### XOR-Fold Hashing

The key is divided into `$clog2(NUM_BUCKETS)`-bit chunks that are XOR-folded
together:

```
For KEY_WIDTH=16, NUM_BUCKETS=16 (4-bit index):
  hash = key[3:0] ^ key[7:4] ^ key[11:8] ^ key[15:12]
```

This is a fast, area-efficient hash with reasonable distribution for typical key
distributions.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `KEY_WIDTH` | 8 | Key width |
| `DATA_WIDTH` | 8 | Data width |
| `NUM_BUCKETS` | 16 | Number of hash buckets |
| `SLOTS_PER_BUCKET` | 4 | Entries per bucket (chain length) |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `insert` | in | 1 | Insert `(key_in, data_in)` |
| `lookup` | in | 1 | Look up `key_in` |
| `remove` | in | 1 | Remove entry matching `key_in` |
| `key_in` / `data_in` | in | — | Key/data for insert |
| `data_out` | out | `DATA_WIDTH` | Matched data |
| `hit` / `miss` | out | 1 | Lookup result |
| `full` | out | 1 | All slots occupied |
| `collision` | out | 1 | Insert attempted to a full bucket |

### Collision Handling

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        collision_count <= '0;
    end else if (collision) begin
        collision_count <= collision_count + 1'b1;
    end
end
```

### Usage

```systemverilog
hash_table_fixed #(
    .KEY_WIDTH        (32),
    .DATA_WIDTH       (16),
    .NUM_BUCKETS      (64),
    .SLOTS_PER_BUCKET (4)
) u_ht (
    .clk       (clk),
    .rst_n     (rst_n),
    .insert    (insert_req),
    .lookup    (lookup_req),
    .remove    (remove_req),
    .key_in    (search_key),
    .data_in   (insert_data),
    .data_out  (lookup_result),
    .hit       (lookup_hit),
    .miss      (lookup_miss),
    .full      (table_full),
    .collision (bucket_full)
);
```

---

## set_associative_table

### Overview

`set_associative_table` implements an **N-way set-associative** lookup structure,
modelled on a CPU cache.  The key is split into a *set index* and a *tag*:

```
Key = [ tag_bits | set_index_bits ]
       key[KEY_WIDTH-1 : SET_BITS]  key[SET_BITS-1:0]
```

Each set holds `WAYS` entries.  On a miss that requires eviction, the module uses
**Pseudo-LRU (PLRU)** replacement to select the victim way.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `KEY_WIDTH` | 8 | Total key width |
| `DATA_WIDTH` | 8 | Payload width |
| `NUM_SETS` | 8 | Number of sets (determines `SET_BITS = $clog2(NUM_SETS)`) |
| `WAYS` | 4 | Associativity (entries per set) |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `write_en` | in | 1 | Insert / update entry |
| `read_en` | in | 1 | Lookup `key_in` |
| `invalidate_en` | in | 1 | Invalidate entry matching `key_in` |
| `key_in` | in | `KEY_WIDTH` | Key |
| `data_in` | in | `DATA_WIDTH` | Data for write |
| `data_out` | out | `DATA_WIDTH` | Matched data on hit |
| `hit` / `miss` | out | 1 | Lookup outcome |
| `evict_way` | out | `$clog2(WAYS)` | Way selected for eviction on miss |

### PLRU Replacement

The module maintains a binary tree of `WAYS-1` bits per set for pseudo-LRU tracking.
When a new entry is written (on a miss), the PLRU policy points to the
least-recently-used way, which is overwritten.  After any access (read hit or
write), the PLRU tree is updated to mark the accessed way as recently used.

```
4-way PLRU tree (3 bits):
        [b0]
       /    \
    [b1]    [b2]
   /   \   /   \
  W0   W1 W2   W3

Access W1: set b0=1 (right subtree not recently used), b1=0 (W0 not used)
Next evict: b0=1 -> right; b2 -> LRU way selected
```

### Usage

```systemverilog
set_associative_table #(
    .KEY_WIDTH  (20),  // 20-bit virtual page number
    .DATA_WIDTH (20),  // 20-bit physical frame number
    .NUM_SETS   (16),
    .WAYS       (4)
) u_tlb (
    .clk          (clk),
    .rst_n        (rst_n),
    .write_en     (tlb_fill),
    .read_en      (tlb_lookup),
    .invalidate_en(tlb_flush),
    .key_in       (vpn),
    .data_in      (pfn),
    .data_out     (pfn_out),
    .hit          (tlb_hit),
    .miss         (tlb_miss),
    .evict_way    ()
);
```

---

## free_list_allocator

### Overview

`free_list_allocator` manages a **pool of resource IDs** using a bitmap to track
which IDs are free.  On `alloc`, it returns the lowest-numbered free ID.  On
`free`, it returns a used ID to the pool.

This is the simplest allocator in the library — use it when all you need is
"give me a free ID" and "return this ID".

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_RESOURCES` | 16 | Total number of IDs in the pool |
| `ID_WIDTH` | `$clog2(NUM_RESOURCES)` | ID bit width |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `alloc` | in | 1 | Request a free ID |
| `free` | in | 1 | Return an ID |
| `free_id` | in | `ID_WIDTH` | ID being returned |
| `alloc_id` | out | `ID_WIDTH` | Allocated ID (valid when `alloc_valid`) |
| `alloc_valid` | out | 1 | Allocation succeeded |
| `empty` | out | 1 | No free IDs remain |
| `full` | out | 1 | All IDs are free (none allocated) |
| `count` | out | `$clog2(NUM_RESOURCES)+1` | Number of free IDs |

### Bitmap Pool Management

At reset all `NUM_RESOURCES` IDs are marked free in the bitmap.  The
`alloc` operation scans the bitmap for the lowest set bit (using a priority
encoder), clears that bit, and returns the ID.  The `free` operation sets
the bit corresponding to `free_id`.

```
Initial state (NUM_RESOURCES=8):  bitmap = 8'b11111111 (all free)
alloc: alloc_id=0,  bitmap = 8'b11111110
alloc: alloc_id=1,  bitmap = 8'b11111100
free(id=0):         bitmap = 8'b11111101
alloc: alloc_id=0,  bitmap = 8'b11111100  ← lowest free re-issued
```

### Usage Example

```systemverilog
free_list_allocator #(
    .NUM_RESOURCES (32),
    .ID_WIDTH      (5)
) u_fla (
    .clk        (clk),
    .rst_n      (rst_n),
    .alloc      (dma_req & ~fla_empty),
    .free       (dma_done),
    .free_id    (dma_channel_id),
    .alloc_id   (new_channel_id),
    .alloc_valid(channel_granted),
    .empty      (fla_empty),
    .full       (),
    .count      (free_channels)
);
```

### Relationship to Other Allocators

| Module | Allocation order | Metadata | Use case |
|---|---|---|---|
| `free_list_allocator` | Lowest free ID first | None | Simple ID pools |
| `bitmap_allocator` | Lowest free slot | None | Slot tracking |
| `free_queue` | FIFO (oldest-freed first) | None | Fair resource re-issue |
| `resource_pool` | Lowest free | Per-resource metadata | Buffers with attributes |
| `index_allocator` | Linked-list order | None | Dense linked structures |
