extends PanelContainer

## MapPanel: Shows expedition destinations and allows launching expeditions.
## Supports two modes:
##   - List mode: A simple list of destinations with launch buttons.
##   - Visual mode: A node-graph style map using Control._draw().

signal expedition_requested(destination_id: String, crew: int)

enum MapMode {
	LIST,
	VISUAL,
}

const RISK_COLORS: Array[Color] = [
	Color(0.4, 0.7, 0.4),  # 0 = safe (green)
	Color(0.7, 0.7, 0.3),  # 1 = low (yellow)
	Color(0.8, 0.5, 0.2),  # 2 = medium (orange)
	Color(0.8, 0.3, 0.3),  # 3 = high (red)
]

@onready var mode_toggle: Button = $Root/Header/ModeToggle
@onready var status_label: Label = $Root/Header/StatusLabel
@onready var list_container: ScrollContainer = $Root/ListContainer
@onready var list_items: VBoxContainer = $Root/ListContainer/ListItems
@onready var visual_container: Control = $Root/VisualContainer
@onready var visual_canvas: Control = $Root/VisualContainer/VisualCanvas
@onready var launch_panel: PanelContainer = $Root/LaunchPanel
@onready var launch_dest_label: Label = $Root/LaunchPanel/LaunchContent/DestLabel
@onready var launch_crew_spin: SpinBox = $Root/LaunchPanel/LaunchContent/CrewRow/CrewSpin
@onready var launch_button: Button = $Root/LaunchPanel/LaunchContent/LaunchButton
@onready var cancel_button: Button = $Root/LaunchPanel/LaunchContent/CancelButton

var _sim: Object = null
var _current_mode: MapMode = MapMode.LIST
var _locations: Array = []
var _edges: Array[Dictionary] = []
var _selected_destination_id: String = ""
var _node_positions: Dictionary = {}  # destination_id -> Vector2 (screen coords)

func _ready() -> void:
	mode_toggle.pressed.connect(_on_mode_toggle)
	launch_button.pressed.connect(_on_launch_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	_apply_mode()
	_clear_selection()

func set_sim(sim_ref: Object) -> void:
	_sim = sim_ref
	refresh()

func refresh() -> void:
	_load_map_data()
	_update_status()
	if _current_mode == MapMode.LIST:
		_rebuild_list()
	else:
		_rebuild_visual()

func _load_map_data() -> void:
	_locations.clear()
	_edges.clear()
	if _sim == null:
		return
	if _sim.has_method("get_map_locations"):
		var locs: Variant = _sim.get_map_locations()
		if locs is Array:
			_locations = locs
	if _sim.has_method("get_map_edges"):
		var edgs: Variant = _sim.get_map_edges()
		if edgs is Array:
			for edge in edgs:
				if edge is Dictionary:
					_edges.append(edge)

func _update_status() -> void:
	if _sim == null:
		status_label.text = "MAP: DISCONNECTED"
		return
	if _sim.has_method("has_active_expedition"):
		if _sim.has_active_expedition():
			var expedition: Dictionary = _sim.get_active_expedition()
			var dest_name: String = str(expedition.get("destination_name", "unknown"))
			var state: String = str(expedition.get("state", "UNKNOWN"))
			status_label.text = "EXPEDITION: %s (%s)" % [dest_name, state]
			return
	status_label.text = "MAP: READY"

func _apply_mode() -> void:
	if _current_mode == MapMode.LIST:
		list_container.visible = true
		visual_container.visible = false
		mode_toggle.text = "VISUAL"
		_rebuild_list()
	else:
		list_container.visible = false
		visual_container.visible = true
		mode_toggle.text = "LIST"
		_rebuild_visual()

func _on_mode_toggle() -> void:
	if _current_mode == MapMode.LIST:
		_current_mode = MapMode.VISUAL
	else:
		_current_mode = MapMode.LIST
	_apply_mode()

func _rebuild_list() -> void:
	# Clear existing items.
	for child in list_items.get_children():
		child.queue_free()

	if _locations.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No destinations available."
		list_items.add_child(empty_label)
		return

	for loc in _locations:
		if not (loc is Dictionary):
			continue
		var loc_id: String = str(loc.get("id", ""))
		if loc_id == "tower":
			continue
		var row := _create_list_row(loc)
		list_items.add_child(row)

func _create_list_row(loc: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = str(loc.get("name", "Unknown"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var dist_label := Label.new()
	var dist_hours := int(loc.get("distance_hours", 0))
	var onsite_hours := int(loc.get("onsite_hours", 0))
	var total := (dist_hours * 2) + onsite_hours
	dist_label.text = "%dh trip" % total
	dist_label.custom_minimum_size.x = 60
	row.add_child(dist_label)

	var risk_label := Label.new()
	var risk := int(loc.get("risk_level", 0))
	var risk_names := ["Safe", "Low", "Med", "High"]
	risk_label.text = risk_names[clamp(risk, 0, 3)]
	if risk < RISK_COLORS.size():
		risk_label.add_theme_color_override("font_color", RISK_COLORS[risk])
	risk_label.custom_minimum_size.x = 40
	row.add_child(risk_label)

	var select_btn := Button.new()
	select_btn.text = "SELECT"
	select_btn.pressed.connect(_on_location_selected.bind(str(loc.get("id", ""))))
	row.add_child(select_btn)

	return row

func _on_location_selected(destination_id: String) -> void:
	_selected_destination_id = destination_id
	_show_launch_panel()

func _show_launch_panel() -> void:
	if _selected_destination_id == "":
		launch_panel.visible = false
		return

	var loc := _find_location(_selected_destination_id)
	if loc.is_empty():
		launch_panel.visible = false
		return

	launch_dest_label.text = "Destination: %s" % str(loc.get("name", "Unknown"))

	var max_crew := 6
	if _sim != null:
		var res: Object = _sim.get("res")
		if res != null and res.has_method("get_amount"):
			max_crew = int(res.get_amount("population"))
		elif res != null:
			max_crew = int(res.get("population"))

	launch_crew_spin.min_value = 1
	launch_crew_spin.max_value = max(max_crew, 1)
	launch_crew_spin.value = min(2, max_crew)

	launch_panel.visible = true

func _find_location(destination_id: String) -> Dictionary:
	for loc in _locations:
		if loc is Dictionary and str(loc.get("id", "")) == destination_id:
			return loc
	return {}

func _on_launch_pressed() -> void:
	if _selected_destination_id == "":
		return

	var crew := int(launch_crew_spin.value)
	expedition_requested.emit(_selected_destination_id, crew)

	# Also try to call sim directly.
	if _sim != null and _sim.has_method("launch_expedition"):
		var result: Dictionary = _sim.launch_expedition(_selected_destination_id, crew)
		print("launch_expedition result: ", result)

	_clear_selection()
	refresh()

func _on_cancel_pressed() -> void:
	_clear_selection()

func _clear_selection() -> void:
	_selected_destination_id = ""
	launch_panel.visible = false
	if visual_canvas != null:
		visual_canvas.queue_redraw()

# =============================================================================
# Visual Mode
# =============================================================================

func _rebuild_visual() -> void:
	_compute_node_positions()
	_update_canvas_data()

func _compute_node_positions() -> void:
	_node_positions.clear()
	if visual_canvas == null:
		return

	var canvas_size := visual_canvas.size
	if canvas_size.x < 10 or canvas_size.y < 10:
		canvas_size = Vector2(400, 300)

	var margin := 40.0

	# Tower is always included.
	_node_positions["tower"] = Vector2(
		margin + (0.5 * (canvas_size.x - 2 * margin)),
		margin + (0.4 * (canvas_size.y - 2 * margin))
	)

	for loc in _locations:
		if not (loc is Dictionary):
			continue
		var loc_id: String = str(loc.get("id", ""))
		var pos_data: Variant = loc.get("position", {})
		var norm_pos := Vector2(0.5, 0.5)
		if pos_data is Dictionary:
			norm_pos.x = float(pos_data.get("x", 0.5))
			norm_pos.y = float(pos_data.get("y", 0.5))
		elif pos_data is Vector2:
			norm_pos = pos_data

		var screen_pos := Vector2(
			margin + (norm_pos.x * (canvas_size.x - 2 * margin)),
			margin + (norm_pos.y * (canvas_size.y - 2 * margin))
		)
		_node_positions[loc_id] = screen_pos

func _update_canvas_data() -> void:
	if visual_canvas == null:
		return
	var active_dest := ""
	if _sim != null and _sim.has_method("get_active_expedition"):
		var expedition: Dictionary = _sim.get_active_expedition()
		active_dest = str(expedition.get("destination_id", ""))
	if visual_canvas.has_method("set_data"):
		visual_canvas.set_data(_locations, _edges, _node_positions, _selected_destination_id, active_dest)
	else:
		visual_canvas.queue_redraw()

func _on_canvas_click(hit_id: String) -> void:
	## Called by VisualMapCanvas when user clicks.
	if hit_id != "" and hit_id != "tower":
		_selected_destination_id = hit_id
		_show_launch_panel()
		_update_canvas_data()
	elif hit_id == "":
		_clear_selection()
