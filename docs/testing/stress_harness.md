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
- `--strict-command-deltas`: enables optional production-compensated checks for queued `cmd_trade`/`cmd_expedition` actions.
- `--strict-delta-sampling=<int>`: sample every N eligible queued commands when strict mode is on (default 25).

## Logging modes

By default, log timestamps are deterministic so every entry uses the monotonic `T#` sequence that stays in lockstep between runs. Enabling `--nondeterministic-logs` injects wall-clock timestamps so you can correlate entries with real time, but those logs can no longer be compared across seeds or repetitions because the timestamps will differ.

## Failure artifacts

Artifacts are written under:

```
<out-dir>/<scenario>_<seed>/
```

Files:

- `failure.json`: failure details, invariant id/message, last actions, and signature.
- `strict_delta`: (present only on strict-mode failures) captures POST_A, POST_B, and delta summary immediately after the offending command.
- `ticks.jsonl`: ring buffer of the last 200 tick snapshots.
- `summary.json`: run summary and determinism status.
- `determinism_diff.json`: only when determinism repeat mismatches.

## Repeat-for-determinism

`--repeat-for-determinism` runs the scenario twice with the same seed and compares action/signature sequences. If the saved `summary.json` indicates a non-determinism mismatch, `determinism_diff.json` holds the first divergence in order, count, or command arguments. This is the recommended way to prove that a seed stays deterministic before logging artifacts from the run.

## Strict command deltas

`--strict-command-deltas` enables optional production-compensated checks for queued `cmd_trade` and `cmd_expedition` actions, which are the primary places stall drift can be masked by production updates. Strict mode snapshots the command queue before and after processing, throws on any delta that would otherwise be hidden by the normal production tick, and writes the `strict_delta` artifact with `POST_A`, `POST_B`, and the delta summary for quick triage.

`--strict-delta-sampling=<int>` lets the harness run those checks on every Nth eligible queued command when strict mode is on (default 25). Lower values reduce the window for hidden drift at the cost of runtime; CI pipelines typically pick a sampling step (for example 5) that balances coverage and timing.

## Stress scenario

`res://tests/scenarios/stress_all.json` runs a generated deterministic action loop and exercises:

- command queue via `cmd_*` actions
- trade/expedition/lever systems
- module enable/priority updates
- outsiders decision (when pending)

## Trade action semantics

Stress actions now emit two distinct trade types:

- `trade_immediate`: a test-only path that calls `_cmd_trade` directly so the immediate invariants (T1-T9) stay exercised.
- `cmd_trade`: the queued command path that runs through `enqueue_command`/production and surfaces the command queue invariants and compliance behavior.

`stress_all.json` weights `cmd_trade` significantly heavier (16 vs. 4) so the queued path remains the primary focus while the immediate action keeps direct trade checks alive.

## Recommended CI commands

Documented commands keep automation aligned with the harness expectations. Replace any `user://` directories or output paths as needed in your CI.

- **Full suite** (every scenario discovered by default):
  ```
  godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd
  ```
- **stress_all (fixed seed)**:
  ```
  godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd --scenario=stress_all --seed=777777
  ```
- **Repeat-for-determinism** (verifies two identical runs stay in sync):
  ```
  godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd --scenario=stress_all --seed=777777 --repeat-for-determinism
  ```
- **Strict-command-deltas + sampling** (checks production-compensated queues and samples aggressively):
  ```
  godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd --scenario=stress_all --seed=777777 --strict-command-deltas --strict-delta-sampling=5
  ```
