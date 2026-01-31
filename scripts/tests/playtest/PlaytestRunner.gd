extends Node
class_name PlaytestRunner

## Headless playtest harness for deterministic scenario execution.
## Run via: godot --headless --path . -s res://scripts/tests/playtest/PlaytestRunner.gd

const ScenarioLoaderScript: Script = preload("res://scripts/tests/playtest/ScenarioLoader.gd")
const ActionExecutorScript: Script = preload("res://scripts/tests/playtest/ActionExecutor.gd")
const InvariantsScript: Script = preload("res://scripts/tests/playtest/Invariants.gd")
const PlaytestLoggerScript: Script = preload("res://scripts/tests/playtest/PlaytestLogger.gd")
const SimScript: Script = preload("res://scripts/sim/Sim.gd")

const SCENARIOS_DIR: String = "res://scripts/tests/scenarios"
const FALLBACK_SCENARIOS_DIR: String = "res://tests/scenarios"
const DEFAULT_MAX_HOURS: int = 1000
const EXIT_SUCCESS: int = 0
const EXIT_INVARIANT_FAIL: int = 1
const EXIT_EXECUTION_ERROR: int = 2

var _verbose: bool = false
var _scenario_filter: String = ""
var _seed_override: int = -1
var _max_hours: int = DEFAULT_MAX_HOURS

var _loader: RefCounted  # ScenarioLoader
var _executor: RefCounted  # ActionExecutor
var _invariants: RefCounted  # Invariants
var _logger: RefCounted  # PlaytestLogger

var _total_scenarios: int = 0
var _passed_scenarios: int = 0
var _failed_scenarios: int = 0
var _resolved_scenarios_dir: String = SCENARIOS_DIR


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


func _run_all() -> void:
	_loader = ScenarioLoaderScript.new()
	_executor = ActionExecutorScript.new()
	_invariants = InvariantsScript.new()
	_logger = PlaytestLoggerScript.new()
	_logger.verbose = _verbose

	var scenarios: Array[Dictionary] = _discover_scenarios()
	if _verbose:
		_logger.log_info("Scenario directory: %s" % _resolved_scenarios_dir)
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
	var scenarios: Array[Dictionary] = _load_scenarios_from_dir(SCENARIOS_DIR)
	_resolved_scenarios_dir = SCENARIOS_DIR

	if scenarios.is_empty():
		var fallback_scenarios: Array[Dictionary] = _load_scenarios_from_dir(FALLBACK_SCENARIOS_DIR)
		if not fallback_scenarios.is_empty():
			scenarios = fallback_scenarios
			_resolved_scenarios_dir = FALLBACK_SCENARIOS_DIR

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
	var actions: Array = scenario.get("actions", [])

	_logger.log_scenario_start(scenario_name, seed_value)

	# Run twice for determinism verification.
	var result_a := _execute_scenario_once(scenario_name, seed_value, actions)
	var result_b := _execute_scenario_once(scenario_name, seed_value, actions)

	# Compare signatures for determinism.
	var sig_a: String = result_a.get("signature", "")
	var sig_b: String = result_b.get("signature", "")
	var deterministic: bool = sig_a == sig_b

	if not deterministic:
		_logger.log_invariant_fail(
			"DETERMINISM",
			"Signature mismatch between runs",
			result_a.get("final_hour", 0),
			result_a.get("final_day", 0),
			sig_a,
			sig_b
		)

	var passed: bool = result_a.get("passed", false) and result_b.get("passed", false) and deterministic

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
		sig_a,
		commands_run
	)

	return passed


func _execute_scenario_once(_scenario_name: String, seed_value: int, actions: Array) -> Dictionary:
	var sim: Sim = SimScript.new() as Sim
	sim.sim_seed = seed_value
	sim._setup_default_state()
	sim.day = 0
	sim.hour_index = 0
	sim.hour_of_day = 0

	_executor.reset(sim, _logger, _invariants, _max_hours)
	_invariants.reset()

	var hours_simulated: int = 0
	var actions_executed: int = 0
	var commands_run: Array[String] = []

	for action in actions:
		if action is Dictionary:
			var action_dict: Dictionary = action as Dictionary
			var action_type := str(action_dict.get("type", ""))
			commands_run.append(action_type)
			var exec_result: Dictionary = _executor.execute(action_dict)
			actions_executed += 1
			hours_simulated = sim.hour_index

			if not exec_result.get("ok", false):
				_logger.log_action_fail(action, exec_result.get("message", "Unknown error"))
				break

			# Check continuous invariants after each action.
			_invariants.check_continuous(sim, _logger)

			if hours_simulated > _max_hours:
				_logger.log_error("Max hours exceeded: %d" % _max_hours)
				break

	var signature := sim._state_signature()

	return {
		"passed": _invariants.all_passed(),
		"signature": signature,
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
