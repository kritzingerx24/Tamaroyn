extends CanvasLayer

const BottomBarScript := preload("res://game/ui/widgets/BottomBar.gd")
const PlayerListOverlay := preload("res://game/ui/widgets/PlayerListOverlay.gd")
const MapOverlay := preload("res://game/ui/widgets/MapOverlay.gd")

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

@onready var chat_panel: Node = get_node_or_null("ChatLogPanel")

@onready var weapon_panel: Node = get_node_or_null("WeaponPanel")

@onready var top_hp_bar: Node = get_node_or_null("TopHPBar")
@onready var top_energy_bar: Node = get_node_or_null("TopEnergyBar")
@onready var team_counts: Node = get_node_or_null("TeamCountsPanel")

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

var _last_chat_status: String = ""

# Match/meta for Wulfram-like bottom tab row.
var _match_start_msec: int = 0
var _world_w: float = 0.0
var _world_d: float = 0.0
var _tab_sector: String = "--"
var _tab_ping_ms: int = 0
var _tab_kills: int = 0

# Cached minimap data for map/player-list overlays.
var _mm_me_pos: Vector3 = Vector3.ZERO
var _mm_me_team: int = 0
var _mm_players: Array = []
var _mm_crates: Array = []
var _mm_buildings: Array = []
var _mm_ships: Array = []
var _mm_target_id: int = -1

# CPU-generated strategic map textures (Visual/Altitude/Slope). Built on client at map load.
var _strat_tex_visual: Texture2D = null
var _strat_tex_alt: Texture2D = null
var _strat_tex_slope: Texture2D = null

var _player_list_overlay: Control = null
var _map_overlay: Control = null

func _ready() -> void:
	_match_start_msec = Time.get_ticks_msec()
	_ensure_bottom_bar()
	_setup_top_bars()
	# The addition of the bottom chat strip pushes the whole HUD cluster upward,
	# so make the cosmetic BottomBar taller to keep everything visually unified.
	if _bottom_bar != null and _bottom_bar.has_method("set_height"):
		_bottom_bar.call("set_height", 260.0)
	# Prefer a dedicated toast label (so we can hide the big debug panel by default).
	var t: Label = get_node_or_null("ToastOverlay")
	if t != null:
		toast_label = t
	_apply_wulfram_skin()
	# Default to a compact HUD (Wulfram has no giant debug panel). Toggle with F1.
	set_compact(true)
	# Hide debug-style panels by default; Wulfram HUD uses the top bars + weapon strip.
	if stats_panel != null:
		stats_panel.visible = false
	if net_panel != null:
		net_panel.visible = false
	# Only create the legacy build panel when the widget isn't present.
	if build_widget == null:
		_ensure_build_panel()

	_ensure_overlays()
	# Bottom chat strip "tabs" act like buttons in Wulfram (Kills, Glimpse).
	if chat_panel != null:
		if chat_panel.has_signal("kills_pressed") and not chat_panel.is_connected("kills_pressed", Callable(self, "_on_kills_pressed")):
			chat_panel.connect("kills_pressed", Callable(self, "_on_kills_pressed"))
		if chat_panel.has_signal("glimpse_pressed") and not chat_panel.is_connected("glimpse_pressed", Callable(self, "_on_glimpse_pressed")):
			chat_panel.connect("glimpse_pressed", Callable(self, "_on_glimpse_pressed"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Overlays (Map/Player List) match original keys.
		if event.keycode == KEY_ESCAPE:
			if _map_overlay != null and _map_overlay.visible:
				_map_overlay.visible = false
				get_viewport().set_input_as_handled()
				return
			if _player_list_overlay != null and _player_list_overlay.visible:
				_player_list_overlay.visible = false
				get_viewport().set_input_as_handled()
				return
		if event.keycode == KEY_N:
			if _map_overlay != null and _map_overlay.visible and _map_overlay.has_method("cycle_mode"):
				_map_overlay.call("cycle_mode")
				get_viewport().set_input_as_handled()
				return
		# While on the strategic map, 'U' toggles the Map/Uplink tab (matches SFHELP strategic display).
		if event.keycode == KEY_U:
			if _map_overlay != null and _map_overlay.visible and _map_overlay.has_method("toggle_tab"):
				_map_overlay.call("toggle_tab")
				get_viewport().set_input_as_handled()
				return
		if event.keycode == KEY_P:
			_toggle_player_list()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_M:
			_toggle_map_overlay()
			get_viewport().set_input_as_handled()
			return
		# PageUp/PageDown scroll the comms/status text (matches original Wulfram behavior).
		if chat_panel != null and chat_panel.has_method("scroll_lines"):
			if event.keycode == KEY_PAGEUP:
				chat_panel.call("scroll_lines", 3 if event.shift_pressed else 1)
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_PAGEDOWN:
				chat_panel.call("scroll_lines", -(3 if event.shift_pressed else 1))
				get_viewport().set_input_as_handled()
				return
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
	# Mirror short single-line status messages into the bottom chat strip.
	if chat_panel != null and chat_panel.has_method("add_line"):
		var s := t.strip_edges()
		if not s.is_empty() and s.find("\n") == -1 and s.length() <= 90 and s != _last_chat_status:
			chat_panel.call("add_line", s)
			_last_chat_status = s


func set_stats(hp: float, hp_max: float, fuel: float, fuel_max: float, charge: float, charge_max: float, cargo: int, cargo_max: int, spd: int, veh: String, in_power: bool) -> void:
	# Top-edge bars should update even if the optional StatsPanel is absent/hidden.
	var hp_frac: float = 0.0
	if hp_max > 0.0:
		hp_frac = clamp(hp / hp_max, 0.0, 1.0)
	var fuel_frac: float = 0.0
	if fuel_max > 0.0:
		fuel_frac = clamp(fuel / fuel_max, 0.0, 1.0)
	if top_hp_bar != null and top_hp_bar.has_method("set_fraction"):
		top_hp_bar.call("set_fraction", hp_frac)
	if top_energy_bar != null and top_energy_bar.has_method("set_fraction"):
		top_energy_bar.call("set_fraction", fuel_frac)

	# Safe-guard: StatsPanel is optional in the Wulfram HUD.
	if stats_panel == null:
		_set_reticle_for_vehicle(veh)
		return
	if veh_label != null:
		veh_label.text = "VEH: %s" % veh.to_upper()
	_set_reticle_for_vehicle(veh)
	if power_label != null:
		power_label.text = "POWER" if in_power else ""
	if hp_bar != null:
		if hp_bar.has_method("set_fraction"):
			hp_bar.call("set_fraction", hp_frac)
		elif hp_bar is ProgressBar:
			var pb: ProgressBar = hp_bar as ProgressBar
			pb.max_value = max(1.0, hp_max)
			pb.value = clamp(hp, 0.0, pb.max_value)
	if hp_val != null:
		hp_val.text = "%d/%d" % [int(round(hp)), int(round(hp_max))]
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
	_tab_ping_ms = max(0, snap_age_ms)
	_push_bottom_tabs()


func set_world_meta(world_w: float, world_d: float) -> void:
	_world_w = max(0.0, world_w)
	_world_d = max(0.0, world_d)
	# Sector will update on the next set_minimap.


func _push_bottom_tabs() -> void:
	if chat_panel == null or not chat_panel.has_method("set_tabs"):
		return
	var elapsed: int = 0
	if _match_start_msec > 0:
		elapsed = max(0, Time.get_ticks_msec() - _match_start_msec)
	chat_panel.call("set_tabs", _tab_kills, elapsed, _tab_ping_ms, _tab_sector)


func set_compact(enabled: bool) -> void:
	_hud_compact = enabled
	# Compact hides the large debug panel (Wulfram-style).
	var p: Control = get_node_or_null("Panel")
	if p != null:
		p.visible = not _hud_compact


func flash_message(t: String, duration: float = 1.0) -> void:
	if toast_label == null:
		return
	if chat_panel != null and chat_panel.has_method("add_line"):
		chat_panel.call("add_line", t)

	# Reflect ship command results into the strategic map order queue.
	if _map_overlay != null and _map_overlay.has_method("resolve_last_pending"):
		if t.begins_with("Ship moved") or t.begins_with("Ship warped"):
			_map_overlay.call("resolve_last_pending", "done")
		elif t.begins_with("Ship command blocked"):
			_map_overlay.call("resolve_last_pending", "rejected")

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

func set_minimap(me_pos: Vector3, me_yaw: float, me_team: int, players: Array, crates: Array, buildings: Array, target_id: int, ships: Array = []) -> void:
	if minimap == null:
		return
	# Cache for overlays (Map/Player list).
	_mm_me_pos = me_pos
	_mm_me_team = me_team
	_mm_players = players
	_mm_crates = crates
	_mm_buildings = buildings
	_mm_ships = ships
	_mm_target_id = target_id
	if chat_panel != null and chat_panel.has_method("set_team"):
		chat_panel.call("set_team", me_team)
	if minimap.has_method("set_data"):
		minimap.call("set_data", me_pos, me_yaw, me_team, players, crates, buildings, target_id)
	# Update top-center team counts (blue left, red right).
	if team_counts != null and team_counts.has_method("set_counts"):
		var blue: int = 0
		var red: int = 0
		for pp in players:
			var t: int = int(pp.get("team", 0))
			if t == 1:
				blue += 1
			else:
				red += 1
		team_counts.call("set_counts", blue, red)

	# Update sector label for the bottom tab row.
	_tab_sector = _compute_sector(me_pos)
	_push_bottom_tabs()
	_refresh_overlay_data()


func _compute_sector(pos: Vector3) -> String:
	# Wulfram shows a grid sector like "E5".
	# Wulfram docs reference a 6x6 sector grid.
	if _world_w > 0.0 and _world_d > 0.0:
		var x0: float = -_world_w * 0.5
		var z0: float = -_world_d * 0.5
		var u: float = clamp((pos.x - x0) / _world_w, 0.0, 0.9999)
		var v: float = clamp((pos.z - z0) / _world_d, 0.0, 0.9999)
		var col: int = int(floor(u * 6.0))
		var row: int = int(floor(v * 6.0)) + 1
		var letter: String = String.chr(65 + clamp(col, 0, 5))
		return "%s%d" % [letter, clamp(row, 1, 6)]

	# Fallback: coarse world-space bins.
	var col2: int = int(floor((pos.x + 512.0) / 128.0))
	var row2: int = int(floor((pos.z + 512.0) / 128.0))
	var letter2: String = String.chr(65 + clamp(col2, 0, 5))
	return "%s%d" % [letter2, clamp(row2 + 1, 1, 6)]



func set_camera_zoom(zoom_x: float) -> void:
	if minimap != null and minimap.has_method("set_cam_zoom_x"):
		minimap.call("set_cam_zoom_x", zoom_x)

func set_radar_range_m(range_m: float) -> void:
	if minimap != null and minimap.has_method("set_radar_range_m"):
		minimap.call("set_radar_range_m", range_m)

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


func _bp_make_row(parent: VBoxContainer, kind: String, key: String, label_text: String) -> Dictionary:
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
	nm.text = label_text
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
		# If repair is not available in the current context, hide that slot and suppress repair highlights.
		if not can_repair and ak == "repair":
			ak = ""
			aok = false
			areason = ""
		build_widget.call("set_build_state", cargo, cargo_max, powercell_cost, turret_cost, repair_cost, can_repair, ak, aok, areason)
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
# -------------------------------
# Top-edge Wulfram bars (v0.13.6)

func _setup_top_bars() -> void:
	# Allow absolute pixel layout regardless of anchors set in the scene.
	if top_hp_bar != null and top_hp_bar is Control:
		var c := top_hp_bar as Control
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.offset_left = 0
		c.offset_top = 0
		c.offset_right = 0
		c.offset_bottom = 0
	if top_energy_bar != null and top_energy_bar is Control:
		var c2 := top_energy_bar as Control
		c2.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c2.offset_left = 0
		c2.offset_top = 0
		c2.offset_right = 0
		c2.offset_bottom = 0
	_layout_top_bars()
	# Re-layout when window size changes.
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_layout_top_bars):
		get_viewport().size_changed.connect(_layout_top_bars)

func _layout_top_bars() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vw: float = float(vp.get_visible_rect().size.x)
	# Baseline Wulfram is 640x480; clamp widths so widescreen doesn't look absurd.
	var hp_w: float = clamp(vw * 0.48, 280.0, 520.0)
	var en_w: float = clamp(vw * 0.40, 240.0, 480.0)
	var bar_h: float = 20.0
	var top_y: float = 4.0
	var left_x: float = 6.0
	if top_hp_bar != null and top_hp_bar is Control:
		var hp := top_hp_bar as Control
		hp.position = Vector2(left_x, top_y)
		hp.size = Vector2(hp_w, bar_h)

	# Energy bar spans to the right edge (weapon strip is below it in the reference).
	var right_edge: float = vw - 6.0
	if top_energy_bar != null and top_energy_bar is Control:
		var en := top_energy_bar as Control
		var x0: float = max(8.0, right_edge - en_w)
		en.position = Vector2(x0, top_y)
		en.size = Vector2(max(0.0, right_edge - x0), bar_h)


# --- Wulfram-style overlays (Map / Player List) ---

func _ensure_overlays() -> void:
	if _player_list_overlay == null:
		_player_list_overlay = PlayerListOverlay.new()
		add_child(_player_list_overlay)
	if _map_overlay == null:
		_map_overlay = MapOverlay.new()
		add_child(_map_overlay)

func _match_elapsed_ms() -> int:
	if _match_start_msec <= 0:
		return 0
	return max(0, Time.get_ticks_msec() - _match_start_msec)

func _refresh_overlay_data() -> void:
	# Keep overlay contents in sync with the latest snapshot.
	if _player_list_overlay != null and _player_list_overlay.visible and _player_list_overlay.has_method("set_data"):
		_player_list_overlay.call("set_data", multiplayer.get_unique_id(), _mm_me_team, _mm_players)
	if _map_overlay != null and _map_overlay.visible and _map_overlay.has_method("set_data"):
		_map_overlay.call("set_data", _mm_me_pos, _mm_me_team, _mm_players, _mm_crates, _mm_buildings, _mm_ships, _mm_target_id, _world_w, _world_d, _tab_sector, _match_elapsed_ms(), _strat_tex_visual, _strat_tex_alt, _strat_tex_slope)

func set_stratmap_textures(visual_tex: Texture2D, altitude_tex: Texture2D, slope_tex: Texture2D) -> void:
	_strat_tex_visual = visual_tex
	_strat_tex_alt = altitude_tex
	_strat_tex_slope = slope_tex
	# If the overlay is already open, update immediately.
	if _map_overlay != null and _map_overlay.visible:
		_refresh_overlay_data()

func _toggle_player_list() -> void:
	_ensure_overlays()
	if _map_overlay != null:
		_map_overlay.visible = false
	if _player_list_overlay != null:
		_player_list_overlay.visible = not _player_list_overlay.visible
		if _player_list_overlay.visible:
			_refresh_overlay_data()

func _toggle_map_overlay() -> void:
	_ensure_overlays()
	if _player_list_overlay != null:
		_player_list_overlay.visible = false
	if _map_overlay != null:
		_map_overlay.visible = not _map_overlay.visible
		if _map_overlay.visible:
			_refresh_overlay_data()

func _on_kills_pressed() -> void:
	_toggle_player_list()

func _on_glimpse_pressed() -> void:
	_toggle_map_overlay()
