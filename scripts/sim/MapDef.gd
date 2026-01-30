extends RefCounted
class_name MapDef

## Map data model for expeditions.
## Contains static location definitions and provides lookup methods.
## Locations are deterministic and do not regenerate.

class LocationDef extends RefCounted:
	var id: String = ""
	var name: String = ""
	var distance_hours: int = 0  # One-way travel time in hours.
	var onsite_hours: int = 0    # Time spent at location.
	var risk_level: int = 0      # 0=safe, 1=low, 2=medium, 3=high.
	var resources: Dictionary = {}  # Available yields: {"food": 30, "materials": 50, ...}.
	var position: Vector2 = Vector2.ZERO  # Visual map position (0-1 normalized).
	var connected_to: Array[String] = []  # Location IDs this connects to (for visual edges).

	func _init(
		_id: String = "",
		_name: String = "",
		_distance_hours: int = 4,
		_onsite_hours: int = 2,
		_risk_level: int = 1,
		_resources: Dictionary = {},
		_position: Vector2 = Vector2.ZERO,
		_connected_to: Array[String] = []
	) -> void:
		id = _id
		name = _name
		distance_hours = max(_distance_hours, 1)
		onsite_hours = max(_onsite_hours, 1)
		risk_level = clamp(_risk_level, 0, 3)
		resources = _resources.duplicate(true)
		position = _position
		connected_to = _connected_to.duplicate()

	func total_trip_hours() -> int:
		# Round trip: travel out + onsite + travel back.
		return (distance_hours * 2) + onsite_hours

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"distance_hours": distance_hours,
			"onsite_hours": onsite_hours,
			"risk_level": risk_level,
			"resources": resources.duplicate(true),
			"position": {"x": position.x, "y": position.y},
			"connected_to": connected_to.duplicate(),
		}


# Default location definitions (3-6 as required).
const DEFAULT_LOCATIONS: Array[Dictionary] = [
	{
		"id": "scrapyard",
		"name": "Abandoned Scrapyard",
		"distance_hours": 4,
		"onsite_hours": 3,
		"risk_level": 1,
		"resources": {"materials": 60, "food": 10},
		"position": Vector2(0.3, 0.2),
		"connected_to": ["tower", "reservoir"],
	},
	{
		"id": "reservoir",
		"name": "Old Reservoir",
		"distance_hours": 6,
		"onsite_hours": 2,
		"risk_level": 1,
		"resources": {"water": 80, "materials": 15},
		"position": Vector2(0.7, 0.25),
		"connected_to": ["tower", "scrapyard", "greenhouse"],
	},
	{
		"id": "greenhouse",
		"name": "Collapsed Greenhouse",
		"distance_hours": 8,
		"onsite_hours": 4,
		"risk_level": 2,
		"resources": {"food": 70, "water": 20},
		"position": Vector2(0.8, 0.55),
		"connected_to": ["reservoir", "bunker"],
	},
	{
		"id": "bunker",
		"name": "Sealed Bunker",
		"distance_hours": 12,
		"onsite_hours": 6,
		"risk_level": 3,
		"resources": {"materials": 100, "food": 40, "water": 30},
		"position": Vector2(0.5, 0.8),
		"connected_to": ["greenhouse", "outpost"],
	},
	{
		"id": "outpost",
		"name": "Remote Outpost",
		"distance_hours": 10,
		"onsite_hours": 3,
		"risk_level": 2,
		"resources": {"materials": 45, "food": 25},
		"position": Vector2(0.2, 0.7),
		"connected_to": ["bunker", "tower"],
	},
]

# The tower (home base) is always present as origin.
const TOWER_LOCATION: Dictionary = {
	"id": "tower",
	"name": "The Tower",
	"distance_hours": 0,
	"onsite_hours": 0,
	"risk_level": 0,
	"resources": {},
	"position": Vector2(0.5, 0.4),
	"connected_to": ["scrapyard", "reservoir", "outpost"],
}

var _locations: Dictionary = {}  # id -> LocationDef


func _init() -> void:
	_build_default_map()


func _build_default_map() -> void:
	_locations.clear()
	# Add tower first.
	_locations["tower"] = _dict_to_location(TOWER_LOCATION)
	# Add all default expedition targets.
	for loc_data in DEFAULT_LOCATIONS:
		var loc := _dict_to_location(loc_data)
		_locations[loc.id] = loc


func _dict_to_location(data: Dictionary) -> LocationDef:
	var pos_data: Variant = data.get("position", Vector2.ZERO)
	var pos: Vector2 = Vector2.ZERO
	if pos_data is Vector2:
		pos = pos_data
	elif pos_data is Dictionary:
		pos = Vector2(float(pos_data.get("x", 0.0)), float(pos_data.get("y", 0.0)))

	var connected_raw: Variant = data.get("connected_to", [])
	var connected: Array[String] = []
	if connected_raw is Array:
		for item in connected_raw:
			connected.append(str(item))

	return LocationDef.new(
		str(data.get("id", "")),
		str(data.get("name", "")),
		int(data.get("distance_hours", 4)),
		int(data.get("onsite_hours", 2)),
		int(data.get("risk_level", 1)),
		data.get("resources", {}) if data.get("resources") is Dictionary else {},
		pos,
		connected
	)


func get_locations() -> Array[LocationDef]:
	var result: Array[LocationDef] = []
	var keys := _locations.keys()
	keys.sort()
	for key in keys:
		var loc: Variant = _locations.get(key)
		if loc is LocationDef:
			result.append(loc)
	return result


func get_expedition_destinations() -> Array[LocationDef]:
	## Returns all locations except the tower (valid expedition targets).
	var result: Array[LocationDef] = []
	var keys := _locations.keys()
	keys.sort()
	for key in keys:
		if key == "tower":
			continue
		var loc: Variant = _locations.get(key)
		if loc is LocationDef:
			result.append(loc)
	return result


func get_location(location_id: String) -> LocationDef:
	var loc: Variant = _locations.get(location_id, null)
	if loc is LocationDef:
		return loc
	return null


func has_location(location_id: String) -> bool:
	return _locations.has(location_id)


func is_valid_destination(location_id: String) -> bool:
	## Returns true if location_id is a valid expedition target (exists and is not tower).
	if location_id == "tower":
		return false
	return _locations.has(location_id)


func get_edges() -> Array[Dictionary]:
	## Returns all unique edges for visual map rendering.
	## Each edge is {"from": id, "to": id}.
	var seen: Dictionary = {}
	var edges: Array[Dictionary] = []
	var keys := _locations.keys()
	keys.sort()
	for key in keys:
		var loc: Variant = _locations.get(key)
		if not (loc is LocationDef):
			continue
		for target_id in loc.connected_to:
			var edge_key := _edge_key(key, target_id)
			if seen.has(edge_key):
				continue
			seen[edge_key] = true
			edges.append({"from": key, "to": target_id})
	return edges


func _edge_key(a: String, b: String) -> String:
	if a < b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]
