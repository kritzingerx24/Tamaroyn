extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")
const _LOCK_ICON: Texture2D = preload("res://assets/wulfram_textures/extracted/cursor_marker_target.png")

# Wulfram-II-inspired target HUD overlay.
#
# Mix of procedural + bitmap UI:
# - Corner bracket target box
# - Off-screen indicator (arrow + ring)
# - Info panel uses Wulfram ventpannel bitmap frame variants
# - LOCK indicator (progress arc + label + icon)
# - Tick-mark effect during lock buildup

@export var safe_margin_px: float = 26.0
@export var base_box_size_px: float = 56.0
@export var min_box_size_px: float = 28.0
@export var max_box_size_px: float = 62.0
@export var lock_arc_radius_pad_px: float = 14.0

var _enabled: bool = false

var _on_screen: bool = false
var _screen_pos: Vector2 = Vector2.ZERO
var _dir_screen: Vector2 = Vector2(0, -1)

var _dist_m: float = 0.0
var _hp: float = 0.0
var _hpmax: float = 1.0
var _team: int = 0
var _veh: String = ""
var _id: int = -1
var _is_enemy: bool = true

var _lock_level: float = 0.0
var _lock_ready: bool = false

var _t: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	if _enabled:
		queue_redraw()

func set_target_data(
		enabled: bool,
		on_screen: bool,
		screen_pos: Vector2,
		dir_screen: Vector2,
		dist_m: float,
		hp: float,
		hpmax: float,
		team: int,
		veh: String,
		id: int,
		is_enemy: bool,
		lock_level: float,
		lock_ready: bool
	) -> void:
	_enabled = enabled
	_on_screen = on_screen
	_screen_pos = screen_pos
	_dir_screen = dir_screen
	if _dir_screen.length() < 0.001:
		_dir_screen = Vector2(0, -1)
	else:
		_dir_screen = _dir_screen.normalized()
	_dist_m = dist_m
	_hp = hp
	_hpmax = max(0.001, hpmax)
	_team = team
	_veh = veh
	_id = id
	_is_enemy = is_enemy
	_lock_level = clamp(lock_level, 0.0, 1.0)
	_lock_ready = lock_ready
	visible = _enabled
	queue_redraw()

func _draw() -> void:
	if not _enabled:
		return
	var f: Font = get_theme_default_font()
	if f == null:
		return

	var vp: Vector2 = size
	var center: Vector2 = vp * 0.5
	var col_team: Color = _color_for_team(_team, _is_enemy)

	var pos: Vector2
	var offscreen: bool = false
	if _on_screen:
		pos = _screen_pos
	else:
		offscreen = true
		var edge_r: float = min(center.x, center.y) - safe_margin_px
		pos = center + _dir_screen * max(20.0, edge_r)
		pos = _clamp_to_safe(pos)

	# Off-screen indicator
	if offscreen:
		_draw_offscreen_indicator(pos, _dir_screen, col_team)

	# Target box size scales gently with distance (Wulfram-ish: stable, not too jumpy).
	var s: float = base_box_size_px - (_dist_m * 0.04)
	s = clamp(s, min_box_size_px, max_box_size_px)
	var half: float = s * 0.5

	# Bracket box
	var thick: float = 3.0 if _lock_ready else 2.0
	_draw_brackets(pos, half, col_team, thick)

	# Tick-mark effect (animated)
	_draw_ticks(pos, half, col_team)

	# Lock progress arc
	_draw_lock_arc(pos, half, col_team)

	# Info panel
	_draw_info_panel(f, pos, half, col_team)

func _clamp_to_safe(p: Vector2) -> Vector2:
	var r: Rect2 = Rect2(Vector2(safe_margin_px, safe_margin_px), size - Vector2(safe_margin_px * 2.0, safe_margin_px * 2.0))
	return Vector2(clamp(p.x, r.position.x, r.position.x + r.size.x), clamp(p.y, r.position.y, r.position.y + r.size.y))

func _color_for_team(team: int, is_enemy: bool) -> Color:
	if not is_enemy:
		return Color(0.45, 1.0, 0.55, 0.95)
	if team == 0:
		return Color(1.0, 0.35, 0.35, 0.95)
	if team == 1:
		return Color(0.35, 0.55, 1.0, 0.95)
	return Color(1.0, 0.95, 0.55, 0.95)

func _draw_offscreen_indicator(p: Vector2, dir: Vector2, col: Color) -> void:
	# Ring
	var pulse: float = 0.0
	if _lock_ready:
		pulse = 0.5 + 0.5 * sin(_t * 8.0)
	var ring_a: float = 0.35 + (0.20 * pulse)
	draw_arc(p, 14.0, 0.0, TAU, 32, Color(1, 1, 1, ring_a), 2.0)
	# Arrow
	var d: Vector2 = dir.normalized()
	var right: Vector2 = Vector2(-d.y, d.x)
	var tip: Vector2 = p + d * 18.0
	var a: Vector2 = p - d * 8.0 + right * 8.0
	var b: Vector2 = p - d * 8.0 - right * 8.0
	draw_colored_polygon([tip, a, b], Color(col.r, col.g, col.b, 0.90))

func _draw_brackets(p: Vector2, half: float, col: Color, thick: float) -> void:
	var k: float = half * 0.55
	var a: float = 0.90
	var c: Color = Color(col.r, col.g, col.b, a)

	# Top-left
	draw_line(p + Vector2(-half, -half), p + Vector2(-half + k, -half), c, thick)
	draw_line(p + Vector2(-half, -half), p + Vector2(-half, -half + k), c, thick)
	# Top-right
	draw_line(p + Vector2(half, -half), p + Vector2(half - k, -half), c, thick)
	draw_line(p + Vector2(half, -half), p + Vector2(half, -half + k), c, thick)
	# Bottom-left
	draw_line(p + Vector2(-half, half), p + Vector2(-half + k, half), c, thick)
	draw_line(p + Vector2(-half, half), p + Vector2(-half, half - k), c, thick)
	# Bottom-right
	draw_line(p + Vector2(half, half), p + Vector2(half - k, half), c, thick)
	draw_line(p + Vector2(half, half), p + Vector2(half, half - k), c, thick)

	# Subtle inner frame
	var inner: Rect2 = Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	draw_rect(inner.grow(-4.0), Color(1, 1, 1, 0.12), false, 1.0)

func _draw_ticks(p: Vector2, half: float, col: Color) -> void:
	# Animated tick marks that become stronger as lock builds.
	var a_base: float = 0.10
	var a_lock: float = 0.70 * _lock_level
	var pulse: float = 0.0
	if _lock_ready:
		pulse = 0.35 + 0.35 * sin(_t * 8.0)
	var alpha: float = clamp(a_base + a_lock + pulse, 0.0, 0.95)
	if alpha < 0.05:
		return
	var c: Color = Color(HudStyle.TEXT.r, HudStyle.TEXT.g, HudStyle.TEXT.b, alpha)
	var w: float = 2.0
	var tick_len: float = 7.0
	var drift: float = 0.0
	if _lock_level > 0.01:
		drift = 3.0 * sin(_t * 6.0)

	# Top edge ticks
	for i in 3:
		var t: float = (float(i) + 1.0) / 4.0
		var x: float = lerp(p.x - half, p.x + half, t) + drift
		draw_line(Vector2(x, p.y - half - 3.0), Vector2(x, p.y - half - 3.0 - tick_len), c, w)
	# Bottom edge ticks
	for i2 in 3:
		var t2: float = (float(i2) + 1.0) / 4.0
		var x2: float = lerp(p.x - half, p.x + half, t2) - drift
		draw_line(Vector2(x2, p.y + half + 3.0), Vector2(x2, p.y + half + 3.0 + tick_len), c, w)
	# Left edge ticks
	for j in 3:
		var tj: float = (float(j) + 1.0) / 4.0
		var y: float = lerp(p.y - half, p.y + half, tj) - drift
		draw_line(Vector2(p.x - half - 3.0, y), Vector2(p.x - half - 3.0 - tick_len, y), c, w)
	# Right edge ticks
	for j2 in 3:
		var tj2: float = (float(j2) + 1.0) / 4.0
		var y2: float = lerp(p.y - half, p.y + half, tj2) + drift
		draw_line(Vector2(p.x + half + 3.0, y2), Vector2(p.x + half + 3.0 + tick_len, y2), c, w)

func _draw_lock_arc(p: Vector2, half: float, col: Color) -> void:
	if _lock_level <= 0.001 and not _lock_ready:
		return
	var r: float = half + lock_arc_radius_pad_px
	var start: float = -PI * 0.5
	var end: float = start + TAU * _lock_level
	var a: float = 0.80
	var thick: float = 2.0
	if _lock_ready:
		# Full arc + pulse ring.
		var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
		a = 0.85
		thick = 3.0
		draw_arc(p, r + 6.0, 0.0, TAU, 64, Color(1, 1, 1, 0.18 + 0.18 * pulse), 2.0)
		end = start + TAU
	# Lock arc uses the HUD accent for a Wulfram-ish highlight.
	var tint: Color = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, a)
	if not _lock_ready:
		# While building lock, fade in.
		tint.a = clamp(0.25 + 0.65 * _lock_level, 0.25, 0.90)
	draw_arc(p, r, start, end, 56, tint, thick)

func _draw_info_panel(f: Font, p: Vector2, half: float, col: Color) -> void:
	var w: float = 180.0
	var h: float = 54.0
	var off: Vector2 = Vector2(half + 10.0, -half - 10.0)
	var rect: Rect2 = Rect2(p + off, Vector2(w, h))

	# Clamp panel into screen.
	var maxx: float = size.x - safe_margin_px - w
	var maxy: float = size.y - safe_margin_px - h
	rect.position.x = clamp(rect.position.x, safe_margin_px, maxx)
	rect.position.y = clamp(rect.position.y, safe_margin_px, maxy)

	# Bitmap frame (vent panel variants) for a closer Wulfram look.
	var vname: String = "ventpannel"
	if not _is_enemy:
		vname = "ventpannelG"
	else:
		if _team == 0:
			vname = "ventpannelR"
		elif _team == 1:
			vname = "ventpannel"
		else:
			vname = "ventpannel2"
	var vtex: Texture2D = HudStyle.tex(vname)
	if vtex != null:
		draw_texture_rect(vtex, rect, true, Color(1, 1, 1, 0.92))
		# Darken slightly so text stays readable.
		draw_rect(rect, Color(0, 0, 0, 0.26), true)
	else:
		HudStyle.draw_panel_back(self, rect, HudStyle.ACCENT)
	# Team tint border
	draw_rect(rect, Color(col.r, col.g, col.b, 0.55), false, 2.0)

	# Title line
	var team_tag: String = "RED" if _team == 0 else ("BLUE" if _team == 1 else "TEAM")
	var vtag: String = _veh.to_upper()
	if vtag.is_empty():
		vtag = "VEH"
	var title: String = "%s %s #%d" % [team_tag, vtag, _id]
	var title_col: Color = HudStyle.TEXT
	draw_string(f, rect.position + Vector2(8, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, title_col)

	# Distance
	var dist_txt: String = "RANGE %dm" % int(round(_dist_m))
	draw_string(f, rect.position + Vector2(8, 34), dist_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudStyle.TEXT_MUTED)

	# HP bar
	var bar_rect: Rect2 = Rect2(rect.position + Vector2(8, 40), Vector2(w - 16.0, 10.0))
	var frac: float = clamp(_hp / _hpmax, 0.0, 1.0)
	var back_name: String = "blue_bar_back"
	var fill_name: String = "green_bar"
	if _is_enemy:
		back_name = "red_bar_back" if _team == 0 else "blue_bar_back"
		fill_name = "red_bar" if _team == 0 else "blue_bar"
	var back_tex: Texture2D = HudStyle.tex(back_name)
	if back_tex != null:
		draw_texture_rect(back_tex, bar_rect, true, Color(1, 1, 1, 0.95))
	else:
		draw_rect(bar_rect, Color(0, 0, 0, 0.35), true)
	var fw: float = bar_rect.size.x * frac
	if fw > 0.5:
		var fill_rect: Rect2 = Rect2(bar_rect.position, Vector2(fw, bar_rect.size.y))
		var fill_tex: Texture2D = HudStyle.tex(fill_name)
		if fill_tex != null:
			draw_texture_rect(fill_tex, fill_rect, true, Color(1, 1, 1, 0.95))
		else:
			draw_rect(fill_rect, Color(col.r, col.g, col.b, 0.60), true)
	# Subtle frame
	draw_rect(bar_rect, Color(1, 1, 1, 0.10), false, 1.0)
	var hp_txt: String = "%d/%d" % [int(round(_hp)), int(round(_hpmax))]
	draw_string(f, rect.position + Vector2(w - 8.0, 34), hp_txt, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, HudStyle.TEXT_MUTED)

	# LOCK label + icon
	if _lock_ready:
		var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
		if _LOCK_ICON != null:
			var ir: Rect2 = Rect2(rect.position + Vector2(w - 28.0, 4.0), Vector2(20, 20))
			draw_texture_rect(_LOCK_ICON, ir, false, Color(1, 1, 1, 0.90))
		draw_string(
			f,
			rect.position + Vector2(w - 8.0, 18),
			"LOCK",
			HORIZONTAL_ALIGNMENT_RIGHT,
			-1,
			14,
			Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.55 + 0.35 * pulse)
		)