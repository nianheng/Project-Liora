extends Control

const WorldGraph = preload("res://scripts/core/world_graph.gd")
const WorldObjects = preload("res://scripts/core/world_objects.gd")
const AgentFactory = preload("res://scripts/core/agent_factory.gd")
const AgentRuntimeConfig = preload("res://scripts/core/agent_runtime_config.gd")
const AgentContextScript = preload("res://scripts/core/types/agent_context.gd")
const AgentCommandScript = preload("res://scripts/core/types/agent_command.gd")
const SystemCommandExecutorScript = preload("res://scripts/core/system/system_command_executor.gd")
const WorldRuntimeScript = preload("res://scripts/core/system/world_runtime.gd")

const BG := Color("07111f")
const PANEL := Color("10243a")
const PANEL_ALT := Color("16324c")
const PANEL_MUTED := Color("0c1a2c")
const ACCENT := Color("69e2ff")
const ACCENT_WARM := Color("f4c16f")
const TEXT := Color("ecf7ff")
const TEXT_SOFT := Color("8ea7be")
const ALERT := Color("ff8d74")
const MAP_NODE_SIZE := Vector2(76, 34)
const MAP_GRID_STEP := Vector2(64, 44)
const MAP_CANVAS_MARGIN := Vector2(32, 26)
const MAP_NODE_MIN_GAP := Vector2(18, 14)
const DESIGN_WINDOW_SIZE := Vector2i(2020, 1290)
const MAX_SCREEN_COVERAGE := 0.95


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

	func get_hovered_connection(point: Vector2) -> Dictionary:
		for segment in connection_segments:
			var from_point: Vector2 = segment.get("from", Vector2.ZERO)
			var to_point: Vector2 = segment.get("to", Vector2.ZERO)
			if _distance_to_segment(point, from_point, to_point) <= 8.0:
				return segment
		return {}

	func _distance_to_segment(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
		var segment := to_point - from_point
		var segment_length_squared := segment.length_squared()
		if segment_length_squared <= 0.001:
			return point.distance_to(from_point)
		var t := clampf((point - from_point).dot(segment) / segment_length_squared, 0.0, 1.0)
		var projection := from_point + segment * t
		return point.distance_to(projection)

var world_time_seconds: int = 22 * 3600 + 14 * 60
var paused := false
var world_graph := WorldGraph.new()
var world_objects := WorldObjects.new()
var current_agent = null
var system_command_executor := SystemCommandExecutorScript.new(self)
var world_runtime := WorldRuntimeScript.new(self)
var girl_favorability: int = 42
var girl_satiety: int = 57
var girl_ideology: int = 61
var girl_mood: int = 38
var satiety_decay_accumulator_seconds: int = 0
var system_agent_desired_location_ids: Array[String] = []
var system_agent_short_term_goal: String = "保持通讯稳定并评估周边区域。"
var system_recent_dialogue_summary: String = "玩家与少女刚建立无线电联系，正在规划下一步探索。"
var girl_memory_entries: Array[String] = []
var girl_display_name := "-----"
var girl_identity_revealed := false
var player_display_name := "-----"
var player_name_known := false
var player_name_hint_pending := false
var first_player_u2a_completed := false
var player_name_extraction_attempts := 0
const PLAYER_NAME_EXTRACTION_MAX_ATTEMPTS := 3
var interrupted_player_messages: Array[String] = []
var interrupted_system_events: Array[Dictionary] = []
var agent_request_serial: int = 0
var intro_sequence_serial: int = 0
var intro_playing := false
var active_request_player_messages: Array[String] = []
var active_request_system_events: Array[Dictionary] = []
var selected_location_id := ""
var unlocked_requirements: Array[String] = ["light_source"]
var agent_state: String = "EXPLORING"
var prologue_intro_played := false
var prologue_contact_confirmed := false
var travel_origin_id: String = ""
var travel_destination_id: String = ""
var travel_remaining_seconds: int = 0
var active_travel_connection: Dictionary = {}
var planned_route: Array[String] = []
var seconds_since_last_agent_exchange: int = 0
var auto_explore_interval_seconds: int = 240
var auto_explore_interval_min_seconds: int = 20
var auto_explore_interval_max_seconds: int = 60
var agent_request_in_flight := false
var applying_agent_output := false
var pending_system_events: Array = []
var show_system_messages := false
var world_timer: Timer

var time_label: Label
var status_label: Label
var location_label: Label
var objective_label: Label
var system_log_toggle_button: Button
var map_summary_label: Label
var map_scroll: ScrollContainer
var map_canvas: Control
var map_graph_view
var map_node_layer: Control
var map_node_buttons: Dictionary = {}
var detail_object_list: ItemList
var inventory_list: ItemList
var comms_scroll: ScrollContainer
var comms_message_list: VBoxContainer
var typing_indicator_timer: Timer
var typing_indicator_row: Control
var typing_indicator_body_label: Label
var typing_indicator_dot_count := 0
var input_box: LineEdit
var pause_overlay: ColorRect
var pause_label: Label
var auto_explore_min_spin: SpinBox
var auto_explore_max_spin: SpinBox
var comms_log_entry_count := 0
const COMMS_PLAYER_COLOR := "#F2F5FF"
const COMMS_GIRL_COLOR := "#C9E7FF"
const COMMS_SYSTEM_COLOR := "#8FA6BC"
const COMMS_DEFAULT_COLOR := "#F2F5FF"
var detail_title_label: Label
var detail_description_label: Label
var detail_meta_label: Label
var character_profile_label: Label
var character_status_bars: Dictionary = {}
var character_status_value_labels: Dictionary = {}
var map_drag_pending := false
var map_dragging := false
var map_drag_origin := Vector2.ZERO
var map_scroll_origin := Vector2i.ZERO
var main_split_container: HSplitContainer
var right_outer_split: VSplitContainer
var bottom_row_split: HSplitContainer
var map_lower_split: HSplitContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_startup_window_size()
	world_graph.load_from_file("res://data/world/graph_demo.json")
	world_objects.load_from_file("res://data/world/objects_intro.json")
	current_agent = AgentFactory.create_agent()
	selected_location_id = world_graph.current_location_id
	build_ui()
	resized.connect(_on_ui_resized)
	setup_world_timer()
	setup_typing_indicator_timer()
	render_graph_data()
	clear_comms_log()
	call_deferred("play_first_contact_intro")
	set_process_unhandled_input(true)
	call_deferred("_apply_split_offsets")


func _on_ui_resized() -> void:
	call_deferred("_apply_split_offsets")


func apply_startup_window_size() -> void:
	var window := get_window()
	if window == null:
		return
	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	var max_size := Vector2(usable_rect.size) * MAX_SCREEN_COVERAGE
	var fit_scale := minf(
		max_size.x / float(DESIGN_WINDOW_SIZE.x),
		max_size.y / float(DESIGN_WINDOW_SIZE.y)
	)
	var target_size := Vector2i(
		maxi(1, int(floor(float(DESIGN_WINDOW_SIZE.x) * fit_scale))),
		maxi(1, int(floor(float(DESIGN_WINDOW_SIZE.y) * fit_scale)))
	)
	window.size = target_size
	window.position = usable_rect.position + Vector2i((Vector2(usable_rect.size - target_size) * 0.5).floor())


func _apply_split_offsets() -> void:
	if main_split_container != null:
		main_split_container.split_offset = 0
	if right_outer_split != null and right_outer_split.size.y > 0.0:
		right_outer_split.split_offset = int(right_outer_split.size.y * (9.0 / 13.0) - right_outer_split.size.y * 0.5)
	if bottom_row_split != null and bottom_row_split.size.x > 0.0:
		bottom_row_split.split_offset = int(bottom_row_split.size.x * (50.0 / 77.0) - bottom_row_split.size.x * 0.5)
	if map_lower_split != null and map_lower_split.size.x > 0.0:
		map_lower_split.split_offset = int(map_lower_split.size.x * (50.0 / 77.0) - map_lower_split.size.x * 0.5)


func _input(event: InputEvent) -> void:
	handle_map_drag_input(event)


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

	main_split_container = HSplitContainer.new()
	main_split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main_split_container)

	main_split_container.add_child(build_left_column())
	main_split_container.add_child(build_right_column())

	pause_overlay = build_pause_overlay()
	add_child(pause_overlay)


func setup_world_timer() -> void:
	world_timer = Timer.new()
	world_timer.wait_time = 1.0
	world_timer.one_shot = false
	world_timer.autostart = true
	world_timer.timeout.connect(_on_world_tick)
	add_child(world_timer)


func setup_typing_indicator_timer() -> void:
	typing_indicator_timer = Timer.new()
	typing_indicator_timer.wait_time = 0.50
	typing_indicator_timer.one_shot = false
	typing_indicator_timer.autostart = false
	typing_indicator_timer.timeout.connect(_on_typing_indicator_tick)
	add_child(typing_indicator_timer)


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
	title.text = "Project Liora // Planetfall"
	title.add_theme_font_size_override("font_size", 30)
	title_box.add_child(title)

	objective_label = Label.new()
	objective_label.text = "目标：建立稳定通讯，协助少女确认飞船现状。"

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
	pause_button.text = "⚙ 设置"
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

	comms_column.add_child(make_section_title("通讯终端", ""))

	comms_scroll = ScrollContainer.new()
	comms_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comms_scroll.custom_minimum_size = Vector2(0, 320)
	comms_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	comms_column.add_child(comms_scroll)

	comms_message_list = VBoxContainer.new()
	comms_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comms_message_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	comms_message_list.custom_minimum_size.x = 1
	comms_message_list.add_theme_constant_override("separation", 14)
	comms_scroll.add_child(comms_message_list)

	var input_label := Label.new()
	input_label.text = "发送消息"
	input_label.modulate = TEXT_SOFT
	comms_column.add_child(input_label)

	input_box = LineEdit.new()
	input_box.custom_minimum_size = Vector2(0, 42)
	input_box.placeholder_text = ""
	input_box.add_theme_font_size_override("font_size", 23)
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
	right_outer_split = VSplitContainer.new()
	right_outer_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_outer_split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	right_outer_split.add_child(build_map_panel())

	bottom_row_split = HSplitContainer.new()
	bottom_row_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_row_split.add_child(build_character_panel())
	bottom_row_split.add_child(build_media_panel())
	right_outer_split.add_child(bottom_row_split)

	return right_outer_split


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

	column.add_child(make_section_title("地图与地点", "上半部分显示地图；下半部分显示当前地点的详情和内容。"))

	map_summary_label = Label.new()
	map_summary_label.modulate = TEXT_SOFT
	column.add_child(map_summary_label)

	map_scroll = ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.custom_minimum_size = Vector2(0, 180)
	map_scroll.clip_contents = true
	map_scroll.follow_focus = false
	map_scroll.get_h_scroll_bar().modulate = Color(1, 1, 1, 0)
	map_scroll.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	map_scroll.get_h_scroll_bar().custom_minimum_size = Vector2(0, 0)
	map_scroll.get_v_scroll_bar().custom_minimum_size = Vector2(0, 0)
	column.add_child(map_scroll)

	map_canvas = Control.new()
	map_canvas.custom_minimum_size = Vector2(520, 240)
	map_scroll.add_child(map_canvas)

	map_graph_view = MapGraphView.new()
	map_graph_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_graph_view.mouse_filter = Control.MOUSE_FILTER_STOP
	map_graph_view.anchor_right = 1.0
	map_graph_view.anchor_bottom = 1.0
	map_graph_view.offset_right = 0.0
	map_graph_view.offset_bottom = 0.0
	map_graph_view.gui_input.connect(_on_map_graph_gui_input)
	map_graph_view.mouse_exited.connect(_clear_map_hover_summary)
	map_canvas.add_child(map_graph_view)

	map_node_layer = Control.new()
	map_node_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_node_layer.anchor_right = 1.0
	map_node_layer.anchor_bottom = 1.0
	map_node_layer.offset_right = 0.0
	map_node_layer.offset_bottom = 0.0
	map_canvas.add_child(map_node_layer)

	map_lower_split = HSplitContainer.new()
	map_lower_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(map_lower_split)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_lower_split.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 14)
	detail_margin.add_theme_constant_override("margin_top", 14)
	detail_margin.add_theme_constant_override("margin_right", 14)
	detail_margin.add_theme_constant_override("margin_bottom", 14)
	detail_panel.add_child(detail_margin)

	var detail_column := VBoxContainer.new()
	detail_margin.add_child(detail_column)

	detail_title_label = Label.new()
	detail_title_label.add_theme_font_size_override("font_size", 22)
	detail_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(detail_title_label)

	detail_meta_label = Label.new()
	detail_meta_label.modulate = TEXT_SOFT
	detail_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_column.add_child(detail_meta_label)

	detail_description_label = Label.new()
	detail_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(detail_description_label)

	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_lower_split.add_child(content_panel)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_top", 14)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_bottom", 14)
	content_panel.add_child(content_margin)

	var content_column := VBoxContainer.new()
	content_margin.add_child(content_column)

	var content_header := Label.new()
	content_header.text = "地点内容"
	content_header.modulate = TEXT_SOFT
	content_column.add_child(content_header)

	detail_object_list = ItemList.new()
	detail_object_list.custom_minimum_size = Vector2(0, 120)
	detail_object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_column.add_child(detail_object_list)

	return panel


func build_character_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	column.add_child(make_section_title("任务状态", "这里显示当前目标，以及少女当前最关键的状态。"))

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

	return panel


func build_media_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
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
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)

	pause_label = Label.new()
	pause_label.text = "游戏时间已停止。这里后续可以放设置、存档、任务日志和系统说明。"
	pause_label.modulate = TEXT_SOFT
	pause_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(pause_label)

	column.add_child(build_auto_explore_interval_settings())

	for text in ["继续", "保存占位", "设置占位"]:
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(0, 42)
		if text == "继续":
			button.pressed.connect(toggle_pause)
		column.add_child(button)

	return overlay


func build_auto_explore_interval_settings() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", make_panel_style(PANEL_MUTED, 10, PANEL_ALT))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "少女等待时间范围"
	title.modulate = TEXT
	column.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	row.add_child(make_settings_label("最短"))
	auto_explore_min_spin = make_interval_spin_box(auto_explore_interval_min_seconds)
	auto_explore_min_spin.value_changed.connect(_on_auto_explore_min_changed)
	row.add_child(auto_explore_min_spin)

	row.add_child(make_settings_label("最长"))
	auto_explore_max_spin = make_interval_spin_box(auto_explore_interval_max_seconds)
	auto_explore_max_spin.value_changed.connect(_on_auto_explore_max_changed)
	row.add_child(auto_explore_max_spin)

	var unit_label := Label.new()
	unit_label.text = "秒"
	unit_label.modulate = TEXT_SOFT
	row.add_child(unit_label)

	return panel


func make_settings_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = TEXT_SOFT
	return label


func make_interval_spin_box(value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 10
	spin.max_value = 1800
	spin.step = 10
	spin.value = value
	spin.custom_minimum_size = Vector2(96, 36)
	return spin


func _on_auto_explore_min_changed(value: float) -> void:
	auto_explore_interval_min_seconds = int(value)
	if auto_explore_interval_min_seconds > auto_explore_interval_max_seconds:
		auto_explore_interval_max_seconds = auto_explore_interval_min_seconds
		if auto_explore_max_spin != null:
			auto_explore_max_spin.set_value_no_signal(auto_explore_interval_max_seconds)
	auto_explore_interval_seconds = clampi(
		auto_explore_interval_seconds,
		auto_explore_interval_min_seconds,
		auto_explore_interval_max_seconds
	)


func _on_auto_explore_max_changed(value: float) -> void:
	auto_explore_interval_max_seconds = int(value)
	if auto_explore_interval_max_seconds < auto_explore_interval_min_seconds:
		auto_explore_interval_min_seconds = auto_explore_interval_max_seconds
		if auto_explore_min_spin != null:
			auto_explore_min_spin.set_value_no_signal(auto_explore_interval_min_seconds)
	auto_explore_interval_seconds = clampi(
		auto_explore_interval_seconds,
		auto_explore_interval_min_seconds,
		auto_explore_interval_max_seconds
	)


func render_graph_data() -> void:
	render_header()
	render_map_list()
	render_character_status()
	render_location_detail()
	render_clues()
	render_inventory()


func render_header() -> void:
	var current_location: Dictionary = world_graph.get_current_location()
	time_label.text = format_clock(world_time_seconds)
	status_label.text = "少女状态: %s" % agent_state
	if world_runtime.is_traveling():
		var from_name: String = str(world_graph.get_location(travel_origin_id).get("name", "--"))
		var to_name: String = str(world_graph.get_location(travel_destination_id).get("name", "--"))
		location_label.text = "当前位置: %s -> %s" % [from_name, to_name]
	else:
		location_label.text = "当前位置: %s" % current_location.get("name", "--")
	map_summary_label.text = "将鼠标移动到地点或道路上可查看探索与通行信息。"


func render_character_status() -> void:
	if character_profile_label != null:
		character_profile_label.text = "主目标：%s\n当前目标：%s" % [
			objective_label.text.replace("目标：", ""),
			system_agent_short_term_goal
		]

	_update_status_meter("favorability", girl_favorability, "保留")
	_update_status_meter("satiety", girl_satiety, "稳定")


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
		button.position = positions.get(location_id, Vector2.ZERO)
		button.size = MAP_NODE_SIZE
		button.text = str(world_graph.get_location(location_id).get("name", ""))
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
				"width": 3.0,
				"travel_time": int(neighbor.get("travel_time", 0)),
				"from_name": str(neighbor.get("from_name", world_graph.get_location(from_id).get("name", from_id))),
				"to_name": str(neighbor.get("to_name", to_id))
			})

	if world_runtime.is_traveling():
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
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_map_node_pressed.bind(location_id))
		button.mouse_entered.connect(_on_map_node_hovered.bind(location_id))
		button.mouse_exited.connect(_clear_map_hover_summary)
		map_node_layer.add_child(button)
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

	var positions: Dictionary = {}
	var centers: Dictionary = {}
	var content_width: float = (max_x - min_x) * MAP_GRID_STEP.x + MAP_NODE_SIZE.x + MAP_CANVAS_MARGIN.x * 2.0
	var content_height: float = (max_y - min_y) * MAP_GRID_STEP.y + MAP_NODE_SIZE.y + MAP_CANVAS_MARGIN.y * 2.0
	if map_canvas != null:
		map_canvas.custom_minimum_size = Vector2(
			maxf(content_width, 520.0),
			maxf(content_height, 240.0)
		)

	for location_id in ids:
		var raw_position: Vector2 = raw_positions[location_id]
		var final_position := Vector2(
			MAP_CANVAS_MARGIN.x + (raw_position.x - min_x) * MAP_GRID_STEP.x,
			MAP_CANVAS_MARGIN.y + (max_y - raw_position.y) * MAP_GRID_STEP.y
		)
		positions[location_id] = final_position
	centers = _resolve_map_node_overlap(ids, positions)

	return {
		"positions": positions,
		"centers": centers
	}


func _resolve_map_node_overlap(ids: Array[String], positions: Dictionary) -> Dictionary:
	var adjusted_positions: Dictionary = {}
	var min_dx: float = MAP_NODE_SIZE.x + MAP_NODE_MIN_GAP.x
	var min_dy: float = MAP_NODE_SIZE.y + MAP_NODE_MIN_GAP.y

	for location_id in ids:
		adjusted_positions[location_id] = positions[location_id]

	for _pass in range(6):
		var moved := false
		for index_a in range(ids.size()):
			for index_b in range(index_a + 1, ids.size()):
				var id_a: String = ids[index_a]
				var id_b: String = ids[index_b]
				var pos_a: Vector2 = adjusted_positions[id_a]
				var pos_b: Vector2 = adjusted_positions[id_b]
				var delta: Vector2 = pos_b - pos_a
				var overlap_x: float = min_dx - absf(delta.x)
				var overlap_y: float = min_dy - absf(delta.y)
				if overlap_x <= 0.0 or overlap_y <= 0.0:
					continue

				if absf(delta.x) >= absf(delta.y):
					var push_x: float = overlap_x * 0.5
					if delta.x >= 0.0:
						pos_a.x -= push_x
						pos_b.x += push_x
					else:
						pos_a.x += push_x
						pos_b.x -= push_x
				else:
					var push_y: float = overlap_y * 0.5
					if delta.y >= 0.0:
						pos_a.y -= push_y
						pos_b.y += push_y
					else:
						pos_a.y += push_y
						pos_b.y -= push_y

				adjusted_positions[id_a] = pos_a
				adjusted_positions[id_b] = pos_b
				moved = true
		if not moved:
			break

	var min_pos := Vector2(999999.0, 999999.0)
	var max_pos := Vector2(-999999.0, -999999.0)
	for location_id in ids:
		var adjusted: Vector2 = adjusted_positions[location_id]
		min_pos.x = minf(min_pos.x, adjusted.x)
		min_pos.y = minf(min_pos.y, adjusted.y)
		max_pos.x = maxf(max_pos.x, adjusted.x)
		max_pos.y = maxf(max_pos.y, adjusted.y)

	var shift := Vector2.ZERO
	if min_pos.x < MAP_CANVAS_MARGIN.x:
		shift.x = MAP_CANVAS_MARGIN.x - min_pos.x
	if min_pos.y < MAP_CANVAS_MARGIN.y:
		shift.y = MAP_CANVAS_MARGIN.y - min_pos.y
	min_pos += shift
	max_pos += shift

	var content_size := Vector2(
		max_pos.x - min_pos.x + MAP_NODE_SIZE.x + MAP_CANVAS_MARGIN.x,
		max_pos.y - min_pos.y + MAP_NODE_SIZE.y + MAP_CANVAS_MARGIN.y
	)
	var viewport_size := Vector2(520.0, 240.0)
	if map_scroll != null and map_scroll.size.x > 0.0 and map_scroll.size.y > 0.0:
		viewport_size = map_scroll.size

	var canvas_size := Vector2(
		maxf(content_size.x, viewport_size.x),
		maxf(content_size.y, viewport_size.y)
	)
	if map_canvas != null:
		map_canvas.custom_minimum_size = canvas_size

	var center_shift := Vector2.ZERO
	if content_size.x < canvas_size.x:
		center_shift.x = (canvas_size.x - content_size.x) * 0.5
	if content_size.y < canvas_size.y:
		center_shift.y = (canvas_size.y - content_size.y) * 0.5

	var centers: Dictionary = {}
	for location_id in ids:
		var final_position: Vector2 = adjusted_positions[location_id] + shift + center_shift
		positions[location_id] = final_position
		centers[location_id] = final_position + MAP_NODE_SIZE * 0.5

	return centers


func _style_map_node_button(button: Button, location_id: String) -> void:
	var fill: Color = PANEL_ALT
	var border: Color = Color("35536f")
	if location_id == world_graph.current_location_id:
		border = ACCENT
	elif location_id == selected_location_id:
		border = ACCENT_WARM

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

	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", make_panel_style(fill, 14, border))
	button.add_theme_stylebox_override("hover", make_panel_style(fill.lightened(0.08), 14, ACCENT_WARM))
	button.add_theme_stylebox_override("pressed", make_panel_style(fill.darkened(0.08), 14, ACCENT_WARM))


func handle_map_drag_input(event: InputEvent) -> void:
	if map_scroll == null:
		return
	var map_rect := map_scroll.get_global_rect()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if map_rect.has_point(event.global_position):
				map_drag_pending = true
				map_dragging = false
				map_drag_origin = event.global_position
				map_scroll_origin = Vector2i(map_scroll.scroll_horizontal, map_scroll.scroll_vertical)
		else:
			if map_dragging:
				get_viewport().set_input_as_handled()
			map_drag_pending = false
			map_dragging = false
	elif event is InputEventMouseMotion and (map_drag_pending or map_dragging):
		if not map_dragging:
			if not map_rect.has_point(map_drag_origin):
				map_drag_pending = false
				return
			if event.global_position.distance_to(map_drag_origin) < 8.0:
				return
			map_dragging = true
		var delta: Vector2 = event.global_position - map_drag_origin
		map_scroll.scroll_horizontal = map_scroll_origin.x - int(delta.x)
		map_scroll.scroll_vertical = map_scroll_origin.y - int(delta.y)
		get_viewport().set_input_as_handled()


func _on_map_node_pressed(location_id: String) -> void:
	selected_location_id = location_id
	render_map_list()
	render_location_detail()
	render_clues()

func _on_map_node_hovered(location_id: String) -> void:
	var location: Dictionary = world_graph.get_location(location_id)
	var can_travel_result: Dictionary = world_graph.can_travel(world_graph.current_location_id, location_id, unlocked_requirements)
	if location_id == world_graph.current_location_id:
		map_summary_label.text = "%s | 当前所在地点" % str(location.get("name", location_id))
		return
	var can_explore_text := "可以探索"
	var can_travel_text := "可以通行"
	if not bool(can_travel_result.get("allowed", false)):
		can_travel_text = "不可以通行"
	map_summary_label.text = "%s | %s | %s" % [
		str(location.get("name", location_id)),
		can_explore_text,
		can_travel_text
	]


func _on_map_graph_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered_segment: Dictionary = map_graph_view.get_hovered_connection(event.position)
		if hovered_segment.is_empty():
			_clear_map_hover_summary()
			return
		map_summary_label.text = "道路 %s -> %s | 移动时间: %d 分钟" % [
			str(hovered_segment.get("from_name", "--")),
			str(hovered_segment.get("to_name", "--")),
			int(hovered_segment.get("travel_time", 0))
		]


func _clear_map_hover_summary() -> void:
	if map_summary_label != null:
		map_summary_label.text = "将鼠标移动到地点或道路上可查看探索与通行信息。"


func render_location_detail() -> void:
	if world_runtime.is_traveling():
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
	detail_meta_label.text = "当前地点内容: %d 项" % world_objects.get_location_objects(selected_location_id).size()
	detail_description_label.text = str(location.get("description", ""))


func render_clues() -> void:
	if detail_object_list == null:
		return
	detail_object_list.clear()
	if world_runtime.is_traveling():
		detail_object_list.add_item("道路 | 起点 | %s" % world_graph.get_location(travel_origin_id).get("name", "--"))
		detail_object_list.add_item("道路 | 终点 | %s" % world_graph.get_location(travel_destination_id).get("name", "--"))
		detail_object_list.add_item("道路 | 方向 | %s" % active_travel_connection.get("direction_label", ""))
		detail_object_list.add_item("道路 | 剩余时间 | %s" % format_duration(travel_remaining_seconds))
		var travel_requirements: Array = active_travel_connection.get("requirements", [])
		var travel_requirement_text: String = "无" if travel_requirements.is_empty() else ", ".join(travel_requirements)
		detail_object_list.add_item("道路 | 通行条件 | %s" % travel_requirement_text)
		return
	for object_data in world_objects.get_location_objects(selected_location_id):
		detail_object_list.add_item(format_object_list_entry(object_data))
	if detail_object_list.item_count == 0:
		detail_object_list.add_item("当前地点没有可见对象。")


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


func play_first_contact_intro() -> void:
	if prologue_intro_played:
		return
	prologue_intro_played = true
	intro_sequence_serial += 1
	var current_intro_serial := intro_sequence_serial
	intro_playing = true
	objective_label.text = "目标：回应无线电呼叫，先与少女建立稳定通讯。"
	system_agent_short_term_goal = "先确认无线电另一端是否有人稳定回应。"
	system_recent_dialogue_summary = "少女正在通过无线电反复尝试呼叫未知对象，希望确认通讯另一端是否真的有人存在。"
	await wait_for_game_seconds(1.0)
	if current_intro_serial != intro_sequence_serial:
		stop_intro_sequence_after_interrupt()
		return
	var opening_lines := [
		"Hello?",
		"Allô ?",
		"Hallo?",
		"Алло ?",
		"여보세요?",
		"もしもし？",
		"有人吗？",
		"如果你能听见，随便回我一句什么都行。哪怕一个字也行。"
	]
	for index in range(opening_lines.size()):
		var line: String = opening_lines[index]
		if current_intro_serial != intro_sequence_serial:
			stop_intro_sequence_after_interrupt()
			return
		show_typing_indicator()
		await wait_for_game_seconds(get_scripted_line_delay_seconds(line))
		if current_intro_serial != intro_sequence_serial:
			stop_intro_sequence_after_interrupt()
			return
		hide_typing_indicator()
		append_scripted_girl_line(line)
	intro_playing = false
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


func append_log(message: String, speaker_kind: String = "") -> void:
	if not show_system_messages and message.begins_with("[系统]"):
		return
	var message_parts := _split_comms_message(message)
	var body_text: String = str(message_parts.get("body", "")).strip_edges()
	if body_text.is_empty():
		return
	var speaker_text: String = str(message_parts.get("speaker", "")).strip_edges()
	var message_color := Color.html(_get_comms_message_color(message, speaker_kind))
	var message_row := HBoxContainer.new()
	message_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_row.add_theme_constant_override("separation", 8)

	var speaker_label := Label.new()
	speaker_label.text = speaker_text
	speaker_label.custom_minimum_size = Vector2(92, 0)
	speaker_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	speaker_label.add_theme_color_override("font_color", message_color)
	speaker_label.add_theme_font_size_override("font_size", 23)
	message_row.add_child(speaker_label)

	var body_label := Label.new()
	body_label.text = body_text
	body_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_label.add_theme_color_override("font_color", message_color)
	body_label.add_theme_font_size_override("font_size", 23)
	message_row.add_child(body_label)

	comms_message_list.add_child(message_row)
	comms_log_entry_count += 1
	call_deferred("_scroll_comms_to_bottom")


func clear_comms_log() -> void:
	hide_typing_indicator()
	if comms_message_list == null:
		comms_log_entry_count = 0
		return
	for child in comms_message_list.get_children():
		child.queue_free()
	comms_log_entry_count = 0


func _scroll_comms_to_bottom() -> void:
	if comms_scroll == null:
		return
	await get_tree().process_frame
	if comms_scroll == null:
		return
	var vertical_bar := comms_scroll.get_v_scroll_bar()
	vertical_bar.value = vertical_bar.max_value


func show_typing_indicator() -> void:
	if comms_message_list == null:
		return
	if typing_indicator_row != null:
		_scroll_comms_to_bottom()
		return
	typing_indicator_dot_count = 0
	var message_color := Color.html(COMMS_GIRL_COLOR)
	typing_indicator_row = HBoxContainer.new()
	typing_indicator_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	typing_indicator_row.add_theme_constant_override("separation", 8)

	var speaker_label := Label.new()
	speaker_label.text = get_girl_speaker_prefix()
	speaker_label.custom_minimum_size = Vector2(92, 0)
	speaker_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	speaker_label.add_theme_color_override("font_color", message_color)
	speaker_label.add_theme_font_size_override("font_size", 23)
	typing_indicator_row.add_child(speaker_label)

	typing_indicator_body_label = Label.new()
	typing_indicator_body_label.text = "·"
	typing_indicator_body_label.add_theme_color_override("font_color", message_color)
	typing_indicator_body_label.add_theme_font_size_override("font_size", 23)
	typing_indicator_row.add_child(typing_indicator_body_label)

	comms_message_list.add_child(typing_indicator_row)
	if typing_indicator_timer != null:
		typing_indicator_timer.start()
	_on_typing_indicator_tick()
	call_deferred("_scroll_comms_to_bottom")


func hide_typing_indicator() -> void:
	if typing_indicator_timer != null:
		typing_indicator_timer.stop()
	if typing_indicator_row != null:
		typing_indicator_row.queue_free()
	typing_indicator_row = null
	typing_indicator_body_label = null
	typing_indicator_dot_count = 0


func interrupt_intro_sequence() -> void:
	if not intro_playing:
		return
	intro_sequence_serial += 1
	intro_playing = false
	hide_typing_indicator()


func stop_intro_sequence_after_interrupt() -> void:
	intro_playing = false
	hide_typing_indicator()


func _on_typing_indicator_tick() -> void:
	if typing_indicator_body_label == null:
		return
	typing_indicator_dot_count = typing_indicator_dot_count % 4 + 1
	typing_indicator_body_label.text = "·".repeat(typing_indicator_dot_count)
	call_deferred("_scroll_comms_to_bottom")


func _split_comms_message(message: String) -> Dictionary:
	var speaker := ""
	var body := message
	if message.begins_with("["):
		var closing_index := message.find("]")
		if closing_index > 1:
			speaker = message.substr(0, closing_index + 1)
			body = message.substr(closing_index + 1).strip_edges()
	return {
		"speaker": speaker,
		"body": body
	}


func _get_comms_message_color(message: String, speaker_kind: String = "") -> String:
	match speaker_kind:
		"system":
			return COMMS_SYSTEM_COLOR
		"player":
			return COMMS_PLAYER_COLOR
		"girl":
			return COMMS_GIRL_COLOR
	var speaker_tag := _extract_comms_speaker_tag(message)
	if speaker_tag == "系统":
		return COMMS_SYSTEM_COLOR
	if speaker_tag == player_display_name or speaker_tag == "You":
		return COMMS_PLAYER_COLOR
	if speaker_tag == girl_display_name or speaker_tag == "Liora":
		return COMMS_GIRL_COLOR
	return COMMS_DEFAULT_COLOR


func _extract_comms_speaker_tag(message: String) -> String:
	if not message.begins_with("["):
		return ""
	var closing_index := message.find("]")
	if closing_index <= 1:
		return ""
	return message.substr(1, closing_index - 1)


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


func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if world_timer != null:
		world_timer.paused = paused
	pause_overlay.visible = paused


func record_interrupted_player_message(message: String) -> void:
	var normalized := message.strip_edges()
	if normalized.is_empty():
		return
	interrupted_player_messages.append(normalized)


func record_interrupted_system_event(event) -> void:
	if event == null:
		return
	interrupted_system_events.append({
		"event_type": str(event.event_type),
		"summary_text": str(event.summary_text),
		"payload": event.payload
	})


func snapshot_system_event(event) -> Dictionary:
	if event == null:
		return {}
	return {
		"event_type": str(event.event_type),
		"summary_text": str(event.summary_text),
		"payload": event.payload.duplicate(true)
	}


func capture_active_request_snapshot(context, player_message: String = "", event = null) -> void:
	active_request_player_messages = context.interrupted_player_messages.duplicate()
	active_request_system_events = context.interrupted_system_events.duplicate(true)
	var normalized_message := player_message.strip_edges()
	if not normalized_message.is_empty():
		active_request_player_messages.append(normalized_message)
	var event_snapshot := snapshot_system_event(event)
	if not event_snapshot.is_empty():
		active_request_system_events.append(event_snapshot)


func clear_active_request_snapshot() -> void:
	active_request_player_messages.clear()
	active_request_system_events.clear()


func interrupt_active_agent_request() -> void:
	if not agent_request_in_flight:
		return
	hide_typing_indicator()
	for message in active_request_player_messages:
		record_interrupted_player_message(message)
	for event_data in active_request_system_events:
		interrupted_system_events.append(event_data.duplicate(true))
	agent_request_serial += 1
	clear_active_request_snapshot()
	agent_request_in_flight = false


func is_request_serial_current(request_serial: int) -> bool:
	return request_serial == agent_request_serial


func build_agent_context(trigger_type: String = AgentContextScript.TRIGGER_PLAYER_MESSAGE, trigger_reason: String = "player_submitted_message"):
	var context = AgentContextScript.new()
	context.trigger_type = trigger_type
	context.trigger_reason = trigger_reason
	context.world_time_seconds = world_time_seconds
	context.agent_state = agent_state
	context.character_status = {
		"favorability": girl_favorability,
		"satiety": girl_satiety,
		"ideology": girl_ideology,
		"mood": girl_mood
	}
	context.hunger_prompt_hint = get_hunger_prompt_hint()
	context.auto_explore_interval_seconds = auto_explore_interval_seconds
	context.auto_explore_interval_min_seconds = auto_explore_interval_min_seconds
	context.auto_explore_interval_max_seconds = auto_explore_interval_max_seconds
	context.short_term_goal = system_agent_short_term_goal
	context.recent_dialogue_summary = system_recent_dialogue_summary
	context.desired_location_ids = system_agent_desired_location_ids.duplicate()
	context.memory_entries = girl_memory_entries.duplicate()
	context.player_display_name = player_display_name
	context.should_ask_player_name_hint = not first_player_u2a_completed
	context.interrupted_player_messages = interrupted_player_messages.duplicate()
	context.interrupted_system_events = interrupted_system_events.duplicate()
	interrupted_player_messages.clear()
	interrupted_system_events.clear()
	context.current_location_objects = build_visible_objects_for_holder(world_graph.current_location_id)
	context.inventory_objects = build_visible_objects_for_holder("girl")
	context.allowed_command_types.clear()
	context.allowed_command_types.append(AgentCommandScript.TYPE_MOVE_TO_LOCATION)
	context.allowed_command_types.append(AgentCommandScript.TYPE_ACT)
	context.allowed_command_types.append(AgentCommandScript.TYPE_SET_AUTO_EXPLORE_INTERVAL)

	if world_runtime.is_traveling():
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

	context.visible_routes = build_visible_routes_snapshot(world_graph.current_location_id)

	return context


func start_player_agent_request(message: String) -> void:
	_run_player_agent_request_async(message)


func start_system_event_agent_request(event) -> void:
	_run_system_event_agent_request_async(event)


func _run_player_agent_request_async(message: String) -> void:
	var context = build_agent_context()
	var source_memory_entry := build_player_memory_entry(message, context.current_location_name)
	var consumed_memory_entries := build_consumed_request_memory_entries(context, source_memory_entry)
	append_log("[系统] 已向少女同步世界信息：时间 %s，当前位置 %s。" % [
		context.format_clock(),
		context.current_location_name
	])
	agent_request_serial += 1
	var request_serial := agent_request_serial
	agent_request_in_flight = true
	capture_active_request_snapshot(context, message, null)
	var agent_output
	if current_agent.is_async():
		agent_output = await current_agent.process_player_message_async(self, message, context, world_graph)
	else:
		agent_output = current_agent.process_player_message(message, context, world_graph)
	if not is_request_serial_current(request_serial):
		return
	commit_request_memory_entries(consumed_memory_entries)
	clear_active_request_snapshot()
	await apply_agent_output(agent_output, "[少女]", request_serial)
	if not is_request_serial_current(request_serial):
		return
	if not first_player_u2a_completed:
		first_player_u2a_completed = true
		player_name_hint_pending = true
	if player_name_hint_pending and not player_name_known:
		player_name_extraction_attempts += 1
		var extracted_player_name := ""
		if current_agent.is_async():
			extracted_player_name = await current_agent.extract_player_name_async(self, build_player_name_extraction_source())
		if not is_request_serial_current(request_serial):
			return
		if extracted_player_name.strip_edges().is_empty():
			if player_name_extraction_attempts >= PLAYER_NAME_EXTRACTION_MAX_ATTEMPTS:
				finalize_player_name_fallback()
		else:
			apply_player_name_if_detected(extracted_player_name)
	agent_request_in_flight = false
	clear_active_request_snapshot()
	reset_agent_exchange_timer()
	process_pending_system_events()


func _run_system_event_agent_request_async(event) -> void:
	var context = build_agent_context(AgentContextScript.TRIGGER_SYSTEM_EVENT, str(event.event_type))
	var source_memory_entry := build_system_event_memory_entry(event, context.current_location_name)
	var consumed_memory_entries := build_consumed_request_memory_entries(context, source_memory_entry)
	append_log("[系统] 已触发 S->A 事件：%s" % str(event.summary_text))
	system_recent_dialogue_summary = "最近一次系统事件：%s" % str(event.summary_text)
	agent_request_serial += 1
	var request_serial := agent_request_serial
	agent_request_in_flight = true
	capture_active_request_snapshot(context, "", event)
	var agent_output
	if current_agent.is_async():
		agent_output = await current_agent.process_system_event_async(self, event, context, world_graph)
	else:
		agent_output = current_agent.process_system_event(event, context, world_graph)
	if not is_request_serial_current(request_serial):
		return
	commit_request_memory_entries(consumed_memory_entries)
	clear_active_request_snapshot()
	await apply_agent_output(agent_output, "[少女]", request_serial)
	if not is_request_serial_current(request_serial):
		return
	agent_request_in_flight = false
	clear_active_request_snapshot()
	reset_agent_exchange_timer()
	process_pending_system_events()


func build_visible_objects_for_holder(holder_id: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for object_data in world_objects.get_objects_by_holder(holder_id):
		var object_id: String = str(object_data.get("instance_id", ""))
		if object_id.is_empty():
			continue
		results.append(world_objects.get_visible_object(object_id))
	return results


func append_girl_memory_input(entry: String) -> void:
	var normalized: String = entry.strip_edges()
	if normalized.is_empty():
		return
	girl_memory_entries.append(normalized)


func append_girl_memory_reply_line(reply_text: String) -> void:
	var normalized_reply: String = reply_text.strip_edges()
	if normalized_reply.is_empty():
		return
	var lines: Array[String] = ["[少女回复]", "文本: %s" % normalized_reply]
	girl_memory_entries.append("\n".join(lines))


func append_girl_memory_reply_commands(commands: Array = []) -> void:
	var command_summary: String = JSON.stringify(_serialize_agent_commands(commands))
	if command_summary == "[]":
		return
	var lines: Array[String] = ["[少女回复]", "指令集: %s" % command_summary]
	girl_memory_entries.append("\n".join(lines))

func get_girl_speaker_prefix() -> String:
	return "[%s]" % girl_display_name


func get_player_speaker_prefix() -> String:
	return "[%s]" % player_display_name


func update_girl_display_identity_from_text(text: String) -> void:
	if girl_identity_revealed:
		return
	if text.find("Liora") != -1:
		girl_identity_revealed = true
		girl_display_name = "Liora"


func split_reply_text_into_lines(reply_text: String) -> Array[String]:
	var lines: Array[String] = []
	for raw_line_variant in reply_text.split("\n", false):
		var raw_line: String = str(raw_line_variant)
		var line := raw_line.strip_edges()
		if not line.is_empty():
			lines.append(line)
	return lines


func wait_for_game_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds, false).timeout


func display_girl_reply_lines(reply_text: String, trigger_label: String, request_serial: int = -1) -> void:
	var lines := split_reply_text_into_lines(reply_text)
	if lines.is_empty():
		return
	for index in range(lines.size()):
		var line: String = lines[index]
		if request_serial != -1 and not is_request_serial_current(request_serial):
			return
		show_typing_indicator()
		await wait_for_game_seconds(get_scripted_line_delay_seconds(line))
		if request_serial != -1 and not is_request_serial_current(request_serial):
			return
		update_girl_display_identity_from_text(line)
		var normalized_trigger_label := trigger_label
		if trigger_label == "[少女]" or trigger_label == "[Liora]" or trigger_label == "[-----]":
			normalized_trigger_label = get_girl_speaker_prefix()
		hide_typing_indicator()
		append_log("%s %s" % [normalized_trigger_label, line], "girl")
		append_girl_memory_reply_line(line)

func apply_player_name_if_detected(candidate_name: String) -> void:
	var normalized_name := candidate_name.strip_edges()
	if normalized_name.is_empty():
		return
	player_name_known = true
	player_name_hint_pending = false
	player_display_name = normalized_name


func finalize_player_name_fallback() -> void:
	player_name_known = true
	player_name_hint_pending = false
	player_display_name = "You"


func build_player_name_extraction_source() -> String:
	return "\n\n".join(girl_memory_entries)


func append_scripted_girl_line(line_text: String) -> void:
	update_girl_display_identity_from_text(line_text)
	append_log("%s %s" % [get_girl_speaker_prefix(), line_text], "girl")
	append_girl_memory_reply_line(line_text)


func get_scripted_line_delay_seconds(line_text: String, base_delay: float = 0.5, per_char_delay: float = 0.15, max_delay: float = 5.2) -> float:
	var content_length := line_text.strip_edges().length()
	var jitter := randf_range(-0.3, 0.3)
	return clampf(base_delay + float(content_length) * per_char_delay + jitter, 0.35, max_delay)


func build_player_memory_entry(message: String, location_name: String = "") -> String:
	return "\n".join([
		"[玩家输入]",
		"地点: %s" % location_name,
		"玩家消息: %s" % message
	])


func build_system_event_memory_entry(event, location_name: String = "") -> String:
	return "\n".join([
		"[系统事件]",
		"地点: %s" % location_name,
		"事件摘要: %s" % str(event.summary_text),
		"事件载荷: %s" % JSON.stringify(event.payload)
	])


func build_system_event_memory_entry_from_snapshot(event_data: Dictionary) -> String:
	return "\n".join([
		"[系统事件]",
		"事件摘要: %s" % str(event_data.get("summary_text", "")),
		"事件载荷: %s" % JSON.stringify(event_data.get("payload", {}))
	])


func build_visible_routes_snapshot(from_location_id: String) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	for neighbor in world_graph.get_neighbors(from_location_id):
		var neighbor_id: String = str(neighbor.get("to_id", ""))
		var travel_result: Dictionary = world_graph.can_travel(from_location_id, neighbor_id, unlocked_requirements)
		routes.append({
			"to_location_id": neighbor_id,
			"to_location_name": str(neighbor.get("to_name", neighbor_id)),
			"direction_label": str(neighbor.get("direction_label", "")),
			"travel_time_seconds": int(neighbor.get("travel_time", 0)) * 60,
			"allowed": bool(travel_result.get("allowed", false)),
			"reasons": travel_result.get("reasons", [])
		})
	return routes


func build_consumed_request_memory_entries(context, source_memory_entry: String) -> Array[String]:
	var entries: Array[String] = []
	for message in context.interrupted_player_messages:
		var normalized_message := str(message).strip_edges()
		if not normalized_message.is_empty():
			entries.append(build_player_memory_entry(normalized_message))
	for event_data in context.interrupted_system_events:
		if typeof(event_data) == TYPE_DICTIONARY:
			entries.append(build_system_event_memory_entry_from_snapshot(event_data))
	var normalized_source := source_memory_entry.strip_edges()
	if not normalized_source.is_empty():
		entries.append(normalized_source)
	return entries


func commit_request_memory_entries(entries: Array[String]) -> void:
	for entry_variant in entries:
		var entry := str(entry_variant).strip_edges()
		if not entry.is_empty():
			append_girl_memory_input(entry)


func _serialize_agent_commands(commands: Array) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for command_variant in commands:
		if command_variant == null:
			continue
		var command = command_variant as AgentCommand
		if command == null:
			continue
		var payload: Dictionary = {
			"type": command.type
		}
		if not command.target_location_id.is_empty():
			payload["target_location_id"] = command.target_location_id
		if not command.target_location_name.is_empty():
			payload["target_location_name"] = command.target_location_name
		if not command.target_id.is_empty():
			payload["target_id"] = command.target_id
		if not command.action.is_empty():
			payload["action"] = command.action
		if not command.params.is_empty():
			payload["params"] = command.params.duplicate(true)
		serialized.append(payload)
	return serialized


func apply_agent_output(agent_output, trigger_label: String, request_serial: int = -1) -> void:
	if agent_output == null:
		return
	applying_agent_output = true
	if not str(agent_output.reply_text).is_empty():
		await display_girl_reply_lines(str(agent_output.reply_text), trigger_label, request_serial)
	if request_serial != -1 and not is_request_serial_current(request_serial):
		applying_agent_output = false
		return
	if request_serial == -1 or is_request_serial_current(request_serial):
		system_command_executor.execute_command_set(agent_output.commands)
		append_girl_memory_reply_commands(agent_output.commands)
	var desired_names: Array[String] = get_system_desired_location_names()
	if not desired_names.is_empty():
		append_log("[系统] 当前希望前往的位置队列：%s" % " -> ".join(desired_names))
	append_log("[系统] 当前短期目标：%s" % system_agent_short_term_goal)
	applying_agent_output = false


func apply_agent_output_with_reply_delay(agent_output, trigger_label: String, reply_delay_seconds: float, request_serial: int = -1) -> void:
	if agent_output == null:
		return
	applying_agent_output = true
	if not str(agent_output.reply_text).is_empty():
		show_typing_indicator()
		await wait_for_game_seconds(reply_delay_seconds)
		if request_serial != -1 and not is_request_serial_current(request_serial):
			hide_typing_indicator()
			applying_agent_output = false
			return
		await display_girl_reply_lines(str(agent_output.reply_text), trigger_label, request_serial)
	if request_serial != -1 and not is_request_serial_current(request_serial):
		applying_agent_output = false
		return
	if request_serial == -1 or is_request_serial_current(request_serial):
		system_command_executor.execute_command_set(agent_output.commands)
		append_girl_memory_reply_commands(agent_output.commands)
	var desired_names: Array[String] = get_system_desired_location_names()
	if not desired_names.is_empty():
		append_log("[系统] 当前希望前往的位置队列：%s" % " -> ".join(desired_names))
	append_log("[系统] 当前短期目标：%s" % system_agent_short_term_goal)
	applying_agent_output = false


func reset_agent_exchange_timer() -> void:
	seconds_since_last_agent_exchange = 0


func dispatch_system_event(event) -> void:
	if event == null:
		return
	if applying_agent_output:
		pending_system_events.append(event)
		return
	if agent_request_in_flight:
		interrupt_active_agent_request()
	start_system_event_agent_request(event)

func _dispatch_system_event_async(event) -> void:
	start_system_event_agent_request(event)

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


func _on_send_pressed() -> void:
	var message := input_box.text.strip_edges()
	if message.is_empty():
		return
	interrupt_intro_sequence()
	append_log("%s %s" % [get_player_speaker_prefix(), message], "player")
	if not prologue_contact_confirmed:
		prologue_contact_confirmed = true
		objective_label.text = "目标：完成首次通讯，帮助少女确认飞船内部现状。"
		system_agent_short_term_goal = "完成首次通讯，帮助少女确认飞船内部的关键状况。"
		system_recent_dialogue_summary = "玩家首次回应了无线电呼叫，少女开始与玩家进行正式交流。"
	else:
		system_recent_dialogue_summary = "玩家最近一次输入：%s" % message
	if agent_request_in_flight:
		interrupt_active_agent_request()
	start_player_agent_request(message)
	input_box.clear()

func _on_send_submitted(_text: String) -> void:
	_on_send_pressed()


func process_pending_system_events() -> void:
	if agent_request_in_flight or applying_agent_output:
		return
	if pending_system_events.is_empty():
		return
	var next_event = pending_system_events.pop_front()
	start_system_event_agent_request(next_event)

func _on_quick_action(action_text: String) -> void:
	append_log("[玩家] " + action_text, "player")
	append_log("[系统] 已记录快捷动作，后续可以在这里接入专门的动作解析器。")


func _on_world_tick() -> void:
	if paused:
		return
	world_runtime.advance_world_time(1)


func _on_debug_advance_time() -> void:
	world_runtime.advance_world_time(10, true)


func _on_map_location_selected(index: int) -> void:
	var ids: Array[String] = world_graph.get_location_ids()
	if index < 0 or index >= ids.size():
		return
	selected_location_id = ids[index]
	render_location_detail()
	render_clues()


func _on_move_pressed() -> void:
	if world_runtime.is_traveling():
		append_log("[系统] 少女已经在路上了，请等当前移动结束后再下达新的移动指令。")
		return
	if selected_location_id == world_graph.current_location_id:
		append_log("[系统] 少女已经在这个地点，无需再次移动。")
		return
	system_command_executor.execute_move_command(AgentCommandScript.move_to_location(
		selected_location_id,
		str(world_graph.get_location(selected_location_id).get("name", selected_location_id))
	))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
