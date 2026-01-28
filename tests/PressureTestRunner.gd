extends Node

const SIM_SCRIPT: Script = preload("res://scripts/sim/Sim.gd")
const OPERATIONS_CONSOLE: Script = preload("res://scripts/ui/OperationsConsole.gd")
const TEST_UTIL: Script = preload("res://tests/TestUtil.gd")

const TEST_OUTPUT_DIR: String = "user://pressure_tests"
const RUN_A_PATH: String = "%s/runA.json" % TEST_OUTPUT_DIR
const RUN_B_PATH: String = "%s/runB.json" % TEST_OUTPUT_DIR
const PAUSED_PATH: String = "%s/paused_test.json" % TEST_OUTPUT_DIR

const RUN_SEED: int = 12345
const DURATION_HOURS: int = 72

const BASE_SECONDS_PER_HOUR: float = 10.0
const MULTIPLIER: float = 2.0
const TICK_INTERVAL: float = BASE_SECONDS_PER_HOUR / MULTIPLIER
const DELTA_SECONDS: float = 120.0
const MAX_TICKS_PER_FRAME: int = 3

const HARNESS_LEVER_SCHEDULE: Array = [
	{
		"hour": 3,
		"lever_id": OPERATIONS_CONSOLE.LEVER_RATION_HARDENING,
		"payload": {"mode": "hard", "duration_days": 4},
	},
	{
		"hour": 7,
		"lever_id": OPERATIONS_CONSOLE.LEVER_LABOR_OVERDRIVE,
		"payload": {"intensity": 3, "duration_days": 4},
	},
	{
		"hour": 12,
		"lever_id": OPERATIONS_CONSOLE.LEVER_EXPEDITION_COMPRESSION,
		"payload": {"intensity": 2, "duration_days": 5},
	},
	{
		"hour": 25,
		"lever_id": OPERATIONS_CONSOLE.LEVER_INFORMATION_THROTTLING,
		"payload": {"level": 3, "duration_days": 6},
	},
	{
		"hour": 49,
		"lever_id": OPERATIONS_CONSOLE.LEVER_EMERGENCY_CONVERSION,
		"payload": {"from": "food", "to": "materials", "amount": 5},
	},
]

const PAUSE_LEVER_CONFIG: Dictionary = {
	"lever_id": OPERATIONS_CONSOLE.LEVER_INFORMATION_THROTTLING,
	"payload": {"level": 2, "duration_days": 3},
}

func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	var overall_success: bool = true
	if not TEST_UTIL.ensure_dir(TEST_OUTPUT_DIR):
		print("Failed to create %s" % TEST_OUTPUT_DIR)
		overall_success = false
	else:
		print("Output directory ready: %s" % TEST_OUTPUT_DIR)
	if not _run_determinism_test():
		overall_success = false
	if not _run_paused_and_clamp_tests():
		overall_success = false
	get_tree().quit(0 if overall_success else 1)

func _run_determinism_test() -> bool:
	print("Running deterministic pressure test schedule")
	var result_a: Dictionary = _run_simulation(HARNESS_LEVER_SCHEDULE, RUN_SEED)
	var result_b: Dictionary = _run_simulation(HARNESS_LEVER_SCHEDULE, RUN_SEED)
	var snapshot_a: Dictionary = result_a["snapshot"]
	var snapshot_b: Dictionary = result_b["snapshot"]
	var success: bool = result_a["ok"] and result_b["ok"]
	var json_a: String = TEST_UTIL.stable_json(snapshot_a)
	var json_b: String = TEST_UTIL.stable_json(snapshot_b)
	var deterministic: bool = json_a == json_b
	if not deterministic:
		_report_determinism_mismatch(snapshot_a, snapshot_b)
		success = false
	if not TEST_UTIL.write_json(RUN_A_PATH, snapshot_a):
		print("Failed to write runA output")
		success = false
	if not TEST_UTIL.write_json(RUN_B_PATH, snapshot_b):
		print("Failed to write runB output")
		success = false
	print("Run A path: %s" % RUN_A_PATH)
	print("Run B path: %s" % RUN_B_PATH)
	if deterministic:
		print("Determinism check: outputs match")
	else:
		print("Determinism check failed")
	return success and deterministic

func _run_paused_and_clamp_tests() -> bool:
	print("Running paused lever immediacy and pacing clamp tests")
	var paused_result: Dictionary = _run_paused_lever_test()
	var clamp_result: Dictionary = _run_clamp_test()
	var combined: Dictionary = {
		"paused_lever_test": paused_result["data"],
		"clamp_simulation_test": clamp_result["data"],
	}
	var wrote: bool = TEST_UTIL.write_json(PAUSED_PATH, combined)
	if not wrote:
		print("Failed to write paused/clamp output")
	else:
		print("Paused/clamp test path: %s" % PAUSED_PATH)
	return paused_result["ok"] and clamp_result["ok"] and wrote

func _run_simulation(schedule: Array, seed: int) -> Dictionary:
	var sim: Sim = _build_sim_instance(seed)
	var levers_ok: bool = true
	for _i in range(DURATION_HOURS):
		sim._advance_hour()
		levers_ok = levers_ok and _apply_levers_for_hour(sim, schedule)
	var snapshot: Dictionary = _gather_run_snapshot(sim)
	return {"snapshot": snapshot, "ok": levers_ok}

func _build_sim_instance(seed: int) -> Sim:
	var sim: Sim = SIM_SCRIPT.new() as Sim
	sim.sim_seed = seed
	sim._setup_default_state()
	sim.day = 0
	sim.hour_index = 0
	sim.hour_of_day = 0
	sim.phase = "HOUR_TICK"
	sim._accum = 0.0
	sim.lever_events.clear()
	return sim

func _apply_levers_for_hour(sim: Sim, schedule: Array) -> bool:
	var ok: bool = true
	var current_hour: int = sim.hour_index
	for entry in schedule:
		if entry is Dictionary:
			var target_hour: int = int(entry.get("hour", -1))
			if target_hour != current_hour:
				continue
			var lever_id: String = str(entry.get("lever_id", ""))
			var payload: Dictionary = (entry.get("payload", {}) as Dictionary).duplicate(true)
			var applied: bool = sim.apply_lever(lever_id, payload)
			if not applied:
				print("Lever %s rejected at hour %d" % [lever_id, current_hour])
			ok = ok and applied
	return ok

func _gather_run_snapshot(sim: Sim) -> Dictionary:
	return {
		"seed": sim.sim_seed,
		"final_hour_index": sim.hour_index,
		"final_day": sim.day,
		"final_hour_of_day": sim.hour_of_day,
		"phase": sim.phase,
		"resources": _resource_snapshot(sim.res),
		"lever_events": _copy_lever_events(sim.lever_events),
	}

func _resource_snapshot(res: Resources) -> Dictionary:
	return {
		"food": res.food,
		"water": res.water,
		"materials": res.materials,
		"morale": res.morale,
		"threat": res.threat,
		"population": res.population,
		"power_supply": res.power_supply,
		"power_used": res.power_used,
		"days_without_food": res.days_without_food,
		"days_without_water": res.days_without_water,
		"morale_ceiling": res.morale_ceiling,
		"staying_index": res.staying_index,
	}

func _copy_lever_events(events: Array) -> Array:
	var copies: Array = []
	for entry in events:
		if entry is Dictionary:
			var copy: Dictionary = entry.duplicate(true)
			copies.append(copy)
	return copies

func _report_determinism_mismatch(run_a: Dictionary, run_b: Dictionary) -> void:
	print("Determinism mismatch detected between run A and run B")
	if run_a.has("resources") and run_b.has("resources"):
		print("  resources runA: %s" % run_a["resources"])
		print("  resources runB: %s" % run_b["resources"])
	var count_a: int = run_a.get("lever_events", []).size()
	var count_b: int = run_b.get("lever_events", []).size()
	print("  lever_events count: %d vs %d" % [count_a, count_b])

func _run_paused_lever_test() -> Dictionary:
	var sim: Sim = _build_sim_instance(RUN_SEED)

	for _unused in range(5):
		sim._advance_hour()

	var before_snapshot: Dictionary = _capture_pause_snapshot(sim)
	var lever_id: String = str(PAUSE_LEVER_CONFIG.get("lever_id", ""))
	var payload: Dictionary = (PAUSE_LEVER_CONFIG.get("payload", {}) as Dictionary).duplicate(true)

	var applied: bool = sim.apply_lever(lever_id, payload)

	var after_snapshot: Dictionary = _capture_pause_snapshot(sim)
	var time_delta: int = int(after_snapshot.get("hour_index", 0)) - int(before_snapshot.get("hour_index", 0))
	var changed_fields: Array = _detect_pause_changes(before_snapshot, after_snapshot)

	var success: bool = applied and time_delta == 0 and changed_fields.size() > 0

	if success:
		print("Paused lever immediacy confirmed for %s" % lever_id)
	else:
		print("Paused lever test failed: delta=%d changed=%s" % [time_delta, str(changed_fields)])

	var data: Dictionary = {
		"pre_lever_state": before_snapshot,
		"post_lever_state": after_snapshot,
		"lever": {"id": lever_id, "payload": payload, "result": applied},
		"time_delta_hours": time_delta,
		"changed_fields": changed_fields
	}
	return {"data": data, "ok": success}

func _capture_pause_snapshot(sim: Sim) -> Dictionary:
	return {
		"day": sim.day,
		"hour_index": sim.hour_index,
		"hour_of_day": sim.hour_of_day,
		"info_throttle_level": sim.info_throttle_level,
		"info_throttle_days_left": sim.info_throttle_days_left,
		"info_throttle_backlog": sim.info_throttle_backlog,
		"lever_events_count": sim.lever_events.size(),
	}

func _detect_pause_changes(before: Dictionary, after: Dictionary) -> Array:
	var changed: Array = []
	var keys: Array = [
		"info_throttle_level",
		"info_throttle_days_left",
		"info_throttle_backlog",
		"lever_events_count",
	]
	for key in keys:
		var key_str: String = str(key)
		if before.get(key_str) != after.get(key_str):
			changed.append(key_str)
	return changed

func _run_clamp_test() -> Dictionary:
	var pending_seconds: float = DELTA_SECONDS
	var accumulator: float = 0.0
	var frame_hours: Array = []
	var total_hours: int = 0
	while pending_seconds > 0 or accumulator >= TICK_INTERVAL:
		var delta: float = 0.0
		if pending_seconds > 0:
			delta = min(pending_seconds, DELTA_SECONDS)
			pending_seconds -= delta
		accumulator += delta
		var ticks_this_frame: int = 0
		while accumulator >= TICK_INTERVAL and ticks_this_frame < MAX_TICKS_PER_FRAME:
			accumulator -= TICK_INTERVAL
			ticks_this_frame += 1
			total_hours += 1
		if delta == 0.0 and ticks_this_frame == 0:
			break
		frame_hours.append(ticks_this_frame)
	var expected_hours: int = int(floor(DELTA_SECONDS / TICK_INTERVAL))
	var max_frame: int = 0
	for count in frame_hours:
		var frame_count: int = int(count)
		if frame_count > max_frame:
			max_frame = frame_count
	var clamp_ok: bool = total_hours == expected_hours and max_frame <= MAX_TICKS_PER_FRAME
	if clamp_ok:
		print("Clamp pacing test succeeded (%d hours in %d frames)" % [total_hours, frame_hours.size()])
	else:
		print("Clamp pacing test failed: expected %d hours, got %d (max frame %d)" % [expected_hours, total_hours, max_frame])
	var data: Dictionary = {
		"base_seconds_per_hour": BASE_SECONDS_PER_HOUR,
		"multiplier": MULTIPLIER,
		"tick_interval": TICK_INTERVAL,
		"delta_seconds": DELTA_SECONDS,
		"frames": frame_hours,
		"frame_count": frame_hours.size(),
		"accumulator_remainder": accumulator,
		"pending_seconds": pending_seconds,
		"total_hours_advanced": total_hours,
		"expected_hours": expected_hours,
		"max_ticks_in_frame": max_frame,
	}
	return {"data": data, "ok": clamp_ok}
