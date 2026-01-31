# ADR-006: Deterministic Headless Playtest Harness

**Status:** Proposed  
**Date:** 2026-01-30  
**Context:** Feature Mode / WORK Thread

## Summary

Design a minimal deterministic playtest harness that runs headlessly via Godot CLI, executes scripted scenarios (trade, expedition, policy toggles), emits structured logs with state signatures, and exits non-zero on invariant failure.

---

## File Layout

```
res://
├── scripts/
│   └── tests/
│       ├── playtest/
│       │   ├── PlaytestRunner.gd        # Main entry point, runs scenarios
│       │   ├── ScenarioLoader.gd        # Parses scenario JSON files
│       │   ├── ActionExecutor.gd        # Executes scenario actions against Sim
│       │   ├── Invariants.gd            # All invariant checks (Trade v1, Expeditions, UI)
│       │   └── PlaytestLogger.gd        # JSON-line logging + signature generation
│       └── determinism_test.gd          # (existing)
│       └── debug_run_days.gd            # (existing)
├── tests/
│   ├── PressureTestRunner.gd            # (existing)
│   ├── TestUtil.gd                      # (existing)
│   └── scenarios/
│       ├── smoke_trade.json             # Basic trade scenario
│       ├── smoke_expedition.json        # Basic expedition scenario
│       ├── stress_combined.json         # Multi-system stress test
│       └── regression_lever_stack.json  # Policy lever stacking
```

---

## Scenario Action Schema

Scenarios are JSON arrays of action objects. Each action has:

```json
{
  "actions": [
    {
      "type": "advance_hours",
      "hours": 24,
      "comment": "Advance one full day"
    },
    {
      "type": "trade",
      "direction": "buy",
      "resource": "food",
      "amount": 5
    },
    {
      "type": "expedition",
      "destination_id": "scrapyard",
      "crew": 2
    },
    {
      "type": "lever",
      "lever_id": "ration_hardening",
      "payload": {
        "mode": "soft",
        "duration_hours": 48
      }
    },
    {
      "type": "set_rations",
      "food_ration": 0.75,
      "water_ration": 1.0
    },
    {
      "type": "wait_expedition_resolve",
      "timeout_hours": 100
    },
    {
      "type": "assert",
      "condition": "res.food >= 10",
      "message": "Food must remain above 10"
    }
  ],
  "metadata": {
    "name": "smoke_trade",
    "seed": 12345,
    "description": "Basic trade buy/sell cycle"
  }
}
```

### Supported Action Types

| Type                    | Required Fields                      | Description                                     |
|-------------------------|--------------------------------------|-------------------------------------------------|
| `advance_hours`         | `hours: int`                         | Advance simulation by N hours                   |
| `advance_days`          | `days: int`                          | Advance simulation by N days (N*24 hours)       |
| `trade`                 | `direction`, `resource`, `amount`    | Queue and execute a trade command               |
| `expedition`            | `destination_id`, `crew`             | Launch an expedition                            |
| `lever`                 | `lever_id`, `payload: {}`            | Apply a policy lever                            |
| `set_rations`           | `food_ration`, `water_ration`        | Set ration multipliers                          |
| `wait_expedition_resolve`| `timeout_hours`                     | Advance until expedition resolves or timeout    |
| `assert`                | `condition`, `message`               | Runtime assertion (fails scenario if false)     |
| `snapshot`              | `label: string`                      | Emit named state snapshot to log                |
| `comment`               | `text: string`                       | No-op, documentation only                       |

---

## CLI Commands (Godot 4 Style)

### Run All Scenarios
```powershell
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd
```

### Run Specific Scenario
```powershell
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd -- --scenario=smoke_trade
```

### Run With Custom Seed Override
```powershell
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd -- --scenario=smoke_trade --seed=99999
```

### Run With Verbose Logging
```powershell
godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd -- --verbose
```

### CI Integration (Exit Codes)
- `0` = All scenarios passed, all invariants held
- `1` = One or more invariant failures
- `2` = Scenario execution error (parse failure, missing file, etc.)

---

## Log Format (JSON Lines)

Each line is a self-contained JSON object. Logs go to stdout (captured by CI).

### Event Log Entry
```json
{"ts":"2026-01-30T10:00:00Z","type":"action","action":"trade","hour":5,"day":1,"payload":{"direction":"buy","resource":"food","amount":5},"result":"ok"}
```

### State Snapshot
```json
{"ts":"...","type":"snapshot","label":"post_trade","hour":5,"day":1,"state":{"food":25,"water":20,"materials":50,"morale":50,"threat":0,"silver":94000,"population":5}}
```

### Invariant Check
```json
{"ts":"...","type":"invariant","name":"TRADE_SILVER_BALANCE","passed":true,"hour":5,"day":1}
```

### Invariant Failure
```json
{"ts":"...","type":"invariant_fail","name":"TRADE_SILVER_BALANCE","message":"Silver went negative after trade","hour":5,"day":1,"expected":"silver >= 0","actual":-1200}
```

### Run Summary (End of Scenario)
```json
{"ts":"...","type":"summary","scenario":"smoke_trade","seed":12345,"hours_simulated":72,"days_simulated":3,"actions_executed":15,"invariants_checked":42,"invariants_passed":42,"invariants_failed":0,"signature":"a3f8c9d2e1b0"}
```

### State Signature Format
Compact hash of critical state for run-to-run comparison:
```
day=3|hour_idx=72|res=food=18,water=22,materials=45,morale=48,threat=5,population=5,power_supply=10,power_used=8,silver=87600,gold=0|staying=0.00|exp_count=1|visibility=true
```

---

## Invariants

### Trade v1 Invariants (5-10)

| ID | Name | Condition | Failure Message |
|----|------|-----------|-----------------|
| T1 | `TRADE_SILVER_NON_NEGATIVE` | `res.silver >= 0` | Silver balance went negative after trade |
| T2 | `TRADE_RESOURCE_NON_NEGATIVE` | `res.{resource} >= 0` for all tradeable | Resource went negative after sell |
| T3 | `TRADE_BUY_COST_CORRECT` | `silver_before - silver_after == amount * buy_rate` | Buy cost calculation incorrect |
| T4 | `TRADE_SELL_REVENUE_CORRECT` | `silver_after - silver_before == amount * sell_rate` | Sell revenue calculation incorrect |
| T5 | `TRADE_RESOURCE_DELTA_CORRECT` | Buy: `res_after = res_before + amount`; Sell: `res_after = res_before - amount` | Resource delta mismatch |
| T6 | `TRADE_ATTENTION_APPLIED` | `attention_after >= attention_before` | Attention cost not applied |
| T7 | `TRADE_ATTENTION_CAPPED` | `attention_cost <= TRADE_ATTENTION_CAP (5.0)` | Attention exceeded cap |
| T8 | `TRADE_AMOUNT_BOUNDS` | `0 < amount <= 999` | Trade amount out of bounds |
| T9 | `TRADE_INVALID_REJECTED` | Invalid trades return `ok=false` | Invalid trade was accepted |
| T10 | `TRADE_EVENT_EMITTED` | Trade action produces exactly one TRADE event | Missing or duplicate trade event |

### Expedition Invariants (5-10)

| ID | Name | Condition | Failure Message |
|----|------|-----------|-----------------|
| E1 | `EXPEDITION_SINGLE_ACTIVE` | `active_expedition.is_empty() OR count == 1` | Multiple expeditions active simultaneously |
| E2 | `EXPEDITION_CREW_VALID` | `crew >= 1 AND crew <= population` | Crew count invalid |
| E3 | `EXPEDITION_STATE_MACHINE` | State transitions follow PLANNED→OUTBOUND→ONSITE→RETURNING→RESOLVED | Invalid state transition |
| E4 | `EXPEDITION_DESTINATION_VALID` | `destination_id` exists in map_def | Expedition to invalid destination |
| E5 | `EXPEDITION_HOURS_PROGRESS` | `hours_in_state` increments each tick while active | Expedition time not progressing |
| E6 | `EXPEDITION_RESOURCES_GAINED` | On RESOLVED, resources gained match destination yields | Resource gain mismatch |
| E7 | `EXPEDITION_THREAT_APPLIED` | Launching expedition increases threat | Threat not applied on launch |
| E8 | `EXPEDITION_EVENT_LAUNCHED` | Launch produces EXPEDITION_LAUNCHED event | Missing launch event |
| E9 | `EXPEDITION_EVENT_RESOLVED` | Resolution produces completion event | Missing resolution event |
| E10 | `EXPEDITION_BLOCKED_WHILE_ACTIVE` | `launch_expedition()` returns `ok=false` when active | Overlapping expedition allowed |

### UI Wiring Invariants (5)

| ID | Name | Condition | Failure Message |
|----|------|-----------|-----------------|
| U1 | `UI_LEVER_STATE_REFLECTS_SIM` | UI lever hours_left matches Sim lever hours_left | Lever state desync |
| U2 | `UI_RESOURCES_MATCH_SIM` | UI displayed resources match `res.snapshot()` | Resource display desync |
| U3 | `UI_EXPEDITION_STATUS_MATCH` | UI expedition panel matches `active_expedition` state | Expedition status desync |
| U4 | `UI_EVENT_FEED_ORDERED` | Events in feed are ordered by sequence number | Event ordering violation |
| U5 | `UI_MAP_LOCATIONS_VALID` | All UI map locations exist in `map_def` | Orphan map location in UI |

---

## Implementation Notes

### Determinism Guarantees

1. **Seeded RNG**: All `RandomNumberGenerator` instances derive seed from `sim_seed + context_offset`
2. **No Time Dependencies**: Use `hour_index` not wall clock
3. **Stable Iteration**: Dictionary keys sorted before iteration where order matters
4. **Float Snapping**: Apply `SIM_FLOAT_SNAP (0.01)` to accumulators

### Invariant Checking Strategy

- **Continuous**: T1, T2, E1 checked every hour tick
- **Post-Action**: T3-T10, E2-E10 checked after relevant action
- **End-of-Scenario**: Summary invariants, determinism signature comparison

### Determinism Verification

Each scenario runs twice with identical seed. Final signatures must match:
```gdscript
var sig_a := _run_scenario(scenario, seed)
var sig_b := _run_scenario(scenario, seed)
assert(sig_a == sig_b, "Determinism violation: %s != %s" % [sig_a, sig_b])
```

---

## Example Scenario: smoke_trade.json

```json
{
  "metadata": {
    "name": "smoke_trade",
    "seed": 12345,
    "description": "Verify basic trade buy/sell mechanics"
  },
  "actions": [
    {"type": "comment", "text": "Setup: start with default state"},
    {"type": "snapshot", "label": "initial"},
    
    {"type": "advance_hours", "hours": 6},
    {"type": "snapshot", "label": "pre_buy"},
    
    {"type": "trade", "direction": "buy", "resource": "food", "amount": 10},
    {"type": "snapshot", "label": "post_buy"},
    {"type": "assert", "condition": "res.food == 30", "message": "Food should be initial(20) + bought(10)"},
    
    {"type": "advance_hours", "hours": 12},
    
    {"type": "trade", "direction": "sell", "resource": "materials", "amount": 5},
    {"type": "snapshot", "label": "post_sell"},
    {"type": "assert", "condition": "res.materials == 45", "message": "Materials should be initial(50) - sold(5)"},
    
    {"type": "advance_days", "days": 2},
    {"type": "snapshot", "label": "final"}
  ]
}
```

---

## Example Scenario: smoke_expedition.json

```json
{
  "metadata": {
    "name": "smoke_expedition",
    "seed": 54321,
    "description": "Verify expedition launch, progress, and resolution"
  },
  "actions": [
    {"type": "snapshot", "label": "initial"},
    
    {"type": "expedition", "destination_id": "scrapyard", "crew": 2},
    {"type": "assert", "condition": "has_active_expedition", "message": "Expedition should be active"},
    {"type": "snapshot", "label": "post_launch"},
    
    {"type": "wait_expedition_resolve", "timeout_hours": 50},
    {"type": "assert", "condition": "!has_active_expedition", "message": "Expedition should be resolved"},
    {"type": "snapshot", "label": "post_resolve"},
    
    {"type": "assert", "condition": "res.materials > 50", "message": "Should have gained materials from scrapyard"},
    
    {"type": "advance_days", "days": 1},
    {"type": "snapshot", "label": "final"}
  ]
}
```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Float drift causes signature mismatch | Apply `SIM_FLOAT_SNAP` consistently; use integer math where possible |
| Scenario JSON parsing errors | Validate schema on load; fail fast with clear error |
| Long-running scenarios timeout CI | Add `--max-hours=N` CLI flag; default to 1000 |
| UI invariants require scene tree | Provide headless stub for SimBridge; skip UI invariants in headless mode |

---

## Next Steps

1. Implement `PlaytestRunner.gd` with CLI argument parsing
2. Implement `ScenarioLoader.gd` with JSON validation
3. Implement `ActionExecutor.gd` with action dispatch
4. Implement `Invariants.gd` with all defined checks
5. Create initial scenario files
6. Add to CI pipeline

---

## References

- [determinism_test.gd](scripts/tests/determinism_test.gd) - Existing determinism verification
- [PressureTestRunner.gd](tests/PressureTestRunner.gd) - Existing pressure test patterns
- [Sim.gd](scripts/sim/Sim.gd) - Core simulation with `_state_signature()`, `queue_trade()`, `launch_expedition()`
