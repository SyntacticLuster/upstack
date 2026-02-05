extends RefCounted
class_name StressActionGenerator

const DEFAULT_HISTORY_LIMIT: int = 200

const DEFAULT_ACTION_WEIGHTS := {
	"advance_hours": 40,
	"cmd_rations": 8,
	"cmd_expedition": 12,
	"cmd_trade": 12,
	"trade_immediate": 4,
	"cmd_module_enable": 6,
	"cmd_module_priority": 4,
	"cmd_outsiders": 4,
	"lever_apply": 8,
	"wait_expedition": 4,
	"snapshot": 2,
}

var _rng: RandomNumberGenerator
var _history: Array[Dictionary] = []
var _history_limit: int = DEFAULT_HISTORY_LIMIT
var _weights: Dictionary = {}
var _lever_cycle: Array[String] = []
var _lever_index: int = 0
var _trade_bounds: Dictionary = {"min": 1, "max": 50}
var _lever_durations: Dictionary = {"min_hours": 12, "max_hours": 96}
var _expedition_destinations: Array[String] = []
var _coverage_remaining: Array[String] = []


func setup(seed_value: int, config: Dictionary) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(seed_value)
	_history_limit = int(config.get("history_limit", DEFAULT_HISTORY_LIMIT))
	var weights_value: Variant = config.get("action_weights", DEFAULT_ACTION_WEIGHTS)
	if weights_value is Dictionary:
		_weights = weights_value as Dictionary
	else:
		_weights = DEFAULT_ACTION_WEIGHTS.duplicate(true)
	if _weights.is_empty():
		_weights = DEFAULT_ACTION_WEIGHTS.duplicate(true)
	var trade_value: Variant = config.get("trade_bounds", _trade_bounds)
	if trade_value is Dictionary:
		_trade_bounds = trade_value as Dictionary
	var lever_value: Variant = config.get("lever_durations", _lever_durations)
	if lever_value is Dictionary:
		_lever_durations = lever_value as Dictionary
	var dest_value: Variant = config.get("expedition_destinations", [])
	_expedition_destinations_from_config(dest_value)
	var coverage_value: Variant = config.get("force_coverage", [])
	_coverage_remaining = _normalize_coverage(coverage_value)
	_lever_cycle = [
		Sim.LEVER_RATION_HARDENING,
		Sim.LEVER_LABOR_OVERDRIVE,
		Sim.LEVER_EXPEDITION_COMPRESSION,
		Sim.LEVER_INFORMATION_THROTTLING,
		Sim.LEVER_MODULE_ABANDONMENT,
		Sim.LEVER_EMERGENCY_CONVERSION,
	]
	if not _coverage_remaining.is_empty():
		var merged: Array[String] = []
		for lever_id in _coverage_remaining:
			if not merged.has(lever_id):
				merged.append(lever_id)
		for lever_id in _lever_cycle:
			if not merged.has(lever_id):
				merged.append(lever_id)
		_lever_cycle = merged


func next_action(sim: Sim) -> Dictionary:
	var action_type := _pick_weighted_action()
	if not _coverage_remaining.is_empty():
		action_type = "lever_apply"
	var action: Dictionary = {}
	match action_type:
		"advance_hours":
			action = _gen_advance_hours(sim)
		"cmd_rations":
			action = _gen_cmd_rations(sim)
		"cmd_expedition":
			action = _gen_cmd_expedition(sim)
		"trade_immediate":
			action = _gen_trade_immediate(sim)
		"cmd_trade":
			action = _gen_cmd_trade(sim)
		"cmd_module_enable":
			action = _gen_cmd_module_enable(sim)
		"cmd_module_priority":
			action = _gen_cmd_module_priority(sim)
		"cmd_outsiders":
			action = _gen_cmd_outsiders(sim)
		"lever_apply":
			if not _coverage_remaining.is_empty():
				action = _gen_lever_apply(sim, _coverage_remaining.pop_front())
			else:
				action = _gen_lever_apply(sim)
		"wait_expedition":
			action = _gen_wait_expedition(sim)
		"snapshot":
			action = _gen_snapshot(sim)
		_:
			action = _skip_action("unknown action")

	_record_history(action, sim)
	return action


func get_history() -> Array[Dictionary]:
	return _history.duplicate(true)


func _pick_weighted_action() -> String:
	var total: int = 0
	var keys: Array = _weights.keys()
	keys.sort()
	for key in keys:
		total += int(_weights.get(key, 0))
	if total <= 0:
		return "advance_hours"
	var roll: int = int(_rng.randi_range(1, total))
	var running: int = 0
	for key in keys:
		running += int(_weights.get(key, 0))
		if roll <= running:
			return str(key)
	return "advance_hours"


func _gen_advance_hours(_sim: Sim) -> Dictionary:
	var hours: int = 1
	var roll := _rng.randf()
	if roll < 0.6:
		hours = _rng.randi_range(1, 2)
	else:
		hours = _rng.randi_range(1, 6)
	return {"type": "advance_hours", "hours": hours}


func _gen_cmd_rations(_sim: Sim) -> Dictionary:
	var food: float = _rng.randf_range(0.4, 1.0)
	var water: float = _rng.randf_range(0.4, 1.0)
	return {
		"type": "cmd_set_rations",
		"food_ration": snappedf(food, 0.01),
		"water_ration": snappedf(water, 0.01),
	}


func _gen_cmd_expedition(sim: Sim) -> Dictionary:
	if sim.has_active_expedition():
		return _skip_action("expedition already active")
	var destinations: Array[String] = _expedition_destinations_for(sim)
	if destinations.is_empty():
		return _skip_action("no expedition destinations")
	var idx: int = _rng.randi_range(0, destinations.size() - 1)
	var destination_id := destinations[idx]
	var max_party: int = sim.get_max_party_size()
	if max_party <= 0:
		return _skip_action("no available crew")
	var crew: int = _rng.randi_range(1, max_party)
	return {
		"type": "cmd_expedition",
		"destination_id": destination_id,
		"crew": crew,
	}


func _gen_trade_immediate(_sim: Sim) -> Dictionary:
	var payload := _build_trade_payload(_sim)
	if payload.is_empty():
		return _skip_action("no tradeable resources")
	payload["type"] = "trade_immediate"
	return payload

func _gen_cmd_trade(_sim: Sim) -> Dictionary:
	var payload := _build_trade_payload(_sim)
	if payload.is_empty():
		return _skip_action("no tradeable resources")
	payload["type"] = "cmd_trade"
	return payload

func _build_trade_payload(_sim: Sim) -> Dictionary:
	var resources: Array = Sim.TRADEABLE_RESOURCES
	if resources.is_empty():
		return {}
	var direction := "buy" if _rng.randf() < 0.5 else "sell"
	var resource := str(resources[_rng.randi_range(0, resources.size() - 1)])
	var min_amt: int = int(_trade_bounds.get("min", 1))
	var max_amt: int = int(_trade_bounds.get("max", 50))
	var amount: int = _rng.randi_range(max(min_amt, 1), max(max_amt, min_amt))
	return {
		"direction": direction,
		"resource": resource,
		"amount": amount,
	}


func _gen_cmd_module_enable(sim: Sim) -> Dictionary:
	var coords := _random_module_coord(sim)
	if coords.is_empty():
		return _skip_action("no module coords")
	return {
		"type": "cmd_set_module_enabled",
		"f": int(coords.get("f", -1)),
		"x": int(coords.get("x", -1)),
		"y": int(coords.get("y", -1)),
		"enabled": _rng.randf() >= 0.5,
	}


func _gen_cmd_module_priority(sim: Sim) -> Dictionary:
	var coords := _random_module_coord(sim)
	if coords.is_empty():
		return _skip_action("no module coords")
	var floor_idx: int = int(coords.get("f", -1))
	var used: Dictionary = {}
	if floor_idx >= 0 and floor_idx < sim.tower.floors.size():
		var grid: Array[Variant] = sim.tower.floors[floor_idx]
		for y in range(grid.size()):
			var row: Array[Variant] = grid[y]
			for x in range(row.size()):
				if row[x] == null:
					continue
				var priority_value: Variant = sim.tower.get_module_priority_override(floor_idx, x, y)
				if priority_value == null:
					continue
				used[int(priority_value)] = true
	var priority_candidate: int = _rng.randi_range(0, 100)
	var attempts: int = 0
	while attempts < 20 and used.has(priority_candidate):
		priority_candidate = _rng.randi_range(0, 100)
		attempts += 1
	if used.has(priority_candidate):
		priority_candidate = _first_unused_priority(used, 0, 100)
		if priority_candidate < 0:
			return _skip_action("no free priority")
	return {
		"type": "cmd_set_module_priority",
		"f": int(coords.get("f", -1)),
		"x": int(coords.get("x", -1)),
		"y": int(coords.get("y", -1)),
		"priority": priority_candidate,
	}


func _gen_cmd_outsiders(sim: Sim) -> Dictionary:
	var pending: Array[Dictionary] = sim.get_pending_outsiders()
	if pending.is_empty():
		return _skip_action("no pending outsiders")
	var entry: Dictionary = pending[_rng.randi_range(0, pending.size() - 1)]
	var event_id: int = int(entry.get("id", -1))
	if event_id < 0:
		return _skip_action("invalid outsider event")
	return {
		"type": "cmd_outsiders_decision",
		"event_id": event_id,
		"accept": _rng.randf() >= 0.5,
	}


func _gen_lever_apply(sim: Sim, forced_lever: String = "") -> Dictionary:
	if _lever_cycle.is_empty():
		return _skip_action("no levers")
	var lever_id := forced_lever
	if lever_id == "":
		lever_id = _lever_cycle[_lever_index]
		_lever_index = int((_lever_index + 1) % _lever_cycle.size())
	var min_hours: int = int(_lever_durations.get("min_hours", 12))
	var max_hours: int = int(_lever_durations.get("max_hours", 96))
	var duration_hours: int = _rng.randi_range(max(min_hours, 1), max(max_hours, min_hours))
	var payload: Dictionary = {}
	match lever_id:
		Sim.LEVER_RATION_HARDENING:
			payload = {
				"mode": "soft" if _rng.randf() < 0.5 else "hard",
				"duration_hours": duration_hours,
			}
		Sim.LEVER_LABOR_OVERDRIVE:
			payload = {
				"intensity": _rng.randi_range(1, Sim.LABOR_OVERDRIVE_MAX_INTENSITY),
				"duration_hours": duration_hours,
			}
		Sim.LEVER_EXPEDITION_COMPRESSION:
			payload = {
				"intensity": _rng.randi_range(1, Sim.EXPEDITION_COMPRESSION_MAX_INTENSITY),
				"duration_hours": duration_hours,
			}
		Sim.LEVER_INFORMATION_THROTTLING:
			payload = {
				"level": _rng.randi_range(1, Sim.INFO_THROTTLE_MAX_LEVEL),
				"duration_hours": duration_hours,
			}
		Sim.LEVER_MODULE_ABANDONMENT:
			var coords := _random_module_coord(sim)
			if coords.is_empty():
				return _skip_action("no module coords")
			payload = coords
		Sim.LEVER_EMERGENCY_CONVERSION:
			var resources: Array[String] = Sim.CONVERTIBLE_RESOURCES
			if resources.size() < 2:
				return _skip_action("no convertible resources")
			var from_key := resources[_rng.randi_range(0, resources.size() - 1)]
			var to_key := resources[_rng.randi_range(0, resources.size() - 1)]
			if from_key == to_key:
				return _skip_action("conversion same resource")
			payload = {
				"from": from_key,
				"to": to_key,
				"amount": _rng.randi_range(1, 10),
			}
		_:
			return _skip_action("unknown lever")
	return {
		"type": "lever",
		"lever_id": lever_id,
		"payload": payload,
	}


func _gen_wait_expedition(sim: Sim) -> Dictionary:
	if not sim.has_active_expedition():
		return _skip_action("no active expedition")
	return {
		"type": "wait_expedition_resolve",
		"timeout_hours": _rng.randi_range(12, 96),
	}


func _gen_snapshot(sim: Sim) -> Dictionary:
	return {
		"type": "snapshot",
		"label": "auto_%d" % sim.hour_index,
	}


func _skip_action(reason: String) -> Dictionary:
	return {
		"type": "comment",
		"text": "skip",
		"reason": reason,
		"skipped": true,
	}


func _record_history(action: Dictionary, sim: Sim) -> void:
	var entry := action.duplicate(true)
	entry["hour"] = sim.hour_index
	entry["day"] = sim.day
	_history.append(entry)
	if _history.size() > _history_limit:
		_history.pop_front()


func _random_module_coord(sim: Sim) -> Dictionary:
	var coords: Array[Dictionary] = []
	for floor_idx in range(sim.tower.floor_count()):
		var grid: Array[Variant] = sim.tower.floors[floor_idx]
		for y in range(grid.size()):
			var row: Array[Variant] = grid[y]
			for x in range(row.size()):
				if row[x] == null:
					continue
				coords.append({"f": floor_idx, "x": x, "y": y})
	if coords.is_empty():
		return {}
	return coords[_rng.randi_range(0, coords.size() - 1)]


func _expedition_destinations_for(sim: Sim) -> Array[String]:
	if not _expedition_destinations.is_empty():
		return _expedition_destinations.duplicate()
	var result: Array[String] = []
	if sim.map_def != null:
		for loc in sim.map_def.get_expedition_destinations():
			var location: MapDef.LocationDef = loc
			result.append(location.id)
	return result


func _expedition_destinations_from_config(value: Variant) -> void:
	_expedition_destinations_clear()
	if value is Array:
		for entry in value:
			var id := str(entry)
			if id != "":
				_expedition_destinations.append(id)


func _expedition_destinations_clear() -> void:
	_expedition_destinations.clear()


func _normalize_coverage(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			var lever_id := str(entry)
			if lever_id != "" and not result.has(lever_id):
				result.append(lever_id)
	return result


func _first_unused_priority(used: Dictionary, min_value: int, max_value: int) -> int:
	var start: int = min(min_value, max_value)
	var end: int = max(min_value, max_value)
	for value in range(start, end + 1):
		if not used.has(value):
			return value
	return -1
