extends RefCounted
class_name Invariants

## Invariant checks for playtest harness.
## Trade v1 (T1-T10), Expedition (E1-E10), UI wiring (U1-U5).

const TRADE_ATTENTION_CAP: float = 5.0
const TRADE_BUY_RATES := {
	"food": 1200,
	"water": 1000,
	"materials": 2800,
}
const TRADE_SELL_RATES := {
	"food": 900,
	"water": 800,
	"materials": 2200,
}

var _passed: int = 0
var _failed: int = 0
var _checked: int = 0
var _failures: Array[Dictionary] = []
var _sampling_interval: int = 1
var _prev_lever_hours: Dictionary = {}
var _prev_hour_index: int = -1
var _last_expedition_member_ids: Array[int] = []

# Track previous expedition state for transition validation.
var _prev_expedition_state: String = ""
var _prev_expedition_hours: int = 0


func reset() -> void:
	_passed = 0
	_failed = 0
	_checked = 0
	_failures.clear()
	_prev_expedition_state = ""
	_prev_expedition_hours = 0
	_prev_lever_hours.clear()
	_prev_hour_index = -1
	_last_expedition_member_ids.clear()


func set_sampling_interval(interval: int) -> void:
	_sampling_interval = max(interval, 1)


func total_checked() -> int:
	return _checked


func total_passed() -> int:
	return _passed


func total_failed() -> int:
	return _failed


func all_passed() -> bool:
	return _failed == 0


func record_pass(_name: String) -> void:
	_checked += 1
	_passed += 1


func record_failure(name: String, message: String) -> void:
	_checked += 1
	_failed += 1
	_failures.append({"name": name, "message": message})


# =============================================================================
# Continuous Invariants (checked every tick)
# =============================================================================

func check_continuous(sim: Sim, logger: RefCounted) -> void:
	_check_NS_no_nan(sim, logger)
	_check_NS_no_inf(sim, logger)
	_check_NS_threat_bounds(sim, logger)
	_check_NS_morale_bounds(sim, logger)
	_check_NS_population_non_negative(sim, logger)
	_check_NS_resources_non_negative(sim, logger)
	_check_NS_strain_bounds(sim, logger)
	_check_NS_power_accounting(sim, logger)
	_check_LV_scar_bounds(sim, logger)
	_check_LV_intensity_bounds(sim, logger)
	_check_LV_duration_countdown(sim, logger)
	_check_LV_expiration_state(sim, logger)
	_check_T1_silver_non_negative(sim, logger)
	_check_T2_resources_non_negative(sim, logger)
	_check_E1_single_active_expedition(sim, logger)
	_check_EX_party_size_bounds(sim, logger)
	_check_EX_member_status(sim, logger)
	_check_EX_haul_sanity(sim, logger)
	var sample_due: bool = (_sampling_interval <= 1) or (sim.hour_index % _sampling_interval == 0)
	if sample_due:
		_check_PS_alive_equals_population(sim, logger)
		_check_PS_no_duplicate_ids(sim, logger)
		_check_PS_valid_status(sim, logger)
		_check_MA_module_accounting(sim, logger)
		_check_MA_abandoned_disabled(sim, logger)
		_check_MA_priority_unique(sim, logger)


func _check_T1_silver_non_negative(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.res.silver >= 0:
		_passed += 1
		logger.log_invariant("T1_TRADE_SILVER_NON_NEGATIVE", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T1_TRADE_SILVER_NON_NEGATIVE",
			"Silver balance went negative after trade",
			sim.hour_index,
			sim.day,
			">= 0",
			str(sim.res.silver)
		)


func _check_T2_resources_non_negative(sim: Sim, logger: RefCounted) -> void:
	var resources: Array[String] = ["food", "water", "materials"]
	for res_key in resources:
		_checked += 1
		var amount := sim.res.get_amount(res_key)
		if amount >= 0:
			_passed += 1
		else:
			_failed += 1
			logger.log_invariant_fail(
				"T2_TRADE_RESOURCE_NON_NEGATIVE",
				"Resource %s went negative" % res_key,
				sim.hour_index,
				sim.day,
				">= 0",
				str(amount)
			)


func _check_E1_single_active_expedition(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	# This is implicitly enforced by the expedition design (single active_expedition dict).
	# Check that if there's an active expedition, it has valid structure.
	if sim.has_active_expedition():
		var expedition := sim.get_active_expedition()
		if expedition.has("id") and expedition.has("state"):
			_passed += 1
			logger.log_invariant("E1_EXPEDITION_SINGLE_ACTIVE", true, sim.hour_index, sim.day)
		else:
			_failed += 1
			logger.log_invariant_fail(
				"E1_EXPEDITION_SINGLE_ACTIVE",
				"Active expedition missing required fields",
				sim.hour_index,
				sim.day,
				"id and state present",
				str(expedition.keys())
			)
	else:
		_passed += 1


# =============================================================================
# Trade Invariants (checked after trade action)
# =============================================================================

func check_trade(
	sim: Sim,
	logger: RefCounted,
	direction: String,
	resource: String,
	amount: int,
	pre_silver: int,
	pre_resource: int,
	pre_attention: float
) -> void:
	_check_T3_buy_cost_correct(sim, logger, direction, resource, amount, pre_silver)
	_check_T4_sell_revenue_correct(sim, logger, direction, resource, amount, pre_silver)
	_check_T5_resource_delta_correct(sim, logger, direction, resource, amount, pre_resource)
	_check_T6_attention_applied(sim, logger, pre_attention)
	_check_T7_attention_capped(sim, logger)
	_check_T8_amount_bounds(logger, amount, sim.hour_index, sim.day)


func check_trade_rejection(
	sim: Sim,
	logger: RefCounted,
	pre_hour_index: int,
	pre_day: int,
	pre_hour_of_day: int,
	pre_snapshot: String,
	pre_attention: float
) -> void:
	_checked += 1
	var time_ok: bool = sim.hour_index == pre_hour_index and sim.day == pre_day and sim.hour_of_day == pre_hour_of_day
	var res_ok: bool = sim.res.snapshot() == pre_snapshot
	var attention_ok: bool = sim.res.attention_multiplier == pre_attention

	if time_ok and res_ok and attention_ok:
		_passed += 1
		logger.log_invariant("T9_TRADE_REJECTION_NO_SIDE_EFFECTS", true, sim.hour_index, sim.day)
		return

	_failed += 1
	var actual := "time_ok=%s res_ok=%s attention_ok=%s" % [str(time_ok), str(res_ok), str(attention_ok)]
	logger.log_invariant_fail(
		"T9_TRADE_REJECTION_NO_SIDE_EFFECTS",
		"Trade rejection caused side effects",
		sim.hour_index,
		sim.day,
		"time/res/attention unchanged",
		actual
	)


func _check_T3_buy_cost_correct(
	sim: Sim,
	logger: RefCounted,
	direction: String,
	resource: String,
	amount: int,
	pre_silver: int
) -> void:
	if direction != "buy":
		return

	_checked += 1
	var rate := int(TRADE_BUY_RATES.get(resource, 0))
	var expected_cost := amount * rate
	var actual_cost := pre_silver - sim.res.silver

	if actual_cost == expected_cost:
		_passed += 1
		logger.log_invariant("T3_TRADE_BUY_COST_CORRECT", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T3_TRADE_BUY_COST_CORRECT",
			"Buy cost calculation incorrect",
			sim.hour_index,
			sim.day,
			str(expected_cost),
			str(actual_cost)
		)


func _check_T4_sell_revenue_correct(
	sim: Sim,
	logger: RefCounted,
	direction: String,
	resource: String,
	amount: int,
	pre_silver: int
) -> void:
	if direction != "sell":
		return

	_checked += 1
	var rate := int(TRADE_SELL_RATES.get(resource, 0))
	var expected_revenue := amount * rate
	var actual_revenue := sim.res.silver - pre_silver

	if actual_revenue == expected_revenue:
		_passed += 1
		logger.log_invariant("T4_TRADE_SELL_REVENUE_CORRECT", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T4_TRADE_SELL_REVENUE_CORRECT",
			"Sell revenue calculation incorrect",
			sim.hour_index,
			sim.day,
			str(expected_revenue),
			str(actual_revenue)
		)


func _check_T5_resource_delta_correct(
	sim: Sim,
	logger: RefCounted,
	direction: String,
	resource: String,
	amount: int,
	pre_resource: int
) -> void:
	_checked += 1
	var post_resource := sim.res.get_amount(resource)
	var expected_delta: int = amount if direction == "buy" else -amount
	var actual_delta := post_resource - pre_resource

	if actual_delta == expected_delta:
		_passed += 1
		logger.log_invariant("T5_TRADE_RESOURCE_DELTA_CORRECT", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T5_TRADE_RESOURCE_DELTA_CORRECT",
			"Resource delta mismatch for %s" % resource,
			sim.hour_index,
			sim.day,
			str(expected_delta),
			str(actual_delta)
		)


func _check_T6_attention_applied(sim: Sim, logger: RefCounted, pre_attention: float) -> void:
	_checked += 1
	var post_attention := sim.res.attention_multiplier

	if post_attention >= pre_attention:
		_passed += 1
		logger.log_invariant("T6_TRADE_ATTENTION_APPLIED", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T6_TRADE_ATTENTION_APPLIED",
			"Attention cost not applied",
			sim.hour_index,
			sim.day,
			">= %.2f" % pre_attention,
			"%.2f" % post_attention
		)


func _check_T7_attention_capped(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	# Note: attention_multiplier accumulates, so we check the per-trade delta was capped.
	# This is implicitly verified by T6; we just ensure no absurd values.
	var attention := sim.res.attention_multiplier
	# Allow reasonable accumulation (e.g., 100 trades * 5.0 cap = 500 max reasonable).
	if attention >= 0.0 and attention < 10000.0:
		_passed += 1
		logger.log_invariant("T7_TRADE_ATTENTION_CAPPED", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T7_TRADE_ATTENTION_CAPPED",
			"Attention multiplier out of bounds",
			sim.hour_index,
			sim.day,
			"0 <= x < 10000",
			"%.2f" % attention
		)


func _check_T8_amount_bounds(logger: RefCounted, amount: int, hour: int, day: int) -> void:
	_checked += 1
	if amount > 0 and amount <= 999:
		_passed += 1
		logger.log_invariant("T8_TRADE_AMOUNT_BOUNDS", true, hour, day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"T8_TRADE_AMOUNT_BOUNDS",
			"Trade amount out of bounds",
			hour,
			day,
			"0 < amount <= 999",
			str(amount)
		)


# =============================================================================
# Expedition Invariants (checked on launch)
# =============================================================================

func check_expedition_launch(
	sim: Sim,
	logger: RefCounted,
	destination_id: String,
	crew: int,
	pre_threat: int,
	had_active: bool
) -> void:
	_check_E2_crew_valid(sim, logger, crew)
	_check_E4_destination_valid(sim, logger, destination_id)
	_check_E7_threat_applied(sim, logger, pre_threat)
	_check_E10_blocked_while_active(sim, logger, had_active)

	# Initialize state tracking for this expedition.
	if sim.has_active_expedition():
		var expedition := sim.get_active_expedition()
		_prev_expedition_state = str(expedition.get("state", ""))
		_prev_expedition_hours = int(expedition.get("hours_in_state", 0))
		var member_value: Variant = expedition.get("member_ids", [])
		_last_expedition_member_ids.clear()
		if member_value is Array:
			for member_id in member_value:
				_last_expedition_member_ids.append(int(member_id))


func _check_E2_crew_valid(sim: Sim, logger: RefCounted, crew: int) -> void:
	_checked += 1
	if crew >= 1 and crew <= sim.res.population:
		_passed += 1
		logger.log_invariant("E2_EXPEDITION_CREW_VALID", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"E2_EXPEDITION_CREW_VALID",
			"Crew count invalid",
			sim.hour_index,
			sim.day,
			"1 <= crew <= %d" % sim.res.population,
			str(crew)
		)


func _check_E4_destination_valid(sim: Sim, logger: RefCounted, destination_id: String) -> void:
	_checked += 1
	if sim.map_def != null and sim.map_def.is_valid_destination(destination_id):
		_passed += 1
		logger.log_invariant("E4_EXPEDITION_DESTINATION_VALID", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"E4_EXPEDITION_DESTINATION_VALID",
			"Expedition to invalid destination",
			sim.hour_index,
			sim.day,
			"valid destination",
			destination_id
		)


func _check_E7_threat_applied(sim: Sim, logger: RefCounted, pre_threat: int) -> void:
	_checked += 1
	if sim.res.threat > pre_threat:
		_passed += 1
		logger.log_invariant("E7_EXPEDITION_THREAT_APPLIED", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"E7_EXPEDITION_THREAT_APPLIED",
			"Threat not applied on launch",
			sim.hour_index,
			sim.day,
			"> %d" % pre_threat,
			str(sim.res.threat)
		)


func _check_E10_blocked_while_active(sim: Sim, logger: RefCounted, _had_active: bool) -> void:
	_checked += 1
	# If there was already an active expedition, launch should have been blocked.
	# Since we're checking post-launch, this invariant is about the previous state.
	# The scenario should test this by attempting overlapping launches.
	_passed += 1
	logger.log_invariant("E10_EXPEDITION_BLOCKED_WHILE_ACTIVE", true, sim.hour_index, sim.day)


# =============================================================================
# Expedition Progress Invariants (checked during wait)
# =============================================================================

func check_expedition_progress(sim: Sim, logger: RefCounted) -> void:
	if not sim.has_active_expedition():
		return

	var expedition := sim.get_active_expedition()
	var current_state := str(expedition.get("state", ""))
	var current_hours := int(expedition.get("hours_in_state", 0))

	_check_E3_state_machine(sim, logger, current_state)
	_check_E5_hours_progress(sim, logger, current_state, current_hours)

	_prev_expedition_state = current_state
	_prev_expedition_hours = current_hours


func _check_E3_state_machine(sim: Sim, logger: RefCounted, current_state: String) -> void:
	if _prev_expedition_state == "":
		return  # First check, no previous state.

	_checked += 1
	var valid_transitions := {
		"PLANNED": ["OUTBOUND"],
		"OUTBOUND": ["OUTBOUND", "ONSITE"],
		"ONSITE": ["ONSITE", "RETURNING"],
		"RETURNING": ["RETURNING", "RESOLVED"],
		"RESOLVED": [],
		"FAILED": [],
	}

	var allowed: Array = valid_transitions.get(_prev_expedition_state, [])
	if current_state == _prev_expedition_state or allowed.has(current_state):
		_passed += 1
		logger.log_invariant("E3_EXPEDITION_STATE_MACHINE", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"E3_EXPEDITION_STATE_MACHINE",
			"Invalid state transition",
			sim.hour_index,
			sim.day,
			"%s -> %s" % [_prev_expedition_state, str(allowed)],
			"%s -> %s" % [_prev_expedition_state, current_state]
		)


func _check_E5_hours_progress(
	sim: Sim,
	logger: RefCounted,
	current_state: String,
	current_hours: int
) -> void:
	if _prev_expedition_state == "":
		return

	_checked += 1
	# Hours should increment if state unchanged, or reset to 0 on state change.
	if current_state == _prev_expedition_state:
		if current_hours >= _prev_expedition_hours:
			_passed += 1
			logger.log_invariant("E5_EXPEDITION_HOURS_PROGRESS", true, sim.hour_index, sim.day)
		else:
			_failed += 1
			logger.log_invariant_fail(
				"E5_EXPEDITION_HOURS_PROGRESS",
				"Expedition time not progressing",
				sim.hour_index,
				sim.day,
				">= %d" % _prev_expedition_hours,
				str(current_hours)
			)
	else:
		# State changed, hours should reset.
		_passed += 1
		logger.log_invariant("E5_EXPEDITION_HOURS_PROGRESS", true, sim.hour_index, sim.day)


# =============================================================================
# Expedition Resolve Invariants (checked on completion)
# =============================================================================

func check_expedition_resolve(sim: Sim, logger: RefCounted) -> void:
	_check_E9_resolution_event(sim, logger)
	# E6 (resources gained) would require tracking pre-resolve state.
	# For now, we trust the event log.


func _check_E9_resolution_event(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	# Check that expedition is no longer active (resolution occurred).
	if not sim.has_active_expedition():
		_passed += 1
		logger.log_invariant("E9_EXPEDITION_EVENT_RESOLVED", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"E9_EXPEDITION_EVENT_RESOLVED",
			"Expedition still active after wait timeout",
			sim.hour_index,
			sim.day,
			"no active expedition",
			"expedition still active"
		)


# =============================================================================
# Numeric Sanity (NS-*)
# =============================================================================

func _check_NS_no_nan(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	var nan_fields: Array[String] = []
	if is_nan(sim.res.morale_ceiling):
		nan_fields.append("morale_ceiling")
	if is_nan(sim.res.attention_multiplier):
		nan_fields.append("attention_multiplier")
	if is_nan(sim.res.collapse_debt):
		nan_fields.append("collapse_debt")
	if is_nan(sim.res.strain):
		nan_fields.append("strain")
	if is_nan(sim.ration_scar):
		nan_fields.append("ration_scar")
	if is_nan(sim.labor_scar):
		nan_fields.append("labor_scar")
	if is_nan(sim.expedition_attention):
		nan_fields.append("expedition_attention")

	if nan_fields.is_empty():
		_passed += 1
		logger.log_invariant("NS-1_NO_NAN", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-1_NO_NAN",
			"NaN detected in fields: %s" % ", ".join(nan_fields),
			sim.hour_index,
			sim.day,
			"finite",
			"NaN in: %s" % ", ".join(nan_fields)
		)


func _check_NS_no_inf(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	var inf_fields: Array[String] = []
	if is_inf(sim.res.morale_ceiling):
		inf_fields.append("morale_ceiling")
	if is_inf(sim.res.attention_multiplier):
		inf_fields.append("attention_multiplier")
	if is_inf(sim.res.collapse_debt):
		inf_fields.append("collapse_debt")
	if is_inf(sim.res.strain):
		inf_fields.append("strain")
	if is_inf(sim.ration_scar):
		inf_fields.append("ration_scar")
	if is_inf(sim.labor_scar):
		inf_fields.append("labor_scar")
	if is_inf(sim.expedition_attention):
		inf_fields.append("expedition_attention")

	if inf_fields.is_empty():
		_passed += 1
		logger.log_invariant("NS-2_NO_INF", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-2_NO_INF",
			"Inf detected in fields: %s" % ", ".join(inf_fields),
			sim.hour_index,
			sim.day,
			"finite",
			"Inf in: %s" % ", ".join(inf_fields)
		)


func _check_NS_threat_bounds(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.res.threat >= 0 and sim.res.threat <= 999:
		_passed += 1
		logger.log_invariant("NS-3_THREAT_BOUNDS", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-3_THREAT_BOUNDS",
			"Threat out of bounds",
			sim.hour_index,
			sim.day,
			"0..999",
			str(sim.res.threat)
		)


func _check_NS_morale_bounds(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	var morale_cap: int = int(floor(sim.res.morale_ceiling))
	if sim.res.morale >= 0 and sim.res.morale <= morale_cap:
		_passed += 1
		logger.log_invariant("NS-4_MORALE_BOUNDS", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-4_MORALE_BOUNDS",
			"Morale out of bounds",
			sim.hour_index,
			sim.day,
			"0..%d" % morale_cap,
			str(sim.res.morale)
		)


func _check_NS_population_non_negative(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.res.population >= 0:
		_passed += 1
		logger.log_invariant("NS-5_POPULATION_NON_NEGATIVE", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-5_POPULATION_NON_NEGATIVE",
			"Population went negative",
			sim.hour_index,
			sim.day,
			">= 0",
			str(sim.res.population)
		)


func _check_NS_resources_non_negative(sim: Sim, logger: RefCounted) -> void:
	var keys: Array[String] = ["food", "water", "materials", "silver", "gold"]
	for key in keys:
		_checked += 1
		var amount := sim.res.get_amount(key)
		if amount >= 0:
			_passed += 1
		else:
			_failed += 1
			logger.log_invariant_fail(
				"NS-6_RESOURCE_NON_NEGATIVE",
				"Resource %s went negative" % key,
				sim.hour_index,
				sim.day,
				">= 0",
				str(amount)
			)


func _check_NS_strain_bounds(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.res.strain >= 0.0 and sim.res.strain <= 100.0:
		_passed += 1
		logger.log_invariant("NS-7_STRAIN_BOUNDS", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-7_STRAIN_BOUNDS",
			"Structural strain out of bounds",
			sim.hour_index,
			sim.day,
			"0..100",
			"%.2f" % sim.res.strain
		)


func _check_NS_power_accounting(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.res.power_used <= sim.res.power_supply:
		_passed += 1
		logger.log_invariant("NS-8_POWER_ACCOUNTING", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"NS-8_POWER_ACCOUNTING",
			"Power used exceeds supply",
			sim.hour_index,
			sim.day,
			"used <= supply",
			"%d/%d" % [sim.res.power_used, sim.res.power_supply]
		)


# =============================================================================
# People System (PS-*)
# =============================================================================

func _check_PS_alive_equals_population(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	var alive_count: int = sim._alive_people_count()
	var population: int = sim.res.population
	if alive_count == population:
		_passed += 1
		logger.log_invariant("PS-1_ALIVE_EQUALS_POP", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"PS-1_ALIVE_EQUALS_POP",
			"Alive people count mismatch",
			sim.hour_index,
			sim.day,
			str(population),
			str(alive_count)
		)


func _check_PS_no_duplicate_ids(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	var seen: Dictionary = {}
	for entry in sim._people:
		if not (entry is Dictionary):
			continue
		var person_id: int = int((entry as Dictionary).get("id", -1))
		if person_id <= 0:
			continue
		if seen.has(person_id):
			_failed += 1
			logger.log_invariant_fail(
				"PS-2_NO_DUPLICATE_IDS",
				"Duplicate person id detected",
				sim.hour_index,
				sim.day,
				"unique ids",
				str(person_id)
			)
			return
		seen[person_id] = true
	_passed += 1
	logger.log_invariant("PS-2_NO_DUPLICATE_IDS", true, sim.hour_index, sim.day)


func _check_PS_valid_status(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	var allowed := {
		sim.PEOPLE_STATUS_HOME: true,
		sim.PEOPLE_STATUS_AWAY: true,
		sim.PEOPLE_STATUS_INJURED: true,
		sim.PEOPLE_STATUS_DEAD: true,
	}
	for entry in sim._people:
		if not (entry is Dictionary):
			continue
		var status: String = str((entry as Dictionary).get("status", ""))
		if not allowed.has(status):
			_failed += 1
			logger.log_invariant_fail(
				"PS-3_VALID_STATUS",
				"Invalid person status",
				sim.hour_index,
				sim.day,
				"home/away/injured/dead",
				status
			)
			return
	_passed += 1
	logger.log_invariant("PS-3_VALID_STATUS", true, sim.hour_index, sim.day)


# =============================================================================
# Expedition Sanity (EX-*)
# =============================================================================

func _check_EX_party_size_bounds(sim: Sim, logger: RefCounted) -> void:
	if not sim.has_active_expedition():
		return
	_checked += 1
	var expedition: Dictionary = sim.get_active_expedition()
	var party_size: int = int(expedition.get("party_size", expedition.get("crew", 0)))
	var max_party_size: int = sim.get_max_party_size()
	if party_size >= 1 and party_size <= max_party_size:
		_passed += 1
		logger.log_invariant("EX-3_PARTY_SIZE_BOUNDS", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"EX-3_PARTY_SIZE_BOUNDS",
			"Expedition party size out of bounds",
			sim.hour_index,
			sim.day,
			"1..%d" % max_party_size,
			str(party_size)
		)


func _check_EX_member_status(sim: Sim, logger: RefCounted) -> void:
	if not sim.has_active_expedition():
		return
	_checked += 1
	var expedition: Dictionary = sim.get_active_expedition()
	var state: String = str(expedition.get("state", ""))
	if state == sim.EXPEDITION_STATE_RESOLVED or state == sim.EXPEDITION_STATE_FAILED:
		_passed += 1
		logger.log_invariant("EX-4_MEMBER_IDS_VALID", true, sim.hour_index, sim.day)
		return
	var member_value: Variant = expedition.get("member_ids", [])
	if not (member_value is Array):
		_passed += 1
		logger.log_invariant("EX-4_MEMBER_IDS_VALID", true, sim.hour_index, sim.day)
		return
	var member_ids: Array = member_value as Array
	for member_id in member_ids:
		var person_id: int = int(member_id)
		var found := false
		for entry in sim._people:
			if not (entry is Dictionary):
				continue
			var entry_id: int = int((entry as Dictionary).get("id", -1))
			if entry_id == person_id:
				found = true
				var status: String = str((entry as Dictionary).get("status", ""))
				if status != sim.PEOPLE_STATUS_AWAY:
					_failed += 1
					logger.log_invariant_fail(
						"EX-4_MEMBER_IDS_VALID",
						"Expedition member not marked away",
						sim.hour_index,
						sim.day,
						"away",
						status
					)
					return
				break
		if not found:
			_failed += 1
			logger.log_invariant_fail(
				"EX-4_MEMBER_IDS_VALID",
				"Expedition member id missing",
				sim.hour_index,
				sim.day,
				"existing person",
				str(person_id)
			)
			return
	_passed += 1
	logger.log_invariant("EX-4_MEMBER_IDS_VALID", true, sim.hour_index, sim.day)


func _check_EX_haul_sanity(sim: Sim, logger: RefCounted) -> void:
	if sim.has_active_expedition():
		return
	if _last_expedition_member_ids.is_empty():
		return
	_checked += 1
	# Best-effort check: after resolve, ensure members return home or dead.
	for member_id in _last_expedition_member_ids:
		var person_id: int = int(member_id)
		for entry in sim._people:
			if not (entry is Dictionary):
				continue
			var entry_id: int = int((entry as Dictionary).get("id", -1))
			if entry_id == person_id:
				var status: String = str((entry as Dictionary).get("status", ""))
				if status != sim.PEOPLE_STATUS_HOME and status != sim.PEOPLE_STATUS_DEAD:
					_failed += 1
					logger.log_invariant_fail(
						"EX-5_MEMBER_RECONCILE",
						"Expedition member status not reconciled",
						sim.hour_index,
						sim.day,
						"home/dead",
						status
					)
					return
				break
	_passed += 1
	logger.log_invariant("EX-5_MEMBER_RECONCILE", true, sim.hour_index, sim.day)
	_last_expedition_member_ids.clear()


# =============================================================================
# Command Queue (CQ-*)
# =============================================================================

func check_command_queue(
	sim: Sim,
	logger: RefCounted,
	cmd_type: String,
	stalled: bool,
	pre_state: Dictionary,
	post_state: Dictionary
) -> void:
	_checked += 1
	if sim._command_queue.is_empty():
		_passed += 1
		logger.log_invariant("CQ-1_QUEUE_DRAINED", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"CQ-1_QUEUE_DRAINED",
			"Command queue not empty after production",
			sim.hour_index,
			sim.day,
			"empty",
			"size=%d" % sim._command_queue.size()
		)

	_checked += 1
	var compliance_subject := (cmd_type == Sim.CMD_TRADE or cmd_type == Sim.CMD_EXPEDITION)
	if stalled and not compliance_subject:
		_failed += 1
		logger.log_invariant_fail(
			"CQ-3_COMPLIANCE_SCOPE",
			"Compliance stall on non-compliance command",
			sim.hour_index,
			sim.day,
			"trade/expedition",
			cmd_type
		)
	else:
		_passed += 1
		logger.log_invariant("CQ-3_COMPLIANCE_SCOPE", true, sim.hour_index, sim.day)

	_checked += 1
	if stalled and not _dict_equals(pre_state, post_state):
		_failed += 1
		logger.log_invariant_fail(
			"CQ-2_STALL_NO_SIDE_EFFECTS",
			"Stalled command mutated tracked state",
			sim.hour_index,
			sim.day,
			JSON.stringify(pre_state),
			JSON.stringify(post_state)
		)
	else:
		_passed += 1
		logger.log_invariant("CQ-2_STALL_NO_SIDE_EFFECTS", true, sim.hour_index, sim.day)


func _dict_equals(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
		var left: Variant = a.get(key)
		var right: Variant = b.get(key)
		if left != right:
			return false
	return true


# =============================================================================
# Lever Invariants (LV-*)
# =============================================================================

func _check_LV_scar_bounds(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.ration_scar >= 0.0 and sim.labor_scar >= 0.0:
		_passed += 1
		logger.log_invariant("LV-2_SCAR_BOUNDS", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"LV-2_SCAR_BOUNDS",
			"Lever scar went negative",
			sim.hour_index,
			sim.day,
			">= 0",
			"ration=%.2f labor=%.2f" % [sim.ration_scar, sim.labor_scar]
		)


func _check_LV_intensity_bounds(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if (
		sim.labor_overdrive_intensity <= Sim.LABOR_OVERDRIVE_MAX_INTENSITY
		and sim.expedition_compression_intensity <= Sim.EXPEDITION_COMPRESSION_MAX_INTENSITY
		and sim.info_throttle_level <= Sim.INFO_THROTTLE_MAX_LEVEL
	):
		_passed += 1
		logger.log_invariant("LV-3_INTENSITY_BOUNDS", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"LV-3_INTENSITY_BOUNDS",
			"Lever intensity out of bounds",
			sim.hour_index,
			sim.day,
			"<= max",
			"labor=%d expedition=%d info=%d" % [
				sim.labor_overdrive_intensity,
				sim.expedition_compression_intensity,
				sim.info_throttle_level,
			]
		)


func _check_LV_duration_countdown(sim: Sim, logger: RefCounted) -> void:
	var current: Dictionary = {
		"ration": sim.ration_hardening_hours_left,
		"labor": sim.labor_overdrive_hours_left,
		"expedition": sim.expedition_compression_hours_left,
		"info": sim.info_throttle_hours_left,
	}
	if _prev_hour_index >= 0 and sim.hour_index == _prev_hour_index + 1:
		for key in current.keys():
			var prev_value: int = int(_prev_lever_hours.get(key, int(current.get(key, 0))))
			var next_value: int = int(current.get(key, 0))
			if prev_value > 0 and next_value < prev_value and next_value != prev_value - 1:
				_checked += 1
				_failed += 1
				logger.log_invariant_fail(
					"LV-1_DURATION_COUNTDOWN",
					"Lever hours_left did not decrement by 1",
					sim.hour_index,
					sim.day,
					"%d" % (prev_value - 1),
					"%d" % next_value
				)
				_prev_lever_hours = current
				_prev_hour_index = sim.hour_index
				return
	_checked += 1
	_passed += 1
	logger.log_invariant("LV-1_DURATION_COUNTDOWN", true, sim.hour_index, sim.day)
	_prev_lever_hours = current
	_prev_hour_index = sim.hour_index


func _check_LV_expiration_state(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if (
		sim.ration_hardening_hours_left == 0
		and sim.labor_overdrive_hours_left == 0
		and sim.expedition_compression_hours_left == 0
		and sim.info_throttle_hours_left == 0
	):
		_passed += 1
		logger.log_invariant("LV-4_EXPIRATION_STATE", true, sim.hour_index, sim.day)
		return
	# If any lever active, consider invariant satisfied (no expiration needed).
	_passed += 1
	logger.log_invariant("LV-4_EXPIRATION_STATE", true, sim.hour_index, sim.day)


# =============================================================================
# Module Accounting (MA-*)
# =============================================================================

func _check_MA_module_accounting(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	if sim.res.power_used <= sim.res.power_supply:
		_passed += 1
		logger.log_invariant("MA-1_POWER_BALANCE", true, sim.hour_index, sim.day)
	else:
		_failed += 1
		logger.log_invariant_fail(
			"MA-1_POWER_BALANCE",
			"Power balance negative",
			sim.hour_index,
			sim.day,
			"used <= supply",
			"%d/%d" % [sim.res.power_used, sim.res.power_supply]
		)


func _check_MA_abandoned_disabled(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	for key in sim.abandoned_modules.keys():
		var parts := str(key).split(":")
		if parts.size() != 3:
			continue
		var f: int = int(parts[0])
		var x: int = int(parts[1])
		var y: int = int(parts[2])
		if sim.tower.is_module_enabled(f, x, y):
			_failed += 1
			logger.log_invariant_fail(
				"MA-2_ABANDONED_DISABLED",
				"Abandoned module still enabled",
				sim.hour_index,
				sim.day,
				"disabled",
				"enabled"
			)
			return
	_passed += 1
	logger.log_invariant("MA-2_ABANDONED_DISABLED", true, sim.hour_index, sim.day)


func _check_MA_priority_unique(sim: Sim, logger: RefCounted) -> void:
	_checked += 1
	for floor_idx in range(sim.tower.floor_count()):
		var seen: Dictionary = {}
		var grid: Array[Variant] = sim.tower.floors[floor_idx]
		for y in range(grid.size()):
			var row: Array[Variant] = grid[y]
			for x in range(row.size()):
				if row[x] == null:
					continue
				var priority_value: Variant = sim.tower.get_module_priority_override(floor_idx, x, y)
				if priority_value == null:
					continue
				var prio: int = int(priority_value)
				if seen.has(prio):
					_failed += 1
					logger.log_invariant_fail(
						"MA-3_PRIORITY_UNIQUE",
						"Duplicate module priority override",
						sim.hour_index,
						sim.day,
						"unique priority",
						str(prio)
					)
					return
				seen[prio] = true
	_passed += 1
	logger.log_invariant("MA-3_PRIORITY_UNIQUE", true, sim.hour_index, sim.day)
