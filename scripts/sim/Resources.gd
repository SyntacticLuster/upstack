extends RefCounted
class_name Resources

# Core survival resources
var food: int = 20
var water: int = 20

# Survival pressure tracking (deterministic, no RNG)
var days_without_food: int = 0
var days_without_water: int = 0

# Industrial / stock resources
var materials: int = 50

# Social state
var morale: int = 50
var threat: int = 0
var morale_ceiling: float = 100.0
var staying_index: float = 0.0
var attention_multiplier: float = 1.0
var collapse_debt: float = 0.0
var strain: float = 0.0

# People
var population: int = 5

# Power accounting (per-day, derived)
var power_supply: int = 0
var power_used: int = 0

const _RESOURCE_KEYS: Array[String] = [
	"food",
	"water",
	"materials",
	"morale",
	"threat",
	"population",
	"power_supply",
	"power_used",
]

var _deltas: Dictionary = {}

func clamp_all() -> void:
	food = max(food, 0)
	water = max(water, 0)
	materials = max(materials, 0)
	morale_ceiling = clamp(morale_ceiling, 0.0, 100.0)
	var morale_cap: int = int(floor(morale_ceiling))
	morale = clamp(morale, 0, morale_cap)
	threat = clamp(threat, 0, 999)
	population = max(population, 0)
	power_supply = max(power_supply, 0)
	power_used = max(power_used, 0)
	collapse_debt = max(collapse_debt, 0.0)
	strain = clamp(strain, 0.0, 100.0)
	attention_multiplier = max(attention_multiplier, 0.0)

func reset_deltas() -> void:
	_deltas.clear()
	for key in _RESOURCE_KEYS:
		_deltas[key] = 0

func add_delta(key: String, amount: int) -> void:
	if key not in _RESOURCE_KEYS:
		push_error("Unknown resource key in add_delta: %s" % key)
		return
	_deltas[key] = int(_deltas.get(key, 0)) + amount

func get_amount(key: String) -> int:
	match key:
		"food":
			return food
		"water":
			return water
		"materials":
			return materials
		"morale":
			return morale
		"threat":
			return threat
		"population":
			return population
		"power_supply":
			return power_supply
		"power_used":
			return power_used
		_:
			push_error("Unknown resource key in get_amount: %s" % key)
			return 0

func set_amount(key: String, value: int) -> void:
	var normalized: int = int(value)
	match key:
		"food":
			food = normalized
		"water":
			water = normalized
		"materials":
			materials = normalized
		"morale":
			morale = normalized
		"threat":
			threat = normalized
		"population":
			population = normalized
		"power_supply":
			power_supply = normalized
		"power_used":
			power_used = normalized
		_:
			push_error("Unknown resource key in set_amount: %s" % key)

func apply_deltas() -> void:
	for key in _RESOURCE_KEYS:
		var delta: int = int(_deltas.get(key, 0))
		if delta == 0:
			continue
		var current_value: int = get_amount(key)
		set_amount(key, current_value + delta)

func snapshot() -> String:
	var parts: Array[String] = []
	for key in _RESOURCE_KEYS:
		parts.append("%s=%s" % [key, str(get_amount(key))])
	return ",".join(parts)

func summary() -> String:
	return "POP=%d FOOD=%d WATER=%d MAT=%d MOR=%d PWR=%d/%d THR=%d" % [
		population, food, water, materials, morale, power_used, power_supply, threat
]
