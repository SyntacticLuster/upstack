extends RefCounted
class_name Tower

var width: int
var height: int
var floors: Array = []

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
	return true
