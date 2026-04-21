extends RefCounted
class_name WorldObjects

var _objects: Dictionary = {}


func load_from_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldObjects could not open file: %s" % path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("WorldObjects invalid JSON in: %s" % path)
		return
	load_from_array(parsed as Array)


func load_from_array(entries: Array) -> void:
	_objects.clear()
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var instance_id := str(entry.get("instance_id", ""))
		if instance_id.is_empty():
			continue
		_objects[instance_id] = entry.duplicate(true)


func get_object(instance_id: String) -> Dictionary:
	if not _objects.has(instance_id):
		return {}
	return (_objects[instance_id] as Dictionary).duplicate(true)


func has_object(instance_id: String) -> bool:
	return _objects.has(instance_id)


func get_holder(instance_id: String) -> String:
	if not _objects.has(instance_id):
		return ""
	return str((_objects[instance_id] as Dictionary).get("holder", ""))


func supports_action(instance_id: String, action_name: String) -> bool:
	if not _objects.has(instance_id):
		return false
	var object_data: Dictionary = _objects[instance_id]
	var actions: Array = object_data.get("actions", [])
	return actions.has(action_name)


func get_objects_by_holder(holder_id: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for instance_id in _objects.keys():
		var object_data: Dictionary = _objects[instance_id]
		if str(object_data.get("holder", "")) == holder_id:
			results.append(object_data.duplicate(true))
	_sort_objects_by_name(results)
	return results


func get_location_objects(location_id: String) -> Array[Dictionary]:
	return get_objects_by_holder(location_id)


func get_inventory_objects() -> Array[Dictionary]:
	return get_objects_by_holder("girl")


func get_pickable_objects_in_location(location_id: String) -> Array[Dictionary]:
	return _filter_objects_by_action(get_location_objects(location_id), "pick_up")


func get_interactable_objects_in_location(location_id: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for object_data in get_location_objects(location_id):
		var actions: Array = object_data.get("actions", [])
		if actions.is_empty():
			continue
		if not actions.has("pick_up"):
			results.append(object_data)
	return results


func move_object(instance_id: String, new_holder: String) -> bool:
	if not _objects.has(instance_id):
		return false
	var object_data: Dictionary = _objects[instance_id]
	object_data["holder"] = new_holder
	_objects[instance_id] = object_data
	return true


func remove_object(instance_id: String) -> bool:
	if not _objects.has(instance_id):
		return false
	_objects.erase(instance_id)
	return true


func set_object_state(instance_id: String, state: Dictionary) -> bool:
	if not _objects.has(instance_id):
		return false
	var object_data: Dictionary = _objects[instance_id]
	object_data["state"] = state.duplicate(true)
	_objects[instance_id] = object_data
	return true


func get_visible_object(instance_id: String) -> Dictionary:
	var object_data: Dictionary = get_object(instance_id)
	if object_data.is_empty():
		return {}
	return {
		"id": str(object_data.get("instance_id", "")),
		"name": str(object_data.get("name", "")),
		"type": str(object_data.get("type", "")),
		"description": str(object_data.get("description", "")),
		"actions": (object_data.get("actions", []) as Array).duplicate(),
		"state": (object_data.get("state", {}) as Dictionary).duplicate(true)
	}


func _filter_objects_by_action(objects: Array[Dictionary], action_name: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for object_data in objects:
		var actions: Array = object_data.get("actions", [])
		if actions.has(action_name):
			results.append(object_data)
	return results


func _sort_objects_by_name(objects: Array[Dictionary]) -> void:
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
