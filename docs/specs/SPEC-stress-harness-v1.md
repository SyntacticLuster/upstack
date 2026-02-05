# SPEC: Single-Run Stress Harness Extension (v1)

**Status**: IMPLEMENTATION-READY  
**Thread**: SPEC  
**Author**: Codex  
**Date**: 2026-01-31  

---

## 1. OBJECTIVE

Extend the existing `PlaytestRunner` and associated playtest infrastructure into a **single-process stress suite** capable of:

1. Hammering ALL simulation systems in one run
2. Reliably surfacing: invariant violations, determinism drift, bad scaling, NaN/Inf state, expedition/people bugs, command-queue/compliance bugs, and module accounting errors
3. Producing reproducible failure artifacts for debugging

---

## 2. KEY OBSERVATIONS FROM CURRENT IMPLEMENTATION

| Observation | Impact |
|-------------|--------|
| `PlaytestRunner` prefers `res://scripts/tests/scenarios` but scenarios there are stale (e.g., `materials==50` vs default `220`) | Scenario mismatch causes false failures |
| Commands execute during daily production tick (`Sim._step_day_core`), not immediately after enqueue | Tests calling direct methods bypass queued command path |
| `PlaytestLogger._timestamp()` uses system time (`Time.get_datetime_dict_from_system`) | Non-deterministic log output breaks diff-based CI |
| `ActionExecutor` tests trade/expedition via direct method calls, not via `CMD_*` queue | Incomplete coverage of compliance stall logic |
| Invariants check only T1-T10, E1-E10 (trade/expedition) | No coverage for: levers, modules, people system, numeric sanity, structural strain |

---

## 3. IMPLEMENTATION CHECKLIST

### 3.1 SCENARIO DISCOVERY UNIFICATION

**Goal**: Single authoritative scenario directory with explicit override support.

| Step | File | Change |
|------|------|--------|
| 3.1.1 | `PlaytestRunner.gd` | Remove `FALLBACK_SCENARIOS_DIR` constant |
| 3.1.2 | `PlaytestRunner.gd` | Add CLI flag `--scenarios-dir=<path>` to override `SCENARIOS_DIR` |
| 3.1.3 | `PlaytestRunner.gd` | On startup, emit resolved directory to log: `{"type":"config","scenarios_dir":"..."}` |
| 3.1.4 | `scripts/tests/scenarios/` | Delete or archive; canonical location becomes `tests/scenarios/` |
| 3.1.5 | `PlaytestRunner.gd` | Change `SCENARIOS_DIR` default to `"res://tests/scenarios"` |

**Validation**: Single source of truth; no silent fallback behavior.

---

### 3.2 STRESS/FUZZ MECHANISM: DETERMINISTIC ACTION GENERATOR

**Goal**: A `StressActionGenerator` class that produces deterministic action sequences for N hours/days.

| Step | File | Change |
|------|------|--------|
| 3.2.1 | Create `scripts/tests/playtest/StressActionGenerator.gd` | New RefCounted class |
| 3.2.2 | `StressActionGenerator._init(seed: int, config: Dictionary)` | Store RNG seed, action probabilities, bounds |
| 3.2.3 | `StressActionGenerator.next_action(sim: Sim) -> Dictionary` | Generate next action based on sim state + RNG |
| 3.2.4 | `StressActionGenerator` | Weighted action selection from pool (see §3.2.5) |
| 3.2.5 | `StressActionGenerator` | Action pool (all must be exercised): |

```gdscript
const ACTION_WEIGHTS := {
    "advance_hours": 40,       # Most common
    "cmd_rations": 8,          # CMD_SET_RATIONS via queue
    "cmd_expedition": 12,      # CMD_EXPEDITION via queue
    "cmd_trade": 12,           # CMD_TRADE via queue
    "cmd_module_enable": 6,    # CMD_SET_MODULE_ENABLED via queue
    "cmd_module_priority": 4,  # CMD_SET_MODULE_PRIORITY via queue
    "cmd_outsiders": 4,        # CMD_OUTSIDERS_DECISION via queue
    "lever_apply": 8,          # apply_lever() for all lever types
    "wait_expedition": 4,      # wait for expedition resolve
    "snapshot": 2,             # state capture
}
```

| Step | File | Change |
|------|------|--------|
| 3.2.6 | `StressActionGenerator._gen_cmd_expedition(sim: Sim) -> Dictionary` | Pick valid destination, crew 1..max_party_size |
| 3.2.7 | `StressActionGenerator._gen_cmd_trade(sim: Sim) -> Dictionary` | Random resource, direction, amount 1..50 |
| 3.2.8 | `StressActionGenerator._gen_lever_apply(sim: Sim) -> Dictionary` | Cycle through all 6 lever types with valid payloads |
| 3.2.9 | `StressActionGenerator._gen_cmd_module_enable(sim: Sim) -> Dictionary` | Random module coords, enable/disable toggle |
| 3.2.10 | `StressActionGenerator._gen_advance_hours(_sim: Sim) -> Dictionary` | 1-6 hours, biased toward 1 |
| 3.2.11 | `StressActionGenerator` | Track action history for ring buffer dump on failure |

---

### 3.3 EXPANDED ACTION SURFACE IN ActionExecutor

**Goal**: All actions route through the command queue path where applicable.

| Step | File | Change |
|------|------|--------|
| 3.3.1 | `ActionExecutor.gd` | Add `_exec_cmd_rations(action)` → `sim.enqueue_command(CMD_SET_RATIONS, ...)` |
| 3.3.2 | `ActionExecutor.gd` | Add `_exec_cmd_expedition(action)` → `sim.enqueue_command(CMD_EXPEDITION, ...)` then advance to production hour |
| 3.3.3 | `ActionExecutor.gd` | Add `_exec_cmd_trade(action)` → uses existing `queue_trade()` but verifies execution at production hour |
| 3.3.4 | `ActionExecutor.gd` | Add `_exec_cmd_module_enable(action)` → `sim.enqueue_command(CMD_SET_MODULE_ENABLED, ...)` |
| 3.3.5 | `ActionExecutor.gd` | Add `_exec_cmd_module_priority(action)` → `sim.enqueue_command(CMD_SET_MODULE_PRIORITY, ...)` |
| 3.3.6 | `ActionExecutor.gd` | Add `_exec_cmd_outsiders(action)` → `sim.enqueue_command(CMD_OUTSIDERS_DECISION, ...)` |
| 3.3.7 | `ActionExecutor.gd` | Modify `execute()` match block to include new `cmd_*` action types |
| 3.3.8 | `ScenarioLoader.gd` | Add new action types to `VALID_ACTION_TYPES` |

**Critical**: After enqueueing a command, advance sim to production hour to force execution via `_phase_commands()`.

---

### 3.4 INVARIANT SUITE UPGRADE

**Goal**: Comprehensive, named invariants with clear failure messages.

#### 3.4.1 Numeric Sanity Invariants (NS-*)

| ID | Check | Implementation |
|----|-------|----------------|
| NS-1 | No NaN in Resources floats | `is_nan(res.morale_ceiling)`, `is_nan(res.attention_multiplier)`, etc. |
| NS-2 | No Inf in Resources floats | `is_inf(res.attention_multiplier)`, `is_inf(res.strain)`, etc. |
| NS-3 | Threat clamped 0..999 | Pre-clamp value check during `_step_day_core` entry |
| NS-4 | Morale 0..floor(morale_ceiling) | After `clamp_all()`, verify invariant |
| NS-5 | Population >= 0 | `res.population >= 0` every tick |
| NS-6 | No negative resources | All of food, water, materials, silver >= 0 |
| NS-7 | Strain clamped 0..100 | `res.strain` bounds check |
| NS-8 | Power accounting | `power_used <= power_supply` or flag shortfall |

**File**: Add `_check_NS_*` methods to `Invariants.gd`.

#### 3.4.2 People System Invariants (PS-*)

| ID | Check | Implementation |
|----|-------|----------------|
| PS-1 | Alive count == population | `sim._alive_people_count() == sim.res.population` |
| PS-2 | No duplicate person IDs | Set check on `_people[*].id` |
| PS-3 | Valid status values | Each person.status in {home, away, injured, dead} |
| PS-4 | Away status during expedition | Expedition members have status "away" while active |
| PS-5 | Reconcile on resolve | After expedition resolve, members return to "home" (or "dead") |

**File**: Add `_check_PS_*` methods to `Invariants.gd`.

#### 3.4.3 Expedition System Invariants (EX-*)

| ID | Check | Implementation |
|----|-------|----------------|
| EX-1 | At most one active expedition | `active_expedition.is_empty()` or valid structure |
| EX-2 | Valid state machine transitions | OUTBOUND→ONSITE→RETURNING→RESOLVED (already E3) |
| EX-3 | Party size bounds | 1 <= party_size <= max_party_size(population) |
| EX-4 | Member IDs valid | All member_ids exist in _people with status "away" |
| EX-5 | Haul sanity | If risk > 0 and no loss event, haul > 0 expected (flag if total_haul == 0 for crew >= 2) |

**File**: Extend existing expedition checks in `Invariants.gd`.

#### 3.4.4 Command Queue Invariants (CQ-*)

| ID | Check | Implementation |
|----|-------|----------------|
| CQ-1 | Commands apply at production tick | After `_phase_commands()`, queue is empty |
| CQ-2 | Stall does not mutate on stall | Pre/post snapshot equality for stalled commands |
| CQ-3 | Compliance only affects expedition/trade | Other commands always execute |

**File**: Add `_check_CQ_*` methods to `Invariants.gd`.

#### 3.4.5 Lever Invariants (LV-*)

| ID | Check | Implementation |
|----|-------|----------------|
| LV-1 | Duration countdown correct | `hours_left` decrements by 1 per hour |
| LV-2 | Scar accumulation bounds | `ration_scar`, `labor_scar` non-negative |
| LV-3 | Intensity bounds | e.g., `labor_overdrive_intensity <= 5` |
| LV-4 | Expiration clears state | When hours_left reaches 0, lever state resets |

#### 3.4.6 Module Accounting Invariants (MA-*)

| ID | Check | Implementation |
|----|-------|----------------|
| MA-1 | Power balance | Sum of module power_supply >= power_used |
| MA-2 | Abandoned modules stay disabled | If abandoned, `is_module_enabled` returns false |
| MA-3 | Module priority ordering | Priorities are unique integers per floor |

---

### 3.5 DETERMINISM REQUIREMENTS

| Step | File | Change |
|------|------|--------|
| 3.5.1 | `PlaytestLogger.gd` | Add `deterministic_mode: bool = false` flag |
| 3.5.2 | `PlaytestLogger._timestamp()` | If `deterministic_mode`, return `"T0"` or sim hour as string |
| 3.5.3 | `PlaytestRunner.gd` | Add CLI flag `--deterministic-output` to set logger mode |
| 3.5.4 | `PlaytestRunner.gd` | Run scenario twice (already done); compare full log output in deterministic mode |
| 3.5.5 | All logs | Avoid any system-time, PID, or random ordering in output |

---

### 3.6 FAILURE ARTIFACTS SPEC

**Goal**: On any invariant failure, dump structured artifacts for debugging.

#### 3.6.1 `failure.json` Structure

```json
{
  "version": 1,
  "timestamp_system": "2026-01-31T12:34:56Z",
  "scenario": "stress_all",
  "seed": 99999,
  "failure_hour": 1234,
  "failure_day": 51,
  "invariant_id": "NS-1",
  "invariant_message": "NaN detected in morale_ceiling",
  "expected": "finite float",
  "actual": "NaN",
  "signature": "day=51|hour_idx=1234|res=...",
  "signature_hash": "a1b2c3d4",
  "last_n_actions": [
    {"type": "cmd_trade", "payload": {...}, "hour": 1230},
    {"type": "advance_hours", "hours": 2, "hour": 1232},
    {"type": "lever", "lever_id": "labor_overdrive", "hour": 1233}
  ],
  "state_snapshots": {
    "pre_failure": {...},
    "failure": {...}
  },
  "rng_history_tail": [
    {"context": "expedition_roll", "value": 0.42},
    {"context": "compliance_stall", "value": 0.87}
  ]
}
```

| Step | File | Change |
|------|------|--------|
| 3.6.1 | `PlaytestRunner.gd` | Add `_dump_failure_artifact(scenario, invariant, sim, action_history)` |
| 3.6.2 | `PlaytestRunner.gd` | Write to `user://playtest_failures/failure_<scenario>_<seed>_<hour>.json` |
| 3.6.3 | `Invariants.gd` | On failure, call runner callback with failure context |

#### 3.6.2 `ticks.jsonl` Ring Buffer

| Step | File | Change |
|------|------|--------|
| 3.6.4 | `PlaytestRunner.gd` | Maintain ring buffer of last 200 tick snapshots |
| 3.6.5 | Tick snapshot structure | `{"hour": N, "day": D, "resources": {...}, "active_expedition": {...}, "levers": {...}}` |
| 3.6.6 | On failure | Dump ring buffer to `user://playtest_failures/ticks_<scenario>_<seed>.jsonl` |

---

### 3.7 PERFORMANCE APPROACH

| Step | File | Change |
|------|------|--------|
| 3.7.1 | `PlaytestRunner.gd` | Default `_max_hours = 2000` (existing is 1000) |
| 3.7.2 | `PlaytestRunner.gd` | CLI flag `--max-hours=N` already exists; increase default |
| 3.7.3 | `Invariants.gd` | Add `_sampling_interval: int = 1` for expensive checks |
| 3.7.4 | `Invariants.check_continuous()` | Skip PS-1, PS-2 if `hour_index % sampling_interval != 0` |
| 3.7.5 | `PlaytestRunner.gd` | CLI flag `--invariant-sampling=N` to control interval |
| 3.7.6 | Output | Log total invariant checks, passes, time elapsed |

---

### 3.8 STRESS SCENARIO DESIGN: `stress_all.json`

**Location**: `tests/scenarios/stress_all.json`

```json
{
  "metadata": {
    "name": "stress_all",
    "seed": 777777,
    "description": "Deterministic chaos loop covering all simulation systems",
    "mode": "generated",
    "generator": "StressActionGenerator",
    "target_hours": 2000
  },
  "generator_config": {
    "action_weights": {
      "advance_hours": 40,
      "cmd_rations": 8,
      "cmd_expedition": 12,
      "cmd_trade": 12,
      "cmd_module_enable": 6,
      "cmd_module_priority": 4,
      "cmd_outsiders": 4,
      "lever_apply": 8,
      "wait_expedition": 4,
      "snapshot": 2
    },
    "force_coverage": [
      "ration_hardening",
      "labor_overdrive",
      "expedition_compression",
      "information_throttling",
      "module_abandonment",
      "emergency_conversion"
    ],
    "expedition_destinations": ["scrapyard", "reservoir", "greenhouse", "bunker", "outpost"],
    "trade_bounds": {"min": 1, "max": 50},
    "lever_durations": {"min_hours": 12, "max_hours": 96}
  },
  "actions": "GENERATED"
}
```

| Step | File | Change |
|------|------|--------|
| 3.8.1 | `PlaytestRunner.gd` | Detect `"mode": "generated"` in metadata |
| 3.8.2 | `PlaytestRunner.gd` | If generated, instantiate `StressActionGenerator` with config |
| 3.8.3 | `PlaytestRunner._run_generated_scenario()` | Loop: generate action → execute → check invariants → repeat until target_hours |
| 3.8.4 | Action logging | Record every generated action in history ring buffer |

---

## 4. MINIMUM INVARIANT IMPLEMENTATION

### 4.1 Numeric Sanity (Priority: CRITICAL)

```gdscript
func check_numeric_sanity(sim: Sim, logger: RefCounted) -> void:
    _check_NS1_no_nan(sim, logger)
    _check_NS2_no_inf(sim, logger)
    _check_NS3_threat_bounds(sim, logger)
    _check_NS4_morale_bounds(sim, logger)
    _check_NS5_population_non_negative(sim, logger)
    _check_NS6_resources_non_negative(sim, logger)

func _check_NS1_no_nan(sim: Sim, logger: RefCounted) -> void:
    _checked += 1
    var nan_fields: Array[String] = []
    if is_nan(sim.res.morale_ceiling):
        nan_fields.append("morale_ceiling")
    if is_nan(sim.res.attention_multiplier):
        nan_fields.append("attention_multiplier")
    if is_nan(sim.res.collapse_debt):
        nan_fields.append("collapse_debt")
    if is_nan(sim.res.strain):
        nan_fields.append("strain")
    if is_nan(sim.ration_scar):
        nan_fields.append("ration_scar")
    if is_nan(sim.labor_scar):
        nan_fields.append("labor_scar")
    if is_nan(sim.expedition_attention):
        nan_fields.append("expedition_attention")
    
    if nan_fields.is_empty():
        _passed += 1
        logger.log_invariant("NS1_NO_NAN", true, sim.hour_index, sim.day)
    else:
        _failed += 1
        logger.log_invariant_fail(
            "NS1_NO_NAN",
            "NaN detected in fields: %s" % ", ".join(nan_fields),
            sim.hour_index,
            sim.day,
            "all finite",
            "NaN in: %s" % ", ".join(nan_fields)
        )
```

### 4.2 People System (Priority: HIGH)

```gdscript
func check_people_system(sim: Sim, logger: RefCounted) -> void:
    _check_PS1_alive_equals_population(sim, logger)
    _check_PS2_no_duplicate_ids(sim, logger)
    _check_PS3_valid_statuses(sim, logger)

func _check_PS1_alive_equals_population(sim: Sim, logger: RefCounted) -> void:
    _checked += 1
    var alive_count: int = sim._alive_people_count()
    var population: int = sim.res.population
    
    if alive_count == population:
        _passed += 1
        logger.log_invariant("PS1_ALIVE_EQUALS_POP", true, sim.hour_index, sim.day)
    else:
        _failed += 1
        logger.log_invariant_fail(
            "PS1_ALIVE_EQUALS_POP",
            "Alive people count mismatch",
            sim.hour_index,
            sim.day,
            str(population),
            str(alive_count)
        )
```

---

## 5. FILE CHANGES SUMMARY

| File | Type | Changes |
|------|------|---------|
| `PlaytestRunner.gd` | MODIFY | CLI args, generated scenario support, failure artifacts, ring buffer |
| `ActionExecutor.gd` | MODIFY | Add `cmd_*` action types routing through command queue |
| `Invariants.gd` | MODIFY | Add NS-*, PS-*, EX-*, CQ-*, LV-*, MA-* invariant suites |
| `PlaytestLogger.gd` | MODIFY | Deterministic timestamp mode |
| `ScenarioLoader.gd` | MODIFY | Add new action types, generated mode detection |
| `StressActionGenerator.gd` | CREATE | Deterministic action generator class |
| `tests/scenarios/stress_all.json` | CREATE | Stress scenario definition |
| `scripts/tests/scenarios/*` | DELETE | Remove stale duplicate scenarios |

---

## 6. EXECUTION ORDER

1. **Phase 1**: Scenario directory unification (3.1.*)
2. **Phase 2**: Determinism fixes in logger (3.5.*)
3. **Phase 3**: Expanded invariant suite (3.4.*)
4. **Phase 4**: Command queue action types (3.3.*)
5. **Phase 5**: StressActionGenerator (3.2.*)
6. **Phase 6**: Failure artifacts (3.6.*)
7. **Phase 7**: stress_all.json scenario (3.8.*)
8. **Phase 8**: Performance tuning (3.7.*)

---

## 7. ACCEPTANCE CRITERIA

| Criterion | Verification |
|-----------|--------------|
| All systems exercised in single run | stress_all completes 2000 hours touching trade, expedition, all levers, module commands |
| Determinism verified | Two identical runs produce byte-identical log output in deterministic mode |
| No NaN/Inf escapes | NS-1, NS-2 checks pass for full stress run |
| People system consistent | PS-1 never fails for full stress run |
| Failure artifacts generated | Introduce intentional bug, verify failure.json and ticks.jsonl created |
| Performance acceptable | 2000-hour stress run completes in < 30 seconds headless |

---

## 8. RISKS AND MITIGATIONS

| Risk | Mitigation |
|------|------------|
| StressActionGenerator produces impossible actions | Validate action against sim state before execution; skip and log if invalid |
| Ring buffer memory pressure | Cap at 200 entries; only dump on failure |
| Expensive invariants slow down long runs | Sampling interval with CLI control |
| Generated actions too random to find bugs | Add "force_coverage" patterns that guarantee specific sequences |

---

## 9. NON-GOALS (Explicit)

- ❌ OrbitSuite or any other repo/project crossfeed
- ❌ Balance changes
- ❌ UI changes
- ❌ Multi-process parallelism
- ❌ Network/multiplayer considerations

---

## 10. APPENDIX: COMMAND QUEUE EXECUTION FLOW

```
enqueue_command(CMD_*) → _command_queue.append()
         ↓
_advance_hour() until hour_of_day == scheduled_production_hour
         ↓
_step_day_core()
         ↓
_phase_commands() ← Commands execute here
         ↓
_command_queue.clear()
```

**Critical for testing**: After enqueueing, must advance to production hour to observe effect.
