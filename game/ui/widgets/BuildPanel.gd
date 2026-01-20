extends Control

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")
const _BTN_TEX: Texture2D = preload("res://assets/wulfram_textures/extracted/pannel_map_hanging_button.png")

# Wulfram-inspired build HUD.
#
# Graphical build slots plus placement preview feedback.
# No external textures required (procedural drawing).

var cargo: int = 0
var cargo_max: int = 0

var cost_powercell: int = 1
var cost_turret: int = 1

var active_kind: String = "" # "powercell" or "turret" or ""
var active_ok: bool = false
var active_reason: String = ""

var _show: bool = true

func set_build_state(p_cargo: int, p_cargo_max: int, p_cost_pc: int, p_cost_turret: int, p_active_kind: String, p_active_ok: bool, p_active_reason: String) -> void:
	cargo = p_cargo
	cargo_max = p_cargo_max
	cost_powercell = p_cost_pc
	cost_turret = p_cost_turret
	active_kind = p_active_kind
	active_ok = p_active_ok
	active_reason = p_active_reason
	queue_redraw()

func set_visible_enabled(v: bool) -> void:
	_show = v
	visible = v

func _get_slot_rect(i: int) -> Rect2:
	# Two slots side by side.
	var pad: float = 8.0
	var slot: float = 56.0
	var x0: float = pad + float(i) * (slot + 8.0)
	return Rect2(Vector2(x0, pad), Vector2(slot, slot))

func _draw() -> void:
	if not _show:
		return
	var f: Font = get_theme_default_font()
	if f == null:
		return

	# Panel background (shared Wulfram skin).
	var bg: Rect2 = Rect2(Vector2.ZERO, size)
	HudStyle.draw_panel_back(self, bg)

	# Title + cargo.
	var title_pos: Vector2 = Vector2(10, 4)
	draw_string(f, title_pos + Vector2(0, 14), "BUILD", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudStyle.TEXT)
	var ctxt: String = "%d/%d" % [cargo, cargo_max]
	draw_string(f, Vector2(size.x - 10, 18), ctxt, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.95))

	# Slots.
	_draw_slot(f, 0, "powercell", "B", cost_powercell)
	_draw_slot(f, 1, "turret", "T", cost_turret)

	# Active reason line (when holding a build key).
	if not active_kind.is_empty():
		var msg: String = "OK" if active_ok else active_reason
		var col: Color = HudStyle.OK if active_ok else HudStyle.BAD
		draw_string(f, Vector2(10, size.y - 8), "%s: %s" % [active_kind.to_upper(), msg], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

func _draw_slot(f: Font, i: int, kind: String, key: String, cost: int) -> void:
	var r: Rect2 = _get_slot_rect(i)
	var have: bool = cargo >= cost

	# Slot background uses Wulfram bitmap button skin.
	var st: int = 0
	if not have:
		st = 2
	if active_kind == kind:
		st = 1
	HudStyle.draw_button_back(self, r, st, HudStyle.ACCENT)

	# Border highlight.
	var is_active: bool = (active_kind == kind)
	var border_col: Color
	if is_active:
		border_col = Color(0.6, 1.0, 0.6, 0.9) if active_ok else Color(1.0, 0.4, 0.4, 0.9)
	else:
		border_col = Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.30)
	draw_rect(r, border_col, false, 2.0 if is_active else 1.0)

	# Key tag.
	draw_string(f, r.position + Vector2(6, 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudStyle.TEXT)

	# Icon.
	if kind == "powercell":
		_draw_icon_powercell(r)
	else:
		_draw_icon_turret(r)

	# Cost (bottom-right) + availability.
	var col: Color = Color(0.97, 0.92, 0.78, 0.95) if have else HudStyle.BAD
	draw_string(f, r.position + Vector2(r.size.x - 6, r.size.y - 6), str(cost), HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, col)
	if not have:
		draw_string(f, r.position + Vector2(6, r.size.y - 6), "NO", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudStyle.BAD)

func _draw_icon_powercell(r: Rect2) -> void:
	# Simple battery + bolt.
	var cx: float = r.position.x + r.size.x * 0.52
	var cy: float = r.position.y + r.size.y * 0.52
	var w: float = 24
	var h: float = 18
	var body: Rect2 = Rect2(Vector2(cx - w * 0.5, cy - h * 0.5), Vector2(w, h))
	draw_rect(body, Color(0.85, 0.90, 1.0, 0.25), true)
	draw_rect(body, Color(0.85, 0.90, 1.0, 0.65), false, 1.0)
	var nub: Rect2 = Rect2(Vector2(body.position.x + body.size.x, body.position.y + body.size.y * 0.35), Vector2(4, body.size.y * 0.30))
	draw_rect(nub, Color(0.85, 0.90, 1.0, 0.65), true)
	# Bolt
	var p0: Vector2 = Vector2(cx - 2, cy - 7)
	var p1: Vector2 = Vector2(cx + 3, cy - 2)
	var p2: Vector2 = Vector2(cx - 1, cy - 2)
	var p3: Vector2 = Vector2(cx + 2, cy + 6)
	draw_line(p0, p1, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.95), 2.0)
	draw_line(p1, p2, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.95), 2.0)
	draw_line(p2, p3, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.95), 2.0)

func _draw_icon_turret(r: Rect2) -> void:
	# Base + barrel.
	var cx: float = r.position.x + r.size.x * 0.52
	var cy: float = r.position.y + r.size.y * 0.56
	# Base
	var base: Rect2 = Rect2(Vector2(cx - 12, cy + 4), Vector2(24, 10))
	draw_rect(base, Color(0.85, 0.90, 1.0, 0.25), true)
	draw_rect(base, Color(0.85, 0.90, 1.0, 0.65), false, 1.0)
	# Head
	var head: Rect2 = Rect2(Vector2(cx - 10, cy - 6), Vector2(20, 12))
	draw_rect(head, Color(0.85, 0.90, 1.0, 0.20), true)
	draw_rect(head, Color(0.85, 0.90, 1.0, 0.65), false, 1.0)
	# Barrel
	draw_line(Vector2(cx + 8, cy - 1), Vector2(cx + 18, cy - 4), Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.95), 3.0)
	draw_circle(Vector2(cx - 6, cy - 1), 2.0, Color(HudStyle.ACCENT.r, HudStyle.ACCENT.g, HudStyle.ACCENT.b, 0.95))