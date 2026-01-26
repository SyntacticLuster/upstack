# WORK — EVENTS

THREAD: UPSTACK — EVENTS
THREAD_TYPE: WORK
SCOPE: `res://scripts/sim/Incident*.gd (future)`
VERSION: v0.1
LAST_REVIEWED: 2026-01-26

This file is intentionally a stub until an EVENTS thread output is reviewed and pasted here.

## Scope boundary

- Incident definitions
- Threshold logic
- Trigger conditions
- Event resolution (logic only)

## Excludes

- UI presentation
- Sound/visual effects
- Core sim tick logic (except via explicit hooks)

## Constraints

- Deterministic triggers on thresholds
- Log-only phase first
- No state mutation without explicit design approval
