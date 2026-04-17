extends RefCounted
class_name AgentCommand

const TYPE_MOVE_TO_LOCATION := "move_to_location"

var type: String = ""
var target_location_id: String = ""
var target_location_name: String = ""


static func move_to_location(location_id: String, location_name: String) -> AgentCommand:
	var command := AgentCommand.new()
	command.type = TYPE_MOVE_TO_LOCATION
	command.target_location_id = location_id
	command.target_location_name = location_name
	return command
