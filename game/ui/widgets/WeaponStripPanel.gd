extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# Wulfram-like top-right weapon strip: icons + tiny readiness bars.
# Two rows: (Primary, Secondary) then (Hunter, Flare, Mine).
# Uses the same set_weapons(...) signature as the legacy WeaponPanel.

# Icon sources (some are vertical strips; we crop a 16x16 tile via AtlasTexture).
const _TEX_GUN: Texture2D = preload("res://assets/wulfram_textures/extracted/gun.png")
const _TEX_GUN2: Texture2D = preload("res://assets/wulfram_textures/extracted/gun2.png")
const _TEX_PULSE_RED: Texture2D = preload("res://assets/wulfram_textures/extracted/pulsered.png")
const _TEX_PULSE_BLUE: Texture2D = preload("res://assets/wulfram_textures/extracted/pulseblue.png")
const _TEX_ROCKET: Texture2D = preload("res://assets/wulfram_textures/extracted/rocket.png")
const _TEX_FLARE_RED: Texture2D = preload("res://assets/wulfram_textures/extracted/flare_red_tank_normal.png")
const _TEX_FLARE_BLUE: Texture2D = preload("res://assets/wulfram_textures/extracted/flare_blue_tank_normal.png")
const _TEX_MINE_RED: Texture2D = preload("res://assets/wulfram_textures/extracted/mine_red_tank_normal.png")
const _TEX_MINE_BLUE: Texture2D = preload("res://assets/wulfram_textures/extracted/mine_blue_tank_normal.png")

var _tex_bar_bg: Texture2D = null
var _tex_bar_fill: Texture2D = null

var _font: Font = null
var _font_size: int = 12

var _last_team: int = -99
var _last_veh: String = ""

var _icons: Dictionary = {
	"primary": null,
	"secondary": null,
	"hunter": null,
	"flare": null,
	"mine": null,
}

var _entries: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex_bar_bg = HudStyle.tex("blue_bar_back")
	_tex_bar_fill = HudStyle.tex("yellow_bar")
	_font = get_theme_default_font()
	_font_size = max(10, get_theme_default_font_size() - 2)
	_apply_icons("tank", 1)
	_reset_entries()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

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

func _apply_icons(veh: String, team: int) -> void:
	_icons["primary"] = _atlas16(_TEX_GUN, 0)
	if veh == "tank":
		_icons["secondary"] = _atlas16(_TEX_PULSE_RED if team == 0 else _TEX_PULSE_BLUE, 0)
	else:
		_icons["secondary"] = _atlas16(_TEX_GUN2, 0)
	_icons["hunter"] = _atlas16(_TEX_ROCKET, 0)
	_icons["flare"] = _TEX_FLARE_RED if team == 0 else _TEX_FLARE_BLUE
	_icons["mine"] = _TEX_MINE_RED if team == 0 else _TEX_MINE_BLUE

func _reset_entries() -> void:
	# Order matters; we render in two rows.
	_entries = [
		{ "id": "primary", "key": "1", "frac": 1.0, "can": true, "active": false, "note": "" },
		{ "id": "secondary", "key": "2", "frac": 1.0, "can": true, "active": false, "note": "" },
		{ "id": "hunter", "key": "3", "frac": 1.0, "can": true, "active": false, "note": "" },
		{ "id": "flare", "key": "4", "frac": 1.0, "can": true, "active": false, "note": "" },
		{ "id": "mine", "key": "5", "frac": 1.0, "can": true, "active": false, "note": "" },
	]

func _draw_bar(r: Rect2, frac: float, a: float) -> void:
	var rr := r
	if _tex_bar_bg != null:
		draw_texture_rect(_tex_bar_bg, rr, true, Color(1, 1, 1, 0.85 * a))
	else:
		draw_rect(rr, Color(0, 0, 0, 0.35 * a), true)
	# Fill
	# Godot 4.5.x sometimes can't infer type here; be explicit and use clampf.
	var w: float = rr.size.x * clampf(frac, 0.0, 1.0)
	if w <= 0.5:
		return
	var fr := Rect2(rr.position, Vector2(w, rr.size.y))
	if _tex_bar_fill != null:
		draw_texture_rect(_tex_bar_fill, fr, true, Color(1, 1, 1, 0.95 * a))
	else:
		draw_rect(fr, Color(0.95, 0.75, 0.20, 0.85 * a), true)

func _draw_key(text: String, pos: Vector2, a: float) -> void:
	if _font == null:
		return
	# Simple shadow + text for crunchy readability.
	draw_string(_font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(0, 0, 0, 0.85 * a))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(0.97, 0.92, 0.78, 0.95 * a))

func _draw() -> void:
	# No big panel background; the strip floats like in Wulfram.
	var pad: float = 2.0
	var gap: float = 5.0
	var slot_w: float = 30.0
	var slot_h: float = 26.0
	var bar_h: float = 4.0
	var row_gap: float = 5.0

	# Row widths
	var row1_w: float = (2 * slot_w) + gap
	var row2_w: float = (3 * slot_w) + (2 * gap)

	var x_right: float = size.x - pad
	var y0: float = pad
	var y1: float = y0 + slot_h + bar_h + row_gap

	# Draw row 1 (primary, secondary), right-aligned to row 2 width.
	var x1: float = x_right - row2_w
	_draw_slot(_entries[0], Rect2(Vector2(x1 + (row2_w - row1_w), y0), Vector2(slot_w, slot_h + bar_h)))
	_draw_slot(_entries[1], Rect2(Vector2(x1 + (row2_w - row1_w) + slot_w + gap, y0), Vector2(slot_w, slot_h + bar_h)))

	# Draw row 2
	_draw_slot(_entries[2], Rect2(Vector2(x1, y1), Vector2(slot_w, slot_h + bar_h)))
	_draw_slot(_entries[3], Rect2(Vector2(x1 + slot_w + gap, y1), Vector2(slot_w, slot_h + bar_h)))
	_draw_slot(_entries[4], Rect2(Vector2(x1 + 2 * (slot_w + gap), y1), Vector2(slot_w, slot_h + bar_h)))

func _draw_slot(e: Dictionary, rect: Rect2) -> void:
	var can_use: bool = bool(e.get("can", true))
	var active: bool = bool(e.get("active", false))
	var frac: float = float(e.get("frac", 1.0))
	var state: int = 0
	if not can_use:
		state = 2
	elif active:
		state = 1

	HudStyle.draw_button_back(self, rect, state, HudStyle.ACCENT)
	var a: float = 1.0 if can_use else 0.65

	# Icon
	var icon: Texture2D = _icons.get(String(e.get("id", "")), null)
	if icon != null:
		var ir := Rect2(rect.position + Vector2(6, 4), Vector2(18, 18))
		draw_texture_rect(icon, ir, false, Color(1, 1, 1, a))

	# Key label (top-left)
	_draw_key(String(e.get("key", "")), rect.position + Vector2(3, 12), a)

	# Tiny readiness bar
	var br := Rect2(rect.position + Vector2(3, rect.size.y - 4.0), Vector2(rect.size.x - 6.0, 3.0))
	_draw_bar(br, frac, a)

func set_weapons(
		veh: String,
		team: int,
		fuel: float,
		fuel_max: float,
		charge: float,
		charge_max: float,
		cd_fire: float,
		cd_pulse: float,
		cd_hunter: float,
		cd_flare: float,
		cd_mine: float,
		auto_rate_hz: float,
		pulse_cd: float,
		hunter_cd: float,
		flare_cd: float,
		mine_cd: float,
		cost_auto: float,
		cost_pulse: float,
		cost_hunter: float,
		cost_flare: float,
		cost_mine: float,
		beam_cost_per_s: float,
		has_valid_target: bool,
		firing_primary: bool,
		firing_secondary: bool
	) -> void:
	if team != _last_team or veh != _last_veh:
		_last_team = team
		_last_veh = veh
		_apply_icons(veh, team)

	_reset_entries()

	# Primary
	var auto_interval: float = 0.25
	if auto_rate_hz > 0.001:
		auto_interval = 1.0 / auto_rate_hz
	var can_auto: bool = (cd_fire <= 0.001 and fuel >= cost_auto)
	_entries[0]["can"] = can_auto
	_entries[0]["active"] = firing_primary and can_auto
	_entries[0]["frac"] = clamp(1.0 - (cd_fire / max(0.001, auto_interval)), 0.0, 1.0)

	# Secondary
	if veh == "tank":
		var can_pulse: bool = (cd_pulse <= 0.001 and fuel >= cost_pulse)
		_entries[1]["can"] = can_pulse
		_entries[1]["active"] = firing_secondary and can_pulse
		_entries[1]["frac"] = clamp(1.0 - (cd_pulse / max(0.05, pulse_cd)), 0.0, 1.0)
	else:
		# Beam: show fuel fraction; usable when we have some fuel.
		var can_beam: bool = (fuel > 0.05)
		_entries[1]["can"] = can_beam
		_entries[1]["active"] = firing_secondary and can_beam
		_entries[1]["frac"] = clamp(fuel / max(1.0, fuel_max), 0.0, 1.0)

	# Hunter (requires target)
	var can_hunter: bool = (has_valid_target and cd_hunter <= 0.001 and fuel >= cost_hunter)
	_entries[2]["can"] = can_hunter
	_entries[2]["active"] = false
	_entries[2]["frac"] = clamp(1.0 - (cd_hunter / max(0.05, hunter_cd)), 0.0, 1.0)

	# Flare
	var can_flare: bool = (cd_flare <= 0.001 and fuel >= cost_flare)
	_entries[3]["can"] = can_flare
	_entries[3]["active"] = false
	_entries[3]["frac"] = clamp(1.0 - (cd_flare / max(0.05, flare_cd)), 0.0, 1.0)

	# Mine
	var can_mine: bool = (cd_mine <= 0.001 and fuel >= cost_mine)
	_entries[4]["can"] = can_mine
	_entries[4]["active"] = false
	_entries[4]["frac"] = clamp(1.0 - (cd_mine / max(0.05, mine_cd)), 0.0, 1.0)

	queue_redraw()
