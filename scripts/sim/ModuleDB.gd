extends RefCounted
class_name ModuleDB

var defs: Dictionary = {}

func _init() -> void:
	_load_defaults()

func _load_defaults() -> void:
	# id, name, power_supply, power_demand, priority, df, dw, dm, dmo, dcap, noise, heat
	add(_mk("core", "Core", 0, 1, 0, 0, 0, 0, +1, 0, 0, 0))
	add(_mk("generator", "Generator", 6, 0, 10, 0, 0, 0, -1, 0, 2, 2))
	add(_mk("housing", "Housing", 0, 1, 80, 0, 0, 0, -1, +5, 1, 0))
	add(_mk("purifier", "Water Purifier", 0, 2, 20, 0, +4, 0, 0, 0, 1, 0))
	add(_mk("hydro", "Hydroponics", 0, 2, 30, +4, -2, 0, 0, 0, 1, 1))
	add(_mk("workshop", "Workshop", 0, 2, 60, 0, 0, +3, 0, 0, 2, 2))

func _mk(id: String, name: String,
	ps: int, pd: int, prio: int,
	df: int, dw: int, dm: int, dmo: int, dcap: int, noise: int, heat: int) -> ModuleDef:
	var m := ModuleDef.new(id, name)
	m.power_supply = ps
	m.power_demand = pd
	m.priority = prio
	m.delta_food = df
	m.delta_water = dw
	m.delta_materials = dm
	m.delta_morale = dmo
	m.delta_capacity = dcap
	m.noise = noise
	m.heat = heat
	return m

func add(m: ModuleDef) -> void:
	defs[m.id] = m

func get_def(id: String) -> ModuleDef:
	return defs.get(id, null)
