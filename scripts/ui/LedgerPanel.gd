
extends PanelContainer

const FILTERS: Array[String] = ["All", "Sim", "Events", "Debug"]
const MAX_VISIBLE := 300

const FILTER_TO_CATEGORY := {
	"All": "ALL",
	"Sim": "SIM",
	"Events": "EVENT",
	"Debug": "DEBUG",
}

const COLOR_NEUTRAL := Color(0.44, 0.50, 0.55)
const COLOR_DANGER := Color(0.78, 0.22, 0.22)
const COLOR_DEBUG := Color(0.54, 0.39, 0.63)
const CATEGORY_COLORS := {
	"SIM": COLOR_NEUTRAL,
	"EVENT": COLOR_DANGER,
	"DEBUG": COLOR_DEBUG,
}

@onready var status_label: Label = $Root/Status
@onready var scroll_container: ScrollContainer = $Root/Scroll
@onready var list_container: VBoxContainer = $Root/Scroll/Items
@onready var filter_buttons: Dictionary = {
	"All": $Root/Filters/AllFilter,
	"Sim": $Root/Filters/SimFilter,
	"Events": $Root/Filters/EventsFilter,
	"Debug": $Root/Filters/DebugFilter,
}
@onready var header_row: HBoxContainer = $Root/HeaderRow
@onready var filters_row: HBoxContainer = $Root/Filters
@onready var collapse_button: Button = $Root/HeaderRow/CollapseButton
@onready var collapsed_preview: Label = $Root/CollapsedPreview

var _sim_bridge: SimBridge = null
var _active_filter: String = "All"
var _collapsed: bool = false

func _ready() -> void:
	_setup_filters()
	collapse_button.pressed.connect(_on_collapse_pressed)
	_update_collapse_state(false)

func set_sim(sim_ref: Object) -> void:
	if _sim_bridge == null:
		_sim_bridge = SimBridge.new()
	_sim_bridge.set_sim(sim_ref)

func refresh() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		status_label.text = "STATUS: DISCONNECTED"
		_clear_items()
		collapsed_preview.text = "LAST: -"
		return

	var events: Array = _sim_bridge.get_events()
	if events.is_empty():
		status_label.text = "STATUS: NO EVENTS"
		_clear_items()
		collapsed_preview.text = "LAST: -"
		return

	var auto_scroll := _should_auto_scroll()
	var normalized := _normalize_events(events)
	_rebuild_rows(normalized)
	_update_status_label(events.size())
	_update_collapsed_preview(normalized)

	if auto_scroll:
		call_deferred("_scroll_to_bottom")

func _setup_filters() -> void:
	for filter_name in FILTERS:
		var button: Button = filter_buttons.get(filter_name)
		if button == null:
			continue
		button.toggle_mode = true
		button.set_pressed_no_signal(filter_name == _active_filter)
		if not button.pressed.is_connected(Callable(self, "_on_filter_pressed").bind(filter_name)):
			button.pressed.connect(Callable(self, "_on_filter_pressed").bind(filter_name))

func _on_filter_pressed(filter_name: String) -> void:
	if not FILTERS.has(filter_name):
		return
	if _active_filter == filter_name:
		return
	_active_filter = filter_name
	_refresh_filter_buttons()
	_apply_filter_to_all_rows()

func _refresh_filter_buttons() -> void:
	for filter_name in FILTERS:
		var button: Button = filter_buttons.get(filter_name)
		if button == null:
			continue
		button.set_pressed_no_signal(filter_name == _active_filter)

func _update_status_label(count: int) -> void:
	status_label.text = "STATUS: EVENTS: %d · FILTER: %s" % [count, _active_filter.to_upper()]

func _on_collapse_pressed() -> void:
	_update_collapse_state(not _collapsed)

func _update_collapse_state(collapsed: bool) -> void:
	_collapsed = collapsed
	if collapsed:
		if collapse_button.get_parent() != filters_row:
			collapse_button.reparent(filters_row)
		collapse_button.text = "EXPAND ▸"
		header_row.visible = false
		status_label.visible = false
		scroll_container.visible = false
		collapsed_preview.visible = true
		custom_minimum_size = Vector2(custom_minimum_size.x, 40)
	else:
		if collapse_button.get_parent() != header_row:
			collapse_button.reparent(header_row)
		collapse_button.text = "COLLAPSE ▾"
		header_row.visible = true
		status_label.visible = true
		scroll_container.visible = true
		collapsed_preview.visible = false
		custom_minimum_size = Vector2(custom_minimum_size.x, 120)

func _normalize_events(events: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var last_batch: Dictionary = {}
	for entry in events:
		var category := _category_from_entry(entry)
		var time_info := _time_info(entry)
		var day := int(time_info.get("day", -1))
		var hour := int(time_info.get("hour", -1))
		if category == "SIM" and day >= 0 and hour >= 0:
			if not last_batch.is_empty() and last_batch.get("category") == "SIM" and last_batch.get("day") == day and last_batch.get("hour") == hour:
				var count := int(last_batch.get("count", 1)) + 1
				last_batch["count"] = count
				last_batch["message"] = "Hour %02d: %d resource updates" % [hour, count]
				normalized[normalized.size() - 1] = last_batch
				continue
		var message := _format_message(entry)
		var row := {
			"day": day,
			"hour": hour,
			"category": category,
			"message": message,
			"count": 1,
		}
		if category == "SIM" and day >= 0 and hour >= 0:
			row["message"] = "Hour %02d: 1 resource update" % hour
		last_batch = row
		normalized.append(row)
	return normalized

func _rebuild_rows(entries: Array[Dictionary]) -> void:
	_clear_items()
	for entry in entries:
		_append_event(entry)
	if list_container.get_child_count() > MAX_VISIBLE:
		_trim_to_limit()
	_apply_filter_to_all_rows()

func _append_event(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0.0, 28.0)
	row.add_theme_constant_override("separation", 8)

	var time_label := Label.new()
	time_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	time_label.text = _format_time_token(entry)

	var category := str(entry.get("category", "DEBUG"))
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var chip_label := Label.new()
	chip_label.text = category.capitalize()
	chip.add_child(chip_label)
	_apply_chip_style(chip, _category_color(category))

	var message_label := Label.new()
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	message_label.text = _truncate_message(str(entry.get("message", "")))

	row.add_child(time_label)
	row.add_child(chip)
	row.add_child(message_label)
	list_container.add_child(row)

	row.set_meta("category", category)

func _trim_to_limit() -> void:
	while list_container.get_child_count() > MAX_VISIBLE:
		var oldest := list_container.get_child(0)
		if oldest != null:
			oldest.queue_free()

func _clear_items() -> void:
	for child in list_container.get_children():
		child.queue_free()

func _format_time_token(entry: Dictionary) -> String:
	var day := int(entry.get("day", -1))
	var hour := int(entry.get("hour", -1))
	if day >= 0 and hour >= 0:
		return "Day %d · Hour %02d" % [day, hour]
	if day >= 0:
		return "Day %d" % day
	return "Time ?"

func _time_info(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var day_value: Variant = entry.get("day", null)
	var hour_value: Variant = entry.get("hour", entry.get("hour_of_day", null))
	var info := {}
	if day_value != null:
		info["day"] = int(day_value)
	if hour_value != null:
		info["hour"] = int(hour_value)
	return info

func _format_message(entry: Variant) -> String:
	if not (entry is Dictionary):
		return str(entry)
	var parts: Array[String] = []
	var immediate := str(entry.get("immediate_effects_summary", ""))
	if immediate != "":
		parts.append(immediate)
	var debts := str(entry.get("debts_applied", ""))
	if debts != "":
		parts.append(debts)
	if parts.is_empty():
		var payload_variant: Variant = entry.get("payload", {})
		if payload_variant is Dictionary and payload_variant.size() > 0:
			var payload_parts: Array[String] = []
			var payload: Dictionary = payload_variant
			for key in payload.keys():
				payload_parts.append("%s=%s" % [key, payload.get(key)])
			parts.append("payload {" + ", ".join(payload_parts) + "}")
		else:
			parts.append(str(entry.get("lever_id", "event")))
	return ", ".join(parts)

func _truncate_message(message: String) -> String:
	if message.length() <= 80:
		return message
	return message.left(77) + "..."

func _update_collapsed_preview(entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		collapsed_preview.text = "LAST: -"
		return
	var last_entry := entries[entries.size() - 1]
	collapsed_preview.text = "LAST: %s" % _truncate_message(str(last_entry.get("message", "")))

func _should_auto_scroll() -> bool:
	var scrollbar: VScrollBar = scroll_container.get_v_scrollbar()
	if scrollbar == null:
		return true
	return scrollbar.value >= scrollbar.max_value - 4

func _scroll_to_bottom() -> void:
	var scrollbar: VScrollBar = scroll_container.get_v_scrollbar()
	if scrollbar == null:
		return
	scrollbar.value = scrollbar.max_value

func _apply_filter_to_all_rows() -> void:
	for row in list_container.get_children():
		var category: String = str(row.get_meta("category", "DEBUG"))
		row.visible = _matches_filter(category)

func _matches_filter(category: String) -> bool:
	var filter_token: String = str(FILTER_TO_CATEGORY.get(_active_filter, "ALL"))
	if filter_token == "ALL":
		return true
	return category == filter_token

func _category_from_entry(entry: Variant) -> String:
	if entry is Dictionary:
		var label := str(entry.get("category", entry.get("type", entry.get("lever_id", "")))).to_upper()
		var matched := _match_category_token(label)
		if matched != "":
			return matched
		var hint := _message_hint(entry)
		matched = _match_category_token(hint)
		if matched != "":
			return matched
	else:
		var raw := str(entry).to_upper()
		var matched := _match_category_token(raw)
		if matched != "":
			return matched
	return "DEBUG"

func _match_category_token(text: String) -> String:
	if text == "":
		return ""
	if text.find("SIM") != -1:
		return "SIM"
	if text.find("EVENT") != -1:
		return "EVENT"
	if text.find("DEBUG") != -1:
		return "DEBUG"
	return ""

func _category_color(category: String) -> Color:
	return CATEGORY_COLORS.get(str(category).to_upper(), COLOR_NEUTRAL)

func _message_hint(entry: Dictionary) -> String:
	var parts: Array[String] = []
	var immediate := str(entry.get("immediate_effects_summary", ""))
	if immediate != "":
		parts.append(immediate)
	var debts := str(entry.get("debts_applied", ""))
	if debts != "":
		parts.append(debts)
	return ", ".join(parts).to_upper()

func _apply_chip_style(chip: PanelContainer, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
