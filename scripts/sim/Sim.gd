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
const MapDefRef = preload("res://scripts/sim/MapDef.gd")

const MODULE_DELTA_KEYS: Array[String] = [
	"food",
	"water",
	"materials",
	"morale",
]

const THREAT_EVENT_THRESHOLDS: Array[int] = [40, 80, 120, 160, 200]
const MORALE_EVENT_THRESHOLDS: Array[int] = [60, 40, 30, 20, 10]
const MORALE_TIER_STABLE := 0
const MORALE_TIER_WARNING_1 := 1
const MORALE_TIER_WARNING_2 := 2
const MORALE_TIER_WARNING_3 := 3
const MORALE_TIER_OPTIONAL := 4
const MORALE_TIER_NONCOMPLIANT := 5
const MORALE_WARNING_1_ENTER := 60
const MORALE_WARNING_1_EXIT := 62
const MORALE_WARNING_2_ENTER := 40
const MORALE_WARNING_2_EXIT := 42
const MORALE_WARNING_3_ENTER := 30
const MORALE_WARNING_3_EXIT := 32
const MORALE_OPTIONAL_ENTER := 20
const MORALE_OPTIONAL_EXIT := 25
const MORALE_NONCOMPLIANT_ENTER := 10
const MORALE_NONCOMPLIANT_EXIT := 12
const COMPLIANCE_OPTIONAL_STALL_CHANCE := 0.15
const COMPLIANCE_NONCOMPLIANT_STALL_CHANCE := 0.35
const MUTINY_ROLL_BASE := 0.04
const MUTINY_ROLL_PER_POINT := 0.005
const MUTINY_ROLL_CAP := 0.10
const ATTENTION_SUMMARY_INTERVAL_HOURS := 6
const INTRO_QUIET_DAYS := 1
const ATTENTION_DEBT_LOW_THRESHOLD := 10.0
const ATTENTION_DEBT_HIGH_THRESHOLD := 25.0
const ATTENTION_NEUTRAL_MESSAGE := "Background resonance is steady. Nothing urgent to report."
const ATTENTION_LOW_MESSAGE := "Attention metrics are inching upward. Maintain caution."
const ATTENTION_WARNING_MESSAGE := "Attention debt building. Forecast: tensions will rise if unchecked."
const ATTENTION_HIGH_MESSAGE := "Attention debt accruing.\nForecast: When it surfaces, it will surface violently."
const ATTENTION_METER_MAX: float = 100.0
const THREAT_METER_MAX: int = 999

const PEOPLE_FIRST_NAMES: Array[String] = [
	"Ada", "Miles", "Iris", "Jonah", "Mara", "Felix", "Noor", "Reid",
	"Talia", "Ezra", "Vera", "Rafi", "Lina", "Oren", "Sana", "Pax",
	"Mina", "Kian", "Etta", "Ronan"
]
const PEOPLE_LAST_NAMES: Array[String] = [
	"Kerr", "Sato", "Nguyen", "Vale", "Torres", "Rowan", "Quinn", "Patel",
	"Hale", "Yun", "Ortega", "Sol", "Bennett", "Ibrahim", "Cole", "Shaw",
	"Wright", "Singh", "Park", "Reyes"
]

const PEOPLE_STATUS_HOME := "home"
const PEOPLE_STATUS_AWAY := "away"
const PEOPLE_STATUS_INJURED := "injured"
const PEOPLE_STATUS_DEAD := "dead"
const PEOPLE_SYSTEM_VERSION := 1

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
const RNG_OFFSET_ACTIVE_EXPEDITION := 10
const RNG_OFFSET_COMPLIANCE := 11
const RNG_OFFSET_MUTINY := 12
const RNG_OFFSET_EXPEDITION_SURVIVORS := 13
const RNG_OFFSET_OUTSIDERS := RNG_OFFSET_ACTIVE_EXPEDITION + 400
const OUTSIDERS_DECISION_DAYS := 3
const OUTSIDERS_INCIDENT_BONUS := 0.02
const AWAY_RATIO_THRESHOLD := 0.20

# Expedition state machine states.
const EXPEDITION_STATE_PLANNED := "PLANNED"
const EXPEDITION_STATE_OUTBOUND := "OUTBOUND"
const EXPEDITION_STATE_ONSITE := "ONSITE"
const EXPEDITION_STATE_RETURNING := "RETURNING"
const EXPEDITION_STATE_RESOLVED := "RESOLVED"
const EXPEDITION_STATE_FAILED := "FAILED"

const EXPEDITION_YIELD_VERSION_LEGACY := 1
const EXPEDITION_YIELD_VERSION_V2 := 2

const HAUL_BAND_SAFE := {"low": 20.0, "mode": 25.0, "high": 30.0}
const HAUL_BAND_LOW := {"low": 30.0, "mode": 40.0, "high": 50.0}
const HAUL_BAND_MEDIUM := {"low": 55.0, "mode": 72.0, "high": 90.0}
const HAUL_BAND_HIGH := {"low": 85.0, "mode": 110.0, "high": 140.0}

const DURATION_BASELINE_HOURS := 12.0
const DURATION_FACTOR_MIN := 0.8
const DURATION_FACTOR_MAX := 1.5
const DURATION_FACTOR_SCALE := 0.35

const RISK_VARIANCE_SCALE: Array[float] = [0.0, 0.05, 0.12, 0.22]

const CREW_EFFICIENCY_SCALE := 0.15
const CREW_FACTOR_MAX := 1.4

const ALLOCATION_JITTER_RANGE := 0.08

const RISK_ATTENTION_BASE: Array[float] = [0.0, 1.0, 3.0, 6.0]
const RISK_ATTENTION_PER_HAUL: Array[float] = [0.0, 0.02, 0.04, 0.08]
const RISK_ATTENTION_CAP: Array[float] = [0.0, 4.0, 10.0, 20.0]

const PARTIAL_LOSS_THRESHOLDS: Array[float] = [1.0, 0.92, 0.82, 0.70]
const PARTIAL_LOSS_RETAIN_MIN: Array[float] = [1.0, 0.85, 0.70, 0.40]
const PARTIAL_LOSS_RETAIN_MAX: Array[float] = [1.0, 0.95, 0.85, 0.70]

const INJURY_CHANCE_BASE: Array[float] = [0.0, 0.02, 0.06, 0.12]
const INJURY_FATALITY_GIVEN_INJURY := 0.15

const FATIGUE_BASE: Array[int] = [0, 1, 2, 4]

const EXPEDITION_RISK_LABELS := {
	0: "safe",
	1: "low",
	2: "medium",
	3: "high",
}

const RNG_OFFSET_ACTIVE_EXPEDITION_ALLOCATION := RNG_OFFSET_ACTIVE_EXPEDITION + 100
const RNG_OFFSET_ACTIVE_EXPEDITION_RISK := RNG_OFFSET_ACTIVE_EXPEDITION + 200
const RNG_OFFSET_ACTIVE_EXPEDITION_INJURY := RNG_OFFSET_ACTIVE_EXPEDITION + 300

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
const TRADE_ATTENTION_BASE: float = 0.5
const TRADE_ATTENTION_PER_UNIT: float = 0.02
const TRADE_ATTENTION_CAP: float = 5.0
const TRADE_MAX_AMOUNT: int = 999

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
const PHASE_MORALE := "morale"

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
const CMD_OUTSIDERS_DECISION := "OUTSIDERS_DECISION"

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

const LABOR_OVERDRIVE_MULT_PER_LEVEL := 0.25
const LABOR_OVERDRIVE_MAX_INTENSITY := 5
const LABOR_SCAR_PER_DAY := 0.2
const LABOR_SCAR_EFFICIENCY_MULT := 0.05
const LABOR_EFFICIENCY_MIN := 0.6
const LABOR_SCAR_THREAT_MULT := 0.2
const LABOR_OVERDRIVE_REASON_LABELS := {
	"power": "power shortfall",
	"inputs": "missing inputs",
}

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
var _morale_tier: int = MORALE_TIER_STABLE
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

# Map and active expeditions (state machine driven).
var map_def: MapDefRef = null
var active_expedition: Dictionary = {}  # Single active expedition; empty if none.
var location_heat: Dictionary = {}
var pending_outsiders: Dictionary = {}
var rejected_outsiders_days_left: int = 0
var expedition_id_counter: int = 0
var pending_arrival_id_counter: int = 0

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
var _people: Array[Dictionary] = []
var _next_person_id: int = 1
var people_system_version: int = PEOPLE_SYSTEM_VERSION
var pending_outsider_identities: Dictionary = {}
const _SIM_STATE_SIMPLE_KEYS: Array[String] = [
	"day",
	"hour_index",
	"hour_of_day",
	"phase",
	"_accum",
	"sim_seed",
	"_last_obs_tokens",
	"_last_module_snapshots",
	"_last_production_metrics",
	"lever_events",
	"events",
	"visibility_triggered",
	"_event_sequence",
	"_morale_tier",
	"_last_maintenance_shortfall",
	"_last_attention_summary_hour_index",
	"_last_attention_summary_value",
	"_hourly_food_accum",
	"_hourly_water_accum",
	"_daily_food_consumed",
	"_daily_water_consumed",
	"scheduled_production_hour",
	"production_executed_today",
	"_daily_rolls",
	"unrest_active",
	"unrest_hours",
	"exit_reason",
	"_lever_active_state",
	"food_ration",
	"water_ration",
	"scav_pools",
	"expedition_crew_today",
	"expedition_threat_today",
	"expedition_morale_penalty_today",
	"ration_morale_penalty_today",
	"ration_threat_penalty_today",
	"workforce_multiplier_today",
	"ration_consumption_multiplier_today",
	"ration_recovery_multiplier_today",
	"labor_output_multiplier_today",
	"labor_efficiency_cap_today",
	"expedition_yield_bonus_per_crew_today",
	"expedition_attention_bonus_per_trip_today",
	"info_throttle_morale_factor_today",
	"info_misalloc_multiplier_today",
	"lever_threat_bonus_today",
	"expedition_count_total",
	"expedition_streak",
	"expedition_recent_score",
	"expedition_heat",
	"expedition_commands_today",
	"expedition_happened_today",
	"active_expedition",
	"location_heat",
	"pending_outsiders",
	"rejected_outsiders_days_left",
	"expedition_id_counter",
	"pending_arrival_id_counter",
	"expedition_counter",
	"_delayed_consequence_queue",
	"_delayed_insertion_counter",
	"_consequence_queue",
	"_consequence_insertion_counter",
	"_structural_telegraph_level",
	"_structural_warning_logged",
	"_structural_high_strain_days",
	"_structural_collapse_scheduled",
	"ration_hardening_ticks_left",
	"ration_hardening_start_hour_index",
	"ration_hardening_duration_hours",
	"ration_hardening_end_hour_index",
	"ration_hardening_hours_left",
	"ration_hardening_mode",
	"ration_scar",
	"labor_overdrive_ticks_left",
	"labor_overdrive_start_hour_index",
	"labor_overdrive_duration_hours",
	"labor_overdrive_end_hour_index",
	"labor_overdrive_hours_left",
	"labor_overdrive_intensity",
	"labor_scar",
	"expedition_compression_ticks_left",
	"expedition_compression_start_hour_index",
	"expedition_compression_duration_hours",
	"expedition_compression_end_hour_index",
	"expedition_compression_hours_left",
	"expedition_compression_intensity",
	"expedition_attention",
	"info_throttle_ticks_left",
	"info_throttle_start_hour_index",
	"info_throttle_duration_hours",
	"info_throttle_end_hour_index",
	"info_throttle_hours_left",
	"info_throttle_level",
	"info_throttle_backlog",
	"abandoned_modules",
	"conversion_scar",
	"conversion_burn_counts",
	"pending_conversions",
	"_people",
	"_next_person_id",
	"people_system_version",
	"pending_outsider_identities",
]

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
	_tick_active_expedition()
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
	map_def = MapDefRef.new()
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
	_reset_people_state(res.population)

	_refresh_module_snapshots({})

func _reset_people_state(initial_population: int) -> void:
	_people.clear()
	_next_person_id = 1
	people_system_version = PEOPLE_SYSTEM_VERSION
	_sync_people_to_population(max(initial_population, 0), "init", day)

func _sync_people_to_population(target_population: int, cause: String, event_day: int) -> void:
	var target: int = max(target_population, 0)
	var alive_count: int = _alive_people_count()
	if alive_count < target:
		_add_people(target - alive_count, event_day, PEOPLE_STATUS_HOME)
		return
	if alive_count > target:
		var loss: int = alive_count - target
		_kill_people(loss, cause, event_day, false)

func _trim_people_to_population(target_population: int) -> void:
	var target: int = max(target_population, 0)
	while _people.size() > target:
		_people.pop_back()
	_next_person_id = max(_next_person_id, _people.size() + 1)

func _add_people(count: int, joined_day: int, status: String) -> Array[int]:
	var safe_count: int = max(count, 0)
	var ids: Array[int] = []
	var safe_joined_day: int = joined_day
	if safe_joined_day < 0:
		safe_joined_day = day
	var safe_status: String = status if status != "" else PEOPLE_STATUS_HOME
	for _i in range(safe_count):
		var person_id := _next_person_id
		_next_person_id += 1
		_people.append(_make_person(person_id, safe_joined_day, safe_status))
		ids.append(person_id)
	return ids

func _make_person(person_id: int, joined_day: int, status: String) -> Dictionary:
	var index: int = max(person_id - 1, 0)
	var first_idx := int(index % PEOPLE_FIRST_NAMES.size())
	var last_idx: int = int(floor(float(index) / float(PEOPLE_FIRST_NAMES.size()))) % PEOPLE_LAST_NAMES.size()
	var first := PEOPLE_FIRST_NAMES[first_idx]
	var last := PEOPLE_LAST_NAMES[last_idx]
	var generation: int = int(floor(float(index) / float(PEOPLE_FIRST_NAMES.size() * PEOPLE_LAST_NAMES.size())))
	var full_name := "%s %s" % [first, last]
	if generation > 0:
		full_name = "%s %s (%d)" % [first, last, generation + 1]
	return {
		"id": person_id,
		"first": first,
		"last": last,
		"name": full_name,
		"status": status,
		"joined_day": joined_day,
		"death_day": -1,
		"death_cause": "",
	}

func _alive_people_count() -> int:
	var count: int = 0
	for entry in _people:
		if not (entry is Dictionary):
			continue
		var status: String = str((entry as Dictionary).get("status", PEOPLE_STATUS_HOME))
		if status != PEOPLE_STATUS_DEAD:
			count += 1
	return count

func _find_person_index_by_id(person_id: int) -> int:
	if person_id <= 0:
		return -1
	for i in range(_people.size()):
		var entry: Variant = _people[i]
		if entry is Dictionary and int((entry as Dictionary).get("id", 0)) == person_id:
			return i
	return -1

func _insert_person_sorted(person: Dictionary) -> void:
	var person_id: int = int(person.get("id", 0))
	if person_id <= 0:
		return
	if _people.is_empty():
		_people.append(person)
		return
	var insert_idx: int = _people.size()
	for i in range(_people.size()):
		var entry: Variant = _people[i]
		if entry is Dictionary and int((entry as Dictionary).get("id", 0)) > person_id:
			insert_idx = i
			break
	_people.insert(insert_idx, person)

func _home_people_ids_sorted() -> Array[int]:
	var ids: Array[int] = []
	for entry in _people:
		if not (entry is Dictionary):
			continue
		var person: Dictionary = entry as Dictionary
		var status: String = str(person.get("status", PEOPLE_STATUS_HOME))
		if status == PEOPLE_STATUS_HOME:
			ids.append(int(person.get("id", 0)))
	return ids

func _home_people_count() -> int:
	return _home_people_ids_sorted().size()

func _select_home_people(count: int) -> Array[int]:
	var requested: int = max(count, 0)
	if requested <= 0:
		return []
	var home_ids := _home_people_ids_sorted()
	var selected: Array[int] = []
	var limit: int = min(requested, home_ids.size())
	for i in range(limit):
		selected.append(home_ids[i])
	return selected

func _set_people_status(ids: Array[int], status: String) -> void:
	if ids.is_empty():
		return
	for person_id in ids:
		var idx := _find_person_index_by_id(int(person_id))
		if idx < 0:
			continue
		var entry: Variant = _people[idx]
		if entry is Dictionary:
			(entry as Dictionary)["status"] = status

func _select_casualty_ids(count: int) -> Array[int]:
	var requested: int = max(count, 0)
	if requested <= 0:
		return []
	var home_ids := _home_people_ids_sorted()
	home_ids.reverse()
	var away_ids: Array[int] = []
	var injured_ids: Array[int] = []
	for entry in _people:
		if not (entry is Dictionary):
			continue
		var person: Dictionary = entry as Dictionary
		var status: String = str(person.get("status", PEOPLE_STATUS_HOME))
		var person_id: int = int(person.get("id", 0))
		if status == PEOPLE_STATUS_AWAY:
			away_ids.append(person_id)
		elif status == PEOPLE_STATUS_INJURED:
			injured_ids.append(person_id)
	away_ids.reverse()
	injured_ids.reverse()
	var pool: Array[int] = []
	pool.append_array(home_ids)
	pool.append_array(away_ids)
	pool.append_array(injured_ids)
	var selected: Array[int] = []
	var limit: int = min(requested, pool.size())
	for i in range(limit):
		selected.append(pool[i])
	return selected

func _kill_people(count: int, cause: String, event_day: int, emit_event: bool) -> Array[int]:
	var ids := _select_casualty_ids(count)
	if ids.is_empty():
		return []
	for person_id in ids:
		var idx := _find_person_index_by_id(int(person_id))
		if idx < 0:
			continue
		var entry: Variant = _people[idx]
		if entry is Dictionary:
			var person: Dictionary = entry as Dictionary
			person["status"] = PEOPLE_STATUS_DEAD
			person["death_day"] = event_day
			person["death_cause"] = cause
	if emit_event:
		var names := _names_for_ids(ids)
		var message := "%d lost: %s." % [ids.size(), _format_names_list(names)]
		_emit_event(
			"POPULATION_CASUALTIES",
			message,
			"warn",
			"player_feed",
			{
				"count": ids.size(),
				"cause": cause,
				"ids": ids,
				"names": names,
			},
			"population",
			event_day,
			hour_of_day,
			true
		)
	return ids

func _kill_people_by_ids(ids: Array[int], cause: String, event_day: int) -> void:
	if ids.is_empty():
		return
	for person_id in ids:
		var idx := _find_person_index_by_id(int(person_id))
		if idx < 0:
			continue
		var entry: Variant = _people[idx]
		if entry is Dictionary:
			var person: Dictionary = entry as Dictionary
			person["status"] = PEOPLE_STATUS_DEAD
			person["death_day"] = event_day
			person["death_cause"] = cause

func _apply_population_loss(loss_count: int, cause: String, event_day: int, event_type: String, message_prefix: String) -> Array[int]:
	if res == null:
		return []
	var count: int = max(loss_count, 0)
	if count <= 0:
		return []
	_ensure_people_initialized()
	var ids := _select_casualty_ids(count)
	if ids.is_empty():
		return []
	res.population = max(res.population - ids.size(), 0)
	_kill_people_by_ids(ids, cause, event_day)
	var names := _names_for_ids(ids)
	var message := "%s %s" % [message_prefix, _format_names_list(names)]
	_emit_event(
		event_type,
		message,
		"warn",
		"player_feed",
		{
			"count": ids.size(),
			"cause": cause,
			"ids": ids,
			"names": names,
		},
		"population",
		event_day,
		hour_of_day,
		true
	)
	return ids

func _names_for_ids(ids: Array[int]) -> Array[String]:
	var names: Array[String] = []
	for person_id in ids:
		var idx := _find_person_index_by_id(int(person_id))
		if idx < 0:
			names.append(_person_name_for_id(int(person_id)))
			continue
		var entry: Variant = _people[idx]
		if entry is Dictionary:
			names.append(str((entry as Dictionary).get("name", _person_name_for_id(int(person_id)))))
	return names

func _person_name_for_id(person_id: int) -> String:
	var index: int = max(person_id - 1, 0)
	var first_idx := int(index % PEOPLE_FIRST_NAMES.size())
	var last_idx: int = int(floor(float(index) / float(PEOPLE_FIRST_NAMES.size()))) % PEOPLE_LAST_NAMES.size()
	var first := PEOPLE_FIRST_NAMES[first_idx]
	var last := PEOPLE_LAST_NAMES[last_idx]
	var generation: int = int(floor(float(index) / float(PEOPLE_FIRST_NAMES.size() * PEOPLE_LAST_NAMES.size())))
	if generation > 0:
		return "%s %s (%d)" % [first, last, generation + 1]
	return "%s %s" % [first, last]

func _format_names_list(names: Array[String]) -> String:
	if names.is_empty():
		return "none"
	if names.size() <= 3:
		return ", ".join(names)
	return "%s, %s, and %d others" % [names[0], names[1], names.size() - 2]

func _ensure_people_initialized() -> void:
	if not _people.is_empty():
		for i in range(_people.size()):
			var entry: Variant = _people[i]
			if not (entry is Dictionary):
				continue
			var person: Dictionary = entry as Dictionary
			if not person.has("status"):
				person["status"] = PEOPLE_STATUS_HOME
			if not person.has("joined_day"):
				person["joined_day"] = day
			if not person.has("death_day"):
				person["death_day"] = -1
			if not person.has("death_cause"):
				person["death_cause"] = ""
			if not person.has("name"):
				var person_id: int = int(person.get("id", 0))
				person["name"] = _person_name_for_id(person_id)
		people_system_version = PEOPLE_SYSTEM_VERSION
		return
	if res == null:
		return
	var population: int = max(int(res.population), 0)
	if population <= 0:
		return
	_reset_people_state(population)

func _reserve_outsider_identities(group_size: int, joined_day: int) -> Array[Dictionary]:
	var identities: Array[Dictionary] = []
	var count: int = max(group_size, 0)
	for _i in range(count):
		var person_id := _next_person_id
		_next_person_id += 1
		var record := _make_person(person_id, joined_day, "pending")
		identities.append(record)
	return identities

func _next_pending_arrival_id() -> int:
	var candidate: int = pending_arrival_id_counter + 1
	while pending_outsiders.has(candidate):
		candidate += 1
	pending_arrival_id_counter = candidate
	return candidate

func _ids_from_identities(identities: Array[Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	for identity in identities:
		ids.append(int(identity.get("id", 0)))
	return ids

func _names_from_identities(identities: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for identity in identities:
		names.append(str(identity.get("name", "")))
	return names

func _add_reserved_people(identities: Array[Dictionary], joined_day: int) -> Array[int]:
	var added_ids: Array[int] = []
	for identity in identities:
		var person_id: int = int(identity.get("id", 0))
		if person_id <= 0:
			continue
		if _find_person_index_by_id(person_id) >= 0:
			continue
		var person := _make_person(person_id, joined_day, PEOPLE_STATUS_HOME)
		_insert_person_sorted(person)
		added_ids.append(person_id)
	return added_ids

func _current_housing_capacity() -> int:
	if tower == null or db == null:
		return 0
	var total_capacity := 0
	for f in range(tower.floors.size()):
		var floor_data: Variant = tower.floors[f]
		if floor_data == null or not (floor_data is Array):
			continue
		var grid: Array = floor_data as Array
		for y in range(tower.height):
			if y < 0 or y >= grid.size():
				continue
			var row_candidate: Variant = grid[y]
			if row_candidate == null or not (row_candidate is Array):
				continue
			var row: Array = row_candidate as Array
			for x in range(tower.width):
				if x < 0 or x >= row.size():
					continue
				var module_id: Variant = row[x]
				if module_id == null:
					continue
				if _is_module_abandoned(f, x, y):
					continue
				if not tower.is_module_enabled(f, x, y):
					continue
				var def: ModuleDef = db.get_def(str(module_id))
				if def == null:
					continue
				total_capacity += def.delta_capacity
	return total_capacity

func _roll_expedition_survivors(expedition_id: int) -> int:
	var tracker := _create_rng_tracker(day, PHASE_EXPEDITIONS, "expedition_survivors_%d" % expedition_id, RNG_OFFSET_EXPEDITION_SURVIVORS)
	var roll := int(_rng_randi(tracker) % 100)
	if roll < 50:
		return 1
	if roll < 80:
		return 2
	if roll < 90:
		return 3
	if roll < 95:
		return 4
	if roll < 98:
		return 5
	return 6

func _apply_expedition_survivors(
	survivors_gained: int,
	expedition_id: int,
	destination_id: String,
	destination_name: String
) -> Dictionary:
	var entry: Dictionary = {}
	if res == null:
		return entry
	if survivors_gained <= 0:
		return entry
	_ensure_people_initialized()
	var event_id := _next_pending_arrival_id()
	var identities := _reserve_outsider_identities(survivors_gained, day)
	pending_outsider_identities[event_id] = identities
	var survivor_ids := _ids_from_identities(identities)
	var survivor_names := _names_from_identities(identities)
	entry = {
		"id": event_id,
		"expedition_id": expedition_id,
		"destination_id": destination_id,
		"destination_name": destination_name,
		"kind": "expedition_survivors",
		"group_size": identities.size(),
		"count": identities.size(),
		"created_day": day,
		"created_hour": hour_of_day,
		"survivor_ids": survivor_ids,
		"survivor_names": survivor_names,
		"names": survivor_names.duplicate(),
		"command_admit": "SURVIVORS_ADMIT %d" % event_id,
		"command_reject": "SURVIVORS_REJECT %d" % event_id,
	}
	pending_outsiders[event_id] = entry
	active_expedition["survivors_gained"] = survivors_gained
	active_expedition["pending_survivor_event_id"] = event_id
	return entry

func _apply_overcrowding_penalty(population_before: int) -> void:
	if res == null:
		return
	var capacity := _current_housing_capacity()
	if capacity <= 0:
		return
	var previous_home_population: int = maxi(population_before - _current_away_crew(), 0)
	if previous_home_population > capacity:
		return
	var home_population: int = _home_population()
	if home_population <= capacity:
		return
	var over: int = home_population - capacity
	var morale_penalty: int = max(over, 1)
	res.morale -= morale_penalty
	var payload := {
		"population": res.population,
		"capacity": capacity,
		"morale_penalty": morale_penalty,
	}
	var message := "Overcrowding after expedition: population %d exceeds housing capacity %d. Build more housing/floors." % [res.population, capacity]
	_emit_event(
		"HOUSING_OVERCROWDING",
		message,
		"warn",
		"player_feed",
		payload,
		"housing",
		day,
		hour_of_day,
		true
	)

func _current_away_crew() -> int:
	if active_expedition.is_empty():
		return 0
	var state := str(active_expedition.get("state", ""))
	if state == EXPEDITION_STATE_RESOLVED or state == EXPEDITION_STATE_FAILED:
		return 0
	var member_ids := _expedition_member_ids(active_expedition)
	if not member_ids.is_empty():
		return maxi(member_ids.size(), 0)
	var party_size: int = int(active_expedition.get("party_size", 0))
	if party_size <= 0:
		party_size = int(active_expedition.get("crew", 0))
	return maxi(party_size, 0)

func _home_population() -> int:
	if res == null:
		return 0
	var total_population: int = int(res.population)
	return maxi(total_population - _current_away_crew(), 0)

func _max_party_size(total_population: int) -> int:
	var safe_total: int = maxi(total_population, 0)
	if safe_total <= 0:
		return 0
	var scaled: float = float(safe_total) * 0.33
	var max_by_pop: int = int(floor(scaled))
	var cap_by_rule: int = max_by_pop
	if cap_by_rule > 10:
		cap_by_rule = 10
	return maxi(1, min(cap_by_rule, safe_total))

func _party_size_multiplier(party_size: int) -> float:
	if party_size <= 4:
		return 1.0
	if party_size <= 7:
		return 0.9
	return 0.8

func _expedition_party_size(expedition: Dictionary) -> int:
	if expedition == null or expedition.is_empty():
		return 0
	var party_size: int = int(expedition.get("party_size", 0))
	if party_size <= 0:
		party_size = int(expedition.get("crew", 0))
	return maxi(party_size, 0)

func _expedition_member_ids(expedition: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	if expedition == null or expedition.is_empty():
		return ids
	var raw: Variant = expedition.get("member_ids", [])
	if raw is Array:
		for entry in raw:
			ids.append(int(entry))
	return ids

func _select_casualties_from_members(member_ids: Array[int], count: int) -> Array[int]:
	var requested: int = max(count, 0)
	if requested <= 0 or member_ids.is_empty():
		return []
	var selected: Array[int] = []
	var idx: int = member_ids.size() - 1
	while idx >= 0 and selected.size() < requested:
		selected.append(int(member_ids[idx]))
		idx -= 1
	return selected

func _get_location_heat(location_id: String) -> int:
	if location_id == "":
		return 0
	var value: Variant = location_heat.get(location_id, 0)
	return maxi(int(value), 0)

func _increment_location_heat(location_id: String) -> int:
	if location_id == "":
		return 0
	var current: int = _get_location_heat(location_id)
	var next_value: int = current + 1
	location_heat[location_id] = next_value
	return next_value

func _decay_location_heat() -> void:
	if location_heat.is_empty():
		return
	var keys: Array = location_heat.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		var current: int = maxi(int(location_heat.get(key, 0)), 0)
		var next_value: int = maxi(current - 1, 0)
		if next_value <= 0:
			location_heat.erase(key)
		else:
			location_heat[key] = next_value

func _string_seed(source: String) -> int:
	var accumulator: int = 0
	for i in range(source.length()):
		accumulator = int((accumulator * 31 + source.unicode_at(i)) & RNG_CONTEXT_SEED_MASK)
	return accumulator

func _outsiders_seed(
	expedition_id: int,
	destination_id: String,
	return_hour_index: int,
	party_size: int,
	heat: int
) -> int:
	var accumulator: int = int(sim_seed)
	accumulator += expedition_id * 83492791
	accumulator += return_hour_index * 2654435761
	accumulator += party_size * 15485863
	accumulator += heat * 49979687
	accumulator += _string_seed(destination_id)
	accumulator = int((accumulator * RNG_BASE_MULTIPLIER) & RNG_CONTEXT_SEED_MASK)
	return accumulator

func _away_ratio(total_population: int) -> float:
	var safe_total: int = maxi(total_population, 0)
	if safe_total <= 0:
		return 0.0
	var away: int = _current_away_crew()
	if away <= 0:
		return 0.0
	return float(away) / float(safe_total)

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
	_morale_tier = MORALE_TIER_STABLE
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
	active_expedition.clear()
	location_heat.clear()
	pending_outsiders.clear()
	rejected_outsiders_days_left = 0
	expedition_id_counter = 0
	pending_arrival_id_counter = 0
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
	_ensure_people_initialized()
	production_executed_today = false
	_decay_location_heat()
	if rejected_outsiders_days_left > 0:
		rejected_outsiders_days_left = maxi(rejected_outsiders_days_left - 1, 0)
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
	var amount_value: int = int(amount)
	var payload := {
		"direction": normalized_direction,
		"resource": normalized_resource,
		"amount": amount_value,
	}
	var result := {"ok": false, "message": "INVALID TRADE"}
	if normalized_direction != "buy" and normalized_direction != "sell":
		result["message"] = "INVALID ACTION"
		return result
	if not TRADEABLE_RESOURCES.has(normalized_resource):
		result["message"] = "INVALID RESOURCE"
		return result
	if amount_value <= 0 or amount_value > TRADE_MAX_AMOUNT:
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

func get_attention_meter_value() -> float:
	return expedition_attention

func get_attention_meter_max() -> float:
	return ATTENTION_METER_MAX

func get_threat_meter_value() -> int:
	if res == null:
		return 0
	return int(res.threat)

func get_threat_meter_max() -> int:
	return THREAT_METER_MAX

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

func _morale_tier_raw(value: int) -> int:
	if value < MORALE_NONCOMPLIANT_ENTER:
		return MORALE_TIER_NONCOMPLIANT
	if value <= MORALE_OPTIONAL_ENTER:
		return MORALE_TIER_OPTIONAL
	if value <= MORALE_WARNING_3_ENTER:
		return MORALE_TIER_WARNING_3
	if value <= MORALE_WARNING_2_ENTER:
		return MORALE_TIER_WARNING_2
	if value <= MORALE_WARNING_1_ENTER:
		return MORALE_TIER_WARNING_1
	return MORALE_TIER_STABLE

func _morale_tier_exit_threshold(tier: int) -> int:
	match tier:
		MORALE_TIER_NONCOMPLIANT:
			return MORALE_NONCOMPLIANT_EXIT
		MORALE_TIER_OPTIONAL:
			return MORALE_OPTIONAL_EXIT
		MORALE_TIER_WARNING_3:
			return MORALE_WARNING_3_EXIT
		MORALE_TIER_WARNING_2:
			return MORALE_WARNING_2_EXIT
		MORALE_TIER_WARNING_1:
			return MORALE_WARNING_1_EXIT
		_:
			return 1000

func _morale_tier_from_value(value: int, current_tier: int) -> int:
	var raw_tier := _morale_tier_raw(value)
	if raw_tier > current_tier:
		return raw_tier
	if raw_tier == current_tier:
		return current_tier
	var next := current_tier
	while next > raw_tier:
		var exit_threshold := _morale_tier_exit_threshold(next)
		if value >= exit_threshold:
			next -= 1
		else:
			break
	return next

func _morale_tier_label(tier: int) -> String:
	match tier:
		MORALE_TIER_WARNING_1:
			return "warning_1"
		MORALE_TIER_WARNING_2:
			return "warning_2"
		MORALE_TIER_WARNING_3:
			return "warning_3"
		MORALE_TIER_OPTIONAL:
			return "optional"
		MORALE_TIER_NONCOMPLIANT:
			return "noncompliant"
		_:
			return "stable"

func _morale_tier_severity(tier: int) -> String:
	if tier == MORALE_TIER_STABLE:
		return "info"
	return "warn"

func _morale_tier_message(tier: int, value: int) -> String:
	match tier:
		MORALE_TIER_WARNING_1:
			return "Unrest rising. Morale at %d." % value
		MORALE_TIER_WARNING_2:
			return "Strain deepening. Morale at %d." % value
		MORALE_TIER_WARNING_3:
			return "Breakdown risk. Morale at %d." % value
		MORALE_TIER_OPTIONAL:
			return "Compliance is optional. Morale at %d." % value
		MORALE_TIER_NONCOMPLIANT:
			return "NONCOMPLIANT. Mutiny risk rising. Morale at %d." % value
		_:
			return "Morale stabilizing. Morale at %d." % value

func _update_morale_tier(value: int, sim_day: int, include_hour: bool) -> void:
	var next_tier := _morale_tier_from_value(value, _morale_tier)
	if next_tier == _morale_tier:
		return
	_morale_tier = next_tier
	var payload := {
		"tier": _morale_tier_label(next_tier),
		"value": value,
	}
	_emit_event(
		"MORALE_BAND_CROSSED",
		_morale_tier_message(next_tier, value),
		_morale_tier_severity(next_tier),
		"sticky",
		payload,
		"morale",
		sim_day,
		hour_of_day,
		include_hour
	)

func _compliance_stall_chance_for_tier(tier: int) -> float:
	match tier:
		MORALE_TIER_OPTIONAL:
			return COMPLIANCE_OPTIONAL_STALL_CHANCE
		MORALE_TIER_NONCOMPLIANT:
			return COMPLIANCE_NONCOMPLIANT_STALL_CHANCE
		_:
			return 0.0

func _command_subject_to_compliance(command_type: String) -> bool:
	return command_type == CMD_EXPEDITION or command_type == CMD_TRADE

func _emit_morale_band_events(_pre_morale: int, post_morale: int, sim_day: int) -> void:
	_update_morale_tier(post_morale, sim_day, true)

func _run_mutiny_roll(sim_day: int, sim_res: Resources, obs: Array[String]) -> void:
	if sim_res.morale >= MORALE_NONCOMPLIANT_ENTER:
		return
	if exit_reason != "":
		return
	var tracker := _create_rng_tracker(sim_day, PHASE_MORALE, "mutiny_roll", RNG_OFFSET_MUTINY)
	var roll: float = _rng_randf(tracker)
	var morale_gap: int = max(MORALE_NONCOMPLIANT_ENTER - sim_res.morale, 0)
	var chance: float = float(clamp(
		MUTINY_ROLL_BASE + float(morale_gap) * MUTINY_ROLL_PER_POINT,
		0.0,
		MUTINY_ROLL_CAP
	))
	var payload := {
		"roll": roll,
		"chance": chance,
		"morale": sim_res.morale,
	}
	_emit_event(
		"MUTINY_ROLL",
		"Mutiny check roll=%.3f vs %.3f." % [roll, chance],
		"debug",
		"dev_only",
		payload,
		"morale",
		sim_day,
		hour_of_day,
		true
	)
	if roll < chance:
		exit_reason = EXIT_MUTINY
		_emit_event(
			"MUTINY_TRIGGERED",
			"Mutiny erupts. Command authority collapsing.",
			"warn",
			"sticky",
			payload,
			"morale",
			sim_day,
			hour_of_day,
			true
		)
		_obs_push(obs, "MUTINY_TRIGGERED")

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
		var extra_chance: float = 0.0
		if rejected_outsiders_days_left > 0:
			extra_chance += OUTSIDERS_INCIDENT_BONUS
		var away_ratio: float = _away_ratio(int(sim_res.population))
		if away_ratio > AWAY_RATIO_THRESHOLD:
			extra_chance += (away_ratio - AWAY_RATIO_THRESHOLD) * 0.50
		var adjusted_chance: float = chance + extra_chance
		if adjusted_chance < 0.0:
			adjusted_chance = 0.0
		elif adjusted_chance > 1.0:
			adjusted_chance = 1.0
		var roll: float = _rng_randf(tracker)
		if roll <= adjusted_chance:
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
			value = int(ceil(float(value) * multiplier))
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

	var compliance_tier := _morale_tier
	var compliance_chance := _compliance_stall_chance_for_tier(compliance_tier)
	var compliance_tracker: Dictionary = {}
	if compliance_chance > 0.0:
		compliance_tracker = _create_rng_tracker(_sim_day, PHASE_COMMANDS, "compliance", RNG_OFFSET_COMPLIANCE)

	for cmd in _command_queue:
		if cmd == null:
			continue
		var cmd_type: String = cmd.type
		if compliance_chance > 0.0 and _command_subject_to_compliance(cmd_type):
			var roll := _rng_randf(compliance_tracker)
			if roll < compliance_chance:
				var message := "Command stalled (%s). Compliance degraded." % cmd_type
				_emit_event(
					"COMPLIANCE_STALL",
					message,
					"warn",
					"dev_only",
					{"command": cmd_type, "roll": roll, "chance": compliance_chance},
					"morale",
					_sim_day,
					hour_of_day,
					true
				)
				_obs_push(obs, "CMD_STALL@%s" % cmd_type)
				continue
		match cmd_type:
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
			CMD_OUTSIDERS_DECISION:
				_cmd_outsiders_decision(cmd.payload, sim_res, obs, _sim_day)
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
	# Map-driven expeditions: destination_id is required.
	var destination_id: String = str(payload.get("destination_id", ""))
	if destination_id == "":
		# Fallback to legacy "target" for backward compatibility during transition.
		destination_id = str(payload.get("target", ""))

	_ensure_people_initialized()

	var requested_party_size: int = int(payload.get("party_size", payload.get("crew", 1)))
	var home_count: int = _home_people_count()
	if home_count <= 0:
		home_count = int(sim_res.population)
	var max_party_size: int = _max_party_size(home_count)
	if max_party_size <= 0:
		_obs_push(obs, "EXPEDITION_ABORT@NO_CREW")
		return
	var party_size: int = clampi(requested_party_size, 1, max_party_size)
	if party_size < requested_party_size:
		_obs_push(obs, "EXPEDITION_CREW_REDUCED@%d->%d" % [requested_party_size, party_size])
	var crew: int = party_size
	_obs_push(obs, "CMD:EXPEDITION@%s" % destination_id)

	# Validate destination if map_def is available.
	if map_def != null and destination_id != "":
		if not map_def.is_valid_destination(destination_id):
			_obs_push(obs, "EXPEDITION_ABORT@INVALID_DESTINATION")
			return

	if crew <= 0:
		_obs_push(obs, "EXPEDITION_ABORT@NO_CREW")
		return

	# If map-driven expedition is already active, reject.
	if has_active_expedition():
		_obs_push(obs, "EXPEDITION_ABORT@ALREADY_ACTIVE")
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

	# If map_def is available and destination is a map location, use map-driven logic.
	if map_def != null and map_def.is_valid_destination(destination_id):
		var result := launch_expedition(destination_id, crew, party_size)
		if result.get("ok", false):
			_obs_push(obs, "MAP_EXPEDITION_LAUNCHED@%s" % destination_id)
		else:
			_obs_push(obs, "MAP_EXPEDITION_FAILED@%s" % str(result.get("message", "")))
		return

	# Legacy scav_pools fallback for backward compatibility.
	var heat_after_launch: int = _increment_location_heat(destination_id)
	var target := destination_id
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
	var expected_haul: int = (8 * crew) + bonus_yield
	var multiplier: float = _party_size_multiplier(crew)
	var heat_multiplier: float = maxf(1.0 - (0.12 * float(heat_after_launch)), 0.0)
	var capacity_units: int = 12 * crew
	var raw_haul: float = float(expected_haul) * multiplier * heat_multiplier
	var haul_units: int = int(min(float(capacity_units), maxf(raw_haul, 0.0)))
	var yield_amount: int = int(min(remaining, haul_units))
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
	var attention_gain: int = 2 + int(ceil(0.6 * float(crew))) + heat_after_launch
	expedition_attention += float(attention_gain)
	expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)
	_obs_push(obs, "ATTN+%d" % attention_gain)


func _cmd_outsiders_decision(payload: Dictionary, sim_res: Resources, obs: Array[String], sim_day: int) -> void:
	if payload == null:
		return
	var event_id: int = int(payload.get("event_id", -1))
	if event_id < 0:
		_obs_push(obs, "OUTSIDERS_DECISION@INVALID_ID")
		return
	if not pending_outsiders.has(event_id):
		_obs_push(obs, "OUTSIDERS_DECISION@MISSING")
		return
	var entry_value: Variant = pending_outsiders.get(event_id, {})
	var entry: Dictionary = entry_value as Dictionary if entry_value is Dictionary else {}
	var accept: bool = bool(payload.get("accept", false))
	var kind: String = str(entry.get("kind", "gate_outsiders"))
	var group_size: int = maxi(int(entry.get("group_size", 0)), 0)
	var base_payload := entry.duplicate(true)
	base_payload["decision"] = "accept" if accept else "reject"
	base_payload["event_id"] = event_id
	_ensure_people_initialized()
	var identities: Array[Dictionary] = []
	if pending_outsider_identities.has(event_id):
		var identity_value: Variant = pending_outsider_identities.get(event_id, [])
		if identity_value is Array:
			identities = identity_value
	if identities.is_empty() and group_size > 0:
		identities = _reserve_outsider_identities(group_size, sim_day)
	if not identities.is_empty():
		group_size = identities.size()
	var outsider_ids := _ids_from_identities(identities)
	var outsider_names := _names_from_identities(identities)
	base_payload["outsider_ids"] = outsider_ids
	base_payload["outsider_names"] = outsider_names
	base_payload["kind"] = kind
	if kind == "expedition_survivors":
		base_payload["survivor_ids"] = outsider_ids
		base_payload["survivor_names"] = outsider_names

	if kind == "expedition_survivors":
		if accept:
			var population_before := sim_res.population
			var added_ids: Array[int] = []
			if group_size > 0:
				sim_res.population += group_size
				added_ids = _add_reserved_people(identities, sim_day)
			_apply_overcrowding_penalty(population_before)
			base_payload["admitted_ids"] = added_ids
			base_payload["admitted_names"] = _names_for_ids(added_ids)
			_emit_event(
				"EXPEDITION_SURVIVORS_ADMITTED",
				"Expedition survivors admitted: %s. Population +%d." % [
					_format_names_list(outsider_names),
					group_size,
				],
				"info",
				"player_feed",
				base_payload,
				"expedition",
				sim_day,
				hour_of_day,
				true
			)
		else:
			base_payload["rejected_names"] = outsider_names
			_emit_event(
				"EXPEDITION_SURVIVORS_REJECTED",
				"Expedition survivors turned away: %s." % _format_names_list(outsider_names),
				"warn",
				"player_feed",
				base_payload,
				"expedition",
				sim_day,
				hour_of_day,
				true
			)
	elif accept:
		var population_before := sim_res.population
		var added_ids: Array[int] = []
		if group_size > 0:
			sim_res.population += group_size
			added_ids = _add_reserved_people(identities, sim_day)
		var food_cost: int = 2 * group_size
		var water_cost: int = 2 * group_size
		sim_res.food = maxi(sim_res.food - food_cost, 0)
		sim_res.water = maxi(sim_res.water - water_cost, 0)
		var attention_gain: int = 2 + group_size
		expedition_attention += float(attention_gain)
		expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)
		sim_res.morale += 1
		_apply_overcrowding_penalty(population_before)
		base_payload["food_cost"] = food_cost
		base_payload["water_cost"] = water_cost
		base_payload["attention_gain"] = attention_gain
		base_payload["morale_delta"] = 1
		base_payload["admitted_ids"] = added_ids
		base_payload["admitted_names"] = _names_for_ids(added_ids)
		_emit_event(
			"OUTSIDERS_ACCEPTED",
			"Outsiders admitted: %s. Population +%d." % [
				_format_names_list(outsider_names),
				group_size,
			],
			"info",
			"player_feed",
			base_payload,
			"expedition",
			sim_day,
			hour_of_day,
			true
		)
	else:
		expedition_attention += 1.0
		expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)
		sim_res.morale -= 2
		rejected_outsiders_days_left = OUTSIDERS_DECISION_DAYS
		base_payload["attention_gain"] = 1
		base_payload["morale_delta"] = -2
		base_payload["rejected_days"] = OUTSIDERS_DECISION_DAYS
		base_payload["rejected_names"] = outsider_names
		_emit_event(
			"OUTSIDERS_REJECTED",
			"Outsiders turned away: %s. Rumors spread." % _format_names_list(outsider_names),
			"warn",
			"player_feed",
			base_payload,
			"expedition",
			sim_day,
			hour_of_day,
			true
		)

	pending_outsider_identities.erase(event_id)
	pending_outsiders.erase(event_id)


# =============================================================================
# Map-driven expedition state machine (destination required).
# =============================================================================

func has_active_expedition() -> bool:
	return not active_expedition.is_empty()

func get_active_expedition() -> Dictionary:
	if active_expedition.is_empty():
		return {}
	return active_expedition.duplicate(true)

func can_launch_expedition() -> bool:
	return not has_active_expedition()

func launch_expedition(destination_id: String, crew: int, party_size: int = -1) -> Dictionary:
	## Attempts to launch an expedition to destination_id with crew members.
	## Returns {"ok": bool, "message": String, "expedition": Dictionary or null}.
	var result := {"ok": false, "message": "", "expedition": null}

	if has_active_expedition():
		result["message"] = "Expedition already in progress."
		return result

	if map_def == null:
		result["message"] = "Map not initialized."
		return result

	if not map_def.is_valid_destination(destination_id):
		result["message"] = "Invalid destination: %s" % destination_id
		return result

	var location: MapDefRef.LocationDef = map_def.get_location(destination_id)
	if location == null:
		result["message"] = "Destination not found: %s" % destination_id
		return result

	var requested_party_size: int = party_size if party_size > 0 else crew
	var max_party_size: int = _max_party_size(int(res.population))
	if max_party_size <= 0:
		result["message"] = "No crew available."
		return result
	var clamped_party_size: int = clampi(requested_party_size, 1, max_party_size)
	if clamped_party_size <= 0:
		result["message"] = "No crew available."
		return result
	var clamped_crew: int = clamped_party_size

	_ensure_people_initialized()
	var member_ids: Array[int] = _select_home_people(clamped_party_size)
	if member_ids.is_empty():
		result["message"] = "No crew available."
		return result
	if member_ids.size() < clamped_party_size:
		clamped_party_size = member_ids.size()
		clamped_crew = clamped_party_size
	_set_people_status(member_ids, PEOPLE_STATUS_AWAY)
	var member_names: Array[String] = _names_for_ids(member_ids)

	# Create expedition.
	expedition_id_counter += 1
	var exp_id := expedition_id_counter
	var total_hours := location.total_trip_hours()

	var heat_after_launch: int = _increment_location_heat(destination_id)
	active_expedition = {
		"id": exp_id,
		"destination_id": destination_id,
		"destination_name": location.name,
		"crew": clamped_crew,
		"party_size": clamped_party_size,
		"member_ids": member_ids.duplicate(),
		"member_names": member_names.duplicate(),
		"state": EXPEDITION_STATE_PLANNED,
		"yield_version": EXPEDITION_YIELD_VERSION_V2,
		"start_day": day,
		"start_hour": hour_index,
		"start_hour_index": hour_index,
		"estimated_return_hour": hour_index + total_hours,
		"distance_hours": location.distance_hours,
		"onsite_hours": location.onsite_hours,
		"total_hours": total_hours,
		"hours_in_state": 0,
		"risk_level": location.risk_level,
		"risk_label": str(EXPEDITION_RISK_LABELS.get(location.risk_level, "unknown")),
		"resources": location.resources.duplicate(true),
		"weight_profile": location.weight_profile.duplicate(true),
		"heat_at_launch": heat_after_launch,
		"yield_bonus_per_crew": expedition_yield_bonus_per_crew_today,
	}

	# Transition from PLANNED to OUTBOUND immediately.
	active_expedition["state"] = EXPEDITION_STATE_OUTBOUND
	active_expedition["hours_in_state"] = 0

	# Track visibility trigger.
	_mark_visibility_triggered()

	# Emit launch event.
	_emit_expedition_event(
		"EXPEDITION_LAUNCHED",
		"Expedition launched to %s. Crew: %s." % [location.name, _format_names_list(member_names)],
		"info",
		active_expedition.duplicate(true)
	)

	# Apply immediate effects (crew out, threat increase).
	expedition_crew_today += clamped_crew
	var threat_gain := 1 + int(ceil(float(clamped_crew) * 0.5))
	expedition_threat_today += threat_gain
	res.threat += threat_gain

	# Update expedition tracking.
	expedition_commands_today += 1
	expedition_count_total += 1
	if not expedition_happened_today:
		expedition_streak += 1
		expedition_happened_today = true
	_recompute_expedition_heat()
	expedition_counter = expedition_count_total

	result["ok"] = true
	result["message"] = "Expedition launched."
	result["expedition"] = active_expedition.duplicate(true)
	return result

func _tick_active_expedition() -> void:
	## Called every hour tick to progress the active expedition.
	if active_expedition.is_empty():
		return

	var state: String = str(active_expedition.get("state", ""))
	if state == EXPEDITION_STATE_RESOLVED or state == EXPEDITION_STATE_FAILED:
		# Clear completed expeditions.
		active_expedition.clear()
		return

	# Increment hours in current state.
	var hours_in_state := int(active_expedition.get("hours_in_state", 0)) + 1
	active_expedition["hours_in_state"] = hours_in_state

	# State transitions based on time.
	match state:
		EXPEDITION_STATE_OUTBOUND:
			var distance_hours := int(active_expedition.get("distance_hours", 1))
			if hours_in_state >= distance_hours:
				_expedition_transition_to(EXPEDITION_STATE_ONSITE)
		EXPEDITION_STATE_ONSITE:
			var onsite_hours := int(active_expedition.get("onsite_hours", 1))
			if hours_in_state >= onsite_hours:
				_expedition_apply_onsite_outcome()
				_expedition_transition_to(EXPEDITION_STATE_RETURNING)
		EXPEDITION_STATE_RETURNING:
			var distance_hours := int(active_expedition.get("distance_hours", 1))
			if hours_in_state >= distance_hours:
				_expedition_resolve()

func _expedition_transition_to(new_state: String) -> void:
	var _old_state: String = str(active_expedition.get("state", ""))
	active_expedition["state"] = new_state
	active_expedition["hours_in_state"] = 0

	var dest_name: String = str(active_expedition.get("destination_name", "unknown"))

	match new_state:
		EXPEDITION_STATE_ONSITE:
			_emit_expedition_event(
				"EXPEDITION_ARRIVED",
				"Expedition arrived at %s." % dest_name,
				"info",
				active_expedition.duplicate(true)
			)
		EXPEDITION_STATE_RETURNING:
			_emit_expedition_event(
				"EXPEDITION_RETURNING",
				"Expedition returning from %s." % dest_name,
				"info",
				active_expedition.duplicate(true)
			)


func _triangular_sample(low: float, mode: float, high: float, u: float) -> float:
	var clamped_low := low
	var clamped_high := high
	var clamped_mode: float = clamp(mode, clamped_low, clamped_high)
	if clamped_high <= clamped_low:
		return clamped_low
	var fc: float = (clamped_mode - clamped_low) / (clamped_high - clamped_low)
	if u < fc:
		return clamped_low + sqrt(u * (clamped_high - clamped_low) * (clamped_mode - clamped_low))
	return clamped_high - sqrt((1.0 - u) * (clamped_high - clamped_low) * (clamped_high - clamped_mode))

func _expedition_haul_band_for_risk(risk_level: int) -> Dictionary:
	match risk_level:
		0:
			return HAUL_BAND_SAFE
		2:
			return HAUL_BAND_MEDIUM
		3:
			return HAUL_BAND_HIGH
		_:
			return HAUL_BAND_LOW

func _expedition_duration_factor(distance_hours: int, onsite_hours: int) -> float:
	var duration_hours: int = (distance_hours * 2) + onsite_hours
	var normalized_duration: float = float(duration_hours) / DURATION_BASELINE_HOURS
	var scaled: float = DURATION_FACTOR_MIN + (sqrt(normalized_duration) - 1.0) * DURATION_FACTOR_SCALE
	return clamp(scaled, DURATION_FACTOR_MIN, DURATION_FACTOR_MAX)

func _expedition_crew_factor(crew: int) -> float:
	var crew_value: int = int(max(crew, 1))
	var crew_factor: float = 1.0 + (sqrt(float(crew_value)) - 1.0) * CREW_EFFICIENCY_SCALE
	return clamp(crew_factor, 1.0, CREW_FACTOR_MAX)

func _calculate_expedition_haul_points(
	crew: int,
	risk_level: int,
	distance_hours: int,
	onsite_hours: int,
	tracker: Dictionary
) -> int:
	var band := _expedition_haul_band_for_risk(risk_level)
	var low: float = float(band.get("low", 0.0))
	var mode: float = float(band.get("mode", 0.0))
	var high: float = float(band.get("high", 0.0))
	var u: float = _rng_randf(tracker)
	var raw_haul: float = _triangular_sample(low, mode, high, u)
	var variance_roll: float = (_rng_randf(tracker) * 2.0) - 1.0
	var variance_scale: float = RISK_VARIANCE_SCALE[clamp(risk_level, 0, RISK_VARIANCE_SCALE.size() - 1)]
	var variance_amplified: float = raw_haul * (1.0 + variance_roll * variance_scale)
	var duration_factor: float = _expedition_duration_factor(distance_hours, onsite_hours)
	var crew_factor: float = _expedition_crew_factor(crew)
	var final_haul: float = variance_amplified * duration_factor * crew_factor
	return int(round(final_haul))

func _allocate_haul_to_resources(haul_points: int, weight_profile: Dictionary, tracker: Dictionary) -> Dictionary:
	var allocation: Dictionary = {}
	if haul_points <= 0 or weight_profile.is_empty():
		return allocation
	var keys := weight_profile.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		var weight: float = float(weight_profile.get(key, 0.0))
		if weight <= 0.0:
			continue
		var base_share: float = float(haul_points) * weight
		var jitter: float = (_rng_randf(tracker) * 2.0 - 1.0) * ALLOCATION_JITTER_RANGE
		var jittered_share: float = base_share * (1.0 + jitter)
		var final_amount: int = max(0, int(round(jittered_share)))
		allocation[str(key)] = final_amount

	_reduce_expedition_allocation_excess(allocation, haul_points)
	return allocation

func _reduce_expedition_allocation_excess(allocation: Dictionary, haul_points: int) -> void:
	if allocation.is_empty():
		return
	var total_allocated: int = 0
	for amount in allocation.values():
		total_allocated += int(amount)
	if total_allocated <= haul_points:
		return

	var entries: Array = []
	for key in allocation.keys():
		entries.append({"key": str(key), "amount": int(allocation.get(key, 0))})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var amount_a: int = int(a.get("amount", 0))
		var amount_b: int = int(b.get("amount", 0))
		if amount_a != amount_b:
			return amount_a > amount_b
		return str(a.get("key", "")) < str(b.get("key", ""))
	)

	var excess: int = total_allocated - haul_points
	var index: int = 0
	while excess > 0 and index < entries.size():
		var entry: Dictionary = entries[index]
		var key: String = str(entry.get("key", ""))
		var amount: int = int(entry.get("amount", 0))
		if amount <= 0:
			index += 1
			continue
		var reduction: int = min(amount, excess)
		amount -= reduction
		excess -= reduction
		allocation[key] = amount
		entry["amount"] = amount
		index = (index + 1) if excess > 0 else index

func _apply_expedition_pool_caps(allocation: Dictionary, pool: Dictionary) -> Dictionary:
	var yields: Dictionary = {}
	if allocation.is_empty() or pool == null:
		return yields
	var keys := allocation.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		var amount: int = int(allocation.get(key, 0))
		if amount <= 0:
			continue
		var available: int = int(pool.get(key, 0))
		if available <= 0:
			continue
		var actual: int = min(amount, available)
		if actual > 0:
			yields[str(key)] = actual
		pool[key] = max(available - actual, 0)
	return yields

func _apply_expedition_partial_loss(yields: Dictionary, risk_level: int, tracker: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"yields": yields.duplicate(true),
		"loss_applied": false,
		"retain_pct": 1.0,
	}
	var threshold: float = PARTIAL_LOSS_THRESHOLDS[clamp(risk_level, 0, PARTIAL_LOSS_THRESHOLDS.size() - 1)]
	var loss_roll: float = _rng_randf(tracker)
	if loss_roll < threshold:
		var min_retain: float = PARTIAL_LOSS_RETAIN_MIN[clamp(risk_level, 0, PARTIAL_LOSS_RETAIN_MIN.size() - 1)]
		var max_retain: float = PARTIAL_LOSS_RETAIN_MAX[clamp(risk_level, 0, PARTIAL_LOSS_RETAIN_MAX.size() - 1)]
		var retain_pct: float = lerp(min_retain, max_retain, _rng_randf(tracker))
		var adjusted: Dictionary = {}
		var keys := yields.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
		)
		for key in keys:
			var amount: int = int(yields.get(key, 0))
			if amount <= 0:
				continue
			var reduced: int = int(round(float(amount) * retain_pct))
			if reduced > 0:
				adjusted[str(key)] = reduced
		result["yields"] = adjusted
		result["loss_applied"] = true
		result["retain_pct"] = retain_pct
	return result

func _roll_expedition_injury(risk_level: int, crew: int, tracker: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"injury": false,
		"fatal": false,
		"crew_lost": 0,
	}
	if crew <= 0:
		return result
	var injury_chance: float = INJURY_CHANCE_BASE[clamp(risk_level, 0, INJURY_CHANCE_BASE.size() - 1)]
	var injury_roll: float = _rng_randf(tracker)
	if injury_roll < injury_chance:
		result["injury"] = true
		var fatal_roll: float = _rng_randf(tracker)
		if fatal_roll < INJURY_FATALITY_GIVEN_INJURY:
			result["fatal"] = true
			result["crew_lost"] = 1
	return result

func _expedition_weight_profile_from_active() -> Dictionary:
	var profile: Variant = active_expedition.get("weight_profile", {})
	if profile is Dictionary:
		return (profile as Dictionary).duplicate(true)
	var resources_dict: Variant = active_expedition.get("resources", {})
	if resources_dict is Dictionary:
		var keys: Array = (resources_dict as Dictionary).keys()
		var count: int = keys.size()
		if count > 0:
			var weight: float = 1.0 / float(count)
			var fallback: Dictionary = {}
			for key in keys:
				fallback[str(key)] = weight
			return fallback
	return {}

func _expedition_apply_resource_gain(key: String, amount: int) -> void:
	if amount <= 0:
		return
	match key:
		"food":
			res.food += amount
		"water":
			res.water += amount
		"materials":
			res.materials += amount
		"silver":
			res.silver += amount
		"gold":
			res.gold += amount
		_:
			return

func _format_expedition_yield_summary(yields: Dictionary) -> String:
	if yields.is_empty():
		return "nothing"
	var parts: Array[String] = []
	var keys := yields.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		var amount: int = int(yields.get(key, 0))
		if amount <= 0:
			continue
		parts.append("%s +%d" % [str(key), amount])
	return ", ".join(parts)

func _expedition_total_yield_units(yields: Dictionary) -> int:
	var total: int = 0
	for amount in yields.values():
		total += int(amount)
	return total
func _expedition_apply_onsite_outcome() -> void:
	## Apply deterministic outcomes at destination (resource yields, risks).
	var yield_version: int = int(active_expedition.get("yield_version", EXPEDITION_YIELD_VERSION_LEGACY))
	if yield_version < EXPEDITION_YIELD_VERSION_V2:
		_expedition_apply_onsite_outcome_v1()
		return

	var exp_id := int(active_expedition.get("id", 0))
	var crew := int(active_expedition.get("crew", 1))
	var party_size: int = _expedition_party_size(active_expedition)
	var risk_level := int(active_expedition.get("risk_level", 1))
	var distance_hours := int(active_expedition.get("distance_hours", 1))
	var onsite_hours := int(active_expedition.get("onsite_hours", 1))
	var start_day := int(active_expedition.get("start_day", day))
	var start_hour := int(active_expedition.get("start_hour", active_expedition.get("start_hour_index", hour_index)))
	var destination_id: String = str(active_expedition.get("destination_id", ""))
	var heat: int = _get_location_heat(destination_id)
	var bonus_per_crew: int = int(active_expedition.get("yield_bonus_per_crew", 0))
	var bonus_yield: int = party_size * bonus_per_crew
	var expected_haul: int = (8 * party_size) + bonus_yield
	var multiplier: float = _party_size_multiplier(party_size)
	var heat_multiplier: float = maxf(1.0 - (0.12 * float(heat)), 0.0)
	var capacity_units: int = 12 * party_size
	var raw_haul: float = float(expected_haul) * multiplier * heat_multiplier
	var haul_points: int = int(min(float(capacity_units), maxf(raw_haul, 0.0)))

	var alloc_tracker := _create_rng_tracker(
		day,
		PHASE_EXPEDITIONS,
		"expedition:%d:allocation:d%dh%d" % [exp_id, start_day, start_hour],
		RNG_OFFSET_ACTIVE_EXPEDITION_ALLOCATION
	)
	var weight_profile: Dictionary = _expedition_weight_profile_from_active()
	var allocation: Dictionary = _allocate_haul_to_resources(haul_points, weight_profile, alloc_tracker)

	var resources_dict: Variant = active_expedition.get("resources", {})
	var pool: Dictionary = {}
	if resources_dict is Dictionary:
		pool = (resources_dict as Dictionary).duplicate(true)
	var yields: Dictionary = _apply_expedition_pool_caps(allocation, pool)
	active_expedition["resources"] = pool

	var risk_tracker := _create_rng_tracker(
		day,
		PHASE_EXPEDITIONS,
		"expedition:%d:risk_outcome:d%dh%d" % [exp_id, start_day, start_hour],
		RNG_OFFSET_ACTIVE_EXPEDITION_RISK
	)
	var injury_tracker := _create_rng_tracker(
		day,
		PHASE_EXPEDITIONS,
		"expedition:%d:injury_roll:d%dh%d" % [exp_id, start_day, start_hour],
		RNG_OFFSET_ACTIVE_EXPEDITION_INJURY
	)

	var loss_result: Dictionary = _apply_expedition_partial_loss(yields, risk_level, risk_tracker)
	var final_yields: Dictionary = loss_result.get("yields", {}) if loss_result.get("yields", null) is Dictionary else {}
	var loss_applied: bool = bool(loss_result.get("loss_applied", false))
	var retain_pct: float = float(loss_result.get("retain_pct", 1.0))

	var injury_result: Dictionary = _roll_expedition_injury(risk_level, crew, injury_tracker)
	var crew_lost: int = int(injury_result.get("crew_lost", 0))
	var member_ids := _expedition_member_ids(active_expedition)
	var injured_id: int = -1
	if bool(injury_result.get("injury", false)) and not member_ids.is_empty():
		if bool(injury_result.get("fatal", false)):
			injured_id = int(member_ids[member_ids.size() - 1])
		else:
			injured_id = int(member_ids[0])
		if injured_id > 0:
			active_expedition["injured_id"] = injured_id
			active_expedition["injured_name"] = _person_name_for_id(injured_id)
			if bool(injury_result.get("fatal", false)):
				active_expedition["fatality_id"] = injured_id
				active_expedition["fatality_name"] = _person_name_for_id(injured_id)
	if crew_lost > 0:
		active_expedition["crew_lost"] = crew_lost
		active_expedition["crew"] = max(crew - crew_lost, 0)

	var attention_base_value: int = 2 + int(ceil(0.6 * float(party_size))) + heat
	var attention_gained: float = float(maxi(attention_base_value, 0))

	var fatigue_penalty: int = FATIGUE_BASE[clamp(risk_level, 0, FATIGUE_BASE.size() - 1)]
	if float((distance_hours * 2) + onsite_hours) > (DURATION_BASELINE_HOURS * 1.5):
		fatigue_penalty += 1
	if bool(injury_result.get("injury", false)) and not bool(injury_result.get("fatal", false)):
		fatigue_penalty += 2

	active_expedition["haul_points"] = haul_points
	active_expedition["capacity_units"] = capacity_units
	active_expedition["expected_haul"] = expected_haul
	active_expedition["location_heat"] = heat
	active_expedition["yields"] = final_yields.duplicate(true)
	active_expedition["attention_gained"] = attention_gained
	active_expedition["fatigue_penalty"] = fatigue_penalty
	active_expedition["loss_applied"] = loss_applied
	active_expedition["retain_pct"] = retain_pct
	active_expedition["injury"] = bool(injury_result.get("injury", false))
	active_expedition["fatality"] = bool(injury_result.get("fatal", false))
	active_expedition["crew_lost"] = crew_lost

	if loss_applied:
		_emit_expedition_event(
			"EXPEDITION_LOSS",
			"Expedition suffered partial losses en route.",
			"warn",
			active_expedition.duplicate(true)
		)

	if bool(injury_result.get("injury", false)):
		var injury_message := "Expedition reported an injury."
		var injury_event := "EXPEDITION_INJURY"
		var injury_name := str(active_expedition.get("injured_name", ""))
		if bool(injury_result.get("fatal", false)):
			injury_event = "EXPEDITION_FATALITY"
			if injury_name != "":
				injury_message = "%s did not survive the expedition." % injury_name
			else:
				injury_message = "Expedition reported a fatality."
		elif injury_name != "":
			injury_message = "%s was injured during the expedition." % injury_name
		_emit_expedition_event(
			injury_event,
			injury_message,
			"warn",
			active_expedition.duplicate(true)
		)

func _expedition_apply_onsite_outcome_v1() -> void:
	var exp_id := int(active_expedition.get("id", 0))
	var crew := int(active_expedition.get("crew", 1))
	var risk_level := int(active_expedition.get("risk_level", 1))

	var tracker := _create_rng_tracker(
		day,
		PHASE_EXPEDITIONS,
		"expedition:%d:onsite:t%d" % [exp_id, hour_index],
		RNG_OFFSET_ACTIVE_EXPEDITION
	)

	var resources_dict: Variant = active_expedition.get("resources", {})
	var yields: Dictionary = {}
	if resources_dict is Dictionary:
		var res_keys: Array = resources_dict.keys()
		res_keys.sort()
		for res_key in res_keys:
			var available := int(resources_dict.get(res_key, 0))
			if available <= 0:
				continue
			var base_yield := crew * 3
			var yield_amount := int(min(base_yield, available))
			if yield_amount > 0:
				yields[res_key] = yield_amount
				active_expedition["resources"][res_key] = available - yield_amount

	active_expedition["yields"] = yields.duplicate(true)

	var failure_roll := _rng_randf(tracker)
	var failure_chance := float(risk_level) * 0.05
	if failure_roll < failure_chance:
		var casualty_roll := _rng_randf(tracker)
		if casualty_roll < 0.3 and crew > 1:
			active_expedition["crew_lost"] = 1
			active_expedition["crew"] = crew - 1
			var member_ids := _expedition_member_ids(active_expedition)
			if not member_ids.is_empty():
				var fatality_id: int = int(member_ids[member_ids.size() - 1])
				active_expedition["fatality_id"] = fatality_id
				active_expedition["fatality_name"] = _person_name_for_id(fatality_id)
			var casualty_name := str(active_expedition.get("fatality_name", ""))
			var casualty_message := "Expedition suffered a casualty."
			if casualty_name != "":
				casualty_message = "%s did not survive the expedition." % casualty_name
			_emit_expedition_event(
				"EXPEDITION_CASUALTY",
				casualty_message,
				"warn",
				active_expedition.duplicate(true)
			)
		else:
			for key in yields.keys():
				yields[key] = int(yields[key] / 2)
			active_expedition["yields"] = yields.duplicate(true)
			_emit_expedition_event(
				"EXPEDITION_SETBACK",
				"Expedition encountered difficulties; reduced yield.",
				"warn",
				active_expedition.duplicate(true)
			)

func _expedition_resolve() -> void:
	## Finalize expedition: apply yields to resources, return crew.
	var dest_name: String = str(active_expedition.get("destination_name", "unknown"))
	var _dest_id: String = str(active_expedition.get("destination_id", ""))
	var _crew := int(active_expedition.get("crew", 0))
	var crew_lost := int(active_expedition.get("crew_lost", 0))
	var expedition_id := int(active_expedition.get("id", 0))
	var member_ids: Array[int] = _expedition_member_ids(active_expedition)
	var member_names: Array[String] = _names_for_ids(member_ids)
	var survivors_gained := _roll_expedition_survivors(expedition_id)
	var yields: Dictionary = {}
	var yields_variant: Variant = active_expedition.get("yields", {})
	if yields_variant is Dictionary:
		yields = (yields_variant as Dictionary).duplicate(true)

	var yield_version: int = int(active_expedition.get("yield_version", EXPEDITION_YIELD_VERSION_LEGACY))
	var yield_summary: String = _format_expedition_yield_summary(yields)

	if yield_version >= EXPEDITION_YIELD_VERSION_V2:
		if survivors_gained > 0 and not yields.is_empty():
			var party_size: int = _expedition_party_size(active_expedition)
			var effective_carriers: int = party_size + survivors_gained
			if party_size > 0 and effective_carriers > party_size:
				var scale: float = float(effective_carriers) / float(party_size)
				var pool_variant: Variant = active_expedition.get("resources", {})
				var pool_remaining: Dictionary = {}
				if pool_variant is Dictionary:
					pool_remaining = (pool_variant as Dictionary)
				var keys := yields.keys()
				keys.sort_custom(func(a: Variant, b: Variant) -> bool:
					return str(a) < str(b)
				)
				for key in keys:
					var current_amount: int = int(yields.get(key, 0))
					if current_amount <= 0:
						continue
					var target_amount: int = int(round(float(current_amount) * scale))
					if target_amount <= current_amount:
						continue
					var available: int = int(pool_remaining.get(key, 0))
					if available <= 0:
						continue
					var extra: int = min(target_amount - current_amount, available)
					if extra <= 0:
						continue
					yields[key] = current_amount + extra
					pool_remaining[key] = max(available - extra, 0)
				active_expedition["resources"] = pool_remaining
			yield_summary = _format_expedition_yield_summary(yields)
		for key in yields.keys():
			var amount: int = int(yields.get(key, 0))
			_expedition_apply_resource_gain(str(key), amount)

		var attention_gained: float = float(active_expedition.get("attention_gained", 0.0))
		if attention_gained > 0.0:
			expedition_attention += attention_gained
			expedition_attention = snapped(expedition_attention, SIM_FLOAT_SNAP)

		var fatigue_penalty: int = int(active_expedition.get("fatigue_penalty", 0))
		if fatigue_penalty > 0:
			res.morale -= fatigue_penalty

		var fatality_id: int = int(active_expedition.get("fatality_id", -1))
		var injured_id: int = int(active_expedition.get("injured_id", -1))
		var casualty_ids: Array[int] = []
		if crew_lost > 0:
			if fatality_id > 0 and member_ids.has(fatality_id):
				casualty_ids.append(fatality_id)
			else:
				casualty_ids = _select_casualties_from_members(member_ids, crew_lost)
		if not casualty_ids.is_empty():
			_kill_people_by_ids(casualty_ids, "expedition_fatality", day)
			res.population = max(res.population - casualty_ids.size(), 0)

		var survivors_ids: Array[int] = []
		var injured_ids: Array[int] = []
		for person_id in member_ids:
			if casualty_ids.has(person_id):
				continue
			if injured_id == int(person_id) and not bool(active_expedition.get("fatality", false)):
				injured_ids.append(int(person_id))
				continue
			survivors_ids.append(int(person_id))
		if not survivors_ids.is_empty():
			_set_people_status(survivors_ids, PEOPLE_STATUS_HOME)
		if not injured_ids.is_empty():
			_set_people_status(injured_ids, PEOPLE_STATUS_INJURED)

		var pending_survivors_entry := _apply_expedition_survivors(
			survivors_gained,
			expedition_id,
			_dest_id,
			dest_name
		)

		var loss_applied: bool = bool(active_expedition.get("loss_applied", false))
		var retain_pct: float = float(active_expedition.get("retain_pct", 1.0))
		var injury: bool = bool(active_expedition.get("injury", false))
		var fatality: bool = bool(active_expedition.get("fatality", false))

		var outcome_tone := "successful"
		if crew_lost > 0 or fatality or injury:
			outcome_tone = "costly"
		elif loss_applied:
			outcome_tone = "troubled"

		var cost_parts: Array[String] = []
		if attention_gained > 0.0:
			cost_parts.append("+%.1f attention" % attention_gained)
		if fatigue_penalty > 0:
			cost_parts.append("-%d morale (fatigue)" % fatigue_penalty)
		if loss_applied:
			var lost_pct: int = int(round((1.0 - retain_pct) * 100.0))
			cost_parts.append("%d%% haul lost" % lost_pct)
		if crew_lost > 0:
			cost_parts.append("%d crew lost" % crew_lost)
		elif injury:
			cost_parts.append("crew injured")

		var total_units: int = _expedition_total_yield_units(yields)
		var total_summary: String = "%d units gathered" % total_units

		var message := "Expedition #%d returned from %s.\nHaul: %s\nOutcome: %s" % [
			int(active_expedition.get("id", 0)),
			dest_name,
			yield_summary,
			outcome_tone.capitalize()
		]
		if not member_names.is_empty():
			message += "\nCrew returned: %s" % _format_names_list(_names_for_ids(survivors_ids))
		if cost_parts.size() > 0:
			message += "\nCosts: %s" % ", ".join(cost_parts)
		if survivors_gained > 0:
			var survivor_names: Array[String] = []
			if not pending_survivors_entry.is_empty():
				var names_value: Variant = pending_survivors_entry.get("survivor_names", [])
				if names_value is Array:
					for name_value in names_value:
						survivor_names.append(str(name_value))
			if survivor_names.is_empty():
				message += "\nSurvivors awaiting admission: +%d" % survivors_gained
			else:
				message += "\nSurvivors awaiting admission: %s" % _format_names_list(survivor_names)
			var pending_id: int = int(pending_survivors_entry.get("id", -1))
			if pending_id >= 0:
				message += ". Use SURVIVORS_ADMIT %d or SURVIVORS_REJECT %d." % [pending_id, pending_id]

		var payload := active_expedition.duplicate(true)
		payload["yields"] = yields.duplicate(true)
		payload["total_haul_summary"] = total_summary
		payload["costs_incurred"] = {
			"attention_gained": attention_gained,
			"fatigue_applied": fatigue_penalty,
			"loss_applied": loss_applied,
			"injury": injury,
			"fatality": fatality,
			"crew_lost": crew_lost,
		}
		payload["outcome_tone"] = outcome_tone
		payload["member_ids"] = member_ids.duplicate()
		payload["member_names"] = member_names.duplicate()
		payload["survivor_ids"] = survivors_ids.duplicate()
		payload["survivor_names"] = _names_for_ids(survivors_ids)
		payload["casualty_ids"] = casualty_ids.duplicate()
		payload["casualty_names"] = _names_for_ids(casualty_ids)
		payload["injured_ids"] = injured_ids.duplicate()
		payload["injured_names"] = _names_for_ids(injured_ids)
		if not pending_survivors_entry.is_empty():
			payload["pending_survivor_event_id"] = int(pending_survivors_entry.get("id", -1))
			payload["pending_survivor_ids"] = pending_survivors_entry.get("survivor_ids", [])
			payload["pending_survivor_names"] = pending_survivors_entry.get("survivor_names", [])

		_emit_expedition_event(
			"EXPEDITION_RESOLVED",
			message,
			"info",
			payload
		)
	else:
		# Legacy resolution.
		var yield_summary_parts: Array[String] = []
		if yields_variant is Dictionary:
			var yield_keys: Array = yields.keys()
			yield_keys.sort()
			for key in yield_keys:
				var amount := int(yields.get(key, 0))
				if amount <= 0:
					continue
				match key:
					"food":
						res.food += amount
					"water":
						res.water += amount
					"materials":
						res.materials += amount
				yield_summary_parts.append("%s +%d" % [key, amount])

		var fatality_id_legacy: int = int(active_expedition.get("fatality_id", -1))
		var casualty_ids_legacy: Array[int] = []
		if crew_lost > 0:
			if fatality_id_legacy > 0 and member_ids.has(fatality_id_legacy):
				casualty_ids_legacy.append(fatality_id_legacy)
			else:
				casualty_ids_legacy = _select_casualties_from_members(member_ids, crew_lost)
		if not casualty_ids_legacy.is_empty():
			_kill_people_by_ids(casualty_ids_legacy, "expedition_fatality", day)
			res.population = max(res.population - casualty_ids_legacy.size(), 0)

		var survivors_ids_legacy: Array[int] = []
		for person_id in member_ids:
			if not casualty_ids_legacy.has(person_id):
				survivors_ids_legacy.append(int(person_id))
		if not survivors_ids_legacy.is_empty():
			_set_people_status(survivors_ids_legacy, PEOPLE_STATUS_HOME)

		var pending_survivors_entry := _apply_expedition_survivors(
			survivors_gained,
			expedition_id,
			_dest_id,
			dest_name
		)

		active_expedition["state"] = EXPEDITION_STATE_RESOLVED

		var legacy_summary := ", ".join(yield_summary_parts) if not yield_summary_parts.is_empty() else "nothing"
		var legacy_message := "Expedition returned from %s. Yielded: %s." % [dest_name, legacy_summary]
		if not member_names.is_empty():
			legacy_message += " Crew returned: %s." % _format_names_list(_names_for_ids(survivors_ids_legacy))
		if crew_lost > 0:
			legacy_message += " Lost %d crew." % crew_lost
		if survivors_gained > 0:
			var survivor_names: Array[String] = []
			if not pending_survivors_entry.is_empty():
				var names_value: Variant = pending_survivors_entry.get("survivor_names", [])
				if names_value is Array:
					for name_value in names_value:
						survivor_names.append(str(name_value))
			if survivor_names.is_empty():
				legacy_message += " Survivors awaiting admission: +%d." % survivors_gained
			else:
				legacy_message += " Survivors awaiting admission: %s." % _format_names_list(survivor_names)
			var pending_id: int = int(pending_survivors_entry.get("id", -1))
			if pending_id >= 0:
				legacy_message += " Use SURVIVORS_ADMIT %d or SURVIVORS_REJECT %d." % [pending_id, pending_id]

		var legacy_payload := active_expedition.duplicate(true)
		legacy_payload["member_ids"] = member_ids.duplicate()
		legacy_payload["member_names"] = member_names.duplicate()
		legacy_payload["survivor_ids"] = survivors_ids_legacy.duplicate()
		legacy_payload["survivor_names"] = _names_for_ids(survivors_ids_legacy)
		legacy_payload["casualty_ids"] = casualty_ids_legacy.duplicate()
		legacy_payload["casualty_names"] = _names_for_ids(casualty_ids_legacy)
		if not pending_survivors_entry.is_empty():
			legacy_payload["pending_survivor_event_id"] = int(pending_survivors_entry.get("id", -1))
			legacy_payload["pending_survivor_ids"] = pending_survivors_entry.get("survivor_ids", [])
			legacy_payload["pending_survivor_names"] = pending_survivors_entry.get("survivor_names", [])
		_emit_expedition_event(
			"EXPEDITION_RESOLVED",
			legacy_message,
			"info",
			legacy_payload
		)

	# Mark as resolved.
	_maybe_queue_outsiders_event()
	active_expedition["state"] = EXPEDITION_STATE_RESOLVED

	# Clamp resources.
	res.clamp_all()

	# Clear expedition in next tick.

func _maybe_queue_outsiders_event() -> void:
	if res == null:
		return
	if active_expedition.is_empty():
		return
	_ensure_people_initialized()
	var expedition_id: int = int(active_expedition.get("id", 0))
	var destination_id: String = str(active_expedition.get("destination_id", ""))
	if destination_id == "":
		return
	if pending_outsiders.has(expedition_id):
		return
	var party_size: int = _expedition_party_size(active_expedition)
	var heat: int = _get_location_heat(destination_id)
	var chance: float = 0.10 + (0.02 * float(party_size)) + (0.05 * float(heat))
	if chance < 0.0:
		chance = 0.0
	elif chance > 1.0:
		chance = 1.0
	var return_hour_index: int = int(active_expedition.get("estimated_return_hour", hour_index))
	var seed_value: int = _outsiders_seed(expedition_id, destination_id, return_hour_index, party_size, heat)
	var context := "outsiders:%d:%s:h%d:ps%d:ht%d" % [expedition_id, destination_id, return_hour_index, party_size, heat]
	var tracker := _create_rng_tracker(day, PHASE_EXPEDITIONS, context, RNG_OFFSET_OUTSIDERS, seed_value)
	var roll: float = _rng_randf(tracker)
	if roll > chance:
		return
	var group_size: int = 1 + int(_rng_randi(tracker) % 3)
	var entry := {
		"id": expedition_id,
		"expedition_id": expedition_id,
		"destination_id": destination_id,
		"group_size": group_size,
		"created_day": day,
		"created_hour": hour_of_day,
		"chance": chance,
		"roll": roll,
		"party_size": party_size,
		"heat": heat,
	}
	var identities := _reserve_outsider_identities(group_size, day)
	var outsider_ids := _ids_from_identities(identities)
	var outsider_names := _names_from_identities(identities)
	pending_outsider_identities[expedition_id] = identities
	entry["kind"] = "gate_outsiders"
	entry["count"] = group_size
	entry["names"] = outsider_names.duplicate()
	entry["source"] = destination_id
	entry["outsider_ids"] = outsider_ids
	entry["outsider_names"] = outsider_names
	entry["command_admit"] = "GATE_ADMIT %d" % expedition_id
	entry["command_reject"] = "GATE_REJECT %d" % expedition_id
	pending_outsiders[expedition_id] = entry
	var dest_name: String = str(active_expedition.get("destination_name", "unknown"))
	var message := "Outsiders at the gate: %d from %s. %s (id %d). Use GATE_ADMIT %d or GATE_REJECT %d." % [
		group_size,
		dest_name,
		_format_names_list(outsider_names),
		expedition_id,
		expedition_id,
		expedition_id
	]
	_emit_event(
		"OUTSIDERS_AT_GATE",
		message,
		"info",
		"player_feed",
		entry.duplicate(true),
		"expedition",
		day,
		hour_of_day,
		true
	)

func _emit_expedition_event(event_type: String, message: String, severity: String, payload: Dictionary) -> void:
	_emit_event(
		event_type,
		message,
		severity,
		"player_feed",
		payload,
		"expedition",
		day,
		hour_of_day,
		true
	)

func get_map_locations() -> Array:
	## Returns location data for UI consumption.
	if map_def == null:
		return []
	var locations: Array = []
	for loc in map_def.get_expedition_destinations():
		locations.append(loc.to_dict())
	return locations

func get_map_edges() -> Array[Dictionary]:
	## Returns edge data for visual map rendering.
	if map_def == null:
		return []
	return map_def.get_edges()

func get_pending_outsiders() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if pending_outsiders.is_empty():
		return results
	var keys: Array = pending_outsiders.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		var entry_value: Variant = pending_outsiders.get(key, {})
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value as Dictionary
			var kind: String = str(entry.get("kind", "gate_outsiders"))
			if kind != "gate_outsiders":
				continue
			results.append(entry.duplicate(true))
	return results

func queue_outsiders_decision(event_id: int, accept: bool) -> Dictionary:
	var result := {"ok": false, "message": "INVALID"}
	if event_id < 0:
		result["message"] = "INVALID EVENT"
		return result
	if not pending_outsiders.has(event_id):
		result["message"] = "NO PENDING EVENT"
		return result
	var payload := {
		"event_id": event_id,
		"accept": accept,
	}
	enqueue_command(SimCommand.new(CMD_OUTSIDERS_DECISION, payload))
	result["ok"] = true
	result["message"] = "OUTSIDERS DECISION QUEUED"
	return result

func execute_console_command(command_line: String) -> Dictionary:
	var result := {"ok": false, "message": "INVALID COMMAND"}
	if command_line == "":
		result["message"] = "EMPTY COMMAND"
		return result
	var tokens := command_line.strip_edges().split(" ", false)
	if tokens.is_empty():
		result["message"] = "EMPTY COMMAND"
		return result
	var verb := str(tokens[0]).to_upper()
	if verb == "GATE_ADMIT" or verb == "GATE_REJECT":
		if tokens.size() < 2:
			result["message"] = "MISSING ID"
			return result
		var id_token := str(tokens[1])
		if not id_token.is_valid_int():
			result["message"] = "INVALID ID"
			return result
		var event_id := id_token.to_int()
		return queue_outsiders_decision(event_id, verb == "GATE_ADMIT")
	if verb == "SURVIVORS_ADMIT" or verb == "SURVIVORS_REJECT":
		if tokens.size() < 2:
			result["message"] = "MISSING ID"
			return result
		var id_token := str(tokens[1])
		if not id_token.is_valid_int():
			result["message"] = "INVALID ID"
			return result
		var event_id := id_token.to_int()
		return queue_outsiders_decision(event_id, verb == "SURVIVORS_ADMIT")
	return result

func get_max_party_size() -> int:
	if res == null:
		return 1
	var home_count: int = _home_people_count()
	if home_count <= 0:
		home_count = int(res.population)
	return _max_party_size(home_count)


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
	if amount <= 0 or amount > TRADE_MAX_AMOUNT:
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
		var attention_cost: float = clamp(
			TRADE_ATTENTION_BASE + (float(amount) * TRADE_ATTENTION_PER_UNIT),
			0.0,
			TRADE_ATTENTION_CAP
		)
		sim_res.attention_multiplier += attention_cost
		if absf(attention_cost) >= SIM_FLOAT_SNAP:
			sim_res.attention_multiplier = snappedf(sim_res.attention_multiplier, SIM_FLOAT_SNAP)
		var event_payload := base_payload.duplicate()
		event_payload["silver_change"] = -cost
		event_payload["resource_before"] = before_amount
		event_payload["resource_after"] = sim_res.get_amount(resource)
		event_payload["attention_cost"] = attention_cost
		event_payload["attention_after"] = sim_res.attention_multiplier
		var message := "Bought %d %s for %s. (+%.2f attention)" % [
			amount,
			resource,
			Resources.format_currency(cost),
			attention_cost,
		]
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
		var attention_cost: float = clamp(
			TRADE_ATTENTION_BASE + (float(amount) * TRADE_ATTENTION_PER_UNIT),
			0.0,
			TRADE_ATTENTION_CAP
		)
		sim_res.attention_multiplier += attention_cost
		if absf(attention_cost) >= SIM_FLOAT_SNAP:
			sim_res.attention_multiplier = snappedf(sim_res.attention_multiplier, SIM_FLOAT_SNAP)
		var event_payload := base_payload.duplicate()
		event_payload["silver_change"] = revenue
		event_payload["resource_before"] = available
		event_payload["resource_after"] = sim_res.get_amount(resource)
		event_payload["attention_cost"] = attention_cost
		event_payload["attention_after"] = sim_res.attention_multiplier
		var message := "Sold %d %s for %s. (+%.2f attention)" % [
			amount,
			resource,
			Resources.format_currency(revenue),
			attention_cost,
		]
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

	var overdrive_base_totals: Dictionary = {
		"food": 0,
		"water": 0,
	}
	var overdrive_limit_reasons: Array[String] = []

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
			_accumulate_labor_overdrive_base(deltas, overdrive_base_totals)
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
			var reduction_reason := ""
			if candidate_power_enabled and not inputs_ready:
				_obs_push(obs, "MODULE_INPUT_STARVED@%s" % module_key)
				reduction_reason = "inputs"
			else:
				_obs_push(obs, "MODULE_UNPOWERED@%s" % module_key)
				reduction_reason = "power"
			if (
				reduction_reason != ""
				and labor_overdrive_hours_left > 0
				and labor_overdrive_intensity > 0
				and not overdrive_limit_reasons.has(reduction_reason)
			):
				overdrive_limit_reasons.append(reduction_reason)

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

	_log_labor_overdrive_effects(overdrive_base_totals, overdrive_limit_reasons)

	return {
		"powered_count": powered_count,
		"module_count": module_count,
		"total_capacity": total_capacity,
		"total_noise": total_noise,
		"total_heat": total_heat,
	}

func _accumulate_labor_overdrive_base(deltas: Dictionary, totals: Dictionary) -> void:
	if deltas == null or totals == null:
		return
	if labor_overdrive_intensity <= 0 or labor_overdrive_hours_left <= 0:
		return
	var base_food := int(deltas.get("food", 0))
	if base_food > 0:
		totals["food"] = int(totals.get("food", 0)) + base_food
	var base_water := int(deltas.get("water", 0))
	if base_water > 0:
		totals["water"] = int(totals.get("water", 0)) + base_water

func _log_labor_overdrive_effects(base_totals: Dictionary, reduction_reasons: Array[String]) -> void:
	if base_totals == null:
		return
	var intensity := labor_overdrive_intensity
	if intensity <= 0:
		return
	var multiplier := _labor_overdrive_multiplier()
	if multiplier <= 1.0:
		return
	var reason_suffix := _overdrive_reason_suffix(reduction_reasons)
	for resource in ["food", "water"]:
		var base_amount := int(base_totals.get(resource, 0))
		if base_amount <= 0:
			continue
		var boosted := int(ceil(float(base_amount) * multiplier))
		var label: String = resource.capitalize()
		var message := "OVERDRIVE L%d: %s base %d -> %d (+25%%/level)" % [intensity, label, base_amount, boosted]
		if reason_suffix != "":
			message += reason_suffix
		_emit_event(
			"OVERDRIVE_BOOST_%s" % resource.to_upper(),
			message,
			"player_feed",
			"player_feed",
			{},
			"production",
			day,
			hour_of_day,
			true
		)

func _labor_overdrive_multiplier() -> float:
	if labor_overdrive_intensity <= 0:
		return 1.0
	return 1.0 + float(labor_overdrive_intensity) * LABOR_OVERDRIVE_MULT_PER_LEVEL

func _overdrive_reason_suffix(reasons: Array[String]) -> String:
	if reasons == null or reasons.is_empty():
		return ""
	var labels: Array[String] = []
	for reason in reasons:
		var candidate := str(LABOR_OVERDRIVE_REASON_LABELS.get(reason, ""))
		if candidate == "":
			continue
		if not labels.has(candidate):
			labels.append(candidate)
	if labels.is_empty():
		return ""
	return " (limited by %s)" % ", ".join(labels)

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

	var home_population: int = _home_population()
	if total_capacity < home_population:
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
		_apply_population_loss(pop_loss, "scarcity", day, "POPULATION_LOSS", "Population loss:")
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

func _run_civil_unrest_terminal(sim_day: int, _sim_res: Resources, obs: Array[String]) -> void:
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
	var alive_count: int = _alive_people_count()
	_apply_population_loss(alive_count, "civil_unrest_terminal", sim_day, "CIVIL_UNREST_CASUALTIES", "Civil unrest casualties:")
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
	if before_pop > 0:
		_apply_population_loss(CIVIL_UNREST_POP_LOSS_DEFAULT, "civil_unrest", day, "CIVIL_UNREST_POP_LOSS", "Civil unrest claimed:")
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
	_update_morale_tier(pre_morale, sim_day, true)

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
	_run_mutiny_roll(sim_day, sim_res, obs)
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

func _hash_mix(acc: int, value: int) -> int:
	return int(((acc * 31) + value) & 0x7FFFFFFF)

func _hash_string(value: String) -> int:
	var acc: int = 0
	for i in range(value.length()):
		acc = _hash_mix(acc, value.unicode_at(i))
	return acc

func _people_hash_component() -> int:
	var acc: int = 17
	for entry in _people:
		if not (entry is Dictionary):
			continue
		var person: Dictionary = entry as Dictionary
		acc = _hash_mix(acc, int(person.get("id", 0)))
		acc = _hash_mix(acc, _hash_string(str(person.get("name", ""))))
		acc = _hash_mix(acc, _hash_string(str(person.get("status", PEOPLE_STATUS_HOME))))
		acc = _hash_mix(acc, int(person.get("joined_day", 0)))
		acc = _hash_mix(acc, int(person.get("death_day", -1)))
		acc = _hash_mix(acc, _hash_string(str(person.get("death_cause", ""))))
	acc = _hash_mix(acc, _next_person_id)
	return acc

func _pending_outsider_identities_hash_component() -> int:
	var acc: int = 23
	if pending_outsider_identities.is_empty():
		return acc
	var keys := pending_outsider_identities.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str(a) < str(b)
	)
	for key in keys:
		acc = _hash_mix(acc, _hash_string(str(key)))
		var identity_value: Variant = pending_outsider_identities.get(key, [])
		if identity_value is Array:
			var identity_entries: Array[Dictionary] = []
			for entry in identity_value:
				if entry is Dictionary:
					identity_entries.append(entry)
			identity_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("id", 0)) < int(b.get("id", 0))
			)
			for identity in identity_entries:
				acc = _hash_mix(acc, int(identity.get("id", 0)))
				acc = _hash_mix(acc, _hash_string(str(identity.get("name", ""))))
	return acc

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
	parts.append("people_ver=%d" % people_system_version)
	parts.append("people_hash=%d" % _people_hash_component())
	parts.append("pending_outsider_hash=%d" % _pending_outsider_identities_hash_component())
	# Active expedition state for determinism tracking.
	if not active_expedition.is_empty():
		parts.append("active_exp_id=%d" % int(active_expedition.get("id", 0)))
		parts.append("active_exp_state=%s" % str(active_expedition.get("state", "")))
		parts.append("active_exp_dest=%s" % str(active_expedition.get("destination_id", "")))
		parts.append("active_exp_hours=%d" % int(active_expedition.get("hours_in_state", 0)))
		var exp_member_ids := _expedition_member_ids(active_expedition)
		if not exp_member_ids.is_empty():
			var member_tokens: Array[String] = []
			for member_id in exp_member_ids:
				member_tokens.append(str(member_id))
			parts.append("active_exp_members=%s" % ",".join(member_tokens))
	parts.append("rejected_outsiders_days=%d" % rejected_outsiders_days_left)
	if not location_heat.is_empty():
		var heat_keys := location_heat.keys()
		heat_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
		)
		for key in heat_keys:
			parts.append("heat:%s=%d" % [str(key), int(location_heat.get(key, 0))])
	if not pending_outsiders.is_empty():
		var outsider_keys := pending_outsiders.keys()
		outsider_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
		)
		for key in outsider_keys:
			var entry_value: Variant = pending_outsiders.get(key, {})
			if entry_value is Dictionary:
				var entry: Dictionary = entry_value as Dictionary
				parts.append(
					"outsiders:%s@%d@%s" % [
						str(entry.get("id", key)),
						int(entry.get("group_size", 0)),
						str(entry.get("destination_id", ""))
					]
				)
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


func _duplicate_state_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func _export_command_queue() -> Array:
	var queue_copy: Array = []
	for cmd in _command_queue:
		if cmd is SimCommand:
			queue_copy.append(cmd.clone())
	return queue_copy

func _restore_command_queue(data: Array) -> void:
	_command_queue.clear()
	if data is Array:
		for entry in data:
			if entry is SimCommand:
				_command_queue.append(entry.clone())

func _copy_rng_history() -> Array:
	var history: Array = []
	for entry in _rng_usage_history:
		if entry is Dictionary:
			history.append((entry as Dictionary).duplicate(true))
	return history

func _restore_rng_history(data: Array) -> void:
	_rng_usage_history.clear()
	_rng_usage_lookup.clear()
	if data is Array:
		for entry in data:
			if entry is Dictionary:
				var copy_entry := (entry as Dictionary).duplicate(true)
				var key := str(copy_entry.get("key", ""))
				_rng_usage_history.append(copy_entry)
				if key != "":
					_rng_usage_lookup[key] = copy_entry

func _copy_rng_instances() -> Dictionary:
	var rng_copy: Dictionary = {}
	for key in _rng_instances.keys():
		var rng_variant: Variant = _rng_instances.get(key)
		if rng_variant is RandomNumberGenerator:
			var rng: RandomNumberGenerator = rng_variant as RandomNumberGenerator
			rng_copy[str(key)] = rng.duplicate(true)
	return rng_copy

func _restore_rng_instances(data: Dictionary) -> void:
	_rng_instances.clear()
	if data is Dictionary:
		for key in data.keys():
			var rng_value: Variant = data.get(key)
			if rng_value is RandomNumberGenerator:
				var rng: RandomNumberGenerator = rng_value as RandomNumberGenerator
				_rng_instances[str(key)] = rng.duplicate(true)

func _test_export_state() -> Dictionary:
	var state: Dictionary = {}
	for key in _SIM_STATE_SIMPLE_KEYS:
		var value: Variant = get(key)
		state[key] = _duplicate_state_value(value)
	state["tower"] = tower._test_export_state() if tower != null else null
	state["res"] = res._test_export_state() if res != null else null
	state["_command_queue"] = _export_command_queue()
	state["_rng_usage_history"] = _copy_rng_history()
	state["_rng_instances"] = _copy_rng_instances()
	return state

func _test_import_state(state: Dictionary) -> void:
	for key in _SIM_STATE_SIMPLE_KEYS:
		if state.has(key):
			set(key, _duplicate_state_value(state.get(key)))
	tower = Tower.new()
	var tower_state: Variant = state.get("tower", {})
	if tower_state is Dictionary:
		tower._test_import_state(tower_state)
	res = Resources.new()
	var res_state: Variant = state.get("res", {})
	if res_state is Dictionary:
		res._test_import_state(res_state)
	db = ModuleDB.new()
	map_def = MapDefRef.new()
	_restore_command_queue(state.get("_command_queue", []))
	_restore_rng_history(state.get("_rng_usage_history", []))
	_restore_rng_instances(state.get("_rng_instances", {}))
