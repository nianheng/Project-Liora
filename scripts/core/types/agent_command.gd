extends RefCounted
class_name AgentCommand

const TYPE_MOVE_TO_LOCATION := "move_to_location"
const TYPE_ACT := "act"
const TYPE_SET_AUTO_EXPLORE_INTERVAL := "set_auto_explore_interval"

const ACTION_INSPECT := "inspect"
const ACTION_PICK_UP := "pick_up"
const ACTION_USE := "use"
const ACTION_USE_ITEM := "use_item"
const ACTION_SET_VALUE := "set_value"
const ACTION_OPEN := "open"

var type: String = ""
var target_location_id: String = ""
var target_location_name: String = ""
var target_id: String = ""
var action: String = ""
var params: Dictionary = {}
var seconds: int = 0


static func move_to_location(location_id: String, location_name: String) -> AgentCommand:
	var command := AgentCommand.new()
	command.type = TYPE_MOVE_TO_LOCATION
	command.target_location_id = location_id
	command.target_location_name = location_name
	return command


static func act(target_object_id: String, action_name: String, action_params: Dictionary = {}) -> AgentCommand:
	var command := AgentCommand.new()
	command.type = TYPE_ACT
	command.target_id = target_object_id
	command.action = action_name
	command.params = action_params.duplicate(true)
	return command


static func inspect(target_object_id: String) -> AgentCommand:
	return act(target_object_id, ACTION_INSPECT)


static func pick_up(target_object_id: String) -> AgentCommand:
	return act(target_object_id, ACTION_PICK_UP)


static func use(target_object_id: String) -> AgentCommand:
	return act(target_object_id, ACTION_USE)


static func use_item(target_object_id: String, item_id: String) -> AgentCommand:
	return act(target_object_id, ACTION_USE_ITEM, {"item_id": item_id})


static func set_value(target_object_id: String, key: String, value: Variant) -> AgentCommand:
	return act(target_object_id, ACTION_SET_VALUE, {"key": key, "value": value})


static func open(target_object_id: String) -> AgentCommand:
	return act(target_object_id, ACTION_OPEN)


static func set_auto_explore_interval(interval_seconds: int) -> AgentCommand:
	var command := AgentCommand.new()
	command.type = TYPE_SET_AUTO_EXPLORE_INTERVAL
	command.seconds = interval_seconds
	return command
