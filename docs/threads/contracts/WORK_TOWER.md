# WORK — TOWER

THREAD: UPSTACK — TOWER
THREAD_TYPE: WORK
SCOPE: `res://scripts/sim/Tower.gd`
VERSION: v0.1
LAST_REVIEWED: 2026-01-26

Tower.gd is the authoritative source of structural truth.

## Responsibilities

- Grid footprint occupancy
- Floor stack order
- Module placement validation
- Structural serialization hooks

No resources, power, UI, or balance logic.

## Core invariants

- One module per cell
- Deterministic floor order
- Pure placement validation
- Atomic placement operations
- Stable internal ordering

## Data model

- floors: Array (deterministic order)
- occupancy: Dictionary keyed by stable cell key
- monotonic floor_id and module_id counters

No reliance on dictionary iteration order.

## Footprint resolution

- Normalize footprint to absolute cells
- Rectangle or custom shape
- Stable resolution order

## Placement API

- can_place (pure)
- place (atomic)
- remove

Return structured results, not booleans.

## Floor stacking

Prefer implicit index-based floors.
Explicit z-ordering only if required.

## Serialization hooks

- to_layout_dict
- from_layout_dict

Structural data only.

## Acceptance criteria

- Deterministic placement
- Testable validation
- No partial mutation on failure
