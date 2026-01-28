extends Node
class_name Sim

signal tick(day: int)

@export var seconds_per_day: float = 1.0

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

const IncidentDefsRef = preload("res://scripts/sim/IncidentDefs.gd")
const LeverDefsRef = preload("res://scripts/sim/LeverDefs.gd")

const MODULE_DELTA_KEYS: Array[String] = [
	"food",
	"water",
	"materials",
	"morale",
]

class SimCommand extends RefCounted:
	var type: String = ""
	var payload: Dictionary = null

	func _init(_type: String = "", _payload: Dictionary = null) -> void:
		type = _type
		payload = _duplicate_payload(_payload)

	func clone() -> SimCommand:
		var copy := SimCommand.new()
		copy.type = type
		copy.payload = _duplicate_payload(payload)
		return copy

	func _duplicate_payload(value: Dictionary) -> Dictionary:
		if value == null:
			return {}
		if value is Dictionary:
			return value.duplicate(true)
		return {}

const CMD_SET_RATIONS := "SET_RATIONS"
const CMD_SET_MODULE_ENABLED := "SET_MODULE_ENABLED"
const CMD_SET_MODULE_PRIORITY := "SET_MODULE_PRIORITY"
const CMD_EXPEDITION := "EXPEDITION"

const LEVER_RATION_HARDENING := LeverDefsRef.LEVER_RATION_HARDENING
const LEVER_LABOR_OVERDRIVE := LeverDefsRef.LEVER_LABOR_OVERDRIVE
const LEVER_EXPEDITION_COMPRESSION := LeverDefsRef.LEVER_EXPEDITION_COMPRESSION
const LEVER_INFORMATION_THROTTLING := LeverDefsRef.LEVER_INFORMATION_THROTTLING
const LEVER_MODULE_ABANDONMENT := LeverDefsRef.LEVER_MODULE_ABANDONMENT
const LEVER_EMERGENCY_CONVERSION := LeverDefsRef.LEVER_EMERGENCY_CONVERSION

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

const SIM_FLOAT_SNAP := 0.01 # Determinism hardening: snap small float accumulators post-update.

const CONVERSION_SCAR_PER_USE := 1
const CONVERSION_EFFICIENCY_LOSS := 0.1
const CONVERSION_EFFICIENCY_MIN := 0.4
const CONVERSION_BURN_THRESHOLD := 3
const CONVERSION_CEILING_PENALTY := 0.3
const CONVERTIBLE_RESOURCES: Array[String] = ["food", "water", "materials", "morale"]

var _command_queue: Array[SimCommand] = []
var lever_events: Array[Dictionary] = []

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

# Lever state (persistent)
var ration_hardening_ticks_left: int = 0
var ration_hardening_mode: String = ""
var ration_scar: float = 0.0

var labor_overdrive_ticks_left: int = 0
var labor_overdrive_intensity: int = 0
var labor_scar: float = 0.0

var expedition_compression_ticks_left: int = 0
var expedition_compression_intensity: int = 0
var expedition_attention: float = 0.0

var info_throttle_ticks_left: int = 0
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
	day = hour_index // HOURS_PER_DAY
	phase = "HOUR_TICK"
	if hour_of_day == 0:
		var incidents := _step_day_core(day, sim_seed, tower, res, db)
		print(_format_log_line(day, sim_seed, res, incidents, _last_obs_tokens))
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
	ration_hardening_ticks_left = 0
	ration_hardening_mode = ""
	ration_scar = 0.0
	labor_overdrive_ticks_left = 0
	labor_overdrive_intensity = 0
	labor_scar = 0.0
	expedition_compression_ticks_left = 0
	expedition_compression_intensity = 0
	expedition_attention = 0.0
	info_throttle_ticks_left = 0
	info_throttle_level = 0
	info_throttle_backlog = 0.0
	abandoned_modules.clear()
	conversion_scar = 0
	conversion_burn_counts.clear()
	pending_conversions.clear()

func enqueue_command(cmd: SimCommand) -> void:
	if cmd == null:
		return
	_command_queue.append(cmd)

func clear_commands() -> void:
	_command_queue.clear()

func _duration_payload_ticks(payload: Dictionary) -> int:
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

func _dict_merge_into(dst: Dictionary, src: Dictionary) -> void:
	if dst == null or src == null:
		return
	for key in src.keys():
		dst[key] = src[key]

func apply_lever(lever_id: String, payload: Dictionary) -> bool:
	var ok := false
	var sanitized: Dictionary = {}
	var immediate_summary := ""
	var debts_summary := ""

	match lever_id:
		LEVER_RATION_HARDENING:
			var mode: String = str(payload.get("mode", ""))
			var duration_ticks := _duration_payload_ticks(payload)
			if mode != "soft" and mode != "hard":
				immediate_summary = "REJECTED: invalid mode"
			elif duration_ticks <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				ration_hardening_mode = mode
				ration_hardening_ticks_left = duration_ticks
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_ticks"] = duration_ticks
				sanitized = {"mode": mode}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "policy active"
				debts_summary = "scar accrues"
				ok = true
		LEVER_LABOR_OVERDRIVE:
			var intensity: int = int(payload.get("intensity", 0))
			var duration_ticks := _duration_payload_ticks(payload)
			if intensity <= 0:
				immediate_summary = "REJECTED: invalid intensity"
			elif duration_ticks <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				intensity = int(clamp(intensity, 1, LABOR_OVERDRIVE_MAX_INTENSITY))
				labor_overdrive_intensity = intensity
				labor_overdrive_ticks_left = duration_ticks
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_ticks"] = duration_ticks
				sanitized = {"intensity": intensity}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "throughput boosted"
				debts_summary = "labor scar accrues"
				ok = true
		LEVER_EXPEDITION_COMPRESSION:
			var intensity: int = int(payload.get("intensity", 0))
			var duration_ticks := _duration_payload_ticks(payload)
			if intensity <= 0:
				immediate_summary = "REJECTED: invalid intensity"
			elif duration_ticks <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				intensity = int(clamp(intensity, 1, EXPEDITION_COMPRESSION_MAX_INTENSITY))
				expedition_compression_intensity = intensity
				expedition_compression_ticks_left = duration_ticks
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_ticks"] = duration_ticks
				sanitized = {"intensity": intensity}
				_dict_merge_into(sanitized, duration_info)
				immediate_summary = "expedition tempo compressed"
				debts_summary = "attention accrues"
				ok = true
		LEVER_INFORMATION_THROTTLING:
			var level: int = int(payload.get("level", 0))
			var duration_ticks := _duration_payload_ticks(payload)
			if level <= 0:
				immediate_summary = "REJECTED: invalid level"
			elif duration_ticks <= 0:
				immediate_summary = "REJECTED: invalid duration"
			else:
				level = int(clamp(level, 1, INFO_THROTTLE_MAX_LEVEL))
				info_throttle_level = level
				info_throttle_ticks_left = duration_ticks
				var duration_info: Dictionary = _duration_payload_summary(payload)
				duration_info["duration_ticks"] = duration_ticks
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

func _module_key(f: int, x: int, y: int) -> String:
	return "%d:%d:%d" % [f, x, y]

func _parse_module_instance_id(instance_id: String) -> Dictionary:
	if instance_id == "":
		return {}
	var parts: Array[String] = instance_id.split(":")
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
			var grid = sim_tower.floors[f]
			for y in range(sim_tower.height):
				for x in range(sim_tower.width):
					if grid[y][x] == target_id:
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

func _evaluate_incidents(sim_day: int, run_seed: int, sim_res: Resources) -> Array[String]:
	var incidents: Array[String] = []

	# Deterministic RNG derived from seed + day. No global RNG mutation.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run_seed) * 73856093 + int(sim_day) * 19349663

	# INCIDENT_DEFS order is load-bearing for determinism; do not reorder.
	for incident_def in IncidentDefsRef.INCIDENT_DEFS:
		var threshold: int = int(incident_def.get("threshold", 0))
		if sim_res.threat < threshold:
			continue

		var chance: float = float(incident_def.get("chance", 0.0))
		var roll: float = rng.randf()
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
	for key in deltas.keys():
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
	for key in deltas.keys():
		scaled[key] = _scale_delta_for_workforce(int(deltas[key]), effective_multiplier)
	return scaled

func _recompute_expedition_heat() -> void:
	var weighted: int = expedition_count_total + (expedition_streak * 3) + (expedition_recent_score * 2)
	expedition_heat = int(weighted / 4)

func _start_expedition_day() -> void:
	expedition_happened_today = false
	expedition_commands_today = 0
	if expedition_recent_score > 0:
		expedition_recent_score = max(expedition_recent_score - EXPEDITION_RECENT_DECAY, 0)
	_recompute_expedition_heat()

func _phase_levers(sim_day: int, sim_tower: Tower, sim_res: Resources, obs: Array[String]) -> void:
	# Phase -1: levers (policy effects + queued conversions)
	ration_consumption_multiplier_today = 1.0
	ration_recovery_multiplier_today = 1.0
	labor_output_multiplier_today = 1.0
	labor_efficiency_cap_today = 1.0
	expedition_yield_bonus_per_crew_today = 0
	expedition_attention_bonus_per_trip_today = 0
	info_throttle_morale_factor_today = 1.0
	info_misalloc_multiplier_today = 1.0
	lever_threat_bonus_today = 0

	var ration_active_today := ration_hardening_ticks_left > 0
	var labor_active_today := labor_overdrive_ticks_left > 0
	var expedition_active_today := expedition_compression_ticks_left > 0
	var info_active_today := info_throttle_ticks_left > 0
	var conversions_processed_today := false

	if not abandoned_modules.is_empty():
		var keys: Array = abandoned_modules.keys()
		# NOTE: abandoned_modules MUST NOT be mutated during iteration.
		keys.sort()
		for key in keys:
			var parts: Array[String] = str(key).split(":")
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
		ration_hardening_ticks_left = max(ration_hardening_ticks_left - 1, 0)
		_obs_push(obs, "LEVER_RATION@%s" % ration_hardening_mode)
		_log_lever_event(
			sim_day,
			LEVER_RATION_HARDENING,
			{"mode": ration_hardening_mode, "ticks_left": ration_hardening_ticks_left},
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
		labor_overdrive_ticks_left = max(labor_overdrive_ticks_left - 1, 0)
		_obs_push(obs, "LEVER_LABOR@%d" % intensity)
		_log_lever_event(
			sim_day,
			LEVER_LABOR_OVERDRIVE,
			{"intensity": intensity, "ticks_left": labor_overdrive_ticks_left},
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
		expedition_compression_ticks_left = max(expedition_compression_ticks_left - 1, 0)
		_obs_push(obs, "LEVER_EXPEDITION@%d" % intensity)
		_log_lever_event(
			sim_day,
			LEVER_EXPEDITION_COMPRESSION,
			{"intensity": intensity, "ticks_left": expedition_compression_ticks_left},
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
		info_throttle_ticks_left = max(info_throttle_ticks_left - 1, 0)
		_obs_push(obs, "LEVER_INFO@%d" % level)
		_log_lever_event(
			sim_day,
			LEVER_INFORMATION_THROTTLING,
			{"level": level, "ticks_left": info_throttle_ticks_left},
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
			var available := int(sim_res.get(from_key))
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
			sim_res.set(from_key, available - used)
			sim_res.set(to_key, int(sim_res.get(to_key)) + produced)
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
	return (
		int(run_seed) * 73856093
		+ int(sim_day) * 19349663
		+ int(total_count) * 83492791
		+ int(day_index) * 2654435761
	)

func _schedule_expedition_lag(
	sim_day: int,
	run_seed: int,
	obs: Array[String],
	day_index: int,
	heat_at_schedule: int,
	total_count: int
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed_for_expedition(run_seed, sim_day, total_count, day_index)

	var delay: int = 3 + int(rng.randi() % 3) # 3..5 inclusive
	if heat_at_schedule >= EXPEDITION_HEAT_DELAY_THRESHOLD:
		delay = 3 + int(rng.randi() % 2) # 3..4 inclusive

	var retaliation_chance: int = 50 + min(heat_at_schedule * EXPEDITION_KIND_BIAS_PER_HEAT, EXPEDITION_KIND_BIAS_CAP)
	var kind_roll: int = int(rng.randi() % 100)
	var kind: String = "RETALIATION_RISK" if kind_roll < retaliation_chance else "SUPPLY_CHAIN_FRICTION"

	var magnitude_base: int = 0
	if kind == "RETALIATION_RISK":
		magnitude_base = 2 + int(rng.randi() % 5) # 2..6 threat
	else:
		magnitude_base = 1 + int(rng.randi() % 3) # 1..3 morale
	var heat_bonus: int = int(heat_at_schedule / EXPEDITION_MAG_HEAT_DIV)
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
	# Phase B: production & consumption
	var food_consumption := int(ceil(float(sim_res.population) * food_ration * ration_consumption_multiplier_today))
	var water_consumption := int(ceil(float(sim_res.population) * water_ration * ration_consumption_multiplier_today))
	sim_res.add_delta("food", -food_consumption)
	sim_res.add_delta("water", -water_consumption)

	var instances: Array[ModuleInstance] = []
	var total_capacity: int = 0
	var order_index: int = 0
	var powered_count: int = 0

	for f in range(sim_tower.floors.size()):
		var grid = sim_tower.floors[f]
		for y in range(sim_tower.height):
			for x in range(sim_tower.width):
				var id = grid[y][x]
				if id == null:
					continue
				if not sim_tower.is_module_enabled(f, x, y):
					_obs_push(obs, "DISABLED_MODULE@%d:%d:%d" % [f, x, y])
					continue
				if _is_module_abandoned(f, x, y):
					_obs_push(obs, "ABANDONED_MODULE@%d:%d:%d" % [f, x, y])
					continue

				var def: ModuleDef = sim_db.get_def(id)
				if def == null:
					continue

				var inst := ModuleInstance.new(def)
				inst.order_index = order_index
				inst.floor = f
				inst.x = x
				inst.y = y
				var prio_override: Variant = sim_tower.get_module_priority_override(f, x, y)
				if prio_override != null:
					inst.priority = int(prio_override)
				order_index += 1
				instances.append(inst)

				# Generators (and any supply) contribute regardless of priority/power availability
				sim_res.power_supply += def.power_supply

	instances.sort_custom(func(a: ModuleInstance, b: ModuleInstance) -> bool:
		if a.priority != b.priority:
			return a.priority < b.priority
		if a.def.id != b.def.id:
			return a.def.id < b.def.id
		if a.def.name != b.def.name:
			return a.def.name < b.def.name
		if a.floor != b.floor:
			return a.floor < b.floor
		if a.y != b.y:
			return a.y < b.y
		if a.x != b.x:
			return a.x < b.x
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
			powered_count += 1
			var deltas := inst.compute_resource_deltas(sim_res)
			var lever_adjusted := _apply_lever_output_modifiers(deltas)
			var scaled := _scale_deltas_for_workforce(lever_adjusted, workforce_multiplier_today)
			_apply_module_deltas_stably(sim_res, scaled)
			total_capacity += def.delta_capacity
			total_noise += def.noise
			total_heat += def.heat
		else:
			# Unpowered penalty (light, for now)
			sim_res.add_delta("morale", -1)

	sim_res.apply_deltas()

	return {
		"powered_count": powered_count,
		"total_capacity": total_capacity,
		"total_noise": total_noise,
		"total_heat": total_heat,
	}

func _phase_growth_dependency(sim_res: Resources, powered_count: int, obs: Array[String]) -> Dictionary:
	# Phase C: growth & dependency (maintenance / fragility)
	var maintenance_cost: int = int(ceil(float(powered_count) * 0.5))
	var maintenance_shortfall: bool = false
	var maintenance_morale_penalty: int = 0

	if maintenance_cost > 0:
		var materials_before: int = sim_res.materials
		sim_res.materials = max(sim_res.materials - maintenance_cost, 0)
		if materials_before < maintenance_cost:
			maintenance_shortfall = true
			maintenance_morale_penalty = 1
			# Maintenance shortfalls degrade morale and add detectability pressure.
			sim_res.morale -= maintenance_morale_penalty
			sim_res.threat += 1
			_obs_push(obs, "MAINT_SHORTFALL")

	return {
		"maintenance_cost": maintenance_cost,
		"maintenance_shortfall": maintenance_shortfall,
		"maintenance_morale_penalty": maintenance_morale_penalty,
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

	var power_signature := sim_res.power_used
	sim_res.threat += int(total_noise * 0.5) + int(total_heat * 0.5) + int(power_signature * 0.2)

	if expedition_threat_today > 0:
		sim_res.threat += expedition_threat_today

	if lever_threat_bonus_today > 0:
		sim_res.threat += lever_threat_bonus_today

	# If morale is collapsing, people make mistakes -> more threat
	var morale_for_threat: int = sim_res.morale + maintenance_morale_penalty
	if morale_for_threat <= 10:
		sim_res.threat += 1

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

func _phase_exit_checks(sim_res: Resources, obs: Array[String]) -> String:
	# Phase F: exit checks (stub evaluator only)
	if sim_res.population <= 0:
		_obs_push(obs, "EXIT_COLLAPSE_CANDIDATE")
		return "collapse_candidate"
	return "none"

func _emit_observations(pre_threat: int, sim_res: Resources, obs: Array[String]) -> void:
	# Phase G: emit observations (tokens derived from transitions)
	var threshold_logs := _evaluate_threat_thresholds(pre_threat, sim_res.threat)
	for marker in threshold_logs:
		var parts: Array[String] = str(marker).split("@")
		if parts.size() == 2:
			_obs_push(obs, "THR_CROSSED@%s" % parts[1])

func _step_day_core(sim_day: int, run_seed: int, sim_tower: Tower, sim_res: Resources, sim_db: ModuleDB) -> Array[String]:
	var pre_threat: int = sim_res.threat
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
	var growth := _phase_growth_dependency(sim_res, int(production.get("powered_count", 0)), obs)

	# Phase D: pressure accrual
	_phase_pressure_accrual(sim_res, production, growth, obs, sim_day)

	# Phase E: resolution
	_phase_resolution(sim_res, growth, obs)

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
	return _merge_incident_lists(maintenance_logs, _merge_incident_lists(threshold_logs, incident_logs))

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

func debug_run_determinism(days_to_run: int, run_seed: int) -> void:
	var run_a := _simulate_days(days_to_run, run_seed)
	var run_b := _simulate_days(days_to_run, run_seed)

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
		var incidents := sim._step_day_core(sim.day, run_seed, sim.tower, sim.res, sim.db)
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
