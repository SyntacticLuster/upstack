extends Control

## VisualMapCanvas: Draws the expedition map using Control._draw().
## Must be a child of MapPanel.

const NODE_RADIUS := 18.0
const NODE_COLOR_DEFAULT := Color(0.3, 0.5, 0.7)
const NODE_COLOR_SELECTED := Color(0.8, 0.6, 0.2)
const NODE_COLOR_TOWER := Color(0.4, 0.7, 0.4)
const NODE_COLOR_ACTIVE := Color(0.7, 0.3, 0.3)
const EDGE_COLOR := Color(0.25, 0.35, 0.45)
const EDGE_WIDTH := 2.0
const LABEL_OFFSET := Vector2(0, -28)
const RISK_COLORS: Array[Color] = [
	Color(0.4, 0.7, 0.4),  # 0 = safe (green)
	Color(0.7, 0.7, 0.3),  # 1 = low (yellow)
	Color(0.8, 0.5, 0.2),  # 2 = medium (orange)
	Color(0.8, 0.3, 0.3),  # 3 = high (red)
]

var _parent_panel: Control = null
var _node_positions: Dictionary = {}
var _edges: Array[Dictionary] = []
var _locations: Array = []
var _selected_id: String = ""
var _active_dest_id: String = ""


func _ready() -> void:
	# Find parent MapPanel.
	var parent: Node = get_parent()
	while parent != null:
		if parent.has_method("_on_canvas_click"):
			_parent_panel = parent as Control
			break
		parent = parent.get_parent()


func set_data(locations: Array, edges: Array[Dictionary], positions: Dictionary, selected_id: String, active_dest_id: String) -> void:
	_locations = locations
	_edges = edges
	_node_positions = positions
	_selected_id = selected_id
	_active_dest_id = active_dest_id
	queue_redraw()


func _draw() -> void:
	# Draw edges first.
	for edge in _edges:
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if _node_positions.has(from_id) and _node_positions.has(to_id):
			var from_pos: Vector2 = _node_positions[from_id]
			var to_pos: Vector2 = _node_positions[to_id]
			draw_line(from_pos, to_pos, EDGE_COLOR, EDGE_WIDTH)

	# Draw nodes.
	for loc_id in _node_positions.keys():
		var pos: Vector2 = _node_positions[loc_id]
		var color := NODE_COLOR_DEFAULT

		if loc_id == "tower":
			color = NODE_COLOR_TOWER
		elif loc_id == _selected_id:
			color = NODE_COLOR_SELECTED
		elif loc_id == _active_dest_id:
			color = NODE_COLOR_ACTIVE

		draw_circle(pos, NODE_RADIUS, color)

		# Risk indicator ring.
		var loc := _find_location(loc_id)
		if not loc.is_empty():
			var risk := int(loc.get("risk_level", 0))
			if risk > 0 and risk < RISK_COLORS.size():
				draw_arc(pos, NODE_RADIUS + 3, 0, TAU, 32, RISK_COLORS[risk], 2.0)

		# Label.
		var label_text: String = str(loc_id).capitalize()
		if not loc.is_empty():
			label_text = str(loc.get("name", loc_id))
		# Truncate long names.
		if label_text.length() > 20:
			label_text = label_text.substr(0, 17) + "..."

		var font: Font = get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := pos + LABEL_OFFSET - Vector2(text_size.x / 2, 0)
		draw_string(font, text_pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)


func _find_location(location_id: String) -> Dictionary:
	for loc in _locations:
		if loc is Dictionary and str(loc.get("id", "")) == location_id:
			return loc
	return {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var click_pos: Vector2 = event.position
			var hit_id := _hit_test_node(click_pos)
			if _parent_panel != null and _parent_panel.has_method("_on_canvas_click"):
				_parent_panel._on_canvas_click(hit_id)


func _hit_test_node(pos: Vector2) -> String:
	for loc_id in _node_positions.keys():
		var node_pos: Vector2 = _node_positions[loc_id]
		if pos.distance_to(node_pos) <= NODE_RADIUS + 5:
			return loc_id
	return ""
