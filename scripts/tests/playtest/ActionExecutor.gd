extends RefCounted
class_name ActionExecutor

## Executes scenario actions against the simulation.

const LeverDefsRef = preload("res://scripts/sim/LeverDefs.gd")

var _sim: Sim
var _logger: RefCounted  # PlaytestLogger
var _invariants: RefCounted  # Invariants
var _max_hours: int = 1000


func reset(sim: Sim, logger: RefCounted, invariants: RefCounted, max_hours: int) -> void:
	_sim = sim
	_logger = logger
	_invariants = invariants
	_max_hours = max_hours


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

	var result := _sim.queue_trade(resource, direction, amount)

	var payload := {
		"direction": direction,
		"resource": resource,
		"amount": amount,
		"result": result.get("message", ""),
	}

	if result.get("ok", false):
		# Process the trade command immediately.
		_sim._advance_hour()

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
	else:
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
