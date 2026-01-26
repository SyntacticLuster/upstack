UPSTACK — CANON (Rules + Seed v0)

CANON THREAD CONTRACT
---------------------
This document is an append-only ledger of verified facts about the UPSTACK project.
The contract for messages recorded here is as follows:

- **Allowed operations:** every entry must begin with one of the keywords `ADD`, `PATCH`, `REF` or `SCOPE_ACK`.
  - `ADD vX.Y` appends new verified facts to this file.
  - `PATCH vX.Y` corrects a previous fact; it must include a `WAS → NOW` explanation and a reason.
  - `REF vX.Y` points to another thread by name, without including its details.
  - `SCOPE_ACK vX.Y` is reserved for contract violation handling (see below).

- **Forbidden content:** CANON must never contain:
  - implementation plans, pseudocode, code snippets
  - design brainstorming, tuning, balance discussion
  - “next steps” beyond a one-line pointer
  - anything speculative, unverified, or “we should”

- **Verification requirement:** every `ADD` and `PATCH` entry must include an `EVIDENCE:` line.
  - Evidence must be one of:
    - observed runtime output line(s)
    - file path(s) that exist in the repo
    - explicit behavior that was run and seen
  - If evidence is not available, the entry must be rejected (do not record it in CANON).

- **Violation handling protocol:**
  - If an assistant response violates this contract, the user replies with `SCOPE`.
  - The next assistant response must be `SCOPE_ACK vX.Y` followed by a corrected compliant entry or refusal.
  - No argument, no additional content.

- **Versioning rules:**
  - Start at `v0.0` for the Seed.
  - Increment minor for new verified facts (`v0.1`, `v0.2`, …).
  - Increment patch for corrections (`v0.1.1`, `v0.1.2`, …).

Scope boundary
--------------
CANON covers only what exists in the Godot project on disk and has been run/observed.
No marketplace/legal/marketing content. No future design.

Required sections
-----------------
- Environment
- Project Structure
- Runtime Behavior
- Systems Implemented
- Known Verified Failure Modes
- File List (authoritative)
- Pointers (WORK / TRIAGE / DECISIONS threads)

ADD v0.0: CANON Seed (Verified Project State)
--------------------------------------------

### Environment
- Godot scene format indicates Godot 4.x (`format=3` in `.tscn`).
EVIDENCE: `scenes/game/Game.tscn` begins with `[gd_scene load_steps=2 format=3 ...]`.

- Repository: `SyntacticLuster/upstack` (private), default branch `main`.
EVIDENCE: GitHub search results identify `SyntacticLuster/upstack` with default branch `main`.

### Project Structure
- Root scene: `scenes/game/Game.tscn`.
EVIDENCE: File exists at `scenes/game/Game.tscn`.

- Root nodes declared in `Game.tscn`: `Game` (Node), with children `Sim` (Node), `TowerView` (Node2D), `UI` (CanvasLayer).
EVIDENCE: `scenes/game/Game.tscn` includes:
  - `[node name="Game" type="Node"]`
  - `[node name="Sim" type="Node" parent="."]`
  - `[node name="TowerView" type="Node2D" parent="."]`
  - `[node name="UI" type="CanvasLayer" parent="."]`

- `Sim` node uses script `res://scripts/sim/Sim.gd`.
EVIDENCE: `Game.tscn` defines an ext_resource with `path="res://scripts/sim/Sim.gd"` and assigns it to `Sim` node `script`.

### Runtime Behavior
- `Sim` prints a “Day 0” resource summary on `_ready()` and prints a per-day summary line during `_process()` when accumulated time exceeds `seconds_per_day`.
EVIDENCE: `scripts/sim/Sim.gd` contains:
  - `print("Day 0:", res.summary())`
  - In `_process(delta)`: increments `_accum`, advances `day`, calls `_step_day()`, emits `tick`, and prints `print("Day %d: %s" % [day, res.summary()])`.

- `seconds_per_day` is exported and defaults to `1.0`.
EVIDENCE: `scripts/sim/Sim.gd` declares `@export var seconds_per_day: float = 1.0`.

### Systems Implemented
- Tower model exists as `class_name Tower` and stores a 2D grid per floor; default construction adds one floor.
EVIDENCE: `scripts/sim/Tower.gd` defines `class_name Tower`, `floors: Array = []`, `_init(w,h)` calls `add_floor()`, and `add_floor()` allocates a `height x width` grid of `null`.

- Module system exists with `ModuleDef`, `ModuleDB`, `ModuleInstance`.
EVIDENCE:
  - `scripts/sim/ModuleDef.gd` defines `class_name ModuleDef`
  - `scripts/sim/ModuleDB.gd` defines `class_name ModuleDB`
  - `scripts/sim/ModuleInstance.gd` defines `class_name ModuleInstance`

- Default module definitions are created in `ModuleDB._load_defaults()` with ids: `core`, `generator`, `housing`, `purifier`, `hydro`, `workshop`.
EVIDENCE: `scripts/sim/ModuleDB.gd` calls `add(_mk("core", ...))` etc. for those ids.

- Power accounting exists as per-day variables `power_supply` and `power_used` on `Resources`, and `Sim` computes them in `_step_day()`.
EVIDENCE:
  - `scripts/sim/Resources.gd` defines `var power_supply: int = 0`, `var power_used: int = 0`, and includes them in `summary()`.
  - `scripts/sim/Sim.gd` resets `res.power_supply` and `res.power_used` each day and increments them based on module defs.

- Unpowered modules apply a morale penalty of `-1` per unpowered module in the day step.
EVIDENCE: `scripts/sim/Sim.gd` else-branch includes `res.morale -= 1` for unpowered instances.

### Known Verified Failure Modes
(Empty: no runtime observation logs were captured in this CANON seed beyond the existence of print statements and code paths.)

EVIDENCE: No observed runtime output lines were collected in this seed beyond code inspection.

### File List (authoritative)
- `scenes/game/Game.tscn`
- `scripts/sim/Sim.gd`
- `scripts/sim/Tower.gd`
- `scripts/sim/Resources.gd`
- `scripts/sim/ModuleDef.gd`
- `scripts/sim/ModuleDB.gd`
- `scripts/sim/ModuleInstance.gd`

EVIDENCE: Each file above was fetched from the `main` branch of the repository.

### Pointers
These pointers link to other threads without including their details:

REF v0.0: UPSTACK — WORK
REF v0.0: UPSTACK — TRIAGE
REF v0.0: UPSTACK — DECISIONS

EVIDENCE: The files listed above (`scenes/game/Game.tscn`, `scripts/sim/Sim.gd`, `scripts/sim/Tower.gd`, `scripts/sim/Resources.gd`, `scripts/sim/ModuleDef.gd`, `scripts/sim/ModuleDB.gd`, `scripts/sim/ModuleInstance.gd`) are present in the `SyntacticLuster/upstack` repository and have been fetched from the `main` branch.
