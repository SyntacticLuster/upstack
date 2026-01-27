REV v0.2 (2026-01-27)

- Update scope to include the implemented incident data file.
- Clarify that incident evaluation is currently executed in `Sim.gd` and is log-only.
- Reason: incidents now exist and the contract should reflect the current repo state.

# WORK — EVENTS

THREAD: UPSTACK — EVENTS
THREAD_TYPE: WORK
SCOPE: `res://scripts/sim/IncidentDefs.gd, res://scripts/sim/Sim.gd (incident evaluation hook)`
VERSION: v0.2
LAST_REVIEWED: 2026-01-27

This contract covers incident data and deterministic trigger rules. Incident evaluation is currently wired through `Sim.gd` as a log-only phase.

## Scope boundary

- Incident definitions
- Threshold logic
- Trigger conditions
- Event resolution (logic only)
- Deterministic incident logging markers

## Excludes

- UI presentation
- Sound/visual effects
- Core sim tick logic (except via explicit hooks)

## Constraints

- Deterministic triggers on thresholds
- Log-only phase first
- No state mutation without explicit design approval

Current implementation note: incident definitions live in `IncidentDefs.gd`; trigger evaluation occurs in `Sim.gd` via a deterministic per-day RNG derived from run seed + day.
