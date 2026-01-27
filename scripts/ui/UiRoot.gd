extends Control

@export var sim_path: NodePath
@export var poll_interval_sec: float = 0.25

@onready var hud_panel = $VBox/HudPanel
@onready var console_panel = $VBox/OperationsConsole
@onready var ledger_panel = $VBox/LedgerPanel

var _sim: Object = null
var _use_polling: bool = false
var _poll_accum: float = 0.0

func _ready() -> void:
	_sim = _resolve_sim()
	hud_panel.set_sim(_sim)
	console_panel.set_sim(_sim)
	ledger_panel.set_sim(_sim)
	if _sim != null and _sim.has_signal("tick"):
		_sim.connect("tick", Callable(self, "_on_sim_tick"))
		_refresh_all()
	else:
		_use_polling = true
		_refresh_all()

func _process(delta: float) -> void:
	if not _use_polling:
		return
	_poll_accum += delta
	if _poll_accum >= poll_interval_sec:
		_poll_accum = 0.0
		_refresh_all()

func _on_sim_tick(_day: int) -> void:
	_refresh_all()

func _refresh_all() -> void:
	hud_panel.refresh()
	ledger_panel.refresh()

func _resolve_sim() -> Object:
	var sim_ref: Object = null
	if sim_path != NodePath(""):
		var node := get_node_or_null(sim_path)
		if node != null:
			sim_ref = node
	if sim_ref == null:
		sim_ref = get_tree().get_root().find_child("Sim", true, false)
	return sim_ref
