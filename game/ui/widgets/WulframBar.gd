class_name WulframBar
extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# Simple textured bar used by the HUD (weapon cooldowns, etc.).
# Uses Wulfram bitmap UI textures when available.

@export var back_tex_name: String = "blue_bar_back"   # e.g. blue_bar_back / red_bar_back
@export var fill_tex_name: String = "yellow_bar"      # e.g. yellow_bar / green_bar / red_bar / blue_bar
@export var overlay_dark: float = 0.18

var _frac: float = 1.0

func set_fraction(v: float) -> void:
	_frac = clamp(v, 0.0, 1.0)
	queue_redraw()

func set_textures(p_back: String, p_fill: String) -> void:
	back_tex_name = p_back
	fill_tex_name = p_fill
	queue_redraw()

func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return

	var back_tex: Texture2D = HudStyle.tex(back_tex_name)
	if back_tex != null:
		draw_texture_rect(back_tex, r, true, Color(1, 1, 1, 0.95))
	else:
		draw_rect(r, Color(0, 0, 0, 0.35), true)

	if overlay_dark > 0.0:
		draw_rect(r, Color(0, 0, 0, overlay_dark), true)

	var fw: float = r.size.x * _frac
	if fw > 0.5:
		var fr: Rect2 = Rect2(r.position, Vector2(fw, r.size.y))
		var fill_tex: Texture2D = HudStyle.tex(fill_tex_name)
		if fill_tex != null:
			draw_texture_rect(fill_tex, fr, true, Color(1, 1, 1, 0.95))
		else:
			draw_rect(fr, Color(1, 1, 1, 0.35), true)

	# Subtle frame
	draw_rect(r, Color(1, 1, 1, 0.10), false, 1.0)
