extends Node
class_name SimBridge

var _sim: Object = null

func set_sim(sim_ref: Object) -> void:
	_sim = sim_ref

func get_sim() -> Object:
	return _sim

func has_sim() -> bool:
	return _sim != null

func get_day() -> int:
	var value: Variant = _get_sim_property("day")
	if value == null:
		return 0
	return int(value)

func get_hour_index() -> int:
	var value: Variant = _get_sim_property("hour_index")
	if value == null:
		return 0
	return int(value)

func get_hour_of_day() -> int:
	var value: Variant = _get_sim_property("hour_of_day")
	if value == null:
		return 0
	return int(value)

func get_day_index() -> int:
	if _get_sim_property("hour_index") != null:
		return int(get_hour_index() / 24)
	return get_day()

func get_phase() -> String:
	var value: Variant = _get_sim_property("phase")
	if value == null:
		return ""
	return str(value)

func get_time() -> String:
	var value: Variant = _get_sim_property("time")
	if value == null:
		return ""
	return str(value)

func get_res() -> Object:
	if _sim == null:
		return null
	return _sim.get("res")

func get_events() -> Array[Dictionary]:
	var empty_events: Array[Dictionary] = []
	if _sim == null:
		return empty_events
	for key in ["lever_events", "events"]:
		var value: Variant = _get_sim_property(key)
		if value is Array:
			return value
	return empty_events

func _get_sim_property(key: String) -> Variant:
	if _sim == null:
		return null
	if _sim is Node:
		return _sim.get(key)
	if _sim.has_method("get"):
		return _sim.get(key)
	return null

func has_day_value() -> bool:
	return _get_sim_property("day") != null

func has_phase_value() -> bool:
	return _get_sim_property("phase") != null

func has_time_value() -> bool:
	return _get_sim_property("time") != null

func has_events_value() -> bool:
	return _get_sim_property("lever_events") != null or _get_sim_property("events") != null

func apply_lever(lever_id: String, payload: Dictionary) -> bool:
	if _sim == null:
		return false
	if not _sim.has_method("apply_lever"):
		return false
	return _sim.apply_lever(lever_id, payload)
