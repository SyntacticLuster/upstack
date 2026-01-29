extends RefCounted
class_name ModuleDef

var id: String
var name: String

# Per-day effects (applied only if module is "active")
var delta_food: int = 0
var delta_water: int = 0
var delta_materials: int = 0
var delta_morale: int = 0
var delta_capacity: int = 0

# Inputs consumed each day by modules that need resources to operate
var inputs_per_day: Dictionary = {}

# Power model
var power_supply: int = 0   # generates
var power_demand: int = 0   # consumes
var priority: int = 50      # lower = more important (0..100)

# Pressure signals (future)
var noise: int = 0
var heat: int = 0

func _init(_id: String, _name: String) -> void:
	id = _id
	name = _name
