extends Node
class_name Sim

signal tick(day: int)

@export var seconds_per_day: float = 1.0

var day: int = 0
var _accum: float = 0.0

var tower: Tower
var res: Resources
var db: ModuleDB

func _ready() -> void:
	db = ModuleDB.new()
	res = Resources.new()
	tower = Tower.new(6, 6)

	# Place a small starter layout
	tower.place_module(0, 2, 2, "core")
	tower.place_module(0, 2, 3, "generator")
	tower.place_module(0, 1, 2, "housing")
	tower.place_module(0, 3, 2, "purifier")
	tower.place_module(0, 2, 1, "hydro")

	print("Tower floors:", tower.floor_count())
	print("Day 0:", res.summary())

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= seconds_per_day:
		_accum -= seconds_per_day
		day += 1
		_step_day()
		emit_signal("tick", day)
		print("Day %d: %s" % [day, res.summary()])

func _step_day() -> void:
	# Phase 0: base population consumption
	res.food -= res.population
	res.water -= res.population

	# Phase 1: reset per-day accounting
	res.power_supply = 0
	res.power_used = 0

	# Phase 2: collect module instances from the tower + compute total power supply
	var instances: Array[ModuleInstance] = []
	var total_capacity: int = 0

	for f in range(tower.floors.size()):
		var grid = tower.floors[f]
		for y in range(tower.height):
			for x in range(tower.width):
				var id = grid[y][x]
				if id == null:
					continue

				var def: ModuleDef = db.get_def(id)
				if def == null:
					continue

				var inst := ModuleInstance.new(def)
				instances.append(inst)

				# Generators (and any supply) contribute regardless of priority/power availability
				res.power_supply += def.power_supply

	# Phase 3: sort by priority (lower runs first)
	instances.sort_custom(func(a: ModuleInstance, b: ModuleInstance) -> bool:
		return a.def.priority < b.def.priority
	)

	# Phase 4: allocate power + apply effects for powered modules
	var remaining_power: int = res.power_supply
	var total_noise: int = 0
	var total_heat: int = 0


	for inst in instances:
		var def := inst.def
		var needs: int = def.power_demand
		inst.powered = (needs == 0) or (remaining_power >= needs)

		if inst.powered:
			remaining_power -= needs
			res.power_used += needs

			res.food += def.delta_food
			res.water += def.delta_water
			res.materials += def.delta_materials
			res.morale += def.delta_morale
			total_capacity += def.delta_capacity
			total_noise += def.noise
			total_heat += def.heat

		else:
			# Unpowered penalty (light, for now)
			res.morale -= 1

	# Phase 5: derived pressures (housing + shortages)
	if total_capacity < res.population:
		res.morale -= 2

	if res.food <= 0:
		res.morale -= 5
	if res.water <= 0:
		res.morale -= 7

	# Phase 5b: threat growth model (placeholder, but coherent)
	# - noise/heat always add pressure
	# - higher power usage increases detectability
	var power_signature := res.power_used
	res.threat += int(total_noise * 0.5) + int(total_heat * 0.5) + int(power_signature * 0.2)

	# If morale is collapsing, people make mistakes -> more threat
	if res.morale <= 10:
		res.threat += 1

	# Phase 6: clamp to valid bounds
	res.clamp_all()
