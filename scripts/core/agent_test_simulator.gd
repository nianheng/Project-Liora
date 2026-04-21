extends AgentAdapter
class_name AgentTestSimulator

const AgentCommandScript = preload("res://scripts/core/types/agent_command.gd")


func get_adapter_name() -> String:
	return "test"


func process_player_message(message: String, context, world_graph: WorldGraph):
	var target_location: Dictionary = _find_location_in_message(message, world_graph)
	var output = AgentOutput.new()

	if target_location.is_empty():
		output.reply_text = "收到，我先留意附近状况，有发现再告诉你。"
		return output

	var target_id: String = str(target_location.get("id", ""))
	var target_name: String = str(target_location.get("name", "未知地点"))
	var next_desired_ids: Array[String] = context.desired_location_ids.duplicate()
	next_desired_ids.erase(target_id)
	next_desired_ids.append(target_id)

	output.reply_text = "好啊，我也觉得%s那边可能会有线索。" % target_name
	output.add_command(AgentCommandScript.move_to_location(target_id, target_name))
	return output


func process_system_event(event, context, world_graph: WorldGraph):
	var output = AgentOutput.new()
	var target_location: Dictionary = _choose_exploration_target(context, world_graph)
	match str(event.event_type):
		SystemEvent.TYPE_ARRIVED_AT_LOCATION:
			var location_name: String = str(event.payload.get("location_name", context.current_location_name))
			if target_location.is_empty():
				output.reply_text = "I have arrived at %s. Let me inspect the area first." % location_name
				return output
			var target_id: String = str(target_location.get("id", ""))
			var target_name: String = str(target_location.get("name", "unknown"))
			output.reply_text = "I have arrived at %s. %s seems worth checking next." % [location_name, target_name]
			output.add_command(AgentCommandScript.move_to_location(target_id, target_name))
			return output
		SystemEvent.TYPE_EXPLORATION_IDLE:
			if target_location.is_empty():
				output.reply_text = "Nothing urgent stands out yet, so I will keep observing nearby."
				return output
			var idle_target_id: String = str(target_location.get("id", ""))
			var idle_target_name: String = str(target_location.get("name", "unknown"))
			output.reply_text = "It has been quiet for a while. I want to move toward %s and keep exploring." % idle_target_name
			output.add_command(AgentCommandScript.move_to_location(idle_target_id, idle_target_name))
			return output
		SystemEvent.TYPE_INSPECTION_RESULT:
			var inspected_name: String = str(event.payload.get("object_name", "这个东西"))
			output.reply_text = "我已经仔细检查过 %s 了，这会帮助我判断下一步该怎么做。" % inspected_name
			return output
	return output


func _find_location_in_message(message: String, world_graph: WorldGraph) -> Dictionary:
	for location in world_graph.get_locations():
		var location_name: String = str(location.get("name", ""))
		if not location_name.is_empty() and message.find(location_name) != -1:
			return location
	return {}


func _choose_exploration_target(context, world_graph: WorldGraph) -> Dictionary:
	for desired_id in context.desired_location_ids:
		if desired_id == context.current_location_id:
			continue
		for route in context.visible_routes:
			if str(route.get("to_location_id", "")) != desired_id:
				continue
			if not bool(route.get("allowed", false)):
				continue
			return world_graph.get_location(desired_id)

	for route in context.visible_routes:
		if not bool(route.get("allowed", false)):
			continue
		var route_location_id: String = str(route.get("to_location_id", ""))
		var route_location: Dictionary = world_graph.get_location(route_location_id)
		if route_location.is_empty():
			continue
		if not bool(route_location.get("visited", false)):
			return route_location

	for route in context.visible_routes:
		if not bool(route.get("allowed", false)):
			continue
		var fallback_id: String = str(route.get("to_location_id", ""))
		return world_graph.get_location(fallback_id)

	return {}
