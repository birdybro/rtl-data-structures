# Probabilistic Structures

This document covers all filter and membership modules in `rtl/filters/`.

---

## bloom_filter

### Overview

A **Bloom filter** is a space-efficient probabilistic data structure that answers
the question *"Is this key a member of the set?"* with one of two answers:

1. **"Definitely not"** — zero false negatives: if `not_present` is asserted, the
   key was never inserted.
2. **"Probably yes"** — small false positive probability: if `present` is asserted,
   the key was *likely* (but not certainly) inserted.

This makes Bloom filters ideal as a **fast pre-filter** in front of an exact-match
stage (e.g., a CAM or hash table), eliminating most lookups for keys that are
definitely absent.

### How It Works

The filter maintains an array of `FILTER_SIZE` bits, all initialised to 0.  On
`insert`, `NUM_HASH` independent hash functions are computed from the key, and the
corresponding `NUM_HASH` bits are set.  On `query`, the same bits are checked: if
any bit is 0, the key is definitely absent; if all are 1, the key is probably present.

```
FILTER_SIZE=16, NUM_HASH=3, key=0xAB

hash0(0xAB) = 2   → set bit 2
hash1(0xAB) = 7   → set bit 7
hash2(0xAB) = 11  → set bit 11

Filter: 0000100010000100  (bits 2, 7, 11 set)

Query key=0xAB:  bits 2,7,11 all set → present (correct)
Query key=0xCD:  hash0=5 → bit 5=0   → not_present (correct, no false positive)
```

### False Positive Rate

For a filter with `m` bits, `k` hash functions, and `n` inserted elements:

```
P(false positive) ≈ (1 - e^(-k·n/m))^k
```

Example values for guidance:

| FILTER_SIZE | NUM_HASH | Elements | False positive rate |
|---|---|---|---|
| 64 | 3 | 8 | ≈ 5% |
| 128 | 4 | 16 | ≈ 3% |
| 256 | 5 | 32 | ≈ 2% |
| 1024 | 7 | 100 | ≈ 1% |

The optimal number of hash functions for a given `m` and `n` is:
`k_opt = (m/n) * ln(2) ≈ 0.693 * (m/n)`

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `KEY_WIDTH` | 8 | Width of the input key |
| `FILTER_SIZE` | 64 | Number of bits in the filter array |
| `NUM_HASH` | 3 | Number of independent hash functions |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` / `rst_n` | in | 1 | Clock / active-low reset |
| `insert` | in | 1 | Insert `key_in` into the filter |
| `query` | in | 1 | Query membership of `key_in` |
| `clear` | in | 1 | Clear all bits (reset filter) |
| `key_in` | in | `KEY_WIDTH` | Key to insert or query |
| `present` | out | 1 | Key is probably present |
| `not_present` | out | 1 | Key is definitely not present |

### Timing Diagram

```
          ___     ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___|   |___
          ____
insert ___|    |__________________________________________
key_in =[0xAB]===========================================

                      ____
query  _______________|    |_____________________________
key_in ==================[0xAB]=========================

                              ____
present _____________________|    |______________________
not_present _____________________________________
```

Notes:
- `insert` and `query` can be asserted simultaneously (query result reflects
  the state *before* the insert takes effect on that cycle).
- `present` and `not_present` are registered outputs (valid one cycle after
  `insert`/`query`).

### Usage Example (two-stage pipeline)

```systemverilog
bloom_filter #(
    .KEY_WIDTH   (32),
    .FILTER_SIZE (1024),
    .NUM_HASH    (7)
) u_bf (
    .clk         (clk),
    .rst_n       (rst_n),
    .insert      (table_insert),
    .query       (lookup_req),
    .clear       (table_flush),
    .key_in      (search_key),
    .present     (bf_present),
    .not_present (bf_not_present)
);

// Stage 1 pipeline register
logic s1_valid, s1_bf_present;
logic [31:0] s1_key;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid      <= 1'b0;
        s1_bf_present <= 1'b0;
        s1_key        <= '0;
    end else begin
        s1_valid      <= lookup_req;
        s1_bf_present <= bf_present;
        s1_key        <= search_key;
    end
end

// Only forward to CAM if Bloom says "possibly present"
assign cam_lookup_en = s1_valid & s1_bf_present;
assign cam_key_in    = s1_key;
```

### Hardware Implementation Notes

The hash functions are implemented as XOR-based folding networks:

```
For NUM_HASH=3, FILTER_SIZE=64 (6-bit index), KEY_WIDTH=8:

hash0 = key[5:0] ^ {key[7:6], key[5:4]}   (fold with shift)
hash1 = {key[6:1]} ^ {key[0], key[7:5]}   (rotate-fold)
hash2 = key[7:2] ^ {key[1:0], key[7:6]}   (another rotation)
```

Different rotations/shifts ensure independence while using only XOR gates.

---

## counting_bloom_filter

### Overview

`counting_bloom_filter` extends the standard Bloom filter by replacing each
single bit with a small **counter** (`COUNT_BITS` wide).  This allows elements to
be **deleted** from the filter: on `remove`, the counters are decremented.

The trade-off is additional area (counters vs. bits) and a **counter saturation**
hazard described below.

### Deletion Support

```
Insert key=0xAB: counters at positions {2,7,11} incremented → {1,1,1}
Insert key=0xAB again: counters → {2,2,2}
Remove key=0xAB: counters → {1,1,1}
Remove key=0xAB: counters → {0,0,0}  → key now absent
```

### Counter Saturation

If a counter reaches its maximum value `(2^COUNT_BITS - 1)`, it **saturates** and
does not decrement on remove.  This prevents counter wrap-around introducing false
negatives, but means the entry can never be removed.  Choose `COUNT_BITS` large
enough for your maximum insertion multiplicity.

For typical workloads, `COUNT_BITS=4` (max count 15) is sufficient.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `KEY_WIDTH` | 8 | Key width |
| `FILTER_SIZE` | 32 | Number of counters |
| `NUM_HASH` | 3 | Hash functions |
| `COUNT_BITS` | 4 | Counter width per cell |

### Ports

Same as `bloom_filter` with the addition of:

| Port | Dir | Width | Description |
|---|---|---|---|
| `remove` | in | 1 | Remove `key_in` from filter |

### Usage

```systemverilog
counting_bloom_filter #(
    .KEY_WIDTH   (16),
    .FILTER_SIZE (128),
    .NUM_HASH    (4),
    .COUNT_BITS  (4)
) u_cbf (
    .clk         (clk),
    .rst_n       (rst_n),
    .insert      (flow_add),
    .remove      (flow_expire),
    .query       (flow_lookup),
    .clear       (table_reset),
    .key_in      (flow_id),
    .present     (flow_active),
    .not_present (flow_absent)
);
```

---

## membership_filter

### Overview

`membership_filter` is an **exact** membership filter using a direct-mapped
bitmap.  There are **no false positives**.  It uses `KEY_WIDTH` bits of the key
as a direct index into a `TABLE_SIZE`-bit array.

This is optimal when:
- `KEY_WIDTH` is small (≤ 16 bits), so the table fits in a single FPGA BRAM or
  LUT array,
- False positives are unacceptable and you need exact membership.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `KEY_WIDTH` | 8 | Key width (table has `2^KEY_WIDTH` entries if TABLE_SIZE allows) |
| `TABLE_SIZE` | 256 | Bitmap size in bits |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `insert` | in | 1 | Mark `key_in` as a member |
| `remove` | in | 1 | Remove `key_in` from membership |
| `query` | in | 1 | Test membership of `key_in` |
| `clear` | in | 1 | Remove all members |
| `key_in` | in | `KEY_WIDTH` | Key to insert/remove/query |
| `member` | out | 1 | Key is a member |
| `not_member` | out | 1 | Key is not a member |
| `full` | out | 1 | Maximum distinct members reached |
| `count` | out | `$clog2(TABLE_SIZE)+1` | Current membership count |

### Comparison: Bloom vs. Membership Filter

| | `bloom_filter` | `membership_filter` |
|---|---|---|
| False positives | Yes (tunable) | None |
| False negatives | Never | Never |
| Deletions | No | Yes (`remove`) |
| Area | O(FILTER_SIZE) bits | O(TABLE_SIZE) bits |
| Best key space | Large (> TABLE_SIZE) | Small (≤ TABLE_SIZE) |

---

## signature_match_table

### Overview

`signature_match_table` stores up to `NUM_ENTRIES` signatures (wide keys) with
associated data.  On a `lookup`, all stored signatures are compared in parallel
with `sig_in`.  When a match is found, the associated data is returned.

This module is suited for **pattern matching** use cases such as:
- Intrusion detection rule matching (match against known attack signatures)
- Protocol field matching (match Ethernet type, IP protocol, etc.)
- Content inspection (multi-pattern string matching)

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `SIG_WIDTH` | 16 | Width of each signature |
| `NUM_ENTRIES` | 16 | Maximum stored signatures |
| `DATA_WIDTH` | 8 | Action/metadata width per signature |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `insert` | in | 1 | Store `(sig_in, data_in)` |
| `lookup` | in | 1 | Search for `sig_in` |
| `clear_entry` | in | 1 | Invalidate entry matching `sig_in` |
| `sig_in` | in | `SIG_WIDTH` | Signature to insert or match |
| `data_in` | in | `DATA_WIDTH` | Action associated with signature |
| `data_out` | out | `DATA_WIDTH` | Action for matched signature |
| `match` | out | 1 | Signature matched |
| `no_match` | out | 1 | No signature matched |
| `full` | out | 1 | Table is full |

### Usage: Network Packet Classification

```systemverilog
// Match on {IP_proto[7:0], dst_port[15:0]} = 24-bit signature
signature_match_table #(
    .SIG_WIDTH   (24),
    .NUM_ENTRIES (32),
    .DATA_WIDTH  (4)    // action code
) u_acl (
    .clk         (clk),
    .rst_n       (rst_n),
    .insert      (rule_insert),
    .lookup      (pkt_valid),
    .clear_entry (rule_delete),
    .sig_in      ({ip_proto, dst_port}),
    .data_in     (rule_action),
    .data_out    (pkt_action),
    .match       (pkt_classified),
    .no_match    (pkt_default),
    .full        (rules_full)
);
```

### Timing

Like the CAM, signature comparison is fully parallel.  Results are registered and
valid one cycle after `lookup` is asserted.

```
          ___     ___     ___
clk   ___|   |___|   |___|   |___
          ____
lookup ___|    |_________________
sig_in = [MATCH_SIG]

                    ____
match  _____________|    |_______
data_out _________[ACTION]_______
```

---

## Selecting the Right Filter

| Requirement | Recommended module |
|---|---|
| Fast pre-filter, false positives OK | `bloom_filter` |
| Pre-filter with deletion support | `counting_bloom_filter` |
| Exact membership, small key space | `membership_filter` |
| Wide-key pattern matching with metadata | `signature_match_table` |
| Exact key-value lookup, small table | `content_addressable_memory` (see associative docs) |
