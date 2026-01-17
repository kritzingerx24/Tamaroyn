extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# UI icon sources (vertical strips; cropped via _atlas16())
const _TEX_SHIP_BLUE: Texture2D = preload("res://assets/wulfram_textures/extracted/cargojetblue.png")
const _TEX_SHIP_RED: Texture2D = preload("res://assets/wulfram_textures/extracted/cargojetred.png")
const _TEX_CARGO_TOPS: Texture2D = preload("res://assets/wulfram_textures/extracted/cargotops.png")
const _TEX_CARGO_SD: Texture2D = preload("res://assets/wulfram_textures/extracted/cargosd.png")
const _TEX_REPAIR: Texture2D = preload("res://assets/wulfram_textures/extracted/repair_top.png")
const _TEX_TURRET: Texture2D = preload("res://assets/wulfram_textures/extracted/w2rt_turrettop.png")

# Wulfram II: Strategic Map / Uplink display (key 'M'), with view cycle ('N').
# The original UI includes a left control panel with two main tabs: Map and Uplink,
# plus unit visibility toggles and marker creation.

enum ViewMode { VISUAL, ALTITUDE, SLOPE }
enum TabMode { MAP, UPLINK }

# Uplink command placement modes (click command, then click sector on map)
enum UplinkPlaceMode { NONE, REQUEST, MOVE }

var _mode: int = ViewMode.VISUAL
var _tab: int = TabMode.MAP
var _uplink_ship_idx: int = 0
var _uplink_place_mode: int = UplinkPlaceMode.NONE
var _cmd_request_enabled: bool = false
var _cmd_move_enabled: bool = false

var _world_w: float = 0.0
var _world_d: float = 0.0

var _me_pos: Vector3 = Vector3.ZERO
var _me_team: int = 0
var _players: Array = []
var _crates: Array = []
var _bld: Array = []
var _ships: Array = []
var _target_id: int = -1
var _sector: String = "--"
var _glimpse_ms: int = 0

# Optional CPU-generated textures for map modes (built at map load on client).
var _tex_visual: Texture2D = null
var _tex_alt: Texture2D = null
var _tex_slope: Texture2D = null

# Map visibility toggles (minimal subset; can be expanded later)
var _show_players: bool = true
var _show_buildings: bool = true
var _show_cargo: bool = true
var _show_markers: bool = true

# Team markers created from the strategic display.
# Each: {pos:Vector3, team:int, text:String}
var _markers: Array = []
var _placing_marker: bool = false

# Hover state for tooltip
var _hover_screen: Vector2 = Vector2.ZERO
var _hover_world_xz: Vector2 = Vector2.ZERO
var _hover_sector: String = "--"
var _hover_entity: String = ""
var _hover_on_map: bool = false

# Last mouse position (for hover highlights on buttons)
var _mouse_pos: Vector2 = Vector2.ZERO

# Cached UI rects for interaction.
var _panel_r: Rect2 = Rect2()
var _ctl_r: Rect2 = Rect2()
var _map_r: Rect2 = Rect2()
var _btn_map_r: Rect2 = Rect2()
var _btn_uplink_r: Rect2 = Rect2()
var _btns: Dictionary = {}

# Recent Uplink orders (local display). Each: {text:String, ms:int, status:String}
var _order_queue: Array = []

func set_data(me_pos: Vector3, me_team: int, players: Array, crates: Array, bld: Array, ships: Array, target_id: int, world_w: float, world_d: float, sector: String, glimpse_ms: int, tex_visual: Texture2D = null, tex_altitude: Texture2D = null, tex_slope: Texture2D = null) -> void:
	_me_pos = me_pos
	_me_team = me_team
	_players = players
	_crates = crates
	_bld = bld
	_ships = ships
	_target_id = target_id
	_world_w = max(0.0, world_w)
	_world_d = max(0.0, world_d)
	_sector = sector if not sector.is_empty() else "--"
	_glimpse_ms = max(0, glimpse_ms)
	_tex_visual = tex_visual
	_tex_alt = tex_altitude
	_tex_slope = tex_slope
	queue_redraw()

func push_order(text: String, status: String = "") -> void:
	var s: String = text.strip_edges()
	if s.is_empty():
		return
	var d: Dictionary = {"text": s, "ms": Time.get_ticks_msec(), "status": status}
	_order_queue.append(d)
	# Keep last 6
	if _order_queue.size() > 6:
		_order_queue = _order_queue.slice(_order_queue.size() - 6, _order_queue.size())
	queue_redraw()

func resolve_last_pending(status: String) -> void:
	# Mark the most recent pending order as done/rejected when the server replies.
	for i in range(_order_queue.size() - 1, -1, -1):
		var d: Dictionary = _order_queue[i]
		if str(d.get("status", "")) == "pending":
			d["status"] = status
			_order_queue[i] = d
			queue_redraw()
			return


func cycle_mode() -> void:
	_mode = (_mode + 1) % 3
	queue_redraw()

func set_tab(tab: int) -> void:
	_tab = tab
	_placing_marker = false
	_uplink_place_mode = UplinkPlaceMode.NONE
	queue_redraw()

func toggle_tab() -> void:
	set_tab(TabMode.UPLINK if _tab == TabMode.MAP else TabMode.MAP)

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
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse_pos = mm.position
		_update_hover(mm.position)
		accept_event()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		var mp: Vector2 = mb.position
		_mouse_pos = mp
		# Click outside panel closes.
		if _panel_r.size != Vector2.ZERO and not _panel_r.has_point(mp):
			visible = false
			_placing_marker = false
			_uplink_place_mode = UplinkPlaceMode.NONE
			accept_event()
			return

		# Tabs
		if _btn_map_r.has_point(mp):
			set_tab(TabMode.MAP)
			accept_event()
			return
		if _btn_uplink_r.has_point(mp):
			set_tab(TabMode.UPLINK)
			accept_event()
			return

		# Uplink: command buttons (Request / Move Ship)
		if _tab == TabMode.UPLINK:
			if _btns.has("cmd_request") and Rect2(_btns["cmd_request"]).has_point(mp):
				if _cmd_request_enabled:
					_uplink_place_mode = (UplinkPlaceMode.NONE if _uplink_place_mode == UplinkPlaceMode.REQUEST else UplinkPlaceMode.REQUEST)
					_placing_marker = false
					queue_redraw(); accept_event(); return
			if _btns.has("cmd_move") and Rect2(_btns["cmd_move"]).has_point(mp):
				if _cmd_move_enabled:
					_uplink_place_mode = (UplinkPlaceMode.NONE if _uplink_place_mode == UplinkPlaceMode.MOVE else UplinkPlaceMode.MOVE)
					_placing_marker = false
					queue_redraw(); accept_event(); return

		# Uplink: click a sector to issue the currently-armed command
		if _uplink_place_mode != UplinkPlaceMode.NONE:
			if _map_r.has_point(mp):
				var sxsy: Vector2i = _sector_xy_from_map_point(mp)
				_send_uplink_command(_uplink_place_mode, _uplink_ship_idx, sxsy.x, sxsy.y)
				_uplink_place_mode = UplinkPlaceMode.NONE
				queue_redraw(); accept_event(); return
			# Click inside panel but not on map cancels placement.
			_uplink_place_mode = UplinkPlaceMode.NONE
			queue_redraw(); accept_event(); return

		# Marker placement
		if _placing_marker:
			if _map_r.has_point(mp):
				_place_marker_at(mp)
				_placing_marker = false
				queue_redraw()
				accept_event()
				return
			# Click inside panel but not on map cancels placement.
			_placing_marker = false
			queue_redraw()
			accept_event()
			return

		# Map tab buttons
		if _tab == TabMode.MAP:
			if _btns.has("toggle_players") and Rect2(_btns["toggle_players"]).has_point(mp):
				_show_players = not _show_players
				queue_redraw(); accept_event(); return
			if _btns.has("toggle_buildings") and Rect2(_btns["toggle_buildings"]).has_point(mp):
				_show_buildings = not _show_buildings
				queue_redraw(); accept_event(); return
			if _btns.has("toggle_cargo") and Rect2(_btns["toggle_cargo"]).has_point(mp):
				_show_cargo = not _show_cargo
				queue_redraw(); accept_event(); return
			if _btns.has("toggle_markers") and Rect2(_btns["toggle_markers"]).has_point(mp):
				_show_markers = not _show_markers
				queue_redraw(); accept_event(); return
			if _btns.has("create_marker") and Rect2(_btns["create_marker"]).has_point(mp):
				_placing_marker = true
				queue_redraw(); accept_event(); return

		# Uplink tab: allow selecting one of the (up to) 3 starships for display.
		if _tab == TabMode.UPLINK:
			for i in range(3):
				var k: String = "ship_%d" % i
				if _btns.has(k) and Rect2(_btns[k]).has_point(mp):
					_uplink_ship_idx = i
					queue_redraw(); accept_event(); return



func _sector_xy_from_map_point(mp: Vector2) -> Vector2i:
	# Convert a mouse point in _map_r to a sector coordinate (sx, sy), 0..5
	if _map_r.size.x <= 1.0 or _map_r.size.y <= 1.0:
		return Vector2i(0, 0)
	var u: float = clamp((mp.x - _map_r.position.x) / _map_r.size.x, 0.0, 0.9999)
	var v: float = clamp((mp.y - _map_r.position.y) / _map_r.size.y, 0.0, 0.9999)
	var sx: int = int(floor(u * 6.0))
	var sy: int = int(floor(v * 6.0))
	return Vector2i(clamp(sx, 0, 5), clamp(sy, 0, 5))

func _send_uplink_command(mode: int, slot: int, sx: int, sy: int) -> void:
	# Issue an RPC to the server using the root node (named 'ServerMain' in GameClient.tscn).
	var n: Node = get_tree().get_root().get_node_or_null("ServerMain")
	if n == null:
		n = get_tree().current_scene
	if n == null:
		return
	var sec: String = _sector_from_xy(sx, sy)
	if mode == UplinkPlaceMode.REQUEST:
		push_order("REQUEST STARSHIP %d -> %s" % [slot + 1, sec], "pending")
		n.rpc_id(1, "c_uplink_request_ship", slot, sx, sy)
	elif mode == UplinkPlaceMode.MOVE:
		push_order("MOVE STARSHIP %d -> %s" % [slot + 1, sec], "pending")
		n.rpc_id(1, "c_uplink_move_ship", slot, sx, sy)

func _atlas16(src: Texture2D, index: int = 0) -> Texture2D:
	if src == null:
		return null
	var w: int = int(src.get_width())
	var h: int = int(src.get_height())
	if w < 2 or h < 2:
		return src
	var tile: int = min(16, w)
	var y: int = clamp(index * 16, 0, max(0, h - 16))
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = src
	at.region = Rect2(0, y, tile, min(16, h))
	return at

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var full := Rect2(Vector2.ZERO, vp)
	# Dim world behind.
	draw_rect(full, Color(0, 0, 0, 0.55), true)

	# Central panel.
	var pw: float = min(vp.x - 40.0, 1080.0)
	var ph: float = min(vp.y - 40.0, 640.0)
	_panel_r = Rect2(Vector2((vp.x - pw) * 0.5, (vp.y - ph) * 0.5), Vector2(pw, ph))
	HudStyle.draw_panel_back(self, _panel_r, HudStyle.ACCENT)
	var inner := _panel_r.grow(-10.0)

	var f: Font = get_theme_default_font()
	if f == null:
		return
	var fs_title: int = 16
	var fs: int = 14

	# Header
	var header_h: float = 22.0
	var header := Rect2(inner.position, Vector2(inner.size.x, header_h))
	draw_rect(header, Color(0, 0, 0, 0.35), true)
	var mode_name: String = "VISUAL" if _mode == ViewMode.VISUAL else ("ALTITUDE" if _mode == ViewMode.ALTITUDE else "SLOPE")
	var tab_name: String = "MAP" if _tab == TabMode.MAP else "UPLINK"
	var left_text: String = "%s  %s  %s" % [tab_name, _sector, _fmt_mmss(_glimpse_ms)]
	var right_text: String = "N: %s   ESC: close" % mode_name
	draw_string(f, header.position + Vector2(6, 16), left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title, HudStyle.TEXT)
	draw_string(f, header.position + Vector2(header.size.x - 6, 16), right_text, HORIZONTAL_ALIGNMENT_RIGHT, header.size.x - 12.0, fs, HudStyle.TEXT_MUTED)

	# Control + map layout
	var gap: float = 10.0
	var y0: float = header.position.y + header.size.y + 8.0
	var h0: float = inner.position.y + inner.size.y - y0
	var ctl_w: float = clamp(inner.size.x * 0.24, 200.0, 260.0)
	_ctl_r = Rect2(Vector2(inner.position.x, y0), Vector2(ctl_w, h0))
	_map_r = Rect2(Vector2(_ctl_r.position.x + _ctl_r.size.x + gap, y0), Vector2(inner.size.x - ctl_w - gap, h0))

	_draw_control_panel(f, fs)
	_draw_map_area(f, fs)

	if _placing_marker:
		var msg := "Click on map to place marker (click panel to cancel)"
		var tpos := Vector2(_map_r.position.x + 10.0, _map_r.position.y + 20.0)
		draw_string(f, tpos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))

	if _uplink_place_mode != UplinkPlaceMode.NONE:
		var umsg: String = "Click a sector to MOVE SHIP (stabilized)" if _uplink_place_mode == UplinkPlaceMode.MOVE else "Click a sector to REQUEST ship (warp requires 2+ skypumps)"
		var tpos2 := Vector2(_map_r.position.x + 10.0, _map_r.position.y + 38.0)
		draw_string(f, tpos2, umsg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))

func _draw_control_panel(f: Font, fs: int) -> void:
	# Panel background
	draw_rect(_ctl_r, Color(0.05, 0.06, 0.07, 0.92), true)
	draw_rect(_ctl_r, Color(0, 0, 0, 0.85), false, 1.0)

	_btns.clear()

	# Top tabs: Map / Uplink
	var tab_h: float = 22.0
	var half: float = _ctl_r.size.x * 0.5
	_btn_map_r = Rect2(_ctl_r.position, Vector2(half, tab_h))
	_btn_uplink_r = Rect2(Vector2(_ctl_r.position.x + half, _ctl_r.position.y), Vector2(half, tab_h))
	_draw_button(_btn_map_r, "MAP", _tab == TabMode.MAP)
	_draw_button(_btn_uplink_r, "UPLINK", _tab == TabMode.UPLINK)

	var y: float = _ctl_r.position.y + tab_h + 10.0
	var bw: float = _ctl_r.size.x - 12.0
	var bx: float = _ctl_r.position.x + 6.0
	var bh: float = 20.0

	if _tab == TabMode.MAP:
		# Visibility toggles
		_btns["toggle_players"] = Rect2(Vector2(bx, y), Vector2(bw, bh))
		_draw_toggle_button(_btns["toggle_players"], "Players", _show_players)
		y += bh + 6.0
		_btns["toggle_buildings"] = Rect2(Vector2(bx, y), Vector2(bw, bh))
		_draw_toggle_button(_btns["toggle_buildings"], "Units/Buildings", _show_buildings)
		y += bh + 6.0
		_btns["toggle_cargo"] = Rect2(Vector2(bx, y), Vector2(bw, bh))
		_draw_toggle_button(_btns["toggle_cargo"], "Cargo", _show_cargo)
		y += bh + 6.0
		_btns["toggle_markers"] = Rect2(Vector2(bx, y), Vector2(bw, bh))
		_draw_toggle_button(_btns["toggle_markers"], "Markers", _show_markers)
		y += bh + 10.0
		_btns["create_marker"] = Rect2(Vector2(bx, y), Vector2(bw, bh))
		_draw_button(_btns["create_marker"], "Create Marker", false)
		# Hint at bottom
		var hint := "(M: map  N: mode)"
		draw_string(f, Vector2(bx, _ctl_r.position.y + _ctl_r.size.y - 10.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudStyle.TEXT_MUTED)
	else:
		_draw_uplink_view(f, fs, bx, y, bw, bh)


func _draw_uplink_view(f: Font, fs: int, bx: float, y: float, bw: float, bh: float) -> void:
	var line_h: float = 18.0
	var title_fs: int = fs
	var small_fs: int = 12

	# Section: Uplink status
	_draw_label(f, Vector2(bx, y), "UPLINK STATUS", title_fs, HudStyle.TEXT)
	var ut: int = _find_uplink_team()
	var has_uplink: bool = ut != -2
	var owns_uplink: bool = (ut >= 0 and ut == _me_team)
	var can_control: bool = (has_uplink and owns_uplink)
	var ind_r := Rect2(Vector2(bx + bw - 12.0, y + 2.0), Vector2(10.0, 10.0))
	var ind_col: Color = Color(0.25, 0.25, 0.25, 0.85)
	if ut >= 0:
		ind_col = _team_color(ut, true)
	draw_rect(ind_r, ind_col, true)
	draw_rect(ind_r, Color(0, 0, 0, 0.85), false, 1.0)
	y += line_h
	_draw_label(f, Vector2(bx, y), _find_uplink_status(), small_fs, HudStyle.TEXT_MUTED)
	y += line_h + 6.0
	# Divider
	draw_line(Vector2(bx, y), Vector2(bx + bw, y), Color(1, 1, 1, 0.10), 1.0)
	y += 10.0

	# Section: Cargo Bays (visual strip)
	_draw_label(f, Vector2(bx, y), "CARGO BAYS", title_fs, HudStyle.TEXT)
	y += line_h
	var bays: Array = _uplink_sim_bays(_me_team)
	var slot: float = 22.0
	var gap2: float = 6.0
	for i in range(4):
		var rr := Rect2(Vector2(bx + float(i) * (slot + gap2), y), Vector2(slot, slot))
		draw_rect(rr, Color(0, 0, 0, 0.28), true)
		draw_rect(rr, Color(0, 0, 0, 0.85), false, 1.0)
		draw_rect(rr.grow(-1.0), Color(1, 1, 1, 0.10), false, 1.0)
		var code: String = str(bays[i]) if i < bays.size() else ""
		var icon: Texture2D = _uplink_icon_for(code, _me_team)
		if icon != null and can_control:
			draw_texture_rect(icon, rr.grow(-3.0), false, Color(1, 1, 1, 0.9))
	y += slot + 10.0
	draw_line(Vector2(bx, y), Vector2(bx + bw, y), Color(1, 1, 1, 0.10), 1.0)
	y += 10.0

	# Section: Starships (max 3)
	_draw_label(f, Vector2(bx, y), "STARSHIPS", title_fs, HudStyle.TEXT)
	y += line_h
	var ship_tex: Texture2D = _atlas16(_TEX_SHIP_BLUE if _me_team == 1 else _TEX_SHIP_RED, 0)
	# Server supplies the actual starships list. We still show 3 slots like classic Wulfram.
	var team_ships: Array = _ships_for_team(_me_team)
	var slot_to_ship: Dictionary = {}
	for s in team_ships:
		var sd: Dictionary = s
		slot_to_ship[int(sd.get("slot", 0))] = sd
	for i in range(3):
		var sr := Rect2(Vector2(bx, y), Vector2(bw, 26.0))
		_btns["ship_%d" % i] = sr
		var has_ship: bool = slot_to_ship.has(i)
		var online: bool = has_ship and can_control
		var label: String = "%d  STARSHIP" % (i + 1)
		if has_ship:
			var sd2: Dictionary = slot_to_ship[i]
			var st: String = str(sd2.get("state", "online")).to_lower()
			if st != "online":
				online = false
			var sec: String = _sector_from_xy(int(sd2.get("sx", 0)), int(sd2.get("sy", 0)))
			label += "  %s" % sec
		label += ("  ONLINE" if online else "  OFFLINE")
		_draw_button(sr, label, _uplink_ship_idx == i, not online)
		if ship_tex != null:
			var ir := Rect2(sr.position + Vector2(6.0, 5.0), Vector2(16.0, 16.0))
			draw_texture_rect(ship_tex, ir, false, Color(1, 1, 1, 0.9 if online else 0.45))
		y += 30.0
	# Order queue panel (visual-only)
	y += 2.0
	_draw_label(f, Vector2(bx, y), "ORDER QUEUE", title_fs, HudStyle.TEXT)
	y += line_h
	var qh: float = 74.0
	var qr := Rect2(Vector2(bx, y), Vector2(bw, qh))
	draw_rect(qr, Color(0, 0, 0, 0.28), true)
	draw_rect(qr, Color(0, 0, 0, 0.85), false, 1.0)
	draw_rect(qr.grow(-1.0), Color(1, 1, 1, 0.10), false, 1.0)
	var qy: float = y + 14.0
	if not can_control:
		draw_string(f, Vector2(bx + 6.0, qy), "(no control; uplink not installed)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudStyle.TEXT_MUTED)
	else:
		if _order_queue.size() == 0:
			draw_string(f, Vector2(bx + 6.0, qy), "- No orders", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
			qy += 14.0
		else:
			var now: int = Time.get_ticks_msec()
			var show: Array = _order_queue.duplicate()
			show.reverse()
			var max_items: int = min(show.size(), 4)
			for i in range(max_items):
				var e: Dictionary = show[i]
				var txt: String = str(e.get("text", ""))
				var st: String = str(e.get("status", ""))
				var age_s: int = int((now - int(e.get("ms", now))) / 1000)
				var age: String = ("%ds" % age_s) if age_s < 60 else ("%dm" % int(age_s / 60))
				var col: Color = HudStyle.TEXT_MUTED
				if st == "rejected":
					col = Color(1.0, 0.55, 0.55, 0.95)
				elif st == "done":
					col = Color(0.65, 1.0, 0.65, 0.95)
				elif st == "pending":
					col = Color(1.0, 1.0, 1.0, 0.85)
				draw_string(f, Vector2(bx + 6.0, qy), "- %s  %s" % [age, txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
				qy += 14.0
	y += qh + 12.0
	# Commands
	_draw_label(f, Vector2(bx, y), "SHIP COMMANDS", title_fs, HudStyle.TEXT)
	y += line_h
	var cmd_w: float = (bw - 6.0) * 0.5
	var cmd_h: float = 20.0
	var left_x: float = bx
	var right_x: float = bx + cmd_w + 6.0
	# Determine command enablement.
	var has_ship_selected: bool = slot_to_ship.has(_uplink_ship_idx)
	_cmd_request_enabled = can_control and (not has_ship_selected)
	_cmd_move_enabled = can_control and has_ship_selected
	var r_req := Rect2(Vector2(left_x, y), Vector2(cmd_w, cmd_h))
	var r_del := Rect2(Vector2(right_x, y), Vector2(cmd_w, cmd_h))
	_btns["cmd_request"] = r_req
	_btns["cmd_delete"] = r_del
	_draw_button(r_req, "Request", _uplink_place_mode == UplinkPlaceMode.REQUEST, not _cmd_request_enabled)
	_draw_button(r_del, "Delete", false, true)
	y += cmd_h + 6.0
	var r_bomb := Rect2(Vector2(left_x, y), Vector2(cmd_w, cmd_h))
	var r_move := Rect2(Vector2(right_x, y), Vector2(cmd_w, cmd_h))
	_btns["cmd_bombard"] = r_bomb
	_btns["cmd_move"] = r_move
	_draw_button(r_bomb, "Bombard", false, true)
	_draw_button(r_move, "Move Ship", _uplink_place_mode == UplinkPlaceMode.MOVE, not _cmd_move_enabled)
	y += cmd_h + 8.0
	var note: String = "(Control via Uplink)" if can_control else "(No control; uplink not installed)"
	_draw_label(f, Vector2(bx, y), note, 12, HudStyle.TEXT_MUTED)
	# Context help for ship commands
	var help: String = ""
	if r_del.has_point(_mouse_pos):
		help = "Delete: not wired yet"
	elif r_bomb.has_point(_mouse_pos):
		help = "Bombard: not wired yet"
	elif r_req.has_point(_mouse_pos) and _cmd_request_enabled:
		help = "Request: click a WARP sector (2+ skypumps)"
	elif r_move.has_point(_mouse_pos) and _cmd_move_enabled:
		help = "Move: click a stabilized sector (1+ skypump)"
	if not help.is_empty():
		_draw_label(f, Vector2(bx, y + 14.0), help, 12, HudStyle.TEXT_MUTED)

	# Bottom hint
	_draw_label(f, Vector2(bx, _ctl_r.position.y + _ctl_r.size.y - 12.0), "M: map   N: modes   . install   , uninstall", 12, HudStyle.TEXT_MUTED)

func _find_uplink_team() -> int:
	# Returns team id (0/1), 2 for neutral, -2 for none.
	# Prefer our own uplink if both teams have one.
	var other: int = -2
	for b in _bld:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var typ: String = str(bd.get("type", "")).to_lower()
		if typ.find("uplink") == -1:
			continue
		var t: int = int(bd.get("team", -1))
		if t == _me_team:
			return t
		if other == -2:
			other = (t if (t == 0 or t == 1) else 2)
	return other

func _uplink_sim_bays(uplink_team: int) -> Array:
	# Visual-only: show representative cargo icons when the uplink belongs to our team.
	if uplink_team >= 0 and uplink_team == _me_team:
		# These correspond to common Wulfram visuals (turret / repair / cargo).
		return ["turret", "repair", ("tops" if _me_team == 1 else "sd"), ""]
	return ["", "", "", ""]

func _uplink_icon_for(code: String, team: int) -> Texture2D:
	match code:
		"turret":
			return _atlas16(_TEX_TURRET, 0)
		"repair":
			return _atlas16(_TEX_REPAIR, 0)
		"tops":
			return _atlas16(_TEX_CARGO_TOPS, 0)
		"sd":
			return _atlas16(_TEX_CARGO_SD, 0)
		_:
			return null

func _draw_map_area(f: Font, fs: int) -> void:
	# Map area background (optional CPU texture) + mode tint.
	draw_rect(_map_r, Color(0, 0, 0, 0.92), true)
	var tex: Texture2D = null
	if _mode == ViewMode.VISUAL:
		tex = _tex_visual
	elif _mode == ViewMode.ALTITUDE:
		tex = _tex_alt
	elif _mode == ViewMode.SLOPE:
		tex = _tex_slope
	if tex != null:
		draw_texture_rect(tex, _map_r, false, Color(1, 1, 1, 0.98))

	# Subtle tint keeps the mode feel even when textures are missing.
	var tint: Color = Color(0.05, 0.07, 0.05, 0.18)
	if _mode == ViewMode.ALTITUDE:
		tint = Color(0.07, 0.06, 0.05, 0.18)
	elif _mode == ViewMode.SLOPE:
		tint = Color(0.05, 0.06, 0.08, 0.18)
	draw_rect(_map_r, tint, true)

	draw_rect(_map_r, Color(0, 0, 0, 0.85), false, 1.0)
	_draw_grid(_map_r)
	_draw_sector_highlights(_map_r)
	_draw_entities(_map_r)
	_draw_markers(_map_r)
	_draw_hover_tooltip(f, fs)

func _draw_button(r: Rect2, text: String, active: bool, disabled: bool = false) -> void:
	# Wulfram-like button: subtle hover, brighter active, muted disabled.
	var hovered: bool = (not disabled and r.has_point(_mouse_pos))
	var base: Color = Color(0, 0, 0, 0.35)
	if active:
		base = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.18)
	elif hovered:
		base = Color(1, 1, 1, 0.06)
	if disabled:
		base = Color(0, 0, 0, 0.22)
	draw_rect(r, base, true)
	# Outer frame
	draw_rect(r, Color(0, 0, 0, 0.85), false, 1.0)
	# Inner highlight
	var inner: Color = Color(1, 1, 1, 0.10)
	if hovered:
		inner = Color(1, 1, 1, 0.16)
	if active:
		inner = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.22)
	draw_rect(r.grow(-1.0), inner, false, 1.0)
	# Active edge
	if active:
		var edge := Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.45)
		draw_rect(r.grow(-2.0), edge, false, 2.0)
	var f: Font = get_theme_default_font()
	if f == null:
		return
	var col: Color = HudStyle.TEXT_MUTED if disabled else HudStyle.TEXT
	if hovered and not disabled:
		col = Color(1, 1, 1, 0.95)
	var fs: int = 14
	draw_string(f, Vector2(r.position.x + 6.0, r.position.y + 15.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_toggle_button(r: Rect2, label: String, on: bool) -> void:
	_draw_button(r, ("[x] " if on else "[ ] ") + label, on)

func _draw_label(f: Font, pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string(f, pos + Vector2(0, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_grid(r: Rect2) -> void:
	# Wulfram docs mention a 6x6 sector grid.
	var cols: int = 6
	var rows: int = 6
	var col: Color = Color(0.45, 0.60, 0.45, 0.35)
	for i in range(1, cols):
		var x: float = r.position.x + r.size.x * (float(i) / float(cols))
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y), col, 1.0)
	for j in range(1, rows):
		var y: float = r.position.y + r.size.y * (float(j) / float(rows))
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x, y), col, 1.0)

	# Labels (A-F, 1-6)
	var f: Font = get_theme_default_font()
	if f == null:
		return
	var fs: int = 12
	for i2 in range(cols):
		var letter: String = String.chr(65 + i2)
		var tx: float = r.position.x + r.size.x * (float(i2) / float(cols)) + 4.0
		draw_string(f, Vector2(tx, r.position.y + 14.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT_MUTED)
	for j2 in range(rows):
		var num: String = str(j2 + 1)
		var ty: float = r.position.y + r.size.y * (float(j2) / float(rows)) + 14.0
		draw_string(f, Vector2(r.position.x + 4.0, ty), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.TEXT_MUTED)

func _draw_entities(r: Rect2) -> void:
	# If we don't know world extents yet, fall back to a local window around the player.
	var w: float = _world_w
	var d: float = _world_d
	var x0: float
	var z0: float
	if w > 0.0 and d > 0.0:
		x0 = -w * 0.5
		z0 = -d * 0.5
	else:
		w = 800.0
		d = 800.0
		x0 = _me_pos.x - w * 0.5
		z0 = _me_pos.z - d * 0.5

	# Buildings (small squares)
	if _show_buildings:
		for b in _bld:
			if typeof(b) != TYPE_DICTIONARY:
				continue
			var bd: Dictionary = b
			var pos: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
			var team: int = int(bd.get("team", 0))
			var typ: String = str(bd.get("type", ""))
			var pt: Vector2 = _world_to_map(pos, r, x0, z0, w, d)
			var c: Color = _team_color(team, false)
			var sz: float = 4.0
			# Uplink is visually distinct.
			if typ.to_lower().find("uplink") != -1:
				sz = 6.0
				draw_rect(Rect2(pt - Vector2(sz, sz), Vector2(sz * 2.0, sz * 2.0)), Color(1, 1, 1, 0.85), true)
				draw_rect(Rect2(pt - Vector2(sz-1, sz-1), Vector2((sz-1) * 2.0, (sz-1) * 2.0)), c, true)
			else:
				draw_rect(Rect2(pt - Vector2(2, 2), Vector2(4, 4)), c, true)

	# Crates (small diamonds)
	if _show_cargo:
		for c0 in _crates:
			if typeof(c0) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = c0
			var pos2: Vector3 = Vector3(cd.get("pos", Vector3.ZERO))
			var pt2: Vector2 = _world_to_map(pos2, r, x0, z0, w, d)
			var col: Color = Color(0.90, 0.80, 0.40, 0.90)
			_draw_diamond(pt2, 3.5, col)

	# Players (triangles). Highlight self and target.
	if _show_players:
		for p in _players:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var pd: Dictionary = p
			var pid: int = int(pd.get("id", -1))
			var pos3: Vector3 = Vector3(pd.get("pos", Vector3.ZERO))
			var team2: int = int(pd.get("team", 0))
			var yaw: float = float(pd.get("yaw", 0.0))
			var pt3: Vector2 = _world_to_map(pos3, r, x0, z0, w, d)
			var bright: bool = (pid == multiplayer.get_unique_id())
			var col2: Color = _team_color(team2, bright)
			var size: float = 6.0 if bright else 4.5
			_draw_ship_triangle(pt3, yaw, size, col2)
			if pid == _target_id and pid >= 0:
				draw_arc(pt3, 7.0, 0.0, TAU, 24, Color(1, 1, 1, 0.85), 1.0)

func _draw_markers(r: Rect2) -> void:
	if not _show_markers:
		return
	if _markers.is_empty():
		return
	# Same world extents strategy as entities.
	var w: float = _world_w
	var d: float = _world_d
	var x0: float
	var z0: float
	if w > 0.0 and d > 0.0:
		x0 = -w * 0.5
		z0 = -d * 0.5
	else:
		w = 800.0
		d = 800.0
		x0 = _me_pos.x - w * 0.5
		z0 = _me_pos.z - d * 0.5
	var f: Font = get_theme_default_font()
	var fs: int = 12
	for m in _markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var pos: Vector3 = Vector3(md.get("pos", Vector3.ZERO))
		var team: int = int(md.get("team", 0))
		var pt: Vector2 = _world_to_map(pos, r, x0, z0, w, d)
		var col: Color = _team_color(team, true)
		# Cross marker
		draw_line(pt + Vector2(-5, 0), pt + Vector2(5, 0), col, 2.0)
		draw_line(pt + Vector2(0, -5), pt + Vector2(0, 5), col, 2.0)
		var txt: String = str(md.get("text", ""))
		if f != null and not txt.is_empty():
			draw_string(f, pt + Vector2(8.0, -4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _place_marker_at(screen_pt: Vector2) -> void:
	# Convert screen point to world, using the same extents mapping.
	var w: float = _world_w
	var d: float = _world_d
	var x0: float
	var z0: float
	if w > 0.0 and d > 0.0:
		x0 = -w * 0.5
		z0 = -d * 0.5
	else:
		w = 800.0
		d = 800.0
		x0 = _me_pos.x - w * 0.5
		z0 = _me_pos.z - d * 0.5
	var u: float = clamp((screen_pt.x - _map_r.position.x) / max(1.0, _map_r.size.x), 0.0, 1.0)
	var v: float = clamp((screen_pt.y - _map_r.position.y) / max(1.0, _map_r.size.y), 0.0, 1.0)
	var wx: float = x0 + u * w
	var wz: float = z0 + v * d
	# Give markers a short label (M1, M2...) per-team for readability.
	var idx: int = 0
	for m in _markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		if int(md.get("team", -1)) == _me_team:
			idx += 1
	var tag: String = "M%d" % (idx + 1)
	_markers.append({"pos": Vector3(wx, 0.0, wz), "team": _me_team, "text": tag})

func _world_to_map(pos: Vector3, r: Rect2, x0: float, z0: float, w: float, d: float) -> Vector2:
	var u: float = clamp((pos.x - x0) / w, 0.0, 1.0)
	var v: float = clamp((pos.z - z0) / d, 0.0, 1.0)
	# (0,0) at top-left.
	return Vector2(r.position.x + u * r.size.x, r.position.y + v * r.size.y)

func _draw_diamond(center: Vector2, rad: float, col: Color) -> void:
	draw_colored_polygon([
		center + Vector2(0, -rad),
		center + Vector2(rad, 0),
		center + Vector2(0, rad),
		center + Vector2(-rad, 0),
	], col)

func _team_color(team_id: int, bright: bool) -> Color:
	if team_id == 0:
		return Color(1.00, 0.35, 0.35, 0.95) if bright else Color(0.95, 0.25, 0.25, 0.85)
	if team_id == 1:
		return Color(0.35, 0.65, 1.00, 0.95) if bright else Color(0.25, 0.55, 0.95, 0.85)
	return Color(0.80, 0.80, 0.80, 0.85)

func _fmt_mmss(ms: int) -> String:
	var sec: int = int(floor(float(ms) / 1000.0))
	var mm: int = int(sec / 60)
	var ss: int = int(sec % 60)
	return "%02d:%02d" % [mm, ss]

func _find_uplink_status() -> String:
	# Detect uplink objects in the snapshot.
	var has_my: bool = false
	var enemy_team: int = -1
	var neutral: bool = false
	for b in _bld:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var typ: String = str(bd.get("type", "")).to_lower()
		if typ.find("uplink") == -1:
			continue
		var t: int = int(bd.get("team", -1))
		if t == _me_team:
			has_my = true
		elif t == 0 or t == 1:
			enemy_team = t
		else:
			neutral = true
	if has_my:
		return "Uplink online (%s)" % ("BLUE" if _me_team == 1 else "RED")
	if enemy_team != -1:
		return "No friendly uplink (enemy %s uplink detected)" % ("BLUE" if enemy_team == 1 else "RED")
	if neutral:
		return "Neutral uplink detected"
	return "No uplink detected"


func _update_hover(screen_pt: Vector2) -> void:
	_hover_screen = screen_pt
	_hover_on_map = _map_r.size != Vector2.ZERO and _map_r.has_point(screen_pt)
	if not _hover_on_map:
		_hover_sector = "--"
		_hover_entity = ""
		return
	var wp: Vector3 = _screen_to_world(screen_pt)
	_hover_world_xz = Vector2(wp.x, wp.z)
	_hover_sector = _sector_for_world(wp.x, wp.z)
	_hover_entity = _nearest_entity_text(wp)

func _screen_to_world(screen_pt: Vector2) -> Vector3:
	# Convert screen point to world, using the same extents mapping.
	var w: float = _world_w
	var d: float = _world_d
	var x0: float
	var z0: float
	if w > 0.0 and d > 0.0:
		x0 = -w * 0.5
		z0 = -d * 0.5
	else:
		w = 800.0
		d = 800.0
		x0 = _me_pos.x - w * 0.5
		z0 = _me_pos.z - d * 0.5
	var u: float = clamp((screen_pt.x - _map_r.position.x) / max(1.0, _map_r.size.x), 0.0, 1.0)
	var v: float = clamp((screen_pt.y - _map_r.position.y) / max(1.0, _map_r.size.y), 0.0, 1.0)
	var wx: float = x0 + u * w
	var wz: float = z0 + v * d
	return Vector3(wx, 0.0, wz)

func _sector_for_world(wx: float, wz: float) -> String:
	if _world_w > 0.0 and _world_d > 0.0:
		var x0: float = -_world_w * 0.5
		var z0: float = -_world_d * 0.5
		var u: float = clamp((wx - x0) / _world_w, 0.0, 0.9999)
		var v: float = clamp((wz - z0) / _world_d, 0.0, 0.9999)
		var col: int = int(floor(u * 6.0))
		var row: int = int(floor(v * 6.0)) + 1
		var letter: String = String.chr(65 + clamp(col, 0, 5))
		return "%s%d" % [letter, clamp(row, 1, 6)]
	var col2: int = int(floor((wx + 512.0) / 128.0))
	var row2: int = int(floor((wz + 512.0) / 128.0))
	var letter2: String = String.chr(65 + clamp(col2, 0, 5))
	return "%s%d" % [letter2, clamp(row2 + 1, 1, 6)]

func _sector_from_xy(sx: int, sy: int) -> String:
	sx = clamp(sx, 0, 5)
	sy = clamp(sy, 0, 5)
	var letter: String = String.chr(65 + sx)
	return "%s%d" % [letter, sy + 1]

func _ships_for_team(team_id: int) -> Array:
	var out: Array = []
	for s in _ships:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		if int(sd.get("team", -1)) == team_id:
			out.append(sd)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("slot", 0)) < int((b as Dictionary).get("slot", 0))
	)
	return out

func _skypump_sector_counts() -> Dictionary:
	# Returns {0: {"A1": n, ...}, 1: {...}}
	var out: Dictionary = {0: {}, 1: {}}
	for b in _bld:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var typ: String = str(bd.get("type", "")).to_lower()
		if typ.find("skypump") == -1:
			continue
		var t: int = int(bd.get("team", -1))
		if t != 0 and t != 1:
			continue
		var pos: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
		var sec: String = _sector_for_world(pos.x, pos.z)
		var dt: Dictionary = out[t]
		dt[sec] = int(dt.get(sec, 0)) + 1
		out[t] = dt
	return out


func _uplink_sector_marks() -> Array:
	# Returns [{"team":int, "sec":String}, ...] (deduped).
	var out: Array = []
	var seen: Dictionary = {}
	for b in _bld:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var typ: String = str(bd.get("type", "")).to_lower()
		if typ.find("uplink") == -1:
			continue
		var t: int = int(bd.get("team", -1))
		var pos: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
		var sec: String = _sector_for_world(pos.x, pos.z)
		var k: String = "%d:%s" % [t, sec]
		if seen.has(k):
			continue
		seen[k] = true
		out.append({"team": t, "sec": sec})
	return out

func _nearest_entity_text(wp: Vector3) -> String:
	var best: float = 1e18
	var best_text: String = ""
	# Prioritize buildings/markers over cargo over players.
	for b in _bld:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var pos: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
		var dx: float = pos.x - wp.x
		var dz: float = pos.z - wp.z
		var dd: float = dx * dx + dz * dz
		if dd < best and dd < 80.0 * 80.0:
			best = dd
			var typ: String = str(bd.get("type", "Building"))
			var t: int = int(bd.get("team", -1))
			best_text = "%s (%s)" % [typ, "BLUE" if t == 1 else ("RED" if t == 0 else "NEUTRAL")]
	for m in _markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var posm: Vector3 = Vector3(md.get("pos", Vector3.ZERO))
		var dxm: float = posm.x - wp.x
		var dzm: float = posm.z - wp.z
		var ddm: float = dxm * dxm + dzm * dzm
		if ddm < best and ddm < 60.0 * 60.0:
			best = ddm
			var t2: int = int(md.get("team", -1))
			var mtxt: String = str(md.get("text", ""))
			var tn: String = ("BLUE" if t2 == 1 else ("RED" if t2 == 0 else "NEUTRAL"))
			best_text = ("Marker %s (%s)" % [mtxt, tn]) if not mtxt.is_empty() else ("Marker (%s)" % tn)
	for c in _crates:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = c
		var posc: Vector3 = Vector3(cd.get("pos", Vector3.ZERO))
		var dxc: float = posc.x - wp.x
		var dzc: float = posc.z - wp.z
		var ddc: float = dxc * dxc + dzc * dzc
		if ddc < best and ddc < 60.0 * 60.0:
			best = ddc
			best_text = "Cargo"
	for p in _players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = p
		var posp: Vector3 = Vector3(pd.get("pos", Vector3.ZERO))
		var dxp: float = posp.x - wp.x
		var dzp: float = posp.z - wp.z
		var ddp: float = dxp * dxp + dzp * dzp
		if ddp < best and ddp < 60.0 * 60.0:
			best = ddp
			var pid: int = int(pd.get("id", -1))
			var team: int = int(pd.get("team", -1))
			best_text = "Player %d (%s)" % [pid, "BLUE" if team == 1 else ("RED" if team == 0 else "NEUTRAL")]
	return best_text

func _draw_sector_highlights(r: Rect2) -> void:
	# Wulfram-style sector overlays (stabilized squares + orbit sectors + selection/hover).
	var cols: int = 6
	var rows: int = 6
	var cell_w: float = r.size.x / float(cols)
	var cell_h: float = r.size.y / float(rows)
	var f: Font = get_theme_default_font()
	var fs_label: int = 11

	# Stabilized sectors (skypumps) — light up squares by team.
	var sp: Dictionary = _skypump_sector_counts()
	for team_id in [0, 1]:
		var dt: Dictionary = sp.get(team_id, {})
		for sec in dt.keys():
			var ss: String = str(sec)
			if ss.length() < 2:
				continue
			var c: int = int(ss.unicode_at(0) - 65)
			var rn: int = int(ss.substr(1, ss.length() - 1).to_int()) - 1
			if c < 0 or c >= 6 or rn < 0 or rn >= 6:
				continue
			var rr := Rect2(r.position + Vector2(cell_w * c, cell_h * rn), Vector2(cell_w, cell_h))
			var cnt: int = int(dt.get(sec, 1))
			var fill: Color = _team_color(team_id, false)
			fill.a = clamp(0.06 + 0.04 * float(cnt), 0.06, 0.22)
			draw_rect(rr.grow(-1.0), fill, true)
			if cnt >= 2:
				var br: Color = _team_color(team_id, true)
				br.a = 0.35
				draw_rect(rr.grow(-1.0), br, false, 1.0)
				# Warp-capable label (2+ skypumps)
				if f != null:
					var tc: Color = br
					tc.a = 0.55
					draw_string(f, rr.position + Vector2(5.0, 14.0), "WARP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, tc)

	# Uplink placement helper: highlight eligible target sectors for our team.
	if _uplink_place_mode != UplinkPlaceMode.NONE:
		var need: int = 2 if _uplink_place_mode == UplinkPlaceMode.REQUEST else 1
		var mydt: Dictionary = sp.get(_me_team, {})
		for sec2 in mydt.keys():
			var cnt2: int = int(mydt.get(sec2, 0))
			if cnt2 < need:
				continue
			var ss2: String = str(sec2)
			if ss2.length() < 2:
				continue
			var c2: int = int(ss2.unicode_at(0) - 65)
			var rn2: int = int(ss2.substr(1, ss2.length() - 1).to_int()) - 1
			if c2 < 0 or c2 >= 6 or rn2 < 0 or rn2 >= 6:
				continue
			var rr_ok := Rect2(r.position + Vector2(cell_w * c2, cell_h * rn2), Vector2(cell_w, cell_h))
			var oc: Color = Color(1, 1, 1, 0.20)
			var w: float = 2.0 if need == 2 else 1.5
			draw_rect(rr_ok.grow(-3.0), oc, false, w)

	# Uplink sectors (team bases/control points) — show a small marker and label.
	var uplinks: Array = _uplink_sector_marks()
	for u in uplinks:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var ud: Dictionary = u
		var tU: int = int(ud.get("team", -1))
		var secU: String = str(ud.get("sec", ""))
		if secU.length() < 2:
			continue
		var cU: int = int(secU.unicode_at(0) - 65)
		var rU: int = int(secU.substr(1, secU.length() - 1).to_int()) - 1
		if cU < 0 or cU >= 6 or rU < 0 or rU >= 6:
			continue
		var rrU := Rect2(r.position + Vector2(cell_w * float(cU), cell_h * float(rU)), Vector2(cell_w, cell_h))
		var brU: Color = _team_color(tU, true)
		brU.a = 0.55
		draw_rect(rrU.grow(-1.0), brU, false, 1.0)
		if f != null:
			var tcU: Color = brU
			tcU.a = 0.75
			draw_string(f, rrU.position + Vector2(5.0, rrU.size.y - 6.0), "LINK", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, tcU)

	# Orbit sectors (starships). Orbit sector == ship's (sx,sy).
	var ship_tex_blue: Texture2D = _atlas16(_TEX_SHIP_BLUE, 0)
	var ship_tex_red: Texture2D = _atlas16(_TEX_SHIP_RED, 0)
	for s in _ships:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		var team: int = int(sd.get("team", 0))
		var sx: int = int(sd.get("sx", 0))
		var sy: int = int(sd.get("sy", 0))
		if sx < 0 or sx >= 6 or sy < 0 or sy >= 6:
			continue
		var rr2 := Rect2(r.position + Vector2(cell_w * float(sx), cell_h * float(sy)), Vector2(cell_w, cell_h))
		var st: String = str(sd.get("state", "online")).to_lower()
		var online: bool = (st == "online")
		var fill2: Color = _team_color(team, false)
		fill2.a = 0.08 if online else 0.04
		draw_rect(rr2.grow(-2.0), fill2, true)
		var tex: Texture2D = ship_tex_blue if team == 1 else ship_tex_red
		if tex != null:
			var icon_sz: Vector2 = Vector2(14.0, 14.0)
			var ipos: Vector2 = rr2.position + (rr2.size - icon_sz) * 0.5
			draw_texture_rect(tex, Rect2(ipos, icon_sz), false, Color(1, 1, 1, 0.95 if online else 0.55))

	# Selected starship orbit highlight (Uplink tab).
	if _tab == TabMode.UPLINK:
		for sd3 in _ships_for_team(_me_team):
			if int(sd3.get("slot", 0)) != _uplink_ship_idx:
				continue
			var sx3: int = int(sd3.get("sx", 0))
			var sy3: int = int(sd3.get("sy", 0))
			if sx3 < 0 or sx3 >= 6 or sy3 < 0 or sy3 >= 6:
				break
			var rrsel := Rect2(r.position + Vector2(cell_w * float(sx3), cell_h * float(sy3)), Vector2(cell_w, cell_h))
			var sc: Color = _team_color(_me_team, true)
			sc.a = 0.95
			draw_rect(rrsel, sc, false, 3.0)
			break

	# Player sector
	var ps: String = _sector
	if ps.length() >= 2:
		var c3: int = int(ps.unicode_at(0) - 65)
		var rn3: int = int(ps.substr(1, ps.length() - 1).to_int()) - 1
		if c3 >= 0 and c3 < 6 and rn3 >= 0 and rn3 < 6:
			var rrp := Rect2(r.position + Vector2(cell_w * c3, cell_h * rn3), Vector2(cell_w, cell_h))
			var colp := _team_color(_me_team, true)
			colp.a = 0.95
			draw_rect(rrp, colp, false, 2.0)

	# Hover sector
	if _hover_on_map and _hover_sector.length() >= 2:
		var hc: int = int(_hover_sector.unicode_at(0) - 65)
		var hrn: int = int(_hover_sector.substr(1, _hover_sector.length() - 1).to_int()) - 1
		if hc >= 0 and hc < 6 and hrn >= 0 and hrn < 6:
			var rrh := Rect2(r.position + Vector2(cell_w * hc, cell_h * hrn), Vector2(cell_w, cell_h))
			draw_rect(rrh, Color(1, 1, 1, 0.35), false, 1.0)

func _draw_hover_tooltip(f: Font, fs: int) -> void:
	if not _hover_on_map:
		return
	var lines: Array[String] = []
	lines.append("SECTOR %s" % _hover_sector)
	lines.append("X %.0f  Z %.0f" % [_hover_world_xz.x, _hover_world_xz.y])
	if not _hover_entity.is_empty():
		lines.append(_hover_entity)
	var pad: float = 6.0
	var w: float = 0.0
	for s in lines:
		w = max(w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var line_h: float = 16.0
	var h: float = float(len(lines)) * line_h
	var pos := _hover_screen + Vector2(14, 14)
	# Clamp inside map rect
	var tw: float = w + pad * 2.0
	var th: float = h + pad * 2.0
	if pos.x + tw > _map_r.position.x + _map_r.size.x:
		pos.x = (_map_r.position.x + _map_r.size.x) - tw - 2.0
	if pos.y + th > _map_r.position.y + _map_r.size.y:
		pos.y = (_map_r.position.y + _map_r.size.y) - th - 2.0
	var rr := Rect2(pos, Vector2(tw, th))
	# Shadow + frame (more Wulfram-like)
	draw_rect(Rect2(rr.position + Vector2(2, 2), rr.size), Color(0, 0, 0, 0.35), true)
	draw_rect(rr, Color(0, 0, 0, 0.78), true)
	draw_rect(rr, Color(0, 0, 0, 0.90), false, 1.0)
	draw_rect(rr.grow(-1.0), Color(1, 1, 1, 0.18), false, 1.0)
	# Header band
	var header_h: float = line_h + 2.0
	draw_rect(Rect2(rr.position, Vector2(rr.size.x, header_h)), Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.14), true)
	var y: float = rr.position.y + pad + 12.0
	for i in range(lines.size()):
		var s2: String = lines[i]
		var col: Color = HudStyle.TEXT if i == 0 else Color(1, 1, 1, 0.90)
		if i == lines.size() - 1 and not _hover_entity.is_empty():
			col = HudStyle.TEXT_MUTED
		draw_string(f, Vector2(rr.position.x + pad, y), s2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += line_h


func _draw_ship_triangle(center: Vector2, yaw: float, size: float, col: Color) -> void:
	# Pointing direction: yaw around +Y; map assumes +Z down.
	var ang: float = yaw
	# Triangle points in screen space
	var fwd := Vector2(sin(ang), cos(ang))
	var right := Vector2(fwd.y, -fwd.x)
	var p1 := center + fwd * size
	var p2 := center - fwd * size * 0.75 + right * size * 0.65
	var p3 := center - fwd * size * 0.75 - right * size * 0.65
	draw_colored_polygon([p1, p2, p3], col)
