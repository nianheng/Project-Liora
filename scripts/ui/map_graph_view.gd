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
