extends Control

const WorldGraph = preload("res://scripts/core/world_graph.gd")
const AgentFactory = preload("res://scripts/core/agent_factory.gd")
const AgentRuntimeConfig = preload("res://scripts/core/agent_runtime_config.gd")
const AgentContextScript = preload("res://scripts/core/types/agent_context.gd")
const AgentCommandScript = preload("res://scripts/core/types/agent_command.gd")
const SystemEventScript = preload("res://scripts/core/types/system_event.gd")

const BG := Color("07111f")
const PANEL := Color("10243a")
const PANEL_ALT := Color("16324c")
const PANEL_MUTED := Color("0c1a2c")
const ACCENT := Color("69e2ff")
const ACCENT_WARM := Color("f4c16f")
const TEXT := Color("ecf7ff")
const TEXT_SOFT := Color("8ea7be")
const ALERT := Color("ff8d74")
const AUTO_EXPLORE_INTERVAL_SECONDS := 300

var world_time_seconds: int = 22 * 3600 + 14 * 60
var paused := false
var world_graph := WorldGraph.new()
var current_agent = null
var system_agent_desired_location_ids: Array[String] = []
var system_agent_short_term_goal: String = "保持通讯稳定并继续调查周边区域"
var system_recent_dialogue_summary: String = "玩家与少女刚建立稳定联系，正在共同规划探索方向。"
var selected_location_id := ""
var unlocked_requirements: Array[String] = ["light_source"]
var agent_state: String = "EXPLORING"
var travel_origin_id: String = ""
var travel_destination_id: String = ""
var travel_remaining_seconds: int = 0
var active_travel_connection: Dictionary = {}
var planned_route: Array[String] = []
var seconds_since_last_agent_exchange: int = 0
var world_timer: Timer

var time_label: Label
var status_label: Label
var location_label: Label
var objective_label: Label
var map_summary_label: Label
var map_list: ItemList
var route_list: ItemList
var clue_list: ItemList
var comms_log: RichTextLabel
var input_box: LineEdit
var pause_overlay: ColorRect
var pause_label: Label
var detail_title_label: Label
var detail_description_label: Label
var detail_meta_label: Label


func _ready() -> void:
	world_graph.load_from_file("res://data/world/graph_demo.json")
	current_agent = AgentFactory.create_agent()
	selected_location_id = world_graph.current_location_id
	build_ui()
	setup_world_timer()
	render_graph_data()
	append_boot_log()
	set_process_unhandled_input(true)


func build_ui() -> void:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_color", "TextEdit", TEXT)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", BG)
	theme.set_color("guide_color", "Separator", TEXT_SOFT)
	theme.set_constant("separation", "BoxContainer", 16)
	theme.set_stylebox("panel", "PanelContainer", make_panel_style(PANEL, 18, Color("264b68")))
	theme.set_stylebox("normal", "Button", make_panel_style(PANEL_ALT, 12, ACCENT))
	theme.set_stylebox("hover", "Button", make_panel_style(Color("1c4467"), 12, ACCENT))
	theme.set_stylebox("pressed", "Button", make_panel_style(Color("132f48"), 12, ACCENT_WARM))
	theme.set_stylebox("normal", "TextEdit", make_panel_style(PANEL_MUTED, 12, Color("284761")))
	theme.set_stylebox("focus", "TextEdit", make_panel_style(PANEL_MUTED, 12, ACCENT))
	theme.set_stylebox("normal", "LineEdit", make_panel_style(PANEL_MUTED, 12, Color("284761")))
	theme.set_stylebox("focus", "LineEdit", make_panel_style(PANEL_MUTED, 12, ACCENT))
	theme.set_stylebox("panel", "ItemList", make_panel_style(PANEL_MUTED, 12, Color("284761")))
	theme.set_stylebox("normal", "RichTextLabel", make_panel_style(PANEL_MUTED, 12, Color("284761")))
	theme.set_stylebox("normal", "ScrollContainer", StyleBoxEmpty.new())
	self.theme = theme

	var background := ColorRect.new()
	background.color = BG
	background.layout_mode = 1
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	add_child(background)

	var root_margin := MarginContainer.new()
	root_margin.layout_mode = 1
	root_margin.anchor_right = 1.0
	root_margin.anchor_bottom = 1.0
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_top", 20)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_bottom", 20)
	add_child(root_margin)

	var root := VBoxContainer.new()
	root_margin.add_child(root)

	root.add_child(build_header())

	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 520
	root.add_child(main_split)

	main_split.add_child(build_left_column())
	main_split.add_child(build_right_column())

	pause_overlay = build_pause_overlay()
	add_child(pause_overlay)


func setup_world_timer() -> void:
	world_timer = Timer.new()
	world_timer.wait_time = 1.0
	world_timer.one_shot = false
	world_timer.autostart = true
	world_timer.timeout.connect(_on_world_tick)
	add_child(world_timer)


func build_header() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 92)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 20)
	header_margin.add_theme_constant_override("margin_top", 14)
	header_margin.add_theme_constant_override("margin_right", 20)
	header_margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(header_margin)

	var row := HBoxContainer.new()
	header_margin.add_child(row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_box)

	var title := Label.new()
	title.text = "Signal Archive // Planetfall"
	title.add_theme_font_size_override("font_size", 30)
	title_box.add_child(title)

	objective_label = Label.new()
	objective_label.text = "目标: 建立一条可验证的探索闭环。"
	objective_label.modulate = TEXT_SOFT
	title_box.add_child(objective_label)

	var info_row := HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(info_row)

	time_label = make_chip("22:14:00")
	info_row.add_child(time_label)

	status_label = make_chip("少女状态: EXPLORING")
	info_row.add_child(status_label)

	location_label = make_chip("当前位置: --")
	info_row.add_child(location_label)

	var pause_button := Button.new()
	pause_button.text = "暂停"
	pause_button.pressed.connect(toggle_pause)
	info_row.add_child(pause_button)

	return panel


func build_left_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var comms_panel := PanelContainer.new()
	comms_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(comms_panel)

	var comms_margin := MarginContainer.new()
	comms_margin.add_theme_constant_override("margin_left", 18)
	comms_margin.add_theme_constant_override("margin_top", 18)
	comms_margin.add_theme_constant_override("margin_right", 18)
	comms_margin.add_theme_constant_override("margin_bottom", 18)
	comms_panel.add_child(comms_margin)

	var comms_column := VBoxContainer.new()
	comms_margin.add_child(comms_column)

	comms_column.add_child(make_section_title("通讯终端", "后续这里将承接玩家输入、少女回复和系统注入消息。"))

	comms_log = RichTextLabel.new()
	comms_log.bbcode_enabled = true
	comms_log.fit_content = false
	comms_log.scroll_following = true
	comms_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comms_log.custom_minimum_size = Vector2(0, 320)
	comms_column.add_child(comms_log)

	var quick_row := HBoxContainer.new()
	comms_column.add_child(quick_row)

	for text in ["继续前进", "停下观察", "描述周围", "回传照片"]:
		var button := Button.new()
		button.text = text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_quick_action.bind(text))
		quick_row.add_child(button)

	var input_label := Label.new()
	input_label.text = "发送指令"
	input_label.modulate = TEXT_SOFT
	comms_column.add_child(input_label)

	input_box = LineEdit.new()
	input_box.custom_minimum_size = Vector2(0, 42)
	input_box.placeholder_text = "输入你要发送给少女或系统的内容，例如：别急着进塔，先拍一下门锁。"
	input_box.text_submitted.connect(_on_send_submitted)
	comms_column.add_child(input_box)

	var send_row := HBoxContainer.new()
	comms_column.add_child(send_row)

	var send_button := Button.new()
	send_button.text = "发送消息"
	send_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_button.pressed.connect(_on_send_pressed)
	send_row.add_child(send_button)

	var system_button := Button.new()
	system_button.text = "调试 +10秒"
	system_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_button.pressed.connect(_on_debug_advance_time)
	send_row.add_child(system_button)

	return column


func build_right_column() -> Control:
	var outer := VSplitContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.split_offset = 300

	outer.add_child(build_map_panel())
	outer.add_child(build_right_lower_area())

	return outer


func build_map_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 260)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(make_section_title("地图与动线", "左侧列表展示全部地点，右侧路线列表展示当前点的有向连边、方向与耗时。"))

	map_summary_label = Label.new()
	map_summary_label.modulate = TEXT_SOFT
	column.add_child(map_summary_label)

	map_list = ItemList.new()
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_list.custom_minimum_size = Vector2(0, 130)
	map_list.item_selected.connect(_on_map_location_selected)
	column.add_child(map_list)

	var route_title := Label.new()
	route_title.text = "当前可见路线"
	route_title.modulate = TEXT_SOFT
	column.add_child(route_title)

	route_list = ItemList.new()
	route_list.custom_minimum_size = Vector2(0, 90)
	route_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	route_list.item_selected.connect(_on_route_selected)
	column.add_child(route_list)

	var travel_row := HBoxContainer.new()
	column.add_child(travel_row)

	var move_button := Button.new()
	move_button.text = "移动到选中地点"
	move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_button.pressed.connect(_on_move_pressed)
	travel_row.add_child(move_button)

	var scan_button := Button.new()
	scan_button.text = "刷新路线判定"
	scan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan_button.pressed.connect(render_graph_data)
	travel_row.add_child(scan_button)

	return panel


func build_right_lower_area() -> Control:
	var lower := VSplitContainer.new()
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.split_offset = 210

	var middle_row := HSplitContainer.new()
	middle_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_row.split_offset = 300
	middle_row.add_child(build_character_panel())
	middle_row.add_child(build_location_detail_panel())
	lower.add_child(middle_row)

	var bottom_row := HSplitContainer.new()
	bottom_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_row.split_offset = 300
	bottom_row.add_child(build_clue_panel())
	bottom_row.add_child(build_media_panel())
	lower.add_child(bottom_row)

	return lower


func build_character_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 150)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(make_section_title("人物状态", "顶部显示主状态，这里承接体力、情绪、信任、信号等详细信息。"))
	column.add_child(make_meter("体力", 0.68, ACCENT))
	column.add_child(make_meter("情绪", 0.56, ACCENT_WARM))
	column.add_child(make_meter("信任", 0.74, Color("98f5a2")))
	column.add_child(make_meter("信号", 0.41, ALERT))

	return panel


func build_location_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 150)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(make_section_title("当前地点详情", "这里由地图数据直接驱动，用来承接描述、探索状态、进入条件和交互对象。"))

	detail_title_label = Label.new()
	detail_title_label.add_theme_font_size_override("font_size", 22)
	detail_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail_title_label)

	detail_meta_label = Label.new()
	detail_meta_label.modulate = TEXT_SOFT
	detail_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail_meta_label)

	detail_description_label = Label.new()
	detail_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(detail_description_label)

	return panel


func build_clue_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 180)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(make_section_title("线索与道具", "当前选中地点的线索、道具与机关会统一展示在这里。"))

	clue_list = ItemList.new()
	clue_list.custom_minimum_size = Vector2(0, 140)
	clue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(clue_list)

	return panel


func build_media_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 180)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(make_section_title("图像与远程操作", "后续可接照片回传、扫描图、远程门锁、电源与暂停菜单。"))

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 110)
	frame.add_theme_stylebox_override("panel", make_panel_style(Color("09121d"), 16, Color("1d526d")))
	column.add_child(frame)

	var center := CenterContainer.new()
	frame.add_child(center)

	var placeholder := Label.new()
	placeholder.text = "Image Feed Placeholder\n现场截图 / 扫描图 / 机关照片"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.modulate = TEXT_SOFT
	center.add_child(placeholder)

	var action_row := HBoxContainer.new()
	column.add_child(action_row)

	for text in ["请求新照片", "查看暂停菜单", "打开系统日志"]:
		var button := Button.new()
		button.text = text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if text == "查看暂停菜单":
			button.pressed.connect(toggle_pause)
		action_row.add_child(button)

	return panel


func build_pause_overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.03, 0.06, 0.86)
	overlay.layout_mode = 1
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.visible = false

	var center := CenterContainer.new()
	center.layout_mode = 1
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 280)
	panel.add_theme_stylebox_override("panel", make_panel_style(PANEL, 22, ACCENT))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var title := Label.new()
	title.text = "暂停中"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	pause_label = Label.new()
	pause_label.text = "这里后续可以放设置、存档、任务日志和系统说明。"
	pause_label.modulate = TEXT_SOFT
	pause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(pause_label)

	for text in ["继续", "保存占位", "设置占位"]:
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(0, 42)
		if text == "继续":
			button.pressed.connect(toggle_pause)
		column.add_child(button)

	return overlay


func render_graph_data() -> void:
	render_header()
	render_map_list()
	render_route_list()
	render_location_detail()
	render_clues()


func render_header() -> void:
	var current_location: Dictionary = world_graph.get_current_location()
	time_label.text = format_clock(world_time_seconds)
	status_label.text = "少女状态: %s" % agent_state
	if is_traveling():
		var from_name: String = str(world_graph.get_location(travel_origin_id).get("name", "--"))
		var to_name: String = str(world_graph.get_location(travel_destination_id).get("name", "--"))
		location_label.text = "当前位置: %s → %s" % [from_name, to_name]
	else:
		location_label.text = "当前位置: %s" % current_location.get("name", "--")
	map_summary_label.text = "地点 %d 个 | 已探索 %d 个 | 已解锁条件: %s" % [
		world_graph.get_location_ids().size(),
		world_graph.count_visited_locations(),
		", ".join(unlocked_requirements)
	]


func render_map_list() -> void:
	map_list.clear()
	var ids: Array[String] = world_graph.get_location_ids()
	for index in range(ids.size()):
		var location: Dictionary = world_graph.get_location(ids[index])
		var marker: String = "●" if str(location.get("id", "")) == world_graph.current_location_id else "○"
		var visited_text: String = "已探索" if bool(location.get("visited", false)) else "未探索"
		var label: String = "%s %s | %s" % [marker, location.get("name", ""), visited_text]
		map_list.add_item(label)
		if str(location.get("id", "")) == selected_location_id:
			map_list.select(index)


func render_route_list() -> void:
	route_list.clear()
	if is_traveling():
		var route_text: String = "%s %s → %s | 全程 %d 分钟 | 剩余 %s" % [
			active_travel_connection.get("direction_label", ""),
			world_graph.get_location(travel_origin_id).get("name", "--"),
			world_graph.get_location(travel_destination_id).get("name", "--"),
			int(active_travel_connection.get("travel_time", 0)),
			format_duration(travel_remaining_seconds)
		]
		route_list.add_item(route_text)
		return
	for neighbor in world_graph.get_neighbors(world_graph.current_location_id):
		var travel_result: Dictionary = world_graph.can_travel(world_graph.current_location_id, str(neighbor.get("to_id", "")), unlocked_requirements)
		var status: String = "可通行" if bool(travel_result.get("allowed", false)) else "缺少: %s" % ", ".join(travel_result.get("reasons", []))
		var visited_tag: String = "已探索" if bool(neighbor.get("destination_visited", false)) else "未探索"
		var text: String = "%s %s | %s 分钟 | %s | %s" % [
			neighbor.get("direction_label", ""),
			neighbor.get("to_name", ""),
			neighbor.get("travel_time", 0),
			visited_tag,
			status
		]
		route_list.add_item(text)


func render_location_detail() -> void:
	if is_traveling():
		var from_location: Dictionary = world_graph.get_location(travel_origin_id)
		var to_location: Dictionary = world_graph.get_location(travel_destination_id)
		detail_title_label.text = "道路上"
		detail_meta_label.text = "状态: MOVING | 方向: %s | 剩余: %s" % [
			active_travel_connection.get("direction_label", ""),
			format_duration(travel_remaining_seconds)
		]
		detail_description_label.text = "少女正在从 %s 前往 %s。她暂时不属于任何单一地点，因此地图路线与地点详情都切换为道路状态，直到移动时间耗尽。" % [
			from_location.get("name", "--"),
			to_location.get("name", "--")
		]
		return
	var location: Dictionary = world_graph.get_location(selected_location_id)
	if location.is_empty():
		return

	detail_title_label.text = str(location.get("name", "未知地点"))
	var requirements: Array = location.get("entry_requirements", [])
	var requirement_text: String = "无" if requirements.is_empty() else ", ".join(requirements)
	detail_meta_label.text = "ID: %s | 探索状态: %s | 进入条件: %s" % [
		location.get("id", ""),
		"已探索" if bool(location.get("visited", false)) else "未探索",
		requirement_text
	]
	detail_description_label.text = str(location.get("description", ""))


func render_clues() -> void:
	clue_list.clear()
	if is_traveling():
		clue_list.add_item("道路 | 起点 | %s" % world_graph.get_location(travel_origin_id).get("name", "--"))
		clue_list.add_item("道路 | 终点 | %s" % world_graph.get_location(travel_destination_id).get("name", "--"))
		clue_list.add_item("道路 | 方向 | %s" % active_travel_connection.get("direction_label", ""))
		clue_list.add_item("道路 | 剩余时间 | %s" % format_duration(travel_remaining_seconds))
		var travel_requirements: Array = active_travel_connection.get("requirements", [])
		var travel_requirement_text: String = "无" if travel_requirements.is_empty() else ", ".join(travel_requirements)
		clue_list.add_item("道路 | 通行条件 | %s" % travel_requirement_text)
		return
	var location: Dictionary = world_graph.get_location(selected_location_id)
	if location.is_empty():
		return

	for clue in location.get("clues", []):
		clue_list.add_item("线索 | %s" % clue)
	for item in location.get("items", []):
		clue_list.add_item("道具 | %s" % item)
	for puzzle in location.get("puzzles", []):
		clue_list.add_item("机关 | %s" % puzzle)
	for interactive in location.get("interactive_objects", []):
		clue_list.add_item("交互 | %s" % interactive)


func append_boot_log() -> void:
	append_log("[系统] 图结构地图已加载，当前地点是 %s。" % world_graph.get_current_location().get("name", "未知地点"))
	append_log("[系统] 当前地图包含 %d 个地点和 %d 条有向连边。" % [world_graph.get_location_ids().size(), world_graph.get_connection_count()])
	append_log("[系统] 当前短期目标：%s。" % system_agent_short_term_goal)
	append_log("[系统] 当前 Agent 模式：%s。" % current_agent.get_adapter_name())
	if AgentRuntimeConfig.is_llm_mode():
		append_log("[系统] LLM adapter scaffold 已启用，当前项目已经具备测试代理 / 真 Agent 可切换结构。")
	else:
		append_log("[系统] 测试代理已启用。只要你在消息里提到地点名，它就会输出移动指令。")
	append_log("[少女] 我已经把附近能走的路线整理出来了，你可以看右侧路线面板。")


func make_section_title(title_text: String, subtitle_text: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.modulate = TEXT_SOFT
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.max_lines_visible = 2
	subtitle.clip_text = true
	column.add_child(subtitle)

	var separator := HSeparator.new()
	column.add_child(separator)

	return column


func make_chip(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", BG)
	label.add_theme_stylebox_override("normal", make_panel_style(ACCENT, 999, ACCENT))
	return label


func make_meter(label_text: String, value: float, tint: Color) -> Control:
	var column := VBoxContainer.new()

	var row := HBoxContainer.new()
	column.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value_label := Label.new()
	value_label.text = str(int(value * 100)) + "%"
	value_label.modulate = TEXT_SOFT
	row.add_child(value_label)

	var bar := ProgressBar.new()
	bar.value = value * 100.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.modulate = tint
	bar.custom_minimum_size = Vector2(0, 16)
	column.add_child(bar)

	return column


func make_panel_style(fill: Color, radius: int, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8
	return style


func append_log(message: String) -> void:
	if comms_log.text.is_empty():
		comms_log.text = message
	else:
		comms_log.text += "\n\n" + message


func format_clock(total_seconds: int) -> String:
	var normalized: int = posmod(total_seconds, 24 * 3600)
	var hours: int = normalized / 3600
	var minutes: int = (normalized % 3600) / 60
	var seconds: int = normalized % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


func format_duration(total_seconds: int) -> String:
	var clamped: int = maxi(total_seconds, 0)
	var minutes: int = clamped / 60
	var seconds: int = clamped % 60
	return "%02d:%02d" % [minutes, seconds]


func is_traveling() -> bool:
	return agent_state == "MOVING" and not travel_destination_id.is_empty()


func finish_travel() -> void:
	world_graph.set_current_location(travel_destination_id)
	selected_location_id = world_graph.current_location_id
	agent_state = "EXPLORING"
	append_log("[系统] 移动完成，少女已到达 %s。" % world_graph.get_current_location().get("name", "未知地点"))
	append_log("[少女] 我到了，这里和你在地图上看到的一样，但现场细节更多。")
	if not planned_route.is_empty():
		planned_route.remove_at(0)
	if planned_route.size() > 1:
		var next_leg_id: String = planned_route[1]
		append_log("[系统] 已规划后续路段，继续前往 %s。" % world_graph.get_location(next_leg_id).get("name", "未知地点"))
		start_travel_leg(next_leg_id)
		return
	system_agent_desired_location_ids.erase(world_graph.current_location_id)
	travel_origin_id = ""
	travel_destination_id = ""
	travel_remaining_seconds = 0
	active_travel_connection = {}
	planned_route.clear()
	render_graph_data()
	var arrival_event := SystemEventScript.make(
		SystemEventScript.TYPE_ARRIVED_AT_LOCATION,
		"Reached %s and can now inspect the area." % str(world_graph.get_current_location().get("name", world_graph.current_location_id)),
		{
			"location_id": world_graph.current_location_id,
			"location_name": str(world_graph.get_current_location().get("name", world_graph.current_location_id))
		}
	)
	dispatch_system_event(arrival_event)


func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	pause_overlay.visible = paused


func build_agent_context(trigger_type: String = AgentContextScript.TRIGGER_PLAYER_MESSAGE, trigger_reason: String = "player_submitted_message"):
	var context = AgentContextScript.new()
	context.trigger_type = trigger_type
	context.trigger_reason = trigger_reason
	context.world_time_seconds = world_time_seconds
	context.agent_state = agent_state
	context.short_term_goal = system_agent_short_term_goal
	context.recent_dialogue_summary = system_recent_dialogue_summary
	context.desired_location_ids = system_agent_desired_location_ids.duplicate()
	context.allowed_command_types.clear()
	context.allowed_command_types.append(AgentCommandScript.TYPE_MOVE_TO_LOCATION)

	if is_traveling():
		context.current_location_id = travel_origin_id
		context.current_location_name = str(world_graph.get_location(travel_origin_id).get("name", travel_origin_id))
		context.active_travel_route = {
			"from_location_id": travel_origin_id,
			"from_location_name": world_graph.get_location(travel_origin_id).get("name", travel_origin_id),
			"to_location_id": travel_destination_id,
			"to_location_name": world_graph.get_location(travel_destination_id).get("name", travel_destination_id),
			"direction_label": active_travel_connection.get("direction_label", ""),
			"remaining_seconds": travel_remaining_seconds
		}
	else:
		context.current_location_id = world_graph.current_location_id
		context.current_location_name = str(world_graph.get_current_location().get("name", world_graph.current_location_id))

	for neighbor in world_graph.get_neighbors(world_graph.current_location_id):
		var neighbor_id: String = str(neighbor.get("to_id", ""))
		var travel_result: Dictionary = world_graph.can_travel(world_graph.current_location_id, neighbor_id, unlocked_requirements)
		context.visible_routes.append({
			"to_location_id": neighbor_id,
			"to_location_name": neighbor.get("to_name", neighbor_id),
			"direction_label": neighbor.get("direction_label", ""),
			"travel_time_seconds": int(neighbor.get("travel_time", 0)) * 60,
			"allowed": bool(travel_result.get("allowed", false)),
			"reasons": travel_result.get("reasons", [])
		})

	return context


func apply_agent_output(agent_output, trigger_label: String) -> void:
	if agent_output == null:
		return
	if not str(agent_output.reply_text).is_empty():
		append_log("%s %s" % [trigger_label, str(agent_output.reply_text)])
	var desired_names: Array[String] = get_system_desired_location_names()
	if not desired_names.is_empty():
		append_log("[System] Desired locations: %s" % " -> ".join(desired_names))
	append_log("[System] Short-term goal: %s" % system_agent_short_term_goal)
	execute_command_set(agent_output.commands)


func reset_agent_exchange_timer() -> void:
	seconds_since_last_agent_exchange = 0


func dispatch_system_event(event) -> void:
	if event == null:
		return
	reset_agent_exchange_timer()
	var context = build_agent_context(AgentContextScript.TRIGGER_SYSTEM_EVENT, str(event.event_type))
	append_log("[System] Triggered S->A event: %s" % str(event.summary_text))
	system_recent_dialogue_summary = "Latest system event: %s" % str(event.summary_text)
	var agent_output = current_agent.process_system_event(event, context, world_graph)
	apply_agent_output(agent_output, "[Girl]")


func get_system_desired_location_names() -> Array[String]:
	var names: Array[String] = []
	for location_id in system_agent_desired_location_ids:
		var location: Dictionary = world_graph.get_location(location_id)
		if not location.is_empty():
			names.append(str(location.get("name", location_id)))
	return names


func execute_command_set(commands: Array[AgentCommand]) -> Array[SystemResult]:
	var results: Array[SystemResult] = []
	for command in commands:
		match command.type:
			AgentCommandScript.TYPE_MOVE_TO_LOCATION:
				results.append(execute_move_command(command))
	return results


func execute_move_command(command: AgentCommand) -> SystemResult:
	if is_traveling():
		append_log("[系统] 少女已经在路上了，这条移动指令暂时不能执行。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "少女已经在路上")

	var target_location_id: String = command.target_location_id
	var target_location_name: String = command.target_location_name
	if target_location_id.is_empty():
		append_log("[系统] 移动指令缺少目标地点，无法执行。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "移动指令缺少目标地点")

	system_agent_desired_location_ids.erase(target_location_id)
	system_agent_desired_location_ids.append(target_location_id)
	system_agent_short_term_goal = "前往%s并调查是否存在新线索" % target_location_name

	var path: Array[String] = world_graph.find_path(world_graph.current_location_id, target_location_id, unlocked_requirements)
	if path.is_empty():
		append_log("[系统] 已收到前往 %s 的请求，但当前找不到满足条件的路径。" % target_location_name)
		var rejected := SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前找不到满足条件的路径")
		rejected.target_location_id = target_location_id
		return rejected

	if path.size() == 1:
		append_log("[系统] 少女已经在 %s，无需再次移动。" % target_location_name)
		system_agent_desired_location_ids.erase(target_location_id)
		var already := SystemResult.make(SystemResult.TYPE_ALREADY_AT_TARGET, true, "已经位于目标地点")
		already.target_location_id = target_location_id
		return already

	planned_route = path.duplicate()
	selected_location_id = target_location_id
	var next_leg_id: String = path[1]
	var next_connection: Dictionary = world_graph.get_connection(world_graph.current_location_id, next_leg_id)
	var named_path: Array[String] = []
	for location_id in path:
		named_path.append(str(world_graph.get_location(location_id).get("name", location_id)))
	append_log("[系统] 已为 %s 规划路径：%s。" % [target_location_name, " -> ".join(named_path)])
	append_log("[系统] 第一段将沿 %s 方向前往 %s。" % [
		next_connection.get("direction_label", "未知"),
		world_graph.get_location(next_leg_id).get("name", next_leg_id)
	])
	start_travel_leg(next_leg_id)
	var result := SystemResult.make(SystemResult.TYPE_MOVEMENT_STARTED, true, "开始沿规划路径移动")
	result.target_location_id = target_location_id
	result.path = path.duplicate()
	result.from_location_id = world_graph.current_location_id
	result.to_location_id = next_leg_id
	result.direction_label = str(next_connection.get("direction_label", ""))
	result.travel_time_seconds = world_graph.get_travel_time(world_graph.current_location_id, next_leg_id) * 60
	return result


func start_travel_leg(next_location_id: String) -> void:
	var origin_id: String = world_graph.current_location_id
	var destination: Dictionary = world_graph.get_location(next_location_id)
	var travel_time: int = world_graph.get_travel_time(origin_id, next_location_id)
	travel_origin_id = origin_id
	travel_destination_id = next_location_id
	travel_remaining_seconds = travel_time * 60
	active_travel_connection = world_graph.get_connection(origin_id, next_location_id)
	agent_state = "MOVING"
	append_log("[少女] 我从 %s 出发，正在前往 %s，预计需要 %d 分钟。" % [
		world_graph.get_location(origin_id).get("name", "未知地点"),
		destination.get("name", "未知地点"),
		travel_time
	])
	render_graph_data()


func _on_send_pressed() -> void:
	var message := input_box.text.strip_edges()
	if message.is_empty():
		return
	reset_agent_exchange_timer()
	append_log("[玩家] " + message)
	system_recent_dialogue_summary = "玩家最近一次输入：%s" % message
	var context = build_agent_context()
	append_log("[系统] 已向少女同步世界信息：时间 %s，当前位置 %s。" % [
		context.format_clock(),
		context.current_location_name
	])
	var agent_output = current_agent.process_player_message(message, context, world_graph)
	apply_agent_output(agent_output, "[Girl]")
	input_box.clear()
	return
	append_log("[少女] " + agent_output.reply_text)
	var desired_names: Array[String] = get_system_desired_location_names()
	if not desired_names.is_empty():
		append_log("[系统] 当前系统托管的希望前往位置列表：%s。" % " -> ".join(desired_names))
	append_log("[系统] 当前短期目标：%s。" % system_agent_short_term_goal)
	execute_command_set(agent_output.commands)
	input_box.clear()


func _on_send_submitted(_text: String) -> void:
	_on_send_pressed()


func _on_quick_action(action_text: String) -> void:
	append_log("[玩家] " + action_text)
	append_log("[系统] 快捷指令已记录，后续可在这里挂动作解析器。")


func advance_world_time(delta_seconds: int, emit_log: bool = false) -> void:
	world_time_seconds += delta_seconds
	time_label.text = format_clock(world_time_seconds)
	if is_traveling():
		travel_remaining_seconds -= delta_seconds
		seconds_since_last_agent_exchange = 0
		if travel_remaining_seconds <= 0:
			finish_travel()
		elif emit_log:
			append_log("[系统] 时间推进 %d 秒，少女仍在路上，前往 %s 还需 %s。" % [
				delta_seconds,
				world_graph.get_location(travel_destination_id).get("name", "未知地点"),
				format_duration(travel_remaining_seconds)
			])
			render_graph_data()
	else:
		if agent_state == "EXPLORING":
			seconds_since_last_agent_exchange += delta_seconds
			if seconds_since_last_agent_exchange >= AUTO_EXPLORE_INTERVAL_SECONDS:
				var idle_event := SystemEventScript.make(
					SystemEventScript.TYPE_EXPLORATION_IDLE,
					"Five minutes passed without a new U->A or S->A exchange while exploring.",
					{
						"elapsed_seconds": seconds_since_last_agent_exchange,
						"location_id": world_graph.current_location_id,
						"location_name": str(world_graph.get_current_location().get("name", world_graph.current_location_id))
					}
				)
				dispatch_system_event(idle_event)
		elif agent_state != "MOVING":
			seconds_since_last_agent_exchange = 0
		if not emit_log:
			return
		if emit_log:
			pass
		append_log("[系统] 时间推进 %d 秒，少女继续保持自主探索。" % delta_seconds)


func _on_world_tick() -> void:
	if paused:
		return
	advance_world_time(1)


func _on_debug_advance_time() -> void:
	advance_world_time(10, true)


func _on_map_location_selected(index: int) -> void:
	var ids: Array[String] = world_graph.get_location_ids()
	if index < 0 or index >= ids.size():
		return
	selected_location_id = ids[index]
	render_location_detail()
	render_clues()


func _on_route_selected(index: int) -> void:
	var neighbors: Array[Dictionary] = world_graph.get_neighbors(world_graph.current_location_id)
	if index < 0 or index >= neighbors.size():
		return
	selected_location_id = str(neighbors[index].get("to_id", ""))
	render_map_list()
	render_location_detail()
	render_clues()


func _on_move_pressed() -> void:
	if is_traveling():
		append_log("[系统] 少女已经在路上了，必须等当前移动结束后才能下达新的移动命令。")
		return
	if selected_location_id == world_graph.current_location_id:
		append_log("[系统] 当前已在这个地点，无需移动。")
		return
	execute_move_command(AgentCommandScript.move_to_location(
		selected_location_id,
		str(world_graph.get_location(selected_location_id).get("name", selected_location_id))
	))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
