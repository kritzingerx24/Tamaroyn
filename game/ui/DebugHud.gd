extends CanvasLayer

const HudStyle := preload("res://game/ui/widgets/HudStyle.gd")
const BottomBarScript := preload("res://game/ui/widgets/BottomBar.gd")

@onready var label: Label = $Panel/Label
@onready var status_label: Label = $Panel/StatusLabel
@onready var toast_label: Label = $Panel/ToastLabel
@onready var crosshair: Label = $CenterOverlay/Crosshair
@onready var reticle: TextureRect = get_node_or_null("CenterOverlay/Reticle")
@onready var hit_label: Label = $CenterOverlay/Hit

# Structured HUD widgets (added in v0.12.x HUD upgrade). These are optional so older
# scenes can still run without errors if the nodes are missing.
@onready var stats_panel: Control = get_node_or_null("StatsPanel")
@onready var net_panel: Control = get_node_or_null("NetPanel")

@onready var veh_label: Label = get_node_or_null("StatsPanel/VBox/Veh")
@onready var power_label: Label = get_node_or_null("StatsPanel/VBox/Power")
@onready var hp_bar: Node = get_node_or_null("StatsPanel/VBox/HPRow/Bar")
@onready var hp_val: Label = get_node_or_null("StatsPanel/VBox/HPRow/Val")
@onready var fuel_bar: Node = get_node_or_null("StatsPanel/VBox/FuelRow/Bar")
@onready var fuel_val: Label = get_node_or_null("StatsPanel/VBox/FuelRow/Val")
@onready var charge_row: Control = get_node_or_null("StatsPanel/VBox/ChargeRow")
@onready var charge_bar: Node = get_node_or_null("StatsPanel/VBox/ChargeRow/Bar")
@onready var charge_val: Label = get_node_or_null("StatsPanel/VBox/ChargeRow/Val")
@onready var cargo_val: Label = get_node_or_null("StatsPanel/VBox/CargoRow/Val")
@onready var speed_val: Label = get_node_or_null("StatsPanel/VBox/SpeedRow/Val")

@onready var net_label: Label = get_node_or_null("NetPanel/Label")

@onready var minimap: Node = get_node_or_null("MiniMapPanel/MiniMap")

@onready var weapon_panel: Node = get_node_or_null("WeaponPanel")

# Target HUD overlay (procedural, Wulfram-style).
@onready var target_panel: Node = get_node_or_null("CenterOverlay/TargetPanel")

# If present in the scene, prefer the procedural BuildPanel widget (more Wulfram-like).
@onready var build_widget: Node = get_node_or_null("BuildPanel")

# Build HUD panel (created programmatically; keeps editor work minimal).
var build_panel: Panel = null
var _bp_rows: Dictionary = {}
var _bp_hint: Label = null

var _hit_timer: SceneTreeTimer
var _toast_seq: int = 0

var _hud_compact: bool = false

var _bottom_bar: Control = null

func _ready() -> void:
	_ensure_bottom_bar()
	# Prefer a dedicated toast label (so we can hide the big debug panel by default).
	var t: Label = get_node_or_null("ToastOverlay")
	if t != null:
		toast_label = t
	_apply_wulfram_skin()
	# Default to a compact HUD (Wulfram has no giant debug panel). Toggle with F1.
	set_compact(true)
	# Only create the legacy build panel when the widget isn't present.
	if build_widget == null:
		_ensure_build_panel()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# F1: toggle compact HUD (hide big debug text panel)
		if event.keycode == KEY_F1:
			set_compact(not _hud_compact)
			get_viewport().set_input_as_handled()
			return
		# F2: toggle net panel
		if event.keycode == KEY_F2 and net_panel != null:
			net_panel.visible = not net_panel.visible
			get_viewport().set_input_as_handled()
			return
		# F4: toggle stats panel
		if event.keycode == KEY_F4 and stats_panel != null:
			stats_panel.visible = not stats_panel.visible
			get_viewport().set_input_as_handled()
			return

func set_text(t: String) -> void:
	label.text = t

func set_reticle_visible(v: bool) -> void:
	if reticle != null and reticle.texture != null:
		reticle.visible = v
		# Keep the legacy "+" crosshair off when we have a real reticle.
		if crosshair != null:
			crosshair.visible = false
	else:
		if crosshair != null:
			crosshair.visible = v
	# Hit label only shows briefly when we call show_hit().

func show_hit(duration: float = 0.18) -> void:
	if hit_label == null:
		return
	hit_label.visible = true
	if _hit_timer != null:
		# let the old timer expire naturally; we'll just create a new one
		pass
	_hit_timer = get_tree().create_timer(duration)
	_hit_timer.timeout.connect(func() -> void:
		if is_instance_valid(hit_label):
			hit_label.visible = false
	)


func set_status(t: String) -> void:
	if status_label != null:
		status_label.text = t


func set_stats(hp: float, hp_max: float, fuel: float, fuel_max: float, charge: float, charge_max: float, cargo: int, cargo_max: int, spd: int, veh: String, in_power: bool) -> void:
	# Safe-guard: this build may run without the new nodes.
	if stats_panel == null:
		return
	if veh_label != null:
		veh_label.text = "VEH: %s" % veh.to_upper()
	_set_reticle_for_vehicle(veh)
	if power_label != null:
		power_label.text = "POWER" if in_power else ""
	var hp_frac: float = 0.0
	if hp_max > 0.0:
		hp_frac = clamp(hp / hp_max, 0.0, 1.0)
	if hp_bar != null:
		if hp_bar.has_method("set_fraction"):
			hp_bar.call("set_fraction", hp_frac)
		elif hp_bar is ProgressBar:
			var pb: ProgressBar = hp_bar as ProgressBar
			pb.max_value = max(1.0, hp_max)
			pb.value = clamp(hp, 0.0, pb.max_value)
	if hp_val != null:
		hp_val.text = "%d/%d" % [int(round(hp)), int(round(hp_max))]
	var fuel_frac: float = 0.0
	if fuel_max > 0.0:
		fuel_frac = clamp(fuel / fuel_max, 0.0, 1.0)
	if fuel_bar != null:
		if fuel_bar.has_method("set_fraction"):
			fuel_bar.call("set_fraction", fuel_frac)
		elif fuel_bar is ProgressBar:
			var pb2: ProgressBar = fuel_bar as ProgressBar
			pb2.max_value = max(1.0, fuel_max)
			pb2.value = clamp(fuel, 0.0, pb2.max_value)
	if fuel_val != null:
		fuel_val.text = "%d/%d" % [int(round(fuel)), int(round(fuel_max))]

	var is_scout: bool = (veh == "scout")
	if charge_row != null:
		charge_row.visible = is_scout
	if is_scout:
		var ch_frac: float = 0.0
		if charge_max > 0.0:
			ch_frac = clamp(charge / charge_max, 0.0, 1.0)
		if charge_bar != null:
			if charge_bar.has_method("set_fraction"):
				charge_bar.call("set_fraction", ch_frac)
			elif charge_bar is ProgressBar:
				var pb3: ProgressBar = charge_bar as ProgressBar
				pb3.max_value = max(1.0, charge_max)
				pb3.value = clamp(charge, 0.0, pb3.max_value)
		if charge_val != null:
			charge_val.text = "%d/%d" % [int(round(charge)), int(round(charge_max))]

	if cargo_val != null:
		cargo_val.text = "%d/%d" % [cargo, cargo_max]
	if speed_val != null:
		speed_val.text = str(spd)


func set_net(peer_id: int, fps: int, snap_age_ms: int, connected: bool) -> void:
	if net_label == null:
		return
	var ctag: String = "OK" if connected else "..."
	net_label.text = "Peer %d  %s  FPS %d  Snap %dms" % [peer_id, ctag, fps, snap_age_ms]


func set_compact(enabled: bool) -> void:
	_hud_compact = enabled
	# Compact hides the large debug panel (Wulfram-style).
	var p: Control = get_node_or_null("Panel")
	if p != null:
		p.visible = not _hud_compact


func flash_message(t: String, duration: float = 1.0) -> void:
	if toast_label == null:
		return
	_toast_seq += 1
	var my_seq: int = _toast_seq
	toast_label.text = t
	toast_label.visible = true
	var timer: SceneTreeTimer = get_tree().create_timer(duration)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(toast_label):
			return
		if my_seq != _toast_seq:
			return
		toast_label.visible = false
	)

func set_minimap(me_pos: Vector3, me_yaw: float, me_team: int, players: Array, crates: Array, buildings: Array, target_id: int) -> void:
	if minimap == null:
		return
	if minimap.has_method("set_data"):
		minimap.call("set_data", me_pos, me_yaw, me_team, players, crates, buildings, target_id)


func set_target(
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
	if target_panel == null:
		return
	if target_panel.has_method("set_target_data"):
		target_panel.call(
			"set_target_data",
			enabled,
			on_screen,
			screen_pos,
			dir_screen,
			dist_m,
			hp,
			hpmax,
			team,
			veh,
			id,
			is_enemy,
			lock_level,
			lock_ready
		)


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
	if weapon_panel == null:
		return
	if weapon_panel.has_method("set_weapons"):
		weapon_panel.call(
			"set_weapons",
			veh,
			team,
			fuel,
			fuel_max,
			charge,
			charge_max,
			cd_fire,
			cd_pulse,
			cd_hunter,
			cd_flare,
			cd_mine,
			auto_rate_hz,
			pulse_cd,
			hunter_cd,
			flare_cd,
			mine_cd,
			cost_auto,
			cost_pulse,
			cost_hunter,
			cost_flare,
			cost_mine,
			beam_cost_per_s,
			has_valid_target,
			firing_primary,
			firing_secondary
		)


func _set_reticle_for_vehicle(veh: String) -> void:
	if reticle == null:
		return
	var t: Texture2D = null
	if veh == "scout":
		t = HudStyle.tex("reticle_scout2")
	else:
		t = HudStyle.tex("reticle_tank")
	reticle.texture = t
	reticle.visible = (t != null)
	# Hide legacy text crosshair when we have a bitmap reticle.
	if crosshair != null:
		crosshair.visible = (t == null)



func _ensure_build_panel() -> void:
	# If a BuildPanel widget exists in the scene, do not create the legacy panel.
	if build_widget != null and is_instance_valid(build_widget):
		return
	# Also guard against a node named "BuildPanel" already existing (older scenes may add it).
	var existing := get_node_or_null("BuildPanel")
	if existing != null and is_instance_valid(existing) and existing != build_panel:
		build_widget = existing
		return
	if build_panel != null and is_instance_valid(build_panel):
		return
	# Create a Wulfram-inspired build panel to the left of the weapon panel.
	build_panel = Panel.new()
	build_panel.name = "BuildPanel"
	add_child(build_panel)
	build_panel.anchor_left = 0.5
	build_panel.anchor_right = 0.5
	build_panel.anchor_top = 1.0
	build_panel.anchor_bottom = 1.0
	build_panel.offset_left = -560.0
	build_panel.offset_right = -200.0
	build_panel.offset_top = -170.0
	build_panel.offset_bottom = -8.0
	build_panel.custom_minimum_size = Vector2(360, 120)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.anchor_left = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_top = 0.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 8.0
	vbox.offset_top = 8.0
	vbox.offset_right = -8.0
	vbox.offset_bottom = -8.0
	vbox.add_theme_constant_override("separation", 4)
	build_panel.add_child(vbox)

	_bp_rows.clear()
	_bp_rows["powercell"] = _bp_make_row(vbox, "powercell", "B", "POWERCELL")
	_bp_rows["turret"] = _bp_make_row(vbox, "turret", "T", "TURRET")
	_bp_rows["repair"] = _bp_make_row(vbox, "repair", "R", "REPAIR")

	_bp_hint = Label.new()
	_bp_hint.name = "Hint"
	_bp_hint.text = ""
	_bp_hint.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_bp_hint)


func _bp_make_row(parent: VBoxContainer, kind: String, key: String, name: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = kind
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(14, 14)
	# simple color coding; keeps the look readable without requiring textures.
	if kind == "powercell":
		icon.color = Color(0.20, 0.90, 0.40, 0.95)
	elif kind == "turret":
		icon.color = Color(0.95, 0.75, 0.20, 0.95)
	else:
		icon.color = Color(0.65, 0.65, 0.75, 0.95)
	row.add_child(icon)

	var k := Label.new()
	k.name = "Key"
	k.custom_minimum_size = Vector2(26, 0)
	k.text = key
	k.add_theme_font_size_override("font_size", 14)
	row.add_child(k)

	var nm := Label.new()
	nm.name = "Name"
	nm.custom_minimum_size = Vector2(120, 0)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text = name
	nm.add_theme_font_size_override("font_size", 14)
	row.add_child(nm)

	var cost := Label.new()
	cost.name = "Cost"
	cost.custom_minimum_size = Vector2(34, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.text = "x1"
	cost.add_theme_font_size_override("font_size", 14)
	row.add_child(cost)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(90, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	row.add_child(bar)

	var st := Label.new()
	st.name = "State"
	st.custom_minimum_size = Vector2(70, 0)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	st.text = "READY"
	st.add_theme_font_size_override("font_size", 14)
	row.add_child(st)

	return {"row": row, "icon": icon, "key": k, "name": nm, "cost": cost, "bar": bar, "state": st}


func _bp_update_row(kind: String, cargo: int, cost_val: int, enabled: bool, state_text: String) -> void:
	if not _bp_rows.has(kind):
		return
	var r: Dictionary = _bp_rows[kind]
	var cost_lbl: Label = r["cost"]
	var bar: ProgressBar = r["bar"]
	var st: Label = r["state"]
	cost_lbl.text = "x%d" % cost_val
	bar.max_value = max(1.0, float(cost_val))
	bar.value = clamp(float(cargo), 0.0, bar.max_value)
	st.text = state_text
	# dim when unavailable
	var a: float = 1.0 if enabled else 0.45
	(r["row"] as Control).modulate = Color(1.0, 1.0, 1.0, a)



func set_build(
		cargo: int,
		cargo_max: int,
		powercell_cost: int,
		turret_cost: int,
		preview_kind: String,
		preview_ok: bool,
		preview_reason: String,
		reject_kind: String,
		reject_reason: String,
		reject_slope_deg: float,
		reject_age: float,
		can_repair: bool,
		repair_cost: int
	) -> void:
	# Prefer the procedural widget if present.
	if build_widget != null and is_instance_valid(build_widget) and build_widget.has_method("set_build_state"):
		var ak: String = preview_kind
		var aok: bool = preview_ok
		var areason: String = preview_reason
		# Briefly show server rejection in the slot highlight text.
		if reject_age >= 0.0 and reject_age < 1.25 and not reject_kind.is_empty():
			ak = reject_kind
			aok = false
			areason = reject_reason
			if reject_reason == "SLOPE":
				areason = "%s (%.1f°)" % [reject_reason, reject_slope_deg]
		build_widget.call("set_build_state", cargo, cargo_max, powercell_cost, turret_cost, ak, aok, areason)
		return

	# Fallback legacy panel.
	_ensure_build_panel()
	if build_panel == null:
		return

	# helper to update a single row (implemented as a class method; local named funcs cause parse errors)
	var have_pc: bool = cargo >= powercell_cost
	var have_tu: bool = cargo >= turret_cost
	_bp_update_row("powercell", cargo, powercell_cost, have_pc, "READY" if have_pc else "NO CARGO")
	_bp_update_row("turret", cargo, turret_cost, have_tu, "READY" if have_tu else "NO CARGO")
	_bp_update_row("repair", cargo, repair_cost, can_repair, "READY" if can_repair else "")

	# Preview highlight
	var hint: String = ""
	if not preview_kind.is_empty():
		hint = "%s: %s" % [preview_kind.to_upper(), ("OK" if preview_ok else preview_reason)]
		if _bp_rows.has(preview_kind):
			var rr: Control = _bp_rows[preview_kind]["row"]
			rr.modulate = Color(1, 1, 1, 1)
			# subtle cue: slightly brighter while previewing
			rr.modulate = Color(1.08, 1.08, 1.08, 1.0)
			# subtle visual cue: brighten when actively previewing

	# Server rejection flash in the hint line (graphical focus, minimal text)
	if reject_age >= 0.0 and reject_age < 1.25 and not reject_kind.is_empty():
		hint = "%s BLOCKED: %s" % [reject_kind.to_upper(), reject_reason]
		if reject_reason == "SLOPE":
			hint = "%s BLOCKED: %s (%.1f°)" % [reject_kind.to_upper(), reject_reason, reject_slope_deg]

	if _bp_hint != null:
		_bp_hint.text = hint

# -------------------------------
# Wulfram HUD skin helpers (v0.12.6)

func _ensure_bottom_bar() -> void:
	# Create a cosmetic bar behind the bottom HUD widgets (weapon/build/minimap), matching Wulfram's chunky look.
	var existing: Node = get_node_or_null("BottomBar")
	if existing != null and existing is Control:
		_bottom_bar = existing as Control
		return
	_bottom_bar = Control.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.set_script(BottomBarScript)
	add_child(_bottom_bar)
	# Make sure it's behind everything.
	move_child(_bottom_bar, 0)

func _apply_wulfram_skin() -> void:
	# Panels
	var p_debug: Control = get_node_or_null("Panel")
	if p_debug != null:
		HudStyle.apply_panel(p_debug)
	var p_stats: Control = stats_panel
	if p_stats != null:
		HudStyle.apply_panel(p_stats)
	var p_net: Control = net_panel
	if p_net != null:
		HudStyle.apply_panel(p_net)
	var p_mm: Control = get_node_or_null("MiniMapPanel")
	if p_mm != null:
		HudStyle.apply_panel(p_mm)
	# Weapon panel root is a Panel instance.
	if weapon_panel != null and weapon_panel is Control:
		HudStyle.apply_panel(weapon_panel as Control)

	# Labels
	HudStyle.apply_label(label, true)
	HudStyle.apply_label(status_label, true)
	HudStyle.apply_label(toast_label, false)
	HudStyle.apply_label(crosshair, false)
	HudStyle.apply_label(hit_label, false)
	crosshair.add_theme_color_override("font_color", HudStyle.ACCENT)
	hit_label.add_theme_color_override("font_color", HudStyle.ACCENT)

	HudStyle.apply_label(veh_label, false)
	HudStyle.apply_label(power_label, false)
	HudStyle.apply_label(hp_val, false)
	HudStyle.apply_label(fuel_val, false)
	HudStyle.apply_label(charge_val, false)
	HudStyle.apply_label(cargo_val, false)
	HudStyle.apply_label(speed_val, false)
	HudStyle.apply_label(net_label, true)

	# Progress bars
	if hp_bar is ProgressBar:
		HudStyle.apply_progressbar(hp_bar as ProgressBar)
	if fuel_bar is ProgressBar:
		HudStyle.apply_progressbar(fuel_bar as ProgressBar)
	if charge_bar is ProgressBar:
		HudStyle.apply_progressbar(charge_bar as ProgressBar)