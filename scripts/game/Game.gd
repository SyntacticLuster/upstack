extends Node
class_name Game

const SPEED_MULTIPLIERS := [0.5, 1.0, 2.0, 4.0]
const SPEED_LABELS := ["0.5x", "1x", "2x", "4x"]
const BASE_SECONDS_PER_HOUR := 10.0

@export_range(1, 5) var max_ticks_per_frame: int = 3

@onready var sim: Sim = $Sim

var is_paused: bool = false
var speed_index: int = 1
var accumulator_seconds: float = 0.0

signal pacing_state_changed(multiplier: float, is_paused: bool)

func _ready() -> void:
	if sim != null:
		sim.set_process(false)
	set_process(true)
	set_process_input(true)
	max_ticks_per_frame = max(1, max_ticks_per_frame)
	_log_window_state()
	_emit_pacing_state()

func _log_window_state() -> void:
	var mode := DisplayServer.window_get_mode()
	var size := DisplayServer.window_get_size()
	print("[boot] window_mode=%s window_size=%s" % [str(mode), str(size)])

func _process(delta: float) -> void:
	if is_paused or sim == null:
		return
	var speed_multiplier := _current_speed_multiplier()
	if speed_multiplier <= 0.0:
		return
	accumulator_seconds += delta
	var tick_interval := BASE_SECONDS_PER_HOUR / speed_multiplier
	var ticks_this_frame := 0
	while accumulator_seconds >= tick_interval and ticks_this_frame < max_ticks_per_frame:
		_tick_sim_hour()
		accumulator_seconds -= tick_interval
		ticks_this_frame += 1

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			toggle_pause()
		KEY_BRACKETLEFT:
			cycle_speed(-1)
		KEY_BRACKETRIGHT:
			cycle_speed(1)
		KEY_1:
			set_speed_index(0)
		KEY_2:
			set_speed_index(1)
		KEY_3:
			set_speed_index(2)

func toggle_pause() -> void:
	is_paused = not is_paused
	_emit_pacing_state()

func cycle_speed(direction: int) -> void:
	set_speed_index(speed_index + direction)

func set_speed_index(index: int) -> void:
	var clamped: int = int(clamp(index, 0, SPEED_MULTIPLIERS.size() - 1))
	if speed_index == clamped:
		return
	speed_index = clamped
	_emit_pacing_state()

func set_speed_multiplier(multiplier: float) -> void:
	var idx := SPEED_MULTIPLIERS.find(multiplier)
	if idx == -1:
		return
	set_speed_index(idx)

func get_speed_multiplier() -> float:
	return _current_speed_multiplier()

func get_pacing_label() -> String:
	if is_paused:
		return "PAUSED"
	return SPEED_LABELS[clamp(speed_index, 0, SPEED_LABELS.size() - 1)]

func is_paused_now() -> bool:
	return is_paused

func get_speed_index() -> int:
	var max_index: int = SPEED_MULTIPLIERS.size() - 1
	return max(0, min(speed_index, max_index))

func _current_speed_multiplier() -> float:
	return SPEED_MULTIPLIERS[clamp(speed_index, 0, SPEED_MULTIPLIERS.size() - 1)]

func _tick_sim_hour() -> void:
	if sim == null:
		return
	sim._advance_hour()

func _emit_pacing_state() -> void:
	emit_signal("pacing_state_changed", _current_speed_multiplier(), is_paused)
