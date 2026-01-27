extends PanelContainer

@onready var ration_mode: OptionButton = $VBox/RationHardening/Mode
@onready var ration_duration: SpinBox = $VBox/RationHardening/Duration
@onready var ration_apply: Button = $VBox/RationHardening/Apply
@onready var ration_result: Label = $VBox/RationHardening/Result

@onready var labor_intensity: SpinBox = $VBox/LaborOverdrive/Intensity
@onready var labor_duration: SpinBox = $VBox/LaborOverdrive/Duration
@onready var labor_apply: Button = $VBox/LaborOverdrive/Apply
@onready var labor_result: Label = $VBox/LaborOverdrive/Result

@onready var expedition_intensity: SpinBox = $VBox/ExpeditionCompression/Intensity
@onready var expedition_duration: SpinBox = $VBox/ExpeditionCompression/Duration
@onready var expedition_apply: Button = $VBox/ExpeditionCompression/Apply
@onready var expedition_result: Label = $VBox/ExpeditionCompression/Result

@onready var info_level: SpinBox = $VBox/InformationThrottling/Level
@onready var info_duration: SpinBox = $VBox/InformationThrottling/Duration
@onready var info_apply: Button = $VBox/InformationThrottling/Apply
@onready var info_result: Label = $VBox/InformationThrottling/Result

@onready var abandonment_id: LineEdit = $VBox/ModuleAbandonment/ModuleId
@onready var abandonment_apply: Button = $VBox/ModuleAbandonment/Apply
@onready var abandonment_result: Label = $VBox/ModuleAbandonment/Result

@onready var conversion_from: OptionButton = $VBox/EmergencyConversion/From
@onready var conversion_to: OptionButton = $VBox/EmergencyConversion/To
@onready var conversion_amount: SpinBox = $VBox/EmergencyConversion/Amount
@onready var conversion_apply: Button = $VBox/EmergencyConversion/Apply
@onready var conversion_result: Label = $VBox/EmergencyConversion/Result

var _sim_bridge: SimBridge = null

const LEVER_RATION_HARDENING := "RATION_HARDENING"
const LEVER_LABOR_OVERDRIVE := "LABOR_OVERDRIVE"
const LEVER_EXPEDITION_COMPRESSION := "EXPEDITION_COMPRESSION"
const LEVER_INFORMATION_THROTTLING := "INFORMATION_THROTTLING"
const LEVER_MODULE_ABANDONMENT := "MODULE_ABANDONMENT"
const LEVER_EMERGENCY_CONVERSION := "EMERGENCY_CONVERSION"

func set_sim(sim_ref: Object) -> void:
	if _sim_bridge == null:
		_sim_bridge = SimBridge.new()
	_sim_bridge.set_sim(sim_ref)

func _ready() -> void:
	_setup_inputs()
	_bind_buttons()

func _setup_inputs() -> void:
	ration_mode.clear()
	ration_mode.add_item("soft")
	ration_mode.add_item("hard")
	ration_mode.select(0)
	ration_duration.min_value = 1
	ration_duration.max_value = 365
	ration_duration.step = 1
	ration_duration.value = 1

	labor_intensity.min_value = 1
	labor_intensity.max_value = 5
	labor_intensity.step = 1
	labor_intensity.value = 1
	labor_duration.min_value = 1
	labor_duration.max_value = 365
	labor_duration.step = 1
	labor_duration.value = 1

	expedition_intensity.min_value = 1
	expedition_intensity.max_value = 5
	expedition_intensity.step = 1
	expedition_intensity.value = 1
	expedition_duration.min_value = 1
	expedition_duration.max_value = 365
	expedition_duration.step = 1
	expedition_duration.value = 1

	info_level.min_value = 1
	info_level.max_value = 5
	info_level.step = 1
	info_level.value = 1
	info_duration.min_value = 1
	info_duration.max_value = 365
	info_duration.step = 1
	info_duration.value = 1

	conversion_from.clear()
	conversion_to.clear()
	for key in ["food", "water", "materials", "morale"]:
		conversion_from.add_item(key)
		conversion_to.add_item(key)
	conversion_from.select(0)
	conversion_to.select(1)
	conversion_amount.min_value = 1
	conversion_amount.max_value = 999
	conversion_amount.step = 1
	conversion_amount.value = 1

func _bind_buttons() -> void:
	ration_apply.pressed.connect(_apply_ration_hardening)
	labor_apply.pressed.connect(_apply_labor_overdrive)
	expedition_apply.pressed.connect(_apply_expedition_compression)
	info_apply.pressed.connect(_apply_information_throttling)
	abandonment_apply.pressed.connect(_apply_module_abandonment)
	conversion_apply.pressed.connect(_apply_emergency_conversion)

func _apply_ration_hardening() -> void:
	var payload := {
		"mode": ration_mode.get_item_text(ration_mode.selected),
		"duration_days": int(ration_duration.value),
	}
	_set_result(ration_result, _apply_lever(LEVER_RATION_HARDENING, payload))

func _apply_labor_overdrive() -> void:
	var payload := {
		"intensity": int(labor_intensity.value),
		"duration_days": int(labor_duration.value),
	}
	_set_result(labor_result, _apply_lever(LEVER_LABOR_OVERDRIVE, payload))

func _apply_expedition_compression() -> void:
	var payload := {
		"intensity": int(expedition_intensity.value),
		"duration_days": int(expedition_duration.value),
	}
	_set_result(expedition_result, _apply_lever(LEVER_EXPEDITION_COMPRESSION, payload))

func _apply_information_throttling() -> void:
	var payload := {
		"level": int(info_level.value),
		"duration_days": int(info_duration.value),
	}
	_set_result(info_result, _apply_lever(LEVER_INFORMATION_THROTTLING, payload))

func _apply_module_abandonment() -> void:
	var payload := {
		"module_instance_id": abandonment_id.text.strip_edges(),
	}
	_set_result(abandonment_result, _apply_lever(LEVER_MODULE_ABANDONMENT, payload))

func _apply_emergency_conversion() -> void:
	var payload := {
		"from": conversion_from.get_item_text(conversion_from.selected),
		"to": conversion_to.get_item_text(conversion_to.selected),
		"amount": int(conversion_amount.value),
	}
	_set_result(conversion_result, _apply_lever(LEVER_EMERGENCY_CONVERSION, payload))

func _apply_lever(lever_id: String, payload: Dictionary) -> bool:
	if _sim_bridge == null or not _sim_bridge.has_sim():
		return false
	return _sim_bridge.apply_lever(lever_id, payload)

func _set_result(label: Label, ok: bool) -> void:
	label.text = "applied" if ok else "rejected"
