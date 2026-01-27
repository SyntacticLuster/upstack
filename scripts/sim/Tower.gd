extends RefCounted
class_name Tower

var width: int
var height: int
var floors: Array = []
var module_states: Dictionary = {}

func _init(w: int = 6, h: int = 6) -> void:
	width = w
	height = h
	add_floor()

func add_floor() -> void:
	var grid := []
	for y in range(height):
		var row := []
		for x in range(width):
			row.append(null)
		grid.append(row)
	floors.append(grid)

func floor_count() -> int:
	return floors.size()

func _cell_key(floor: int, x: int, y: int) -> String:
	return "%d:%d:%d" % [floor, x, y]

func _ensure_state(floor: int, x: int, y: int) -> void:
	var key := _cell_key(floor, x, y)
	if module_states.has(key):
		return
	module_states[key] = {
		"enabled": true,
		"priority_override": null,
	}

func place_module(floor: int, x: int, y: int, module_id: String) -> bool:
	if floor < 0 or floor >= floors.size():
		return false
	if x < 0 or x >= width:
		return false
	if y < 0 or y >= height:
		return false
	if floors[floor][y][x] != null:
		return false

	floors[floor][y][x] = module_id
	_ensure_state(floor, x, y)
	return true

func has_cell(floor: int, x: int, y: int) -> bool:
	if floor < 0 or floor >= floors.size():
		return false
	if x < 0 or x >= width:
		return false
	if y < 0 or y >= height:
		return false
	return floors[floor][y][x] != null

func set_module_enabled(floor: int, x: int, y: int, enabled: bool) -> bool:
	if not has_cell(floor, x, y):
		return false
	_ensure_state(floor, x, y)
	var key := _cell_key(floor, x, y)
	module_states[key]["enabled"] = bool(enabled)
	return true

func is_module_enabled(floor: int, x: int, y: int) -> bool:
	if not has_cell(floor, x, y):
		return false
	_ensure_state(floor, x, y)
	var key := _cell_key(floor, x, y)
	return bool(module_states[key].get("enabled", true))

func set_module_priority_override(floor: int, x: int, y: int, priority: int) -> bool:
	if not has_cell(floor, x, y):
		return false
	_ensure_state(floor, x, y)
	var key := _cell_key(floor, x, y)
	module_states[key]["priority_override"] = int(priority)
	return true

func clear_module_priority_override(floor: int, x: int, y: int) -> bool:
	if not has_cell(floor, x, y):
		return false
	_ensure_state(floor, x, y)
	var key := _cell_key(floor, x, y)
	module_states[key]["priority_override"] = null
	return true

func get_module_priority_override(floor: int, x: int, y: int) -> Variant:
	if not has_cell(floor, x, y):
		return null
	_ensure_state(floor, x, y)
	var key := _cell_key(floor, x, y)
	return module_states[key].get("priority_override", null)
