extends RefCounted
class_name SystemCommandExecutor

const AgentCommandScript = preload("res://scripts/core/types/agent_command.gd")
const SystemEventScript = preload("res://scripts/core/types/system_event.gd")

var host


func _init(host_node = null) -> void:
	host = host_node

func execute_command_set(commands: Array[AgentCommand]) -> Array[SystemResult]:
	var results: Array[SystemResult] = []
	for command in commands:
		match command.type:
			AgentCommandScript.TYPE_MOVE_TO_LOCATION:
				results.append(execute_move_command(command))
			AgentCommandScript.TYPE_ACT:
				results.append(execute_act_command(command))
			AgentCommandScript.TYPE_SET_AUTO_EXPLORE_INTERVAL:
				results.append(execute_set_auto_explore_interval_command(command))
	return results


func execute_set_auto_explore_interval_command(command: AgentCommand) -> SystemResult:
	var requested_seconds: int = command.seconds
	var clamped_seconds: int = clampi(
		requested_seconds,
		host.auto_explore_interval_min_seconds,
		host.auto_explore_interval_max_seconds
	)
	var previous_seconds: int = host.auto_explore_interval_seconds
	host.auto_explore_interval_seconds = clamped_seconds
	host.append_log("[系统] 少女将自动探索间隔调整为 %d 秒。" % clamped_seconds)
	var result := SystemResult.make(SystemResult.TYPE_AUTO_EXPLORE_INTERVAL_SET, true, "已更新自动探索间隔")
	result.payload = {
		"seconds_before": previous_seconds,
		"seconds_after": clamped_seconds
	}
	return result


func execute_act_command(command: AgentCommand) -> SystemResult:
	if host.world_runtime.is_traveling():
		host.append_log("[系统] 少女正在移动中，当前不能执行对象交互。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "少女正在移动中")

	var target_id: String = command.target_id
	if target_id.is_empty() or not host.world_objects.has_object(target_id):
		host.append_log("[系统] act 指令缺少有效的目标对象。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "act 指令缺少有效的目标对象")

	if not host.world_objects.supports_action(target_id, command.action):
		host.append_log("[系统] 对象 %s 不支持动作 %s。" % [target_id, command.action])
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象不支持该动作")

	match command.action:
		AgentCommandScript.ACTION_INSPECT:
			return execute_inspect_action(target_id)
		AgentCommandScript.ACTION_PICK_UP:
			return execute_pick_up_action(target_id)
		AgentCommandScript.ACTION_USE:
			return execute_use_action(target_id)
		AgentCommandScript.ACTION_USE_ITEM:
			return execute_use_item_action(target_id, command.params)
		AgentCommandScript.ACTION_SET_VALUE:
			return execute_set_value_action(target_id, command.params)
		AgentCommandScript.ACTION_OPEN:
			return execute_open_action(target_id)
		_:
			host.append_log("[系统] 未知 act 动作：%s。" % command.action)
			return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "未知 act 动作")


func execute_inspect_action(target_id: String) -> SystemResult:
	var object_data: Dictionary = host.world_objects.get_object(target_id)
	if not can_access_object(target_id):
		host.append_log("[系统] 当前无法查看 %s，因为它不在少女可直接接触的范围内。" % str(object_data.get("name", target_id)))
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法查看该对象")

	var object_name: String = str(object_data.get("name", target_id))
	var summary: String = host.format_object_state_summary(object_data)
	var inspection_description: String = build_inspection_description(target_id, object_data)
	host.append_log("[系统] 少女检查了 %s。" % object_name)
	host.dispatch_system_event(SystemEventScript.make(
		SystemEventScript.TYPE_INSPECTION_RESULT,
		"少女刚刚检查了 %s。" % object_name,
		{
			"object_id": target_id,
			"object_name": object_name,
			"inspection_description": inspection_description,
			"visible_object": host.world_objects.get_visible_object(target_id),
			"state_summary": summary
		}
	))
	var result := SystemResult.make(SystemResult.TYPE_OBJECT_INSPECTED, true, "已检查对象")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_INSPECT
	result.payload = host.world_objects.get_visible_object(target_id)
	return result


func build_inspection_description(target_id: String, object_data: Dictionary) -> String:
	var object_name: String = str(object_data.get("name", target_id))
	var summary: String = host.format_object_state_summary(object_data)
	if target_id == "obj_backup_power_01":
		var power_state: Dictionary = object_data.get("state", {})
		var stored_power: int = int(power_state.get("stored_power", 0))
		var target_index: int = int(power_state.get("power_target_index", 0))
		return "我检查了一下 %s。这套后备电力系统在充满电之后，可以给某一个指定舱室的所有设备额外供电。面板上 0 号到 5 号按钮整齐地排成一排，但按钮上的舱室名称标签已经模糊不清了。现在亮着的是第 %d 号按钮上的指示灯，当前储能是 %d / 100。" % [
			object_name,
			target_index,
			stored_power
		]
	if summary.is_empty():
		return "我检查了一下 %s，目前没有看到新的数值变化。" % object_name
	return "我检查了一下 %s。当前可见状态：%s。" % [object_name, summary]


func execute_pick_up_action(target_id: String) -> SystemResult:
	var object_data: Dictionary = host.world_objects.get_object(target_id)
	var object_name: String = str(object_data.get("name", target_id))
	var current_holder: String = host.world_objects.get_holder(target_id)
	if current_holder != host.world_graph.current_location_id:
		host.append_log("[系统] 当前无法拾取 %s，因为它不在少女所在地点。" % object_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "对象不在当前地点")

	if not host.world_objects.move_object(target_id, "girl"):
		host.append_log("[系统] 拾取 %s 失败，系统未能更新其归属。" % object_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "拾取失败")

	host.append_log("[系统] 少女拾取了 %s，已加入她的物品栏。" % object_name)
	host.render_graph_data()
	var result := SystemResult.make(SystemResult.TYPE_ITEM_PICKED_UP, true, "已拾取物品")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_PICK_UP
	result.payload = host.world_objects.get_visible_object(target_id)
	return result


func execute_use_action(target_id: String) -> SystemResult:
	var object_data: Dictionary = host.world_objects.get_object(target_id)
	var object_name: String = str(object_data.get("name", target_id))
	if host.world_objects.get_holder(target_id) != "girl":
		host.append_log("[系统] 当前无法使用 %s，因为它不在少女的物品栏中。" % object_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "对象不在少女物品栏中")

	var object_type: String = str(object_data.get("type", ""))
	if object_type != "food":
		host.append_log("[系统] 已识别使用 %s 的请求，但当前只实现了 food 类型物品的直接使用。" % object_name)
		var not_implemented := SystemResult.make(SystemResult.TYPE_ACTION_NOT_IMPLEMENTED, false, "当前只实现了食物的直接使用")
		not_implemented.target_object_id = target_id
		not_implemented.action_name = AgentCommandScript.ACTION_USE
		return not_implemented

	var state: Dictionary = object_data.get("state", {})
	var energy: int = int(state.get("energy", 0))
	var previous_satiety: int = host.girl_satiety
	host.girl_satiety = clampi(host.girl_satiety + energy, 0, 100)
	host.world_objects.remove_object(target_id)
	host.render_graph_data()

	host.append_log("[系统] 少女食用了 %s，饱食度从 %d 提升到 %d。" % [object_name, previous_satiety, host.girl_satiety])

	var result := SystemResult.make(SystemResult.TYPE_ITEM_USED, true, "已使用物品")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_USE
	result.payload = {
		"consumed_item_name": object_name,
		"satiety_before": previous_satiety,
		"satiety_after": host.girl_satiety,
		"energy": energy
	}
	return result


func execute_use_item_action(target_id: String, params: Dictionary) -> SystemResult:
	var target_object: Dictionary = host.world_objects.get_object(target_id)
	var target_name: String = str(target_object.get("name", target_id))
	if not can_access_object(target_id):
		host.append_log("[系统] 当前无法对 %s 使用物品，因为它不在少女可直接操作的范围内。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法对该对象使用物品")

	var item_id: String = str(params.get("item_id", ""))
	if item_id.is_empty() or not host.world_objects.has_object(item_id):
		host.append_log("[系统] use_item 指令缺少有效的 item_id。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "use_item 指令缺少有效的 item_id")

	if host.world_objects.get_holder(item_id) != "girl":
		host.append_log("[系统] 当前无法使用该物品，因为它不在少女的物品栏中。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "物品不在少女物品栏中")

	var item_object: Dictionary = host.world_objects.get_object(item_id)
	var item_name: String = str(item_object.get("name", item_id))
	var item_type: String = str(item_object.get("type", ""))
	var target_type: String = str(target_object.get("type", ""))
	if item_type != "battery" or target_type != "device":
		host.append_log("[系统] 已识别将 %s 用于 %s 的请求，但当前只实现了 battery -> device 的 use_item 逻辑。" % [item_name, target_name])
		var not_implemented := SystemResult.make(SystemResult.TYPE_ACTION_NOT_IMPLEMENTED, false, "当前只实现了 battery -> device 的 use_item 逻辑")
		not_implemented.target_object_id = target_id
		not_implemented.action_name = AgentCommandScript.ACTION_USE_ITEM
		return not_implemented

	var target_state: Dictionary = target_object.get("state", {})
	if not target_state.has("stored_power"):
		host.append_log("[系统] %s 当前没有可充能的 stored_power 状态。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象没有可充能状态")

	var item_state: Dictionary = item_object.get("state", {})
	var charge: int = int(item_state.get("charge", 0))
	if charge <= 0:
		host.append_log("[系统] %s 当前没有可用电量。" % item_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "物品没有可用电量")

	var previous_power: int = int(target_state.get("stored_power", 0))
	var new_power: int = clampi(previous_power + charge, 0, 100)
	target_state["stored_power"] = new_power
	host.world_objects.set_object_state(target_id, target_state)
	host.world_objects.remove_object(item_id)
	host.render_graph_data()

	host.append_log("[系统] 少女将 %s 接入 %s，储能从 %d 提升到 %d。" % [item_name, target_name, previous_power, new_power])
	if target_id == "obj_backup_power_01" and new_power >= 100:
		host.append_log("[系统] 后备电力系统已充满，现在可以继续切换供电目标。")

	var result := SystemResult.make(SystemResult.TYPE_ITEM_APPLIED, true, "已将物品作用于目标对象")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_USE_ITEM
	result.payload = {
		"item_id": item_id,
		"item_name": item_name,
		"target_name": target_name,
		"stored_power_before": previous_power,
		"stored_power_after": new_power
	}
	return result


func execute_set_value_action(target_id: String, params: Dictionary) -> SystemResult:
	var target_object: Dictionary = host.world_objects.get_object(target_id)
	var target_name: String = str(target_object.get("name", target_id))
	if not can_access_object(target_id):
		host.append_log("[系统] 当前无法设置 %s，因为它不在少女可直接操作的范围内。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法设置该对象")

	var key: String = str(params.get("key", ""))
	if key.is_empty() or not params.has("value"):
		host.append_log("[系统] set_value 指令缺少 key 或 value。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "set_value 指令缺少 key 或 value")

	var target_type: String = str(target_object.get("type", ""))
	if target_type != "device":
		host.append_log("[系统] 当前只允许对 device 类型对象执行 set_value。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前只允许对设备设置数值")

	var target_state: Dictionary = target_object.get("state", {})
	if not target_state.has(key):
		host.append_log("[系统] %s 当前没有可设置的状态键 %s。" % [target_name, key])
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象没有该状态键")

	if target_id == "obj_backup_power_01":
		return execute_backup_power_set_value(target_id, target_name, key, params.get("value"))

	host.append_log("[系统] 已识别对 %s 执行 set_value，但当前只实现了后备电力系统的切换逻辑。" % target_name)
	var not_implemented := SystemResult.make(SystemResult.TYPE_ACTION_NOT_IMPLEMENTED, false, "当前只实现了后备电力系统的 set_value 逻辑")
	not_implemented.target_object_id = target_id
	not_implemented.action_name = AgentCommandScript.ACTION_SET_VALUE
	return not_implemented


func execute_backup_power_set_value(target_id: String, target_name: String, key: String, raw_value: Variant) -> SystemResult:
	if key != "power_target_index":
		host.append_log("[系统] 后备电力系统当前只允许设置 power_target_index。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "后备电力系统当前只允许设置 power_target_index")

	var target_state: Dictionary = host.world_objects.get_object(target_id).get("state", {})
	var stored_power: int = int(target_state.get("stored_power", 0))
	if stored_power < 100:
		host.append_log("[系统] 后备电力系统储能不足，当前为 %d，必须达到 100 才能切换供电目标。" % stored_power)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "后备电力系统储能不足")

	var value: int = int(raw_value)
	if value < 0 or value > 5:
		host.append_log("[系统] power_target_index 超出允许范围，当前只接受 0 到 5。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "power_target_index 超出允许范围")

	var previous_value: int = int(target_state.get("power_target_index", 0))
	target_state["power_target_index"] = value
	host.world_objects.set_object_state(target_id, target_state)
	update_airlock_power_state(value == 4)
	host.render_graph_data()

	host.append_log("[系统] 少女将 %s 的供电目标从 %d 切换为 %d。" % [target_name, previous_value, value])
	if value == 4:
		host.append_log("[系统] 舱门系统已恢复供电。")
	else:
		host.append_log("[系统] 当前供电目标不是舱门系统，舱门仍未恢复供电。")

	var result := SystemResult.make(SystemResult.TYPE_VALUE_SET, true, "已更新设备状态值")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_SET_VALUE
	result.payload = {
		"key": key,
		"value_before": previous_value,
		"value_after": value,
		"airlock_powered": value == 4
	}
	return result


func update_airlock_power_state(powered: bool) -> void:
	if powered:
		if not host.unlocked_requirements.has("airlock_power"):
			host.unlocked_requirements.append("airlock_power")
	else:
		host.unlocked_requirements.erase("airlock_power")

	var airlock_door: Dictionary = host.world_objects.get_object("obj_airlock_door_01")
	if not airlock_door.is_empty():
		var airlock_door_state: Dictionary = airlock_door.get("state", {})
		airlock_door_state["powered"] = powered
		host.world_objects.set_object_state("obj_airlock_door_01", airlock_door_state)

	var airlock_panel: Dictionary = host.world_objects.get_object("obj_airlock_panel_01")
	if not airlock_panel.is_empty():
		var airlock_panel_state: Dictionary = airlock_panel.get("state", {})
		airlock_panel_state["powered"] = powered
		host.world_objects.set_object_state("obj_airlock_panel_01", airlock_panel_state)


func execute_open_action(target_id: String) -> SystemResult:
	var target_object: Dictionary = host.world_objects.get_object(target_id)
	var target_name: String = str(target_object.get("name", target_id))
	if not can_access_object(target_id):
		host.append_log("[系统] 当前无法开启 %s，因为它不在少女可直接操作的范围内。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法开启该对象")

	var target_type: String = str(target_object.get("type", ""))
	if target_type != "door":
		host.append_log("[系统] 当前只允许对 door 类型对象执行 open。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前只允许对门执行开启操作")

	var target_state: Dictionary = target_object.get("state", {})
	var is_powered: bool = bool(target_state.get("powered", false))
	var is_opened: bool = bool(target_state.get("opened", false))
	if is_opened:
		host.append_log("[系统] %s 已经处于开启状态。" % target_name)
		var already_opened := SystemResult.make(SystemResult.TYPE_OBJECT_OPENED, true, "对象已经处于开启状态")
		already_opened.target_object_id = target_id
		already_opened.action_name = AgentCommandScript.ACTION_OPEN
		already_opened.payload = host.world_objects.get_visible_object(target_id)
		return already_opened

	if not is_powered:
		host.append_log("[系统] %s 当前没有供电，无法开启。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象当前没有供电")

	target_state["opened"] = true
	host.world_objects.set_object_state(target_id, target_state)
	host.render_graph_data()

	host.append_log("[系统] %s 已成功开启。" % target_name)
	if target_id == "obj_airlock_door_01":
		host.objective_label.text = "目标：穿过舱门离开飞船，开始对外部环境进行探索。"
		host.system_agent_short_term_goal = "穿过已经开启的舱门，确认飞船外部环境是否安全。"
		host.system_recent_dialogue_summary = "少女成功开启了舱门，正在准备离开飞船。"

	var result := SystemResult.make(SystemResult.TYPE_OBJECT_OPENED, true, "对象已开启")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_OPEN
	result.payload = host.world_objects.get_visible_object(target_id)
	return result


func can_access_object(target_id: String) -> bool:
	var holder_id: String = host.world_objects.get_holder(target_id)
	return holder_id == host.world_graph.current_location_id or holder_id == "girl"


func execute_move_command(command: AgentCommand) -> SystemResult:
	if host.world_runtime.is_traveling():
		host.append_log("[系统] 少女已经在路上了，这条移动指令暂时不能执行。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "少女已经在路上了")

	var target_location_id: String = command.target_location_id
	var target_location_name: String = command.target_location_name
	if target_location_id.is_empty():
		host.append_log("[系统] 移动指令缺少目标地点。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "移动指令缺少目标地点")

	host.system_agent_desired_location_ids.erase(target_location_id)
	host.system_agent_desired_location_ids.append(target_location_id)
	host.system_agent_short_term_goal = "前往 %s 并调查是否存在新的线索" % target_location_name

	var path: Array[String] = host.world_graph.find_path(host.world_graph.current_location_id, target_location_id, host.unlocked_requirements)
	if path.is_empty():
		host.append_log("[系统] 已收到前往 %s 的请求，但当前没有满足条件的可行路径。" % target_location_name)
		var rejected := SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前找不到满足条件的路径")
		rejected.target_location_id = target_location_id
		return rejected

	if path.size() == 1:
		host.append_log("[系统] 少女已经位于 %s。" % target_location_name)
		host.system_agent_desired_location_ids.erase(target_location_id)
		host.set_investigation_goal(target_location_id)
		var already := SystemResult.make(SystemResult.TYPE_ALREADY_AT_TARGET, true, "已经位于目标地点")
		already.target_location_id = target_location_id
		return already

	host.planned_route = path.duplicate()
	host.selected_location_id = target_location_id
	var next_leg_id: String = path[1]
	var next_connection: Dictionary = host.world_graph.get_connection(host.world_graph.current_location_id, next_leg_id)
	var named_path: Array[String] = []
	for location_id in path:
		named_path.append(str(host.world_graph.get_location(location_id).get("name", location_id)))
	host.append_log("[系统] 已为 %s 规划路径：%s。" % [target_location_name, " -> ".join(named_path)])
	host.append_log("[系统] 第一段路线方向：%s，目的地：%s。" % [
		next_connection.get("direction_label", "未知"),
		host.world_graph.get_location(next_leg_id).get("name", next_leg_id)
	])
	host.world_runtime.start_travel_leg(next_leg_id)
	var result := SystemResult.make(SystemResult.TYPE_MOVEMENT_STARTED, true, "开始沿规划路径移动")
	result.target_location_id = target_location_id
	result.path = path.duplicate()
	result.from_location_id = host.world_graph.current_location_id
	result.to_location_id = next_leg_id
	result.direction_label = str(next_connection.get("direction_label", ""))
	result.travel_time_seconds = host.world_graph.get_travel_time(host.world_graph.current_location_id, next_leg_id) * 60
	return result
