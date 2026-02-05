# Stress Harness (Single-Run)

This document describes the single-process deterministic stress harness and its artifacts.

## Run (headless)

All scenarios (default directory):

```
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd
```

Only stress_all with explicit seed:

```
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd --scenario=stress_all --seed=777777
```

Repeat for determinism:

```
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd --scenario=stress_all --seed=777777 --repeat-for-determinism
```

Override scenarios directory:

```
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd --scenarios-dir=res://tests/scenarios
```

## Flags

- `--scenario=<name>`: run a single scenario by name.
- `--seed=<int>`: override scenario seed.
- `--max-hours=<int>`: cap simulation hours (default 2000).
- `--repeat-for-determinism`: run scenario twice and compare signature sequences.
- `--scenarios-dir=<path>`: override scenario discovery directory (default `res://tests/scenarios`).
- `--out-dir=<path>`: output directory root (default `user://playtests`).
- `--invariant-sampling=<int>`: run expensive invariants every N ticks (default 1).
- `--nondeterministic-logs`: enable wall-clock timestamps in logs.

## Deterministic logging

By default, log timestamps are deterministic (monotonic `T#` sequence). Use `--nondeterministic-logs` to re-enable wall-clock timestamps.

## Failure artifacts

Artifacts are written under:

```
<out-dir>/<scenario>_<seed>/
```

Files:

- `failure.json`: failure details, invariant id/message, last actions, and signature.
- `ticks.jsonl`: ring buffer of the last 200 tick snapshots.
- `summary.json`: run summary and determinism status.
- `determinism_diff.json`: only when determinism repeat mismatches.

## Stress scenario

`res://tests/scenarios/stress_all.json` runs a generated deterministic action loop and exercises:

- command queue via `cmd_*` actions
- trade/expedition/lever systems
- module enable/priority updates
- outsiders decision (when pending)
