extends Control

# Wulfram-style thin status bar shown along the top edge.
# Draws a small icon and a segmented fill line.

@export var bar_kind: String = "hp" # "hp" or "energy"

var _icon: Texture2D = null
var _fraction: float = 0.0

var _fill_color: Color = Color(0.2, 1.0, 0.25, 1.0)
var _back_color: Color = Color(0.0, 0.0, 0.0, 0.55)
var _border_color: Color = Color(0.0, 0.0, 0.0, 0.9)
var _tick_color: Color = Color(0.0, 0.2, 0.0, 0.6)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_configure_kind()
	queue_redraw()

func _configure_kind() -> void:
	if bar_kind == "energy":
		_icon = load("res://assets/wulfram_textures/extracted/lightning.png")
		_fill_color = Color(1.0, 0.9, 0.25, 1.0)
		_tick_color = Color(0.20, 0.20, 0.00, 0.60)
	else:
		_icon = load("res://assets/wulfram_textures/extracted/shield_icon.png")
		_fill_color = Color(0.20, 1.00, 0.25, 1.0)
		_tick_color = Color(0.00, 0.20, 0.00, 0.60)

func set_fraction(f: float) -> void:
	_fraction = clamp(f, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var sz: Vector2 = size
	var icon_w: float = 0.0
	var icon_h: float = 0.0
	if _icon != null:
		icon_w = float(_icon.get_width())
		icon_h = float(_icon.get_height())
		var icon_pos := Vector2(0.0, (sz.y - icon_h) * 0.5)
		draw_texture(_icon, icon_pos)

	var pad: float = 4.0
	var bar_x0: float = icon_w + pad
	var bar_x1: float = sz.x
	var bar_w: float = max(0.0, bar_x1 - bar_x0)

	# Thin horizontal bar centered vertically.
	var bar_h: float = 4.0
	var bar_y: float = floor((sz.y - bar_h) * 0.5)

	# Background + border.
	draw_rect(Rect2(bar_x0, bar_y, bar_w, bar_h), _back_color, true)
	draw_rect(Rect2(bar_x0, bar_y, bar_w, bar_h), _border_color, false, 1.0)

	# Fill.
	var fill_w: float = floor(bar_w * _fraction)
	if fill_w > 0.0:
		draw_rect(Rect2(bar_x0 + 1.0, bar_y + 1.0, max(0.0, fill_w - 2.0), max(0.0, bar_h - 2.0)), _fill_color, true)

	# Tick marks for a segmented / CRT-ish look.
	var tick_step: float = 12.0
	var tick_y0: float = bar_y - 1.0
	var tick_y1: float = bar_y + bar_h + 1.0
	var x: float = bar_x0 + tick_step
	while x < bar_x1:
		draw_line(Vector2(x, tick_y0), Vector2(x, tick_y1), _tick_color, 1.0)
		x += tick_step
