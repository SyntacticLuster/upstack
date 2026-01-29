
extends PanelContainer

const RESOURCE_OPTIONS := ["food", "water", "materials", "morale"]
const LeverDefsRef = preload("res://scripts/sim/LeverDefs.gd")

const LEVER_RATION_HARDENING := LeverDefsRef.LEVER_RATION_HARDENING
const LEVER_LABOR_OVERDRIVE := LeverDefsRef.LEVER_LABOR_OVERDRIVE
const LEVER_EXPEDITION_COMPRESSION := LeverDefsRef.LEVER_EXPEDITION_COMPRESSION
const LEVER_INFORMATION_THROTTLING := LeverDefsRef.LEVER_INFORMATION_THROTTLING
const LEVER_MODULE_ABANDONMENT := LeverDefsRef.LEVER_MODULE_ABANDONMENT
const LEVER_EMERGENCY_CONVERSION := LeverDefsRef.LEVER_EMERGENCY_CONVERSION

const COLOR_NEUTRAL := Color(0.44, 0.53, 0.63)
const COLOR_SCARCITY := Color(0.92, 0.64, 0.25)
const COLOR_DANGER := Color(0.78, 0.22, 0.22)
const COLOR_AUTHORITY := Color(0.27, 0.55, 0.85)
const COLOR_DESPERATION := Color(0.65, 0.74, 0.20)
const COLOR_LOCKED := Color(0.24, 0.27, 0.33)
const COLOR_DEBUG := Color(0.54, 0.39, 0.63)

const LEVER_BASE_PATHS := {
	LEVER_RATION_HARDENING: "SectionPressure/PressureContent/RationHardening",
	LEVER_LABOR_OVERDRIVE: "SectionPressure/PressureContent/LaborOverdrive",
	LEVER_INFORMATION_THROTTLING: "SectionPressure/PressureContent/InformationThrottling",
	LEVER_EXPEDITION_COMPRESSION: "SectionExpeditions/ExpeditionContent/ExpeditionCompression",
	LEVER_MODULE_ABANDONMENT: "SectionExpeditions/ExpeditionContent/ModuleAbandonment",
	LEVER_EMERGENCY_CONVERSION: "SectionConversions/ConversionContent/EmergencyConversion",
}

const LEVER_HOURS_LEFT_KEYS := {
	LEVER_RATION_HARDENING: "ration_hardening_hours_left",
	LEVER_LABOR_OVERDRIVE: "labor_overdrive_hours_left",
	LEVER_EXPEDITION_COMPRESSION: "expedition_compression_hours_left",
	LEVER_INFORMATION_THROTTLING: "info_throttle_hours_left",
}

const LEVER_METADATA := {
	LEVER_RATION_HARDENING: {
		"touches": ["food stores", "morale", "labor"],
		"cost": "scarcity",
		"reversibility": "delayed",
		"category": "pressure",
	},
	LEVER_LABOR_OVERDRIVE: {
		"touches": ["labor", "morale", "fatigue"],
		"cost": "pressure",
		"reversibility": "delayed",
		"category": "pressure",
	},
	LEVER_INFORMATION_THROTTLING: {
		"touches": ["information", "morale", "authority"],
		"cost": "authority",
		"reversibility": "delayed",
		"category": "pressure",
	},
	LEVER_EXPEDITION_COMPRESSION: {
		"touches": ["crew health", "morale", "time"],
		"cost": "risk",
		"reversibility": "delayed",
		"category": "expedition",
		"note": "Outcomes uncertain; consequences delayed beyond the current cycle.",
	},
	LEVER_MODULE_ABANDONMENT: {
		"touches": ["infrastructure", "morale", "resources"],
		"cost": "irreversible",
		"reversibility": "permanent",
		"category": "expedition",
		"note": "Irreversible module loss.",
	},
	LEVER_EMERGENCY_CONVERSION: {
		"touches": ["resources", "morale"],
		"cost": "irreversible",
		"reversibility": "permanent",
		"category": "conversion",
	},
}

const INPUT_CONFIG := {
	"SectionPressure/PressureContent/RationHardening/CardRoot/Inputs/ModeRow/Mode": {
		"label_path": "SectionPressure/PressureContent/RationHardening/CardRoot/Inputs/ModeRow/ModeLabel",
		"label": "SEVERITY",
		"description": "SOFT: 10% consumption reduction, minor morale hit. HARD: 25% reduction, significant morale and recovery penalties.",
		"payload_key": "mode",
	},
	"SectionPressure/PressureContent/RationHardening/CardRoot/Inputs/DurationRow/Duration": {
		"label_path": "SectionPressure/PressureContent/RationHardening/CardRoot/Inputs/DurationRow/DurationLabel",
		"label": "DURATION (HOURS)",
		"description": "How many hours this policy remains active. 24 hours = 1 day.",
		"payload_key": "duration_hours",
	},
	"SectionPressure/PressureContent/LaborOverdrive/CardRoot/Inputs/IntensityRow/Intensity": {
		"label_path": "SectionPressure/PressureContent/LaborOverdrive/CardRoot/Inputs/IntensityRow/IntensityLabel",
		"label": "INTENSITY",
		"description": "Output multiplier per level: +15%. Higher intensity accelerates labor scar accumulation.",
		"payload_key": "intensity",
	},
	"SectionPressure/PressureContent/LaborOverdrive/CardRoot/Inputs/DurationRow/Duration": {
		"label_path": "SectionPressure/PressureContent/LaborOverdrive/CardRoot/Inputs/DurationRow/DurationLabel",
		"label": "DURATION (HOURS)",
		"description": "How many hours the overdrive policy remains active.",
		"payload_key": "duration_hours",
	},
	"SectionPressure/PressureContent/InformationThrottling/CardRoot/Inputs/LevelRow/Level": {
		"label_path": "SectionPressure/PressureContent/InformationThrottling/CardRoot/Inputs/LevelRow/LevelLabel",
		"label": "THROTTLE LEVEL",
		"description": "Higher levels suppress more information. Increases misallocation risk and backlog accumulation.",
		"payload_key": "level",
	},
	"SectionPressure/PressureContent/InformationThrottling/CardRoot/Inputs/DurationRow/Duration": {
		"label_path": "SectionPressure/PressureContent/InformationThrottling/CardRoot/Inputs/DurationRow/DurationLabel",
		"label": "DURATION (HOURS)",
		"description": "Policy duration in hours.",
		"payload_key": "duration_hours",
	},
	"SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/Inputs/IntensityRow/Intensity": {
		"label_path": "SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/Inputs/IntensityRow/IntensityLabel",
		"label": "TEMPO INTENSITY",
		"description": "Crew yield bonus per level. Higher intensity accumulates attention debt faster.",
		"payload_key": "intensity",
	},
	"SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/Inputs/DurationRow/Duration": {
		"label_path": "SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/Inputs/DurationRow/DurationLabel",
		"label": "DURATION (HOURS)",
		"description": "How many hours the accelerated tempo persists.",
		"payload_key": "duration_hours",
	},
	"SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/Inputs/ModuleRow/ModuleId": {
		"label_path": "SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/Inputs/ModuleRow/ModuleLabel",
		"label": "MODULE INSTANCE ID",
		"description": "Coordinates of the module to abandon. Format: floor:x:y (e.g., 0:2:3). Module will be permanently disabled.",
		"payload_key": "module_instance_id",
	},
	"SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/FromRow/From": {
		"label_path": "SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/FromRow/FromLabel",
		"label": "FROM",
		"description": "Resource to draw from.",
		"payload_key": "from",
	},
	"SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/ToRow/To": {
		"label_path": "SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/ToRow/ToLabel",
		"label": "TO",
		"description": "Resource to convert into.",
		"payload_key": "to",
	},
	"SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/AmountRow/Amount": {
		"label_path": "SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/AmountRow/AmountLabel",
		"label": "AMOUNT",
		"description": "Quantity to redeploy. Actual yield depends on current efficiency.",
		"payload_key": "amount",
	},
}
const NODE_TOOLTIP_CONFIG := {
	"SectionPressure/PressureToggle": {"description": "Toggle Pressure Levers section"},
	"SectionExpeditions/ExpeditionToggle": {"description": "Toggle Expeditions section"},
	"SectionConversions/ConversionToggle": {"description": "Toggle Emergency Conversions section"},
	"SectionPressure/PressureContent/RationHardening/CardRoot/HeaderRow/Title": {"description": "Ration Hardening lever"},
	"SectionPressure/PressureContent/LaborOverdrive/CardRoot/HeaderRow/Title": {"description": "Labor Overdrive lever"},
	"SectionPressure/PressureContent/InformationThrottling/CardRoot/HeaderRow/Title": {"description": "Information Throttling lever"},
	"SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/HeaderRow/Title": {"description": "Expedition Compression lever"},
	"SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/HeaderRow/Title": {"description": "Module Abandonment lever"},
	"SectionConversions/ConversionContent/EmergencyConversion/CardRoot/HeaderRow/Title": {"description": "Emergency Conversion lever"},
	"SectionPressure/PressureContent/RationHardening/CardRoot/FooterRow/Apply": {"lever_id": LEVER_RATION_HARDENING},
	"SectionPressure/PressureContent/LaborOverdrive/CardRoot/FooterRow/Apply": {"lever_id": LEVER_LABOR_OVERDRIVE},
	"SectionPressure/PressureContent/InformationThrottling/CardRoot/FooterRow/Apply": {"lever_id": LEVER_INFORMATION_THROTTLING},
	"SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/FooterRow/Apply": {"lever_id": LEVER_EXPEDITION_COMPRESSION},
	"SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/FooterRow/Apply": {"lever_id": LEVER_MODULE_ABANDONMENT},
	"SectionConversions/ConversionContent/EmergencyConversion/CardRoot/FooterRow/Apply": {"lever_id": LEVER_EMERGENCY_CONVERSION},
}

@onready var _sections_root: VBoxContainer = $Layout/Scroll/Root
@onready var pressure_toggle: Button = _require_section_node("SectionPressure/PressureToggle", "Button") as Button
@onready var pressure_content: VBoxContainer = _require_section_node("SectionPressure/PressureContent", "VBoxContainer") as VBoxContainer
@onready var expedition_toggle: Button = _require_section_node("SectionExpeditions/ExpeditionToggle", "Button") as Button
@onready var expedition_content: VBoxContainer = _require_section_node("SectionExpeditions/ExpeditionContent", "VBoxContainer") as VBoxContainer
@onready var conversion_toggle: Button = _require_section_node("SectionConversions/ConversionToggle", "Button") as Button
@onready var conversion_content: VBoxContainer = _require_section_node("SectionConversions/ConversionContent", "VBoxContainer") as VBoxContainer

@onready var ration_mode: OptionButton = _require_section_node("SectionPressure/PressureContent/RationHardening/CardRoot/Inputs/ModeRow/Mode", "OptionButton") as OptionButton
@onready var ration_duration: SpinBox = _require_section_node("SectionPressure/PressureContent/RationHardening/CardRoot/Inputs/DurationRow/Duration", "SpinBox") as SpinBox
@onready var ration_execute: Button = _require_section_node("SectionPressure/PressureContent/RationHardening/CardRoot/FooterRow/Apply", "Button") as Button
@onready var ration_result: Label = _require_section_node("SectionPressure/PressureContent/RationHardening/CardRoot/FooterRow/Result", "Label") as Label

@onready var labor_intensity: SpinBox = _require_section_node("SectionPressure/PressureContent/LaborOverdrive/CardRoot/Inputs/IntensityRow/Intensity", "SpinBox") as SpinBox
@onready var labor_duration: SpinBox = _require_section_node("SectionPressure/PressureContent/LaborOverdrive/CardRoot/Inputs/DurationRow/Duration", "SpinBox") as SpinBox
@onready var labor_execute: Button = _require_section_node("SectionPressure/PressureContent/LaborOverdrive/CardRoot/FooterRow/Apply", "Button") as Button
@onready var labor_result: Label = _require_section_node("SectionPressure/PressureContent/LaborOverdrive/CardRoot/FooterRow/Result", "Label") as Label

@onready var info_level: SpinBox = _require_section_node("SectionPressure/PressureContent/InformationThrottling/CardRoot/Inputs/LevelRow/Level", "SpinBox") as SpinBox
@onready var info_duration: SpinBox = _require_section_node("SectionPressure/PressureContent/InformationThrottling/CardRoot/Inputs/DurationRow/Duration", "SpinBox") as SpinBox
@onready var info_execute: Button = _require_section_node("SectionPressure/PressureContent/InformationThrottling/CardRoot/FooterRow/Apply", "Button") as Button
@onready var info_result: Label = _require_section_node("SectionPressure/PressureContent/InformationThrottling/CardRoot/FooterRow/Result", "Label") as Label

@onready var expedition_intensity: SpinBox = _require_section_node("SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/Inputs/IntensityRow/Intensity", "SpinBox") as SpinBox
@onready var expedition_duration: SpinBox = _require_section_node("SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/Inputs/DurationRow/Duration", "SpinBox") as SpinBox
@onready var expedition_execute: Button = _require_section_node("SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/FooterRow/Apply", "Button") as Button
@onready var expedition_result: Label = _require_section_node("SectionExpeditions/ExpeditionContent/ExpeditionCompression/CardRoot/FooterRow/Result", "Label") as Label

@onready var abandonment_id: LineEdit = _require_section_node("SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/Inputs/ModuleRow/ModuleId", "LineEdit") as LineEdit
@onready var abandonment_execute: Button = _require_section_node("SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/FooterRow/Apply", "Button") as Button
@onready var abandonment_result: Label = _require_section_node("SectionExpeditions/ExpeditionContent/ModuleAbandonment/CardRoot/FooterRow/Result", "Label") as Label

@onready var conversion_from: OptionButton = _require_section_node("SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/FromRow/From", "OptionButton") as OptionButton
@onready var conversion_to: OptionButton = _require_section_node("SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/ToRow/To", "OptionButton") as OptionButton
@onready var conversion_amount: SpinBox = _require_section_node("SectionConversions/ConversionContent/EmergencyConversion/CardRoot/Inputs/AmountRow/Amount", "SpinBox") as SpinBox
@onready var conversion_execute: Button = _require_section_node("SectionConversions/ConversionContent/EmergencyConversion/CardRoot/FooterRow/Apply", "Button") as Button
@onready var conversion_result: Label = _require_section_node("SectionConversions/ConversionContent/EmergencyConversion/CardRoot/FooterRow/Result", "Label") as Label

var _sim_bridge: SimBridge = null
var _section_config: Dictionary = {}
var _lever_nodes: Dictionary = {}
var _input_controls_ready: bool = false
var _last_results: Dictionary = {}
var _ration_pulse_tween: Tween = null
func _variant_to_int(value: Variant) -> int:
	if value == null:
		return 0
	match typeof(value):
		TYPE_INT:
			return value as int
		TYPE_FLOAT:
			var float_value: float = value as float
			var truncated_value: float
			if float_value >= 0.0:
				truncated_value = floor(float_value)
			else:
				truncated_value = ceil(float_value)
			return truncated_value as int
		TYPE_STRING:
			var text := str(value).strip_edges()
			if text.is_valid_int():
				return text.to_int()
			return 0
		_:
			return 0
func _require_section_node(path: String, type_name: String) -> Node:
	if _sections_root == null:
		push_error("OperationsConsole missing sections root while resolving %s (expected %s)" % [str(path), type_name])
		return null
	var node := _sections_root.get_node_or_null(path)
	if node == null:
		push_error("OperationsConsole missing node at %s (expected %s)" % [str(path), type_name])
	return node

func _validate_required_input_nodes() -> bool:
	var required_nodes := [
		ration_mode,
		ration_duration,
		ration_execute,
		labor_intensity,
		labor_duration,
		labor_execute,
		info_level,
		info_duration,
		info_execute,
		expedition_intensity,
		expedition_duration,
		expedition_execute,
		abandonment_id,
		abandonment_execute,
		conversion_from,
		conversion_to,
		conversion_amount,
		conversion_execute,
	]
	for node in required_nodes:
		if node != null:
			continue
		return false
	return true

func _ready() -> void:
	_setup_sections()
	_input_controls_ready = _validate_required_input_nodes()
	if _input_controls_ready:
		_setup_inputs()
	_map_lever_nodes()
	_apply_tooltips_and_labels()
	if _input_controls_ready:
		_bind_buttons()
		_connect_pressure_signals()
	_refresh_lever_colors()
	_refresh_lever_states()

func set_sim(sim_ref: Object) -> void:
	if _sim_bridge == null:
		_sim_bridge = SimBridge.new()
	_sim_bridge.set_sim(sim_ref)
	refresh()

func _setup_sections() -> void:
	_section_config = {
		"pressure": {
			"toggle": pressure_toggle,
			"content": pressure_content,
			"label": "PRESSURE LEVERS",
			"open": true,
		},
		"expeditions": {
			"toggle": expedition_toggle,
			"content": expedition_content,
			"label": "EXPEDITIONS",
			"open": true,
		},
		"conversions": {
			"toggle": conversion_toggle,
			"content": conversion_content,
			"label": "EMERGENCY CONVERSIONS",
			"open": true,
		},
	}
	for section_name in _section_config.keys():
		var info_variant: Variant = _section_config.get(section_name)
		if not (info_variant is Dictionary):
			continue
		var info: Dictionary = info_variant
		var toggle_variant: Variant = info.get("toggle")
		var content_variant: Variant = info.get("content")
		var toggle := toggle_variant as Button
		var content := content_variant as Control
		if toggle == null or content == null:
			continue
		toggle.toggle_mode = true
		var initial_open := bool(info.get("open", true))
		toggle.set_pressed_no_signal(initial_open)
		content.visible = toggle.is_pressed()
		info["open"] = initial_open
		_update_section_label(section_name)
		toggle.toggled.connect(Callable(self, "_on_section_toggled").bind(section_name))

func _on_section_toggled(pressed: bool, section_name: String) -> void:
	var info_variant: Variant = _section_config.get(section_name)
	if not (info_variant is Dictionary):
		return
	var info: Dictionary = info_variant
	var content_variant: Variant = info.get("content")
	var content := content_variant as Control
	if content != null:
		content.visible = pressed
	info["open"] = pressed
	_update_section_label(section_name)

func _update_section_label(section_name: String) -> void:
	var info_variant: Variant = _section_config.get(section_name)
	if not (info_variant is Dictionary):
		return
	var info: Dictionary = info_variant
	var toggle_variant: Variant = info.get("toggle")
	var label: String = info.get("label", "SECTION")
	var toggle := toggle_variant as Button
	if toggle == null:
		return
	var prefix := "▾" if toggle.pressed else "▸"
	toggle.text = "%s %s" % [prefix, label]

func _setup_inputs() -> void:
	if not _input_controls_ready:
		return
	ration_mode.clear()
	ration_mode.add_item("soft")
	ration_mode.add_item("hard")
	ration_mode.select(0)
	ration_duration.min_value = 1
	ration_duration.max_value = 8760
	ration_duration.step = 1
	ration_duration.value = 24

	labor_intensity.min_value = 1
	labor_intensity.max_value = 5
	labor_intensity.step = 1
	labor_intensity.value = 1
	labor_duration.min_value = 1
	labor_duration.max_value = 8760
	labor_duration.step = 1
	labor_duration.value = 24

	expedition_intensity.min_value = 1
	expedition_intensity.max_value = 5
	expedition_intensity.step = 1
	expedition_intensity.value = 1
	expedition_duration.min_value = 1
	expedition_duration.max_value = 8760
	expedition_duration.step = 1
	expedition_duration.value = 24

	info_level.min_value = 1
	info_level.max_value = 5
	info_level.step = 1
	info_level.value = 1
	info_duration.min_value = 1
	info_duration.max_value = 8760
	info_duration.step = 1
	info_duration.value = 24

	conversion_from.clear()
	conversion_to.clear()
	for key in RESOURCE_OPTIONS:
		conversion_from.add_item(key)
		conversion_to.add_item(key)
	conversion_from.select(0)
	conversion_to.select(1)
	conversion_amount.min_value = 1
	conversion_amount.max_value = 999
	conversion_amount.step = 1
	conversion_amount.value = 1

func _bind_buttons() -> void:
	if not _input_controls_ready:
		return
	ration_execute.pressed.connect(_apply_ration_hardening)
	labor_execute.pressed.connect(_apply_labor_overdrive)
	expedition_execute.pressed.connect(_apply_expedition_compression)
	info_execute.pressed.connect(_apply_information_throttling)
	abandonment_execute.pressed.connect(_apply_module_abandonment)
	conversion_execute.pressed.connect(_apply_emergency_conversion)
func _map_lever_nodes() -> void:
	_lever_nodes.clear()
	for lever_id in LEVER_BASE_PATHS.keys():
		var base_path: String = str(LEVER_BASE_PATHS.get(lever_id, ""))
		if base_path == "":
			continue
		var title: Label = _sections_root.get_node_or_null("%s/CardRoot/HeaderRow/Title" % base_path) as Label
		var intent: Label = _sections_root.get_node_or_null("%s/CardRoot/Intent" % base_path) as Label
		var button: Button = _button_for_lever(lever_id)
		var color_bar: ColorRect = _sections_root.get_node_or_null("%s/CardRoot/ColorBar" % base_path) as ColorRect
		var status_chip: PanelContainer = _sections_root.get_node_or_null("%s/CardRoot/HeaderRow/StatusChip" % base_path) as PanelContainer
		var status_label: Label = _sections_root.get_node_or_null("%s/CardRoot/HeaderRow/StatusChip/StatusLabel" % base_path) as Label
		var warning: Label = _sections_root.get_node_or_null("%s/CardRoot/Warning" % base_path) as Label
		if title == null or intent == null or button == null:
			continue
		_lever_nodes[lever_id] = {
			"title": title,
			"intent": intent,
			"apply": button,
			"color_bar": color_bar,
			"status_chip": status_chip,
			"status_label": status_label,
			"warning": warning,
		}

func _button_for_lever(lever_id: String) -> Button:
	match lever_id:
		LEVER_RATION_HARDENING:
			return ration_execute
		LEVER_LABOR_OVERDRIVE:
			return labor_execute
		LEVER_EXPEDITION_COMPRESSION:
			return expedition_execute
		LEVER_INFORMATION_THROTTLING:
			return info_execute
		LEVER_MODULE_ABANDONMENT:
			return abandonment_execute
		LEVER_EMERGENCY_CONVERSION:
			return conversion_execute
	return null

func _apply_tooltips_and_labels() -> void:
	for path in NODE_TOOLTIP_CONFIG.keys():
		var config: Dictionary = NODE_TOOLTIP_CONFIG.get(path, {})
		var node: Control = _sections_root.get_node_or_null(path) as Control
		if node == null:
			continue
		var tooltip_body: String = _compose_tooltip(config, node)
		if tooltip_body != "":
			node.set_tooltip_text(tooltip_body)
	for path in INPUT_CONFIG.keys():
		var config: Dictionary = INPUT_CONFIG.get(path, {})
		var node: Control = _sections_root.get_node_or_null(path) as Control
		if node == null:
			continue
		var label_path := str(config.get("label_path", ""))
		if label_path != "":
			var label_node := _sections_root.get_node_or_null(label_path) as Label
			if label_node != null:
				label_node.text = str(config.get("label", label_node.text))
		var tooltip_body: String = _compose_tooltip(config, node)
		if tooltip_body != "":
			node.set_tooltip_text(tooltip_body)

func _compose_tooltip(config: Dictionary, control: Control) -> String:
	if config == null:
		return ""
	if config.has("lever_id"):
		var lever_id := str(config.get("lever_id"))
		var meta: Dictionary = LEVER_METADATA.get(lever_id)
		var tooltip_body: String = ""
		if meta != null:
			tooltip_body = _build_tooltip(meta)
		if config.has("description"):
			var prefix := str(config.get("description", ""))
			tooltip_body = "%s\n%s" % [prefix, tooltip_body] if tooltip_body != "" else prefix
		return tooltip_body
	var parts: Array[String] = []
	var description_text := ""
	if config.has("description"):
		description_text = str(config.get("description", ""))
	if description_text != "":
		parts.append(description_text)
	if config.has("payload_key"):
		parts.append("payload: %s" % str(config.get("payload_key")))
	if control is SpinBox:
		var spin: SpinBox = control as SpinBox
		parts.append("Range: %s–%s" % [spin.min_value, spin.max_value])
	return "\n".join(parts)

func refresh() -> void:
	_refresh_conversion_options()
	_refresh_lever_states()
func _refresh_conversion_options() -> void:
	if _sim_bridge == null or not _sim_bridge.has_sim() or conversion_from == null:
		return
	var sim := _sim_bridge.get_sim()
	var burns: Dictionary = sim.get("conversion_burn_counts") if sim != null else {}
	var previously_selected := _selected_conversion_key()
	conversion_from.clear()
	for key in RESOURCE_OPTIONS:
		var count: int = _variant_to_int(burns.get(key, 0))
		var suffix := "[%d/3]" % count
		var label := "%s %s" % [key, suffix]
		if count >= 3:
			label = "%s (BURNED)" % label
		conversion_from.add_item(label)
		var idx := conversion_from.get_item_count() - 1
		conversion_from.set_item_disabled(idx, count >= 3)
	var selected_idx := 0
	if previously_selected != "":
		for idx in range(conversion_from.get_item_count()):
			if conversion_from.get_item_text(idx).begins_with(previously_selected):
				selected_idx = idx
				break
	if conversion_from.is_item_disabled(selected_idx):
		for idx in range(conversion_from.get_item_count()):
			if not conversion_from.is_item_disabled(idx):
				selected_idx = idx
				break
	conversion_from.select(selected_idx)
	if conversion_to.get_item_count() == 0:
		for key in RESOURCE_OPTIONS:
			conversion_to.add_item(key)
		conversion_to.select(1)
	_update_conversion_highlight(burns)

func _update_conversion_highlight(burns: Dictionary) -> void:
	if conversion_from == null:
		return
	var selected_text := conversion_from.get_item_text(conversion_from.selected)
	var key := selected_text.split(" ")[0]
	var count: int = _variant_to_int(burns.get(key, 0))
	if count >= 3:
		conversion_from.modulate = COLOR_LOCKED
	elif count >= 2:
		conversion_from.modulate = COLOR_SCARCITY
	else:
		conversion_from.modulate = Color(1, 1, 1, 1)

func _refresh_lever_states() -> void:
	for lever_id in _lever_nodes.keys():
		_apply_lever_status(lever_id)
		_apply_lever_color(lever_id)

func _apply_lever_status(lever_id: String) -> void:
	var ui: Dictionary = _lever_nodes.get(lever_id)
	if ui == null:
		return
	var status_label: Label = ui.get("status_label") as Label
	var status_chip: PanelContainer = ui.get("status_chip") as PanelContainer
	if status_label == null or status_chip == null:
		return
	var status_text := "INACTIVE"
	var status_color := COLOR_NEUTRAL
	var ration_active := false
	if lever_id == LEVER_EMERGENCY_CONVERSION:
		var burns: Dictionary = _conversion_burns()
		var selected_key: String = _selected_conversion_key()
		var burn_count: int = _variant_to_int(burns.get(selected_key, 0))
		var scar_value: Variant = _read_sim_value("conversion_scar")
		var scar: int = _variant_to_int(scar_value)
		if burn_count >= 3:
			status_text = "BURNED OUT"
			status_color = COLOR_LOCKED
		elif scar > 0:
			status_text = "DEBT ACCRUING"
			status_color = COLOR_DESPERATION
		else:
			status_text = "INACTIVE"
			status_color = COLOR_NEUTRAL
	elif LEVER_HOURS_LEFT_KEYS.has(lever_id):
		var hours_left_value: Variant = _read_sim_value(str(LEVER_HOURS_LEFT_KEYS.get(lever_id)))
		var hours_left: int = _variant_to_int(hours_left_value)
		if hours_left > 0:
			status_text = "ACTIVE (%dh LEFT)" % hours_left
			status_color = COLOR_SCARCITY
			if lever_id == LEVER_RATION_HARDENING:
				ration_active = true
		else:
			status_text = "INACTIVE"
			status_color = COLOR_NEUTRAL
	status_label.text = status_text
	_apply_chip_style(status_chip, status_color)
	var result_label := _result_label_for(lever_id)
	if result_label != null and not _last_results.has(lever_id):
		result_label.text = status_text
	if lever_id == LEVER_RATION_HARDENING:
		_update_ration_pulse(ration_active)

func _update_ration_pulse(active: bool) -> void:
	var ui: Dictionary = _lever_nodes.get(LEVER_RATION_HARDENING)
	var color_bar: ColorRect = ui.get("color_bar") as ColorRect if ui != null else null
	if not active or color_bar == null:
		if _ration_pulse_tween != null:
			_ration_pulse_tween.kill()
			_ration_pulse_tween = null
		if color_bar != null:
			color_bar.modulate = Color(1, 1, 1, 1)
		return
	if _ration_pulse_tween != null and _ration_pulse_tween.is_running():
		return
	_ration_pulse_tween = create_tween()
	_ration_pulse_tween.set_loops()
	_ration_pulse_tween.tween_property(color_bar, "modulate", Color(1, 1, 1, 0.7), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ration_pulse_tween.tween_property(color_bar, "modulate", Color(1, 1, 1, 1.0), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply_chip_style(chip: PanelContainer, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)

func _cleanup_sim_bridge() -> void:
	if _sim_bridge == null:
		return
	if not _sim_bridge.is_queued_for_deletion():
		_sim_bridge.queue_free()
	_sim_bridge = null

func _exit_tree() -> void:
	if _ration_pulse_tween != null:
		if _ration_pulse_tween.is_running():
			_ration_pulse_tween.kill()
		_ration_pulse_tween = null
	_cleanup_sim_bridge()

func _result_label_for(lever_id: String) -> Label:
	match lever_id:
		LEVER_RATION_HARDENING:
			return ration_result
		LEVER_LABOR_OVERDRIVE:
			return labor_result
		LEVER_EXPEDITION_COMPRESSION:
			return expedition_result
		LEVER_INFORMATION_THROTTLING:
			return info_result
		LEVER_MODULE_ABANDONMENT:
			return abandonment_result
		LEVER_EMERGENCY_CONVERSION:
			return conversion_result
	return null

func _read_sim_value(key: String) -> Variant:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		return null
	var sim := _sim_bridge.get_sim()
	if sim == null:
		return null
	if sim is Object:
		return sim.get(key)
	return null

func _conversion_burns() -> Dictionary:
	var raw_burns: Variant = _read_sim_value("conversion_burn_counts")
	if raw_burns is Dictionary:
		return raw_burns
	if raw_burns is Array:
		return Dictionary()
	return {}

func _selected_conversion_key() -> String:
	if conversion_from == null:
		return ""
	var text := conversion_from.get_item_text(conversion_from.selected)
	return text.split(" ")[0]
func _connect_pressure_signals() -> void:
	if not _input_controls_ready:
		return
	if ration_mode != null and not ration_mode.item_selected.is_connected(Callable(self, "_on_ration_mode_changed")):
		ration_mode.item_selected.connect(Callable(self, "_on_ration_mode_changed"))
	if labor_intensity != null:
		labor_intensity.value_changed.connect(Callable(self, "_on_pressure_spin_changed").bind(LEVER_LABOR_OVERDRIVE))
	if info_level != null:
		info_level.value_changed.connect(Callable(self, "_on_pressure_spin_changed").bind(LEVER_INFORMATION_THROTTLING))

func _on_pressure_spin_changed(_value: float, lever_id: String) -> void:
	_apply_lever_color(lever_id)

func _on_ration_mode_changed(_index: int) -> void:
	_apply_lever_color(LEVER_RATION_HARDENING)

func _refresh_lever_colors() -> void:
	for lever_id in _lever_nodes.keys():
		_apply_lever_color(lever_id)

func _apply_lever_color(lever_id: String) -> void:
	var ui: Dictionary = _lever_nodes.get(lever_id)
	if ui == null:
		return
	var title: Label = ui.get("title") as Label
	var intent: Label = ui.get("intent") as Label
	var button: Button = ui.get("apply") as Button
	var color_bar: ColorRect = ui.get("color_bar") as ColorRect
	if title == null or intent == null or button == null:
		return
	var base_color: Color = _calculate_lever_color(lever_id)
	title.add_theme_color_override("font_color", base_color)
	intent.add_theme_color_override("font_color", _muted_intent_color(base_color))
	button.modulate = _button_tint_color(base_color)
	button.add_theme_color_override("font_color", _button_text_color(base_color))
	if color_bar != null:
		color_bar.color = base_color
	var warning: Label = ui.get("warning") as Label
	if warning != null:
		if lever_id == LEVER_EMERGENCY_CONVERSION:
			warning.add_theme_color_override("font_color", COLOR_DESPERATION)
		elif lever_id == LEVER_MODULE_ABANDONMENT:
			warning.add_theme_color_override("font_color", COLOR_DANGER)
		else:
			warning.add_theme_color_override("font_color", COLOR_SCARCITY)

func _calculate_lever_color(lever_id: String) -> Color:
	var meta: Dictionary = LEVER_METADATA.get(lever_id, {})
	var category: String = str(meta.get("category", "neutral"))
	match category:
		"pressure":
			var intensity := _pressure_normalized_value(lever_id)
			return COLOR_SCARCITY.lerp(COLOR_DANGER, intensity)
		"expedition":
			return COLOR_AUTHORITY
		"conversion":
			return COLOR_DESPERATION
		_:
			return COLOR_NEUTRAL

func _pressure_normalized_value(lever_id: String) -> float:
	match lever_id:
		LEVER_RATION_HARDENING:
			if ration_mode == null:
				return 0.0
			var mode := ration_mode.get_item_text(ration_mode.selected).to_lower()
			return 1.0 if mode == "hard" else 0.2
		LEVER_LABOR_OVERDRIVE:
			if labor_intensity == null:
				return 0.0
			return _normalize_spinbox_value(labor_intensity.value)
		LEVER_INFORMATION_THROTTLING:
			if info_level == null:
				return 0.0
			return _normalize_spinbox_value(info_level.value)
		_:
			return 0.0

func _normalize_spinbox_value(value: float) -> float:
	return clamp((value - 1.0) / 4.0, 0.0, 1.0)

func _button_tint_color(base: Color) -> Color:
	return Color(0.08, 0.08, 0.08, 1.0).lerp(base, 0.45)

func _button_text_color(base: Color) -> Color:
	var brightness := (base.r + base.g + base.b) / 3.0
	return Color(1, 1, 1, 1) if brightness < 0.55 else Color(0.1, 0.1, 0.1, 1)

func _muted_intent_color(base: Color) -> Color:
	return base.lerp(Color(1, 1, 1, 1), 0.5)
func _apply_ration_hardening() -> void:
	if not _input_controls_ready:
		return
	var payload: Dictionary = {
		"mode": ration_mode.get_item_text(ration_mode.selected),
		"duration_hours": _variant_to_int(ration_duration.value),
	}
	_set_result(ration_result, _apply_lever(LEVER_RATION_HARDENING, payload), LEVER_RATION_HARDENING)

func _apply_labor_overdrive() -> void:
	if not _input_controls_ready:
		return
	var payload: Dictionary = {
		"intensity": _variant_to_int(labor_intensity.value),
		"duration_hours": _variant_to_int(labor_duration.value),
	}
	_set_result(labor_result, _apply_lever(LEVER_LABOR_OVERDRIVE, payload), LEVER_LABOR_OVERDRIVE)

func _apply_expedition_compression() -> void:
	if not _input_controls_ready:
		return
	var payload: Dictionary = {
		"intensity": _variant_to_int(expedition_intensity.value),
		"duration_hours": _variant_to_int(expedition_duration.value),
	}
	_set_result(expedition_result, _apply_lever(LEVER_EXPEDITION_COMPRESSION, payload), LEVER_EXPEDITION_COMPRESSION)

func _apply_information_throttling() -> void:
	if not _input_controls_ready:
		return
	var payload: Dictionary = {
		"level": _variant_to_int(info_level.value),
		"duration_hours": _variant_to_int(info_duration.value),
	}
	_set_result(info_result, _apply_lever(LEVER_INFORMATION_THROTTLING, payload), LEVER_INFORMATION_THROTTLING)

func _apply_module_abandonment() -> void:
	if not _input_controls_ready:
		return
	var payload: Dictionary = {
		"module_instance_id": abandonment_id.text.strip_edges(),
	}
	_set_result(abandonment_result, _apply_lever(LEVER_MODULE_ABANDONMENT, payload), LEVER_MODULE_ABANDONMENT)

func _apply_emergency_conversion() -> void:
	if not _input_controls_ready:
		return
	var payload: Dictionary = {
		"from": _selected_conversion_key(),
		"to": conversion_to.get_item_text(conversion_to.selected),
		"amount": _variant_to_int(conversion_amount.value),
	}
	_set_result(conversion_result, _apply_lever(LEVER_EMERGENCY_CONVERSION, payload), LEVER_EMERGENCY_CONVERSION)

func _apply_lever(lever_id: String, payload: Dictionary) -> bool:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		return false
	return _sim_bridge.apply_lever(lever_id, payload)

func _set_result(label: Label, ok: bool, lever_id: String) -> void:
	if label == null:
		return
	var result_text := ""
	if ok:
		match lever_id:
			LEVER_RATION_HARDENING, LEVER_LABOR_OVERDRIVE, LEVER_INFORMATION_THROTTLING, LEVER_EXPEDITION_COMPRESSION:
				if LEVER_HOURS_LEFT_KEYS.has(lever_id):
					var hours_left_value: Variant = _read_sim_value(str(LEVER_HOURS_LEFT_KEYS.get(lever_id)))
					var hours_left: int = _variant_to_int(hours_left_value)
					if hours_left > 0:
						result_text = "ACTIVE (%dh LEFT)" % hours_left
			LEVER_MODULE_ABANDONMENT:
				result_text = "DISABLED"
			LEVER_EMERGENCY_CONVERSION:
				result_text = "QUEUED"
	if result_text == "":
		result_text = _last_event_summary(lever_id)
	if result_text == "":
		result_text = "APPLIED" if ok else "REJECTED"
	label.text = result_text.to_upper()
	_last_results[lever_id] = result_text
	_refresh_lever_states()

func _last_event_summary(lever_id: String) -> String:
	if _sim_bridge == null or not _sim_bridge.has_events_value():
		return ""
	var events := _sim_bridge.get_events()
	for i in range(events.size() - 1, -1, -1):
		var entry: Variant = events[i]
		if entry is Dictionary and str(entry.get("lever_id", "")) == lever_id:
			var summary := str(entry.get("immediate_effects_summary", ""))
			if summary != "":
				return summary
			return str(entry.get("debts_applied", ""))
	return ""

func _build_tooltip(meta: Dictionary) -> String:
	var touches: String = ", ".join(meta.get("touches", []))
	if touches == "":
		touches = "systems unknown"
	var cost: String = str(meta.get("cost", "unknown")).to_upper()
	var reversibility: String = str(meta.get("reversibility", "reversible")).to_upper()
	var tooltip: String = "TOUCHES: %s\nCOST TYPE: %s\nREVERSIBILITY: %s" % [touches, cost, reversibility]
	if meta.has("note") and meta.get("note", "") != "":
		tooltip += "\nNOTE: %s" % meta.get("note")
	return tooltip
