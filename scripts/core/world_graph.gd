extends RefCounted
class_name WorldGraph

const VALID_DIRECTIONS := {
	"N": "北",
	"NE": "东北",
	"E": "东",
	"SE": "东南",
	"S": "南",
	"SW": "西南",
	"W": "西",
	"NW": "西北"
}

var meta: Dictionary = {}
var current_location_id := ""
var _locations: Dictionary = {}
var _connections: Array[Dictionary] = []
var _outgoing: Dictionary = {}


func load_from_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldGraph could not open file: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldGraph invalid JSON in: %s" % path)
		return
	load_from_dictionary(parsed)


func load_from_dictionary(data: Dictionary) -> void:
	meta = data.get("meta", {})
	current_location_id = str(meta.get("starting_location_id", ""))
	_locations.clear()
	_connections.clear()
	_outgoing.clear()

	for location_variant in data.get("locations", []):
		var location := location_variant as Dictionary
		var location_id := str(location.get("id", ""))
		if not location_id.is_empty():
			_locations[location_id] = location.duplicate(true)

	for connection_variant in data.get("connections", []):
		var connection := connection_variant as Dictionary
		var direction := str(connection.get("direction", "")).to_upper()
		var from_id := str(connection.get("from", ""))
		var to_id := str(connection.get("to", ""))
		if not VALID_DIRECTIONS.has(direction):
			continue
		if not _locations.has(from_id) or not _locations.has(to_id):
			continue

		var normalized := connection.duplicate(true)
		normalized["direction"] = direction
		_connections.append(normalized)
		if not _outgoing.has(from_id):
			_outgoing[from_id] = []
		var outgoing_for_location: Array = _outgoing[from_id]
		outgoing_for_location.append(normalized)


func get_location_ids() -> Array[String]:
	var ids: Array[String] = []
	for location_id in _locations.keys():
		ids.append(location_id)
	return ids


func get_locations() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for location_id in get_location_ids():
		results.append(get_location(location_id))
	return results


func get_location(location_id: String) -> Dictionary:
	if not _locations.has(location_id):
		return {}
	return (_locations[location_id] as Dictionary).duplicate(true)


func get_location_by_name(location_name: String) -> Dictionary:
	for location_id in _locations.keys():
		var location: Dictionary = _locations[location_id]
		if str(location.get("name", "")) == location_name:
			return location.duplicate(true)
	return {}


func get_current_location() -> Dictionary:
	return get_location(current_location_id)


func set_current_location(location_id: String) -> void:
	if _locations.has(location_id):
		current_location_id = location_id
		mark_visited(location_id)


func mark_visited(location_id: String) -> void:
	if not _locations.has(location_id):
		return
	var location: Dictionary = _locations[location_id]
	location["visited"] = true
	_locations[location_id] = location


func get_neighbors(location_id: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for connection_variant in _outgoing.get(location_id, []):
		var connection := connection_variant as Dictionary
		var destination_id := str(connection.get("to", ""))
		var location := get_location(destination_id)
		results.append({
			"connection_id": str(connection.get("id", "")),
			"to_id": destination_id,
			"to_name": str(location.get("name", destination_id)),
			"direction": str(connection.get("direction", "")),
			"direction_label": VALID_DIRECTIONS.get(str(connection.get("direction", "")), ""),
			"travel_time": int(connection.get("travel_time", 0)),
			"requirements": connection.get("requirements", []),
			"destination_requirements": location.get("entry_requirements", []),
			"destination_visited": bool(location.get("visited", false))
		})
	return results


func get_connection(from_id: String, to_id: String) -> Dictionary:
	for neighbor in get_neighbors(from_id):
		if str(neighbor.get("to_id", "")) == to_id:
			return neighbor
	return {}


func get_travel_time(from_id: String, to_id: String) -> int:
	return int(get_connection(from_id, to_id).get("travel_time", -1))


func find_path(from_id: String, to_id: String, unlocked_requirements: Array[String] = []) -> Array[String]:
	if from_id == to_id and _locations.has(from_id):
		return [from_id]
	if not _locations.has(from_id) or not _locations.has(to_id):
		return []

	var frontier: Array[String] = [from_id]
	var visited: Dictionary = {from_id: true}
	var previous: Dictionary = {}

	while not frontier.is_empty():
		var current_id: String = frontier.pop_front()
		if current_id == to_id:
			break

		var neighbors: Array[Dictionary] = get_neighbors(current_id)
		for neighbor in neighbors:
			var neighbor_id: String = str(neighbor.get("to_id", ""))
			if visited.has(neighbor_id):
				continue

			var travel_result: Dictionary = can_travel(current_id, neighbor_id, unlocked_requirements)
			if not bool(travel_result.get("allowed", false)):
				continue

			visited[neighbor_id] = true
			previous[neighbor_id] = current_id
			frontier.append(neighbor_id)

	if not visited.has(to_id):
		return []

	var reversed_path: Array[String] = [to_id]
	var cursor: String = to_id
	while previous.has(cursor):
		cursor = str(previous[cursor])
		reversed_path.append(cursor)

	reversed_path.reverse()
	return reversed_path


func can_travel(from_id: String, to_id: String, unlocked_requirements: Array[String] = []) -> Dictionary:
	var connection := get_connection(from_id, to_id)
	if connection.is_empty():
		return {"allowed": false, "reasons": ["没有这条路线"]}

	var missing: Array[String] = []
	for requirement_variant in connection.get("requirements", []):
		var requirement := str(requirement_variant)
		if not unlocked_requirements.has(requirement):
			missing.append(requirement)

	for requirement_variant in connection.get("destination_requirements", []):
		var requirement := str(requirement_variant)
		if not unlocked_requirements.has(requirement) and not missing.has(requirement):
			missing.append(requirement)

	return {"allowed": missing.is_empty(), "reasons": missing}


func count_visited_locations() -> int:
	var total := 0
	for location_id in _locations.keys():
		if bool((_locations[location_id] as Dictionary).get("visited", false)):
			total += 1
	return total


func get_connection_count() -> int:
	return _connections.size()
