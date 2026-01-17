extends Control

# Bottom HUD bar to visually unify the weapon/build/minimap panels (Wulfram-II inspired).
# Purely cosmetic: sits behind other HUD widgets.

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

@export var bar_height_px: float = 200.0

func set_height(h: float) -> void:
	bar_height_px = max(64.0, h)
	# Keep anchored to the bottom.
	offset_top = -bar_height_px
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Full-width bottom bar.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	offset_top = -bar_height_px
	queue_redraw()

func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var tile_tex: Texture2D = HudStyle.tex("barnotch_lo")
	var top_tex: Texture2D = HudStyle.tex("menubar")
	# Slight angled top edge like Wulfram's chunky HUD.
	var y0: float = 0.0
	var y1: float = r.size.y
	var slope: float = 18.0
	var poly: PackedVector2Array = PackedVector2Array([
		Vector2(0, y0 + slope),
		Vector2(r.size.x * 0.22, y0),
		Vector2(r.size.x * 0.78, y0),
		Vector2(r.size.x, y0 + slope),
		Vector2(r.size.x, y1),
		Vector2(0, y1),
	])

	# Base fill
	draw_colored_polygon(poly, Color(0.08, 0.06, 0.05, 0.62))
	# Tiled Wulfram UI texture overlay (adds the classic bitmap HUD feel)
	if tile_tex != null:
		draw_texture_rect(tile_tex, Rect2(Vector2.ZERO, r.size), true, Color(1, 1, 1, 0.25))
	# Inner fill
	var poly2: PackedVector2Array = PackedVector2Array([
		Vector2(2, y0 + slope + 2),
		Vector2(r.size.x * 0.22, y0 + 2),
		Vector2(r.size.x * 0.78, y0 + 2),
		Vector2(r.size.x - 2, y0 + slope + 2),
		Vector2(r.size.x - 2, y1 - 2),
		Vector2(2, y1 - 2),
	])
	draw_colored_polygon(poly2, Color(0.12, 0.09, 0.06, 0.56))

	# Top bitmap strip (use Wulfram menubar texture if available)
	if top_tex != null:
		var th: float = min(float(top_tex.get_height()), r.size.y)
		draw_texture_rect(top_tex, Rect2(Vector2(0, 0), Vector2(r.size.x, th)), true, Color(1, 1, 1, 0.55))

	# Top accent line
	draw_line(Vector2(r.size.x * 0.22, y0 + 2), Vector2(r.size.x * 0.78, y0 + 2), Color(0.95, 0.62, 0.22, 0.65), 2.0)
	# Top edge outline
	draw_polyline(poly, Color(0, 0, 0, 0.75), 2.0)
