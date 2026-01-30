extends Node
class_name Sim

signal tick(day: int)

@export var seconds_per_day: float = 1.0
@export var enable_food_debug_log: bool = OS.is_debug_build()

const HOURS_PER_DAY := 24
const MAX_HOUR_TICKS_PER_FRAME := 6

func _ticks_per_day() -> int:
	if phase == "HOUR_TICK":
		return HOURS_PER_DAY
	return 1

func _days_to_ticks(days: int) -> int:
	var safe_days: int = int(days)
	if safe_days < 0:
		safe_days = 0
	if safe_days == 0:
		return 0
	return safe_days * _ticks_per_day()

var day: int = 0
var hour_index: int = 0
var hour_of_day: int = 0
var phase: String = "HOUR_TICK"
var _accum: float = 0.0
var sim_seed: int = 0

var tower: Tower
var res: Resources
var db: ModuleDB
var _last_obs_tokens: Array[String] = []
var _last_module_snapshots: Array[Dictionary] = []
var _last_production_metrics: Dictionary = {}

const IncidentDefsRef = preload("res://scripts/sim/IncidentDefs.gd")
const LeverDefsRef = preload("res://scripts/sim/LeverDefs.gd")

const MODULE_DELTA_KEYS: Array[String] = [
	"food",
	"water",
	"materials",
	"morale",
]

const THREAT_EVENT_THRESHOLDS: Array[int] = [40, 80, 120, 160, 200]
const MORALE_EVENT_THRESHOLDS: Array[int] = [60, 45, 30, 15]
const ATTENTION_SUMMARY_INTERVAL_HOURS := 6
const INTRO_QUIET_DAYS := 1
const ATTENTION_DEBT_LOW_THRESHOLD := 10.0
const ATTENTION_DEBT_HIGH_THRESHOLD := 25.0
const ATTENTION_NEUTRAL_MESSAGE := "Background resonance is steady. Nothing urgent to report."
const ATTENTION_LOW_MESSAGE := "Attention metrics are inching upward. Maintain caution."
const ATTENTION_WARNING_MESSAGE := "Attention debt building. Forecast: tensions will rise if unchecked."
const ATTENTION_HIGH_MESSAGE := "Attention debt accruing.\nForecast: When it surfaces, it will surface violently."

const RNG_BASE_MULTIPLIER := 73856093
const RNG_DAY_MULTIPLIER := 19349663
const RNG_CONTEXT_SEED_MASK := 0x7FFFFFFFFFFFFFFF
const RNG_OFFSET_INCIDENTS := 1
const RNG_OFFSET_EXPEDITIONS := 2
const RNG_OFFSET_COMMANDS := 3
const RNG_OFFSET_STRUCTURAL := 4
const PHASE_CIVIL_UNREST := "civil_unrest"
const RNG_OFFSET_UNREST_PRODUCTION := 5
const RNG_OFFSET_UNREST_INCIDENT := 6
const RNG_OFFSET_UNREST_MODULE := 7
const RNG_OFFSET_UNREST_TERMINAL := 8
const RNG_OFFSET_UNREST_TERMINAL_OUTCOME := 9

const PRODUCTION_HOUR_MIN := 3
const PRODUCTION_HOUR_MAX := 7

const TRADEABLE_RESOURCES := ["food", "water", "materials"]
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

const CIVIL_UNREST_ENTER_THRESHOLD := 40
const CIVIL_UNREST_EXIT_THRESHOLD := 45
const CIVIL_UNREST_POP_LOSS_DEFAULT := 1
const CIVIL_UNREST_POP_LOSS_BASE_CHANCE := 0.05
const CIVIL_UNREST_POP_LOSS_PER_DAY := 0.02
const CIVIL_UNREST_POP_LOSS_CAP := 0.5
const CIVIL_UNREST_MODULE_BASE_CHANCE := 0.03
const CIVIL_UNREST_MODULE_PER_DAY := 0.02
const CIVIL_UNREST_MODULE_CAP := 0.4
const CIVIL_UNREST_TERMINAL_RAMP := {
	3: 0.05,
	4: 0.1,
	5: 0.2,
	6: 0.4,
}
const CIVIL_UNREST_TERMINAL_CAP := 0.75
const EXIT_MUTINY := "EXIT_MUTINY"
const EXIT_EXILE := "EXIT_EXILE"

const PHASE_LEVERS := "levers"
const PHASE_COMMANDS := "commands"
const PHASE_INCIDENTS := "incidents"
const PHASE_EXPEDITIONS := "expeditions"
const PHASE_STRUCTURAL := "structural"

class SimCommand extends RefCounted:
	var type: String = ""
	var payload: Dictionary

	func _init(_type: String = "", _payload: Variant = null) -> void:
		type = _type
		payload = _duplicate_payload(_payload)

	func clone() -> SimCommand:
		var copy := SimCommand.new()
		copy.type = type
		copy.payload = _duplicate_payload(payload)
		return copy

	func _duplicate_payload(value: Variant) -> Dictionary:
		if value == null:
			return {}
		if value is Dictionary:
			return value.duplicate(true)
		return {}

const CMD_SET_RATIONS := "SET_RATIONS"
const CMD_SET_MODULE_ENABLED := "SET_MODULE_ENABLED"
const CMD_SET_MODULE_PRIORITY := "SET_MODULE_PRIORITY"
const CMD_EXPEDITION := "EXPEDITION"
const CMD_TRADE := "TRADE"

const LEVER_RATION_HARDENING := LeverDefsRef.LEVER_RATION_HARDENING
const LEVER_LABOR_OVERDRIVE := LeverDefsRef.LEVER_LABOR_OVERDRIVE
const LEVER_EXPEDITION_COMPRESSION := LeverDefsRef.LEVER_EXPEDITION_COMPRESSION
const LEVER_INFORMATION_THROTTLING := LeverDefsRef.LEVER_INFORMATION_THROTTLING
const LEVER_MODULE_ABANDONMENT := LeverDefsRef.LEVER_MODULE_ABANDONMENT
const LEVER_EMERGENCY_CONVERSION := LeverDefsRef.LEVER_EMERGENCY_CONVERSION

const LEVER_STATE_TRACKED: Array[String] = [
	LEVER_RATION_HARDENING,
	LEVER_LABOR_OVERDRIVE,
	LEVER_EXPEDITION_COMPRESSION,
	LEVER_INFORMATION_THROTTLING,
]
const LEVER_DISPLAY_NAMES := {
	LEVER_RATION_HARDENING: "Ration hardening",
	LEVER_LABOR_OVERDRIVE: "Labor overdrive",
	LEVER_EXPEDITION_COMPRESSION: "Expedition compression",
	LEVER_INFORMATION_THROTTLING: "Information throttling",
	LEVER_MODULE_ABANDONMENT: "Module abandonment",
	LEVER_EMERGENCY_CONVERSION: "Emergency conversion",
}

const RATION_HARDENING_SOFT_MULT := 0.9
const RATION_HARDENING_HARD_MULT := 0.75
const RATION_SCAR_PER_DAY_SOFT := 0.1
const RATION_SCAR_PER_DAY_HARD := 0.25
const RATION_SCAR_RECOVERY_MULT := 0.05
const RATION_RECOVERY_MIN_MULT := 0.5
const RATION_SCAR_CEILING_PENALTY := 0.1

const LABOR_OVERDRIVE_MULT_PER_LEVEL := 0.15
const LABOR_OVERDRIVE_MAX_INTENSITY := 5
const LABOR_SCAR_PER_DAY := 0.2
const LABOR_SCAR_EFFICIENCY_MULT := 0.05
const LABOR_EFFICIENCY_MIN := 0.6
const LABOR_SCAR_THREAT_MULT := 0.2

const EXPEDITION_COMPRESSION_YIELD_PER_CREW := 1
const EXPEDITION_COMPRESSION_MAX_INTENSITY := 5
const EXPEDITION_ATTENTION_PER_DAY := 1
const EXPEDITION_ATTENTION_PER_TRIP := 2
const EXPEDITION_ATTENTION_THREAT_MULT := 0.1

const INFO_THROTTLE_MAX_LEVEL := 5
const INFO_THROTTLE_MORALE_FACTOR_PER_LEVEL := 0.25
const INFO_THROTTLE_MORALE_MIN_FACTOR := 0.4
const INFO_THROTTLE_MISALLOC_PER_LEVEL := 0.1
const INFO_THROTTLE_MISALLOC_MIN := 0.6
const INFO_THROTTLE_SHOCK_THREAT_MULT := 0.5

const SIM_FLOAT_SNAP: float = 0.01 # Determinism hardening: snap small float accumulators post-update.

const STRUCTURAL_STRAIN_PER_MODULE := 0.04
const STRUCTURAL_STRAIN_PER_MAINT_DEFICIT := 0.5
const STRUCTURAL_STRAIN_DECAY := 1.0
const STRUCTURAL_TELEGRAPH_THRESHOLDS: Array[float] = [25.0, 45.0, 70.0]
const STRUCTURAL_TELEGRAPH_EVENTS: Array[String] = [
	"STRUCT_CREAKS",
	"STRUCT_FRACTURES",
	"STRUCT_CRITICAL",
]
const STRUCTURAL_TELEGRAPH_DELAY_DAYS := 1
const STRUCTURAL_COLLAPSE_MIN_STRAIN := 45.0
const STRUCTURAL_COLLAPSE_MIN_DAYS := 3
const STRUCTURAL_COLLAPSE_DEBT_SCALE := 0.05
const STRUCTURAL_COLLAPSE_DEBT_PENALTY := 0.5
const STRUCTURAL_COLLAPSE_DECAY := 0.5
const STRUCTURAL_COLLAPSE_DELAY_DAYS := 1
const STRUCTURAL_WARNING_MORALE_PENALTY := 1
const STRUCTURAL_COLLAPSE_MORALE_PENALTY := 2
const STRUCTURAL_COLLAPSE_MATERIALS_LOSS := 5
const STRUCTURAL_INCIDENT_IDS: Array[String] = [
	"support_shift",
	"floor_sag",
	"structural_breach",
]

const MAINTENANCE_COST_PER_MODULE := 0.5
const MAINTENANCE_STRAIN_THRESHOLD := 50.0
const MAINTENANCE_STRAIN_MULTIPLIER := 0.02
const THREAT_PER_NOISE := 0.5
const THREAT_PER_HEAT := 0.5
const THREAT_PER_POWER := 0.2

const CONVERSION_SCAR_PER_USE := 1
const CONVERSION_EFFICIENCY_LOSS := 0.1
const CONVERSION_EFFICIENCY_MIN := 0.4
const CONVERSION_BURN_THRESHOLD := 3
const CONVERSION_CEILING_PENALTY := 0.3
const CONVERTIBLE_RESOURCES: Array[String] = ["food", "water", "materials", "morale"]

var _command_queue: Array[SimCommand] = []
var lever_events: Array[Dictionary] = []
var events: Array[Dictionary] = []
var visibility_triggered: bool = false
var _event_sequence: int = 0
var _last_maintenance_shortfall: bool = false
var _last_attention_summary_hour_index: int = -1
var _last_attention_summary_value: float = 0.0
var _hourly_food_accum: float = 0.0
var _hourly_water_accum: float = 0.0
var _daily_food_consumed: int = 0
var _daily_water_consumed: int = 0
var scheduled_production_hour: int = PRODUCTION_HOUR_MIN
var production_executed_today: bool = false
var _daily_rolls: Dictionary = {}
var unrest_active: bool = false
var unrest_hours: int = 0
var exit_reason: String = ""
var _lever_active_state: Dictionary = {}
var _rng_usage_history: Array[Dictionary] = []
var _rng_usage_lookup: Dictionary = {}
var _rng_instances: Dictionary[String, RandomNumberGenerator] = {}

# Expedition memory tuning (deterministic, minimal)
const EXPEDITION_RECENT_GAIN := 3
const EXPEDITION_RECENT_DECAY := 1
const EXPEDITION_HEAT_DELAY_THRESHOLD := 4
const EXPEDITION_KIND_BIAS_PER_HEAT := 5
const EXPEDITION_KIND_BIAS_CAP := 30
const EXPEDITION_MAG_HEAT_DIV := 2
const EXPEDITION_MAG_CAP := 10

# Survival policies (persistent levers)
var food_ration: float = 1.0
var water_ration: float = 1.0

# Finite-world expedition pools (no regeneration)
var scav_pools: Dictionary = {}

# Per-day transient effects derived from commands
var expedition_crew_today: int = 0
var expedition_threat_today: int = 0
var expedition_morale_penalty_today: int = 0
var ration_morale_penalty_today: int = 0
var ration_threat_penalty_today: int = 0
var workforce_multiplier_today: float = 1.0
var ration_consumption_multiplier_today: float = 1.0
var ration_recovery_multiplier_today: float = 1.0
var labor_output_multiplier_today: float = 1.0
var labor_efficiency_cap_today: float = 1.0
var expedition_yield_bonus_per_crew_today: int = 0
var expedition_attention_bonus_per_trip_today: int = 0
var info_throttle_morale_factor_today: float = 1.0
var info_misalloc_multiplier_today: float = 1.0
var lever_threat_bonus_today: int = 0

# Expedition profile memory (persistent)
var expedition_count_total: int = 0
var expedition_streak: int = 0
var expedition_recent_score: int = 0
var expedition_heat: int = 0
var expedition_commands_today: int = 0
var expedition_happened_today: bool = false

# Lagged consequences for expeditions (persistent, deterministic queue)
var expedition_counter: int = 0
var _delayed_consequence_queue: Array[Dictionary] = []
var _delayed_insertion_counter: int = 0
var _consequence_queue: Array[Dictionary] = []
var _consequence_insertion_counter: int = 0
var _structural_telegraph_level: int = -1
var _structural_warning_logged: bool = false
var _structural_high_strain_days: int = 0
var _structural_collapse_scheduled: bool = false

# Lever state (persistent)
var ration_hardening_ticks_left: int = 0
var ration_hardening_start_hour_index: int = -1
var ration_hardening_duration_hours: int = 0
var ration_hardening_end_hour_index: int = -1
var ration_hardening_hours_left: int = 0
var ration_hardening_mode: String = ""
var ration_scar: float = 0.0

var labor_overdrive_ticks_left: int = 0
var labor_overdrive_start_hour_index: int = -1
var labor_overdrive_duration_hours: int = 0
var labor_overdrive_end_hour_index: int = -1
var labor_overdrive_hours_left: int = 0
var labor_overdrive_intensity: int = 0
var labor_scar: float = 0.0

var expedition_compression_ticks_left: int = 0
var expedition_compression_start_hour_index: int = -1
var expedition_compression_duration_hours: int = 0
var expedition_compression_end_hour_index: int = -1
var expedition_compression_hours_left: int = 0
var expedition_compression_intensity: int = 0
var expedition_attention: float = 0.0

var info_throttle_ticks_left: int = 0
var info_throttle_start_hour_index: int = -1
var info_throttle_duration_hours: int = 0
var info_throttle_end_hour_index: int = -1
var info_throttle_hours_left: int = 0
var info_throttle_level: int = 0
var info_throttle_backlog: float = 0.0

var abandoned_modules: Dictionary = {}

var conversion_scar: int = 0
var conversion_burn_counts: Dictionary = {}
var pending_conversions: Array[Dictionary] = []

func _ready() -> void:
	_setup_default_state()

	print("Tower floors:", tower.floor_count())
	print("Day 0:", res.summary())

func _process(delta: float) -> void:
	_accum += delta
	var seconds_per_hour := seconds_per_day / float(HOURS_PER_DAY)
	var ticks_this_frame := 0
	while _accum >= seconds_per_hour and ticks_this_frame < MAX_HOUR_TICKS_PER_FRAME:
		_accum -= seconds_per_hour
		ticks_this_frame += 1
		_advance_hour()

func _step_day() -> void:
	_step_day_core(day, sim_seed, tower, res, db)

func _advance_hour() -> void:
	hour_index += 1
	hour_of_day = int(hour_index % HOURS_PER_DAY)
	day = int(float(hour_index) / float(HOURS_PER_DAY))
	phase = "HOUR_TICK"
	_apply_hourly_consumption()
	_update_civil_unrest_state()
	_update_lever_hourly_states()
	_emit_lever_state_changes()
	if hour_of_day == 0:
		_begin_day(day)
	if hour_of_day == scheduled_production_hour and not production_executed_today:
		var incidents := _step_day_core(day, sim_seed, tower, res, db)
		print(_format_log_line(day, sim_seed, res, incidents, _last_obs_tokens))
		production_executed_today = true
	_emit_attention_debt_summary()
	tick.emit(day)


func _setup_default_state() -> void:
	db = ModuleDB.new()
	res = Resources.new()
	tower = Tower.new(6, 6)
	_reset_policies_and_pools()

	# Place a small starter layout
	tower.place_module(0, 2, 2, "core")
	tower.place_module(0, 2, 3, "generator")
	tower.place_module(0, 1, 2, "housing")
	tower.place_module(0, 3, 2, "purifier")
	tower.place_module(0, 2, 1, "hydro")

	# MVP survival-friendly starter expansion (buys time, does not prevent collapse)
	tower.place_module(0, 3, 3, "generator")
	tower.place_module(0, 1, 3, "housing")
	tower.place_module(0, 4, 2, "purifier")
	tower.place_module(0, 2, 4, "hydro")

	# Initial buffers tuned for a ~30 day observation window.
	res.food = 90
	res.water = 90
	res.materials = 220
	res.morale = 65
	res.population = 6

	_refresh_module_snapshots({})

func _reset_policies_and_pools() -> void:
	food_ration = 1.0
	water_ration = 1.0
	# Finite pools: deterministic, auditable, and intentionally exhaustible.
	scav_pools = {
		"materials": 120,
		"water": 80,
		"food": 60,
	}
	_command_queue.clear()
	lever_events.clear()
	events.clear()
	_event_sequence = 0
	visibility_triggered = false
	_reset_rng_usage_log()
	_last_maintenance_shortfall = false
	_last_attention_summary_hour_index = -1
	_last_attention_summary_value = 0.0
	_lever_active_state.clear()
	for lever_id in LEVER_STATE_TRACKED:
		_lever_active_state[lever_id] = false
	expedition_crew_today = 0
	expedition_threat_today = 0
	expedition_morale_penalty_today = 0
	ration_morale_penalty_today = 0
	ration_threat_penalty_today = 0
	workforce_multiplier_today = 1.0
	ration_consumption_multiplier_today = 1.0
	ration_recovery_multiplier_today = 1.0
	labor_output_multiplier_today = 1.0
	labor_efficiency_cap_today = 1.0
	expedition_yield_bonus_per_crew_today = 0
	expedition_attention_bonus_per_trip_today = 0
	info_throttle_morale_factor_today = 1.0
	info_misalloc_multiplier_today = 1.0
	lever_threat_bonus_today = 0
	expedition_count_total = 0
	expedition_streak = 0
	expedition_recent_score = 0
	expedition_heat = 0
	expedition_commands_today = 0
	expedition_happened_today = false
	expedition_counter = 0
	_delayed_consequence_queue.clear()
	_delayed_insertion_counter = 0
	_consequence_queue.clear()
	_consequence_insertion_counter = 0
	_structural_telegraph_level = -1
	_structural_warning_logged = false
	_structural_high_strain_days = 0
	_structural_collapse_scheduled = false
	ration_hardening_ticks_left = 0
	ration_hardening_start_hour_index = -1
	ration_hardening_duration_hours = 0
	ration_hardening_end_hour_index = -1
	ration_hardening_hours_left = 0
	ration_hardening_mode = ""
	ration_scar = 0.0
	labor_overdrive_ticks_left = 0
	labor_overdrive_start_hour_index = -1
	labor_overdrive_duration_hours = 0
	labor_overdrive_end_hour_index = -1
	labor_overdrive_hours_left = 0
	labor_overdrive_intensity = 0
	labor_scar = 0.0
	expedition_compression_ticks_left = 0
	expedition_compression_start_hour_index = -1
	expedition_compression_duration_hours = 0
	expedition_compression_end_hour_index = -1
	expedition_compression_hours_left = 0
	expedition_compression_intensity = 0
	expedition_attention = 0.0
	info_throttle_ticks_left = 0
	info_throttle_start_hour_index = -1
	info_throttle_duration_hours = 0
	info_throttle_end_hour_index = -1
	info_throttle_hours_left = 0
	info_throttle_level = 0
	info_throttle_backlog = 0.0
	abandoned_modules.clear()
	conversion_scar = 0
	conversion_burn_counts.clear()
	pending_conversions.clear()
	_hourly_food_accum = 0.0
	_hourly_water_accum = 0.0
	_daily_food_consumed = 0
	_daily_water_consumed = 0
	scheduled_production_hour = PRODUCTION_HOUR_MIN
	production_executed_today = false
	_daily_rolls.clear()
	unrest_active = false
	unrest_hours = 0
	exit_reason = ""
	_update_lever_hourly_states()

func _begin_day(sim_day: int) -> void:
	production_executed_today = false
	_prepare_daily_rolls(sim_day)
	_daily_food_consumed = 0
	_daily_water_consumed = 0
	scheduled_production_hour = int(_daily_rolls.get("production_hour", PRODUCTION_HOUR_MIN))
	var scheduled := scheduled_production_hour
	var message := "Daily production scheduled for hour %02d." % scheduled
	_emit_event(
		"PRODUCTION_SCHEDULED",
		message,
		"info",
		"dev_only",
		{"scheduled_hour": scheduled},
		"time",
		sim_day,
		hour_of_day,
		true
	)
	print("PRODUCTION_SCHEDULE day=%d hour=%02d" % [sim_day, scheduled])

func _prepare_daily_rolls(sim_day: int) -> void:
	_daily_rolls.clear()
	var production_tracker := _create_rng_tracker(sim_day, PHASE_CIVIL_UNREST, "production_hour", RNG_OFFSET_UNREST_PRODUCTION)
	var hour_range := PRODUCTION_HOUR_MAX - PRODUCTION_HOUR_MIN + 1
	var hour_roll := int(_rng_randi(production_tracker))
	var scheduled_hour := PRODUCTION_HOUR_MIN + int(hour_roll % hour_range)
	_daily_rolls["production_hour"] = scheduled_hour
	_daily_rolls["production_roll"] = hour_roll
	var incident_tracker := _create_rng_tracker(sim_day, PHASE_CIVIL_UNREST, "unrest_incident", RNG_OFFSET_UNREST_INCIDENT)
	_daily_rolls["unrest_incident_roll"] = _rng_randf(incident_tracker)
	var module_tracker := _create_rng_tracker(sim_day, PHASE_CIVIL_UNREST, "unrest_module", RNG_OFFSET_UNREST_MODULE)
	_daily_rolls["unrest_module_roll"] = _rng_randf(module_tracker)
	var terminal_tracker := _create_rng_tracker(sim_day, PHASE_CIVIL_UNREST, "unrest_terminal", RNG_OFFSET_UNREST_TERMINAL)
	_daily_rolls["unrest_terminal_roll"] = _rng_randf(terminal_tracker)
	var outcome_tracker := _create_rng_tracker(sim_day, PHASE_CIVIL_UNREST, "unrest_terminal_outcome", RNG_OFFSET_UNREST_TERMINAL_OUTCOME)
	_daily_rolls["unrest_terminal_outcome_roll"] = _rng_randf(outcome_tracker)

func _apply_hourly_consumption() -> void:
	if res == null:
		return
	var population = max(res.population, 0)
	if population == 0:
		return
	var food_rate := float(population) * food_ration * ration_consumption_multiplier_today / float(HOURS_PER_DAY)
	var water_rate := float(population) * water_ration * ration_consumption_multiplier_today / float(HOURS_PER_DAY)
	_hourly_food_accum = snappedf(_hourly_food_accum + food_rate, SIM_FLOAT_SNAP)
	_hourly_water_accum = snappedf(_hourly_water_accum + water_rate, SIM_FLOAT_SNAP)
	var food_to_consume := int(floor(_hourly_food_accum))
	var water_to_consume := int(floor(_hourly_water_accum))
	if food_to_consume > 0:
		var actual_food = min(res.food, food_to_consume)
		res.food = res.food - actual_food
		_daily_food_consumed += actual_food
		_hourly_food_accum -= float(actual_food)
	if water_to_consume > 0:
		var actual_water = min(res.water, water_to_consume)
		res.water = res.water - actual_water
		_daily_water_consumed += actual_water
		_hourly_water_accum -= float(actual_water)

func _update_civil_unrest_state() -> void:
	if res == null:
		return
	var morale := res.morale
	if unrest_active:
		if morale >= CIVIL_UNREST_EXIT_THRESHOLD:
			unrest_active = false
			unrest_hours = 0
		else:
			unrest_hours += 1
	else:
		if morale < CIVIL_UNREST_ENTER_THRESHOLD:
			unrest_active = true
			unrest_hours = 1
		else:
			unrest_hours = 0

func enqueue_command(cmd: SimCommand) -> void:
	if cmd == null:
		return
	_command_queue.append(cmd)

func queue_trade(resource: String, direction: String, amount: int) -> Dictionary:
	var normalized_resource := str(resource).to_lower()
	var normalized_direction := str(direction).to_lower()
	var payload := {
		"direction": normalized_direction,
		"resource": normalized_resource,
		"amount": clamp(amount, 0, 999999),
	}
	var result := {"ok": false, "message": "INVALID TRADE"}
	if normalized_direction != "buy" and normalized_direction != "sell":
		result["message"] = "INVALID ACTION"
		return result
	if not TRADEABLE_RESOURCES.has(normalized_resource):
		result["message"] = "INVALID RESOURCE"
		return result
	if amount <= 0:
		result["message"] = "INVALID AMOUNT"
		return result
	enqueue_command(SimCommand.new(CMD_TRADE, payload))
	result["ok"] = true
	result["message"] = "TRADE QUEUED"
	return result

func clear_commands() -> void:
	_command_queue.clear()

func _duration_payload_hours(payload: Dictionary) -> int:
	if payload == null:
		return 0
	if payload.has("duration_ticks"):
		return max(int(payload.get("duration_ticks", 0)), 0)
	if payload.has("duration_hours"):
		return max(int(payload.get("duration_hours", 0)), 0)
	if payload.has("duration_days"):
		return _days_to_ticks(int(payload.get("duration_days", 0)))
	return 0

func _duration_payload_summary(payload: Dictionary) -> Dictionary:
	var summary: Dictionary = {}
	if payload == null:
		return summary
	if payload.has("duration_days"):
		summary["duration_days"] = int(payload.get("duration_days", 0))
	if payload.has("duration_hours"):
		summary["duration_hours"] = int(payload.get("duration_hours", 0))
	if payload.has("duration_ticks"):
		summary["duration_ticks"] = int(payload.get("duration_ticks", 0))
	return summary

func _duration_metadata(duration_hours: int) -> Dictionary:
	var start_hour := hour_index
	return {
		"start_hour_index": start_hour,
		"duration_hours": duration_hours,
		"end_hour_index": start_hour + duration_hours,
		"hours_left": duration_hours,
	}

func _lever_hours_left(start_hour_index: int, duration_hours: int) -> int:
	if start_hour_index < 0 or duration_hours <= 0:
		return 0
	var end_hour_index := start_hour_index + duration_hours
	return max(end_hour_index - hour_index, 0)

func _update_lever_hourly_states() -> void:
	if ration_hardening_duration_hours <= 0 and ration_hardening_ticks_left > 0:
		ration_hardening_start_hour_index = hour_index
		ration_hardening_duration_hours = ration_hardening_ticks_left
		ration_hardening_end_hour_index = ration_hardening_start_hour_index + ration_hardening_duration_hours
	if labor_overdrive_duration_hours <= 0 and labor_overdrive_ticks_left > 0:
		labor_overdrive_start_hour_index = hour_index
		labor_overdrive_duration_hours = labor_overdrive_ticks_left
		labor_overdrive_end_hour_index = labor_overdrive_start_hour_index + labor_overdrive_duration_hours
	if expedition_compression_duration_hours <= 0 and expedition_compression_ticks_left > 0:
		expedition_compression_start_hour_index = hour_index
		expedition_compression_duration_hours = expedition_compression_ticks_left
		expedition_compression_end_hour_index = expedition_compression_start_hour_index + expedition_compression_duration_hours
	if info_throttle_duration_hours <= 0 and info_throttle_ticks_left > 0:
		info_throttle_start_hour_index = hour_index
		info_throttle_duration_hours = info_throttle_ticks_left
		info_throttle_end_hour_index = info_throttle_start_hour_index + info_throttle_duration_hours
	ration_hardening_hours_left = _lever_hours_left(ration_hardening_start_hour_index, ration_hardening_duration_hours)
	ration_hardening_ticks_left = ration_hardening_hours_left
	labor_overdrive_hours_left = _lever_hours_left(labor_overdrive_start_hour_index, labor_overdrive_duration_hours)
	labor_overdrive_ticks_left = labor_overdrive_hours_left
	expedition_compression_hours_left = _lever_hours_left(expedition_compression_start_hour_index, expedition_compression_duration_hours)
	expedition_compression_ticks_left = expedition_compression_hours_left
	info_throttle_hours_left = _lever_hours_left(info_throttle_start_hour_index, info_throttle_duration_hours)
	info_throttle_ticks_left = info_throttle_hours_left

func _dict_merge_into(dst: Dictionary, src: Dictionary) -> void:
	if dst == null or src == null:
		return
	var keys := src.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		dst[key] = src[key]

func _rng_tracker_key(tracker_day: int, tracker_phase: String, context: String) -> String:
	return "%d|%s|%s" % [tracker_day, tracker_phase, context]

func _deterministic_seed(seed_day: int, offset: int) -> int:
	var accumulator: int = int(sim_seed)
	accumulator = int((accumulator * RNG_BASE_MULTIPLIER + int(seed_day) * RNG_DAY_MULTIPLIER + offset) & RNG_CONTEXT_SEED_MASK)
	return accumulator

func _create_rng_tracker(tracker_day: int, tracker_phase: String, context: String, offset: int, seed_override: Variant = null) -> Dictionary:
	var base_seed := _deterministic_seed(tracker_day, offset)
	var raw_seed := int(seed_override) if seed_override != null else base_seed
	var seed_value := int(raw_seed) & RNG_CONTEXT_SEED_MASK
	var key := _rng_tracker_key(tracker_day, tracker_phase, context)
	var entry: Dictionary = {
		"day": tracker_day,
		"phase": tracker_phase,
		"context": context,
		"seed": seed_value,
		"calls": 0,
		"key": key,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_rng_usage_history.append(entry)
	_rng_usage_lookup[key] = entry
	_rng_instances[key] = rng
	return entry

func _rng_call(entry: Dictionary) -> void:
	if entry == null:
		return
	entry["calls"] = int(entry.get("calls", 0)) + 1

func _rng_instance_for_entry(entry: Dictionary) -> RandomNumberGenerator:
	if entry == null:
		return null
	var entry_key: String = str(entry.get("key", ""))
	var candidate_value: Variant = _rng_instances.get(entry_key)
	if candidate_value is RandomNumberGenerator:
		return candidate_value as RandomNumberGenerator
	return null

func _rng_randf(entry: Dictionary) -> float:
	_rng_call(entry)
	var rng := _rng_instance_for_entry(entry)
	if rng == null:
		return 0.0
	return rng.randf()

func _rng_randi(entry: Dictionary) -> int:
	_rng_call(entry)
	var rng := _rng_instance_for_entry(entry)
	if rng == null:
		return 0
	return rng.randi()

func _reset_rng_usage_log() -> void:
	_rng_usage_history.clear()
	_rng_usage_lookup.clear()
	_rng_instances.clear()

func get_rng_usage_history() -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for entry in _rng_usage_history:
		if entry is Dictionary:
			copies.append(_rng_entry_metadata(entry))
		else:
			copies.append({})
	return copies

func _rng_entry_metadata(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if entry == null:
		return result
	result["day"] = int(entry.get("day", 0))
	result["phase"] = str(entry.get("phase", ""))
	result["context"] = str(entry.get("context", ""))
	result["seed"] = int(entry.get("seed", 0))
	result["calls"] = int(entry.get("calls", 0))
	result["key"] = str(entry.get("key", ""))
	return result

func get_last_production_metrics() -> Dictionary:
	if _last_production_metrics.is_empty():
		return {}
	return _last_production_metrics.duplicate(true)

func apply_lever(lever_id: String, payload: Dictionary) -> bool:
	var ok := false
	var sanitized: Dictionary = {}
	var immediate_summary := ""
	var debts_summary := ""

	match lever_id:
		LEVER_RATION_HARDENING:
			var mode: String = str(payload.get("mode", ""))
			var duration_hours := _duration_payload_hours(payload)
			if mode != "soft" and mode != "hard":
				immediate_summary = "REJECTED: invalid mode"
			elif duration_hours <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				ration_hardening_mode = mode
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_hours"] = duration_hours
				duration_info["duration_ticks"] = duration_hours
				var duration_metadata: Dictionary = _duration_metadata(duration_hours)
				ration_hardening_start_hour_index = int(duration_metadata.get("start_hour_index", -1))
				ration_hardening_duration_hours = int(duration_metadata.get("duration_hours", 0))
				ration_hardening_end_hour_index = int(duration_metadata.get("end_hour_index", -1))
				_dict_merge_into(duration_info, duration_metadata)
				sanitized = {"mode": mode}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "policy active"
				debts_summary = "scar accrues"
				ok = true
		LEVER_LABOR_OVERDRIVE:
			var intensity: int = int(payload.get("intensity", 0))
			var duration_hours := _duration_payload_hours(payload)
			if intensity <= 0:
				immediate_summary = "REJECTED: invalid intensity"
			elif duration_hours <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				intensity = int(clamp(intensity, 1, LABOR_OVERDRIVE_MAX_INTENSITY))
				labor_overdrive_intensity = intensity
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_hours"] = duration_hours
				duration_info["duration_ticks"] = duration_hours
				var duration_metadata: Dictionary = _duration_metadata(duration_hours)
				labor_overdrive_start_hour_index = int(duration_metadata.get("start_hour_index", -1))
				labor_overdrive_duration_hours = int(duration_metadata.get("duration_hours", 0))
				labor_overdrive_end_hour_index = int(duration_metadata.get("end_hour_index", -1))
				_dict_merge_into(duration_info, duration_metadata)
				sanitized = {"intensity": intensity}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "throughput boosted"
				debts_summary = "labor scar accrues"
				ok = true
		LEVER_EXPEDITION_COMPRESSION:
			var intensity: int = int(payload.get("intensity", 0))
			var duration_hours := _duration_payload_hours(payload)
			if intensity <= 0:
				immediate_summary = "REJECTED: invalid intensity"
			elif duration_hours <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				intensity = int(clamp(intensity, 1, EXPEDITION_COMPRESSION_MAX_INTENSITY))
				expedition_compression_intensity = intensity
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_hours"] = duration_hours
				duration_info["duration_ticks"] = duration_hours
				var duration_metadata: Dictionary = _duration_metadata(duration_hours)
				expedition_compression_start_hour_index = int(duration_metadata.get("start_hour_index", -1))
				expedition_compression_duration_hours = int(duration_metadata.get("duration_hours", 0))
				expedition_compression_end_hour_index = int(duration_metadata.get("end_hour_index", -1))
				_dict_merge_into(duration_info, duration_metadata)
				sanitized = {"intensity": intensity}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "expedition tempo compressed"
				debts_summary = "attention accrues"
				ok = true
		LEVER_INFORMATION_THROTTLING:
			var level: int = int(payload.get("level", 0))
			var duration_hours := _duration_payload_hours(payload)
			if level <= 0:
				immediate_summary = "REJECTED: invalid level"
			elif duration_hours <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				level = int(clamp(level, 1, INFO_THROTTLE_MAX_LEVEL))
				info_throttle_level = level
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_hours"] = duration_hours
				duration_info["duration_ticks"] = duration_hours
				var duration_metadata: Dictionary = _duration_metadata(duration_hours)
				info_throttle_start_hour_index = int(duration_metadata.get("start_hour_index", -1))
				info_throttle_duration_hours = int(duration_metadata.get("duration_hours", 0))
				info_throttle_end_hour_index = int(duration_metadata.get("end_hour_index", -1))
				_dict_merge_into(duration_info, duration_metadata)
				sanitized = {"level": level}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "instability dampened"
				debts_summary = "backlog accrues"
				ok = true
		LEVER_MODULE_ABANDONMENT:
			if tower == null:
				immediate_summary = "REJECTED: tower unavailable"
			else:
				var coords: Dictionary = _resolve_module_target(payload, tower)
				if coords.is_empty():
					immediate_summary = "REJECTED: module not found"
				else:
					var f: int = int(coords.get("f", -1))
					var x: int = int(coords.get("x", -1))
					var y: int = int(coords.get("y", -1))
					var key := _module_key(f, x, y)
					if abandoned_modules.has(key):
						immediate_summary = "REJECTED: module already abandoned"
					else:
						abandoned_modules[key] = true
						tower.set_module_enabled(f, x, y, false)
						sanitized = {"f": f, "x": x, "y": y}
						immediate_summary = "module disabled"
						debts_summary = "irreversible loss"
						ok = true
		LEVER_EMERGENCY_CONVERSION:
			var from_key: String = str(payload.get("from", ""))
			var to_key: String = str(payload.get("to", ""))
			var amount: int = int(payload.get("amount", 0))
			if from_key == "" or to_key == "":
				immediate_summary = "REJECTED: missing resource"
			elif from_key == to_key:
				immediate_summary = "REJECTED: invalid target"
			elif not _is_convertible_resource(from_key) or not _is_convertible_resource(to_key):
				immediate_summary = "REJECTED: unsupported resource"
			elif amount <= 0:
				immediate_summary = "REJECTED: invalid amount"
			elif int(conversion_burn_counts.get(from_key, 0)) >= CONVERSION_BURN_THRESHOLD:
				immediate_summary = "REJECTED: option burned out"
			else:
				sanitized = {"from": from_key, "to": to_key, "amount": amount}
				pending_conversions.append(sanitized.duplicate())
				immediate_summary = "conversion queued"
				debts_summary = "scar accrues"
				ok = true
		_:
			immediate_summary = "REJECTED: unknown lever"

	if ok:
		_update_lever_hourly_states()
	_log_lever_event(day, lever_id, sanitized, immediate_summary, debts_summary)
	return ok

func _log_lever_event(
	sim_day: int,
	lever_id: String,
	payload: Dictionary,
	immediate_effects_summary: String,
	debts_applied: String
) -> void:
	var entry := {
		"day": sim_day,
		"lever_id": lever_id,
		"payload": payload,
		"immediate_effects_summary": immediate_effects_summary,
		"debts_applied": debts_applied,
	}
	lever_events.append(entry)
	var message := _format_lever_message(lever_id, payload, immediate_effects_summary, debts_applied)
	var debug_entry := entry.duplicate(true)
	debug_entry["id"] = _next_event_id()
	debug_entry["type"] = "LEVER_EVENT"
	debug_entry["severity"] = "debug"
	debug_entry["visibility"] = "dev_only"
	debug_entry["message"] = message
	debug_entry["source"] = "lever"
	events.append(debug_entry)

func _format_lever_message(
	lever_id: String,
	payload: Dictionary,
	immediate_effects_summary: String,
	debts_applied: String
) -> String:
	var parts: Array[String] = []
	if immediate_effects_summary != "":
		parts.append(immediate_effects_summary)
	if debts_applied != "":
		parts.append(debts_applied)
	if parts.is_empty():
		if payload != null and not payload.is_empty():
			var payload_parts: Array[String] = []
			var payload_keys := payload.keys()
			payload_keys.sort()
			for key in payload_keys:
				var payload_value: Variant = payload.get(key)
				payload_parts.append("%s=%s" % [key, str(payload_value)])
			parts.append("payload {" + ", ".join(payload_parts) + "}")
		else:
			parts.append(lever_id)
	return ", ".join(parts)

func _next_event_id() -> int:
	var next_id := _event_sequence
	_event_sequence += 1
	return next_id

func _emit_event(
	event_type: String,
	message: String,
	severity: String,
	visibility: String,
	payload: Dictionary,
	source: String,
	event_day: int,
	event_hour: int,
	include_hour: bool
) -> void:
	var day_value := event_day
	if day_value < 0:
		day_value = day
	var entry := {
		"id": _next_event_id(),
		"type": event_type,
		"day": day_value,
		"message": message,
		"severity": severity,
		"visibility": visibility,
	}
	if include_hour:
		var hour_value := event_hour
		if hour_value < 0:
			hour_value = hour_of_day
		entry["hour"] = hour_value
	if source != "":
		entry["source"] = source
	if payload != null and not payload.is_empty():
		entry["payload"] = payload
	events.append(entry)

func _emit_threat_band_events(pre_threat: int, post_threat: int, sim_day: int) -> void:
	if post_threat <= pre_threat:
		return
	for threshold in THREAT_EVENT_THRESHOLDS:
		if pre_threat < threshold and post_threat >= threshold:
			var next_threshold := _next_threshold(THREAT_EVENT_THRESHOLDS, threshold)
			var forecast := "Next escalation at %d." % next_threshold if next_threshold >= 0 else "No further escalation detected."
			var message := "External interest confirmed.\nThreat escalating (%d). Pattern shift detected.\nForecast: %s" % [
				post_threat,
				forecast,
			]
			var payload := {
				"threshold": threshold,
				"value": post_threat,
			}
			if next_threshold >= 0:
				payload["next_threshold"] = next_threshold
			_emit_event(
				"THREAT_BAND_CROSSED",
				message,
				"warn",
				"sticky",
				payload,
				"threat",
				sim_day,
				hour_of_day,
				true
			)

func _emit_morale_band_events(pre_morale: int, post_morale: int, sim_day: int) -> void:
	for threshold in MORALE_EVENT_THRESHOLDS:
		if pre_morale >= threshold and post_morale < threshold:
			var message := "Morale critical (%d). Compliance is voluntary now.\nForecast: Recovery is unlikely under current policies." % post_morale
			var payload := {
				"threshold": threshold,
				"value": post_morale,
			}
			_emit_event(
				"MORALE_BAND_CROSSED",
				message,
				"warn",
				"sticky",
				payload,
				"morale",
				sim_day,
				hour_of_day,
				true
			)

func _emit_materials_exhausted_event(pre_materials: int, post_materials: int, sim_day: int) -> void:
	if pre_materials > 0 and post_materials <= 0:
		var message := "Materials depleted.\nForecast: Failures will become permanent."
		_emit_event(
			"MATERIALS_EXHAUSTED",
			message,
			"warn",
			"sticky",
			{},
			"materials",
			sim_day,
			hour_of_day,
			true
		)

func _emit_maintenance_shortfall_event(sim_day: int, growth: Dictionary) -> void:
	var shortfall_value: Variant = growth.get("maintenance_shortfall", false)
	var shortfall := bool(shortfall_value)
	if shortfall and not _last_maintenance_shortfall:
		var materials_before_value: Variant = growth.get("materials_before", 0)
		var deficit_value: Variant = growth.get("maintenance_deficit", 0)
		var materials_before := int(materials_before_value)
		var deficit := int(deficit_value)
		var message := "Maintenance shortfall. Spares exhausted.\nForecast: Repairs will require cannibalization."
		var payload := {
			"value": materials_before,
			"deficit": deficit,
		}
		_emit_event(
			"MAINTENANCE_SHORTFALL",
			message,
			"warn",
			"sticky",
			payload,
			"maintenance",
			sim_day,
			hour_of_day,
			true
		)
	_last_maintenance_shortfall = shortfall

func _emit_attention_debt_summary() -> void:
	if ATTENTION_SUMMARY_INTERVAL_HOURS <= 0:
		return
	if hour_of_day % ATTENTION_SUMMARY_INTERVAL_HOURS != 0:
		return
	if hour_index == _last_attention_summary_hour_index:
		return
	var total: float = expedition_attention
	var delta: float = total - _last_attention_summary_value
	_last_attention_summary_hour_index = hour_index
	_last_attention_summary_value = total
	if delta <= 0.0:
		return
	if day <= INTRO_QUIET_DAYS:
		return
	var snapped_total: float = snapped(total, SIM_FLOAT_SNAP)
	var snapped_delta: float = snapped(delta, SIM_FLOAT_SNAP)
	var message: String = ATTENTION_NEUTRAL_MESSAGE
	var severity: String = "info"
	if visibility_triggered:
		if snapped_total < ATTENTION_DEBT_LOW_THRESHOLD:
			message = ATTENTION_LOW_MESSAGE
		elif snapped_total < ATTENTION_DEBT_HIGH_THRESHOLD:
			message = ATTENTION_WARNING_MESSAGE
			severity = "warn"
		else:
			message = ATTENTION_HIGH_MESSAGE
			severity = "warn"
	var payload := {
		"delta_period": snapped_delta,
		"total": snapped_total,
		"source": "expedition",
		"visibility_triggered": visibility_triggered,
	}
	_emit_event(
		"ATTENTION_DEBT_SUMMARY",
		message,
		severity,
		"player_feed",
		payload,
		"expedition",
		day,
		hour_of_day,
		true
	)

func _mark_visibility_triggered() -> void:
	if visibility_triggered:
		return
	visibility_triggered = true

func _visibility_hook_floor_build() -> void:
	# Reserved for future floor construction hooks.
	pass

func _visibility_hook_comms_enabled() -> void:
	# Reserved for future comms module toggles.
	pass

func _visibility_hook_extra_rations_policy() -> void:
	# Reserved for future extra rations policy hooks.
	pass

func _emit_lever_state_changes() -> void:
	if _lever_active_state.is_empty():
		for lever_id in LEVER_STATE_TRACKED:
			_lever_active_state[lever_id] = _is_lever_active(lever_id)
		return
	for lever_id in LEVER_STATE_TRACKED:
		var was_active_value: Variant = _lever_active_state.get(lever_id, false)
		var was_active := bool(was_active_value)
		var is_active := _is_lever_active(lever_id)
		if was_active == is_active:
			continue
		_lever_active_state[lever_id] = is_active
		var lever_name := _lever_display_name(lever_id)
		var state := "active" if is_active else "inactive"
		var message := "%s engaged. Costs will accumulate." % lever_name if is_active else "%s ended. Debts remain." % lever_name
		var payload := {
			"lever_id": lever_id,
			"state": state,
		}
		_emit_event(
			"LEVER_STATE_CHANGED",
			message,
			"info",
			"toast",
			payload,
			lever_id,
			day,
			hour_of_day,
			true
		)

func _is_lever_active(lever_id: String) -> bool:
	match lever_id:
		LEVER_RATION_HARDENING:
			return ration_hardening_hours_left > 0
		LEVER_LABOR_OVERDRIVE:
			return labor_overdrive_hours_left > 0
		LEVER_EXPEDITION_COMPRESSION:
			return expedition_compression_hours_left > 0
		LEVER_INFORMATION_THROTTLING:
			return info_throttle_hours_left > 0
		_:
			return false

func _lever_display_name(lever_id: String) -> String:
	var name_value: Variant = LEVER_DISPLAY_NAMES.get(lever_id, "")
	var lever_name := str(name_value)
	return lever_name if lever_name != "" else lever_id.capitalize()

func _next_threshold(thresholds: Array[int], current: int) -> int:
	for threshold in thresholds:
		if threshold > current:
			return threshold
	return -1

func _module_key(f: int, x: int, y: int) -> String:
	return "%d:%d:%d" % [f, x, y]

func _is_module_online(floor_idx: int, x: int, y: int) -> bool:
	if tower == null:
		return false
	if not tower.has_cell(floor_idx, x, y):
		return false
	if _is_module_abandoned(floor_idx, x, y):
		return false
	return tower.is_module_enabled(floor_idx, x, y)

func _module_snapshot_filtered_deltas(raw: Dictionary) -> Dictionary:
	var filtered: Dictionary = {}
	if raw == null:
		return filtered
	var keys := raw.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		var value: Variant = raw.get(key, null)
		if value == null:
			continue
		var numeric: int = 0
		if value is int:
			numeric = int(value)
		elif value is float:
			numeric = int(value)
		else:
			continue
		if numeric == 0:
			continue
		filtered[key] = numeric
	return filtered

func _refresh_module_snapshots(power_map: Dictionary) -> void:
	if power_map == null:
		power_map = {}
	var snapshots: Array[Dictionary] = []
	if tower == null or db == null:
		_last_module_snapshots = snapshots
		return
	for floor_idx in range(tower.floor_count()):
		var grid: Array = tower.floors[floor_idx] as Array
		if grid == null:
			continue
		for y in range(tower.height):
			var row: Array = grid[y] as Array
			if row == null:
				continue
			for x in range(tower.width):
				var module_id: Variant = row[x]
				if module_id == null:
					continue
				var def := db.get_def(str(module_id))
				if def == null:
					continue
				var key := _module_key(floor_idx, x, y)
				var run_entry: Dictionary = {}
				if power_map.has(key) and power_map[key] is Dictionary:
					run_entry = power_map[key]
				var snapshot: Dictionary = {
					"id": key,
					"type": def.id,
					"name": def.name,
					"floor": floor_idx,
					"x": x,
					"y": y,
					"powered": bool(run_entry.get("powered", false)),
					"online": _is_module_online(floor_idx, x, y),
				}
				var deltas_candidate: Variant = run_entry.get("deltas", null)
				if deltas_candidate is Dictionary:
					var filtered := _module_snapshot_filtered_deltas(deltas_candidate)
					if not filtered.is_empty():
						snapshot["deltas"] = filtered
				snapshots.append(snapshot)
	_last_module_snapshots = snapshots

func module_snapshots() -> Array[Dictionary]:
	var copies: Array[Dictionary] = []
	for snapshot in _last_module_snapshots:
		if snapshot is Dictionary:
			copies.append(snapshot.duplicate(true))
		else:
			copies.append({})
	return copies

func _parse_module_instance_id(instance_id: String) -> Dictionary:
	if instance_id == "":
		return {}
	var parts: PackedStringArray = instance_id.split(":")
	if parts.size() != 3:
		return {}
	return {"f": int(parts[0]), "x": int(parts[1]), "y": int(parts[2])}

func _resolve_module_target(payload: Dictionary, sim_tower: Tower) -> Dictionary:
	if payload.has("f") and payload.has("x") and payload.has("y"):
		var coords: Dictionary = _payload_coords(payload)
		if sim_tower.has_cell(int(coords["f"]), int(coords["x"]), int(coords["y"])):
			return coords
	if payload.has("module_instance_id"):
		var parsed: Dictionary = _parse_module_instance_id(str(payload.get("module_instance_id", "")))
		if parsed.is_empty():
			return {}
		if sim_tower.has_cell(int(parsed["f"]), int(parsed["x"]), int(parsed["y"])):
			return parsed
	if payload.has("module_id"):
		var target_id: String = str(payload.get("module_id", ""))
		if target_id == "":
			return {}
		for f in range(sim_tower.floors.size()):
			var floor_data: Variant = sim_tower.floors[f]
			if floor_data == null or not (floor_data is Array):
				continue
			var grid: Array = floor_data as Array
			for y in range(sim_tower.height):
				if y < 0 or y >= grid.size():
					continue
				var row_candidate: Variant = grid[y]
				if row_candidate == null or not (row_candidate is Array):
					continue
				var row: Array = row_candidate as Array
				for x in range(sim_tower.width):
					if x < 0 or x >= row.size():
						continue
					if row[x] == target_id:
						return {"f": f, "x": x, "y": y}
	return {}

func _is_module_abandoned(f: int, x: int, y: int) -> bool:
	return abandoned_modules.has(_module_key(f, x, y))

func _is_convertible_resource(key: String) -> bool:
	return key in CONVERTIBLE_RESOURCES

func _simulate_days(days_to_run: int, _run_seed: int) -> Array[String]:
	_reset_policies_and_pools()
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
		var incidents := _step_day_core(sim_day, _run_seed, sim_tower, sim_res, sim_db)
		# Note: seed is currently informational only (no RNG wired yet).
		output.append(_format_log_line(sim_day, _run_seed, sim_res, incidents, _last_obs_tokens))
	return output

func _step_day_for(sim_tower: Tower, sim_res: Resources, sim_db: ModuleDB) -> void:
	_step_day_core(day, sim_seed, sim_tower, sim_res, sim_db)

func _apply_module_deltas_stably(sim_res: Resources, deltas: Dictionary) -> void:
	for key in MODULE_DELTA_KEYS:
		if deltas.has(key):
			var raw: Variant = deltas[key]
			assert(raw != null, "Module delta missing value for '%s'." % key)
			assert(raw is int or raw is float, "Module delta for '%s' must be numeric." % key)
			sim_res.add_delta(key, int(raw))

func _module_inputs_available(sim_res: Resources, inputs: Dictionary) -> bool:
	if inputs == null:
		return true
	var keys := inputs.keys()
	keys.sort()
	for key in keys:
		var amount_value: Variant = inputs.get(key, 0)
		var amount := int(amount_value)
		if amount <= 0:
			continue
		var current_amount: int = sim_res.get_amount(key)
		if current_amount < amount:
			return false
	return true

func _consume_module_inputs(sim_res: Resources, inputs: Dictionary) -> void:
	if inputs == null:
		return
	var keys := inputs.keys()
	keys.sort()
	for key in keys:
		var amount_value: Variant = inputs.get(key, 0)
		var amount := int(amount_value)
		if amount == 0:
			continue
		var current_amount: int = sim_res.get_amount(key)
		sim_res.set_amount(key, current_amount - amount)

func _evaluate_incidents(sim_day: int, run_seed: int, sim_res: Resources) -> Array[String]:
	var incidents: Array[String] = []
	var incident_seed := int(run_seed) * RNG_BASE_MULTIPLIER + int(sim_day) * RNG_DAY_MULTIPLIER
	var tracker := _create_rng_tracker(sim_day, PHASE_INCIDENTS, "incident_rolls", RNG_OFFSET_INCIDENTS, incident_seed)

	# INCIDENT_DEFS order is load-bearing for determinism; do not reorder.
	for incident_def in IncidentDefsRef.INCIDENT_DEFS:
		var threshold: int = int(incident_def.get("threshold", 0))
		if sim_res.threat < threshold:
			continue

		var chance: float = float(incident_def.get("chance", 0.0))
		var roll: float = _rng_randf(tracker)
		if roll <= chance:
			var incident_id: String = str(incident_def.get("id", "unknown"))
			var severity: String = str(incident_def.get("severity", "na"))
			# Log-only for now (per EVENTS contract: no state mutation without approval).
			incidents.append("%s[%s]" % [incident_id, severity])

	return incidents

func _evaluate_threat_thresholds(pre_threat: int, post_threat: int) -> Array[String]:
	var markers: Array[String] = []
	for threshold in IncidentDefsRef.THREAT_THRESHOLDS:
		if pre_threat < threshold and post_threat >= threshold:
			markers.append("thr@%d" % threshold)
	return markers

func _merge_incident_lists(a: Array[String], b: Array[String]) -> Array[String]:
	var merged: Array[String] = []
	merged.append_array(a)
	merged.append_array(b)
	return merged

func _obs_push(obs: Array[String], token: String) -> void:
	if token == "":
		return
	if token in obs:
		return
	obs.append(token)

func _scale_delta_for_workforce(delta: int, multiplier: float) -> int:
	if delta == 0:
		return 0
	if multiplier <= 0.0:
		return 0
	if multiplier >= 1.0:
		return delta
	if delta > 0:
		return int(floor(float(delta) * multiplier))
	return int(ceil(float(delta) * multiplier))

func _apply_lever_output_modifiers(deltas: Dictionary) -> Dictionary:
	if (
		labor_output_multiplier_today == 1.0
		and info_misalloc_multiplier_today == 1.0
		and ration_recovery_multiplier_today == 1.0
	):
		return deltas
	var adjusted: Dictionary = {}
	var keys := deltas.keys()
	keys.sort()
	for key in keys:
		var value: int = int(deltas[key])
		if value > 0:
			var multiplier := labor_output_multiplier_today * info_misalloc_multiplier_today
			if key == "food" or key == "water":
				multiplier *= ration_recovery_multiplier_today
			value = int(floor(float(value) * multiplier))
		adjusted[key] = value
	return adjusted

func _scale_deltas_for_workforce(deltas: Dictionary, multiplier: float) -> Dictionary:
	var effective_multiplier := multiplier
	if labor_efficiency_cap_today < effective_multiplier:
		effective_multiplier = labor_efficiency_cap_today
	if effective_multiplier >= 1.0:
		return deltas
	var scaled: Dictionary = {}
	var keys := deltas.keys()
	keys.sort()
	for key in keys:
		scaled[key] = _scale_delta_for_workforce(int(deltas[key]), effective_multiplier)
	return scaled

func _recompute_expedition_heat() -> void:
	var weighted: int = expedition_count_total + (expedition_streak * 3) + (expedition_recent_score * 2)
	expedition_heat = int(float(weighted) / 4.0)

func _start_expedition_day() -> void:
	expedition_happened_today = false
	expedition_commands_today = 0
	if expedition_recent_score > 0:
		expedition_recent_score = max(expedition_recent_score - EXPEDITION_RECENT_DECAY, 0)
	_recompute_expedition_heat()

func _phase_levers(sim_day: int, sim_tower: Tower, sim_res: Resources, obs: Array[String]) -> void:
	# Phase -1: levers (policy effects + queued conversions)
	_update_lever_hourly_states()
	ration_consumption_multiplier_today = 1.0
	ration_recovery_multiplier_today = 1.0
	labor_output_multiplier_today = 1.0
	labor_efficiency_cap_today = 1.0
	expedition_yield_bonus_per_crew_today = 0
	expedition_attention_bonus_per_trip_today = 0
	info_throttle_morale_factor_today = 1.0
	info_misalloc_multiplier_today = 1.0
	lever_threat_bonus_today = 0

	var ration_active_today := ration_hardening_hours_left > 0
	var labor_active_today := labor_overdrive_hours_left > 0
	var expedition_active_today := expedition_compression_hours_left > 0
	var info_active_today := info_throttle_hours_left > 0
	var conversions_processed_today := false

	if not abandoned_modules.is_empty():
		var keys: Array = abandoned_modules.keys()
		# NOTE: abandoned_modules MUST NOT be mutated during iteration.
		keys.sort()
		for key in keys:
			var parts: PackedStringArray = str(key).split(":")
			if parts.size() != 3:
				continue
			var f: int = int(parts[0])
			var x: int = int(parts[1])
			var y: int = int(parts[2])
			if sim_tower.has_cell(f, x, y):
				sim_tower.set_module_enabled(f, x, y, false)
				_obs_push(obs, "ABANDONED@%d:%d:%d" % [f, x, y])

	if ration_active_today:
		var hard := ration_hardening_mode == "hard"
		var multiplier := RATION_HARDENING_HARD_MULT if hard else RATION_HARDENING_SOFT_MULT
		ration_consumption_multiplier_today = multiplier
		var scar_gain := RATION_SCAR_PER_DAY_HARD if hard else RATION_SCAR_PER_DAY_SOFT
		ration_scar += scar_gain
		ration_scar = snapped(ration_scar, SIM_FLOAT_SNAP)
		_obs_push(obs, "LEVER_RATION@%s" % ration_hardening_mode)
		_log_lever_event(
			sim_day,
			LEVER_RATION_HARDENING,
			{
				"mode": ration_hardening_mode,
				"hours_left": ration_hardening_hours_left,
				"ticks_left": ration_hardening_hours_left,
			},
			"consumption x%0.2f" % multiplier,
			"scar=%.2f" % ration_scar
		)

	if ration_scar > 0.0:
		var recovery_mult := 1.0 - (ration_scar * RATION_SCAR_RECOVERY_MULT)
		ration_recovery_multiplier_today = clamp(recovery_mult, RATION_RECOVERY_MIN_MULT, 1.0)
		var ceiling_penalty := ration_scar * RATION_SCAR_CEILING_PENALTY
		if ceiling_penalty > 0.0:
			sim_res.morale_ceiling = max(sim_res.morale_ceiling - ceiling_penalty, 0.0)
			_obs_push(obs, "RATION_SCAR@%0.2f" % ration_scar)
		if not ration_active_today:
			_log_lever_event(
				sim_day,
				LEVER_RATION_HARDENING,
				{"scar": ration_scar},
				"scar drag",
				"recovery reduced"
			)

	if labor_active_today:
		var intensity := labor_overdrive_intensity
		labor_output_multiplier_today = 1.0 + (float(intensity) * LABOR_OVERDRIVE_MULT_PER_LEVEL)
		labor_scar += float(intensity) * LABOR_SCAR_PER_DAY
		labor_scar = snapped(labor_scar, SIM_FLOAT_SNAP)
		# Hourly countdown is derived from hour_index; no manual decrement needed.
		_obs_push(obs, "LEVER_LABOR@%d" % intensity)
		_log_lever_event(
			sim_day,
			LEVER_LABOR_OVERDRIVE,
			{
				"intensity": intensity,
				"hours_left": labor_overdrive_hours_left,
				"ticks_left": labor_overdrive_hours_left,
			},
			"output x%0.2f" % labor_output_multiplier_today,
			"scar=%.2f" % labor_scar
		)

	if labor_scar > 0.0:
		var eff_cap := 1.0 - (labor_scar * LABOR_SCAR_EFFICIENCY_MULT)
		labor_efficiency_cap_today = clamp(eff_cap, LABOR_EFFICIENCY_MIN, 1.0)
		var threat_bonus := int(ceil(labor_scar * LABOR_SCAR_THREAT_MULT))
		if threat_bonus > 0:
			lever_threat_bonus_today += threat_bonus
			_obs_push(obs, "LABOR_SCAR@%0.2f" % labor_scar)
		if not labor_active_today:
			_log_lever_event(
				sim_day,
				LEVER_LABOR_OVERDRIVE,
				{"scar": labor_scar},
				"scar drag",
				"efficiency capped"
			)

	if expedition_active_today:
		var intensity := expedition_compression_intensity
		expedition_yield_bonus_per_crew_today = intensity * EXPEDITION_COMPRESSION_YIELD_PER_CREW
		expedition_attention_bonus_per_trip_today = intensity * EXPEDITION_ATTENTION_PER_TRIP
		expedition_attention += float(intensity * EXPEDITION_ATTENTION_PER_DAY)
		expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)
		# Hourly countdown is derived from hour_index; no manual decrement needed.
		_obs_push(obs, "LEVER_EXPEDITION@%d" % intensity)
		_log_lever_event(
			sim_day,
			LEVER_EXPEDITION_COMPRESSION,
			{
				"intensity": intensity,
				"hours_left": expedition_compression_hours_left,
				"ticks_left": expedition_compression_hours_left,
			},
			"yield bonus per crew=%d" % expedition_yield_bonus_per_crew_today,
			"attention=%.1f" % expedition_attention
		)

	if expedition_attention > 0.0:
		var attn_threat := int(ceil(expedition_attention * EXPEDITION_ATTENTION_THREAT_MULT))
		if attn_threat > 0:
			lever_threat_bonus_today += attn_threat
			_obs_push(obs, "ATTN@%d" % int(ceil(expedition_attention)))
		if not expedition_active_today:
			_log_lever_event(
				sim_day,
				LEVER_EXPEDITION_COMPRESSION,
				{"attention": expedition_attention},
				"attention drag",
				"threat pressure"
			)

	if info_active_today:
		var level := info_throttle_level
		info_throttle_morale_factor_today = clamp(
			1.0 - (float(level) * INFO_THROTTLE_MORALE_FACTOR_PER_LEVEL),
			INFO_THROTTLE_MORALE_MIN_FACTOR,
			1.0
		)
		info_misalloc_multiplier_today = clamp(
			1.0 - (float(level) * INFO_THROTTLE_MISALLOC_PER_LEVEL),
			INFO_THROTTLE_MISALLOC_MIN,
			1.0
		)
		# Hourly countdown is derived from hour_index; no manual decrement needed.
		_obs_push(obs, "LEVER_INFO@%d" % level)
		_log_lever_event(
			sim_day,
			LEVER_INFORMATION_THROTTLING,
			{
				"level": level,
				"hours_left": info_throttle_hours_left,
				"ticks_left": info_throttle_hours_left,
			},
			"morale damp x%0.2f" % info_throttle_morale_factor_today,
			"backlog=%0.2f" % info_throttle_backlog
		)
	elif info_throttle_backlog > 0.0:
		var shock := int(ceil(info_throttle_backlog))
		if shock > 0:
			sim_res.morale -= shock
			sim_res.threat += int(ceil(float(shock) * INFO_THROTTLE_SHOCK_THREAT_MULT))
			_obs_push(obs, "INFO_SHOCK@%d" % shock)
			_log_lever_event(
				sim_day,
				LEVER_INFORMATION_THROTTLING,
				{"shock": shock},
				"backlog released",
				"shock applied"
			)
		# Clear after application to prevent double-apply on future phases.
		info_throttle_backlog = 0.0

	if not pending_conversions.is_empty():
		conversions_processed_today = true
		var queue: Array = pending_conversions.duplicate()
		pending_conversions.clear()
		for entry in queue:
			var from_key: String = str(entry.get("from", ""))
			var to_key: String = str(entry.get("to", ""))
			var amount: int = int(entry.get("amount", 0))
			if amount <= 0:
				_log_lever_event(sim_day, LEVER_EMERGENCY_CONVERSION, entry, "REJECTED: invalid amount", "")
				continue
			if not _is_convertible_resource(from_key) or not _is_convertible_resource(to_key):
				_log_lever_event(sim_day, LEVER_EMERGENCY_CONVERSION, entry, "REJECTED: unsupported resource", "")
				continue
			if int(conversion_burn_counts.get(from_key, 0)) >= CONVERSION_BURN_THRESHOLD:
				_log_lever_event(sim_day, LEVER_EMERGENCY_CONVERSION, entry, "REJECTED: option burned out", "")
				continue
			var available: int = sim_res.get_amount(from_key)
			if available <= 0:
				_log_lever_event(sim_day, LEVER_EMERGENCY_CONVERSION, entry, "REJECTED: insufficient", "")
				continue
			var used: int = int(min(amount, available))
			var efficiency: float = float(
				max(
					CONVERSION_EFFICIENCY_MIN,
					1.0 - (float(conversion_scar) * CONVERSION_EFFICIENCY_LOSS),
				)
			)
			var produced := int(floor(float(used) * efficiency))
			sim_res.set_amount(from_key, available - used)
			var target_before: int = sim_res.get_amount(to_key)
			sim_res.set_amount(to_key, target_before + produced)
			conversion_scar += CONVERSION_SCAR_PER_USE
			conversion_burn_counts[from_key] = int(conversion_burn_counts.get(from_key, 0)) + 1
			_obs_push(obs, "CONVERT@%s>%s@%d" % [from_key, to_key, produced])
			_log_lever_event(
				sim_day,
				LEVER_EMERGENCY_CONVERSION,
				{"from": from_key, "to": to_key, "amount": used},
				"converted %d" % produced,
				"scar=%d" % conversion_scar
			)

	if conversion_scar > 0:
		var conversion_penalty := float(conversion_scar) * CONVERSION_CEILING_PENALTY
		if conversion_penalty > 0.0:
			sim_res.morale_ceiling = max(sim_res.morale_ceiling - conversion_penalty, 0.0)
		if not conversions_processed_today:
			_log_lever_event(
				sim_day,
				LEVER_EMERGENCY_CONVERSION,
				{"scar": conversion_scar},
				"scar drag",
				"ceiling reduced"
			)

func _phase_commands(_sim_day: int, _run_seed: int, sim_tower: Tower, sim_res: Resources, obs: Array[String]) -> void:
	# Start-of-day deterministic command application. Order is enqueue order.
	assert(sim_res.population >= 0, "Population must be non-negative at phase entry.")
	expedition_crew_today = 0
	expedition_threat_today = 0
	expedition_morale_penalty_today = 0
	ration_morale_penalty_today = 0
	ration_threat_penalty_today = 0
	workforce_multiplier_today = 1.0
	_start_expedition_day()

	for cmd in _command_queue:
		if cmd == null:
			continue
		match cmd.type:
			CMD_SET_RATIONS:
				_cmd_set_rations(cmd.payload, sim_res, obs)
			CMD_SET_MODULE_ENABLED:
				_cmd_set_module_enabled(cmd.payload, sim_tower, obs)
			CMD_SET_MODULE_PRIORITY:
				_cmd_set_module_priority(cmd.payload, sim_tower, obs)
			CMD_EXPEDITION:
				_cmd_expedition(cmd.payload, _sim_day, _run_seed, sim_res, obs)
			CMD_TRADE:
				_cmd_trade(cmd.payload, sim_res, obs, _sim_day)
			_:
				_obs_push(obs, "CMD:UNKNOWN")

	if not expedition_happened_today:
		if expedition_streak != 0:
			expedition_streak = 0
			_recompute_expedition_heat()

	# Persistent policies emit ongoing observation tokens.
	if food_ration < 1.0:
		_obs_push(obs, "RATION_FOOD@%0.2f" % food_ration)
	if water_ration < 1.0:
		_obs_push(obs, "RATION_WATER@%0.2f" % water_ration)

	# Ration pressure is deterministic and uses existing morale/threat hooks.
	var food_shortfall: float = max(0.0, 1.0 - food_ration)
	var water_shortfall: float = max(0.0, 1.0 - water_ration)
	var shortfall_score: float = food_shortfall + water_shortfall
	if shortfall_score > 0.0:
		ration_morale_penalty_today = int(ceil(shortfall_score * 2.0))
		ration_threat_penalty_today = int(ceil(shortfall_score * 1.0))
		_obs_push(obs, "RATION_PRESSURE@%d" % ration_morale_penalty_today)

	# Crew out reduces same-day workforce effectiveness; clamp safely.
	if sim_res.population > 0 and expedition_crew_today > 0:
		var crew_clamped: int = int(clamp(expedition_crew_today, 0, sim_res.population))
		workforce_multiplier_today = clamp(
			float(sim_res.population - crew_clamped) / float(sim_res.population),
			0.0,
			1.0
		)
		expedition_morale_penalty_today = int(ceil(float(crew_clamped) * 0.2))
		_obs_push(obs, "CREW_OUT@%d" % crew_clamped)
		if expedition_morale_penalty_today > 0:
			_obs_push(obs, "EXPEDITION_STRAIN@%d" % expedition_morale_penalty_today)

	_command_queue.clear()

func _cmd_set_rations(payload: Dictionary, _sim_res: Resources, obs: Array[String]) -> void:
	var next_food: float = float(payload.get("food", food_ration))
	var next_water: float = float(payload.get("water", water_ration))
	food_ration = clamp(next_food, 0.0, 1.0)
	water_ration = clamp(next_water, 0.0, 1.0)
	_obs_push(obs, "CMD:RATION_SET")

func _payload_coords(payload: Dictionary) -> Dictionary:
	return {
		"f": int(payload.get("f", -1)),
		"x": int(payload.get("x", -1)),
		"y": int(payload.get("y", -1)),
	}

func _cmd_set_module_enabled(payload: Dictionary, sim_tower: Tower, obs: Array[String]) -> void:
	var coords: Dictionary = _payload_coords(payload)
	var f: int = int(coords["f"])
	var x: int = int(coords["x"])
	var y: int = int(coords["y"])
	var enabled: bool = bool(payload.get("enabled", true))
	if not sim_tower.has_cell(f, x, y):
		_obs_push(obs, "CMD:MODULE_NOT_FOUND")
		return
	if enabled and _is_module_abandoned(f, x, y):
		_obs_push(obs, "CMD:MODULE_ABANDONED")
		return
	sim_tower.set_module_enabled(f, x, y, enabled)
	if enabled:
		_obs_push(obs, "CMD:ENABLE_MODULE")
	else:
		_obs_push(obs, "CMD:DISABLE_MODULE")
	_obs_push(obs, "CMD:MODULE_ENABLED@%d:%d:%d:%d" % [f, x, y, int(enabled)])

func _cmd_set_module_priority(payload: Dictionary, sim_tower: Tower, obs: Array[String]) -> void:
	var coords: Dictionary = _payload_coords(payload)
	var f: int = int(coords["f"])
	var x: int = int(coords["x"])
	var y: int = int(coords["y"])
	if not sim_tower.has_cell(f, x, y):
		_obs_push(obs, "CMD:MODULE_NOT_FOUND")
		return
	var priority_value: Variant = payload.get("priority", null)
	if priority_value == null:
		sim_tower.clear_module_priority_override(f, x, y)
		_obs_push(obs, "CMD:PRIORITY_CLEAR")
		return
	var priority: int = int(clamp(int(priority_value), 0, 100))
	sim_tower.set_module_priority_override(f, x, y, priority)
	_obs_push(obs, "CMD:PRIORITY_SET")
	_obs_push(obs, "PRIORITY@%d:%d:%d:%d" % [f, x, y, priority])

func _rng_seed_for_expedition(run_seed: int, sim_day: int, total_count: int, day_index: int) -> int:
	# Local, deterministic RNG seed. No global RNG mutation.
	var accumulator: int = int(run_seed)
	accumulator += int(sim_day) * RNG_DAY_MULTIPLIER
	accumulator += int(total_count) * 83492791
	accumulator += int(day_index) * 2654435761
	accumulator = int((accumulator * RNG_BASE_MULTIPLIER) & RNG_CONTEXT_SEED_MASK)
	return accumulator

func _schedule_expedition_lag(
	sim_day: int,
	run_seed: int,
	obs: Array[String],
	day_index: int,
	heat_at_schedule: int,
	total_count: int
) -> void:
	var expedition_seed: int = _rng_seed_for_expedition(run_seed, sim_day, total_count, day_index)
	var tracker := _create_rng_tracker(sim_day, PHASE_EXPEDITIONS, "expedition_lag", RNG_OFFSET_EXPEDITIONS, expedition_seed)

	var delay: int = 3 + int(_rng_randi(tracker) % 3) # 3..5 inclusive
	if heat_at_schedule >= EXPEDITION_HEAT_DELAY_THRESHOLD:
		delay = 3 + int(_rng_randi(tracker) % 2) # 3..4 inclusive

	var retaliation_chance: int = 50 + min(heat_at_schedule * EXPEDITION_KIND_BIAS_PER_HEAT, EXPEDITION_KIND_BIAS_CAP)
	var kind_roll: int = int(_rng_randi(tracker) % 100)
	var kind: String = "RETALIATION_RISK" if kind_roll < retaliation_chance else "SUPPLY_CHAIN_FRICTION"

	var magnitude_base: int = 0
	if kind == "RETALIATION_RISK":
		magnitude_base = 2 + int(_rng_randi(tracker) % 5) # 2..6 threat
	else:
		magnitude_base = 1 + int(_rng_randi(tracker) % 3) # 1..3 morale
	var heat_bonus: int = int(float(heat_at_schedule) / float(EXPEDITION_MAG_HEAT_DIV))
	var magnitude: int = min(magnitude_base + heat_bonus, EXPEDITION_MAG_CAP)

	var entry := {
		"due_day": sim_day + delay,
		"kind": kind,
		"magnitude": magnitude,
		"heat": heat_at_schedule,
		"tags": ["EXPEDITION_LAG"],
		"idx": _delayed_insertion_counter,
	}
	_delayed_insertion_counter += 1
	_delayed_consequence_queue.append(entry)

	_obs_push(obs, "EXPEDITION_LAG_SCHEDULED@%s@D+%d@M%d@heat=%d" % [kind, delay, magnitude, heat_at_schedule])

func _cmd_expedition(payload: Dictionary, sim_day: int, run_seed: int, sim_res: Resources, obs: Array[String]) -> void:
	var target: String = str(payload.get("target", "materials"))
	var requested_crew: int = int(payload.get("crew", 1))
	var crew: int = int(clamp(requested_crew, 0, sim_res.population))
	_obs_push(obs, "CMD:EXPEDITION@%s" % target)
	if crew <= 0:
		_obs_push(obs, "EXPEDITION_ABORT@NO_CREW")
		return

	_mark_visibility_triggered()

	expedition_commands_today += 1
	expedition_count_total += 1
	expedition_recent_score += EXPEDITION_RECENT_GAIN
	if not expedition_happened_today:
		expedition_streak += 1
		expedition_happened_today = true
	_recompute_expedition_heat()
	expedition_counter = expedition_count_total
	_obs_push(
		obs,
		"EXP_PROFILE@tot=%d@streak=%d@recent=%d@heat=%d" % [
			expedition_count_total,
			expedition_streak,
			expedition_recent_score,
			expedition_heat,
		]
	)

	_schedule_expedition_lag(
		sim_day,
		run_seed,
		obs,
		expedition_commands_today,
		expedition_heat,
		expedition_count_total
	)
	expedition_crew_today += crew

	# Expeditions always increase threat deterministically.
	var threat_gain := 1 + int(ceil(float(crew) * 0.5))
	expedition_threat_today += threat_gain
	_obs_push(obs, "THREAT+%d" % threat_gain)

	if expedition_attention_bonus_per_trip_today > 0:
		expedition_attention += float(expedition_attention_bonus_per_trip_today)
		expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)
		_obs_push(obs, "ATTN+%d" % expedition_attention_bonus_per_trip_today)

	if not scav_pools.has(target):
		push_warning("Unknown expedition target '%s' in scav_pools; yield will be zero." % target)
		scav_pools[target] = 0

	var remaining := int(scav_pools[target])
	if remaining <= 0:
		_obs_push(obs, "POOL_EMPTY@%s" % target)
		return

	var bonus_yield: int = 0
	if expedition_yield_bonus_per_crew_today > 0:
		bonus_yield = crew * expedition_yield_bonus_per_crew_today
		if bonus_yield > 0:
			_obs_push(obs, "EXP_COMPRESS_BONUS@%d" % bonus_yield)
	var yield_base: int = int(max(crew * 2, 1)) + bonus_yield
	var yield_amount: int = int(min(remaining, yield_base))
	scav_pools[target] = remaining - yield_amount

	match target:
		"materials":
			sim_res.materials += yield_amount
			_obs_push(obs, "YIELD_MAT@%d" % yield_amount)
		"water":
			sim_res.water += yield_amount
			_obs_push(obs, "YIELD_WATER@%d" % yield_amount)
		"food":
			sim_res.food += yield_amount
			_obs_push(obs, "YIELD_FOOD@%d" % yield_amount)
		_:
			# Unknown targets drain their pool but don't create new subsystems.
			_obs_push(obs, "YIELD_UNKNOWN@%d" % yield_amount)

func _log_trade_event(sim_day: int, message: String, severity: String, payload: Dictionary) -> void:
	_emit_event(
		"TRADE",
		message,
		severity,
		"player_feed",
		payload,
		"trade",
		sim_day,
		hour_of_day,
		true
	)

func _cmd_trade(payload: Dictionary, sim_res: Resources, obs: Array[String], sim_day: int) -> void:
	if payload == null:
		return
	var direction := str(payload.get("direction", "")).to_lower()
	var resource := str(payload.get("resource", "")).to_lower()
	var amount := int(payload.get("amount", 0))
	var base_payload := {
		"direction": direction,
		"resource": resource,
		"amount": amount,
		"silver_balance": sim_res.silver,
	}
	if direction != "buy" and direction != "sell":
		_log_trade_event(sim_day, "Trade rejected: invalid action.", "warn", base_payload)
		_obs_push(obs, "TRADE_REJECTED_ACTION")
		return
	if not TRADEABLE_RESOURCES.has(resource):
		_log_trade_event(sim_day, "Trade rejected: unsupported resource.", "warn", base_payload)
		_obs_push(obs, "TRADE_REJECTED_RESOURCE")
		return
	if amount <= 0:
		_log_trade_event(sim_day, "Trade rejected: invalid amount.", "warn", base_payload)
		_obs_push(obs, "TRADE_REJECTED_AMOUNT")
		return
	if direction == "buy":
		var rate := int(TRADE_BUY_RATES.get(resource, 0))
		if rate <= 0:
			_log_trade_event(sim_day, "Trade rejected: buy rate unavailable.", "warn", base_payload)
			return
		var cost := amount * rate
		if sim_res.silver < cost:
			_log_trade_event(sim_day, "Trade rejected: insufficient silver.", "warn", base_payload)
			_obs_push(obs, "TRADE_NO_SILVER")
			return
		var before_amount := sim_res.get_amount(resource)
		sim_res.silver -= cost
		sim_res.set_amount(resource, before_amount + amount)
		var event_payload := base_payload.duplicate()
		event_payload["silver_change"] = -cost
		event_payload["resource_before"] = before_amount
		event_payload["resource_after"] = sim_res.get_amount(resource)
		var message := "Bought %d %s for %s." % [amount, resource, Resources.format_currency(cost)]
		_log_trade_event(sim_day, message, "info", event_payload)
		_obs_push(obs, "TRADE_BUY@%s" % resource)
	else:
		var rate := int(TRADE_SELL_RATES.get(resource, 0))
		if rate <= 0:
			_log_trade_event(sim_day, "Trade rejected: sell rate unavailable.", "warn", base_payload)
			return
		var available := sim_res.get_amount(resource)
		if available < amount:
			_log_trade_event(sim_day, "Trade rejected: insufficient resources.", "warn", base_payload)
			_obs_push(obs, "TRADE_NO_RESOURCE")
			return
		var revenue := amount * rate
		sim_res.set_amount(resource, available - amount)
		sim_res.silver += revenue
		var event_payload := base_payload.duplicate()
		event_payload["silver_change"] = revenue
		event_payload["resource_before"] = available
		event_payload["resource_after"] = sim_res.get_amount(resource)
		var message := "Sold %d %s for %s." % [amount, resource, Resources.format_currency(revenue)]
		_log_trade_event(sim_day, message, "info", event_payload)
		_obs_push(obs, "TRADE_SELL@%s" % resource)

func _phase_delayed_consequences(sim_day: int, sim_res: Resources, obs: Array[String]) -> void:
	if _delayed_consequence_queue.is_empty():
		return

	var due: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for entry in _delayed_consequence_queue:
		if int(entry.get("due_day", -1)) == sim_day:
			due.append(entry)
		else:
			remaining.append(entry)

	if due.is_empty():
		return

	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_due: int = int(a.get("due_day", -1))
		var b_due: int = int(b.get("due_day", -1))
		if a_due != b_due:
			return a_due < b_due
		return int(a.get("idx", -1)) < int(b.get("idx", -1))
	)

	_delayed_consequence_queue = remaining
	for entry in due:
		var kind: String = str(entry.get("kind", "UNKNOWN"))
		var magnitude: int = int(entry.get("magnitude", 0))
		var heat_at_schedule: int = int(entry.get("heat", 0))
		if magnitude <= 0:
			continue
		match kind:
			"RETALIATION_RISK":
				sim_res.threat += magnitude
			"SUPPLY_CHAIN_FRICTION":
				sim_res.morale -= magnitude
			_:
				continue
		_obs_push(obs, "EXPEDITION_LAG_TRIGGER@%s@M%d@heat=%d" % [kind, magnitude, heat_at_schedule])

func _enqueue_consequence(entry: Dictionary) -> void:
	if entry == null:
		return
	entry["idx"] = _consequence_insertion_counter
	_consequence_insertion_counter += 1
	_consequence_queue.append(entry)

func _process_consequence_queue(sim_day: int, sim_res: Resources, obs: Array[String], tracker: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	if _consequence_queue.is_empty():
		return logs

	var due: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for entry in _consequence_queue:
		if int(entry.get("due_day", -1)) == sim_day:
			due.append(entry)
		else:
			remaining.append(entry)

	if due.is_empty():
		return logs

	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_due: int = int(a.get("due_day", -1))
		var b_due: int = int(b.get("due_day", -1))
		if a_due != b_due:
			return a_due < b_due
		return int(a.get("idx", 0)) < int(b.get("idx", 0))
	)

	_consequence_queue = remaining
	for entry in due:
		var kind: String = str(entry.get("kind", ""))
		match kind:
			"STRUCT_INCIDENT":
				logs.append_array(_process_structural_incident_entry(entry, sim_res, obs, tracker))
			"STRUCT_COLLAPSE_TRY":
				_structural_collapse_scheduled = false
				logs.append_array(_process_structural_collapse_entry(sim_res, obs, tracker))

	return logs

func _structural_level_for_strain(strain: float) -> int:
	var level := -1
	for i in range(STRUCTURAL_TELEGRAPH_THRESHOLDS.size()):
		if strain >= STRUCTURAL_TELEGRAPH_THRESHOLDS[i]:
			level = i
	return level

func _emit_structural_telegraph(sim_day: int, level: int, obs: Array[String]) -> void:
	if level < 0 or level >= STRUCTURAL_TELEGRAPH_EVENTS.size():
		return
	var token := STRUCTURAL_TELEGRAPH_EVENTS[level]
	_obs_push(obs, token)
	if level >= STRUCTURAL_INCIDENT_IDS.size():
		return
	var incident_id := STRUCTURAL_INCIDENT_IDS[level]
	if incident_id in ["support_shift", "floor_sag"]:
		_enqueue_consequence({
			"due_day": sim_day + STRUCTURAL_TELEGRAPH_DELAY_DAYS,
			"kind": "STRUCT_INCIDENT",
			"incident_id": incident_id,
		})

func _structural_incident_def_by_id(incident_id: String) -> Dictionary:
	for incident_def in IncidentDefsRef.STRUCTURAL_INCIDENT_DEFS:
		if str(incident_def.get("id", "")) == incident_id:
			return incident_def
	return {}

func _process_structural_incident_entry(entry: Dictionary, sim_res: Resources, obs: Array[String], tracker: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	var incident_id := str(entry.get("incident_id", ""))
	if incident_id == "":
		return logs
	var incident_def := _structural_incident_def_by_id(incident_id)
	if incident_def.is_empty():
		return logs

	var chance := float(incident_def.get("chance", 0.0))
	var roll := _rng_randf(tracker)
	if roll <= chance:
		var severity := str(incident_def.get("severity", ""))
		var entry_str := "%s[%s]" % [incident_id, severity] if severity != "" else incident_id
		logs.append(entry_str)
		sim_res.morale -= STRUCTURAL_WARNING_MORALE_PENALTY
		_obs_push(obs, "STRUCT_WARN@%s" % incident_id)
		_structural_warning_logged = true

	return logs

func _process_structural_collapse_entry(sim_res: Resources, obs: Array[String], tracker: Dictionary) -> Array[String]:
	var logs: Array[String] = []
	if not _structural_warning_logged:
		return logs

	var collapse_def := _structural_incident_def_by_id("structural_breach")
	if collapse_def.is_empty():
		return logs

	if _structural_high_strain_days < STRUCTURAL_COLLAPSE_MIN_DAYS:
		return logs

	if sim_res.strain < STRUCTURAL_COLLAPSE_MIN_STRAIN:
		return logs

	var base_chance := float(collapse_def.get("chance", 0.0))
	base_chance = clamp(
		base_chance + (sim_res.collapse_debt * STRUCTURAL_COLLAPSE_DEBT_SCALE),
		0.0,
		0.95
	)
	var roll := _rng_randf(tracker)
	if roll <= base_chance:
		var severity := str(collapse_def.get("severity", ""))
		var entry_str := "structural_breach[%s]" % severity if severity != "" else "structural_breach"
		logs.append(entry_str)
		sim_res.morale -= STRUCTURAL_COLLAPSE_MORALE_PENALTY
		sim_res.materials = max(sim_res.materials - STRUCTURAL_COLLAPSE_MATERIALS_LOSS, 0)
		sim_res.collapse_debt += STRUCTURAL_COLLAPSE_DEBT_PENALTY
		sim_res.collapse_debt = snapped(sim_res.collapse_debt, SIM_FLOAT_SNAP)
		_obs_push(obs, "STRUCT_COLLAPSE@%0.2f" % sim_res.collapse_debt)
		_structural_warning_logged = false

	return logs

func _phase_baselines(sim_res: Resources, _obs: Array[String]) -> void:
	# Phase A: baselines (irreversible drift + per-day resets)
	var staying_step: float = 1.0
	if sim_res.food <= 0:
		staying_step += 1.0
	if sim_res.water <= 0:
		staying_step += 1.5
	if sim_res.morale <= 10:
		staying_step += 0.5

	sim_res.staying_index += staying_step
	sim_res.staying_index = snapped(sim_res.staying_index, SIM_FLOAT_SNAP)

	var ceiling_decay: float = 0.05 + (staying_step * 0.02) + (sim_res.staying_index * 0.001)
	if sim_res.days_without_food >= 3:
		ceiling_decay += 0.1
	if sim_res.days_without_water >= 2:
		ceiling_decay += 0.2
	sim_res.morale_ceiling = max(sim_res.morale_ceiling - ceiling_decay, 0.0)

	# Reset per-day accounting
	sim_res.reset_deltas()
	sim_res.power_supply = 0
	sim_res.power_used = 0

func _phase_production(sim_tower: Tower, sim_res: Resources, sim_db: ModuleDB, obs: Array[String]) -> Dictionary:
	# Phase B: production & consumption. Modules require both power and inputs;
	# per spec we avoid partial operation so nothing runs unless both are satisfied.
	var food_before := sim_res.food
	var food_consumption := _daily_food_consumed
	var water_consumption := _daily_water_consumed

	var instances: Array[ModuleInstance] = []
	var order_index: int = 0
	var total_capacity: int = 0
	var powered_count: int = 0
	var applied_food_from_modules: int = 0
	var module_power_map: Dictionary = {}
	var placed_module_count: int = 0

	for f in range(sim_tower.floors.size()):
		var floor_data: Variant = sim_tower.floors[f]
		if floor_data == null or not (floor_data is Array):
			continue
		var grid: Array = floor_data as Array
		for y in range(sim_tower.height):
			if y < 0 or y >= grid.size():
				continue
			var row_candidate: Variant = grid[y]
			if row_candidate == null or not (row_candidate is Array):
				continue
			var row: Array = row_candidate as Array
			for x in range(sim_tower.width):
				if x < 0 or x >= row.size():
					continue
				var module_id: Variant = row[x]
				if module_id == null:
					continue
				if _is_module_abandoned(f, x, y):
					_obs_push(obs, "ABANDONED_MODULE@%d:%d:%d" % [f, x, y])
					continue
				placed_module_count += 1
				if not sim_tower.is_module_enabled(f, x, y):
					_obs_push(obs, "DISABLED_MODULE@%d:%d:%d" % [f, x, y])
					continue

				var def: ModuleDef = sim_db.get_def(module_id)
				if def == null:
					continue

				var inst := ModuleInstance.new(def)
				inst.order_index = order_index
				inst.floor_index = f
				inst.x = x
				inst.y = y
				var prio_override: Variant = sim_tower.get_module_priority_override(f, x, y)
				if prio_override != null:
					inst.priority = int(prio_override)
				order_index += 1
				instances.append(inst)

				sim_res.power_supply += def.power_supply

	instances.sort_custom(func(a: ModuleInstance, b: ModuleInstance) -> bool:
		if a.priority != b.priority:
			return a.priority < b.priority
		if a.def.id != b.def.id:
			return a.def.id < b.def.id
		if a.def.name != b.def.name:
			return a.def.name < b.def.name
		if a.floor_index != b.floor_index:
			return a.floor_index < b.floor_index
		if a.y != b.y:
			return a.y < b.y
		if a.x != b.x:
			return a.x < b.x
		return a.order_index < b.order_index
	)

	var module_count: int = placed_module_count
	var remaining_power: int = sim_res.power_supply
	var total_noise: int = 0
	var total_heat: int = 0

	for inst in instances:
		var def := inst.def
		var needs: int = def.power_demand
		inst.power_required = needs
		var candidate_power_enabled := (needs == 0) or (remaining_power >= needs)
		inst.powered = candidate_power_enabled
		inst.power_allocated = needs if candidate_power_enabled else 0

		var module_key := _module_key(inst.floor_index, inst.x, inst.y)
		var snapshot_entry: Dictionary = {"powered": false}

		var inputs_ready := _module_inputs_available(sim_res, def.inputs_per_day)
		if candidate_power_enabled and inputs_ready:
			remaining_power -= needs
			sim_res.power_used += needs
			powered_count += 1
			_consume_module_inputs(sim_res, def.inputs_per_day)
			var deltas := inst.compute_resource_deltas(sim_res)
			var lever_adjusted := _apply_lever_output_modifiers(deltas)
			var scaled := _scale_deltas_for_workforce(lever_adjusted, workforce_multiplier_today)
			if scaled.has("food"):
				applied_food_from_modules += int(scaled.get("food", 0))
			_apply_module_deltas_stably(sim_res, scaled)
			total_capacity += def.delta_capacity
			total_noise += def.noise
			total_heat += def.heat
			snapshot_entry["powered"] = true
			snapshot_entry["deltas"] = scaled.duplicate(true)
		else:
			inst.powered = false
			inst.power_allocated = 0
			if candidate_power_enabled and not inputs_ready:
				_obs_push(obs, "MODULE_INPUT_STARVED@%s" % module_key)
			else:
				_obs_push(obs, "MODULE_UNPOWERED@%s" % module_key)

		module_power_map[module_key] = snapshot_entry

	sim_res.apply_deltas()
	_refresh_module_snapshots(module_power_map)

	var after_food := sim_res.food
	var expected_food: int = food_before + applied_food_from_modules
	var discrepancy: int = after_food - expected_food
	_last_production_metrics = {
		"food_before": food_before,
		"food_consumption": food_consumption,
		"water_consumption": water_consumption,
		"applied_food": applied_food_from_modules,
		"after_food": after_food,
		"expected_food": expected_food,
		"discrepancy": discrepancy,
	}
	if enable_food_debug_log and (food_consumption > 0 or applied_food_from_modules != 0 or discrepancy != 0 or water_consumption > 0):
		var status := "ok" if discrepancy == 0 else "discrep=%d" % discrepancy
		print("FOOD_SUMMARY consumed=%d water=%d produced=%d before=%d after=%d expected=%d [%s]" % [
			food_consumption,
			water_consumption,
			applied_food_from_modules,
			food_before,
			after_food,
			expected_food,
			status,
		])

	return {
		"powered_count": powered_count,
		"module_count": module_count,
		"total_capacity": total_capacity,
		"total_noise": total_noise,
		"total_heat": total_heat,
	}

func _phase_growth_dependency(sim_res: Resources, module_count: int, _powered_count: int, obs: Array[String]) -> Dictionary:
	# Phase C: growth & dependency (maintenance / fragility)
	# Strain amplifies maintenance burden deterministically per structural risk contract.
	var strain_penalty: float = max(sim_res.strain - MAINTENANCE_STRAIN_THRESHOLD, 0.0)
	var maintenance_multiplier: float = 1.0 + (strain_penalty * MAINTENANCE_STRAIN_MULTIPLIER)
	var targeted_modules: int = max(module_count, 0)
	# All enabled modules contribute to maintenance even when unpowered per spec.
	var maintenance_cost: int = int(ceil(float(targeted_modules) * MAINTENANCE_COST_PER_MODULE * maintenance_multiplier))
	var maintenance_shortfall: bool = false
	var maintenance_morale_penalty: int = 0
	var materials_before: int = sim_res.materials
	var maintenance_deficit: int = 0

	if maintenance_cost > 0:
		sim_res.materials = max(sim_res.materials - maintenance_cost, 0)
		if materials_before < maintenance_cost:
			maintenance_shortfall = true
			maintenance_deficit = maintenance_cost - materials_before
			maintenance_morale_penalty = 1
			# Maintenance shortfalls degrade morale and add detectability pressure.
			sim_res.morale -= maintenance_morale_penalty
			sim_res.threat += 1
			_obs_push(obs, "MAINT_SHORTFALL")

	return {
		"maintenance_cost": maintenance_cost,
		"maintenance_shortfall": maintenance_shortfall,
		"maintenance_morale_penalty": maintenance_morale_penalty,
		"materials_before": materials_before,
		"maintenance_deficit": maintenance_deficit,
		"module_count": targeted_modules,
	}

func _apply_throttled_morale_penalty(sim_res: Resources, amount: int, obs: Array[String], tag: String) -> void:
	if amount <= 0:
		return
	if info_throttle_morale_factor_today >= 1.0:
		sim_res.morale -= amount
		return
	var reduced := int(floor(float(amount) * info_throttle_morale_factor_today))
	var deferred := amount - reduced
	if reduced > 0:
		sim_res.morale -= reduced
	if deferred > 0:
		info_throttle_backlog += float(deferred)
		info_throttle_backlog = snapped(info_throttle_backlog, SIM_FLOAT_SNAP)
		if tag != "":
			_obs_push(obs, "THROTTLED@%s@%d" % [tag, deferred])

func _phase_pressure_accrual(
	sim_res: Resources,
	production: Dictionary,
	growth: Dictionary,
	obs: Array[String],
	sim_day: int
) -> void:
	# Phase D: pressure accrual (morale pressures + threat growth)
	var total_capacity: int = int(production.get("total_capacity", 0))
	var total_noise: int = int(production.get("total_noise", 0))
	var total_heat: int = int(production.get("total_heat", 0))
	var maintenance_morale_penalty: int = int(growth.get("maintenance_morale_penalty", 0))

	# Process any due lagged expedition consequences deterministically.
	_phase_delayed_consequences(sim_day, sim_res, obs)

	if total_capacity < sim_res.population:
		_apply_throttled_morale_penalty(sim_res, 2, obs, "CAPACITY")
		_obs_push(obs, "CAPACITY_SHORTFALL")

	if sim_res.food <= 0:
		_apply_throttled_morale_penalty(sim_res, 5, obs, "FOOD")
		_obs_push(obs, "SHORTAGE_FOOD")
	if sim_res.water <= 0:
		_apply_throttled_morale_penalty(sim_res, 7, obs, "WATER")
		_obs_push(obs, "SHORTAGE_WATER")

	if ration_morale_penalty_today > 0:
		_apply_throttled_morale_penalty(sim_res, ration_morale_penalty_today, obs, "RATION")
		sim_res.threat += ration_threat_penalty_today

	if expedition_morale_penalty_today > 0:
		_apply_throttled_morale_penalty(sim_res, expedition_morale_penalty_today, obs, "EXPEDITION")

	# Derive threat and attention from the same noisy/heat/power signature per specification.
	var threat_delta: int = _signature_threat_delta(total_noise, total_heat, sim_res.power_used, sim_res.power_supply)
	sim_res.threat += threat_delta
	if expedition_threat_today > 0:
		sim_res.threat += expedition_threat_today
	if lever_threat_bonus_today > 0:
		sim_res.threat += lever_threat_bonus_today

	var attention_delta: float = _signature_attention_delta(total_noise, total_heat, sim_res.attention_multiplier)
	if attention_delta > 0.0:
		expedition_attention += attention_delta
		expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)

	# If morale is collapsing, people make mistakes -> more threat
	var morale_for_threat: int = sim_res.morale + maintenance_morale_penalty
	if morale_for_threat <= 10:
		sim_res.threat += 1

func _phase_structural_risk(
	sim_day: int,
	sim_res: Resources,
	growth: Dictionary,
	obs: Array[String]
) -> Array[String]:
	var incidents: Array[String] = []
	var tracker := _create_rng_tracker(sim_day, PHASE_STRUCTURAL, "consequence_queue", RNG_OFFSET_STRUCTURAL)
	incidents.append_array(_process_consequence_queue(sim_day, sim_res, obs, tracker))

	var module_count := int(growth.get("module_count", 0))
	var maintenance_deficit := int(growth.get("maintenance_deficit", 0))
	var strain_gain := float(module_count) * STRUCTURAL_STRAIN_PER_MODULE
	if maintenance_deficit > 0:
		strain_gain += float(maintenance_deficit) * STRUCTURAL_STRAIN_PER_MAINT_DEFICIT

	sim_res.strain += strain_gain
	sim_res.strain = max(sim_res.strain - STRUCTURAL_STRAIN_DECAY, 0.0)
	sim_res.strain = snapped(sim_res.strain, SIM_FLOAT_SNAP)

	if maintenance_deficit > 0:
		sim_res.collapse_debt += float(maintenance_deficit) * STRUCTURAL_COLLAPSE_DEBT_SCALE
	elif sim_res.collapse_debt > 0.0:
		sim_res.collapse_debt = max(sim_res.collapse_debt - STRUCTURAL_COLLAPSE_DECAY, 0.0)
	sim_res.collapse_debt = snapped(sim_res.collapse_debt, SIM_FLOAT_SNAP)

	var prev_level := _structural_telegraph_level
	var new_level := _structural_level_for_strain(sim_res.strain)
	if new_level > prev_level:
		_emit_structural_telegraph(sim_day, new_level, obs)
	_structural_telegraph_level = new_level

	if sim_res.strain >= STRUCTURAL_COLLAPSE_MIN_STRAIN:
		_structural_high_strain_days += 1
	else:
		_structural_high_strain_days = 0

	if _structural_high_strain_days >= STRUCTURAL_COLLAPSE_MIN_DAYS and not _structural_collapse_scheduled:
		_enqueue_consequence({
			"due_day": sim_day + STRUCTURAL_COLLAPSE_DELAY_DAYS,
			"kind": "STRUCT_COLLAPSE_TRY",
		})
		_structural_collapse_scheduled = true
	elif _structural_high_strain_days < STRUCTURAL_COLLAPSE_MIN_DAYS:
		_structural_collapse_scheduled = false

	return incidents

func _signature_threat_delta(noise: int, heat: int, power_used: int, power_supply: int) -> int:
	var noise_threat := int(ceil(float(noise) * THREAT_PER_NOISE))
	var heat_threat := int(ceil(float(heat) * THREAT_PER_HEAT))
	var power_short: int = max(power_used - power_supply, 0)
	var power_threat := int(ceil(float(power_short) * THREAT_PER_POWER))
	return noise_threat + heat_threat + power_threat

func _signature_attention_delta(noise: int, heat: int, multiplier: float) -> float:
	var base: float = float(noise + heat) * 0.05
	var clamped_multiplier: float = max(multiplier, 0.0)
	var amount: float = base * clamped_multiplier
	return snapped(amount, SIM_FLOAT_SNAP)

func _phase_resolution(sim_res: Resources, growth: Dictionary, obs: Array[String]) -> Dictionary:
	# Phase E: resolution (counters, population loss, clamp)
	sim_res.clamp_all()

	if sim_res.food <= 0:
		sim_res.days_without_food += 1
	else:
		sim_res.days_without_food = 0

	if sim_res.water <= 0:
		sim_res.days_without_water += 1
	else:
		sim_res.days_without_water = 0

	var pop_loss := 0
	var maintenance_morale_penalty: int = int(growth.get("maintenance_morale_penalty", 0))
	var morale_for_pop: int = sim_res.morale + maintenance_morale_penalty

	if sim_res.food <= 0:
		pop_loss += 1
	# Humans can survive roughly ~3 days without water; model that explicitly.
	if sim_res.days_without_water >= 3:
		pop_loss += 2
	if morale_for_pop <= 0:
		pop_loss += 1

	if pop_loss > 0:
		sim_res.population = max(sim_res.population - pop_loss, 0)
		_obs_push(obs, "POP_LOSS@%d" % pop_loss)

	sim_res.clamp_all()

	return {
		"pop_loss": pop_loss,
	}

func _run_civil_unrest_daily(sim_day: int, sim_tower: Tower, sim_db: ModuleDB, obs: Array[String]) -> void:
	if not unrest_active:
		return
	var unrest_days := int(floor(float(unrest_hours) / float(HOURS_PER_DAY)))
	var module_target: Dictionary = {}
	var incident_roll = float(_daily_rolls.get("unrest_incident_roll", 1.0))
	var pop_chance = clamp(
		CIVIL_UNREST_POP_LOSS_BASE_CHANCE + float(unrest_days) * CIVIL_UNREST_POP_LOSS_PER_DAY,
		0.0,
		CIVIL_UNREST_POP_LOSS_CAP,
	)
	var module_chance = clamp(
		CIVIL_UNREST_MODULE_BASE_CHANCE + float(unrest_days) * CIVIL_UNREST_MODULE_PER_DAY,
		0.0,
		CIVIL_UNREST_MODULE_CAP,
	)
	var total_threshold = min(1.0, pop_chance + module_chance)
	var incident_type := ""
	if incident_roll <= pop_chance:
		_apply_unrest_pop_loss(obs)
		incident_type = "POP_LOSS"
	elif incident_roll <= total_threshold:
		module_target = _apply_unrest_module_sabotage(sim_tower, sim_db, obs)
		incident_type = "MODULE_SABOTAGE"
	if incident_type != "":
		var payload := {
			"unrest_days": unrest_days,
			"roll": incident_roll,
			"pop_threshold": pop_chance,
			"module_threshold": module_chance,
			"incident_type": incident_type,
		}
		if incident_type == "MODULE_SABOTAGE" and module_target != null and module_target.size() > 0:
			payload["module_id"] = module_target.get("id", "")
			payload["module_name"] = module_target.get("name", "")
			payload["module_location"] = module_target.get("location", "")
		_emit_event(
			"CIVIL_UNREST_%s" % incident_type,
			"Civil unrest roll=%.3f thresholds=pop:%.2f module:%.2f" % [
				incident_roll,
				pop_chance,
				module_chance,
			],
			"warn",
			"sticky",
			payload,
			"unrest",
			sim_day,
			hour_of_day,
			true
		)

func _run_civil_unrest_terminal(sim_day: int, sim_res: Resources, obs: Array[String]) -> void:
	if not unrest_active:
		return
	var unrest_days := int(floor(float(unrest_hours) / float(HOURS_PER_DAY)))
	if unrest_days < 3:
		return
	var chance := _civil_unrest_terminal_chance(unrest_days)
	var terminal_roll := float(_daily_rolls.get("unrest_terminal_roll", 1.0))
	if terminal_roll > chance:
		return
	var outcome_roll := float(_daily_rolls.get("unrest_terminal_outcome_roll", 0.0))
	var outcome := EXIT_MUTINY if outcome_roll < 0.5 else EXIT_EXILE
	exit_reason = outcome
	sim_res.population = 0
	var payload := {
		"unrest_days": unrest_days,
		"roll": terminal_roll,
		"threshold": chance,
		"outcome_roll": outcome_roll,
	}
	var label := outcome.split("_")[-1].capitalize()
	_emit_event(
		outcome,
		"%s triggered after %d unrest days." % [label, unrest_days],
		"warn",
		"modal",
		payload,
		"unrest",
		sim_day,
		hour_of_day,
		true
	)
	_obs_push(obs, outcome)

func _apply_unrest_pop_loss(obs: Array[String]) -> void:
	if res == null:
		return
	if CIVIL_UNREST_POP_LOSS_DEFAULT <= 0:
		return
	var before_pop := res.population
	res.population = max(res.population - CIVIL_UNREST_POP_LOSS_DEFAULT, 0)
	if res.population < before_pop:
		_obs_push(obs, "UNREST_POP_LOSS@%d" % CIVIL_UNREST_POP_LOSS_DEFAULT)

func _apply_unrest_module_sabotage(sim_tower: Tower, sim_db: ModuleDB, obs: Array[String]) -> Dictionary:
	if sim_tower == null or sim_db == null:
		return {}
	var candidates := _civil_unrest_module_candidates(sim_tower, sim_db)
	if candidates.is_empty():
		return {}
	var module_roll := float(_daily_rolls.get("unrest_module_roll", 0.0))
	var normalized = clamp(module_roll, 0.0, 0.999999)
	var idx := int(floor(normalized * float(candidates.size())))
	idx = clamp(idx, 0, candidates.size() - 1)
	var target := candidates[idx]
	res.threat += 1
	res.morale = max(res.morale - 1, 0)
	var module_id := str(target.get("id", "unknown"))
	_obs_push(obs, "MODULE_SABOTAGE@%s" % module_id)
	if target.has("location"):
		_obs_push(obs, "SABOTAGED_MODULE@%s" % target.get("location"))
	return target

func _civil_unrest_module_candidates(sim_tower: Tower, sim_db: ModuleDB) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for f in range(sim_tower.floors.size()):
		var floor_data: Variant = sim_tower.floors[f]
		if floor_data == null or not (floor_data is Array):
			continue
		var grid: Array = floor_data as Array
		for y in range(sim_tower.height):
			if y < 0 or y >= grid.size():
				continue
			var row_candidate: Variant = grid[y]
			if row_candidate == null or not (row_candidate is Array):
				continue
			var row: Array = row_candidate as Array
			for x in range(sim_tower.width):
				if x < 0 or x >= row.size():
					continue
				var module_id = row[x]
				if module_id == null:
					continue
				if _is_module_abandoned(f, x, y):
					continue
				if str(module_id) == "core":
					continue
				var module_def := sim_db.get_def(str(module_id))
				var module_name := str(module_def.name) if module_def != null else str(module_id)
				candidates.append({
					"id": str(module_id),
					"name": module_name,
					"location": "%d:%d:%d" % [f, x, y],
				})
	return candidates

func _civil_unrest_terminal_chance(unrest_days: int) -> float:
	if unrest_days <= 0:
		return 0.0
	if CIVIL_UNREST_TERMINAL_RAMP.has(unrest_days):
		return CIVIL_UNREST_TERMINAL_RAMP.get(unrest_days, 0.0)
	if unrest_days >= 7:
		return CIVIL_UNREST_TERMINAL_CAP
	return 0.0

func _phase_exit_checks(sim_res: Resources, obs: Array[String]) -> String:
	# Phase F: exit checks (stub evaluator only)
	if exit_reason != "":
		return exit_reason
	if sim_res.population <= 0:
		_obs_push(obs, "EXIT_COLLAPSE_CANDIDATE")
		return "collapse_candidate"
	return "none"

func _emit_observations(pre_threat: int, sim_res: Resources, obs: Array[String]) -> void:
	# Phase G: emit observations (tokens derived from transitions)
	var threshold_logs := _evaluate_threat_thresholds(pre_threat, sim_res.threat)
	for marker in threshold_logs:
		var parts: PackedStringArray = str(marker).split("@")
		if parts.size() == 2:
			_obs_push(obs, "THR_CROSSED@%s" % parts[1])

func _step_day_core(sim_day: int, run_seed: int, sim_tower: Tower, sim_res: Resources, sim_db: ModuleDB) -> Array[String]:
	var pre_threat: int = sim_res.threat
	var pre_morale: int = sim_res.morale
	var pre_materials: int = sim_res.materials
	var obs: Array[String] = []

	# Phase -1: levers (policy effects + queued conversions)
	_phase_levers(sim_day, sim_tower, sim_res, obs)

	# Phase 0: commands (start-of-day player/debug inputs)
	_phase_commands(sim_day, run_seed, sim_tower, sim_res, obs)

	# Phase A: baselines
	_phase_baselines(sim_res, obs)

	# Phase B: production & consumption
	var production := _phase_production(sim_tower, sim_res, sim_db, obs)

	# Phase C: growth & dependency
	var growth := _phase_growth_dependency(
		sim_res,
		int(production.get("module_count", 0)),
		int(production.get("powered_count", 0)),
		obs
	)

	# Phase D: pressure accrual
	_phase_pressure_accrual(sim_res, production, growth, obs, sim_day)
	var structural_logs := _phase_structural_risk(sim_day, sim_res, growth, obs)

	# Phase E: resolution
	_phase_resolution(sim_res, growth, obs)
	_run_civil_unrest_daily(sim_day, sim_tower, sim_db, obs)
	_run_civil_unrest_terminal(sim_day, sim_res, obs)

	var post_threat: int = sim_res.threat
	var post_morale: int = sim_res.morale
	var post_materials: int = sim_res.materials
	_emit_threat_band_events(pre_threat, post_threat, sim_day)
	_emit_morale_band_events(pre_morale, post_morale, sim_day)
	_emit_materials_exhausted_event(pre_materials, post_materials, sim_day)
	_emit_maintenance_shortfall_event(sim_day, growth)

	# Phase F: exit checks (stub)
	_phase_exit_checks(sim_res, obs)

	# Clamp before derived observation and incident evaluation
	sim_res.clamp_all()
	_emit_observations(pre_threat, sim_res, obs)

	# Incidents remain log-only and deterministic
	var maintenance_cost: int = int(growth.get("maintenance_cost", 0))
	var maintenance_logs: Array[String] = []
	if maintenance_cost > 0:
		maintenance_logs.append("maint[%d]" % maintenance_cost)

	var incident_logs := _evaluate_incidents(sim_day, run_seed, sim_res)
	var threshold_logs := _evaluate_threat_thresholds(pre_threat, sim_res.threat)
	_last_obs_tokens = obs
	return _merge_incident_lists(
		maintenance_logs,
		_merge_incident_lists(
			structural_logs,
			_merge_incident_lists(threshold_logs, incident_logs)
		)
	)

func _format_incidents(incidents: Array[String]) -> String:
	if incidents.is_empty():
		return "-"
	return "+".join(incidents)

func _format_obs(obs: Array[String]) -> String:
	if obs.is_empty():
		return "-"
	return "+".join(obs)

func _format_log_line(_day: int, _seed: int, _res: Resources, incidents: Array[String], obs: Array[String]) -> String:
	return "SIM day=%d seed=%d pwr=%d/%d thr=%d dw=%d df=%d inc=%s obs=%s RES{%s}" % [
		_day,
		_seed,
		_res.power_used,
		_res.power_supply,
		_res.threat,
		_res.days_without_water,
		_res.days_without_food,
		_format_incidents(incidents),
		_format_obs(obs),
		_res.snapshot(),
	]

func _state_signature() -> String:
	var parts: Array[String] = []
	parts.append("day=%d" % day)
	parts.append("hour_idx=%d" % hour_index)
	parts.append("res=%s" % res.snapshot())
	parts.append("staying=%.2f" % snapped(res.staying_index, SIM_FLOAT_SNAP))
	parts.append("morale_ceiling=%.2f" % res.morale_ceiling)
	parts.append("attention_mult=%.2f" % res.attention_multiplier)
	parts.append("expedition_attention=%.2f" % snapped(expedition_attention, SIM_FLOAT_SNAP))
	parts.append("strain=%.2f" % snapped(res.strain, SIM_FLOAT_SNAP))
	parts.append("collapse_debt=%.2f" % snapped(res.collapse_debt, SIM_FLOAT_SNAP))
	parts.append("ration_scar=%.2f" % snapped(ration_scar, SIM_FLOAT_SNAP))
	parts.append("labor_scar=%.2f" % snapped(labor_scar, SIM_FLOAT_SNAP))
	parts.append("conversion_scar=%d" % conversion_scar)
	var abandoned_keys := abandoned_modules.keys()
	abandoned_keys.sort()
	for key in abandoned_keys:
		parts.append("abandoned=%s" % key)
	parts.append("visibility=%s" % str(visibility_triggered))
	return "|".join(parts)

func _simulate_state_signatures(days_to_run: int, run_seed: int, commands_by_day: Dictionary) -> Dictionary:
	_reset_rng_usage_log()
	var sim := Sim.new()
	sim.sim_seed = run_seed
	sim._setup_default_state()
	sim.day = 0
	var signatures: Array[String] = []
	if commands_by_day == null:
		commands_by_day = {}
	for i in range(days_to_run):
		sim.day = i + 1
		sim.clear_commands()
		var scheduled: Array = commands_by_day.get(sim.day, [])
		for cmd in _clone_command_array(scheduled):
			sim.enqueue_command(cmd)
		sim.hour_of_day = 0
		sim._begin_day(sim.day)
		sim.hour_index = sim.day * HOURS_PER_DAY + sim.scheduled_production_hour
		sim.hour_of_day = sim.scheduled_production_hour
		sim._step_day_core(sim.day, run_seed, sim.tower, sim.res, sim.db)
		sim.production_executed_today = true
		signatures.append(sim._state_signature())
	return {
		"hashes": signatures,
		"rng_log": sim.get_rng_usage_history(),
	}

func debug_run_determinism(days_to_run: int, run_seed: int) -> void:
	var result_a := _simulate_state_signatures(days_to_run, run_seed, {})
	var result_b := _simulate_state_signatures(days_to_run, run_seed, {})
	var hashes_a: Array[String] = result_a.get("hashes", [])
	var hashes_b: Array[String] = result_b.get("hashes", [])

	var max_days: int = max(hashes_a.size(), hashes_b.size())
	for i in range(max_days):
		var hash_a := hashes_a[i] if i < hashes_a.size() else "MISSING"
		var hash_b := hashes_b[i] if i < hashes_b.size() else "MISSING"
		if hash_a != hash_b:
			print("DETERMINISM MISMATCH day=%d\nA:%s\nB:%s" % [i + 1, hash_a, hash_b])
			print("RNG LOG A:", result_a.get("rng_log"))
			print("RNG LOG B:", result_b.get("rng_log"))
			return
	print("DETERMINISM OK")
	print("RNG LOG A:", result_a.get("rng_log"))
	print("RNG LOG B:", result_b.get("rng_log"))

func debug_run_days(days_to_run: int, run_seed: int) -> void:
	var lines := _simulate_days(days_to_run, run_seed)
	for line in lines:
		print(line)

func _clone_command_array(commands: Array) -> Array[SimCommand]:
	var cloned: Array[SimCommand] = []
	for cmd in commands:
		if cmd is SimCommand:
			cloned.append(cmd.clone())
	return cloned

func _run_scripted_once(days_to_run: int, run_seed: int, commands_by_day: Dictionary) -> Array[String]:
	var sim := Sim.new()
	sim.sim_seed = run_seed
	sim._setup_default_state()
	sim.day = 0
	var lines: Array[String] = []

	for i in range(days_to_run):
		sim.day = i + 1
		sim.clear_commands()
		var scheduled: Array = commands_by_day.get(sim.day, [])
		for cmd in _clone_command_array(scheduled):
			sim.enqueue_command(cmd)
		sim.hour_of_day = 0
		sim._begin_day(sim.day)
		sim.hour_index = sim.day * HOURS_PER_DAY + sim.scheduled_production_hour
		sim.hour_of_day = sim.scheduled_production_hour
		var incidents := sim._step_day_core(sim.day, run_seed, sim.tower, sim.res, sim.db)
		sim.production_executed_today = true
		lines.append(sim._format_log_line(sim.day, run_seed, sim.res, incidents, sim._last_obs_tokens))

	return lines

func debug_scripted_run(days_to_run: int, run_seed: int, commands_by_day: Dictionary) -> Array[String]:
	var run_a := _run_scripted_once(days_to_run, run_seed, commands_by_day)
	var run_b := _run_scripted_once(days_to_run, run_seed, commands_by_day)

	if run_a.size() != run_b.size():
		print("DETERMINISM MISMATCH size=%d/%d" % [run_a.size(), run_b.size()])
		return run_a

	for i in range(run_a.size()):
		if run_a[i] != run_b[i]:
			print("DETERMINISM MISMATCH day=%d" % [i + 1])
			return run_a

	return run_a

# Helper to validate expedition escalation behavior.
func debug_test_expedition_escalation() -> void:
	var schedule := {
		1: [SimCommand.new(CMD_EXPEDITION, {"target": "yard", "crew": 2})],
		2: [SimCommand.new(CMD_EXPEDITION, {"target": "yard", "crew": 2})],
		3: [SimCommand.new(CMD_EXPEDITION, {"target": "yard", "crew": 2})],
		6: [SimCommand.new(CMD_EXPEDITION, {"target": "yard", "crew": 2})],
		7: [SimCommand.new(CMD_EXPEDITION, {"target": "yard", "crew": 2})],
	}
	var run_a := debug_scripted_run(10, 1234, schedule)
	var run_b := debug_scripted_run(10, 1234, schedule)

	for line in run_a:
		print(line)

	print("DETERMINISM OK" if run_a == run_b else "DETERMINISM FAIL")

# Example scripted schedule (commented; for ad-hoc debug use):
# var schedule := {
# 	1: [
# 		SimCommand.new(CMD_SET_RATIONS, {"food": 0.8, "water": 0.8}),
# 	],
# 	2: [
# 		SimCommand.new(CMD_SET_MODULE_ENABLED, {"f": 0, "x": 2, "y": 1, "enabled": false}), # hydro off
# 	],
# 	5: [
# 		SimCommand.new(CMD_SET_MODULE_ENABLED, {"f": 0, "x": 2, "y": 1, "enabled": true}), # hydro on
# 	],
# }
# for d in range(3, 31, 3):
# 	if not schedule.has(d):
# 		schedule[d] = []
# 	schedule[d].append(SimCommand.new(CMD_EXPEDITION, {"target": "materials", "crew": 2}))
# var lines := debug_scripted_run(30, 12345, schedule)
# for line in lines:
# 	print(line)
