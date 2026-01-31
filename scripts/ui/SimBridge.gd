extends Node
class_name SimBridge

var _sim: Object = null

const DEFAULT_SEVERITY := "debug"
const DEFAULT_VISIBILITY := "dev_only"
const VISIBILITY_CATEGORY := {
	"dev_only": "DEBUG",
	"player_feed": "SIM",
	"toast": "SIM",
	"sticky": "EVENT",
	"modal": "EVENT",
}

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

func get_attention_meter_value() -> float:
	if _sim == null:
		return 0.0
	if _sim.has_method("get_attention_meter_value"):
		return float(_sim.get_attention_meter_value())
	var value: Variant = _get_sim_property("expedition_attention")
	if value == null:
		return 0.0
	match typeof(value):
		TYPE_INT:
			return float(value)
		TYPE_FLOAT:
			return float(value)
	return 0.0

func get_threat_meter_value() -> int:
	if _sim == null:
		return 0
	if _sim.has_method("get_threat_meter_value"):
		return int(_sim.get_threat_meter_value())
	var res_value := get_res() as Resources
	if res_value != null:
		return int(res_value.threat)
	return 0

func get_events() -> Array[Dictionary]:
	var empty_events: Array[Dictionary] = []
	if _sim == null:
		return empty_events
	var raw_events := _collect_raw_events()
	if raw_events.is_empty():
		return empty_events
	return _normalize_events(raw_events)

func get_module_snapshots() -> Array[Dictionary]:
	var empty_snapshots: Array[Dictionary] = []
	if _sim == null:
		return empty_snapshots
	if not _sim.has_method("module_snapshots"):
		return empty_snapshots
	var snapshots: Variant = _sim.module_snapshots()
	if snapshots is Array:
		return snapshots
	return empty_snapshots

func _collect_raw_events() -> Array:
	var collected: Array = []
	var events_value: Variant = _get_sim_property("events")
	if events_value is Array:
		collected = events_value
		return collected
	var lever_value: Variant = _get_sim_property("lever_events")
	if lever_value is Array:
		collected = lever_value
	return collected

func _normalize_events(raw_events: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	for idx in range(raw_events.size()):
		var entry: Variant = raw_events[idx]
		var normalized_entry := _normalize_event_entry(entry, idx)
		normalized.append(normalized_entry)
	return normalized

func _normalize_event_entry(entry: Variant, fallback_index: int) -> Dictionary:
	var normalized: Dictionary = {}
	if entry is Dictionary:
		normalized = entry.duplicate(true)
	else:
		normalized = {"message": str(entry)}

	var type_value: Variant = normalized.get("type", null)
	var event_type := str(type_value) if type_value != null and str(type_value) != "" else ""
	if event_type == "" and normalized.has("lever_id"):
		event_type = str(normalized.get("lever_id"))
	if event_type == "" and normalized.has("category"):
		event_type = str(normalized.get("category"))
	if event_type == "":
		event_type = "DEBUG_EVENT"
	normalized["type"] = event_type

	var severity_value: Variant = normalized.get("severity", DEFAULT_SEVERITY)
	var severity := str(severity_value)
	if severity == "":
		severity = DEFAULT_SEVERITY
	normalized["severity"] = severity

	var visibility_value: Variant = normalized.get("visibility", DEFAULT_VISIBILITY)
	var visibility := str(visibility_value)
	if visibility == "":
		visibility = DEFAULT_VISIBILITY
	normalized["visibility"] = visibility

	var payload_value: Variant = normalized.get("payload", null)
	if payload_value is Dictionary:
		normalized["payload"] = payload_value
	elif payload_value != null:
		normalized["payload"] = {}

	var message_value: Variant = normalized.get("message", "")
	var message := str(message_value)
	if message == "":
		message = _format_message(normalized)
	normalized["message"] = message

	if not normalized.has("day"):
		var day_value: Variant = _get_sim_property("day")
		if day_value != null:
			normalized["day"] = int(day_value)

	if not normalized.has("hour") and normalized.has("hour_of_day"):
		var hour_value: Variant = normalized.get("hour_of_day", null)
		if hour_value != null:
			normalized["hour"] = int(hour_value)

	if not normalized.has("category"):
		var category_value: Variant = VISIBILITY_CATEGORY.get(visibility, "DEBUG")
		normalized["category"] = str(category_value)

	if not normalized.has("key"):
		var key := ""
		if normalized.has("id"):
			var id_value: Variant = normalized.get("id", "")
			key = "id:%s" % str(id_value)
		else:
			var day_token := str(normalized.get("day", ""))
			var hour_token := str(normalized.get("hour", ""))
			key = "%s|%s|%s|%s|%d" % [event_type, day_token, hour_token, message, fallback_index]
		normalized["key"] = key

	return normalized

func _format_message(entry: Dictionary) -> String:
	var parts: Array[String] = []
	var immediate := str(entry.get("immediate_effects_summary", ""))
	if immediate != "":
		parts.append(immediate)
	var debts := str(entry.get("debts_applied", ""))
	if debts != "":
		parts.append(debts)
	if parts.is_empty():
		var payload_value: Variant = entry.get("payload", null)
		if payload_value is Dictionary and payload_value.size() > 0:
			var payload_parts: Array[String] = []
			var payload: Dictionary = payload_value
			for key in payload.keys():
				var payload_item: Variant = payload.get(key)
				payload_parts.append("%s=%s" % [key, str(payload_item)])
			parts.append("payload {" + ", ".join(payload_parts) + "}")
		else:
			parts.append(str(entry.get("lever_id", "event")))
	return ", ".join(parts)

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
