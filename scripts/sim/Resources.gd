extends RefCounted
class_name Resources

# Core survival resources
var food: int = 20
var water: int = 20

# Industrial / stock resources
var materials: int = 50

# Social state
var morale: int = 50
var threat: int = 0

# People
var population: int = 5

# Power accounting (per-day, derived)
var power_supply: int = 0
var power_used: int = 0

func clamp_all() -> void:
	food = max(food, 0)
	water = max(water, 0)
	materials = max(materials, 0)
	morale = clamp(morale, 0, 100)
	threat = clamp(threat, 0, 999)
	population = max(population, 0)
	power_supply = max(power_supply, 0)
	power_used = max(power_used, 0)

func summary() -> String:
	return "POP=%d FOOD=%d WATER=%d MAT=%d MOR=%d PWR=%d/%d THR=%d" % [
		population, food, water, materials, morale, power_used, power_supply, threat
]
