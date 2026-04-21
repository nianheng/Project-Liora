extends RefCounted
class_name AgentAdapter


func get_adapter_name() -> String:
	return "base"


func is_async() -> bool:
	return false


func process_player_message(message: String, context, world_graph: WorldGraph):
	push_error("process_player_message must be implemented by adapter subclasses")
	return AgentOutput.new()


func process_system_event(event, context, world_graph: WorldGraph):
	return AgentOutput.new()


func process_player_message_async(host: Node, message: String, context, world_graph: WorldGraph):
	return process_player_message(message, context, world_graph)


func process_system_event_async(host: Node, event, context, world_graph: WorldGraph):
	return process_system_event(event, context, world_graph)
