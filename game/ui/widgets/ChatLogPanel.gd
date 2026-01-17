extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# Wulfram-style bottom status/chat strip.
#
# This is intentionally lightweight and purely visual: it maintains a small scrollback
# buffer and draws it into a framed bitmap panel. It is fed by DebugHud.gd.

@export var title_text: String = "NEAREST FRIENDLY CARGO"
@export var max_lines: int = 6
@export var max_history: int = 64

signal kills_pressed
signal glimpse_pressed

var _team: int = 0
var _lines: Array[String] = []

# Scrollback: 0 = newest. Positive values show older lines.
var _scroll_offset: int = 0

# Bottom tab row values (Wulfram-style)
var _tab_kills: int = 0
var _tab_glimpse_ms: int = 0
var _tab_ping_ms: int = 0
var _tab_sector: String = ""

# Cached tab rects for click detection.
var _r_kills: Rect2 = Rect2()
var _r_glimpse: Rect2 = Rect2()
var _r_ping: Rect2 = Rect2()
var _r_sector: Rect2 = Rect2()

# Hover state for clickable tabs.
var _hover_kills: bool = false
var _hover_glimpse: bool = false

func _ready() -> void:
	# This panel is clickable (Kills / Glimpse).
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var p: Vector2 = mb.position
			if _r_kills.has_point(p):
				emit_signal("kills_pressed")
				accept_event()
				return
			if _r_glimpse.has_point(p):
				emit_signal("glimpse_pressed")
				accept_event()
				return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var p2: Vector2 = mm.position
		var hk: bool = _r_kills.has_point(p2)
		var hg: bool = _r_glimpse.has_point(p2)
		if hk != _hover_kills or hg != _hover_glimpse:
			_hover_kills = hk
			_hover_glimpse = hg
			queue_redraw()
		if hk or hg:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW

func set_team(team_id: int) -> void:
	if _team == team_id:
		return
	_team = team_id
	queue_redraw()

func clear() -> void:
	_lines.clear()
	queue_redraw()

func add_line(t: String) -> void:
	var s := t.strip_edges()
	if s.is_empty():
		return
	# Split multiline input into distinct log lines.
	for part in s.split("\n", false):
		var p := String(part).strip_edges()
		if p.is_empty():
			continue
		_lines.append(p)
	# Keep scrollback bounded.
	if _lines.size() > max_history:
		_lines = _lines.slice(_lines.size() - max_history, _lines.size())
	# New activity snaps view back to newest.
	_scroll_offset = 0
	queue_redraw()

func set_tabs(kills: int, glimpse_ms: int, ping_ms: int, sector: String) -> void:
	_tab_kills = max(0, kills)
	_tab_glimpse_ms = max(0, glimpse_ms)
	_tab_ping_ms = max(0, ping_ms)
	_tab_sector = sector
	queue_redraw()

func scroll_lines(delta: int) -> void:
	# delta > 0 => older (PageUp); delta < 0 => newer (PageDown)
	if _lines.is_empty():
		_scroll_offset = 0
		queue_redraw()
		return
	_scroll_offset = clamp(_scroll_offset + delta, 0, max(0, _lines.size() - 1))
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	HudStyle.draw_panel_back(self, rect, HudStyle.ACCENT)

	# Inner content region
	var pad := 4.0
	var inner := rect.grow(-pad)
	if inner.size.x <= 10 or inner.size.y <= 10:
		return

	# Title strip
	var title_h := 16.0
	var title_rect := Rect2(inner.position, Vector2(inner.size.x, title_h))
	# Subtle title strip background
	draw_rect(title_rect, Color(0, 0, 0, 0.35), true)
	# Team-tinted fill behind the text area.
	var tint := _team_tint(_team)
	var fill_rect := Rect2(inner.position + Vector2(0, title_h), Vector2(inner.size.x, inner.size.y - title_h))
	draw_rect(fill_rect, tint, true)

	var f: Font = get_theme_default_font()
	if f == null:
		return

	# Title text
	var fs: int = max(11, get_theme_default_font_size() - 3)
	var title_fs: int = fs
	var title_y: float = title_rect.position.y + (title_rect.size.y - float(f.get_height(title_fs))) * 0.5 + float(f.get_ascent(title_fs))
	draw_string(f, Vector2(title_rect.position.x + 4.0, title_y), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, HudStyle.TEXT_MUTED)

	# Bottom tabs row (Kills / Glimpse / ping / sector)
	var tabs_h := 18.0
	var tabs_rect := Rect2(fill_rect.position + Vector2(0, fill_rect.size.y - tabs_h), Vector2(fill_rect.size.x, tabs_h))
	_draw_tabs(f, tabs_rect, fs)

	# Log lines bottom-up (newest at bottom), like classic scrolling comms.
	var line_h := float(f.get_height(fs))
	var log_rect := Rect2(fill_rect.position, Vector2(fill_rect.size.x, fill_rect.size.y - tabs_h))
	var y_bottom := log_rect.position.y + log_rect.size.y - 5.0
	var shown := 0
	var start_idx: int = _lines.size() - 1 - _scroll_offset
	for i in range(start_idx, -1, -1):
		var y := y_bottom - line_h * float(shown)
		if y < log_rect.position.y + 4.0:
			break
		draw_string(f, Vector2(log_rect.position.x + 6.0, y), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT)
		shown += 1
		if shown >= max_lines:
			break

	# Subtle scroll indicator if we can scroll further back.
	if _scroll_offset > 0:
		draw_string(f, Vector2(log_rect.position.x + 6.0, log_rect.position.y + 12.0), "^", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT_MUTED)
	elif _lines.size() > max_lines:
		# Show a faint marker that there is scrollback.
		draw_string(f, Vector2(log_rect.position.x + 6.0, log_rect.position.y + 12.0), "·", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT_MUTED)


func _draw_tabs(f: Font, rect: Rect2, fs: int) -> void:
	# Dark strip background
	draw_rect(rect, Color(0, 0, 0, 0.38), true)

	# Compose strings
	var t_kills: String = "Kills"  # Wulfram shows this as a tab label
	var t_glimpse: String = "Glimpse %s" % _fmt_mmss(_tab_glimpse_ms)
	var t_ping: String = "%dms" % _tab_ping_ms
	var t_sector: String = _tab_sector
	if t_sector.is_empty():
		t_sector = "--"

	var pad: float = 8.0
	var gap: float = 2.0
	# Measure preferred widths
	var w_k: float = max(56.0, f.get_string_size(t_kills, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad * 2.0)
	var w_g: float = max(112.0, f.get_string_size(t_glimpse, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad * 2.0)
	var w_p: float = max(62.0, f.get_string_size(t_ping, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad * 2.0)
	var w_s: float = max(44.0, f.get_string_size(t_sector, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad * 2.0)

	# Right side tabs
	var x_right: float = rect.position.x + rect.size.x
	var r_sector := Rect2(Vector2(x_right - w_s, rect.position.y), Vector2(w_s, rect.size.y))
	var r_ping := Rect2(Vector2(r_sector.position.x - gap - w_p, rect.position.y), Vector2(w_p, rect.size.y))
	# Left side tabs
	var x_left: float = rect.position.x
	var r_kills := Rect2(Vector2(x_left, rect.position.y), Vector2(w_k, rect.size.y))
	var r_glimpse := Rect2(Vector2(r_kills.position.x + r_kills.size.x + gap, rect.position.y), Vector2(w_g, rect.size.y))

	# If the center tab would collide with the right tabs, shrink it to fit.
	var max_glimpse_right: float = r_ping.position.x - gap
	var desired_right: float = r_glimpse.position.x + r_glimpse.size.x
	if desired_right > max_glimpse_right:
		r_glimpse.size.x = max(60.0, max_glimpse_right - r_glimpse.position.x)

	# Draw tabs: kills is the "active" tab visually
	_draw_tab(f, r_kills, t_kills, fs, true, _hover_kills)
	_draw_tab(f, r_glimpse, t_glimpse, fs, false, _hover_glimpse)
	_draw_tab(f, r_ping, t_ping, fs, false, false)
	_draw_tab(f, r_sector, t_sector, fs, false, false)

	# Cache for click detection (local coordinates)
	_r_kills = r_kills
	_r_glimpse = r_glimpse
	_r_ping = r_ping
	_r_sector = r_sector

func _draw_tab(f: Font, r: Rect2, text: String, fs: int, active: bool, hovered: bool) -> void:
	var base: Color = Color(0, 0, 0, 0.22)
	var border: Color = Color(0, 0, 0, 0.80)
	if active:
		base = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.18)
		border = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.75)
	elif hovered:
		# Hover highlight for clickable tabs.
		base = Color(1, 1, 1, 0.06)
		border = Color(1, 1, 1, 0.22)
	if active and hovered:
		border = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.90)
		base = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.24)
	draw_rect(r, base, true)
	draw_rect(r, border, false, 1.0)
	# subtle top highlight
	draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x + r.size.x, r.position.y), Color(1, 1, 1, 0.08), 1.0)
	# Vertically center text in the tab strip.
	var baseline_y: float = r.position.y + (r.size.y - float(f.get_height(fs))) * 0.5 + float(f.get_ascent(fs))
	draw_string(f, Vector2(r.position.x + 8.0, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12.0, fs, HudStyle.TEXT_MUTED)

func _fmt_mmss(ms: int) -> String:
	var total_s: int = int(floor(float(ms) / 1000.0))
	var m: int = total_s / 60
	var s: int = total_s % 60
	return "%02d:%02d" % [m, s]

func _team_tint(team_id: int) -> Color:
	# Low-opacity tint to mimic Wulfram's red/blue team comms background.
	if team_id == 0:
		return Color(0.35, 0.05, 0.05, 0.55)
	if team_id == 1:
		return Color(0.05, 0.10, 0.35, 0.55)
	return Color(0.10, 0.10, 0.10, 0.55)
