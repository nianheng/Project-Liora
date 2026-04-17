extends RefCounted
class_name AgentOutput

const PROTOCOL_VERSION := "agent_output.v1"

var protocol_version: String = PROTOCOL_VERSION
var reply_text: String = ""
var commands: Array[AgentCommand] = []


func add_command(command: AgentCommand) -> void:
	commands.append(command)
