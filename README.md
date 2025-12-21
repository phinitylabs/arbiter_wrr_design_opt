# Resource Optimization: Weighted Round Robin Arbiter with Atomic Lock Support

## Overview

This repository contains a Reinforcement Learning (RL) task for hardware design agents. The goal is to **optimize an existing, functionally correct** Weighted Round Robin (WRR) Arbiter that supports **Atomic Locking**. The current implementation meets all functional requirements but suffers from excessive area usage and poor timing paths.

The objective is to refactor the RTL to reduce resource utilization (Area) and improve critical path timing (Performance) while maintaining strict functional equivalence.

## Motivation: Why this Task?

We chose this task to target specific weaknesses in current Large Language Models (LLMs) regarding **micro-architecture optimization**. While LLMs can often generate functional code, they struggle to visualize the physical hardware implications of that code (e.g., LUT inference, logic depth).

Key challenges this task presents to an agent:

* **Redundancy Identification:** The reference design uses separate counters for weighting and timeout logic where a single shared resource could suffice. The agent must identify and merge these datapath elements.
* **Critical Path Reduction:** The original grant logic is implemented as a deep priority encoder chain. The agent needs to restructure this into a more parallel look-ahead structure to improve timing slack.
* **Preserving Corner Cases:** A common failure mode in optimization is "over-pruning." The agent must realize that complex locking logic—even if rarely triggered—cannot be removed. It must optimize the common path without breaking the corner cases (atomic lock support).

## Industry Relevance

In modern semiconductor design, getting RTL to "work" is only 20% of the job. The remaining 80% is optimizing for **PPA (Power, Performance, Area)**.

* **Area Efficiency (Cost):** In high-volume NoC (Network-on-Chip) routers, an arbiter is instantiated hundreds of times. Saving even a few dozen gates per instance translates to significant silicon area savings.
* **Timing Closure (Frequency):** Arbiters often sit on the critical path of bus interconnects. If the arbitration logic is too deep, it limits the maximum frequency of the entire system.
* **Functional Equivalence Checking:** This task mimics the real-world engineering workflow of "refactoring legacy code," requiring the agent to ensure that performance improvements do not introduce regression bugs.

## Context Codebase Description

The repository is structured to mimic a standard hardware optimization workflow.

| Directory / File | Description |
| :--- | :--- |
| **`sources/`** | Contains the SystemVerilog RTL source code. |
| `sources/arbiter_wrr_lock.sv` | **The optimization target.** Contains a working but inefficient implementation (high area, deep logic). The agent must refactor this file. |
| **`tests/`** | Contains the verification environment. |
| `tests/test_arbiter_regression.py` | The hidden `cocotb` regression suite. Unlike a design task, this testbench is strict about **functional equivalence**—the optimized design must match the behavior of the original exactly. |
| **`docs/`** | Contains the technical documentation. |
| `docs/optimization_goals.md` | Defines the specific targets (e.g., "Reduce LUT count by 20%", "Improve Setup Slack by 15%") and the baseline metrics. |
| **Root** | |
| `prompt.txt` | The high-level optimization directive provided to the agent/engineer. |
| `pyproject.toml` | Python dependencies required to run the `cocotb` simulations. |