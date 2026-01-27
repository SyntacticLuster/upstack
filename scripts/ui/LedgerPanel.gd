extends PanelContainer

@onready var status_label: Label = $VBox/Status
@onready var list_container: VBoxContainer = $VBox/Scroll/Items

var _sim_bridge: SimBridge = null
var _last_count: int = -1
var _max_visible: int = 300

func set_sim(sim_ref: Object) -> void:
	if _sim_bridge == null:
		_sim_bridge = SimBridge.new()
	_sim_bridge.set_sim(sim_ref)

func refresh() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		status_label.text = "DISCONNECTED"
		_clear_items()
		return
	var events: Array = _sim_bridge.get_events()
	if events.size() == 0:
		status_label.text = "NO EVENTS"
		_clear_items()
		_last_count = 0
		return
	status_label.text = "EVENTS: %d" % [events.size()]
	if events.size() == _last_count:
		return
	_last_count = events.size()
	_render_events(events)

func _clear_items() -> void:
	for child in list_container.get_children():
		child.queue_free()
	_last_count = -1

func _render_events(events: Array) -> void:
	for child in list_container.get_children():
		child.queue_free()
	var start_index: int = int(max(events.size() - _max_visible, 0))
	for i in range(start_index, events.size()):
		var entry: Variant = events[i]
		var label := Label.new()
		label.text = _format_event(entry)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_container.add_child(label)

func _format_event(entry: Variant) -> String:
	if not (entry is Dictionary):
		return str(entry)
	var d: Dictionary = entry
	var day: Variant = d.get("day", "?")
	var lever_id: Variant = d.get("lever_id", d.get("type", "event"))
	var event_type: Variant = d.get("type", "lever")
	var payload: Variant = d.get("payload", {})
	var immediate: Variant = d.get("immediate_effects_summary", "")
	var debts: Variant = d.get("debts_applied", "")
	var payload_summary: String = _format_payload(payload)
	var summary: String = _join_summary(str(immediate), str(debts))
	return "[%s] [%s] %s %s %s" % [str(day), str(event_type), str(lever_id), payload_summary, summary]

func _format_payload(payload: Variant) -> String:
	if not (payload is Dictionary):
		return str(payload)
	var parts: Array[String] = []
	for key in payload.keys():
		parts.append("%s=%s" % [str(key), str(payload.get(key))])
	if parts.is_empty():
		return "{}"
	return "{" + ", ".join(parts) + "}"

func _join_summary(a: String, b: String) -> String:
	if a == "" and b == "":
		return ""
	if a != "" and b != "":
		return "[%s | %s]" % [a, b]
	return "[%s]" % (a if a != "" else b)
