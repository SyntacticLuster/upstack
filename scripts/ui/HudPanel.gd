extends PanelContainer

@onready var day_label: Label = $VBox/RowTop/DayValue
@onready var phase_label: Label = $VBox/RowTop/PhaseValue
@onready var time_label: Label = $VBox/RowTop/TimeValue
@onready var stats_container: VBoxContainer = $VBox/Stats

var _sim_bridge: SimBridge = null
var _stat_rows: Array[Dictionary] = []

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

func refresh() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		_set_disconnected()
		return
	_day_phase_time()
	_update_stats()

func _ready() -> void:
	_build_stat_rows()

func _set_disconnected() -> void:
	day_label.text = "Day: N/A"
	phase_label.text = "Phase: N/A"
	time_label.text = "Time: N/A"
	for row in _stat_rows:
		var value_label: Label = row.get("value")
		if value_label != null:
			value_label.text = "N/A"

func _day_phase_time() -> void:
	var day_val: int = _sim_bridge.get_day()
	var day_text := "N/A"
	if _sim_bridge.has_day_value():
		day_text = str(day_val)
	day_label.text = "Day: %s" % day_text

	var phase_val: String = _sim_bridge.get_phase()
	var phase_text := "N/A"
	if _sim_bridge.has_phase_value():
		phase_text = phase_val
	phase_label.text = "Phase: %s" % phase_text

	var time_val: String = _sim_bridge.get_time()
	var time_text := "N/A"
	if _sim_bridge.has_time_value():
		time_text = time_val
	time_label.text = "Time: %s" % time_text

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
