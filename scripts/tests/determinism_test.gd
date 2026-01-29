extends Object

const SIM_SCRIPT: Script = preload("res://scripts/sim/Sim.gd")
const DAYS_TO_RUN: int = 5
const RUN_SEED: int = 1234

func _run() -> void:
	var sim := SIM_SCRIPT.new() as Sim
	sim.sim_seed = RUN_SEED
	sim._setup_default_state()

	var metrics_obs: Array[String] = []
	sim._phase_baselines(sim.res, metrics_obs)
	sim._phase_production(sim.tower, sim.res, sim.db, metrics_obs)

	var production_metrics := sim.get_last_production_metrics()
	if production_metrics.is_empty():
		push_error("Missing production metrics after phase run.")
		return

	var discrepancy := int(production_metrics.get("discrepancy", 0))
	if discrepancy != 0:
		push_error("Food accounting mismatch: discrepancy=%d" % discrepancy)
		return

	var hash_result_a := sim._simulate_state_signatures(DAYS_TO_RUN, RUN_SEED, {})
	var hash_result_b := sim._simulate_state_signatures(DAYS_TO_RUN, RUN_SEED, {})

	var hashes_a := hash_result_a.get("hashes", [])
	var hashes_b := hash_result_b.get("hashes", [])
	if hashes_a != hashes_b:
		push_error("Determinism hash mismatch: %s vs %s" % [hashes_a, hashes_b])
		return

	var rng_log_a := hash_result_a.get("rng_log", [])
	var rng_log_b := hash_result_b.get("rng_log", [])
	if not _compare_rng_logs(rng_log_a, rng_log_b):
		return

	print("determinism_test finished: days=%d seed=%d" % [DAYS_TO_RUN, RUN_SEED])

func _compare_rng_logs(log_a: Array[Dictionary], log_b: Array[Dictionary]) -> bool:
	if log_a.size() != log_b.size():
		push_error("RNG log length mismatch: %d vs %d" % [log_a.size(), log_b.size()])
		return false
	for i in range(log_a.size()):
		var entry_a := log_a[i]
		var entry_b := log_b[i]
		if int(entry_a.get("seed", 0)) != int(entry_b.get("seed", 0)) or int(entry_a.get("calls", 0)) != int(entry_b.get("calls", 0)):
			push_error("RNG log mismatch @%d (seed:%s calls:%s vs seed:%s calls:%s)" % [
				i,
				str(entry_a.get("seed", 0)),
				str(entry_a.get("calls", 0)),
				str(entry_b.get("seed", 0)),
				str(entry_b.get("calls", 0)),
			])
			return false
	return true
