extends RefCounted
class_name Resources

# Currency representation (troy ounces in milli-units for determinism).
const CURRENCY_SUBUNITS_PER_OZT: int = 1000
const CURRENCY_DISPLAY_DECIMALS: int = 3

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

# Currency holdings (milli-ozt internal units)
var silver: int = 0
var gold: int = 0

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
	"silver",
	"gold",
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
	silver = max(silver, 0)
	gold = max(gold, 0)
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
		"silver":
			return silver
		"gold":
			return gold
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
		"silver":
			silver = normalized
		"gold":
			gold = normalized
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
	var parts: Array[String] = [
		"POP=%d" % population,
		"FOOD=%d" % food,
		"WATER=%d" % water,
		"MAT=%d" % materials,
		"MOR=%d" % morale,
		"PWR=%d/%d" % [power_used, power_supply],
		"THR=%d" % threat,
		"SILVER=%s" % format_currency(silver),
		"GOLD=%s" % format_currency(gold),
	]
	return " ".join(parts)

static func format_currency(value: int) -> String:
	var prefix := "-" if value < 0 else ""
	var absolute = abs(value)
	var whole = absolute / CURRENCY_SUBUNITS_PER_OZT
	var fraction = absolute % CURRENCY_SUBUNITS_PER_OZT
	var fraction_text := str(fraction)
	while fraction_text.length() < CURRENCY_DISPLAY_DECIMALS:
		fraction_text = "0" + fraction_text
	return "%s%d.%s" % [prefix, whole, fraction_text]

func _test_export_state() -> Dictionary:
	return {
		"food": food,
		"water": water,
		"days_without_food": days_without_food,
		"days_without_water": days_without_water,
		"materials": materials,
		"morale": morale,
		"threat": threat,
		"morale_ceiling": morale_ceiling,
		"staying_index": staying_index,
		"attention_multiplier": attention_multiplier,
		"collapse_debt": collapse_debt,
		"strain": strain,
		"population": population,
		"silver": silver,
		"gold": gold,
		"power_supply": power_supply,
		"power_used": power_used,
		"_deltas": _deltas.duplicate(true),
	}

func _test_import_state(state: Dictionary) -> void:
	food = int(state.get("food", food))
	water = int(state.get("water", water))
	days_without_food = int(state.get("days_without_food", days_without_food))
	days_without_water = int(state.get("days_without_water", days_without_water))
	materials = int(state.get("materials", materials))
	morale = int(state.get("morale", morale))
	threat = int(state.get("threat", threat))
	morale_ceiling = float(state.get("morale_ceiling", morale_ceiling))
	staying_index = float(state.get("staying_index", staying_index))
	attention_multiplier = float(state.get("attention_multiplier", attention_multiplier))
	collapse_debt = float(state.get("collapse_debt", collapse_debt))
	strain = float(state.get("strain", strain))
	population = int(state.get("population", population))
	silver = int(state.get("silver", silver))
	gold = int(state.get("gold", gold))
	power_supply = int(state.get("power_supply", power_supply))
	power_used = int(state.get("power_used", power_used))
	_deltas = state.get("_deltas", {}).duplicate(true)
