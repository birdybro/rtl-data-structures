# Scheduler Patterns

This document covers every scheduling module in `rtl/schedulers/`.

---

## round_robin_scheduler

### Overview

`round_robin_scheduler` grants access to one of `NUM_CLIENTS` requesters in a
rotating order.  Each cycle it scans from the client *after* the last-granted one,
granting the next active requester.  This ensures no client is starved as long as
it eventually deasserts its request.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_CLIENTS` | 8 | Number of clients |
| `ID_WIDTH` | `$clog2(NUM_CLIENTS)` | Width of grant ID |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` / `rst_n` | in | 1 | Clock / reset |
| `request` | in | `NUM_CLIENTS` | One bit per client; 1 = requesting |
| `grant` | out | `NUM_CLIENTS` | One-hot grant vector |
| `grant_valid` | out | 1 | At least one client granted |
| `grant_id` | out | `ID_WIDTH` | Binary-encoded ID of granted client |
| `advance` | in | 1 | Pulse to consume current grant and advance pointer |

### Timing Diagram

```
          ___     ___     ___     ___     ___
clk   ___|   |___|   |___|   |___|   |___|   |___

request   1111    1111    1011    1011    1011
          (A,B,C,D requesting)

grant     0001    0010    0100    0001    0010
          (D)     (C)     (B-skip A) ...
advance _____|___|    |___|    |___
```

### Usage

```systemverilog
round_robin_scheduler #(
    .NUM_CLIENTS (4)
) u_rr (
    .clk         (clk),
    .rst_n       (rst_n),
    .request     (client_req),
    .grant       (client_grant),
    .grant_valid (grant_valid),
    .grant_id    (granted_id),
    .advance     (xfer_done)    // advance when transfer completes
);
```

---

## priority_scheduler

### Overview

`priority_scheduler` grants the highest-priority active requester.  Each client
provides a `PRIO_BITS`-wide priority value.  Among clients at the same priority
level, round-robin arbitration is applied to ensure fairness.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_CLIENTS` | 8 | Number of clients |
| `PRIORITY_LEVELS` | 4 | Distinct priority levels |
| `ID_WIDTH` | `$clog2(NUM_CLIENTS)` | Grant ID width |
| `PRIO_BITS` | `$clog2(PRIORITY_LEVELS)` | Priority field width |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `request` | in | `NUM_CLIENTS` | Request bitmap |
| `priority_in` | in | `NUM_CLIENTS × PRIO_BITS` | Packed priority per client |
| `grant` | out | `NUM_CLIENTS` | One-hot grant |
| `grant_id` | out | `ID_WIDTH` | Granted client ID |
| `grant_valid` | out | 1 | Valid grant this cycle |
| `advance` | in | 1 | Consume grant and re-arbitrate |

### Priority Encoding

`priority_in` is a flat packed vector.  Client `i`'s priority occupies bits
`[i*PRIO_BITS +: PRIO_BITS]`.  Lower numeric value = higher priority (same
convention as `priority_queue_linear`).

```systemverilog
// Pack priorities for 4 clients
assign priority_in = {client3_prio, client2_prio, client1_prio, client0_prio};
```

---

## aging_scheduler

### Overview

`aging_scheduler` extends `priority_scheduler` with **anti-starvation aging**.
Each waiting client accumulates an age counter.  The effective priority is:

```
effective_priority = base_priority - (age >> AGE_SHIFT)
```

So a low-priority client that has been waiting long enough will eventually be
promoted above higher-priority clients that just arrived.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_CLIENTS` | 8 | Number of clients |
| `MAX_AGE` | 15 | Maximum age counter value |
| `AGE_BITS` | 4 | Age counter width |
| `ID_WIDTH` | `$clog2(NUM_CLIENTS)` | Grant ID width |
| `BASE_PBITS` | 2 | Base priority field width |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `request` | in | `NUM_CLIENTS` | Request bitmap |
| `base_prio_in` | in | `NUM_CLIENTS × BASE_PBITS` | Base priority per client |
| `grant` | out | `NUM_CLIENTS` | One-hot grant |
| `grant_id` | out | `ID_WIDTH` | Granted client ID |
| `grant_valid` | out | 1 | Valid grant |
| `advance` | in | 1 | Consume grant |

### Starvation Prevention Example

```
Client A: base_prio=0 (highest), arrives at cycle 0
Client B: base_prio=3 (lowest),  arrives at cycle 0

Without aging: A granted every cycle, B starves forever
With aging:    B's age counter increases each cycle it waits;
               after MAX_AGE cycles, B's effective priority surpasses A's
               → B is eventually granted
```

---

## deficit_round_robin_scheduler

### Overview

`deficit_round_robin_scheduler` (DRR) is designed for clients that send
**variable-size** work units (e.g., packets of different lengths).  Each client is
assigned a quantum; each round it may transmit up to `quantum + deficit` bytes.
Any unused allowance carries forward as a deficit, ensuring byte-level fairness
over time.

### DRR Algorithm

```
For each active client i in round-robin order:
    deficit[i] += quantum[i]
    while request[i] and deficit[i] >= packet_size[i]:
        grant client i
        deficit[i] -= packet_size[i]
    if !request[i]:
        deficit[i] = 0   // clear deficit when queue empties
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_CLIENTS` | 8 | Number of clients |
| `QUANTUM_BITS` | 8 | Quantum / deficit counter width |
| `ID_WIDTH` | `$clog2(NUM_CLIENTS)` | Grant ID width |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `request` | in | `NUM_CLIENTS` | Active client bitmap |
| `quantum` | in | `NUM_CLIENTS × QUANTUM_BITS` | Per-client quantum (packed) |
| `packet_size` | in | `QUANTUM_BITS` | Size of the current head-of-queue packet |
| `grant` | out | 1 | Grant pulse |
| `grant_id` | out | `ID_WIDTH` | Granted client |
| `grant_valid` | out | 1 | Valid grant |
| `advance` | in | 1 | Advance to next client |

### Usage

```systemverilog
deficit_round_robin_scheduler #(
    .NUM_CLIENTS  (4),
    .QUANTUM_BITS (10)
) u_drr (
    .clk         (clk),
    .rst_n       (rst_n),
    .request     (flow_active),
    .quantum     ({flow3_q, flow2_q, flow1_q, flow0_q}),
    .packet_size (hd_pkt_len),
    .grant       (send_grant),
    .grant_id    (send_flow),
    .grant_valid (grant_valid),
    .advance     (pkt_sent)
);
```

---

## token_bucket_shaper

### Overview

`token_bucket_shaper` implements a **token bucket** rate limiter.  Tokens
accumulate at `fill_rate` tokens per `tick`, up to a maximum of `burst_size`.
When a `consume` request arrives, it is allowed (`allow=1`) if at least one token
is available, and a token is deducted.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `TOKEN_BITS` | 16 | Token counter width |
| `RATE_BITS` | 8 | Fill rate field width |
| `BURST_BITS` | 16 | Burst size field width |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `tick` | in | 1 | Refill tick (e.g., from a divider for desired rate) |
| `consume` | in | 1 | Request to consume one token |
| `fill_rate` | in | `RATE_BITS` | Tokens added per tick |
| `burst_size` | in | `BURST_BITS` | Maximum token accumulation |
| `token_count` | out | `TOKEN_BITS` | Current token level |
| `allow` | out | 1 | consume was granted (token deducted) |
| `full` | out | 1 | Token bucket is full |
| `empty` | out | 1 | No tokens available |

### Token Bucket vs. Leaky Bucket

| | Token Bucket | Leaky Bucket |
|---|---|---|
| Burst allowed | Yes (up to `burst_size`) | No (constant drain rate) |
| Excess tokens | Accumulated up to burst | Discarded |
| RTL model | This module | `consume` every N ticks unconditionally |

### Usage: Rate-Limiting an AXI Stream

```systemverilog
// Generate a 125 MHz tick from a 1 GHz clock (÷8)
logic [2:0] tick_div;
always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) tick_div <= '0;
    else        tick_div <= tick_div + 1'b1;
assign rate_tick = (tick_div == 3'd7);

token_bucket_shaper #(
    .TOKEN_BITS (16),
    .RATE_BITS  (8),
    .BURST_BITS (16)
) u_tbs (
    .clk         (clk),
    .rst_n       (rst_n),
    .tick        (rate_tick),
    .consume     (axis_valid & axis_ready),
    .fill_rate   (8'd10),        // 10 tokens per tick
    .burst_size  (16'd1000),     // burst up to 1000 tokens
    .token_count (),
    .allow       (axis_ready),
    .full        (),
    .empty       (bucket_empty)
);
```

---

## credit_pool_manager

### Overview

`credit_pool_manager` tracks **per-flow credits** across `NUM_FLOWS` flows.
Credits are added with `add_credit` and consumed with `consume_credit`.  The
module indicates whether the selected flow has credits available (`credit_ok`) or
is exhausted (`credit_zero`).

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `NUM_FLOWS` | 8 | Number of independent flow credit pools |
| `CREDIT_BITS` | 16 | Per-flow credit counter width |
| `FLOW_ID_BITS` | `$clog2(NUM_FLOWS)` | Flow ID width |

### Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `add_credit` | in | 1 | Add `credit_amount` to flow `flow_id` |
| `consume_credit` | in | 1 | Consume one unit from flow `flow_id` |
| `flow_id` | in | `FLOW_ID_BITS` | Target flow |
| `credit_amount` | in | `CREDIT_BITS` | Credits to add (used with `add_credit`) |
| `credit_ok` | out | 1 | Selected flow has credits |
| `credit_zero` | out | 1 | Selected flow has no credits |
| `total_credits` | out | `CREDIT_BITS + FLOW_ID_BITS` | Aggregate credit info |

### Usage: Weighted Fair Queuing

```systemverilog
credit_pool_manager #(
    .NUM_FLOWS   (8),
    .CREDIT_BITS (16)
) u_cpm (
    .clk           (clk),
    .rst_n         (rst_n),
    .add_credit    (credit_refill),
    .consume_credit(pkt_sent),
    .flow_id       (active_flow),
    .credit_amount (flow_weight[active_flow]),
    .credit_ok     (flow_has_credit),
    .credit_zero   (flow_starved),
    .total_credits ()
);
// Only schedule flows with credits
assign schedule_flow = flow_has_credit & flow_active[active_flow];
```

---

## Choosing the Right Scheduler

| Requirement | Module |
|---|---|
| Simple fair arbitration, equal weights | `round_robin_scheduler` |
| Fixed priority classes, RR within class | `priority_scheduler` |
| Priority with starvation prevention | `aging_scheduler` |
| Variable-size work units, byte fairness | `deficit_round_robin_scheduler` |
| Rate limiting / traffic shaping | `token_bucket_shaper` |
| Per-flow credit accounting | `credit_pool_manager` |
