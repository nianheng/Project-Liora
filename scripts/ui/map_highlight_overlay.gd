extends Control

var highlight_rect := Rect2()
var highlight_visible := false
var fill_color := Color(0.45, 0.9, 1.0, 0.22)
var border_color := Color(0.72, 0.96, 1.0, 0.75)


func _draw() -> void:
	if not highlight_visible or highlight_rect.size.x <= 0.0 or highlight_rect.size.y <= 0.0:
		return

	var expanded := highlight_rect.grow(4.0)
	draw_rect(expanded, Color(fill_color.r, fill_color.g, fill_color.b, 0.08), true)
	draw_rect(highlight_rect, fill_color, true)
	draw_rect(highlight_rect, border_color, false, 3.0)


func show_highlight(rect: Rect2, tint: Color = Color(0.45, 0.9, 1.0, 0.22)) -> void:
	highlight_rect = rect
	fill_color = tint
	border_color = Color(tint.r, tint.g, tint.b, 0.78)
	highlight_visible = true
	queue_redraw()


func clear_highlight() -> void:
	highlight_visible = false
	queue_redraw()
