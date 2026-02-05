extends RefCounted
class_name ActionExecutor

## Executes scenario actions against the simulation.

const LeverDefsRef = preload("res://scripts/sim/LeverDefs.gd")
const SimScript: Script = preload("res://scripts/sim/Sim.gd")
const STRICT_DELTA_COMMANDS: Array[String] = ["cmd_trade", "cmd_expedition"]

var _sim: Sim
var _logger: RefCounted  # PlaytestLogger
var _invariants: RefCounted  # Invariants
var _max_hours: int = 1000
var _strict_command_deltas_enabled: bool = false
var _strict_delta_sampling: int = 25
var _strict_command_delta_counter: int = 0


func reset(sim: Sim, logger: RefCounted, invariants: RefCounted, max_hours: int) -> void:
	_sim = sim
	_logger = logger
	_invariants = invariants
	_max_hours = max_hours

func configure_strict_command_deltas(enabled: bool, sampling: int) -> void:
	_strict_command_deltas_enabled = enabled
	_strict_delta_sampling = max(1, sampling)
	_strict_command_delta_counter = 0


func execute(action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", ""))

	match action_type:
		"advance_hours":
			return _exec_advance_hours(action)
		"advance_days":
			return _exec_advance_days(action)
		"trade":
			return _exec_trade(action)
		"expedition":
			return _exec_expedition(action)
		"lever":
			return _exec_lever(action)
		"set_rations":
			return _exec_set_rations(action)
		"cmd_set_rations":
			return _exec_cmd_set_rations(action)
		"cmd_trade":
			return _exec_cmd_trade(action)
		"cmd_expedition":
			return _exec_cmd_expedition(action)
		"cmd_set_module_enabled":
			return _exec_cmd_set_module_enabled(action)
		"cmd_set_module_priority":
			return _exec_cmd_set_module_priority(action)
		"cmd_outsiders_decision":
			return _exec_cmd_outsiders_decision(action)
		"wait_expedition_resolve":
			return _exec_wait_expedition_resolve(action)
		"assert":
			return _exec_assert(action)
		"snapshot":
			return _exec_snapshot(action)
		"comment":
			return {"ok": true}
		_:
			return {"ok": false, "message": "Unknown action type: %s" % action_type}


func _exec_advance_hours(action: Dictionary) -> Dictionary:
	var hours := int(action.get("hours", 0))
	if hours <= 0:
		return {"ok": false, "message": "Invalid hours: %d" % hours}

	for _i in range(hours):
		_sim._advance_hour()
		_invariants.check_continuous(_sim, _logger)

		if _sim.hour_index > _max_hours:
			return {"ok": false, "message": "Max hours exceeded"}

	_logger.log_action("advance_hours", _sim.hour_index, _sim.day, {"hours": hours}, "ok")
	return {"ok": true}


func _exec_advance_days(action: Dictionary) -> Dictionary:
	var days := int(action.get("days", 0))
	if days <= 0:
		return {"ok": false, "message": "Invalid days: %d" % days}

	var hours := days * _sim.HOURS_PER_DAY
	for _i in range(hours):
		_sim._advance_hour()
		_invariants.check_continuous(_sim, _logger)

		if _sim.hour_index > _max_hours:
			return {"ok": false, "message": "Max hours exceeded"}

	_logger.log_action("advance_days", _sim.hour_index, _sim.day, {"days": days}, "ok")
	return {"ok": true}


func _exec_trade(action: Dictionary) -> Dictionary:
	var direction := str(action.get("direction", ""))
	var resource := str(action.get("resource", ""))
	var amount := int(action.get("amount", 0))

	# Capture pre-trade state for invariant checking.
	var pre_hour_index: int = _sim.hour_index
	var pre_day: int = _sim.day
	var pre_hour_of_day: int = _sim.hour_of_day
	var pre_snapshot: String = _sim.res.snapshot()
	var pre_silver: int = _sim.res.silver
	var pre_resource: int = 0
	if _sim.TRADEABLE_RESOURCES.has(resource):
		pre_resource = _sim.res.get_amount(resource)
	var pre_attention: float = _sim.res.attention_multiplier

	var payload := {
		"direction": direction,
		"resource": resource,
		"amount": amount,
	}

	var obs: Array[String] = []
	_sim._cmd_trade(payload, _sim.res, obs, _sim.day)
	var rejected: bool = _trade_rejected(obs)

	if not rejected:
		# Check trade-specific invariants.
		_invariants.check_trade(
			_sim,
			_logger,
			direction,
			resource,
			amount,
			pre_silver,
			pre_resource,
			pre_attention
		)
		_logger.log_action("trade", _sim.hour_index, _sim.day, payload, "ok")
		return {"ok": true}

	# Rejection case should not advance time or mutate state.
	_invariants.check_trade_rejection(
		_sim,
		_logger,
		pre_hour_index,
		pre_day,
		pre_hour_of_day,
		pre_snapshot,
		pre_attention
	)
	_logger.log_action("trade", _sim.hour_index, _sim.day, payload, "rejected")
	# Trade rejection may be intentional (testing invalid trades).
	return {"ok": true, "trade_rejected": true}


func _exec_expedition(action: Dictionary) -> Dictionary:
	var destination_id := str(action.get("destination_id", ""))
	var crew := int(action.get("crew", 1))

	# Capture pre-launch state.
	var pre_threat: int = _sim.res.threat
	var had_active: bool = _sim.has_active_expedition()

	var result := _sim.launch_expedition(destination_id, crew)

	var payload := {
		"destination_id": destination_id,
		"crew": crew,
		"result": result.get("message", ""),
	}

	if result.get("ok", false):
		# Check expedition launch invariants.
		_invariants.check_expedition_launch(
			_sim,
			_logger,
			destination_id,
			crew,
			pre_threat,
			had_active
		)
		_logger.log_action("expedition", _sim.hour_index, _sim.day, payload, "ok")
		return {"ok": true}
	else:
		_logger.log_action("expedition", _sim.hour_index, _sim.day, payload, "rejected")
		# Rejection may be intentional.
		return {"ok": true, "expedition_rejected": true}


func _exec_lever(action: Dictionary) -> Dictionary:
	var lever_id := str(action.get("lever_id", ""))
	var payload: Dictionary = action.get("payload", {})

	if payload is Dictionary:
		payload = payload.duplicate(true)
	else:
		payload = {}

	var applied := _sim.apply_lever(lever_id, payload)

	var log_payload := {
		"lever_id": lever_id,
		"payload": payload,
		"applied": applied,
	}

	_logger.log_action("lever", _sim.hour_index, _sim.day, log_payload, "ok" if applied else "rejected")
	return {"ok": true}


func _exec_set_rations(action: Dictionary) -> Dictionary:
	if action.has("food_ration"):
		var food_ration := float(action.get("food_ration", 1.0))
		_sim.food_ration = clamp(food_ration, 0.0, 1.0)

	if action.has("water_ration"):
		var water_ration := float(action.get("water_ration", 1.0))
		_sim.water_ration = clamp(water_ration, 0.0, 1.0)

	var payload := {
		"food_ration": _sim.food_ration,
		"water_ration": _sim.water_ration,
	}

	_logger.log_action("set_rations", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_cmd_set_rations(action: Dictionary) -> Dictionary:
	var payload: Dictionary = {}
	if action.has("food_ration"):
		payload["food"] = clamp(float(action.get("food_ration", 1.0)), 0.0, 1.0)
	if action.has("water_ration"):
		payload["water"] = clamp(float(action.get("water_ration", 1.0)), 0.0, 1.0)
	if payload.is_empty():
		return {"ok": false, "message": "cmd_set_rations missing payload"}

	var pre_food: float = _sim.food_ration
	var pre_water: float = _sim.water_ration
	_sim.enqueue_command(Sim.SimCommand.new(Sim.CMD_SET_RATIONS, payload))
	var advance_result := _advance_to_next_production()
	if not advance_result.get("ok", false):
		return advance_result

	var stalled := _command_stalled(Sim.CMD_SET_RATIONS)
	_invariants.check_command_queue(
		_sim,
		_logger,
		Sim.CMD_SET_RATIONS,
		stalled,
		{"food_ration": pre_food, "water_ration": pre_water},
		{"food_ration": _sim.food_ration, "water_ration": _sim.water_ration}
	)
	_logger.log_action("cmd_set_rations", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_cmd_trade(action: Dictionary) -> Dictionary:
	var direction := str(action.get("direction", "")).to_lower()
	var resource := str(action.get("resource", "")).to_lower()
	var amount := int(action.get("amount", 0))
	var payload := {
		"direction": direction,
		"resource": resource,
		"amount": amount,
	}

	var strict_context: Dictionary = _capture_strict_context("cmd_trade")
	_sim.enqueue_command(Sim.SimCommand.new(Sim.CMD_TRADE, payload))
	var advance_result := _advance_to_next_production()
	if not advance_result.get("ok", false):
		return advance_result

	var stalled := _command_stalled(Sim.CMD_TRADE)
	var trade_rejected := _trade_rejected(_sim._last_obs_tokens as Array[String])
	var strict_result := _finalize_strict_delta(
		"cmd_trade",
		payload,
		strict_context,
		{
			"advance_ok": true,
			"stalled": stalled,
			"rejected": trade_rejected,
		}
	)
	if not strict_result.get("ok", true):
		return strict_result

	_invariants.check_command_queue(
		_sim,
		_logger,
		Sim.CMD_TRADE,
		stalled,
		{},
		{}
	)
	_logger.log_action("cmd_trade", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_cmd_expedition(action: Dictionary) -> Dictionary:
	var destination_id := str(action.get("destination_id", ""))
	var crew := int(action.get("crew", 1))
	var payload := {
		"destination_id": destination_id,
		"crew": crew,
	}
	var pre_has_active: bool = _sim.has_active_expedition()
	var pre_active_id: int = 0
	if pre_has_active:
		var pre_active: Dictionary = _sim.get_active_expedition()
		pre_active_id = int(pre_active.get("id", 0))
	var strict_context: Dictionary = _capture_strict_context("cmd_expedition")

	_sim.enqueue_command(Sim.SimCommand.new(Sim.CMD_EXPEDITION, payload))
	var advance_result := _advance_to_next_production()
	if not advance_result.get("ok", false):
		return advance_result

	var post_has_active: bool = _sim.has_active_expedition()
	var post_active_id: int = 0
	if post_has_active:
		var post_active: Dictionary = _sim.get_active_expedition()
		post_active_id = int(post_active.get("id", 0))

	var stalled := _command_stalled(Sim.CMD_EXPEDITION)
	var strict_result := _finalize_strict_delta(
		"cmd_expedition",
		payload,
		strict_context,
		{
			"advance_ok": true,
			"stalled": stalled,
			"pre_has_active": pre_has_active,
			"post_has_active": post_has_active,
		}
	)
	if not strict_result.get("ok", true):
		return strict_result
	_invariants.check_command_queue(
		_sim,
		_logger,
		Sim.CMD_EXPEDITION,
		stalled,
		{"has_active": pre_has_active, "active_id": pre_active_id},
		{"has_active": post_has_active, "active_id": post_active_id}
	)
	_logger.log_action("cmd_expedition", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_cmd_set_module_enabled(action: Dictionary) -> Dictionary:
	var payload := {
		"f": int(action.get("f", -1)),
		"x": int(action.get("x", -1)),
		"y": int(action.get("y", -1)),
		"enabled": bool(action.get("enabled", true)),
	}
	var pre_enabled: bool = _sim.tower.is_module_enabled(int(payload["f"]), int(payload["x"]), int(payload["y"]))
	_sim.enqueue_command(Sim.SimCommand.new(Sim.CMD_SET_MODULE_ENABLED, payload))
	var advance_result := _advance_to_next_production()
	if not advance_result.get("ok", false):
		return advance_result

	var post_enabled: bool = _sim.tower.is_module_enabled(int(payload["f"]), int(payload["x"]), int(payload["y"]))
	var stalled := _command_stalled(Sim.CMD_SET_MODULE_ENABLED)
	_invariants.check_command_queue(
		_sim,
		_logger,
		Sim.CMD_SET_MODULE_ENABLED,
		stalled,
		{"enabled": pre_enabled},
		{"enabled": post_enabled}
	)
	_logger.log_action("cmd_set_module_enabled", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_cmd_set_module_priority(action: Dictionary) -> Dictionary:
	var payload := {
		"f": int(action.get("f", -1)),
		"x": int(action.get("x", -1)),
		"y": int(action.get("y", -1)),
		"priority": int(action.get("priority", 0)),
	}
	var pre_priority: Variant = _sim.tower.get_module_priority_override(int(payload["f"]), int(payload["x"]), int(payload["y"]))
	_sim.enqueue_command(Sim.SimCommand.new(Sim.CMD_SET_MODULE_PRIORITY, payload))
	var advance_result := _advance_to_next_production()
	if not advance_result.get("ok", false):
		return advance_result

	var post_priority: Variant = _sim.tower.get_module_priority_override(int(payload["f"]), int(payload["x"]), int(payload["y"]))
	var stalled := _command_stalled(Sim.CMD_SET_MODULE_PRIORITY)
	_invariants.check_command_queue(
		_sim,
		_logger,
		Sim.CMD_SET_MODULE_PRIORITY,
		stalled,
		{"priority": pre_priority},
		{"priority": post_priority}
	)
	_logger.log_action("cmd_set_module_priority", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_cmd_outsiders_decision(action: Dictionary) -> Dictionary:
	var payload := {
		"event_id": int(action.get("event_id", -1)),
		"accept": bool(action.get("accept", false)),
	}
	var pre_population: int = _sim.res.population
	_sim.enqueue_command(Sim.SimCommand.new(Sim.CMD_OUTSIDERS_DECISION, payload))
	var advance_result := _advance_to_next_production()
	if not advance_result.get("ok", false):
		return advance_result

	var post_population: int = _sim.res.population
	var stalled := _command_stalled(Sim.CMD_OUTSIDERS_DECISION)
	_invariants.check_command_queue(
		_sim,
		_logger,
		Sim.CMD_OUTSIDERS_DECISION,
		stalled,
		{"population": pre_population},
		{"population": post_population}
	)
	_logger.log_action("cmd_outsiders_decision", _sim.hour_index, _sim.day, payload, "ok")
	return {"ok": true}


func _exec_wait_expedition_resolve(action: Dictionary) -> Dictionary:
	var timeout_hours := int(action.get("timeout_hours", 100))
	var hours_waited: int = 0

	while _sim.has_active_expedition() and hours_waited < timeout_hours:
		_sim._advance_hour()
		_invariants.check_continuous(_sim, _logger)

		# Check expedition progress invariants.
		_invariants.check_expedition_progress(_sim, _logger)

		hours_waited += 1

		if _sim.hour_index > _max_hours:
			return {"ok": false, "message": "Max hours exceeded during expedition wait"}

	var resolved := not _sim.has_active_expedition()
	var payload := {
		"hours_waited": hours_waited,
		"resolved": resolved,
		"timed_out": hours_waited >= timeout_hours and not resolved,
	}

	if resolved:
		_invariants.check_expedition_resolve(_sim, _logger)

	_logger.log_action("wait_expedition_resolve", _sim.hour_index, _sim.day, payload, "ok" if resolved else "timeout")
	return {"ok": true, "resolved": resolved}


func _exec_assert(action: Dictionary) -> Dictionary:
	var condition := str(action.get("condition", ""))
	var message := str(action.get("message", "Assertion failed"))

	var result := _evaluate_condition(condition)

	if not result:
		_logger.log_invariant_fail(
			"SCENARIO_ASSERT",
			message,
			_sim.hour_index,
			_sim.day,
			"true",
			"false"
		)
		_invariants.record_failure("SCENARIO_ASSERT", message)
		return {"ok": false, "message": message}

	_invariants.record_pass("SCENARIO_ASSERT")
	return {"ok": true}


func _exec_snapshot(action: Dictionary) -> Dictionary:
	var label := str(action.get("label", "unnamed"))

	var state := {
		"food": _sim.res.food,
		"water": _sim.res.water,
		"materials": _sim.res.materials,
		"morale": _sim.res.morale,
		"threat": _sim.res.threat,
		"silver": _sim.res.silver,
		"population": _sim.res.population,
		"power_supply": _sim.res.power_supply,
		"power_used": _sim.res.power_used,
	}

	_logger.log_snapshot(label, _sim.hour_index, _sim.day, state)
	return {"ok": true}


func _advance_to_next_production() -> Dictionary:
	var guard: int = max(_max_hours - _sim.hour_index, 0) + 1
	while guard > 0:
		_sim._advance_hour()
		_invariants.check_continuous(_sim, _logger)
		if _sim.hour_index > _max_hours:
			return {"ok": false, "message": "Max hours exceeded"}
		if _sim.production_executed_today and _sim.hour_of_day == _sim.scheduled_production_hour:
			return {"ok": true}
		guard -= 1
	return {"ok": false, "message": "Max hours exceeded while awaiting production"}


func _command_stalled(cmd_type: String) -> bool:
	var obs: Array[String] = []
	if _sim._last_obs_tokens is Array:
		obs = _sim._last_obs_tokens as Array[String]
	return obs.has("CMD_STALL@%s" % cmd_type)


func _trade_rejected(obs: Array[String]) -> bool:
	for token in obs:
		var text := str(token)
		if text.begins_with("TRADE_REJECTED") or text.begins_with("TRADE_NO_"):
			return true
	return false


func _evaluate_condition(condition: String) -> bool:
	## Simple condition evaluator for common patterns.
	## Supports: res.X OP Y, has_active_expedition, !has_active_expedition

	var cond := condition.strip_edges()

	# Boolean expedition checks.
	if cond == "has_active_expedition":
		return _sim.has_active_expedition()
	if cond == "!has_active_expedition":
		return not _sim.has_active_expedition()

	# Resource comparisons: res.food >= 10
	var resource_pattern := RegEx.new()
	resource_pattern.compile("^res\\.(\\w+)\\s*(==|!=|>=|<=|>|<)\\s*(\\d+)$")
	var match_result := resource_pattern.search(cond)

	if match_result != null:
		var res_key := match_result.get_string(1)
		var op := match_result.get_string(2)
		var value := int(match_result.get_string(3))
		var actual := _sim.res.get_amount(res_key)

		match op:
			"==":
				return actual == value
			"!=":
				return actual != value
			">=":
				return actual >= value
			"<=":
				return actual <= value
			">":
				return actual > value
			"<":
				return actual < value

	# Unknown condition format - fail safe.
	push_warning("Unknown condition format: %s" % condition)
	return false


func _capture_strict_context(action_type: String) -> Dictionary:
	if not _should_sample_strict_command(action_type):
		return {}
	return {
		"pre_state": _sim._test_export_state(),
		"pre_signature": _sim._state_signature(),
		"sampling_index": _strict_command_delta_counter,
	}


func _should_sample_strict_command(action_type: String) -> bool:
	if not _strict_command_deltas_enabled:
		return false
	if not STRICT_DELTA_COMMANDS.has(action_type):
		return false
	_strict_command_delta_counter += 1
	if _strict_delta_sampling <= 0:
		_strict_delta_sampling = 1
	return _strict_command_delta_counter % _strict_delta_sampling == 0


func _finalize_strict_delta(
	action_type: String,
	payload: Dictionary,
	context: Dictionary,
	result_info: Dictionary
) -> Dictionary:
	if context.is_empty():
		return {"ok": true}
	if not result_info.get("advance_ok", false):
		return {"ok": true}
	var check := _run_strict_delta_check(action_type, payload, context, result_info)
	if check.get("ok", false):
		return {"ok": true}
	return {
		"ok": false,
		"message": check.get("message", "Strict delta mismatch"),
		"strict_failure": check.get("failure", {}),
	}


func _run_strict_delta_check(
	action_type: String,
	payload: Dictionary,
	context: Dictionary,
	result_info: Dictionary
) -> Dictionary:
	var clone := SimScript.new() as Sim
	clone._test_import_state(context.get("pre_state", {}))
	if not _simulate_to_next_production(clone):
		return {"ok": true}

	var post_a := _capture_strict_snapshot(_sim)
	var post_b := _capture_strict_snapshot(clone)
	var delta := _compute_delta_summary(post_a, post_b)
	var evaluation := _evaluate_strict_delta(action_type, payload, result_info, delta, post_a, post_b)
	if evaluation.get("ok", false):
		return {"ok": true}

	var failure_payload := {
		"type": "strict_command_delta",
		"command_type": action_type,
		"sampling_index": context.get("sampling_index", -1),
		"pre_signature": context.get("pre_signature", ""),
		"result_info": result_info.duplicate(true),
		"post_a": post_a,
		"post_b": post_b,
		"delta": delta,
	}
	return {
		"ok": false,
		"message": evaluation.get("message", "Strict delta mismatch"),
		"failure": failure_payload,
	}


func _simulate_to_next_production(sim: Sim) -> bool:
	var guard: int = max(_max_hours - sim.hour_index, 0) + 1
	while guard > 0:
		sim._advance_hour()
		if sim.hour_index > _max_hours:
			return false
		if sim.production_executed_today and sim.hour_of_day == sim.scheduled_production_hour:
			return true
		guard -= 1
	return false


func _capture_strict_snapshot(sim: Sim) -> Dictionary:
	return {
		"signature": sim._state_signature(),
		"hour_index": sim.hour_index,
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
			"attention_multiplier": sim.res.attention_multiplier,
		},
		"active_expedition": sim.get_active_expedition(),
		"has_active_expedition": sim.has_active_expedition(),
		"active_expedition_id": sim.has_active_expedition() ? int(sim.get_active_expedition().get("id", 0)) : null,
		"people_count": sim._alive_people_count(),
	}


func _compute_delta_summary(post_a: Dictionary, post_b: Dictionary) -> Dictionary:
	var summary: Dictionary = {}
	var resources: Dictionary = {}
	var a_resources := post_a.get("resources", {})
	var b_resources := post_b.get("resources", {})
	for key in a_resources.keys():
		var a_val := a_resources.get(key, 0)
		var b_val := b_resources.get(key, 0)
		var diff := 0.0
		if a_val is float or b_val is float:
			diff = float(a_val) - float(b_val)
			if abs(diff) >= Sim.SIM_FLOAT_SNAP:
				resources[key] = diff
		else:
			diff = int(a_val) - int(b_val)
			if diff != 0:
				resources[key] = diff
	if not resources.is_empty():
		summary["resources"] = resources

	if post_a.get("has_active_expedition", false) != post_b.get("has_active_expedition", false):
		summary["active_expedition_present"] = {
			"a": post_a.get("has_active_expedition", false),
			"b": post_b.get("has_active_expedition", false),
		}

	var id_a := post_a.get("active_expedition_id", null)
	var id_b := post_b.get("active_expedition_id", null)
	if id_a != id_b:
		summary["active_expedition_id"] = {
			"a": id_a,
			"b": id_b,
		}

	var people_delta := int(post_a.get("people_count", 0)) - int(post_b.get("people_count", 0))
	if people_delta != 0:
		summary["people_count"] = people_delta
	return summary


func _evaluate_strict_delta(
	action_type: String,
	payload: Dictionary,
	result_info: Dictionary,
	delta_summary: Dictionary,
	post_a: Dictionary,
	post_b: Dictionary
) -> Dictionary:
	match action_type:
		"cmd_trade":
			return _evaluate_strict_trade_delta(payload, result_info, delta_summary)
		"cmd_expedition":
			return _evaluate_strict_expedition_delta(payload, result_info, delta_summary)
	_:
			return {"ok": true}


func _evaluate_strict_trade_delta(
	payload: Dictionary,
	result_info: Dictionary,
	delta_summary: Dictionary
) -> Dictionary:
	var resource := str(payload.get("resource", "")).to_lower()
	var direction := str(payload.get("direction", "")).to_lower()
	var amount := int(payload.get("amount", 0))
	if resource == "" or amount == 0:
		return {"ok": true}

	var resource_delta := int(_delta_value(delta_summary, "resources.%s" % resource))
	var silver_delta := int(_delta_value(delta_summary, "resources.silver"))
	var attention_delta := float(_delta_value(delta_summary, "resources.attention_multiplier"))

	var stalled := result_info.get("stalled", false)
	var rejected := result_info.get("rejected", false)
	var success := not stalled and not rejected

	if not success:
		if resource_delta != 0 or silver_delta != 0 or abs(attention_delta) >= Sim.SIM_FLOAT_SNAP:
			return {"ok": false, "message": "Strict trade delta non-zero despite stall/reject"}
		return {"ok": true}

	var expected_resource_delta: int = 0
	var expected_silver_delta: int = 0
	var rate_valid := true

	match direction:
		"buy":
			expected_resource_delta = amount
			var rate := int(Sim.TRADE_BUY_RATES.get(resource, 0))
			if rate <= 0:
				rate_valid = false
			else:
				expected_silver_delta = -amount * rate
		"sell":
			expected_resource_delta = -amount
			var rate := int(Sim.TRADE_SELL_RATES.get(resource, 0))
			if rate <= 0:
				rate_valid = false
			else:
				expected_silver_delta = amount * rate
		_:
			return {"ok": true}

	var attention_cost := clamp(
		Sim.TRADE_ATTENTION_BASE + (float(amount) * Sim.TRADE_ATTENTION_PER_UNIT),
		0.0,
		Sim.TRADE_ATTENTION_CAP
	)

	if resource_delta != expected_resource_delta:
		return {"ok": false, "message": "Strict trade resource delta mismatch (%s vs %s)" % [resource_delta, expected_resource_delta]}
	if rate_valid and silver_delta != expected_silver_delta:
		return {"ok": false, "message": "Strict trade silver delta mismatch (%s vs %s)" % [silver_delta, expected_silver_delta]}
	if abs(attention_delta - attention_cost) > Sim.SIM_FLOAT_SNAP:
		return {"ok": false, "message": "Strict trade attention delta mismatch (%.3f vs %.3f)" % [attention_delta, attention_cost]}
	return {"ok": true}


func _evaluate_strict_expedition_delta(
	payload: Dictionary,
	result_info: Dictionary,
	delta_summary: Dictionary
) -> Dictionary:
	if result_info.get("pre_has_active", false):
		return {"ok": true}

	var stalled := result_info.get("stalled", false)
	var post_has_active := result_info.get("post_has_active", false)
	var success := not stalled and post_has_active

	var has_active_change := delta_summary.has("active_expedition_present") or delta_summary.has("active_expedition_id")

	if not success:
		if not delta_summary.is_empty():
			return {"ok": false, "message": "Strict expedition delta non-zero despite stall/reject"}
		return {"ok": true}

	if not has_active_change:
		return {"ok": false, "message": "Strict expedition delta missing active expedition change"}
	return {"ok": true}


func _delta_value(data: Dictionary, path: String) -> Variant:
	var parts := path.split(".")
	var current: Variant = data
	for part in parts:
		if current is Dictionary and current.has(part):
			current = current.get(part)
		else:
			return 0
	return current
