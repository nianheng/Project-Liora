extends RefCounted
class_name AgentAdapter


func get_adapter_name() -> String:
	return "base"


func process_player_message(message: String, context, world_graph: WorldGraph):
	push_error("process_player_message must be implemented by adapter subclasses")
	return AgentOutput.new()


func process_system_event(event, context, world_graph: WorldGraph):
	return AgentOutput.new()
