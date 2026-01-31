extends RefCounted
class_name ScenarioLoader

## Loads and validates scenario JSON files.

const REQUIRED_KEYS: Array[String] = ["actions"]
const VALID_ACTION_TYPES: Array[String] = [
	"advance_hours",
	"advance_days",
	"trade",
	"expedition",
	"lever",
	"set_rations",
	"wait_expedition_resolve",
	"assert",
	"snapshot",
	"comment",
]


func load_scenario(path: String) -> Dictionary:
	var result: Dictionary = {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["error"] = "Cannot open file: %s" % path
		return result

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(content)
	if parse_result != OK:
		result["error"] = "JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return result

	var data: Variant = json.data
	if not data is Dictionary:
		result["error"] = "Scenario root must be a Dictionary"
		return result

	var scenario: Dictionary = data as Dictionary

	# Validate required keys.
	for key in REQUIRED_KEYS:
		if not scenario.has(key):
			result["error"] = "Missing required key: %s" % key
			return result

	# Validate actions array.
	var actions: Variant = scenario.get("actions")
	if not actions is Array:
		result["error"] = "actions must be an Array"
		return result

	var actions_array: Array = actions as Array
	var validation_error := _validate_actions(actions_array)
	if validation_error != "":
		result["error"] = validation_error
		return result

	return scenario


func _validate_actions(actions: Array) -> String:
	for i in range(actions.size()):
		var action: Variant = actions[i]
		if not action is Dictionary:
			return "Action at index %d is not a Dictionary" % i

		var action_dict: Dictionary = action as Dictionary
		if not action_dict.has("type"):
			return "Action at index %d missing 'type'" % i

		var action_type := str(action_dict.get("type", ""))
		if not VALID_ACTION_TYPES.has(action_type):
			return "Action at index %d has invalid type: %s" % [i, action_type]

		var field_error := _validate_action_fields(i, action_type, action_dict)
		if field_error != "":
			return field_error

	return ""


func _validate_action_fields(index: int, action_type: String, action: Dictionary) -> String:
	match action_type:
		"advance_hours":
			if not action.has("hours"):
				return "Action %d (advance_hours) missing 'hours'" % index
			if not _is_positive_int(action.get("hours")):
				return "Action %d (advance_hours) 'hours' must be positive int" % index

		"advance_days":
			if not action.has("days"):
				return "Action %d (advance_days) missing 'days'" % index
			if not _is_positive_int(action.get("days")):
				return "Action %d (advance_days) 'days' must be positive int" % index

		"trade":
			if not action.has("direction"):
				return "Action %d (trade) missing 'direction'" % index
			if not action.has("resource"):
				return "Action %d (trade) missing 'resource'" % index
			if not action.has("amount"):
				return "Action %d (trade) missing 'amount'" % index
			var direction := str(action.get("direction", "")).to_lower()
			if direction != "buy" and direction != "sell":
				return "Action %d (trade) 'direction' must be 'buy' or 'sell'" % index

		"expedition":
			if not action.has("destination_id"):
				return "Action %d (expedition) missing 'destination_id'" % index
			if not action.has("crew"):
				return "Action %d (expedition) missing 'crew'" % index
			if not _is_positive_int(action.get("crew")):
				return "Action %d (expedition) 'crew' must be positive int" % index

		"lever":
			if not action.has("lever_id"):
				return "Action %d (lever) missing 'lever_id'" % index
			if not action.has("payload"):
				return "Action %d (lever) missing 'payload'" % index

		"set_rations":
			if not action.has("food_ration") and not action.has("water_ration"):
				return "Action %d (set_rations) must have 'food_ration' or 'water_ration'" % index

		"wait_expedition_resolve":
			if not action.has("timeout_hours"):
				return "Action %d (wait_expedition_resolve) missing 'timeout_hours'" % index

		"assert":
			if not action.has("condition"):
				return "Action %d (assert) missing 'condition'" % index
			if not action.has("message"):
				return "Action %d (assert) missing 'message'" % index

		"snapshot":
			if not action.has("label"):
				return "Action %d (snapshot) missing 'label'" % index

		"comment":
			pass  # No required fields.

	return ""


func _is_positive_int(value: Variant) -> bool:
	if value is int:
		return int(value) > 0
	if value is float:
		return int(value) > 0
	return false
