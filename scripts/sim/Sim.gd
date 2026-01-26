extends Node
class_name Sim

signal tick(day: int)

@export var seconds_per_day: float = 1.0

var day: int = 0
var _accum: float = 0.0
var sim_seed: int = 0

var tower: Tower
var res: Resources
var db: ModuleDB

func _ready() -> void:
	_setup_default_state()
	debug_run_determinism(10, 12345)

	print("Tower floors:", tower.floor_count())
	print("Day 0:", res.summary())
	
	get_tree().quit()

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= seconds_per_day:
		_accum -= seconds_per_day
		day += 1
		_step_day()
		emit_signal("tick", day)
		print(_format_log_line(day, sim_seed, res))

func _step_day() -> void:
	# Phase 0: reset per-day accounting
	res.reset_deltas()
	res.power_supply = 0
	res.power_used = 0

	# Phase 1: base population consumption
	res.add_delta("food", -res.population)
	res.add_delta("water", -res.population)

	# Phase 2: collect module instances from the tower + compute total power supply
	var instances: Array[ModuleInstance] = []
	var total_capacity: int = 0
	var order_index: int = 0

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
				inst.order_index = order_index
				order_index += 1
				instances.append(inst)

				# Generators (and any supply) contribute regardless of priority/power availability
				res.power_supply += def.power_supply

	# Phase 3: sort deterministically by priority, id/name, and placement order
	instances.sort_custom(func(a: ModuleInstance, b: ModuleInstance) -> bool:
		if a.def.priority != b.def.priority:
			return a.def.priority < b.def.priority
		if a.def.id != b.def.id:
			return a.def.id < b.def.id
		if a.def.name != b.def.name:
			return a.def.name < b.def.name
		return a.order_index < b.order_index
	)

	# Phase 4: allocate power + apply effects for powered modules
	var remaining_power: int = res.power_supply
	var total_noise: int = 0
	var total_heat: int = 0


	for inst in instances:
		var def := inst.def
		var needs: int = def.power_demand
		inst.power_required = needs
		inst.powered = (needs == 0) or (remaining_power >= needs)
		inst.power_allocated = needs if inst.powered else 0

		if inst.powered:
			remaining_power -= needs
			res.power_used += needs
			var deltas := inst.compute_resource_deltas(res)
			for key in deltas.keys():
				res.add_delta(key, int(deltas[key]))
			total_capacity += def.delta_capacity
			total_noise += def.noise
			total_heat += def.heat

		else:
			# Unpowered penalty (light, for now)
			res.add_delta("morale", -1)

	# Phase 4b: apply accumulated deltas in stable order
	res.apply_deltas()

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

func _setup_default_state() -> void:
	db = ModuleDB.new()
	res = Resources.new()
	tower = Tower.new(6, 6)

	# Place a small starter layout
	tower.place_module(0, 2, 2, "core")
	tower.place_module(0, 2, 3, "generator")
	tower.place_module(0, 1, 2, "housing")
	tower.place_module(0, 3, 2, "purifier")
	tower.place_module(0, 2, 1, "hydro")

func _format_log_line(_day: int, _seed: int, _res: Resources) -> String:
	return "SIM day=%d seed=%d pwr=%d/%d thr=%d RES{%s}" % [
		_day,
		_seed,
		_res.power_used,
		_res.power_supply,
		_res.threat,
		_res.snapshot(),
	]

func _simulate_days(days_to_run: int, seed: int) -> Array[String]:
	var sim_res := Resources.new()
	var sim_tower := Tower.new(6, 6)
	var sim_db := ModuleDB.new()
	var sim_day: int = 0
	var output: Array[String] = []

	sim_tower.place_module(0, 2, 2, "core")
	sim_tower.place_module(0, 2, 3, "generator")
	sim_tower.place_module(0, 1, 2, "housing")
	sim_tower.place_module(0, 3, 2, "purifier")
	sim_tower.place_module(0, 2, 1, "hydro")

	for i in range(days_to_run):
		sim_day += 1
		_step_day_for(sim_tower, sim_res, sim_db)
		output.append(_format_log_line(sim_day, seed, sim_res))
	return output

func _step_day_for(sim_tower: Tower, sim_res: Resources, sim_db: ModuleDB) -> void:
	sim_res.reset_deltas()
	sim_res.power_supply = 0
	sim_res.power_used = 0

	sim_res.add_delta("food", -sim_res.population)
	sim_res.add_delta("water", -sim_res.population)

	var instances: Array[ModuleInstance] = []
	var total_capacity: int = 0
	var order_index: int = 0

	for f in range(sim_tower.floors.size()):
		var grid = sim_tower.floors[f]
		for y in range(sim_tower.height):
			for x in range(sim_tower.width):
				var id = grid[y][x]
				if id == null:
					continue

				var def: ModuleDef = sim_db.get_def(id)
				if def == null:
					continue

				var inst := ModuleInstance.new(def)
				inst.order_index = order_index
				order_index += 1
				instances.append(inst)
				sim_res.power_supply += def.power_supply

	instances.sort_custom(func(a: ModuleInstance, b: ModuleInstance) -> bool:
		if a.def.priority != b.def.priority:
			return a.def.priority < b.def.priority
		if a.def.id != b.def.id:
			return a.def.id < b.def.id
		if a.def.name != b.def.name:
			return a.def.name < b.def.name
		return a.order_index < b.order_index
	)

	var remaining_power: int = sim_res.power_supply
	var total_noise: int = 0
	var total_heat: int = 0

	for inst in instances:
		var def := inst.def
		var needs: int = def.power_demand
		inst.power_required = needs
		inst.powered = (needs == 0) or (remaining_power >= needs)
		inst.power_allocated = needs if inst.powered else 0

		if inst.powered:
			remaining_power -= needs
			sim_res.power_used += needs
			var deltas := inst.compute_resource_deltas(sim_res)
			for key in deltas.keys():
				sim_res.add_delta(key, int(deltas[key]))
			total_capacity += def.delta_capacity
			total_noise += def.noise
			total_heat += def.heat
		else:
			sim_res.add_delta("morale", -1)

	sim_res.apply_deltas()

	if total_capacity < sim_res.population:
		sim_res.morale -= 2

	if sim_res.food <= 0:
		sim_res.morale -= 5
	if sim_res.water <= 0:
		sim_res.morale -= 7

	var power_signature := sim_res.power_used
	sim_res.threat += int(total_noise * 0.5) + int(total_heat * 0.5) + int(power_signature * 0.2)

	if sim_res.morale <= 10:
		sim_res.threat += 1

	sim_res.clamp_all()

func debug_run_determinism(days_to_run: int, seed: int) -> void:
	var run_a := _simulate_days(days_to_run, seed)
	var run_b := _simulate_days(days_to_run, seed)

	for line in run_a:
		print(line)
	for line in run_b:
		print(line)

	if run_a.size() != run_b.size():
		print("DETERMINISM MISMATCH size=%d/%d" % [run_a.size(), run_b.size()])
		return

	for i in range(run_a.size()):
		if run_a[i] != run_b[i]:
			print("DETERMINISM MISMATCH day=%d" % [i + 1])
			return
