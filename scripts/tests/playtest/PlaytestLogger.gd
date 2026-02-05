extends RefCounted
class_name PlaytestLogger

## JSON-line logger for playtest harness.
## All output goes to stdout for CI capture.

var verbose: bool = false
var deterministic_mode: bool = true
var _sequence: int = 0
var _last_invariant_failure: Dictionary = {}


func log_info(message: String) -> void:
	print(message)


func log_error(message: String) -> void:
	push_error(message)
	print("ERROR: %s" % message)


func log_scenario_start(name: String, seed_value: int) -> void:
	var entry := {
		"ts": _timestamp(),
		"type": "scenario_start",
		"name": name,
		"seed": seed_value,
	}
	_emit_json(entry)


func log_config(config: Dictionary) -> void:
	var entry := {
		"ts": _timestamp(),
		"type": "config",
	}
	for key in config.keys():
		entry[str(key)] = config.get(key)
	_emit_json(entry)


func log_scenario_summary(
	name: String,
	seed_value: int,
	hours_simulated: int,
	days_simulated: int,
	actions_executed: int,
	invariants_checked: int,
	invariants_passed: int,
	invariants_failed: int,
	signature: String,
	commands_run: Array[String]
) -> void:
	var entry := {
		"ts": _timestamp(),
		"type": "summary",
		"scenario": name,
		"seed": seed_value,
		"hours_simulated": hours_simulated,
		"days_simulated": days_simulated,
		"actions_executed": actions_executed,
		"commands_run": commands_run,
		"invariants_checked": invariants_checked,
		"invariants_passed": invariants_passed,
		"invariants_failed": invariants_failed,
		"signature": _hash_signature(signature),
	}
	if verbose:
		entry["signature_full"] = signature
	_emit_json(entry)


func log_action(
	action_type: String,
	hour: int,
	day: int,
	payload: Dictionary,
	result: String
) -> void:
	if not verbose:
		return

	var entry := {
		"ts": _timestamp(),
		"type": "action",
		"action": action_type,
		"hour": hour,
		"day": day,
		"payload": payload,
		"result": result,
	}
	_emit_json(entry)


func log_action_fail(action: Dictionary, message: String) -> void:
	var entry := {
		"ts": _timestamp(),
		"type": "action_fail",
		"action": action,
		"message": message,
	}
	_emit_json(entry)


func log_snapshot(label: String, hour: int, day: int, state: Dictionary) -> void:
	var entry := {
		"ts": _timestamp(),
		"type": "snapshot",
		"label": label,
		"hour": hour,
		"day": day,
		"state": state,
	}
	_emit_json(entry)


func log_invariant(name: String, passed: bool, hour: int, day: int) -> void:
	if not verbose:
		return

	var entry := {
		"ts": _timestamp(),
		"type": "invariant",
		"name": name,
		"passed": passed,
		"hour": hour,
		"day": day,
	}
	_emit_json(entry)


func log_invariant_fail(
	name: String,
	message: String,
	hour: int,
	day: int,
	expected: String,
	actual: String
) -> void:
	var entry := {
		"ts": _timestamp(),
		"type": "invariant_fail",
		"name": name,
		"message": message,
		"hour": hour,
		"day": day,
		"expected": expected,
		"actual": actual,
	}
	_last_invariant_failure = entry.duplicate(true)
	_emit_json(entry)


func _emit_json(entry: Dictionary) -> void:
	print(JSON.stringify(entry))


func _timestamp() -> String:
	if deterministic_mode:
		_sequence += 1
		return "T%d" % _sequence
	var datetime := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		datetime.get("year", 1970),
		datetime.get("month", 1),
		datetime.get("day", 1),
		datetime.get("hour", 0),
		datetime.get("minute", 0),
		datetime.get("second", 0),
	]


func get_last_invariant_failure() -> Dictionary:
	if _last_invariant_failure.is_empty():
		return {}
	return _last_invariant_failure.duplicate(true)


func _hash_signature(signature: String) -> String:
	## Returns a compact hash of the full signature for easy comparison.
	## Full signature is also available in verbose mode.
	if signature.is_empty():
		return ""

	# Use CRC32 for a compact, deterministic hash.
	var crc := signature.hash()
	return "%08x" % crc
