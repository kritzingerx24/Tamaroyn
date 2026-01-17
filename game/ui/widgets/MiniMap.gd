extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# Wulfram radar sprites (8-direction tank pips) and markers.
const _RADAR_TANK: Array[Texture2D] = [
	preload("res://assets/wulfram_textures/extracted/radartank1.png"),
	preload("res://assets/wulfram_textures/extracted/radartank2.png"),
	preload("res://assets/wulfram_textures/extracted/radartank3.png"),
	preload("res://assets/wulfram_textures/extracted/radartank4.png"),
	preload("res://assets/wulfram_textures/extracted/radartank5.png"),
	preload("res://assets/wulfram_textures/extracted/radartank6.png"),
	preload("res://assets/wulfram_textures/extracted/radartank7.png"),
	preload("res://assets/wulfram_textures/extracted/radartank8.png"),
]
const _MARK_TARGET: Texture2D = preload("res://assets/wulfram_textures/extracted/cursor_marker_target.png")
const _MARK_WAYPOINT: Texture2D = preload("res://assets/wulfram_textures/extracted/cursor_marker_waypoint.png")

# Camera zoom UI (displayed inside the radar panel in the classic HUD)
const _ZOOM_STEP: float = 1.25
const _ZOOM_MIN_X: float = 1.0
const _ZOOM_MAX_X: float = 28.6


# Minimap/Radar stub inspired by Wulfram II: circular radar with pips.
# Drawn procedurally (no texture dependencies).

@export var radar_radius_px: float = 78.0
@export var radar_range_m: float = 140.0
@export var rotate_with_player: bool = true

# Camera zoom factor for HUD display (controlled by GameClient: Insert\/Delete).
var _cam_zoom_x: float = 1.0


var _hover_zoom_in: bool = false
var _hover_zoom_out: bool = false
var _r_zoom_in: Rect2 = Rect2()
var _r_zoom_out: Rect2 = Rect2()

var _me_pos: Vector3 = Vector3.ZERO
var _me_yaw: float = 0.0
var _me_team: int = 0

# Arrays of dictionaries:
# players: {id:int, pos:Vector3, team:int, veh:String}
# crates:  {id:int, pos:Vector3}
# bld:     {id:int, pos:Vector3, team:int, type:String}
var _players: Array = []
var _crates: Array = []
var _bld: Array = []
var _target_id: int = -1

func set_data(me_pos: Vector3, me_yaw: float, me_team: int, players: Array, crates: Array, bld: Array, target_id: int) -> void:
	_me_pos = me_pos
	_me_yaw = me_yaw
	_me_team = me_team
	_players = players
	_crates = crates
	_bld = bld
	_target_id = target_id
	queue_redraw()

func set_cam_zoom_x(zoom_x: float) -> void:
	_cam_zoom_x = clamp(zoom_x, _ZOOM_MIN_X, _ZOOM_MAX_X)
	queue_redraw()

func set_radar_range_m(range_m: float) -> void:
	radar_range_m = clamp(range_m, 30.0, 2000.0)
	queue_redraw()



func _draw() -> void:
	# Wulfram-ish frame around the radar
	var frame: Rect2 = Rect2(Vector2.ZERO, size)
	HudStyle.draw_panel_back(self, frame, HudStyle.ACCENT)

	# Tighten padding to better match Wulfram framing.
	var inset: float = 6.0
	var inner: Vector2 = size - Vector2(inset * 2.0, inset * 2.0)
	var center: Vector2 = Vector2(inset, inset) + inner * 0.5
	var r: float = min(radar_radius_px, min(inner.x, inner.y) * 0.5 - 2.0)

	_draw_zoom_ui(inset)

	# Background disk
	_draw_disk(center, r)

	# Crosshair lines and tick marks
	_draw_grid(center, r)

	# Range ring
	draw_arc(center, r * 0.66, 0.0, TAU, 64, Color(0.45, 0.55, 0.45, 0.45), 1.0)

	# Player forward indicator
	_draw_me(center, r)

	# Other entities
	_draw_crates(center, r)
	_draw_buildings(center, r)
	_draw_players(center, r)

	# Border
	draw_arc(center, r, 0.0, TAU, 96, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.70), 2.0)

func _gui_input(event: InputEvent) -> void:
	# Zoom controls only when hovering this panel.
	if event is InputEventMouseMotion:
		var mp: Vector2 = get_local_mouse_position()
		_hover_zoom_in = _r_zoom_in.has_point(mp)
		_hover_zoom_out = _r_zoom_out.has_point(mp)
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var mp2: Vector2 = mb.position
		# Mouse wheel zoom while hovering panel
		if Rect2(Vector2.ZERO, size).has_point(mp2):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_in()
				accept_event()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_out()
				accept_event()
				return
		# Click buttons
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _r_zoom_in.has_point(mp2):
				_zoom_in()
				accept_event()
				return
			if _r_zoom_out.has_point(mp2):
				_zoom_out()
				accept_event()
				return

func _zoom_in() -> void:
	_emit_zoom_key(true)

func _zoom_out() -> void:
	_emit_zoom_key(false)

func _emit_zoom_key(zoom_in: bool) -> void:
	# Trigger the same input path as Insert/Delete so GameClient owns zoom logic.
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_INSERT if zoom_in else KEY_DELETE
	Input.parse_input_event(ev)

func _draw_zoom_ui(inset: float) -> void:
	# Inside-panel zoom label + +/- buttons (top-right area).
	var f: Font = get_theme_default_font()
	if f == null:
		return
	var fs: int = 14
	var btn: float = 14.0
	var gap: float = 2.0
	var y: float = inset + 2.0
	var right: float = size.x - inset - 2.0
	_r_zoom_out = Rect2(Vector2(right - btn, y), Vector2(btn, btn))
	_r_zoom_in = Rect2(Vector2(right - btn * 2.0 - gap, y), Vector2(btn, btn))

	# Zoom text sits to the left of the buttons.
	var zoom_x: float = _cam_zoom_x
	var ztext: String = "Zoom: %.1fx" % zoom_x
	var zsize: Vector2 = f.get_string_size(ztext, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var zpos: Vector2 = Vector2(_r_zoom_in.position.x - 6.0 - zsize.x, y + 12.0)
	if zpos.x < inset + 2.0:
		zpos.x = inset + 2.0
	draw_string(f, zpos, ztext, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT_MUTED)

	_draw_zoom_button(_r_zoom_in, true, _hover_zoom_in)
	_draw_zoom_button(_r_zoom_out, false, _hover_zoom_out)

func _draw_zoom_button(r: Rect2, is_plus: bool, hovered: bool) -> void:
	# Small framed button.
	var base: Color = Color(0, 0, 0, 0.35)
	if hovered:
		base = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.18)
	draw_rect(r, base, true)
	draw_rect(r, Color(0, 0, 0, 0.85), false, 1.0)
	draw_rect(r.grow(-1.0), Color(1, 1, 1, 0.10), false, 1.0)

	# Symbol
	var cx: float = r.position.x + r.size.x * 0.5
	var cy: float = r.position.y + r.size.y * 0.5
	var col: Color = HudStyle.TEXT
	var w: float = r.size.x * 0.28
	draw_line(Vector2(cx - w, cy), Vector2(cx + w, cy), col, 2.0)
	if is_plus:
		draw_line(Vector2(cx, cy - w), Vector2(cx, cy + w), col, 2.0)

func _draw_disk(center: Vector2, r: float) -> void:
	# Slightly noisy/scanline-ish fill using layered circles.
	draw_circle(center, r, Color(0.08, 0.10, 0.08, 0.85))
	draw_circle(center, r * 0.96, Color(0.06, 0.08, 0.06, 0.90))
	draw_circle(center, r * 0.90, Color(0.05, 0.06, 0.05, 0.95))

func _draw_grid(center: Vector2, r: float) -> void:
	var gcol := Color(0.40, 0.55, 0.40, 0.55)
	draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), gcol, 1.0)
	draw_line(center + Vector2(0, -r), center + Vector2(0, r), gcol, 1.0)
	# Tick marks at 45 degrees
	for k in 8:
		var ang: float = float(k) * (TAU / 8.0)
		var a: Vector2 = center + Vector2(cos(ang), sin(ang)) * (r * 0.92)
		var b: Vector2 = center + Vector2(cos(ang), sin(ang)) * (r * 0.99)
		draw_line(a, b, gcol, 1.0)

func _draw_me(center: Vector2, r: float) -> void:
	var col: Color = _team_color(_me_team, true)
	var dir_ang: float = -_me_yaw
	if rotate_with_player:
		dir_ang = 0.0
	# Small triangle/chevron pointing up.
	var tip: Vector2 = center + Vector2(0, -r * 0.18).rotated(dir_ang)
	var left: Vector2 = center + Vector2(-r * 0.08, r * 0.06).rotated(dir_ang)
	var right: Vector2 = center + Vector2(r * 0.08, r * 0.06).rotated(dir_ang)
	draw_colored_polygon([tip, right, left], col)

func _draw_players(center: Vector2, r: float) -> void:
	for p in _players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		var id: int = int(pd.get("id", -1))
		var pos: Vector3 = Vector3(pd.get("pos", Vector3.ZERO))
		var team: int = int(pd.get("team", 0))
		var rel2: Vector2 = _to_radar(pos, r)
		var pt: Vector2 = center + rel2
		var is_target: bool = (id == _target_id and id >= 0)
		var col: Color = _team_color(team, false)
		# Choose an 8-direction radar tank sprite based on bearing from center.
		var ang: float = atan2(rel2.y, rel2.x)  # -PI..PI
		var sector: int = int(floor(((ang + PI) / TAU) * 8.0 + 0.5)) % 8
		var tex: Texture2D = _RADAR_TANK[sector] if sector >= 0 and sector < _RADAR_TANK.size() else null
		if tex != null:
			var s: float = 10.0
			draw_texture_rect(tex, Rect2(pt - Vector2(s, s), Vector2(s*2.0, s*2.0)), false, col)
		else:
			# Fallback: small triangle
			var s2: float = 4.0
			draw_rect(Rect2(pt - Vector2(s2, s2), Vector2(s2*2.0, s2*2.0)), col)

		if is_target:
			# Target marker (Wulfram cursor marker).
			if _MARK_TARGET != null:
				var ts: float = 12.0
				draw_texture_rect(_MARK_TARGET, Rect2(pt - Vector2(ts, ts), Vector2(ts*2.0, ts*2.0)), false, Color(1,1,1,0.95))
			else:
				draw_arc(pt, 6.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 1.0)
func _draw_crates(center: Vector2, r: float) -> void:
	for c in _crates:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = c
		var pos: Vector3 = Vector3(cd.get("pos", Vector3.ZERO))
		var rel2: Vector2 = _to_radar(pos, r)
		var pt: Vector2 = center + rel2
		# Cargo marker uses waypoint cursor sprite (scaled down).
		if _MARK_WAYPOINT != null:
			var s: float = 6.0
			draw_texture_rect(_MARK_WAYPOINT, Rect2(pt - Vector2(s, s), Vector2(s*2.0, s*2.0)), false, Color(1,1,1,0.85))
		else:
			# Fallback: diamond
			var d: float = 3.5
			var col: Color = Color(0.96, 0.80, 0.28, 0.95)
			draw_colored_polygon([pt + Vector2(0,-d), pt + Vector2(d,0), pt + Vector2(0,d), pt + Vector2(-d,0)], col)
func _draw_buildings(center: Vector2, r: float) -> void:
	for b in _bld:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var pos: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
		var team: int = int(bd.get("team", 0))
		var rel2: Vector2 = _to_radar(pos, r)
		var pt: Vector2 = center + rel2
		# buildings as squares
		var s: float = 3.5
		var col: Color = _team_color(team, false)
		draw_rect(Rect2(pt - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), col)

func _to_radar(world_pos: Vector3, r: float) -> Vector2:
	var rel: Vector3 = world_pos - _me_pos
	# Flatten to XZ
	var v: Vector2 = Vector2(rel.x, rel.z)
	if rotate_with_player:
		v = v.rotated(_me_yaw)
	var scale: float = r / max(1.0, radar_range_m)
	v *= scale
	# Clamp to radar circle
	var len: float = v.length()
	if len > r * 0.98:
		v = v.normalized() * (r * 0.98)
	return v

func _team_color(team: int, is_me: bool) -> Color:
	if team == 0:
		return Color(1.0, 0.35, 0.35, 0.95 if is_me else 0.85)
	if team == 1:
		return Color(0.35, 0.55, 1.0, 0.95 if is_me else 0.85)
	return Color(1.0, 0.95, 0.55, 0.85)
