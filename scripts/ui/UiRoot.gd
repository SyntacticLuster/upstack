extends CanvasLayer

@export var sim_path: NodePath
@export var game_path: NodePath = NodePath("../..")
@export var poll_interval_sec: float = 0.25

const BREAKPOINT_TABS := 800.0
const BREAKPOINT_RAIL_COLLAPSE := 800.0
const LEDGER_DEFAULT_RATIO := 0.2
const LEDGER_MIN_HEIGHT := 225.0

@onready var root_control: Control = $Root
@onready var hud_panel = $Root/Layout/HudPanel
@onready var content_split: VSplitContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit
@onready var content_tabs: TabContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentTabs
@onready var console_panel = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/OperationsConsole
@onready var ledger_panel = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/LedgerPanel

var _sim: Object = null
var _game: Object = null
var _use_polling: bool = false
var _poll_accum: float = 0.0
var _layout_forced_left_rail: bool = false
var _split_initialized: bool = false

func _ready() -> void:
	_sim = _resolve_sim()
	hud_panel.set_sim(_sim)
	console_panel.set_sim(_sim)
	ledger_panel.set_sim(_sim)

	_game = _resolve_game()
	if _game == null:
		push_warning("UIRoot: unable to resolve Game node for HUD updates")
	hud_panel.set_game(_game)
	if _game != null and _game.has_signal("pacing_state_changed"):
		_game.connect("pacing_state_changed", Callable(self, "_on_game_pacing_state_changed"))

	if _sim != null and _sim.has_signal("tick"):
		_sim.connect("tick", Callable(self, "_on_sim_tick"))
		_refresh_all()
	else:
		_use_polling = true
		_refresh_all()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_apply_responsive_layout")
	call_deferred("_log_ui_sizes")

func _log_ui_sizes() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var root_size := root_control.size if root_control != null else Vector2.ZERO
	print("[boot] viewport_size=%s uiroot_size=%s" % [str(viewport_size), str(root_size)])

func _process(delta: float) -> void:
	if not _use_polling:
		return
	_poll_accum += delta
	if _poll_accum >= poll_interval_sec:
		_poll_accum = 0.0
		_refresh_all()

func _on_sim_tick(_day: int) -> void:
	_refresh_all()

func _on_game_pacing_state_changed(_multiplier: float, _paused: bool) -> void:
	_refresh_all()

func _refresh_all() -> void:
	hud_panel.refresh()
	console_panel.refresh()
	ledger_panel.refresh()

func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()

func _apply_responsive_layout() -> void:
	if root_control == null:
		return
	var width := root_control.size.x
	var narrow := width < BREAKPOINT_TABS
	var collapse_rail := width <= BREAKPOINT_RAIL_COLLAPSE
	_set_time_controls_vertical(collapse_rail)
	_apply_left_rail_layout(width, collapse_rail)
	_apply_content_layout(narrow)

func _set_time_controls_vertical(use_column: bool) -> void:
	if hud_panel != null and hud_panel.has_method("set_time_controls_vertical"):
		hud_panel.set_time_controls_vertical(use_column)

func _apply_left_rail_layout(width: float, collapse_rail: bool) -> void:
	if hud_panel == null:
		return
	if collapse_rail:
		_layout_forced_left_rail = true
		if hud_panel.has_method("set_left_rail_collapsed"):
			hud_panel.set_left_rail_collapsed(true, "layout")
		return
	if _layout_forced_left_rail and hud_panel.has_method("restore_left_rail_from_user"):
		hud_panel.restore_left_rail_from_user()
		_layout_forced_left_rail = false
	if hud_panel.has_method("apply_left_rail_width"):
		hud_panel.apply_left_rail_width(_left_rail_width_for(width))

func _left_rail_width_for(width: float) -> float:
	if width >= 1920.0:
		return 260.0
	if width >= 1600.0:
		return 220.0
	if width >= 1152.0:
		return 180.0
	return 160.0

func _apply_content_layout(use_tabs: bool) -> void:
	if content_split == null or content_tabs == null:
		return
	if use_tabs:
		_move_to_tabs()
	else:
		_move_to_split()
	content_tabs.visible = use_tabs
	content_split.visible = not use_tabs
	if not use_tabs:
		_apply_split_ratio()

func _move_to_tabs() -> void:
	if console_panel != null and console_panel.get_parent() != content_tabs:
		console_panel.reparent(content_tabs)
	if ledger_panel != null and ledger_panel.get_parent() != content_tabs:
		ledger_panel.reparent(content_tabs)
	_ensure_tab_titles()

func _move_to_split() -> void:
	if console_panel != null and console_panel.get_parent() != content_split:
		console_panel.reparent(content_split)
	if ledger_panel != null and ledger_panel.get_parent() != content_split:
		ledger_panel.reparent(content_split)
	if console_panel != null and ledger_panel != null:
		content_split.move_child(console_panel, 0)
		content_split.move_child(ledger_panel, 1)

func _ensure_tab_titles() -> void:
	if console_panel != null:
		var idx := content_tabs.get_tab_idx_from_control(console_panel)
		if idx >= 0:
			content_tabs.set_tab_title(idx, "OPERATIONS")
	if ledger_panel != null:
		var idx := content_tabs.get_tab_idx_from_control(ledger_panel)
		if idx >= 0:
			content_tabs.set_tab_title(idx, "LEDGER")

func _apply_split_ratio() -> void:
	if _split_initialized:
		return
	if content_split.size.y <= 0.0:
		call_deferred("_apply_split_ratio")
		return
	var total_height := content_split.size.y
	var ledger_target := int(max(LEDGER_MIN_HEIGHT, total_height * LEDGER_DEFAULT_RATIO))
	var top_height := int(max(0.0, total_height - ledger_target))
	content_split.split_offset = top_height
	_split_initialized = true

func _resolve_sim() -> Object:
	var sim_ref: Object = null
	if sim_path != NodePath(""):
		var node := get_node_or_null(sim_path)
		if node != null:
			sim_ref = node
	if sim_ref == null:
		sim_ref = get_tree().get_root().find_child("Sim", true, false)
	return sim_ref

func _resolve_game() -> Game:
	var candidate := _resolve_game_from_parent()
	if candidate != null:
		return candidate
	candidate = _resolve_game_from_current_scene()
	if candidate != null:
		return candidate
	candidate = _resolve_game_from_path()
	if candidate != null:
		return candidate
	return _resolve_game_from_tree()

func _resolve_game_from_parent() -> Game:
	var parent_game := get_parent()
	return parent_game if _is_game_node(parent_game) else null

func _resolve_game_from_current_scene() -> Game:
	var current_scene := get_tree().get_current_scene()
	return current_scene if _is_game_node(current_scene) else null

func _resolve_game_from_path() -> Game:
	if game_path == NodePath(""):
		return null
	var node := get_node_or_null(game_path)
	if node == null:
		push_warning("UIRoot: game_path %s did not resolve to a node" % game_path)
		return null
	if _is_game_node(node):
		return node
	push_warning("UIRoot: node at %s is %s, expected Game" % [game_path, node.get_class()])
	return null

func _resolve_game_from_tree() -> Game:
	var tree_root := get_tree().get_root()
	var found := tree_root.find_child("Game", true, false)
	return found if _is_game_node(found) else null

func _is_game_node(node: Object) -> bool:
	return node != null and node is Game
