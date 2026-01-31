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
const LEDGER_COLLAPSED_HEIGHT := 40
const LEDGER_EXPANDED_MIN_HEIGHT := 225
const SCROLL_FOLLOW_THRESHOLD := 16

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
@onready var modules_container: PanelContainer = $Root/ModulesContainer
@onready var modules_roster: ItemList = $Root/ModulesContainer/ModulesSplit/ModulesRosterPanel/ModulesRoster
@onready var inspector_id_label: Label = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/ModuleIdLabel
@onready var inspector_type_label: Label = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/ModuleTypeLabel
@onready var inspector_location_label: Label = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/ModuleLocationLabel
@onready var inspector_powered_label: Label = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/ModulePoweredLabel
@onready var inspector_online_label: Label = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/ModuleOnlineLabel
@onready var inspector_deltas_section: VBoxContainer = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/DeltasSection
@onready var inspector_deltas_label: Label = $Root/ModulesContainer/ModulesSplit/ModuleInspectorPanel/InspectorContent/DeltasSection/DeltasLabel

var _sim_bridge: SimBridge = null
var _active_filter: String = "All"
var _collapsed: bool = false
var _module_snapshots: Array[Dictionary] = []
var _follow_scroll: bool = true

func _ready() -> void:
	_setup_filters()
	collapse_button.pressed.connect(_on_collapse_pressed)
	modules_roster.connect("item_selected", Callable(self, "_on_module_selected"))
	modules_roster.select_mode = ItemList.SELECT_SINGLE
	var scrollbar := _vertical_scrollbar()
	if scrollbar != null and not scrollbar.value_changed.is_connected(Callable(self, "_on_scroll_value_changed")):
		scrollbar.value_changed.connect(Callable(self, "_on_scroll_value_changed"))
	_follow_scroll = _is_near_bottom()
	_update_collapse_state(false)
	_clear_module_inspector()
	_update_view_mode()

func set_sim(sim_ref: Object) -> void:
	if _sim_bridge == null:
		_sim_bridge = SimBridge.new()
	_sim_bridge.set_sim(sim_ref)

func refresh() -> void:
	_refresh_modules_data()
	if _sim_bridge == null or not _sim_bridge.has_sim():
		status_label.text = "STATUS: DISCONNECTED"
		_clear_items()
		collapsed_preview.text = "LAST: -"
		_update_view_mode()
		return

	var events: Array = _sim_bridge.get_events()
	if events.is_empty():
		status_label.text = "STATUS: NO EVENTS"
		_clear_items()
		collapsed_preview.text = "LAST: -"
		_update_view_mode()
		return

	var auto_scroll := _should_auto_scroll()
	var normalized := _normalize_events(events)
	_rebuild_rows(normalized)
	_update_status_label(events.size())
	_update_collapsed_preview(normalized)

	if auto_scroll:
		call_deferred("_scroll_to_bottom")
	_update_view_mode()

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

	var auto_scroll := _should_auto_scroll()
	_active_filter = filter_name
	_refresh_filter_buttons()
	_apply_filter_to_all_rows()
	_scroll_ledger_to_bottom_if_following(auto_scroll)
	_update_view_mode()

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
		custom_minimum_size = Vector2(custom_minimum_size.x, LEDGER_COLLAPSED_HEIGHT)
	else:
		if collapse_button.get_parent() != header_row:
			collapse_button.reparent(header_row)
		collapse_button.text = "COLLAPSE ▾"
		header_row.visible = true
		status_label.visible = true
		scroll_container.visible = true
		collapsed_preview.visible = false
		custom_minimum_size = Vector2(custom_minimum_size.x, LEDGER_EXPANDED_MIN_HEIGHT)
	_update_view_mode()

func _normalize_events(events: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	for entry in events:
		if not (entry is Dictionary):
			continue
		var category := _category_from_entry(entry)
		var time_info := _time_info(entry)
		var day := int(time_info.get("day", -1))
		var hour := int(time_info.get("hour", -1))
		var message := str(entry.get("message", ""))
		if message == "":
			message = _format_message(entry)
		var visibility := str(entry.get("visibility", "dev_only"))
		var severity := str(entry.get("severity", "debug"))
		var row := {
			"day": day,
			"hour": hour,
			"category": category,
			"message": message,
			"count": 1,
			"visibility": visibility,
			"severity": severity,
		}
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
	row.set_meta("visibility", str(entry.get("visibility", "dev_only")))
	row.set_meta("severity", str(entry.get("severity", "debug")))

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

func _update_view_mode() -> void:
	var manage_modules: bool = modules_container != null and modules_container.get_parent() == $Root
	if manage_modules:
		modules_container.visible = false
	scroll_container.visible = not _collapsed
	status_label.visible = not _collapsed
	collapsed_preview.visible = _collapsed

func _refresh_modules_data() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		_module_snapshots.clear()
		modules_roster.clear()
		_clear_module_inspector()
		return

	var snapshots := _sim_bridge.get_module_snapshots()
	if not (snapshots is Array):
		snapshots = []
	snapshots = snapshots.duplicate(true)
	if snapshots.is_empty():
		_module_snapshots = []
		modules_roster.clear()
		_clear_module_inspector()
		return

	snapshots.sort_custom(Callable(self, "_module_snapshot_compare"))
	_module_snapshots = snapshots
	modules_roster.clear()
	for snapshot in _module_snapshots:
		if snapshot is Dictionary:
			modules_roster.add_item(_format_module_row(snapshot))
		else:
			modules_roster.add_item("module")

	if modules_roster.get_item_count() > 0:
		modules_roster.select(0)
		_on_module_selected(0)
	else:
		_clear_module_inspector()

func _format_module_row(snapshot: Dictionary) -> String:
	if snapshot == null:
		return "unknown module"
	var level_index := int(snapshot.get("floor", -1))
	var x := int(snapshot.get("x", -1))
	var y := int(snapshot.get("y", -1))
	var module_label := str(snapshot.get("name", snapshot.get("type", "unknown"))).to_upper()
	var powered := "yes" if bool(snapshot.get("powered", false)) else "no"
	var online := "yes" if bool(snapshot.get("online", false)) else "no"
	var id := str(snapshot.get("id", "-"))
	return "F%d (%d,%d) %s powered:%s online:%s id:%s" % [level_index, x, y, module_label, powered, online, id]

func _module_snapshot_compare(a: Dictionary, b: Dictionary) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var a_level := int(a.get("floor", 0))
	var b_level := int(b.get("floor", 0))
	if a_level != b_level:
		return a_level < b_level
	var ay := int(a.get("y", 0))
	var by := int(b.get("y", 0))
	if ay != by:
		return ay < by
	var ax := int(a.get("x", 0))
	var bx := int(b.get("x", 0))
	if ax != bx:
		return ax < bx
	var a_type := str(a.get("type", "")).to_lower()
	var b_type := str(b.get("type", "")).to_lower()
	if a_type != b_type:
		return a_type < b_type
	return false

func _on_module_selected(index: int) -> void:
	if index < 0 or index >= _module_snapshots.size():
		_clear_module_inspector()
		return
	var snapshot := _module_snapshots[index]
	if snapshot is Dictionary:
		_update_inspector(snapshot)
	else:
		_clear_module_inspector()

func _clear_module_inspector() -> void:
	inspector_id_label.text = "ID: -"
	inspector_type_label.text = "Type: -"
	inspector_location_label.text = "Location: -"
	inspector_powered_label.text = "Powered: -"
	inspector_online_label.text = "Online: -"
	inspector_deltas_section.visible = false
	inspector_deltas_label.text = ""

func _update_inspector(snapshot: Dictionary) -> void:
	if snapshot == null:
		_clear_module_inspector()
		return
	var id_text := str(snapshot.get("id", "-"))
	var type_text := str(snapshot.get("name", snapshot.get("type", "-")))
	var level_index := int(snapshot.get("floor", -1))
	var x := int(snapshot.get("x", -1))
	var y := int(snapshot.get("y", -1))
	var powered_text := "yes" if bool(snapshot.get("powered", false)) else "no"
	var online_text := "yes" if bool(snapshot.get("online", false)) else "no"
	inspector_id_label.text = "ID: %s" % id_text
	inspector_type_label.text = "Type: %s" % type_text
	inspector_location_label.text = "Location: F%d (%d,%d)" % [level_index, x, y]
	inspector_powered_label.text = "Powered: %s" % powered_text
	inspector_online_label.text = "Online: %s" % online_text
	var delta_summary := _format_module_deltas(snapshot.get("deltas", {}))
	if delta_summary != "":
		inspector_deltas_section.visible = true
		inspector_deltas_label.text = delta_summary
	else:
		inspector_deltas_section.visible = false
		inspector_deltas_label.text = ""

func _format_module_deltas(deltas: Dictionary) -> String:
	if deltas == null or not (deltas is Dictionary):
		return ""
	var keys: Array = deltas.keys()
	if keys.is_empty():
		return ""
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		var value := int(deltas.get(key, 0))
		if value == 0:
			continue
		var delta_sign := "+" if value > 0 else "-"
		parts.append("%s%s %d" % [delta_sign, key, abs(value)])
	return ", ".join(parts)

func _vertical_scrollbar() -> VScrollBar:
	if scroll_container == null:
		return null
	return scroll_container.get_v_scroll_bar()

func _is_near_bottom() -> bool:
	var scrollbar: VScrollBar = _vertical_scrollbar()
	if scrollbar == null:
		return true
	return (scrollbar.max_value - scrollbar.value) <= SCROLL_FOLLOW_THRESHOLD

func _should_auto_scroll() -> bool:
	return _follow_scroll

func _on_scroll_value_changed(_value: float) -> void:
	_follow_scroll = _is_near_bottom()

func _scroll_ledger_to_bottom_if_following(near_bottom: bool) -> void:
	if not near_bottom:
		return
	call_deferred("_scroll_to_bottom")

func _scroll_to_bottom() -> void:
	var scrollbar: VScrollBar = _vertical_scrollbar()
	if scrollbar == null:
		return
	scrollbar.value = scrollbar.max_value

func _apply_filter_to_all_rows() -> void:
	for row in list_container.get_children():
		var category: String = str(row.get_meta("category", "DEBUG"))
		var visibility: String = str(row.get_meta("visibility", "dev_only"))
		var severity: String = str(row.get_meta("severity", "debug"))
		row.visible = _matches_filter(category, visibility, severity)

func _matches_filter(category: String, visibility: String, severity: String) -> bool:
	var filter_token: String = str(FILTER_TO_CATEGORY.get(_active_filter, "ALL"))
	if filter_token == "ALL":
		return true
	match filter_token:
		"DEBUG":
			return visibility == "dev_only" or severity == "debug"
		"SIM":
			return visibility in ["player_feed", "toast", "sticky", "modal"]
		"EVENT":
			return visibility in ["sticky", "modal"]
		_:
			return category == filter_token

func _category_from_entry(entry: Variant) -> String:
	if entry is Dictionary:
		var category_value: Variant = entry.get("category", "")
		var category := str(category_value).to_upper()
		if category != "":
			return category
		var visibility_value: Variant = entry.get("visibility", "")
		var visibility := str(visibility_value)
		match visibility:
			"player_feed", "toast":
				return "SIM"
			"sticky", "modal":
				return "EVENT"
			"dev_only":
				return "DEBUG"
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

func _cleanup_sim_bridge() -> void:
	if _sim_bridge == null:
		return
	if not _sim_bridge.is_queued_for_deletion():
		_sim_bridge.queue_free()
	_sim_bridge = null

func _exit_tree() -> void:
	_cleanup_sim_bridge()
