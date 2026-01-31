extends PanelContainer

const STAT_DEFINITIONS: Array[Dictionary] = [
	{"label": "Food", "path": ["res", "food"], "group": "resource"},
	{"label": "Water", "path": ["res", "water"], "group": "resource"},
	{"label": "Materials", "path": ["res", "materials"], "group": "resource"},
	{"label": "Silver", "path": ["res", "silver"], "group": "currency"},
	{"label": "Gold", "path": ["res", "gold"], "group": "currency"},
	{"label": "Morale", "path": ["res", "morale"], "group": "status"},
	{"label": "Threat", "path": ["res", "threat"], "group": "status"},
	{"label": "Population", "path": ["res", "population"], "group": "status"},
]

const COLLAPSED_ICON_MAP := {
	"Food": "F",
	"Water": "W",
	"Materials": "M",
	"Silver": "SI",
	"Gold": "G",
	"Morale": "MO",
	"Threat": "TH",
	"Population": "POP",
}

const COLOR_STATUS_GOOD: Color = Color(0.29, 0.56, 0.85)
const COLOR_STATUS_BAD: Color = Color(0.78, 0.22, 0.22)
const COLOR_STATUS_NEUTRAL: Color = Color(0.44, 0.53, 0.63)
const COLOR_METER_GREEN: Color = Color(0.22, 0.64, 0.39)
const COLOR_METER_YELLOW: Color = Color(0.78, 0.64, 0.2)
const COLOR_METER_RED: Color = Color(0.78, 0.22, 0.22)
const METER_GREEN_MAX := 49.0
const METER_YELLOW_MAX := 79.0
const VALUE_TWEEN_DURATION := 0.18
const LEFT_RAIL_COLLAPSED_WIDTH := 32.0

@onready var day_label: Label = $Root/TopBarPanel/TopBar/DayGroup/DayValue
@onready var time_label: Label = $Root/TopBarPanel/TopBar/DayGroup/TimeValue
@onready var alerts_group: Control = $Root/TopBarPanel/TopBar/AlertsGroup
@onready var alerts_value: Label = $Root/TopBarPanel/TopBar/AlertsGroup/AlertsValue
@onready var alerts_drawer: PanelContainer = $Root/AlertsDrawer
@onready var alerts_items: VBoxContainer = $Root/AlertsDrawer/AlertsRoot/AlertsScroll/AlertsItems
@onready var alerts_close: Button = $Root/AlertsDrawer/AlertsRoot/AlertsHeader/AlertsClose
@onready var overdrive_status_label: Label = $Root/TopBarPanel/TopBar/AlertsGroup/OverdriveStatus
@onready var pause_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/PauseButton
@onready var half_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/HalfButton
@onready var one_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/OneButton
@onready var two_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/TwoButton
@onready var four_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/FourButton
@onready var eight_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/EightButton
@onready var sixteen_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/SixteenButton
@onready var time_controls_row: HBoxContainer = $Root/TopBarPanel/TopBar/TimeControlsRow
@onready var time_controls_column: VBoxContainer = $Root/TopBarPanel/TopBar/TimeControlsColumn

@onready var left_rail_panel: PanelContainer = $Root/MainRow/LeftRailPanel
@onready var expanded_rail: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail
@onready var collapsed_rail: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/CollapsedRail
@onready var resource_cards: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/ResourceCards
@onready var attention_value_label: Label = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/ResourceMeters/AttentionMeter/AttentionHeader/AttentionValue
@onready var threat_value_label: Label = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/ResourceMeters/ThreatMeter/ThreatHeader/ThreatValue
@onready var attention_bar: ProgressBar = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/ResourceMeters/AttentionMeter/AttentionBar
@onready var threat_bar: ProgressBar = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/ResourceMeters/ThreatMeter/ThreatBar
@onready var status_chips: FlowContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/StatusChips
@onready var collapse_button: Button = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/CollapseRail
@onready var expand_button: Button = $Root/MainRow/LeftRailPanel/LeftRailRoot/CollapsedRail/ExpandRail
@onready var collapsed_icons: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/CollapsedRail/CollapsedIcons

var _sim_bridge: SimBridge = null
var _game: Game = null
var _stat_entries: Array[Dictionary] = []
var _pacing_state_callback: Callable = Callable(self, "_on_game_pacing_state_changed")
var _left_rail_collapsed: bool = false
var _left_rail_user_collapsed: bool = false
var _left_rail_width: float = 180.0
var _alert_acknowledged: Dictionary = {}
var _meter_style_green: StyleBoxFlat = null
var _meter_style_yellow: StyleBoxFlat = null
var _meter_style_red: StyleBoxFlat = null

func _ready() -> void:
	_build_stat_entries()
	_build_meter_styles()
	alerts_value.text = "0"
	_connect_pacing_buttons()
	_refresh_pacing_controls()
	collapse_button.pressed.connect(_on_collapse_left_rail)
	expand_button.pressed.connect(_on_expand_left_rail)
	var alerts_group_cb: Callable = Callable(self, "_on_alerts_group_input")
	if alerts_group != null and not alerts_group.gui_input.is_connected(alerts_group_cb):
		alerts_group.mouse_filter = Control.MOUSE_FILTER_STOP
		alerts_group.gui_input.connect(alerts_group_cb)
	var alerts_close_cb: Callable = Callable(self, "_on_alerts_close_pressed")
	if alerts_close != null and not alerts_close.pressed.is_connected(alerts_close_cb):
		alerts_close.pressed.connect(alerts_close_cb)
	_set_alerts_drawer_visible(false)
	_apply_left_rail_state(_left_rail_collapsed)

func set_sim(sim_ref: Object) -> void:
	if _sim_bridge == null:
		_sim_bridge = SimBridge.new()
	_sim_bridge.set_sim(sim_ref)

func set_game(game_ref: Game) -> void:
	if _game == game_ref:
		return
	var cb: Callable = _pacing_state_callback
	if _game != null and _game.has_signal("pacing_state_changed"):
		if _game.pacing_state_changed.is_connected(cb):
			_game.pacing_state_changed.disconnect(cb)
	_game = game_ref
	if _game != null and _game.has_signal("pacing_state_changed"):
		if not _game.pacing_state_changed.is_connected(cb):
			_game.pacing_state_changed.connect(cb)
	_refresh_pacing_controls()

func refresh() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		_set_disconnected()
		return
	_day_phase_time()
	_update_stats()
	_update_meters()
	_refresh_alerts()
	_refresh_overdrive_status()

func set_time_controls_vertical(use_column: bool) -> void:
	if use_column:
		if pause_button.get_parent() != time_controls_column:
			pause_button.reparent(time_controls_column)
		if half_button.get_parent() != time_controls_column:
			half_button.reparent(time_controls_column)
		if one_button.get_parent() != time_controls_column:
			one_button.reparent(time_controls_column)
		if two_button.get_parent() != time_controls_column:
			two_button.reparent(time_controls_column)
		if four_button.get_parent() != time_controls_column:
			four_button.reparent(time_controls_column)
		if eight_button.get_parent() != time_controls_column:
			eight_button.reparent(time_controls_column)
		if sixteen_button.get_parent() != time_controls_column:
			sixteen_button.reparent(time_controls_column)
		time_controls_row.visible = false
		time_controls_column.visible = true
	else:
		if pause_button.get_parent() != time_controls_row:
			pause_button.reparent(time_controls_row)
		if half_button.get_parent() != time_controls_row:
			half_button.reparent(time_controls_row)
		if one_button.get_parent() != time_controls_row:
			one_button.reparent(time_controls_row)
		if two_button.get_parent() != time_controls_row:
			two_button.reparent(time_controls_row)
		if four_button.get_parent() != time_controls_row:
			four_button.reparent(time_controls_row)
		if eight_button.get_parent() != time_controls_row:
			eight_button.reparent(time_controls_row)
		if sixteen_button.get_parent() != time_controls_row:
			sixteen_button.reparent(time_controls_row)
		time_controls_row.visible = true
		time_controls_column.visible = false

func set_left_rail_collapsed(collapsed: bool, reason: String = "user") -> void:
	if reason != "layout":
		_left_rail_user_collapsed = collapsed
	_apply_left_rail_state(collapsed)

func restore_left_rail_from_user() -> void:
	_apply_left_rail_state(_left_rail_user_collapsed)

func apply_left_rail_width(width: float) -> void:
	_left_rail_width = width
	if not _left_rail_collapsed and left_rail_panel != null:
		left_rail_panel.custom_minimum_size = Vector2(_left_rail_width, 0.0)

func _apply_left_rail_state(collapsed: bool) -> void:
	_left_rail_collapsed = collapsed
	if expanded_rail != null:
		expanded_rail.visible = not collapsed
	if collapsed_rail != null:
		collapsed_rail.visible = collapsed
	if left_rail_panel != null:
		var width := LEFT_RAIL_COLLAPSED_WIDTH if collapsed else _left_rail_width
		left_rail_panel.custom_minimum_size = Vector2(width, 0.0)
		left_rail_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if collapsed else Control.SIZE_FILL

func _on_collapse_left_rail() -> void:
	set_left_rail_collapsed(true)

func _on_expand_left_rail() -> void:
	set_left_rail_collapsed(false)

func _connect_pacing_buttons() -> void:
	pause_button.pressed.connect(_on_pause_button_pressed)
	_connect_speed_button(half_button)
	_connect_speed_button(one_button)
	_connect_speed_button(two_button)
	_connect_speed_button(four_button)
	_connect_speed_button(eight_button)
	_connect_speed_button(sixteen_button)

func _build_stat_entries() -> void:
	_clear_children(resource_cards)
	_clear_children(status_chips)
	_clear_children(collapsed_icons)
	_stat_entries.clear()
	for mapping in STAT_DEFINITIONS:
		var entry := _create_stat_entry(mapping)
		if mapping.get("group", "resource") == "status":
			status_chips.add_child(entry.container)
		else:
			resource_cards.add_child(entry.container)
		var collapsed_label: Label = entry.get("collapsed_label") as Label
		if collapsed_label != null:
			collapsed_icons.add_child(collapsed_label)
		_stat_entries.append(entry)

func _clear_children(container: Control) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child != null:
			child.queue_free()

func _create_stat_entry(mapping: Dictionary) -> Dictionary:
	var group := str(mapping.get("group", "resource"))
	var label_text := str(mapping.get("label", "Stat"))
	var collapsed_label := Label.new()
	collapsed_label.text = COLLAPSED_ICON_MAP.get(label_text, label_text.left(2)).to_upper()
	collapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	collapsed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collapsed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	collapsed_label.set_tooltip_text(label_text.to_upper())

	if group == "status":
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var chip_label := Label.new()
		chip_label.text = "%s: N/A" % label_text.to_upper()
		chip_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chip.add_child(chip_label)
		return {
			"map": mapping,
			"value_label": chip_label,
			"indicator_label": null,
			"name_label": null,
			"container": chip,
			"collapsed_label": collapsed_label,
			"last_numeric": NAN,
			"last_display": "",
		}

	var container := PanelContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_FILL
	container.custom_minimum_size = Vector2(0.0, 28.0)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = label_text.to_upper()
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var indicator_label := Label.new()
	indicator_label.text = "•"
	indicator_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	indicator_label.add_theme_color_override("font_color", COLOR_STATUS_NEUTRAL)
	indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var value_label := Label.new()
	value_label.text = "N/A"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	row.add_child(name_label)
	row.add_child(indicator_label)
	row.add_child(value_label)
	container.add_child(row)
	return {
		"map": mapping,
		"value_label": value_label,
		"indicator_label": indicator_label,
		"name_label": name_label,
		"container": container,
		"collapsed_label": collapsed_label,
		"last_numeric": NAN,
		"last_display": "",
	}

func _day_phase_time() -> void:
	var day_val: int = _sim_bridge.get_day_index()
	var day_text := "N/A"
	if _sim_bridge.has_day_value():
		day_text = str(day_val)
	day_label.text = "DAY: %s" % day_text

	var time_display := "N/A"
	if _sim_bridge.has_sim():
		var hour_value: int = _sim_bridge.get_hour_of_day()
		time_display = "%02d:00" % hour_value
	var fast_forward_suffix := _debug_fast_forward_suffix()
	time_label.text = "TIME: %s%s%s" % [time_display, fast_forward_suffix, _pacing_suffix()]

func _update_stats() -> void:
	for entry in _stat_entries:
		var mapping: Dictionary = entry.get("map", {})
		var value_label_variant: Variant = entry.get("value_label")
		var indicator_label_variant: Variant = entry.get("indicator_label")
		var name_label_variant: Variant = entry.get("name_label")
		var value_label := value_label_variant as Label
		var indicator_label := indicator_label_variant as Label
		var name_label := name_label_variant as Label
		if value_label == null:
			continue
		var value: Variant = _read_path(mapping.get("path", []))
		var group := str(mapping.get("group", "resource"))
		var display_value: String = _display_for_value(group, value)
		var change_state := _determine_change_state(entry, value)
		if indicator_label != null:
			_apply_indicator_state(indicator_label, change_state)
		if entry.last_display != display_value:
			_animate_value_change(value_label)
			entry.last_display = display_value
		if name_label == null:
			value_label.text = "%s: %s" % [str(mapping.get("label", "STAT")).to_upper(), display_value]
		else:
			value_label.text = display_value
		entry.last_numeric = _to_numeric(value)
		var collapsed_label: Label = entry.get("collapsed_label") as Label
		if collapsed_label != null:
			collapsed_label.set_tooltip_text("%s: %s" % [str(mapping.get("label", "STAT")).to_upper(), display_value])

func _set_disconnected() -> void:
	day_label.text = "DAY: N/A"
	time_label.text = "TIME: N/A"
	_set_alerts_count(0)
	_alert_acknowledged.clear()
	_clear_alert_items()
	_set_meter_disconnected()
	for entry in _stat_entries:
		var value_label_variant: Variant = entry.get("value_label")
		var value_label := value_label_variant as Label
		if value_label != null:
			value_label.text = "N/A"
			value_label.modulate = Color(1, 1, 1, 1)
		var indicator_label_variant: Variant = entry.get("indicator_label")
		var indicator_label := indicator_label_variant as Label
		if indicator_label != null:
			_apply_indicator_state(indicator_label, "neutral")
		entry.last_display = ""
		entry.last_numeric = NAN
	if overdrive_status_label != null:
		overdrive_status_label.text = "Overdrive: N/A"

func _build_meter_styles() -> void:
	_meter_style_green = _build_meter_style(COLOR_METER_GREEN)
	_meter_style_yellow = _build_meter_style(COLOR_METER_YELLOW)
	_meter_style_red = _build_meter_style(COLOR_METER_RED)

func _build_meter_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style

func _set_meter_disconnected() -> void:
	if attention_value_label != null:
		attention_value_label.text = "N/A"
	if threat_value_label != null:
		threat_value_label.text = "N/A"
	if attention_bar != null:
		attention_bar.value = 0.0
		_apply_meter_band_style(attention_bar, 0.0)
	if threat_bar != null:
		threat_bar.value = 0.0
		_apply_meter_band_style(threat_bar, 0.0)

func _update_meters() -> void:
	if attention_value_label == null or threat_value_label == null:
		return
	if attention_bar == null or threat_bar == null:
		return
	if _sim_bridge == null or not _sim_bridge.has_sim():
		_set_meter_disconnected()
		return
	var attention_raw: float = _sim_bridge.get_attention_meter_value()
	var threat_raw: float = float(_sim_bridge.get_threat_meter_value())
	var attention_value: float = _normalize_meter_value(attention_raw)
	var threat_value: float = _normalize_meter_value(threat_raw)
	attention_bar.value = attention_value
	threat_bar.value = threat_value
	attention_value_label.text = str(int(round(attention_value)))
	threat_value_label.text = str(int(round(threat_value)))
	_apply_meter_band_style(attention_bar, attention_value)
	_apply_meter_band_style(threat_bar, threat_value)

func _normalize_meter_value(raw: float) -> float:
	var normalized: float = raw
	if normalized >= 0.0 and normalized <= 1.0:
		normalized = normalized * 100.0
	return clamp(normalized, 0.0, 100.0)

func _apply_meter_band_style(bar: ProgressBar, value: float) -> void:
	var style: StyleBoxFlat = _meter_style_green
	if value > METER_YELLOW_MAX:
		style = _meter_style_red
	elif value > METER_GREEN_MAX:
		style = _meter_style_yellow
	if style != null:
		bar.add_theme_stylebox_override("fill", style)

func _refresh_alerts() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		_set_alerts_count(0)
		_alert_acknowledged.clear()
		_clear_alert_items()
		return
	var events: Array[Dictionary] = _sim_bridge.get_events()
	if events.is_empty():
		_set_alerts_count(0)
		_alert_acknowledged.clear()
		_clear_alert_items()
		return
	var alert_entries: Array[Dictionary] = []
	for entry in events:
		var visibility_value: Variant = entry.get("visibility", "")
		var visibility := str(visibility_value)
		if visibility == "sticky" or visibility == "modal":
			alert_entries.append(entry)
	_rebuild_alert_items(alert_entries)
	_update_alert_count(alert_entries)

func _refresh_overdrive_status() -> void:
	if overdrive_status_label == null:
		return
	if _sim_bridge == null or not _sim_bridge.has_sim():
		overdrive_status_label.text = "Overdrive: N/A"
		return
	var intensity: int = _variant_to_int(_read_sim_value("labor_overdrive_intensity"))
	var hours_left: int = _variant_to_int(_read_sim_value("labor_overdrive_hours_left"))
	if hours_left > 0 and intensity > 0:
		var percent: int = intensity * 25
		overdrive_status_label.text = "Overdrive L%d (+%d%%)" % [intensity, percent]
	else:
		overdrive_status_label.text = "Overdrive inactive"

func _rebuild_alert_items(entries: Array[Dictionary]) -> void:
	_clear_alert_items()
	for entry in entries:
		var key := _alert_key(entry)
		if key == "":
			continue
		var message := str(entry.get("message", ""))
		var time_token := _alert_time_token(entry)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s\n%s" % [time_token, message]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		row.add_child(label)

		var acknowledged := _alert_acknowledged.has(key)
		var ack_button := Button.new()
		ack_button.text = "ACKNOWLEDGED" if acknowledged else "ACK"
		ack_button.disabled = acknowledged
		if not acknowledged:
			ack_button.pressed.connect(Callable(self, "_on_alert_ack_pressed").bind(key))
		row.add_child(ack_button)
		alerts_items.add_child(row)

func _clear_alert_items() -> void:
	if alerts_items == null:
		return
	for child in alerts_items.get_children():
		child.queue_free()

func _update_alert_count(entries: Array[Dictionary]) -> void:
	var unread := 0
	for entry in entries:
		var key := _alert_key(entry)
		if key == "":
			continue
		if not _alert_acknowledged.has(key):
			unread += 1
	_set_alerts_count(unread)

func _set_alerts_count(count: int) -> void:
	if alerts_value != null:
		alerts_value.text = str(count)

func _alert_key(entry: Dictionary) -> String:
	var key_value: Variant = entry.get("key", "")
	var key := str(key_value)
	if key != "":
		return key
	var type_token := str(entry.get("type", ""))
	var day_token := str(entry.get("day", ""))
	var hour_token := str(entry.get("hour", ""))
	var message := str(entry.get("message", ""))
	return "%s|%s|%s|%s" % [type_token, day_token, hour_token, message]

func _alert_time_token(entry: Dictionary) -> String:
	var day_value: Variant = entry.get("day", -1)
	var hour_value: Variant = entry.get("hour", -1)
	var day := int(day_value)
	var hour := int(hour_value)
	if day >= 0 and hour >= 0:
		return "Day %d · Hour %02d" % [day, hour]
	if day >= 0:
		return "Day %d" % day
	return "Time ?"

func _on_alert_ack_pressed(key: String) -> void:
	acknowledge_alert(key)

func acknowledge_alert(key: String) -> void:
	if key == "":
		return
	_alert_acknowledged[key] = true
	_refresh_alerts()

func _on_alerts_group_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_set_alerts_drawer_visible(not _is_alerts_drawer_visible())

func _on_alerts_close_pressed() -> void:
	_set_alerts_drawer_visible(false)

func _is_alerts_drawer_visible() -> bool:
	return alerts_drawer != null and alerts_drawer.visible

func _set_alerts_drawer_visible(visible: bool) -> void:
	if alerts_drawer == null:
		return
	alerts_drawer.visible = visible

func _determine_change_state(entry: Dictionary, current: Variant) -> String:
	var numeric: float = _to_numeric(current)
	var previous_raw: Variant = entry.get("last_numeric", NAN)
	var previous: float = float(previous_raw) if typeof(previous_raw) in [TYPE_INT, TYPE_FLOAT] else NAN
	if is_nan(numeric) or is_nan(previous):
		return "neutral"
	if numeric > previous:
		return "up"
	if numeric < previous:
		return "down"
	return "neutral"

func _apply_indicator_state(indicator: Label, state: String) -> void:
	match state:
		"up":
			indicator.text = "▲"
			indicator.add_theme_color_override("font_color", COLOR_STATUS_GOOD)
		"down":
			indicator.text = "▼"
			indicator.add_theme_color_override("font_color", COLOR_STATUS_BAD)
		_:
			indicator.text = "•"
			indicator.add_theme_color_override("font_color", COLOR_STATUS_NEUTRAL)

func _animate_value_change(label: Label) -> void:
	label.modulate = Color(1, 1, 1, 0.5)
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color(1, 1, 1, 1), VALUE_TWEEN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _to_numeric(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return NAN

func _display_for_value(group: String, value: Variant) -> String:
	if value == null:
		return "N/A"
	if group == "currency":
		return _format_currency_value(value)
	return str(value)

func _format_currency_value(value: Variant) -> String:
	var amount := 0
	match typeof(value):
		TYPE_INT:
			amount = int(value)
		TYPE_FLOAT:
			amount = int(round(value))
		_:
			return "0.000"
	return _currency_display(amount)

func _currency_display(amount: int) -> String:
	return Resources.format_currency(amount)

func _on_pause_button_pressed() -> void:
	if _game == null:
		return
	_game.toggle_pause()

func _set_speed_index(index: int) -> void:
	if _game == null:
		return
	_game.set_speed_index(index)

func _connect_speed_button(button: Button) -> void:
	if button == null:
		return
	button.pressed.connect(Callable(self, "_on_speed_button_pressed").bind(button))

func _on_speed_button_pressed(button: Button) -> void:
	if _game == null or button == null:
		return
	var multiplier := _parse_speed_multiplier(button.text)
	if multiplier <= 0.0:
		return
	_game.set_speed_multiplier(multiplier)

func _parse_speed_multiplier(label: String) -> float:
	var cleaned := str(label).strip_edges()
	if cleaned == "":
		return -1.0
	var normalized := cleaned.to_lower()
	if normalized.ends_with("x"):
		normalized = normalized.substr(0, normalized.length() - 1).strip_edges()
	return normalized.to_float()

func _on_game_pacing_state_changed(_multiplier: float, _paused: bool) -> void:
	_refresh_pacing_controls()

func _refresh_pacing_controls() -> void:
	var has_game: bool = _game != null
	var paused: bool = false
	var active_index: int = -1
	if has_game:
		paused = _game.is_paused_now()
		active_index = _game.get_speed_index()
	pause_button.text = "RESUME" if paused else "PAUSE"
	pause_button.disabled = not has_game
	var speed_buttons: Array[Button] = [half_button, one_button, two_button, four_button, eight_button, sixteen_button]
	for idx in range(speed_buttons.size()):
		var button: Button = speed_buttons[idx]
		button.disabled = not has_game or idx == active_index

func _pacing_suffix() -> String:
	if _game == null:
		return ""
	if not _game.has_method("get_pacing_label"):
		return ""
	var label := str(_game.get_pacing_label())
	if label == "":
		return ""
	return " (%s)" % label

func _debug_fast_forward_suffix() -> String:
	if not OS.is_debug_build():
		return ""
	if _game == null or not _game.has_method("get_last_hours_processed"):
		return ""
	var hours_processed := int(_game.get_last_hours_processed())
	if hours_processed <= 1:
		return ""
	return " +%dh" % hours_processed

func _read_path(path: Array) -> Variant:
	if path.is_empty():
		return null
	var current: Variant = _sim_bridge.get_sim()
	for key in path:
		if current == null:
			return null
		if current is Object:
			current = current.get(str(key))
		elif current is Dictionary:
			current = current.get(key)
		else:
			return null
	return current

func _read_sim_value(key: String) -> Variant:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		return null
	var sim := _sim_bridge.get_sim()
	if sim == null:
		return null
	return sim.get(key)

func _variant_to_int(value: Variant) -> int:
	if value == null:
		return 0
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(value)
	return 0
