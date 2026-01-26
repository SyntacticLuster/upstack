# WORK — SIM

THREAD: UPSTACK — SIM
THREAD_TYPE: WORK
SCOPE: `res://scripts/sim/Sim.gd, Resources.gd, ModuleInstance.gd`
VERSION: v0.1
LAST_REVIEWED: 2026-01-26

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
6. Evaluate incidents
7. Log

No deviations.

## Power allocation

Priority-first, deterministic ordering.
Debuggable and predictable.

## Incident triggering

- Seeded RNG derived from global_seed and day
- Stable incident ordering
- Threshold + probability based
- Logged outcomes

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
