extends RefCounted
class_name ModuleInstance

var def: ModuleDef
var powered: bool = false
var power_required: int = 0
var power_allocated: int = 0
var order_index: int = 0
var priority: int = 50
var floor: int = 0
var x: int = 0
var y: int = 0

func _init(_def: ModuleDef) -> void:
	def = _def
	priority = def.priority

func compute_resource_deltas(_resources: Resources) -> Dictionary:
	var deltas: Dictionary = {}
	if power_required > 0 and power_allocated < power_required:
		return deltas

	deltas["food"] = def.delta_food
	deltas["water"] = def.delta_water
	deltas["materials"] = def.delta_materials
	deltas["morale"] = def.delta_morale
	return deltas
