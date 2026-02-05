extends Node
class_name PlaytestRunner

## Headless playtest harness for deterministic scenario execution.
## Run via: godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd

const ScenarioLoaderScript: Script = preload("res://scripts/tests/playtest/ScenarioLoader.gd")
const ActionExecutorScript: Script = preload("res://scripts/tests/playtest/ActionExecutor.gd")
const InvariantsScript: Script = preload("res://scripts/tests/playtest/Invariants.gd")
const PlaytestLoggerScript: Script = preload("res://scripts/tests/playtest/PlaytestLogger.gd")
const StressActionGeneratorScript: Script = preload("res://scripts/tests/playtest/StressActionGenerator.gd")
const SimScript: Script = preload("res://scripts/sim/Sim.gd")

const SCENARIOS_DIR: String = "res://tests/scenarios"
const DEFAULT_MAX_HOURS: int = 2000
const DEFAULT_TICK_RING_SIZE: int = 200
const DEFAULT_ACTION_HISTORY_SIZE: int = 200
const DEFAULT_OUT_DIR: String = "user://playtests"
const EXIT_SUCCESS: int = 0
const EXIT_INVARIANT_FAIL: int = 1
const EXIT_EXECUTION_ERROR: int = 2

var _verbose: bool = false
var _scenario_filter: String = ""
var _seed_override: int = -1
var _max_hours: int = DEFAULT_MAX_HOURS
var _scenarios_dir_override: String = ""
var _deterministic_logs: bool = true
var _repeat_for_determinism: bool = false
var _out_dir_override: String = ""
var _invariant_sampling: int = 1

var _loader: RefCounted  # ScenarioLoader
var _executor: RefCounted  # ActionExecutor
var _invariants: RefCounted  # Invariants
var _logger: RefCounted  # PlaytestLogger

var _total_scenarios: int = 0
var _passed_scenarios: int = 0
var _failed_scenarios: int = 0
var _resolved_scenarios_dir: String = SCENARIOS_DIR

var _tick_ring: Array[Dictionary] = []
var _tick_ring_max: int = DEFAULT_TICK_RING_SIZE
var _action_history: Array[Dictionary] = []
var _action_history_max: int = DEFAULT_ACTION_HISTORY_SIZE
var _current_sim: Sim
var _current_out_dir: String = ""


func _ready() -> void:
	_parse_args()
	call_deferred("_run_all")


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		var arg_str := str(arg)
		if arg_str == "--verbose" or arg_str == "-v":
			_verbose = true
		elif arg_str.begins_with("--scenario="):
			_scenario_filter = arg_str.substr("--scenario=".length())
		elif arg_str.begins_with("--seed="):
			_seed_override = int(arg_str.substr("--seed=".length()))
		elif arg_str.begins_with("--max-hours="):
			_max_hours = int(arg_str.substr("--max-hours=".length()))
		elif arg_str.begins_with("--scenarios-dir="):
			_scenarios_dir_override = arg_str.substr("--scenarios-dir=".length())
		elif arg_str == "--nondeterministic-logs":
			_deterministic_logs = false
		elif arg_str == "--repeat-for-determinism":
			_repeat_for_determinism = true
		elif arg_str.begins_with("--out-dir="):
			_out_dir_override = arg_str.substr("--out-dir=".length())
		elif arg_str.begins_with("--invariant-sampling="):
			_invariant_sampling = max(1, int(arg_str.substr("--invariant-sampling=".length())))


func _run_all() -> void:
	_loader = ScenarioLoaderScript.new()
	_executor = ActionExecutorScript.new()
	_invariants = InvariantsScript.new()
	_logger = PlaytestLoggerScript.new()
	_logger.verbose = _verbose
	_logger.deterministic_mode = _deterministic_logs
	_invariants.set_sampling_interval(_invariant_sampling)

	var scenarios: Array[Dictionary] = _discover_scenarios()
	_logger.log_config({"scenarios_dir": _resolved_scenarios_dir})
	if scenarios.is_empty():
		_logger.log_error("No scenarios found in %s" % _resolved_scenarios_dir)
		get_tree().quit(EXIT_EXECUTION_ERROR)
		return

	_total_scenarios = scenarios.size()
	_logger.log_info("Discovered %d scenario(s)" % _total_scenarios)

	for scenario in scenarios:
		var result := _run_scenario(scenario)
		if result:
			_passed_scenarios += 1
		else:
			_failed_scenarios += 1

	_print_final_summary()

	var exit_code: int = EXIT_SUCCESS if _failed_scenarios == 0 else EXIT_INVARIANT_FAIL
	get_tree().quit(exit_code)


func _discover_scenarios() -> Array[Dictionary]:
	var dir_path: String = SCENARIOS_DIR
	if _scenarios_dir_override != "":
		dir_path = _scenarios_dir_override
	var scenarios: Array[Dictionary] = _load_scenarios_from_dir(dir_path)
	_resolved_scenarios_dir = dir_path
	return scenarios


func _load_scenarios_from_dir(dir_path: String) -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return scenarios

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var scenario_name := file_name.get_basename()
			if _scenario_filter == "" or scenario_name == _scenario_filter:
				var path := "%s/%s" % [dir_path, file_name]
				var loaded: Dictionary = _loader.load_scenario(path)
				if loaded.has("error"):
					_logger.log_error("Failed to load %s: %s" % [path, loaded["error"]])
				else:
					loaded["_path"] = path
					scenarios.append(loaded)
		file_name = dir.get_next()
	dir.list_dir_end()

	return scenarios


func _run_scenario(scenario: Dictionary) -> bool:
	var metadata: Dictionary = scenario.get("metadata", {})
	var scenario_name: String = str(metadata.get("name", "unnamed"))
	var seed_value: int = _seed_override if _seed_override >= 0 else int(metadata.get("seed", 12345))
	var actions: Array = []
	var actions_value: Variant = scenario.get("actions", [])
	if actions_value is Array:
		actions = actions_value as Array

	_logger.log_scenario_start(scenario_name, seed_value)

	var result_a := _execute_scenario_once(scenario_name, seed_value, actions, metadata)
	var result_b: Dictionary = {}
	var deterministic: bool = true

	if _repeat_for_determinism:
		result_b = _execute_scenario_once(scenario_name, seed_value, actions, metadata)
		var sig_seq_a: Array = result_a.get("signatures", [])
		var sig_seq_b: Array = result_b.get("signatures", [])
		deterministic = _compare_signature_sequences(scenario_name, seed_value, sig_seq_a, sig_seq_b)

	var passed: bool = result_a.get("passed", false) and (not _repeat_for_determinism or result_b.get("passed", false)) and deterministic

	var commands_run: Array[String] = []
	var commands_variant: Variant = result_a.get("commands_run", [])
	if commands_variant is Array:
		commands_run = commands_variant as Array[String]

	_logger.log_scenario_summary(
		scenario_name,
		seed_value,
		result_a.get("hours_simulated", 0),
		result_a.get("days_simulated", 0),
		result_a.get("actions_executed", 0),
		result_a.get("invariants_checked", 0),
		result_a.get("invariants_passed", 0),
		result_a.get("invariants_failed", 0),
		result_a.get("signature", ""),
		commands_run
	)

	_write_summary(scenario_name, seed_value, result_a, result_b, deterministic)

	return passed


func _execute_scenario_once(_scenario_name: String, seed_value: int, actions: Array, metadata: Dictionary) -> Dictionary:
	var sim: Sim = SimScript.new() as Sim
	_current_sim = sim
	sim.sim_seed = seed_value
	sim._setup_default_state()
	sim.day = 0
	sim.hour_index = 0
	sim.hour_of_day = 0
	_prepare_run_state(_scenario_name, seed_value)
	if not sim.tick.is_connected(_on_sim_tick):
		sim.tick.connect(_on_sim_tick)

	_executor.reset(sim, _logger, _invariants, _max_hours)
	_invariants.reset()
	_invariants.set_sampling_interval(_invariant_sampling)

	var hours_simulated: int = 0
	var actions_executed: int = 0
	var commands_run: Array[String] = []
	var signatures: Array[String] = []
	var execution_failed: bool = false

	var mode: String = str(metadata.get("mode", ""))
	if mode == "generated":
		var result := _run_generated_scenario(sim, _scenario_name, seed_value, metadata, commands_run, signatures)
		hours_simulated = int(result.get("hours_simulated", sim.hour_index))
		actions_executed = int(result.get("actions_executed", 0))
		execution_failed = bool(result.get("failed", false))
	else:
		for action in actions:
			if action is Dictionary:
				var action_dict: Dictionary = action as Dictionary
				var action_type := str(action_dict.get("type", ""))
				commands_run.append(action_type)
				_record_action_history(action_dict, sim)
				var exec_result: Dictionary = _executor.execute(action_dict)
				actions_executed += 1
				hours_simulated = sim.hour_index
				signatures.append(sim._state_signature())

				if not exec_result.get("ok", false):
					_logger.log_action_fail(action_dict, exec_result.get("message", "Unknown error"))
					_handle_failure(_scenario_name, seed_value, exec_result.get("message", "Execution error"))
					execution_failed = true
					break

				if _invariants.total_failed() > 0:
					_handle_failure(_scenario_name, seed_value, "Invariant failure")
					execution_failed = true
					break

				if hours_simulated > _max_hours:
					_logger.log_error("Max hours exceeded: %d" % _max_hours)
					_handle_failure(_scenario_name, seed_value, "Max hours exceeded")
					execution_failed = true
					break

	var signature := sim._state_signature()

	if sim.tick.is_connected(_on_sim_tick):
		sim.tick.disconnect(_on_sim_tick)

	return {
		"passed": _invariants.all_passed() and not execution_failed,
		"signature": signature,
		"signatures": signatures,
		"hours_simulated": hours_simulated,
		"days_simulated": sim.day,
		"final_hour": sim.hour_index,
		"final_day": sim.day,
		"actions_executed": actions_executed,
		"invariants_checked": _invariants.total_checked(),
		"invariants_passed": _invariants.total_passed(),
		"invariants_failed": _invariants.total_failed(),
		"commands_run": commands_run,
	}


func _prepare_run_state(scenario_name: String, seed_value: int) -> void:
	_tick_ring.clear()
	_action_history.clear()
	_current_out_dir = _resolve_out_dir(scenario_name, seed_value)
	_ensure_out_dir(_current_out_dir)


func _resolve_out_dir(scenario_name: String, seed_value: int) -> String:
	var base_dir: String = _out_dir_override if _out_dir_override != "" else DEFAULT_OUT_DIR
	var safe_name := scenario_name.strip_edges().to_lower().replace(" ", "_")
	var run_id := "%s_%d" % [safe_name, seed_value]
	return "%s/%s" % [base_dir, run_id]


func _ensure_out_dir(dir_path: String) -> void:
	var absolute := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(absolute)


func _on_sim_tick(_day: int) -> void:
	if _current_sim == null:
		return
	_record_tick(_snapshot_tick(_current_sim))


func _record_tick(snapshot: Dictionary) -> void:
	_tick_ring.append(snapshot)
	if _tick_ring.size() > _tick_ring_max:
		_tick_ring.pop_front()


func _record_action_history(action: Dictionary, sim: Sim) -> void:
	var entry := action.duplicate(true)
	entry["hour"] = sim.hour_index
	entry["day"] = sim.day
	_action_history.append(entry)
	if _action_history.size() > _action_history_max:
		_action_history.pop_front()


func _snapshot_tick(sim: Sim) -> Dictionary:
	var expedition: Dictionary = sim.get_active_expedition()
	var lever_state := {
		"ration_hardening": sim.ration_hardening_hours_left,
		"labor_overdrive": sim.labor_overdrive_hours_left,
		"expedition_compression": sim.expedition_compression_hours_left,
		"information_throttling": sim.info_throttle_hours_left,
		"labor_intensity": sim.labor_overdrive_intensity,
		"expedition_intensity": sim.expedition_compression_intensity,
		"info_level": sim.info_throttle_level,
	}
	return {
		"hour": sim.hour_index,
		"day": sim.day,
		"resources": {
			"food": sim.res.food,
			"water": sim.res.water,
			"materials": sim.res.materials,
			"morale": sim.res.morale,
			"threat": sim.res.threat,
			"silver": sim.res.silver,
			"population": sim.res.population,
			"power_supply": sim.res.power_supply,
			"power_used": sim.res.power_used,
			"strain": sim.res.strain,
		},
		"active_expedition": expedition,
		"levers": lever_state,
	}


func _snapshot_state(sim: Sim) -> Dictionary:
	return {
		"signature": sim._state_signature(),
		"resources": {
			"food": sim.res.food,
			"water": sim.res.water,
			"materials": sim.res.materials,
			"morale": sim.res.morale,
			"threat": sim.res.threat,
			"silver": sim.res.silver,
			"population": sim.res.population,
		},
		"expedition": sim.get_active_expedition(),
		"people_count": sim._alive_people_count(),
	}


func _run_generated_scenario(
	sim: Sim,
	scenario_name: String,
	seed_value: int,
	metadata: Dictionary,
	commands_run: Array[String],
	signatures: Array[String]
) -> Dictionary:
	var generator_config_value: Variant = metadata.get("generator_config", {})
	var generator_config: Dictionary = generator_config_value as Dictionary if generator_config_value is Dictionary else {}
	var generator: RefCounted = StressActionGeneratorScript.new() as RefCounted
	generator.call("setup", seed_value, generator_config)

	var target_hours: int = int(metadata.get("target_hours", _max_hours))
	if target_hours <= 0:
		target_hours = _max_hours
	if _max_hours > 0:
		target_hours = min(target_hours, _max_hours)

	var actions_executed: int = 0
	var failed: bool = false
	while sim.hour_index < target_hours:
		var action: Dictionary = generator.call("next_action", sim)
		var action_type := str(action.get("type", ""))
		commands_run.append(action_type)
		_record_action_history(action, sim)
		if action.get("skipped", false):
			_logger.log_action("skip", sim.hour_index, sim.day, action, "skipped")

		var exec_result: Dictionary = _executor.execute(action)
		actions_executed += 1
		signatures.append(sim._state_signature())
		if not exec_result.get("ok", false):
			_logger.log_action_fail(action, exec_result.get("message", "Unknown error"))
			_handle_failure(scenario_name, seed_value, exec_result.get("message", "Execution error"))
			failed = true
			break
		if _invariants.total_failed() > 0:
			_handle_failure(scenario_name, seed_value, "Invariant failure")
			failed = true
			break
		if sim.hour_index > _max_hours:
			_logger.log_error("Max hours exceeded: %d" % _max_hours)
			_handle_failure(scenario_name, seed_value, "Max hours exceeded")
			failed = true
			break

	return {
		"actions_executed": actions_executed,
		"hours_simulated": sim.hour_index,
		"failed": failed,
	}


func _compare_signature_sequences(
	scenario_name: String,
	seed_value: int,
	seq_a: Array,
	seq_b: Array
) -> bool:
	var size_a: int = seq_a.size()
	var size_b: int = seq_b.size()
	var limit: int = min(size_a, size_b)
	for i in range(limit):
		var sig_a := str(seq_a[i])
		var sig_b := str(seq_b[i])
		if sig_a != sig_b:
			_logger.log_invariant_fail(
				"DETERMINISM",
				"Signature mismatch between runs",
				int(_current_sim.hour_index),
				int(_current_sim.day),
				sig_a,
				sig_b
			)
			_write_determinism_diff(scenario_name, seed_value, i, sig_a, sig_b)
			return false
	if size_a != size_b:
		_logger.log_invariant_fail(
			"DETERMINISM",
			"Signature sequence length mismatch",
			int(_current_sim.hour_index),
			int(_current_sim.day),
			str(size_a),
			str(size_b)
		)
		_write_determinism_diff(scenario_name, seed_value, limit, "len=%d" % size_a, "len=%d" % size_b)
		return false
	return true


func _handle_failure(scenario_name: String, seed_value: int, reason: String) -> void:
	var failure: Dictionary = _logger.get_last_invariant_failure()
	var invariant_id: String = str(failure.get("name", ""))
	var message: String = str(failure.get("message", reason))
	var expected: String = str(failure.get("expected", ""))
	var actual: String = str(failure.get("actual", ""))
	var signature: String = _current_sim._state_signature()
	var rng_history: Array[Dictionary] = _current_sim.get_rng_usage_history()
	var tail_start: int = max(rng_history.size() - 10, 0)
	var rng_tail: Array = rng_history.slice(tail_start, rng_history.size())
	var failure_record := {
		"version": 1,
		"scenario": scenario_name,
		"seed": seed_value,
		"failure_hour": _current_sim.hour_index,
		"failure_day": _current_sim.day,
		"invariant_id": invariant_id,
		"invariant_message": message,
		"expected": expected,
		"actual": actual,
		"signature": signature,
		"signature_hash": _logger._hash_signature(signature),
		"last_actions": _action_history.duplicate(true),
		"state_snapshots": {
			"failure": _snapshot_state(_current_sim),
		},
		"rng_history_tail": rng_tail,
	}

	_write_failure_artifacts(failure_record)


func _write_failure_artifacts(failure_record: Dictionary) -> void:
	_write_json_file("%s/failure.json" % _current_out_dir, failure_record)
	_write_ticks_jsonl("%s/ticks.jsonl" % _current_out_dir)


func _write_ticks_jsonl(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	for entry in _tick_ring:
		file.store_line(JSON.stringify(entry))
	file.close()


func _write_summary(
	scenario_name: String,
	seed_value: int,
	result_a: Dictionary,
	result_b: Dictionary,
	deterministic: bool
) -> void:
	var summary := {
		"scenario": scenario_name,
		"seed": seed_value,
		"passed": bool(result_a.get("passed", false)) and deterministic,
		"hours_simulated": int(result_a.get("hours_simulated", 0)),
		"days_simulated": int(result_a.get("days_simulated", 0)),
		"actions_executed": int(result_a.get("actions_executed", 0)),
		"invariants_checked": int(result_a.get("invariants_checked", 0)),
		"invariants_passed": int(result_a.get("invariants_passed", 0)),
		"invariants_failed": int(result_a.get("invariants_failed", 0)),
		"signature": str(result_a.get("signature", "")),
		"repeat_for_determinism": _repeat_for_determinism,
		"deterministic": deterministic,
	}
	if _repeat_for_determinism and not result_b.is_empty():
		summary["signature_repeat"] = str(result_b.get("signature", ""))
	_write_json_file("%s/summary.json" % _current_out_dir, summary)


func _write_determinism_diff(
	scenario_name: String,
	seed_value: int,
	index: int,
	sig_a: String,
	sig_b: String
) -> void:
	var diff := {
		"scenario": scenario_name,
		"seed": seed_value,
		"first_diff_index": index,
		"signature_a": sig_a,
		"signature_b": sig_b,
	}
	_write_json_file("%s/determinism_diff.json" % _current_out_dir, diff)


func _write_json_file(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_line(JSON.stringify(payload, "\t"))
	file.close()


func _print_final_summary() -> void:
	_logger.log_info("=" .repeat(60))
	_logger.log_info("PLAYTEST SUMMARY")
	_logger.log_info("  Total:  %d" % _total_scenarios)
	_logger.log_info("  Passed: %d" % _passed_scenarios)
	_logger.log_info("  Failed: %d" % _failed_scenarios)
	_logger.log_info("=" .repeat(60))

	if _failed_scenarios == 0:
		_logger.log_info("ALL SCENARIOS PASSED")
	else:
		_logger.log_error("SOME SCENARIOS FAILED")
