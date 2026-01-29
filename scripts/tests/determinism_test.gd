extends Object

const DAYS_TO_RUN: int = 5
const RUN_SEED: int = 1234

func _run() -> void:
	var sim: Sim = Sim.new()
	sim.sim_seed = RUN_SEED
	sim._setup_default_state()

	sim.day = 1
	sim.hour_of_day = 0
	sim._begin_day(sim.day)
	sim.hour_index = sim.day * sim.HOURS_PER_DAY + sim.scheduled_production_hour
	sim.hour_of_day = sim.scheduled_production_hour
	sim._step_day_core(sim.day, RUN_SEED, sim.tower, sim.res, sim.db)
	sim.production_executed_today = true

	var production_metrics: Dictionary = sim.get_last_production_metrics()
	if production_metrics.is_empty():
		push_error("Missing production metrics after phase run.")
		return

	var discrepancy := int(production_metrics.get("discrepancy", 0))
	if discrepancy != 0:
		push_error("Food accounting mismatch: discrepancy=%d" % discrepancy)
		return

	var hash_result_a: Dictionary = sim._simulate_state_signatures(DAYS_TO_RUN, RUN_SEED, {})
	var hash_result_b: Dictionary = sim._simulate_state_signatures(DAYS_TO_RUN, RUN_SEED, {})

	var hashes_a: Array = hash_result_a.get("hashes", [])
	var hashes_b: Array = hash_result_b.get("hashes", [])
	if hashes_a != hashes_b:
		push_error("Determinism hash mismatch: %s vs %s" % [hashes_a, hashes_b])
		return

	var rng_log_a: Array = hash_result_a.get("rng_log", [])
	var rng_log_b: Array = hash_result_b.get("rng_log", [])
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
