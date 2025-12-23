# Weighted Round Robin Arbiter with Atomic Lock Support - Specification

## 1. Overview

This module implements a Weighted Round Robin (WRR) arbiter with atomic lock support for managing access to a shared resource among multiple clients.

## 2. Interface

### Parameters
- `NUM_CLIENTS`: Number of clients (default: 4), always a power of 2
- `WEIGHT_WIDTH`: Width of weight values in bits (default: 4)

### Inputs
- `clk`: Clock signal
- `rst_n`: Active-low asynchronous reset
- `i_req[NUM_CLIENTS-1:0]`: Request signals from clients (one-hot encoding possible)
- `i_lock[NUM_CLIENTS-1:0]`: Lock signals from clients
- `i_weight[NUM_CLIENTS*WEIGHT_WIDTH-1:0]`: Packed weight configuration for all clients

### Outputs
- `o_gnt[NUM_CLIENTS-1:0]`: Grant signals to clients (one-hot encoding)

## 3. Functional Requirements

### 3.1 Round Robin Arbitration
- When multiple clients request access, the arbiter grants access in round-robin order
- The arbiter maintains a pointer that advances to the next requesting client after the current grant expires
- After reset, the pointer starts at position N-1, so the first search checks Client 0 first

### 3.2 Weighted Fairness
- Each client has an associated weight value (0 to 2^WEIGHT_WIDTH - 1)
- A client with weight W holds the grant for (W + 1) clock cycles when continuously requesting
- Weight of 0 means the client gets exactly 1 cycle
- Weights can be updated dynamically via the `i_weight` input

### 3.3 Atomic Lock Support
- A client holding the grant can assert its lock signal to maintain access indefinitely
- Lock is only valid when asserted by the current grant holder
- Lock assertions from non-granted clients must be ignored
- While locked, the weight counter decrements normally (if > 0) but the grant is not released
- Lock can extend access beyond the normal weight-based duration

### 3.4 Work Conservation
- If the current grant holder drops its request before exhausting its weight, the arbiter immediately moves to the next requesting client
- The arbiter should never stay idle when there are pending requests

### 3.5 Reset Behavior
- On reset (`rst_n` = 0):
  - All grants are de-asserted
  - Round-robin pointer is set to NUM_CLIENTS - 1
  - Weight counter is reset to 0
  - Active state is cleared

## 4. Weight Packing Format

The `i_weight` input is a packed array where each client's weight occupies `WEIGHT_WIDTH` bits:
```
i_weight = [ CLIENT_(N-1)_WEIGHT | ... | CLIENT_1_WEIGHT | CLIENT_0_WEIGHT ]
```

For example, with NUM_CLIENTS=4 and WEIGHT_WIDTH=4:
- Bits [3:0] = Client 0 weight
- Bits [7:4] = Client 1 weight
- Bits [11:8] = Client 2 weight
- Bits [15:12] = Client 3 weight

## 5. Timing

- All state changes occur on the rising edge of `clk`
- Reset is asynchronous and active-low
- Grant output is registered (changes on clock edge)

## 6. Optimization Goals

The implementation should aim to:
- Minimize resource utilization (LUTs, registers)
- Achieve at least 67% reduction in resource usage compared to baseline
- Maintain functional correctness across all scenarios
- Avoid unnecessary state registers or combinational logic

