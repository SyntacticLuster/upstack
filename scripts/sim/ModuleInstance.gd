extends RefCounted
class_name ModuleInstance

var def: ModuleDef
var powered: bool = false

func _init(_def: ModuleDef) -> void:
	def = _def
