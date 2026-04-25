extends RefCounted
class_name WorldRuntime

const SystemEventScript = preload("res://scripts/core/types/system_event.gd")

var host


func _init(host_node = null) -> void:
	host = host_node


func is_traveling() -> bool:
	return host.agent_state == "MOVING" and not host.travel_destination_id.is_empty()


func finish_travel() -> void:
	host.world_graph.set_current_location(host.travel_destination_id)
	host.selected_location_id = host.world_graph.current_location_id
	host.agent_state = "EXPLORING"
	host.append_log("[系统] 移动完成，少女已抵达 %s。" % host.world_graph.get_current_location().get("name", "未知地点"))
	if not host.planned_route.is_empty():
		host.planned_route.remove_at(0)
	if host.planned_route.size() > 1:
		var next_leg_id: String = host.planned_route[1]
		host.append_log("[系统] 已规划后续路段，继续前往 %s。" % host.world_graph.get_location(next_leg_id).get("name", "未知地点"))
		start_travel_leg(next_leg_id)
		return
	host.system_agent_desired_location_ids.erase(host.world_graph.current_location_id)
	host.set_investigation_goal(host.world_graph.current_location_id)
	host.travel_origin_id = ""
	host.travel_destination_id = ""
	host.travel_remaining_seconds = 0
	host.active_travel_connection = {}
	host.planned_route.clear()
	host.render_graph_data()
	var arrival_event := SystemEventScript.make(
		SystemEventScript.TYPE_ARRIVED_AT_LOCATION,
		"已抵达 %s，现在可以开始观察周围环境。" % str(host.world_graph.get_current_location().get("name", host.world_graph.current_location_id)),
		{
			"location_id": host.world_graph.current_location_id,
			"location_name": str(host.world_graph.get_current_location().get("name", host.world_graph.current_location_id))
		}
	)
	host.dispatch_system_event(arrival_event)


func start_travel_leg(next_location_id: String) -> void:
	var origin_id: String = host.world_graph.current_location_id
	var travel_time: int = host.world_graph.get_travel_time(origin_id, next_location_id)
	host.travel_origin_id = origin_id
	host.travel_destination_id = next_location_id
	host.travel_remaining_seconds = travel_time * 60
	host.active_travel_connection = host.world_graph.get_connection(origin_id, next_location_id)
	host.agent_state = "MOVING"
	host.render_graph_data()


func advance_world_time(delta_seconds: int, emit_log: bool = false) -> void:
	host.world_time_seconds += delta_seconds
	host.time_label.text = host.format_clock(host.world_time_seconds)
	host.satiety_decay_accumulator_seconds += delta_seconds
	var satiety_changed := false
	while host.satiety_decay_accumulator_seconds >= 60:
		host.satiety_decay_accumulator_seconds -= 60
		var next_satiety: int = maxi(host.girl_satiety - 1, 0)
		if next_satiety == host.girl_satiety:
			continue
		host.girl_satiety = next_satiety
		satiety_changed = true
	if satiety_changed:
		host.render_character_status()
	if is_traveling():
		host.travel_remaining_seconds -= delta_seconds
		host.seconds_since_last_agent_exchange = 0
		host.render_location_detail()
		host.render_clues()
		if host.travel_remaining_seconds <= 0:
			finish_travel()
		elif emit_log:
			host.append_log("[系统] 时间推进 %d 秒，少女仍在前往 %s 的路上，还需要 %s。" % [
				delta_seconds,
				host.world_graph.get_location(host.travel_destination_id).get("name", "未知地点"),
				host.format_duration(host.travel_remaining_seconds)
			])
			host.render_graph_data()
	else:
		if host.agent_request_in_flight:
			return
		if host.agent_state == "EXPLORING":
			host.seconds_since_last_agent_exchange += delta_seconds
			if host.seconds_since_last_agent_exchange >= host.auto_explore_interval_seconds:
				var idle_event := SystemEventScript.make(
					SystemEventScript.TYPE_EXPLORATION_IDLE,
					"少女已自主探索一段时间，准备继续推进当前行动。",
					{
						"elapsed_seconds": host.seconds_since_last_agent_exchange,
						"location_id": host.world_graph.current_location_id,
						"location_name": str(host.world_graph.get_current_location().get("name", host.world_graph.current_location_id))
					}
				)
				host.dispatch_system_event(idle_event)
		elif host.agent_state != "MOVING":
			host.seconds_since_last_agent_exchange = 0
		if not emit_log:
			return
		if emit_log:
			pass
		host.append_log("[系统] 时间推进 %d 秒，少女继续保持自主探索。" % delta_seconds)
