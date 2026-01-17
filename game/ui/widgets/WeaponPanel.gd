extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")

# Wulfram-inspired weapon HUD: compact list with cooldown bars and availability.
# This build adds Wulfram bitmap button states (normal/selected/dark) and bitmap weapon icons.

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

@onready var row_primary: HBoxContainer = $VBox/Primary
@onready var row_secondary: HBoxContainer = $VBox/Secondary
@onready var row_hunter: HBoxContainer = $VBox/Hunter
@onready var row_flare: HBoxContainer = $VBox/Flare
@onready var row_mine: HBoxContainer = $VBox/Mine

@onready var key_primary: Label = $VBox/Primary/Key
@onready var name_primary: Label = $VBox/Primary/Name
@onready var bar_primary: WulframBar = $VBox/Primary/Bar
@onready var st_primary: Label = $VBox/Primary/State

@onready var key_secondary: Label = $VBox/Secondary/Key
@onready var name_secondary: Label = $VBox/Secondary/Name
@onready var bar_secondary: WulframBar = $VBox/Secondary/Bar
@onready var st_secondary: Label = $VBox/Secondary/State

@onready var key_hunter: Label = $VBox/Hunter/Key
@onready var name_hunter: Label = $VBox/Hunter/Name
@onready var bar_hunter: WulframBar = $VBox/Hunter/Bar
@onready var st_hunter: Label = $VBox/Hunter/State

@onready var key_flare: Label = $VBox/Flare/Key
@onready var name_flare: Label = $VBox/Flare/Name
@onready var bar_flare: WulframBar = $VBox/Flare/Bar
@onready var st_flare: Label = $VBox/Flare/State

@onready var key_mine: Label = $VBox/Mine/Key
@onready var name_mine: Label = $VBox/Mine/Name
@onready var bar_mine: WulframBar = $VBox/Mine/Bar
@onready var st_mine: Label = $VBox/Mine/State

@onready var icon_primary: TextureRect = $VBox/Primary/Icon
@onready var icon_secondary: TextureRect = $VBox/Secondary/Icon
@onready var icon_hunter: TextureRect = $VBox/Hunter/Icon
@onready var icon_flare: TextureRect = $VBox/Flare/Icon
@onready var icon_mine: TextureRect = $VBox/Mine/Icon

var _last_team: int = -99
var _last_veh: String = ""

# Per-row button state for backgrounds.
# 0=normal, 1=selected, 2=dark/disabled
var _row_state: Dictionary = {
	"Primary": 0,
	"Secondary": 0,
	"Hunter": 0,
	"Flare": 0,
	"Mine": 0,
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Textured Wulfram-ish bars (cooldown readiness).
	bar_primary.set_textures("blue_bar_back", "yellow_bar")
	bar_secondary.set_textures("blue_bar_back", "yellow_bar")
	bar_hunter.set_textures("blue_bar_back", "yellow_bar")
	bar_flare.set_textures("blue_bar_back", "yellow_bar")
	bar_mine.set_textures("blue_bar_back", "yellow_bar")

	HudStyle.apply_label(key_primary, true)
	HudStyle.apply_label(name_primary, false)
	HudStyle.apply_label(st_primary, false)
	HudStyle.apply_label(key_secondary, true)
	HudStyle.apply_label(name_secondary, false)
	HudStyle.apply_label(st_secondary, false)
	HudStyle.apply_label(key_hunter, true)
	HudStyle.apply_label(name_hunter, false)
	HudStyle.apply_label(st_hunter, false)
	HudStyle.apply_label(key_flare, true)
	HudStyle.apply_label(name_flare, false)
	HudStyle.apply_label(st_flare, false)
	HudStyle.apply_label(key_mine, true)
	HudStyle.apply_label(name_mine, false)
	HudStyle.apply_label(st_mine, false)

	# Static labels
	key_primary.text = "LMB"
	key_secondary.text = "RMB"
	key_hunter.text = "E"
	key_flare.text = "F"
	key_mine.text = "G"

	name_primary.text = "AUTOCANNON"
	name_hunter.text = "HUNTER"
	name_flare.text = "FLARE"
	name_mine.text = "MINE"

	# Default icons (tank/blue). Real icons are applied on first set_weapons().
	_apply_icons("tank", 1)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	HudStyle.draw_panel_back(self, Rect2(Vector2.ZERO, size))
	# Button backgrounds behind each row.
	_draw_row_back(row_primary)
	_draw_row_back(row_secondary)
	_draw_row_back(row_hunter)
	_draw_row_back(row_flare)
	_draw_row_back(row_mine)

func _draw_row_back(row: Control) -> void:
	if row == null or not row.visible:
		return
	var rr: Rect2 = _to_local_rect(row.get_global_rect())
	# Slight grow to cover container gaps.
	rr = rr.grow_individual(2.0, 1.0, 2.0, 1.0)
	var st: int = int(_row_state.get(row.name, 0))
	HudStyle.draw_button_back(self, rr, st, HudStyle.ACCENT)

func _to_local_rect(global_r: Rect2) -> Rect2:
	var my: Rect2 = get_global_rect()
	return Rect2(global_r.position - my.position, global_r.size)

func _atlas16(src: Texture2D, index: int = 0) -> Texture2D:
	# Many Wulfram UI/weapon sprites are packed as vertical strips.
	# We use the top 16x16 tile by default.
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
	# Primary
	icon_primary.texture = _atlas16(_TEX_GUN, 0)

	# Secondary: tank=PULSE (team colored), scout=BEAM (alt gun)
	if veh == "tank":
		icon_secondary.texture = _atlas16(_TEX_PULSE_RED if team == 0 else _TEX_PULSE_BLUE, 0)
	else:
		icon_secondary.texture = _atlas16(_TEX_GUN2, 0)

	# Hunter / Flare / Mine
	icon_hunter.texture = _atlas16(_TEX_ROCKET, 0)
	icon_flare.texture = _TEX_FLARE_RED if team == 0 else _TEX_FLARE_BLUE
	icon_mine.texture = _TEX_MINE_RED if team == 0 else _TEX_MINE_BLUE

func _set_row(row: HBoxContainer, state_label: Label, bar: WulframBar, cd_left: float, cd_max: float, can_use: bool, active: bool, blocked_reason: String) -> void:
	# Cooldown bar: full when ready, empty when fully cooling down.
	var m: float = max(0.001, cd_max)
	var ready_frac: float = clamp(1.0 - (cd_left / m), 0.0, 1.0)
	bar.set_fraction(ready_frac)

	var st: int = 0
	if not can_use:
		st = 2
	elif active:
		st = 1
	_row_state[row.name] = st

	if can_use:
		state_label.text = "FIRE" if active else "READY"
		row.modulate = Color(1, 1, 1, 1)
	else:
		state_label.text = blocked_reason
		row.modulate = Color(1, 1, 1, 0.55)

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
	# Update icons if needed.
	if team != _last_team or veh != _last_veh:
		_last_team = team
		_last_veh = veh
		_apply_icons(veh, team)

	# Primary always exists.
	var auto_interval: float = 0.25
	if auto_rate_hz > 0.001:
		auto_interval = 1.0 / auto_rate_hz
	var can_auto: bool = (cd_fire <= 0.001 and fuel >= cost_auto)
	var auto_reason: String = "COOLDOWN" if cd_fire > 0.001 else ("NO FUEL" if fuel < cost_auto else "")
	_set_row(row_primary, st_primary, bar_primary, cd_fire, auto_interval, can_auto, firing_primary, auto_reason)

	# Secondary depends on vehicle.
	if veh == "tank":
		name_secondary.text = "PULSE"
		row_secondary.visible = true
		var can_pulse: bool = (cd_pulse <= 0.001 and fuel >= cost_pulse)
		var pulse_reason: String = "COOLDOWN" if cd_pulse > 0.001 else ("NO FUEL" if fuel < cost_pulse else "")
		_set_row(row_secondary, st_secondary, bar_secondary, cd_pulse, max(0.05, pulse_cd), can_pulse, firing_secondary, pulse_reason)
	else:
		name_secondary.text = "BEAM"
		row_secondary.visible = true
		# Beam has no cooldown; show readiness based on fuel.
		var can_beam: bool = (fuel > 0.05)
		var beam_reason: String = "NO FUEL" if not can_beam else ""
		# Use bar as 'fuel fraction' reference for beam (Wulfram-ish).
		bar_secondary.set_fraction(clamp(fuel / max(1.0, fuel_max), 0.0, 1.0))
		st_secondary.text = "BEAM" if firing_secondary else ("READY" if can_beam else beam_reason)
		row_secondary.modulate = Color(1, 1, 1, 1) if can_beam else Color(1, 1, 1, 0.55)
		_row_state[row_secondary.name] = 1 if firing_secondary else (0 if can_beam else 2)

	# Hunter
	var can_hunter: bool = (has_valid_target and cd_hunter <= 0.001 and fuel >= cost_hunter)
	var hunter_reason: String = "NO TGT"
	if has_valid_target:
		hunter_reason = "COOLDOWN" if cd_hunter > 0.001 else ("NO FUEL" if fuel < cost_hunter else "")
	_set_row(row_hunter, st_hunter, bar_hunter, cd_hunter, max(0.05, hunter_cd), can_hunter, false, hunter_reason)

	# Flare
	var can_flare: bool = (cd_flare <= 0.001 and fuel >= cost_flare)
	var flare_reason: String = "COOLDOWN" if cd_flare > 0.001 else ("NO FUEL" if fuel < cost_flare else "")
	_set_row(row_flare, st_flare, bar_flare, cd_flare, max(0.05, flare_cd), can_flare, false, flare_reason)

	# Mine
	var can_mine: bool = (cd_mine <= 0.001 and fuel >= cost_mine)
	var mine_reason: String = "COOLDOWN" if cd_mine > 0.001 else ("NO FUEL" if fuel < cost_mine else "")
	_set_row(row_mine, st_mine, bar_mine, cd_mine, max(0.05, mine_cd), can_mine, false, mine_reason)

	queue_redraw()
