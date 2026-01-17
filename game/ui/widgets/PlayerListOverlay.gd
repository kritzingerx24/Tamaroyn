extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# Wulfram II: Player list (key 'P').
# We don't yet have player names/kills replicated, so we display peer id + vehicle.

var _players: Array = []
var _me_id: int = -1
var _me_team: int = 0

func set_data(me_id: int, me_team: int, players: Array) -> void:
	_me_id = me_id
	_me_team = me_team
	_players = players
	queue_redraw()

func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Click anywhere to close.
			visible = false
			accept_event()
			return

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var full := Rect2(Vector2.ZERO, vp)
	# Dim world behind.
	draw_rect(full, Color(0, 0, 0, 0.55), true)

	# Central panel.
	var pw: float = min(vp.x - 60.0, 820.0)
	var ph: float = min(vp.y - 60.0, 520.0)
	var panel := Rect2(Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5), Vector2(pw, ph))
	HudStyle.draw_panel_back(self, panel, HudStyle.ACCENT)
	var inner := panel.grow(-10.0)

	var f: Font = get_theme_default_font()
	if f == null:
		return
	var fs_title: int = 16
	var fs: int = 14

	# Header
	var header_h: float = 22.0
	var header := Rect2(inner.position, Vector2(inner.size.x, header_h))
	draw_rect(header, Color(0, 0, 0, 0.35), true)
	draw_string(f, header.position + Vector2(6, 16), "PLAYER LIST", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title, HudStyle.TEXT)
	draw_string(f, header.position + Vector2(header.size.x - 6, 16), "ESC: close", HORIZONTAL_ALIGNMENT_RIGHT, header.size.x - 12.0, fs, HudStyle.TEXT_MUTED)

	# Columns
	var col_gap: float = 10.0
	var cols_y: float = header.position.y + header.size.y + 8.0
	var cols_h: float = inner.position.y + inner.size.y - cols_y
	var col_w: float = (inner.size.x - col_gap) * 0.5
	var left := Rect2(Vector2(inner.position.x, cols_y), Vector2(col_w, cols_h))
	var right := Rect2(Vector2(inner.position.x + col_w + col_gap, cols_y), Vector2(col_w, cols_h))

	_draw_team_list(f, left, 1, "BLUE TEAM", fs)
	_draw_team_list(f, right, 0, "RED TEAM", fs)

func _draw_team_list(f: Font, r: Rect2, team: int, title: String, fs: int) -> void:
	# Title strip
	var th: float = 18.0
	var tr := Rect2(r.position, Vector2(r.size.x, th))
	draw_rect(tr, Color(0, 0, 0, 0.28), true)
	var tint: Color = Color(0.10, 0.22, 0.55, 0.70) if team == 1 else Color(0.55, 0.12, 0.12, 0.70)
	draw_rect(tr.grow(-1.0), Color(tint.r, tint.g, tint.b, 0.18), true)
	draw_string(f, tr.position + Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT)

	var y: float = tr.position.y + tr.size.y + 6.0
	var line_h: float = float(f.get_height(fs)) + 2.0
	var shown: int = 0
	for p in _players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		if int(pd.get("team", 0)) != team:
			continue
		var pid: int = int(pd.get("id", -1))
		var veh: String = str(pd.get("veh", ""))
		var is_me: bool = (pid == _me_id)
		var tag: String = "P%d" % pid
		if is_me:
			tag = "P%d (you)" % pid
		var text: String = "%s  %s" % [tag, veh.to_upper()]
		var row := Rect2(Vector2(r.position.x + 2.0, y - 13.0), Vector2(r.size.x - 4.0, line_h))
		if is_me:
			draw_rect(row, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.18), true)
		draw_string(f, Vector2(r.position.x + 6.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT)
		y += line_h
		shown += 1
		if y > r.position.y + r.size.y - 6.0:
			break

	if shown == 0:
		draw_string(f, Vector2(r.position.x + 6.0, y), "(no players)", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT_MUTED)
