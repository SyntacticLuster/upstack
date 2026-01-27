REV v0.3 (2026-01-27)

- Add deterministic starvation counter phase before population resolution.
- Document that water-driven population loss occurs after 3 consecutive dry days.
- Reason: align contract with current survival modeling and improve failure legibility.

REV v0.2 (2026-01-27)

- Update daily tick sequence to include population resolution, maintenance debt, and incident evaluation after maintenance.
- Clarify incident triggers use a deterministic per-day RNG derived from run seed + day.
- Reason: current `Sim.gd` behavior has evolved beyond v0.1 and the contract must match reality.

# WORK — SIM

THREAD: UPSTACK — SIM
THREAD_TYPE: WORK
SCOPE: `res://scripts/sim/Sim.gd, Resources.gd, ModuleInstance.gd`
VERSION: v0.3
LAST_REVIEWED: 2026-01-27

Core simulation logic and deterministic world-state progression.

## Determinism rules

- Fixed tick cadence (day increments exactly once per tick)
- Stable iteration order
- No frame-time dependence
- No unseeded randomness
- Single deterministic RNG source

Unordered dictionary iteration is a determinism bug.

## Resources.gd responsibilities

- Authoritative resource quantities
- Per-day delta accumulation
- Deterministic delta application
- Snapshot and logging support

All application must occur in stable key order.

## ModuleInstance.gd responsibilities

- Encapsulate per-module effects
- Declare power demand
- Compute deltas given allocated power
- No global state mutation

compute_resource_deltas returns data only.

## Sim.gd responsibilities

- Own day index and module order
- Allocate power deterministically
- Collect and apply resource deltas
- Accumulate threat
- Trigger incidents deterministically
- Log results

## Daily tick sequence

1. Reset deltas
2. Allocate power
3. Collect module deltas
4. Apply deltas
5. Update threat
6. Clamp bounds
7. Update starvation counters
8. Resolve population loss (water loss after 3 dry days)
9. Apply maintenance debt
10. Evaluate incidents and threat-threshold markers (log-only)
11. Log

No deviations.

## Power allocation

Priority-first, deterministic ordering.
Debuggable and predictable.

## Incident triggering

- Seeded RNG derived from run seed and day
- Stable incident ordering
- Threshold + probability based
- Logged outcomes

Determinism note: incident RNG must be derived from a per-day seed and must not mutate global RNG state.

## Logging requirements

One line per day including:

- day
- power generated/used
- resource snapshot
- threat
- incidents

Identical inputs must produce byte-identical logs.

## Acceptance criteria

- Deterministic per-day simulation
- Headless execution possible
- Logs sufficient to verify behavior
