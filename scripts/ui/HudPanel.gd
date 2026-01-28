extends PanelContainer

@onready var day_label: Label = $VBox/RowTop/DayValue
@onready var phase_label: Label = $VBox/RowTop/PhaseValue
@onready var time_label: Label = $VBox/RowTop/TimeValue
@onready var stats_container: VBoxContainer = $VBox/Stats
@onready var pause_button: Button = $VBox/TimeControls/PauseButton
@onready var half_button: Button = $VBox/TimeControls/HalfButton
@onready var one_button: Button = $VBox/TimeControls/OneButton
@onready var two_button: Button = $VBox/TimeControls/TwoButton
@onready var four_button: Button = $VBox/TimeControls/FourButton

var _sim_bridge: SimBridge = null
var _stat_rows: Array[Dictionary] = []
var _game: Game = null
var _pacing_state_callback: Callable = Callable(self, "_on_game_pacing_state_changed")

const STAT_MAP: Array[Dictionary] = [
	{"label": "Food", "path": ["res", "food"]},
	{"label": "Water", "path": ["res", "water"]},
	{"label": "Materials", "path": ["res", "materials"]},
	{"label": "Morale", "path": ["res", "morale"]},
	{"label": "Threat", "path": ["res", "threat"]},
	{"label": "Population", "path": ["res", "population"]},
]

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

func _ready() -> void:
	_build_stat_rows()
	pause_button.pressed.connect(_on_pause_button_pressed)
	half_button.pressed.connect(_on_half_button_pressed)
	one_button.pressed.connect(_on_one_button_pressed)
	two_button.pressed.connect(_on_two_button_pressed)
	four_button.pressed.connect(_on_four_button_pressed)
	_refresh_pacing_controls()

func _set_disconnected() -> void:
	day_label.text = "Day: N/A"
	phase_label.text = "Phase: N/A"
	time_label.text = "Time: N/A"
	for row in _stat_rows:
		var value_label: Label = row.get("value")
		if value_label != null:
			value_label.text = "N/A"

func _day_phase_time() -> void:
	var day_val: int = _sim_bridge.get_day_index()
	var day_text := "N/A"
	if _sim_bridge.has_day_value():
		day_text = str(day_val)
	day_label.text = "Day: %s" % day_text

	var phase_val: String = _sim_bridge.get_phase()
	var phase_text := "N/A"
	if _sim_bridge.has_phase_value():
		phase_text = phase_val
	phase_label.text = "Phase: %s" % phase_text

	var hour_text := "N/A"
	if _sim_bridge.has_sim():
		hour_text = "%02d" % _sim_bridge.get_hour_of_day()
	time_label.text = "Hour: %s%s" % [hour_text, _pacing_suffix()]

func _build_stat_rows() -> void:
	_stat_rows.clear()
	for mapping in STAT_MAP:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = "%s:" % [str(mapping.get("label", "Stat"))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := Label.new()
		value.text = "N/A"
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(value)
		stats_container.add_child(row)
		_stat_rows.append({"map": mapping, "value": value})

func _update_stats() -> void:
	for row in _stat_rows:
		var mapping: Dictionary = row.get("map", {})
		var value_label: Label = row.get("value")
		if value_label == null:
			continue
		var value: Variant = _read_path(mapping.get("path", []))
		value_label.text = str(value) if value != null else "N/A"

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

func _pacing_suffix() -> String:
	if _game == null:
		return ""
	if not _game.has_method("get_pacing_label"):
		return ""
	var label := str(_game.get_pacing_label())
	if label == "":
		return ""
	return " (%s)" % label

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
	pause_button.text = "▶" if paused else "⏸"
	pause_button.disabled = not has_game
	var speed_buttons: Array[Button] = [half_button, one_button, two_button, four_button]
	for idx in range(speed_buttons.size()):
		var button: Button = speed_buttons[idx]
		button.disabled = not has_game or idx == active_index
