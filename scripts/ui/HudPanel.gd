extends PanelContainer

const STAT_DEFINITIONS: Array[Dictionary] = [
	{"label": "Food", "path": ["res", "food"], "group": "resource"},
	{"label": "Water", "path": ["res", "water"], "group": "resource"},
	{"label": "Materials", "path": ["res", "materials"], "group": "resource"},
	{"label": "Morale", "path": ["res", "morale"], "group": "status"},
	{"label": "Threat", "path": ["res", "threat"], "group": "status"},
	{"label": "Population", "path": ["res", "population"], "group": "status"},
]

const COLLAPSED_ICON_MAP := {
	"Food": "F",
	"Water": "W",
	"Materials": "M",
	"Morale": "MO",
	"Threat": "TH",
	"Population": "POP",
}

const COLOR_STATUS_GOOD: Color = Color(0.29, 0.56, 0.85)
const COLOR_STATUS_BAD: Color = Color(0.78, 0.22, 0.22)
const COLOR_STATUS_NEUTRAL: Color = Color(0.44, 0.53, 0.63)
const VALUE_TWEEN_DURATION := 0.18
const LEFT_RAIL_COLLAPSED_WIDTH := 32.0

@onready var day_label: Label = $Root/TopBarPanel/TopBar/DayGroup/DayValue
@onready var phase_label: Label = $Root/TopBarPanel/TopBar/DayGroup/PhaseValue
@onready var time_label: Label = $Root/TopBarPanel/TopBar/DayGroup/TimeValue
@onready var alerts_value: Label = $Root/TopBarPanel/TopBar/AlertsGroup/AlertsValue
@onready var pause_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/PauseButton
@onready var half_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/HalfButton
@onready var one_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/OneButton
@onready var two_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/TwoButton
@onready var four_button: Button = $Root/TopBarPanel/TopBar/TimeControlsRow/FourButton
@onready var time_controls_row: HBoxContainer = $Root/TopBarPanel/TopBar/TimeControlsRow
@onready var time_controls_column: VBoxContainer = $Root/TopBarPanel/TopBar/TimeControlsColumn

@onready var left_rail_panel: PanelContainer = $Root/MainRow/LeftRailPanel
@onready var expanded_rail: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail
@onready var collapsed_rail: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/CollapsedRail
@onready var resource_cards: VBoxContainer = $Root/MainRow/LeftRailPanel/LeftRailRoot/ExpandedRail/ResourceCards
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

func _ready() -> void:
	_build_stat_entries()
	alerts_value.text = "0"
	_connect_pacing_buttons()
	_refresh_pacing_controls()
	collapse_button.pressed.connect(_on_collapse_left_rail)
	expand_button.pressed.connect(_on_expand_left_rail)
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
	half_button.pressed.connect(_on_half_button_pressed)
	one_button.pressed.connect(_on_one_button_pressed)
	two_button.pressed.connect(_on_two_button_pressed)
	four_button.pressed.connect(_on_four_button_pressed)

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

	var phase_val: String = _sim_bridge.get_phase()
	var phase_text := "N/A"
	if _sim_bridge.has_phase_value():
		phase_text = phase_val
	phase_label.text = "PHASE: %s" % phase_text

	var hour_text := "N/A"
	if _sim_bridge.has_sim():
		hour_text = "%02d" % _sim_bridge.get_hour_of_day()
	time_label.text = "HOUR: %s%s" % [hour_text, _pacing_suffix()]

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
		var display_value: String = str(value) if value != null else "N/A"
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
	phase_label.text = "PHASE: N/A"
	time_label.text = "HOUR: N/A"
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

func _on_pause_button_pressed() -> void:
	if _game == null:
		return
	_game.toggle_pause()

func _on_half_button_pressed() -> void:
	_set_speed_index(0)

func _on_one_button_pressed() -> void:
	_set_speed_index(1)

func _on_two_button_pressed() -> void:
	_set_speed_index(2)

func _on_four_button_pressed() -> void:
	_set_speed_index(3)

func _set_speed_index(index: int) -> void:
	if _game == null:
		return
	_game.set_speed_index(index)

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
	var speed_buttons: Array[Button] = [half_button, one_button, two_button, four_button]
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
