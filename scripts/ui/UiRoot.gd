extends CanvasLayer

@export var sim_path: NodePath
@export var game_path: NodePath = NodePath("../..")
@export var poll_interval_sec: float = 0.25

const BREAKPOINT_TABS := 800.0
const BREAKPOINT_RAIL_COLLAPSE := 800.0
const LEDGER_DEFAULT_RATIO := 0.5
const BOTTOM_SPLIT_RATIO := 0.65

@onready var root_control: Control = $Root
@onready var hud_panel = $Root/Layout/HudPanel
@onready var content_split: VSplitContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit
@onready var content_tabs: TabContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentTabs
@onready var console_panel = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/OperationsConsole
@onready var bottom_split: HSplitContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/BottomSplit
@onready var expedition_tabs: TabContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/BottomSplit/ExpeditionTabs
@onready var expeditions_root: VBoxContainer = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/BottomSplit/ExpeditionTabs/ExpeditionsTab/ExpeditionsRoot
@onready var map_panel = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/BottomSplit/ExpeditionTabs/MapTab/MapPanel
@onready var ledger_panel = $Root/Layout/HudPanel/Root/MainRow/ContentColumn/ContentSplit/BottomSplit/LedgerPanel
@onready var toast_panel: PanelContainer = $Root/ToastLayer/ToastPanel
@onready var toast_label: Label = $Root/ToastLayer/ToastPanel/ToastLabel
@onready var modal_layer: ColorRect = $Root/ModalLayer
@onready var modal_message: Label = $Root/ModalLayer/ModalPanel/ModalRoot/ModalMessage
@onready var modal_ack: Button = $Root/ModalLayer/ModalPanel/ModalRoot/ModalAcknowledge

var _sim: Object = null
var _game: Object = null
var _use_polling: bool = false
var _poll_accum: float = 0.0
var _layout_forced_left_rail: bool = false
var _layout_initialized: bool = false
var _event_bridge: SimBridge = null
var _seen_event_keys: Dictionary = {}
var _toast_queue: Array[Dictionary] = []
var _toast_active: bool = false
var _toast_tween: Tween = null
var _toast_cooldowns: Dictionary = {}
var _modal_queue: Array[Dictionary] = []
var _modal_active_key: String = ""
var _content_split_ratio: float = LEDGER_DEFAULT_RATIO
var _content_split_user_set: bool = false
var _content_split_applying: bool = false
var _bottom_split_ratio: float = BOTTOM_SPLIT_RATIO
var _bottom_split_user_set: bool = false
var _bottom_split_applying: bool = false

func _ready() -> void:
	_sim = _resolve_sim()
	hud_panel.set_sim(_sim)
	console_panel.set_sim(_sim)
	map_panel.set_sim(_sim)
	ledger_panel.set_sim(_sim)
	_move_expeditions_to_tabs()
	_ensure_expedition_tab_titles()
	if _event_bridge == null:
		_event_bridge = SimBridge.new()
	_event_bridge.set_sim(_sim)
	if toast_panel != null:
		toast_panel.visible = false
	if modal_layer != null:
		modal_layer.visible = false
	var modal_cb: Callable = Callable(self, "_on_modal_ack_pressed")
	if modal_ack != null and not modal_ack.pressed.is_connected(modal_cb):
		modal_ack.pressed.connect(modal_cb)

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
	if bottom_split != null:
		var dragged_cb := Callable(self, "_on_bottom_split_dragged")
		if not bottom_split.dragged.is_connected(dragged_cb):
			bottom_split.dragged.connect(dragged_cb)
		var size_cb := Callable(self, "_on_bottom_split_resized")
		if not bottom_split.resized.is_connected(size_cb):
			bottom_split.resized.connect(size_cb)
	if content_split != null:
		var content_dragged_cb := Callable(self, "_on_content_split_dragged")
		if not content_split.dragged.is_connected(content_dragged_cb):
			content_split.dragged.connect(content_dragged_cb)
		var content_size_cb := Callable(self, "_on_content_split_resized")
		if not content_split.resized.is_connected(content_size_cb):
			content_split.resized.connect(content_size_cb)
	call_deferred("_apply_responsive_layout")
	call_deferred("_log_ui_sizes")
	call_deferred("_ensure_layout_initialized")

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
	map_panel.refresh()
	ledger_panel.refresh()
	_refresh_event_routing()

func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()
	if not _layout_initialized:
		call_deferred("_ensure_layout_initialized")

func _ensure_layout_initialized() -> void:
	if _layout_initialized:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if _layout_initialized:
		return
	if not _layout_has_sizes():
		call_deferred("_ensure_layout_initialized")
		return
	_layout_initialized = true
	_apply_split_ratio()
	_apply_bottom_split_ratio()

func _layout_has_sizes() -> bool:
	if content_split == null or bottom_split == null:
		return false
	if content_split.size.y <= 0.0:
		return false
	if bottom_split.size.x <= 0.0:
		return false
	return true

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
	_apply_bottom_split_ratio()

func _move_to_tabs() -> void:
	if console_panel != null and console_panel.get_parent() != content_tabs:
		console_panel.reparent(content_tabs)
	if bottom_split != null and bottom_split.get_parent() != content_tabs:
		bottom_split.reparent(content_tabs)
	_ensure_tab_titles()

func _move_to_split() -> void:
	if console_panel != null and console_panel.get_parent() != content_split:
		console_panel.reparent(content_split)
	if bottom_split != null and bottom_split.get_parent() != content_split:
		bottom_split.reparent(content_split)
	if console_panel != null and bottom_split != null:
		content_split.move_child(console_panel, 0)
		content_split.move_child(bottom_split, 1)

func _ensure_tab_titles() -> void:
	if console_panel != null:
		var idx := content_tabs.get_tab_idx_from_control(console_panel)
		if idx >= 0:
			content_tabs.set_tab_title(idx, "OPERATIONS")
	if bottom_split != null:
		var idx := content_tabs.get_tab_idx_from_control(bottom_split)
		if idx >= 0:
			content_tabs.set_tab_title(idx, "FIELD")

func _apply_split_ratio() -> void:
	if content_split == null:
		return
	if content_split.size.y <= 0.0:
		call_deferred("_apply_split_ratio")
		return
	if not _layout_initialized and not _content_split_user_set:
		return
	var total_height := content_split.size.y
	var target_ratio := _content_split_ratio if _content_split_user_set else LEDGER_DEFAULT_RATIO
	if not _is_valid_ratio(target_ratio):
		_content_split_user_set = false
		target_ratio = LEDGER_DEFAULT_RATIO
	_set_content_split_offset_for_ratio(target_ratio, total_height)

func _apply_bottom_split_ratio() -> void:
	if bottom_split == null:
		return
	if bottom_split.size.x <= 0.0:
		call_deferred("_apply_bottom_split_ratio")
		return
	if not _layout_initialized and not _bottom_split_user_set:
		return
	var total_width := bottom_split.size.x
	var target_ratio := _bottom_split_ratio if _bottom_split_user_set else BOTTOM_SPLIT_RATIO
	if not _is_valid_ratio(target_ratio):
		_bottom_split_user_set = false
		target_ratio = BOTTOM_SPLIT_RATIO
	_set_bottom_split_offset_for_ratio(target_ratio, total_width)

func _on_bottom_split_dragged(offset: float) -> void:
	if bottom_split == null:
		return
	var width: float = maxf(1.0, bottom_split.size.x)
	_bottom_split_ratio = clampf(0.5 + (float(offset) / width), 0.0, 1.0)
	_bottom_split_user_set = true

func _on_bottom_split_resized() -> void:
	if _bottom_split_applying:
		return
	_apply_bottom_split_ratio()

func _on_content_split_dragged(offset: float) -> void:
	if content_split == null:
		return
	var height: float = maxf(1.0, content_split.size.y)
	_content_split_ratio = clampf(0.5 + (float(offset) / height), 0.0, 1.0)
	_content_split_user_set = true

func _on_content_split_resized() -> void:
	if _content_split_applying:
		return
	_apply_split_ratio()

func _set_bottom_split_offset_for_ratio(ratio: float, width: float) -> void:
	if bottom_split == null or width <= 0.0 or _bottom_split_applying:
		return
	_bottom_split_applying = true
	var clamped := clampf(ratio, 0.0, 1.0)
	bottom_split.split_offset = int(round((clamped - 0.5) * width))
	_bottom_split_applying = false

func _set_content_split_offset_for_ratio(ratio: float, height: float) -> void:
	if content_split == null or height <= 0.0 or _content_split_applying:
		return
	_content_split_applying = true
	var clamped := clampf(ratio, 0.0, 1.0)
	content_split.split_offset = int(round((clamped - 0.5) * height))
	_content_split_applying = false

func _is_valid_ratio(ratio: float) -> bool:
	return ratio >= 0.0 and ratio <= 1.0

func _ensure_expedition_tab_titles() -> void:
	if expedition_tabs == null:
		return
	var expeditions_tab := expedition_tabs.get_node_or_null("ExpeditionsTab") as Control
	if expeditions_tab != null:
		var expeditions_idx := expedition_tabs.get_tab_idx_from_control(expeditions_tab)
		if expeditions_idx >= 0:
			expedition_tabs.set_tab_title(expeditions_idx, "EXPEDITIONS")
	if map_panel != null:
		var map_tab := map_panel.get_parent() as Control
		if map_tab != null:
			var map_idx := expedition_tabs.get_tab_idx_from_control(map_tab)
			if map_idx >= 0:
				expedition_tabs.set_tab_title(map_idx, "MAP")

func _move_expeditions_to_tabs() -> void:
	if console_panel == null or expeditions_root == null:
		return
	var expeditions_section := console_panel.get_node_or_null("Layout/Scroll/Root/SectionExpeditions") as Control
	if expeditions_section == null:
		return
	if expeditions_section.get_parent() != expeditions_root:
		expeditions_section.reparent(expeditions_root)
		expeditions_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		expeditions_section.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _refresh_event_routing() -> void:
	if _event_bridge == null or not _event_bridge.has_sim():
		return
	var events: Array[Dictionary] = _event_bridge.get_events()
	if events.is_empty():
		_seen_event_keys.clear()
		_toast_cooldowns.clear()
		_toast_queue.clear()
		_modal_queue.clear()
		_modal_active_key = ""
		_toast_active = false
		if _toast_tween != null and _toast_tween.is_running():
			_toast_tween.kill()
		if toast_panel != null:
			toast_panel.visible = false
		if modal_layer != null:
			modal_layer.visible = false
		return
	for entry in events:
		var key := _event_key(entry)
		if key == "":
			continue
		if _seen_event_keys.has(key):
			continue
		_seen_event_keys[key] = true
		var visibility_value: Variant = entry.get("visibility", "")
		var visibility := str(visibility_value)
		match visibility:
			"toast":
				_maybe_queue_toast(entry)
			"modal":
				_queue_modal(entry)

func _event_key(entry: Dictionary) -> String:
	var key_value: Variant = entry.get("key", "")
	var key := str(key_value)
	if key != "":
		return key
	var type_token := str(entry.get("type", ""))
	var day_token := str(entry.get("day", ""))
	var hour_token := str(entry.get("hour", ""))
	var message := str(entry.get("message", ""))
	return "%s|%s|%s|%s" % [type_token, day_token, hour_token, message]

func _maybe_queue_toast(entry: Dictionary) -> void:
	var message := str(entry.get("message", ""))
	if message == "":
		return
	var cooldown_key := _toast_cooldown_key(entry)
	var current_hour := _event_bridge.get_hour_index()
	var last_value: Variant = _toast_cooldowns.get(cooldown_key, -9999)
	var last_hour := int(last_value)
	if current_hour - last_hour < 6:
		return
	_toast_cooldowns[cooldown_key] = current_hour
	_toast_queue.append({"message": message})
	_show_next_toast()

func _toast_cooldown_key(entry: Dictionary) -> String:
	var type_token := str(entry.get("type", ""))
	var source_token := str(entry.get("source", ""))
	return "%s|%s" % [type_token, source_token]

func _show_next_toast() -> void:
	if _toast_active or _toast_queue.is_empty():
		return
	if toast_panel == null or toast_label == null:
		return
	var next_entry: Dictionary = _toast_queue.pop_front()
	var message_text: String = String(next_entry.get("message", ""))
	toast_label.text = message_text
	toast_panel.modulate = Color(1, 1, 1, 0)
	toast_panel.visible = true
	if _toast_tween != null and _toast_tween.is_running():
		_toast_tween.kill()
	_toast_active = true
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_panel, "modulate", Color(1, 1, 1, 1), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(toast_panel, "modulate", Color(1, 1, 1, 0), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_toast_tween.finished.connect(_on_toast_finished)

func _on_toast_finished() -> void:
	_toast_active = false
	if toast_panel != null:
		toast_panel.visible = false
	_show_next_toast()

func _queue_modal(entry: Dictionary) -> void:
	_modal_queue.append(entry)
	_show_next_modal()

func _show_next_modal() -> void:
	if modal_layer == null or modal_message == null:
		return
	if modal_layer.visible:
		return
	if _modal_queue.is_empty():
		return
	var entry: Dictionary = _modal_queue.pop_front()
	var message := str(entry.get("message", ""))
	if message == "":
		return
	_modal_active_key = _event_key(entry)
	modal_message.text = message
	modal_layer.visible = true

func _on_modal_ack_pressed() -> void:
	if modal_layer == null:
		return
	modal_layer.visible = false
	if _modal_active_key != "" and hud_panel != null and hud_panel.has_method("acknowledge_alert"):
		hud_panel.acknowledge_alert(_modal_active_key)
		hud_panel.refresh()
	_modal_active_key = ""
	_show_next_modal()

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
