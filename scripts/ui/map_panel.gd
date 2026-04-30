extends PanelContainer

signal location_selected(location_id: String)

const PANEL_ALT := Color("16324c")
const ACCENT := Color("69e2ff")
const ACCENT_WARM := Color("f4c16f")
const TEXT := Color("ecf7ff")
const TEXT_SOFT := Color("8ea7be")
const MAP_NODE_SIZE := Vector2(76, 34)
const MAP_CANVAS_MARGIN := Vector2(32, 26)
const MAP_VIEWPORT_SIZE := Vector2(640, 360)
const MAP_BACKGROUND_ASPECT_SIZE := Vector2(1086, 1449)
const MAP_ART_ANCHORS := {
	"bridge": Vector2(0.50, 0.325),
	"lounge": Vector2(0.37, 0.480),
	"pressure_room": Vector2(0.635, 0.480),
	"airlock_hatch": Vector2(0.795, 0.540),
	"supply_room": Vector2(0.370, 0.735),
	"engine_room": Vector2(0.645, 0.735)
}
const MAP_ART_HIGHLIGHT_RECTS := {
	"bridge": Rect2(0.405, 0.250, 0.190, 0.165),
	"lounge": Rect2(0.245, 0.410, 0.240, 0.170),
	"pressure_room": Rect2(0.520, 0.410, 0.230, 0.175),
	"airlock_hatch": Rect2(0.720, 0.475, 0.140, 0.120),
	"supply_room": Rect2(0.245, 0.625, 0.235, 0.235),
	"engine_room": Rect2(0.530, 0.630, 0.230, 0.235)
}

var world_graph
var world_objects
var world_runtime
var selected_location_id := ""
var unlocked_requirements: Array[String] = []
var travel_origin_id := ""
var travel_destination_id := ""
var travel_remaining_seconds := 0
var active_travel_connection: Dictionary = {}
var planned_route: Array[String] = []

var map_node_buttons: Dictionary = {}
var map_drag_pending := false
var map_dragging := false
var map_drag_origin := Vector2.ZERO
var map_scroll_origin := Vector2i.ZERO

@onready var map_summary_label: Label = %MapSummaryLabel
@onready var map_scroll: ScrollContainer = %MapScroll
@onready var map_canvas: Control = %MapCanvas
@onready var map_highlight_overlay = %MapHighlightOverlay
@onready var map_graph_view = %MapGraphView
@onready var map_node_layer: Control = %MapNodeLayer
@onready var map_lower_split: HSplitContainer = %MapLowerSplit
@onready var detail_title_label: Label = %DetailTitleLabel
@onready var detail_meta_label: Label = %DetailMetaLabel
@onready var detail_description_label: Label = %DetailDescriptionLabel
@onready var detail_object_list: ItemList = %DetailObjectList


func _ready() -> void:
	map_summary_label.modulate = TEXT_SOFT
	detail_meta_label.modulate = TEXT_SOFT
	map_scroll.get_h_scroll_bar().modulate = Color(1, 1, 1, 0)
	map_scroll.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	map_scroll.get_h_scroll_bar().custom_minimum_size = Vector2(0, 0)
	map_scroll.get_v_scroll_bar().custom_minimum_size = Vector2(0, 0)
	map_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	map_scroll.size_flags_vertical = Control.SIZE_FILL
	map_scroll.custom_minimum_size = MAP_VIEWPORT_SIZE
	map_scroll.resized.connect(_on_map_scroll_resized)
	map_graph_view.gui_input.connect(_on_map_graph_gui_input)
	map_graph_view.mouse_exited.connect(_clear_map_hover_summary)
	set_process_input(true)
	if world_graph != null:
		render_all()


func configure(graph, objects, runtime) -> void:
	world_graph = graph
	world_objects = objects
	world_runtime = runtime


func update_state(state: Dictionary) -> void:
	selected_location_id = str(state.get("selected_location_id", selected_location_id))
	unlocked_requirements.assign(state.get("unlocked_requirements", []))
	travel_origin_id = str(state.get("travel_origin_id", ""))
	travel_destination_id = str(state.get("travel_destination_id", ""))
	travel_remaining_seconds = int(state.get("travel_remaining_seconds", 0))
	active_travel_connection = state.get("active_travel_connection", {})
	planned_route.assign(state.get("planned_route", []))


func render_all() -> void:
	if not is_node_ready() or world_graph == null or world_objects == null:
		return
	_clear_map_hover_summary()
	render_map_list()
	render_location_detail()
	render_clues()


func apply_split_offset() -> void:
	if map_lower_split != null and map_lower_split.size.x > 0.0:
		map_lower_split.split_offset = int(map_lower_split.size.x * (50.0 / 77.0) - map_lower_split.size.x * 0.5)


func handle_drag_input(event: InputEvent) -> void:
	if not is_node_ready():
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


func _on_map_scroll_resized() -> void:
	map_scroll.custom_minimum_size = MAP_VIEWPORT_SIZE
	render_map_list()


func render_map_list() -> void:
	if map_graph_view == null or world_graph == null:
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

	if _is_traveling():
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


func render_location_detail() -> void:
	if _is_traveling():
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
	if _is_traveling():
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


func _ensure_map_node_buttons() -> void:
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
	var positions: Dictionary = {}
	var centers: Dictionary = {}
	var viewport_size := MAP_VIEWPORT_SIZE
	if map_scroll != null and map_scroll.size.x > 0.0 and map_scroll.size.y > 0.0:
		viewport_size = map_scroll.size
	var canvas_size := get_map_background_canvas_size(viewport_size)
	if map_canvas != null:
		map_canvas.custom_minimum_size = canvas_size
	var background_rect := get_map_background_rect(canvas_size)

	for location_id in ids:
		var anchor := get_location_map_art_anchor(location_id)
		var center := background_rect.position + Vector2(
			background_rect.size.x * anchor.x,
			background_rect.size.y * anchor.y
		)
		var final_position := center - MAP_NODE_SIZE * 0.5
		positions[location_id] = final_position
		centers[location_id] = center

	return {
		"positions": positions,
		"centers": centers
	}


func get_location_map_art_anchor(location_id: String) -> Vector2:
	if MAP_ART_ANCHORS.has(location_id):
		return MAP_ART_ANCHORS[location_id]
	var location: Dictionary = world_graph.get_location(location_id)
	var map_position: Dictionary = location.get("map_position", {})
	var x: float = float(map_position.get("x", 0.5))
	var y: float = float(map_position.get("y", 0.5))
	if x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0:
		return Vector2(x, y)
	return Vector2(0.5, 0.5)


func get_map_background_canvas_size(viewport_size: Vector2) -> Vector2:
	if MAP_BACKGROUND_ASPECT_SIZE.x <= 0.0 or MAP_BACKGROUND_ASPECT_SIZE.y <= 0.0:
		return viewport_size
	var image_aspect := MAP_BACKGROUND_ASPECT_SIZE.x / MAP_BACKGROUND_ASPECT_SIZE.y
	if image_aspect <= 0.0:
		return viewport_size
	var display_width := MAP_VIEWPORT_SIZE.x
	return Vector2(display_width, display_width / image_aspect)


func get_map_canvas_size() -> Vector2:
	if map_canvas != null:
		var canvas_size := map_canvas.custom_minimum_size
		if canvas_size.x > 0.0 and canvas_size.y > 0.0:
			return canvas_size
	return get_map_background_canvas_size(MAP_VIEWPORT_SIZE)


func get_map_background_rect(canvas_size: Vector2) -> Rect2:
	if MAP_BACKGROUND_ASPECT_SIZE.x <= 0.0 or MAP_BACKGROUND_ASPECT_SIZE.y <= 0.0:
		return Rect2(Vector2.ZERO, canvas_size)
	var image_aspect := MAP_BACKGROUND_ASPECT_SIZE.x / MAP_BACKGROUND_ASPECT_SIZE.y
	var canvas_aspect := canvas_size.x / canvas_size.y
	var display_size := canvas_size
	if canvas_aspect > image_aspect:
		display_size.x = canvas_size.y * image_aspect
	else:
		display_size.y = canvas_size.x / image_aspect
	var display_position := (canvas_size - display_size) * 0.5
	return Rect2(display_position, display_size)


func _style_map_node_button(button: Button, location_id: String) -> void:
	var fill: Color = PANEL_ALT
	var border: Color = Color("35536f")
	if world_graph != null and location_id == world_graph.current_location_id:
		border = ACCENT
	elif location_id == selected_location_id:
		border = ACCENT_WARM

	if location_id == "airlock_hatch" and world_objects != null:
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


func _on_map_node_pressed(location_id: String) -> void:
	selected_location_id = location_id
	location_selected.emit(location_id)
	render_map_list()
	render_location_detail()
	render_clues()


func _on_map_node_hovered(location_id: String) -> void:
	show_map_location_highlight(location_id)
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
		clear_map_location_highlight()
		map_summary_label.text = "道路 %s -> %s | 移动时间: %d 分钟" % [
			str(hovered_segment.get("from_name", "--")),
			str(hovered_segment.get("to_name", "--")),
			int(hovered_segment.get("travel_time", 0))
		]


func _clear_map_hover_summary() -> void:
	clear_map_location_highlight()
	if map_summary_label != null:
		map_summary_label.text = "将鼠标移动到地点或道路上可查看探索与通行信息。"


func show_map_location_highlight(location_id: String) -> void:
	if map_highlight_overlay == null or not MAP_ART_HIGHLIGHT_RECTS.has(location_id):
		return
	var canvas_size := get_map_canvas_size()
	var background_rect := get_map_background_rect(canvas_size)
	var normalized_rect: Rect2 = MAP_ART_HIGHLIGHT_RECTS[location_id]
	var highlight_rect := Rect2(
		background_rect.position + Vector2(
			background_rect.size.x * normalized_rect.position.x,
			background_rect.size.y * normalized_rect.position.y
		),
		Vector2(
			background_rect.size.x * normalized_rect.size.x,
			background_rect.size.y * normalized_rect.size.y
		)
	)
	map_highlight_overlay.show_highlight(highlight_rect, get_map_location_highlight_tint(location_id))


func clear_map_location_highlight() -> void:
	if map_highlight_overlay != null:
		map_highlight_overlay.clear_highlight()


func get_map_location_highlight_tint(location_id: String) -> Color:
	if world_graph != null and location_id == world_graph.current_location_id:
		return Color(0.43, 0.95, 1.0, 0.26)
	if location_id == selected_location_id:
		return Color(1.0, 0.76, 0.35, 0.24)
	if location_id == "airlock_hatch":
		return Color(1.0, 0.36, 0.34, 0.22)
	return Color(0.45, 0.9, 1.0, 0.22)


func format_object_list_entry(object_data: Dictionary) -> String:
	var object_type: String = str(object_data.get("type", "object"))
	var object_name: String = str(object_data.get("name", "未知对象"))
	var summary: String = format_object_state_summary(object_data)
	if summary.is_empty():
		return "%s | %s" % [object_type_label(object_type), object_name]
	return "%s | %s | %s" % [object_type_label(object_type), object_name, summary]


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


func format_duration(total_seconds: int) -> String:
	var clamped: int = maxi(total_seconds, 0)
	var minutes: int = floori(float(clamped) / 60.0)
	var seconds: int = clamped % 60
	return "%02d:%02d" % [minutes, seconds]


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


func _is_traveling() -> bool:
	return world_runtime != null and world_runtime.is_traveling()
