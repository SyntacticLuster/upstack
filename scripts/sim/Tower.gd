extends RefCounted
class_name Tower

var width: int
var height: int

var floors: Array[Variant] = []  # each element is a grid (an Array)
var module_states: Dictionary[String, Variant] = {}  # avoids Dictionary[String, Dictionary] inference

func _init(w: int = 6, h: int = 6) -> void:
	width = w
	height = h
	add_floor()

func add_floor() -> void:
	var grid: Array[Variant] = []
	for y in range(height):
		var row: Array[Variant] = []
		for x in range(width):
			row.append(null)
		grid.append(row)
	floors.append(grid)
func floor_count() -> int:
	return floors.size()

func _cell_key(floor_idx: int, x: int, y: int) -> String:
	return "%d:%d:%d" % [floor_idx, x, y]

func _ensure_state(floor_idx: int, x: int, y: int) -> void:
	var key := _cell_key(floor_idx, x, y)
	if module_states.has(key):
		return
	module_states[key] = {
		"enabled": true,
		"priority_override": null,
	}

func place_module(floor_idx: int, x: int, y: int, module_id: String) -> bool:
	if floor_idx < 0 or floor_idx >= floors.size():
		return false
	if x < 0 or x >= width:
		return false
	if y < 0 or y >= height:
		return false
	if floors[floor_idx][y][x] != null:
		return false

	floors[floor_idx][y][x] = module_id
	_ensure_state(floor_idx, x, y)
	return true

func has_cell(floor_idx: int, x: int, y: int) -> bool:
	if floor_idx < 0 or floor_idx >= floors.size():
		return false
	if x < 0 or x >= width:
		return false
	if y < 0 or y >= height:
		return false
	return floors[floor_idx][y][x] != null

func set_module_enabled(floor_idx: int, x: int, y: int, enabled: bool) -> bool:
	if not has_cell(floor_idx, x, y):
		return false
	_ensure_state(floor_idx, x, y)
	var key := _cell_key(floor_idx, x, y)
	module_states[key]["enabled"] = bool(enabled)
	return true

func is_module_enabled(floor_idx: int, x: int, y: int) -> bool:
	if not has_cell(floor_idx, x, y):
		return false
	_ensure_state(floor_idx, x, y)
	var key := _cell_key(floor_idx, x, y)
	return bool(module_states[key].get("enabled", true))

func set_module_priority_override(floor_idx: int, x: int, y: int, priority: int) -> bool:
	if not has_cell(floor_idx, x, y):
		return false
	_ensure_state(floor_idx, x, y)
	var key := _cell_key(floor_idx, x, y)
	module_states[key]["priority_override"] = int(priority)
	return true

func clear_module_priority_override(floor_idx: int, x: int, y: int) -> bool:
	if not has_cell(floor_idx, x, y):
		return false
	_ensure_state(floor_idx, x, y)
	var key := _cell_key(floor_idx, x, y)
	module_states[key]["priority_override"] = null
	return true

func get_module_priority_override(floor_idx: int, x: int, y: int) -> Variant:
	if not has_cell(floor_idx, x, y):
		return null
	_ensure_state(floor_idx, x, y)
	var key := _cell_key(floor_idx, x, y)
	return module_states[key].get("priority_override", null)

func _test_export_state() -> Dictionary:
	var floors_copy: Array = []
	for floor_data in floors:
		if floor_data is Array:
			floors_copy.append((floor_data as Array).duplicate(true))
		else:
			floors_copy.append([])
	return {
		"width": width,
		"height": height,
		"floors": floors_copy,
		"module_states": module_states.duplicate(true),
	}

func _test_import_state(state: Dictionary) -> void:
	var safe_width: int = int(state.get("width", width))
	var safe_height: int = int(state.get("height", height))
	width = max(safe_width, 0)
	height = max(safe_height, 0)
	var floors_value: Variant = state.get("floors", [])
	floors.clear()
	if floors_value is Array:
		for floor_entry in floors_value as Array:
			if floor_entry is Array:
				floors.append((floor_entry as Array).duplicate(true))
			else:
				floors.append([])
	module_states = state.get("module_states", {}).duplicate(true)
