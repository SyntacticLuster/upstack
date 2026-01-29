extends Object

const SIM_SCRIPT: Script = preload("res://scripts/sim/Sim.gd")
const DAYS_TO_RUN: int = 3
const RUN_SEED: int = 1

func _run() -> void:
	var sim: Sim = SIM_SCRIPT.new() as Sim
	sim.sim_seed = RUN_SEED
	sim.debug_run_days(DAYS_TO_RUN, RUN_SEED)
	print("debug_run_days finished: days=%d seed=%d" % [DAYS_TO_RUN, RUN_SEED])
