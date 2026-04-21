extends Control

const WorldGraph = preload("res://scripts/core/world_graph.gd")
const WorldObjects = preload("res://scripts/core/world_objects.gd")
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
const AUTO_EXPLORE_INTERVAL_SECONDS := 30
const MAP_NODE_SIZE := Vector2(132, 42)


class MapGraphView:
	extends Control

	var connection_segments: Array[Dictionary] = []
	var highlight_segments: Array[Dictionary] = []

	func _draw() -> void:
		for segment in connection_segments:
			draw_line(
				segment.get("from", Vector2.ZERO),
				segment.get("to", Vector2.ZERO),
				segment.get("color", Color.GRAY),
				float(segment.get("width", 3.0)),
				true
			)
		for segment in highlight_segments:
			draw_line(
				segment.get("from", Vector2.ZERO),
				segment.get("to", Vector2.ZERO),
				segment.get("color", Color.WHITE),
				float(segment.get("width", 5.0)),
				true
			)

var world_time_seconds: int = 22 * 3600 + 14 * 60
var paused := false
var world_graph := WorldGraph.new()
var world_objects := WorldObjects.new()
var current_agent = null
var girl_name: String = "迫降的星际探险少女"
var girl_profile: String = "一名在深空任务中遭遇迫降的年轻探险少女。她刚从休眠舱醒来，已经独自在失事飞船里撑过三天。她受过基础工程与野外调查训练，警惕、坚韧，也会因为长时间独处而格外珍惜来之不易的联系。"
var girl_favorability: int = 42
var girl_satiety: int = 57
var girl_ideology: int = 61
var girl_mood: int = 38
var satiety_decay_accumulator_seconds: int = 0
var system_agent_desired_location_ids: Array[String] = []
var system_agent_short_term_goal: String = "保持通讯稳定并评估周边区域。"
var system_recent_dialogue_summary: String = "玩家与少女刚建立无线电联系，正在规划下一步探索。"
var selected_location_id := ""
var unlocked_requirements: Array[String] = ["light_source"]
var agent_state: String = "EXPLORING"
var prologue_intro_played := false
var travel_origin_id: String = ""
var travel_destination_id: String = ""
var travel_remaining_seconds: int = 0
var active_travel_connection: Dictionary = {}
var planned_route: Array[String] = []
var seconds_since_last_agent_exchange: int = 0
var agent_request_in_flight := false
var pending_system_events: Array = []
var show_system_messages := false
var world_timer: Timer

var time_label: Label
var status_label: Label
var location_label: Label
var objective_label: Label
var system_log_toggle_button: Button
var map_summary_label: Label
var map_graph_view
var map_list = null
var map_node_buttons: Dictionary = {}
var route_list: ItemList
var clue_list: ItemList
var inventory_list: ItemList
var comms_log: RichTextLabel
var input_box: LineEdit
var pause_overlay: ColorRect
var pause_label: Label
var detail_title_label: Label
var detail_description_label: Label
var detail_meta_label: Label
var character_profile_label: Label
var character_status_bars: Dictionary = {}
var character_status_value_labels: Dictionary = {}


func _ready() -> void:
	world_graph.load_from_file("res://data/world/graph_demo.json")
	world_objects.load_from_file("res://data/world/objects_intro.json")
	current_agent = AgentFactory.create_agent()
	selected_location_id = world_graph.current_location_id
	build_ui()
	setup_world_timer()
	render_graph_data()
	append_boot_log()
	play_first_contact_intro()
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
	objective_label.text = "目标：建立稳定通讯，协助少女确认飞船现状。"
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

	system_log_toggle_button = Button.new()
	system_log_toggle_button.text = get_system_log_toggle_text()
	system_log_toggle_button.pressed.connect(toggle_system_log_visibility)
	info_row.add_child(system_log_toggle_button)

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

	comms_column.add_child(make_section_title("通讯终端", "这里用于显示玩家输入、少女回复和系统注入的消息。"))

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
	input_label.text = "发送消息"
	input_label.modulate = TEXT_SOFT
	comms_column.add_child(input_label)

	input_box = LineEdit.new()
	input_box.custom_minimum_size = Vector2(0, 42)
	input_box.placeholder_text = "输入你要发给少女的话，例如：先别开舱门，拍一下门锁给我看看。"
	input_box.text_submitted.connect(_on_send_submitted)
	comms_column.add_child(input_box)

	var send_row := HBoxContainer.new()
	comms_column.add_child(send_row)

	var send_button := Button.new()
	send_button.text = "发送"
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

	column.add_child(make_section_title("地图与动线", "节点图显示全部地点；下方列表显示当前可见的有向路线、方向和耗时。"))

	map_summary_label = Label.new()
	map_summary_label.modulate = TEXT_SOFT
	column.add_child(map_summary_label)

	map_graph_view = MapGraphView.new()
	map_graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_graph_view.custom_minimum_size = Vector2(0, 180)
	map_graph_view.clip_contents = false
	map_graph_view.resized.connect(render_map_list)
	column.add_child(map_graph_view)

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
	panel.custom_minimum_size = Vector2(280, 190)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	column.add_child(make_section_title("人物状态", "这里显示少女的设定摘要，以及好感、饱食、思想倾向和情绪状态。"))

	character_profile_label = Label.new()
	character_profile_label.modulate = TEXT_SOFT
	character_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_profile_label.max_lines_visible = 4
	column.add_child(character_profile_label)

	var favorability_meter: Dictionary = make_status_meter("好感度", Color("98f5a2"))
	column.add_child(favorability_meter.get("root"))
	character_status_bars["favorability"] = favorability_meter.get("bar")
	character_status_value_labels["favorability"] = favorability_meter.get("value_label")

	var satiety_meter: Dictionary = make_status_meter("饱食度", ACCENT_WARM)
	column.add_child(satiety_meter.get("root"))
	character_status_bars["satiety"] = satiety_meter.get("bar")
	character_status_value_labels["satiety"] = satiety_meter.get("value_label")

	var ideology_meter: Dictionary = make_status_meter("思想倾向", ACCENT)
	column.add_child(ideology_meter.get("root"))
	character_status_bars["ideology"] = ideology_meter.get("bar")
	character_status_value_labels["ideology"] = ideology_meter.get("value_label")

	var mood_meter: Dictionary = make_status_meter("情绪", ALERT)
	column.add_child(mood_meter.get("root"))
	character_status_bars["mood"] = mood_meter.get("bar")
	character_status_value_labels["mood"] = mood_meter.get("value_label")

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

	column.add_child(make_section_title("当前地点详情", "这里由地图数据驱动，显示描述、探索状态、进入条件和交互对象。"))

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

	column.add_child(make_section_title("当前地点内容", "这里显示当前地点中的可拾取物品和可交互对象，仅用于观察，不直接替少女执行动作。"))

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

	column.add_child(make_section_title("物品栏", "这里显示少女当前持有的对象。玩家只能查看，不能直接代替少女拾取、使用或丢弃物品。"))

	inventory_list = ItemList.new()
	inventory_list.custom_minimum_size = Vector2(0, 140)
	inventory_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(inventory_list)

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
	render_character_status()
	render_location_detail()
	render_clues()
	render_inventory()


func render_header() -> void:
	var current_location: Dictionary = world_graph.get_current_location()
	time_label.text = format_clock(world_time_seconds)
	status_label.text = "少女状态: %s" % agent_state
	if is_traveling():
		var from_name: String = str(world_graph.get_location(travel_origin_id).get("name", "--"))
		var to_name: String = str(world_graph.get_location(travel_destination_id).get("name", "--"))
		location_label.text = "当前位置: %s -> %s" % [from_name, to_name]
	else:
		location_label.text = "当前位置: %s" % current_location.get("name", "--")
	map_summary_label.text = "地点 %d 个 | 已探索 %d 个 | 已解锁条件: %s" % [
		world_graph.get_location_ids().size(),
		world_graph.count_visited_locations(),
		", ".join(unlocked_requirements)
	]


func render_character_status() -> void:
	if character_profile_label != null:
		character_profile_label.text = "%s\n%s" % [girl_name, girl_profile]

	_update_status_meter("favorability", girl_favorability, "保留")
	_update_status_meter("satiety", girl_satiety, "稳定")
	_update_status_meter("ideology", girl_ideology, "保守 ← → 自由")
	_update_status_meter("mood", girl_mood, "消极 ← → 积极")


func _update_status_meter(status_id: String, value: int, suffix: String) -> void:
	var bar: ProgressBar = character_status_bars.get(status_id, null)
	var value_label: Label = character_status_value_labels.get(status_id, null)
	if bar != null:
		bar.value = clampi(value, 0, 100)
	if value_label != null:
		value_label.text = "%d / 100  %s" % [clampi(value, 0, 100), suffix]


func get_hunger_prompt_hint() -> String:
	if girl_satiety < 10:
		return "系统补充：你现在已经快要饿死了，饥饿感正在强烈影响你的判断与情绪。"
	if girl_satiety < 30:
		return "系统补充：你现在已经很饿了，必须认真考虑食物和体力问题。"
	return ""


func render_map_list() -> void:
	if map_graph_view == null:
		return

	_ensure_map_node_buttons()
	var ids: Array[String] = world_graph.get_location_ids()
	if ids.is_empty():
		return

	var layout: Dictionary = _build_map_node_layout(ids)
	var positions: Dictionary = layout.get("positions", {})
	var centers: Dictionary = layout.get("centers", {})
	var connection_segments: Array[Dictionary] = []
	var highlight_segments: Array[Dictionary] = []

	for location_id in ids:
		var button: Button = map_node_buttons.get(location_id, null)
		if button == null:
			continue
		var location: Dictionary = world_graph.get_location(location_id)
		button.position = positions.get(location_id, Vector2.ZERO)
		button.size = MAP_NODE_SIZE
		var visited_text_graph: String = "已探索" if bool(location.get("visited", false)) else "未知"
		button.text = "%s\n%s" % [str(location.get("name", "")), visited_text_graph]
		_style_map_node_button(button, location_id)

	for from_id in ids:
		for neighbor in world_graph.get_neighbors(from_id):
			var to_id: String = str(neighbor.get("to_id", ""))
			if not centers.has(from_id) or not centers.has(to_id):
				continue
			connection_segments.append({
				"from": centers[from_id],
				"to": centers[to_id],
				"color": Color("35536f"),
				"width": 3.0
			})

	if is_traveling():
		if centers.has(travel_origin_id) and centers.has(travel_destination_id):
			highlight_segments.append({
				"from": centers[travel_origin_id],
				"to": centers[travel_destination_id],
				"color": ACCENT_WARM,
				"width": 6.0
			})
	elif planned_route.size() > 1:
		for index_graph in range(planned_route.size() - 1):
			var route_from_id: String = planned_route[index_graph]
			var route_to_id: String = planned_route[index_graph + 1]
			if not centers.has(route_from_id) or not centers.has(route_to_id):
				continue
			highlight_segments.append({
				"from": centers[route_from_id],
				"to": centers[route_to_id],
				"color": ACCENT,
				"width": 5.0
			})

	map_graph_view.connection_segments = connection_segments
	map_graph_view.highlight_segments = highlight_segments
	map_graph_view.queue_redraw()


func _ensure_map_node_buttons() -> void:
	if map_graph_view == null:
		return

	var valid_ids: Dictionary = {}
	for location_id in world_graph.get_location_ids():
		valid_ids[location_id] = true
		if map_node_buttons.has(location_id):
			continue
		var button := Button.new()
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(_on_map_node_pressed.bind(location_id))
		map_graph_view.add_child(button)
		map_node_buttons[location_id] = button

	for existing_id in map_node_buttons.keys():
		if valid_ids.has(existing_id):
			continue
		var stale_button: Button = map_node_buttons[existing_id]
		if stale_button != null:
			stale_button.queue_free()
		map_node_buttons.erase(existing_id)


func _build_map_node_layout(ids: Array[String]) -> Dictionary:
	var min_x: float = 999999.0
	var max_x: float = -999999.0
	var min_y: float = 999999.0
	var max_y: float = -999999.0
	var raw_positions: Dictionary = {}

	for location_id in ids:
		var location: Dictionary = world_graph.get_location(location_id)
		var map_position: Dictionary = location.get("map_position", {})
		var x: float = float(map_position.get("x", 0.0))
		var y: float = float(map_position.get("y", 0.0))
		raw_positions[location_id] = Vector2(x, y)
		min_x = mini(min_x, x)
		max_x = maxi(max_x, x)
		min_y = mini(min_y, y)
		max_y = maxi(max_y, y)

	var graph_size: Vector2 = map_graph_view.size
	if graph_size.x <= 0.0 or graph_size.y <= 0.0:
		graph_size = map_graph_view.custom_minimum_size
	if graph_size.x <= 0.0:
		graph_size.x = 480.0
	if graph_size.y <= 0.0:
		graph_size.y = 180.0

	var horizontal_steps: float = maxi(max_x - min_x, 1.0)
	var vertical_steps: float = maxi(max_y - min_y, 1.0)
	var available_width: float = maxi(graph_size.x - MAP_NODE_SIZE.x - 24.0, 1.0)
	var available_height: float = maxi(graph_size.y - MAP_NODE_SIZE.y - 24.0, 1.0)
	var step_x: float = available_width / horizontal_steps
	var step_y: float = available_height / vertical_steps
	var positions: Dictionary = {}
	var centers: Dictionary = {}

	for location_id in ids:
		var raw_position: Vector2 = raw_positions[location_id]
		var final_position := Vector2(
			12.0 + (raw_position.x - min_x) * step_x,
			12.0 + (max_y - raw_position.y) * step_y
		)
		positions[location_id] = final_position
		centers[location_id] = final_position + MAP_NODE_SIZE * 0.5

	return {
		"positions": positions,
		"centers": centers
	}


func _style_map_node_button(button: Button, location_id: String) -> void:
	var fill: Color = PANEL_ALT
	var border: Color = Color("35536f")
	if location_id == world_graph.current_location_id:
		fill = ACCENT
		border = ACCENT
	elif location_id == selected_location_id:
		fill = Color("214e73")
		border = ACCENT_WARM
	elif bool(world_graph.get_location(location_id).get("visited", false)):
		fill = Color("17324a")
		border = Color("4e6d87")

	if location_id == "airlock_hatch":
		var airlock_door: Dictionary = world_objects.get_object("obj_airlock_door_01")
		if not airlock_door.is_empty():
			var airlock_state: Dictionary = airlock_door.get("state", {})
			var airlock_powered: bool = bool(airlock_state.get("powered", false))
			var airlock_opened: bool = bool(airlock_state.get("opened", false))
			if airlock_opened:
				border = Color("7ddc8b")
			elif not airlock_powered:
				border = Color("e27d7d")

	button.add_theme_color_override("font_color", BG if location_id == world_graph.current_location_id else TEXT)
	button.add_theme_stylebox_override("normal", make_panel_style(fill, 14, border))
	button.add_theme_stylebox_override("hover", make_panel_style(fill.lightened(0.08), 14, ACCENT_WARM))
	button.add_theme_stylebox_override("pressed", make_panel_style(fill.darkened(0.08), 14, ACCENT_WARM))


func _on_map_node_pressed(location_id: String) -> void:
	selected_location_id = location_id
	render_map_list()
	render_location_detail()
	render_clues()


func render_route_list() -> void:
	route_list.clear()
	if is_traveling():
		var route_text: String = "%s %s -> %s | 全程 %d 分钟 | 剩余 %s" % [
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
		var status: String = "可通行" if bool(travel_result.get("allowed", false)) else "缺少条件: %s" % ", ".join(travel_result.get("reasons", []))
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
		detail_title_label.text = "路途中"
		detail_meta_label.text = "状态: MOVING | 方向: %s | 剩余: %s" % [
			active_travel_connection.get("direction_label", ""),
			format_duration(travel_remaining_seconds)
		]
		detail_description_label.text = "少女正在从 %s 前往 %s。在移动完成之前，她处于道路状态而不是某个具体地点。" % [
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
	for object_data in world_objects.get_location_objects(selected_location_id):
		clue_list.add_item(format_object_list_entry(object_data))
	if clue_list.item_count == 0:
		clue_list.add_item("当前地点没有可见对象。")


func render_inventory() -> void:
	if inventory_list == null:
		return
	inventory_list.clear()
	for object_data in world_objects.get_inventory_objects():
		inventory_list.add_item(format_object_list_entry(object_data))
	if inventory_list.item_count == 0:
		inventory_list.add_item("少女当前没有携带任何物品。")


func format_object_list_entry(object_data: Dictionary) -> String:
	var object_type: String = str(object_data.get("type", "object"))
	var name: String = str(object_data.get("name", "未知对象"))
	var summary: String = format_object_state_summary(object_data)
	if summary.is_empty():
		return "%s | %s" % [object_type_label(object_type), name]
	return "%s | %s | %s" % [object_type_label(object_type), name, summary]


func object_type_label(object_type: String) -> String:
	match object_type:
		"item":
			return "物品"
		"food":
			return "食物"
		"battery":
			return "电池"
		"device":
			return "设备"
		"door":
			return "舱门"
		"container":
			return "容器"
		_:
			return "对象"


func format_object_state_summary(object_data: Dictionary) -> String:
	var state: Dictionary = object_data.get("state", {})
	if state.has("charge"):
		return "电量 %s" % str(state.get("charge", 0))
	if state.has("energy"):
		return "能量 %s" % str(state.get("energy", 0))
	if state.has("stored_power") or state.has("power_target_index"):
		return "储能 %s / 目标 %s" % [
			str(state.get("stored_power", 0)),
			str(state.get("power_target_index", 0))
		]
	if state.has("powered") or state.has("opened"):
		return "供电 %s / 开启 %s" % [
			"是" if bool(state.get("powered", false)) else "否",
			"是" if bool(state.get("opened", false)) else "否"
		]
	return str(object_data.get("description", ""))


func append_boot_log() -> void:
	append_log("[系统] 图结构地图已加载，当前地点是 %s。" % world_graph.get_current_location().get("name", "未知地点"))
	append_log("[系统] 当前地图包含 %d 个地点和 %d 条有向连边。" % [world_graph.get_location_ids().size(), world_graph.get_connection_count()])
	append_log("[系统] 当前短期目标：%s。" % system_agent_short_term_goal)
	append_log("[系统] 当前 Agent 模式：%s。" % current_agent.get_adapter_name())
	if AgentRuntimeConfig.is_llm_mode():
		append_log("[系统] 已启用真实 Agent 适配层，当前项目可以在测试代理和 LLM 代理之间切换。")
	else:
		append_log("[系统] 已启用测试代理，在消息里提到地点名时会自动生成移动指令。")
	append_log("[少女] 我先把附近能走的路线整理好了，你可以看看右边的路线面板。")


func play_first_contact_intro() -> void:
	if prologue_intro_played:
		return
	prologue_intro_played = true
	objective_label.text = "目标：完成首次通讯，帮助少女确认飞船内部现状。"
	system_agent_short_term_goal = "完成首次通讯，帮助少女确认飞船内部的关键状况。"
	system_recent_dialogue_summary = "少女刚通过无线电与玩家建立联系，正在说明自己迫降后的处境。"
	append_log("[系统] 序章事件触发：首次接通无线电。")
	append_log("[少女] 喂？能听见吗？太好了，终于有人回应我了。")
	append_log("[少女] 我刚从休眠舱里醒来，发现乘坐的飞船迫降在一颗陌生的星球上。")
	append_log("[少女] 从我醒来到现在已经过去三天了。这三天我一直在摸索飞船里还能不能用的东西，刚才摆弄无线电时正好联系上了你。")
	append_log("[少女] 我现在在休息室。飞船内部勉强还能活动，但很多系统都不太稳定。你愿意先陪我确认一下这艘船现在到底是什么情况吗？")
	render_graph_data()


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


func make_status_meter(label_text: String, tint: Color) -> Dictionary:
	var column := VBoxContainer.new()

	var row := HBoxContainer.new()
	column.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value_label := Label.new()
	value_label.text = "0 / 100"
	value_label.modulate = TEXT_SOFT
	row.add_child(value_label)

	var bar := ProgressBar.new()
	bar.value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.modulate = tint
	bar.custom_minimum_size = Vector2(0, 16)
	column.add_child(bar)

	return {
		"root": column,
		"bar": bar,
		"value_label": value_label
	}


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
	if not show_system_messages and message.begins_with("[系统]"):
		return
	if comms_log.text.is_empty():
		comms_log.text = message
	else:
		comms_log.text += "\n\n" + message


func get_system_log_toggle_text() -> String:
	return "系统消息: 开" if show_system_messages else "系统消息: 关"


func toggle_system_log_visibility() -> void:
	show_system_messages = not show_system_messages
	if system_log_toggle_button != null:
		system_log_toggle_button.text = get_system_log_toggle_text()


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
	append_log("[系统] 移动完成，少女已抵达 %s。" % world_graph.get_current_location().get("name", "未知地点"))
	append_log("[少女] 我到了。这里和地图上看到的大致一致，但现场细节更多。")
	if not planned_route.is_empty():
		planned_route.remove_at(0)
	if planned_route.size() > 1:
		var next_leg_id: String = planned_route[1]
		append_log("[系统] 已规划后续路段，继续前往 %s。" % world_graph.get_location(next_leg_id).get("name", "未知地点"))
		start_travel_leg(next_leg_id)
		return
	system_agent_desired_location_ids.erase(world_graph.current_location_id)
	set_investigation_goal(world_graph.current_location_id)
	travel_origin_id = ""
	travel_destination_id = ""
	travel_remaining_seconds = 0
	active_travel_connection = {}
	planned_route.clear()
	render_graph_data()
	var arrival_event := SystemEventScript.make(
		SystemEventScript.TYPE_ARRIVED_AT_LOCATION,
		"已抵达 %s，现在可以开始观察周围环境。" % str(world_graph.get_current_location().get("name", world_graph.current_location_id)),
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
	context.character_name = girl_name
	context.character_profile = girl_profile
	context.character_status = {
		"favorability": girl_favorability,
		"satiety": girl_satiety,
		"ideology": girl_ideology,
		"mood": girl_mood
	}
	context.hunger_prompt_hint = get_hunger_prompt_hint()
	context.short_term_goal = system_agent_short_term_goal
	context.recent_dialogue_summary = system_recent_dialogue_summary
	context.desired_location_ids = system_agent_desired_location_ids.duplicate()
	context.current_location_objects = build_visible_objects_for_holder(world_graph.current_location_id)
	context.inventory_objects = build_visible_objects_for_holder("girl")
	context.allowed_command_types.clear()
	context.allowed_command_types.append(AgentCommandScript.TYPE_MOVE_TO_LOCATION)
	context.allowed_command_types.append(AgentCommandScript.TYPE_ACT)

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


func build_visible_objects_for_holder(holder_id: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for object_data in world_objects.get_objects_by_holder(holder_id):
		var object_id: String = str(object_data.get("instance_id", ""))
		if object_id.is_empty():
			continue
		results.append(world_objects.get_visible_object(object_id))
	return results


func apply_agent_output(agent_output, trigger_label: String) -> void:
	if agent_output == null:
		return
	if not str(agent_output.reply_text).is_empty():
		append_log("%s %s" % [trigger_label, str(agent_output.reply_text)])
	execute_command_set(agent_output.commands)
	var desired_names: Array[String] = get_system_desired_location_names()
	if not desired_names.is_empty():
		append_log("[系统] 当前希望前往的位置队列：%s" % " -> ".join(desired_names))
	append_log("[系统] 当前短期目标：%s" % system_agent_short_term_goal)


func reset_agent_exchange_timer() -> void:
	seconds_since_last_agent_exchange = 0


func dispatch_system_event(event) -> void:
	if event == null:
		return
	if agent_request_in_flight:
		pending_system_events.append(event)
		append_log("[系统] LLM 请求仍在处理中，系统事件已排队等待后续执行。")
		return
	_dispatch_system_event_async(event)


func _dispatch_system_event_async(event) -> void:
	reset_agent_exchange_timer()
	var context = build_agent_context(AgentContextScript.TRIGGER_SYSTEM_EVENT, str(event.event_type))
	append_log("[系统] 已触发 S->A 事件：%s" % str(event.summary_text))
	system_recent_dialogue_summary = "最近一次系统事件：%s" % str(event.summary_text)
	agent_request_in_flight = true
	var agent_output
	if current_agent.is_async():
		agent_output = await current_agent.process_system_event_async(self, event, context, world_graph)
	else:
		agent_output = current_agent.process_system_event(event, context, world_graph)
	agent_request_in_flight = false
	apply_agent_output(agent_output, "[少女]")
	process_pending_system_events()


func get_system_desired_location_names() -> Array[String]:
	var names: Array[String] = []
	for location_id in system_agent_desired_location_ids:
		var location: Dictionary = world_graph.get_location(location_id)
		if not location.is_empty():
			names.append(str(location.get("name", location_id)))
	return names


func set_investigation_goal(location_id: String) -> void:
	var location: Dictionary = world_graph.get_location(location_id)
	var location_name: String = str(location.get("name", location_id))
	system_agent_short_term_goal = "在 %s 调查周围并寻找新的线索" % location_name


func execute_command_set(commands: Array[AgentCommand]) -> Array[SystemResult]:
	var results: Array[SystemResult] = []
	for command in commands:
		match command.type:
			AgentCommandScript.TYPE_MOVE_TO_LOCATION:
				results.append(execute_move_command(command))
			AgentCommandScript.TYPE_ACT:
				results.append(execute_act_command(command))
	return results


func execute_act_command(command: AgentCommand) -> SystemResult:
	if is_traveling():
		append_log("[系统] 少女正在移动中，当前不能执行对象交互。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "少女正在移动中")

	var target_id: String = command.target_id
	if target_id.is_empty() or not world_objects.has_object(target_id):
		append_log("[系统] act 指令缺少有效的目标对象。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "act 指令缺少有效的目标对象")

	if not world_objects.supports_action(target_id, command.action):
		append_log("[系统] 对象 %s 不支持动作 %s。" % [target_id, command.action])
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
			append_log("[系统] 未知 act 动作：%s。" % command.action)
			return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "未知 act 动作")


func execute_inspect_action(target_id: String) -> SystemResult:
	var object_data: Dictionary = world_objects.get_object(target_id)
	if not can_access_object(target_id):
		append_log("[系统] 当前无法查看 %s，因为它不在少女可直接接触的范围内。" % str(object_data.get("name", target_id)))
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法查看该对象")

	var object_name: String = str(object_data.get("name", target_id))
	var summary: String = format_object_state_summary(object_data)
	var inspection_description: String = build_inspection_description(target_id, object_data)
	append_log("[系统] 少女检查了 %s。" % object_name)
	append_log("[少女] %s" % inspection_description)
	dispatch_system_event(SystemEventScript.make(
		SystemEventScript.TYPE_INSPECTION_RESULT,
		"少女刚刚检查了 %s。" % object_name,
		{
			"object_id": target_id,
			"object_name": object_name,
			"inspection_description": inspection_description,
			"visible_object": world_objects.get_visible_object(target_id),
			"state_summary": summary
		}
	))
	var result := SystemResult.make(SystemResult.TYPE_OBJECT_INSPECTED, true, "已检查对象")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_INSPECT
	result.payload = world_objects.get_visible_object(target_id)
	return result


func build_inspection_description(target_id: String, object_data: Dictionary) -> String:
	var object_name: String = str(object_data.get("name", target_id))
	var summary: String = format_object_state_summary(object_data)
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
	var object_data: Dictionary = world_objects.get_object(target_id)
	var object_name: String = str(object_data.get("name", target_id))
	var current_holder: String = world_objects.get_holder(target_id)
	if current_holder != world_graph.current_location_id:
		append_log("[系统] 当前无法拾取 %s，因为它不在少女所在地点。" % object_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "对象不在当前地点")

	if not world_objects.move_object(target_id, "girl"):
		append_log("[系统] 拾取 %s 失败，系统未能更新其归属。" % object_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "拾取失败")

	append_log("[系统] 少女拾取了 %s，已加入她的物品栏。" % object_name)
	append_log("[少女] 我把 %s 收好了。" % object_name)
	render_graph_data()
	var result := SystemResult.make(SystemResult.TYPE_ITEM_PICKED_UP, true, "已拾取物品")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_PICK_UP
	result.payload = world_objects.get_visible_object(target_id)
	return result


func execute_use_action(target_id: String) -> SystemResult:
	var object_data: Dictionary = world_objects.get_object(target_id)
	var object_name: String = str(object_data.get("name", target_id))
	if world_objects.get_holder(target_id) != "girl":
		append_log("[系统] 当前无法使用 %s，因为它不在少女的物品栏中。" % object_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "对象不在少女物品栏中")

	var object_type: String = str(object_data.get("type", ""))
	if object_type != "food":
		append_log("[系统] 已识别使用 %s 的请求，但当前只实现了 food 类型物品的直接使用。" % object_name)
		var not_implemented := SystemResult.make(SystemResult.TYPE_ACTION_NOT_IMPLEMENTED, false, "当前只实现了食物的直接使用")
		not_implemented.target_object_id = target_id
		not_implemented.action_name = AgentCommandScript.ACTION_USE
		return not_implemented

	var state: Dictionary = object_data.get("state", {})
	var energy: int = int(state.get("energy", 0))
	var previous_satiety: int = girl_satiety
	girl_satiety = clampi(girl_satiety + energy, 0, 100)
	world_objects.remove_object(target_id)
	render_graph_data()

	append_log("[系统] 少女食用了 %s，饱食度从 %d 提升到 %d。" % [object_name, previous_satiety, girl_satiety])
	append_log("[少女] 我把 %s 吃掉了，感觉稍微缓过来一点。" % object_name)

	var result := SystemResult.make(SystemResult.TYPE_ITEM_USED, true, "已使用物品")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_USE
	result.payload = {
		"consumed_item_name": object_name,
		"satiety_before": previous_satiety,
		"satiety_after": girl_satiety,
		"energy": energy
	}
	return result


func execute_use_item_action(target_id: String, params: Dictionary) -> SystemResult:
	var target_object: Dictionary = world_objects.get_object(target_id)
	var target_name: String = str(target_object.get("name", target_id))
	if not can_access_object(target_id):
		append_log("[系统] 当前无法对 %s 使用物品，因为它不在少女可直接操作的范围内。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法对该对象使用物品")

	var item_id: String = str(params.get("item_id", ""))
	if item_id.is_empty() or not world_objects.has_object(item_id):
		append_log("[系统] use_item 指令缺少有效的 item_id。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "use_item 指令缺少有效的 item_id")

	if world_objects.get_holder(item_id) != "girl":
		append_log("[系统] 当前无法使用该物品，因为它不在少女的物品栏中。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "物品不在少女物品栏中")

	var item_object: Dictionary = world_objects.get_object(item_id)
	var item_name: String = str(item_object.get("name", item_id))
	var item_type: String = str(item_object.get("type", ""))
	var target_type: String = str(target_object.get("type", ""))
	if item_type != "battery" or target_type != "device":
		append_log("[系统] 已识别将 %s 用于 %s 的请求，但当前只实现了 battery -> device 的 use_item 逻辑。" % [item_name, target_name])
		var not_implemented := SystemResult.make(SystemResult.TYPE_ACTION_NOT_IMPLEMENTED, false, "当前只实现了 battery -> device 的 use_item 逻辑")
		not_implemented.target_object_id = target_id
		not_implemented.action_name = AgentCommandScript.ACTION_USE_ITEM
		return not_implemented

	var target_state: Dictionary = target_object.get("state", {})
	if not target_state.has("stored_power"):
		append_log("[系统] %s 当前没有可充能的 stored_power 状态。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象没有可充能状态")

	var item_state: Dictionary = item_object.get("state", {})
	var charge: int = int(item_state.get("charge", 0))
	if charge <= 0:
		append_log("[系统] %s 当前没有可用电量。" % item_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "物品没有可用电量")

	var previous_power: int = int(target_state.get("stored_power", 0))
	var new_power: int = clampi(previous_power + charge, 0, 100)
	target_state["stored_power"] = new_power
	world_objects.set_object_state(target_id, target_state)
	world_objects.remove_object(item_id)
	render_graph_data()

	append_log("[系统] 少女将 %s 接入 %s，储能从 %d 提升到 %d。" % [item_name, target_name, previous_power, new_power])
	if target_id == "obj_backup_power_01" and new_power >= 100:
		append_log("[系统] 后备电力系统已充满，现在可以继续切换供电目标。")
	append_log("[少女] 我已经把 %s 接到 %s 上了。设备现在有反应了。" % [item_name, target_name])

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
	var target_object: Dictionary = world_objects.get_object(target_id)
	var target_name: String = str(target_object.get("name", target_id))
	if not can_access_object(target_id):
		append_log("[系统] 当前无法设置 %s，因为它不在少女可直接操作的范围内。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法设置该对象")

	var key: String = str(params.get("key", ""))
	if key.is_empty() or not params.has("value"):
		append_log("[系统] set_value 指令缺少 key 或 value。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "set_value 指令缺少 key 或 value")

	var target_type: String = str(target_object.get("type", ""))
	if target_type != "device":
		append_log("[系统] 当前只允许对 device 类型对象执行 set_value。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前只允许对设备设置数值")

	var target_state: Dictionary = target_object.get("state", {})
	if not target_state.has(key):
		append_log("[系统] %s 当前没有可设置的状态键 %s。" % [target_name, key])
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象没有该状态键")

	if target_id == "obj_backup_power_01":
		return execute_backup_power_set_value(target_id, target_name, key, params.get("value"))

	append_log("[系统] 已识别对 %s 执行 set_value，但当前只实现了后备电力系统的切换逻辑。" % target_name)
	var not_implemented := SystemResult.make(SystemResult.TYPE_ACTION_NOT_IMPLEMENTED, false, "当前只实现了后备电力系统的 set_value 逻辑")
	not_implemented.target_object_id = target_id
	not_implemented.action_name = AgentCommandScript.ACTION_SET_VALUE
	return not_implemented


func execute_backup_power_set_value(target_id: String, target_name: String, key: String, raw_value: Variant) -> SystemResult:
	if key != "power_target_index":
		append_log("[系统] 后备电力系统当前只允许设置 power_target_index。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "后备电力系统当前只允许设置 power_target_index")

	var target_state: Dictionary = world_objects.get_object(target_id).get("state", {})
	var stored_power: int = int(target_state.get("stored_power", 0))
	if stored_power < 100:
		append_log("[系统] 后备电力系统储能不足，当前为 %d，必须达到 100 才能切换供电目标。" % stored_power)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "后备电力系统储能不足")

	var value: int = int(raw_value)
	if value < 0 or value > 5:
		append_log("[系统] power_target_index 超出允许范围，当前只接受 0 到 5。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "power_target_index 超出允许范围")

	var previous_value: int = int(target_state.get("power_target_index", 0))
	target_state["power_target_index"] = value
	world_objects.set_object_state(target_id, target_state)
	update_airlock_power_state(value == 4)
	render_graph_data()

	append_log("[系统] 少女将 %s 的供电目标从 %d 切换为 %d。" % [target_name, previous_value, value])
	if value == 4:
		append_log("[系统] 舱门系统已恢复供电。")
		append_log("[少女] 这个目标切过去之后，右前方那边好像真的有设备启动声。")
	else:
		append_log("[系统] 当前供电目标不是舱门系统，舱门仍未恢复供电。")
		append_log("[少女] 切过去了，但我这边还没有听到舱门那边的明显反应。")

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
		if not unlocked_requirements.has("airlock_power"):
			unlocked_requirements.append("airlock_power")
	else:
		unlocked_requirements.erase("airlock_power")

	var airlock_door: Dictionary = world_objects.get_object("obj_airlock_door_01")
	if not airlock_door.is_empty():
		var airlock_door_state: Dictionary = airlock_door.get("state", {})
		airlock_door_state["powered"] = powered
		world_objects.set_object_state("obj_airlock_door_01", airlock_door_state)

	var airlock_panel: Dictionary = world_objects.get_object("obj_airlock_panel_01")
	if not airlock_panel.is_empty():
		var airlock_panel_state: Dictionary = airlock_panel.get("state", {})
		airlock_panel_state["powered"] = powered
		world_objects.set_object_state("obj_airlock_panel_01", airlock_panel_state)


func execute_open_action(target_id: String) -> SystemResult:
	var target_object: Dictionary = world_objects.get_object(target_id)
	var target_name: String = str(target_object.get("name", target_id))
	if not can_access_object(target_id):
		append_log("[系统] 当前无法开启 %s，因为它不在少女可直接操作的范围内。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前无法开启该对象")

	var target_type: String = str(target_object.get("type", ""))
	if target_type != "door":
		append_log("[系统] 当前只允许对 door 类型对象执行 open。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前只允许对门执行开启操作")

	var target_state: Dictionary = target_object.get("state", {})
	var is_powered: bool = bool(target_state.get("powered", false))
	var is_opened: bool = bool(target_state.get("opened", false))
	if is_opened:
		append_log("[系统] %s 已经处于开启状态。" % target_name)
		var already_opened := SystemResult.make(SystemResult.TYPE_OBJECT_OPENED, true, "对象已经处于开启状态")
		already_opened.target_object_id = target_id
		already_opened.action_name = AgentCommandScript.ACTION_OPEN
		already_opened.payload = world_objects.get_visible_object(target_id)
		return already_opened

	if not is_powered:
		append_log("[系统] %s 当前没有供电，无法开启。" % target_name)
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "目标对象当前没有供电")

	target_state["opened"] = true
	world_objects.set_object_state(target_id, target_state)
	render_graph_data()

	append_log("[系统] %s 已成功开启。" % target_name)
	append_log("[少女] 门开了！外面的路终于通了。")
	if target_id == "obj_airlock_door_01":
		objective_label.text = "目标：穿过舱门离开飞船，开始对外部环境进行探索。"
		system_agent_short_term_goal = "穿过已经开启的舱门，确认飞船外部环境是否安全。"
		system_recent_dialogue_summary = "少女成功开启了舱门，正在准备离开飞船。"

	var result := SystemResult.make(SystemResult.TYPE_OBJECT_OPENED, true, "对象已开启")
	result.target_object_id = target_id
	result.action_name = AgentCommandScript.ACTION_OPEN
	result.payload = world_objects.get_visible_object(target_id)
	return result


func can_access_object(target_id: String) -> bool:
	var holder_id: String = world_objects.get_holder(target_id)
	return holder_id == world_graph.current_location_id or holder_id == "girl"


func execute_move_command(command: AgentCommand) -> SystemResult:
	if is_traveling():
		append_log("[系统] 少女已经在路上了，这条移动指令暂时不能执行。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "少女已经在路上了")

	var target_location_id: String = command.target_location_id
	var target_location_name: String = command.target_location_name
	if target_location_id.is_empty():
		append_log("[系统] 移动指令缺少目标地点。")
		return SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "移动指令缺少目标地点")

	system_agent_desired_location_ids.erase(target_location_id)
	system_agent_desired_location_ids.append(target_location_id)
	system_agent_short_term_goal = "前往 %s 并调查是否存在新的线索" % target_location_name

	var path: Array[String] = world_graph.find_path(world_graph.current_location_id, target_location_id, unlocked_requirements)
	if path.is_empty():
		append_log("[系统] 已收到前往 %s 的请求，但当前没有满足条件的可行路径。" % target_location_name)
		var rejected := SystemResult.make(SystemResult.TYPE_COMMAND_REJECTED, false, "当前找不到满足条件的路径")
		rejected.target_location_id = target_location_id
		return rejected

	if path.size() == 1:
		append_log("[系统] 少女已经位于 %s。" % target_location_name)
		system_agent_desired_location_ids.erase(target_location_id)
		set_investigation_goal(target_location_id)
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
	append_log("[系统] 第一段路线方向：%s，目的地：%s。" % [
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
	append_log("[少女] 我现在从 %s 出发，前往 %s，预计需要 %d 分钟。" % [
		world_graph.get_location(origin_id).get("name", "未知地点"),
		destination.get("name", "未知地点"),
		travel_time
	])
	render_graph_data()


func _on_send_pressed() -> void:
	var message := input_box.text.strip_edges()
	if message.is_empty():
		return
	if agent_request_in_flight:
		append_log("[系统] 少女仍在整理上一条请求的回应，请稍等一下再发送新消息。")
		return
	reset_agent_exchange_timer()
	append_log("[玩家] " + message)
	system_recent_dialogue_summary = "玩家最近一次输入：%s" % message
	var context = build_agent_context()
	append_log("[系统] 已向少女同步世界信息：时间 %s，当前位置 %s。" % [
		context.format_clock(),
		context.current_location_name
	])
	agent_request_in_flight = true
	var agent_output
	if current_agent.is_async():
		agent_output = await current_agent.process_player_message_async(self, message, context, world_graph)
	else:
		agent_output = current_agent.process_player_message(message, context, world_graph)
	agent_request_in_flight = false
	apply_agent_output(agent_output, "[少女]")
	input_box.clear()
	process_pending_system_events()


func _on_send_submitted(_text: String) -> void:
	_on_send_pressed()


func process_pending_system_events() -> void:
	if agent_request_in_flight:
		return
	if pending_system_events.is_empty():
		return
	var next_event = pending_system_events.pop_front()
	_dispatch_system_event_async(next_event)


func _on_quick_action(action_text: String) -> void:
	append_log("[玩家] " + action_text)
	append_log("[系统] 已记录快捷动作，后续可以在这里接入专门的动作解析器。")


func advance_world_time(delta_seconds: int, emit_log: bool = false) -> void:
	world_time_seconds += delta_seconds
	time_label.text = format_clock(world_time_seconds)
	satiety_decay_accumulator_seconds += delta_seconds
	var satiety_changed := false
	while satiety_decay_accumulator_seconds >= 60:
		satiety_decay_accumulator_seconds -= 60
		var next_satiety: int = maxi(girl_satiety - 1, 0)
		if next_satiety == girl_satiety:
			continue
		girl_satiety = next_satiety
		satiety_changed = true
	if satiety_changed:
		render_character_status()
	if is_traveling():
		travel_remaining_seconds -= delta_seconds
		seconds_since_last_agent_exchange = 0
		if travel_remaining_seconds <= 0:
			finish_travel()
		elif emit_log:
			append_log("[系统] 时间推进 %d 秒，少女仍在前往 %s 的路上，还需要 %s。" % [
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
					"少女自主探索已持续五分钟，期间没有新的 U->A 或 S->A 交互。",
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
		append_log("[系统] 少女已经在路上了，请等当前移动结束后再下达新的移动指令。")
		return
	if selected_location_id == world_graph.current_location_id:
		append_log("[系统] 少女已经在这个地点，无需再次移动。")
		return
	execute_move_command(AgentCommandScript.move_to_location(
		selected_location_id,
		str(world_graph.get_location(selected_location_id).get("name", selected_location_id))
	))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
