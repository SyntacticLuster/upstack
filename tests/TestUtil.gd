extends Node
class_name TestUtil

static func stable_json(value: Variant) -> String:
	var kind: int = typeof(value)
	if kind == TYPE_DICTIONARY:
		var result: Array = []
		var dict: Dictionary = value
		var keys: Array = dict.keys()
		keys.sort()
		for key in keys:
			var entry: Variant = dict[key]
			result.append("%s:%s" % [JSON.stringify(key), stable_json(entry)])
		return "{%s}" % ",".join(result)
	if kind == TYPE_ARRAY:
		var array: Array = value
		var items: Array = []
		for element in array:
			items.append(stable_json(element))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)

static func ensure_dir(path: String) -> bool:
	if path == "":
		return true
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute_path):
		return true
	if path.begins_with("user://"):
		var relative_path: String = path.substr("user://".length())
		relative_path = relative_path.strip_prefix("/")
		var user_dir := DirAccess.open("user://")
		if user_dir == null:
			return false
		if relative_path == "":
			user_dir.close()
			return true
		var err := user_dir.make_dir_recursive(relative_path)
		user_dir.close()
		return err == OK
	return DirAccess.make_dir_recursive_absolute(absolute_path) == OK

static func write_json(path: String, value: Variant) -> bool:
	var dir: String = path.get_base_dir()
	if dir != "" and not ensure_dir(dir):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(stable_json(value))
	file.close()
	return true
