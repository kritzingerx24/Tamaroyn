extends Node3D

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 2456
const DEFAULT_MAP_SCENE := "res://imported_maps/aberdour.tscn"

@export var host: String = DEFAULT_HOST
@export var port: int = DEFAULT_PORT
@export var map_scene_path: String = DEFAULT_MAP_SCENE

@export var input_send_rate_hz: float = 30.0
@export var mouse_sensitivity: float = 0.004  # radians per pixel
@export var pitch_limit: float = 1.15         # ~66 degrees

# Terrain tuning (client visuals only)
@export var terrain_uv_scale_micro: float = 0.035
@export var terrain_uv_scale_macro: float = 0.010
@export var terrain_macro_strength: float = 0.40
@export var terrain_macro_distance_start: float = 250.0
@export var terrain_macro_distance_end: float = 900.0
@export var terrain_contours_enabled: bool = true
@export var terrain_contour_period: float = 25.0
@export var terrain_contour_strength: float = 0.10
@export var terrain_slope_ao_strength: float = 0.18


# Weapon feel (client-side only; server is authoritative)
@export var show_tracers: bool = true

var _cached_metal_tex: Texture2D
var _cached_sky_tex: Texture2D
var _map_root: Node = null
var _terrain_debug_enabled: bool = false
var _skybox_sphere: MeshInstance3D

var _tex_terrain_tag: String = "Placeholder"
var _tex_vehicle_tag: String = "Placeholder"
var _tex_sky_tag: String = "Placeholder"

var _send_accum: float = 0.0
var _send_dt: float = 1.0 / input_send_rate_hz

var _avatars: Dictionary = {}
var _projectiles: Dictionary = {}  # pulse projectiles: proj_id -> Node
var _missiles: Dictionary = {}     # hunter missiles: missile_id -> Node
var _mines: Dictionary = {}        # mines: mine_id -> Node
var _crates: Dictionary = {}       # cargo crates: crate_id -> Node
var _buildings: Dictionary = {}    # buildings: building_id -> Node

@onready var world_root: Node3D = $World
@onready var hud: Node = $DebugHud
@onready var camera: Camera3D = $Camera3D

var _connected: bool = false
var _target_peer_id: int = -1

# Target lock (client-side HUD only; server is authoritative for shots).
var _lock_target_id: int = -1
var _lock_level: float = 0.0
var _lock_ready: bool = false
var _last_snapshot: Dictionary = {}
var _last_snapshot_msec: int = 0
var _base_hud_text: String = ""

var _show_shape_debug: bool = false

var _cfg_cargo_max: int = 5
var _cfg_cargo_pickup_radius: float = 4.0
var _cfg_fuel_max: float = 100.0
var _cfg_charge_max: float = 100.0

# Weapon config (sent from server via _cfg)
var _cfg_auto_rate_hz: float = 10.0
var _cfg_pulse_cooldown: float = 1.25
var _cfg_hunter_cooldown: float = 3.5
var _cfg_flare_cooldown: float = 4.5
var _cfg_mine_cooldown: float = 2.0
var _cfg_fuel_cost_autocannon: float = 0.8
var _cfg_fuel_cost_pulse: float = 6.0
var _cfg_fuel_cost_hunter: float = 10.0
var _cfg_fuel_cost_flare: float = 8.0
var _cfg_fuel_cost_mine: float = 6.0
var _cfg_beam_fuel_cost_per_s: float = 8.0

# Build preview (client-side UX; server remains authoritative)
var _cfg_build_distance: float = 12.0
var _cfg_build_max_slope_deg: float = 24.0
var _cfg_build_min_spacing: float = 6.0
var _cfg_powercell_radius: float = 35.0
var _cfg_turret_range: float = 55.0
var _cfg_turret_build_cost: int = 1
var _cfg_powercell_build_cost: int = 1

var _build_preview: Node3D = null
var _build_preview_kind: String = ""
var _build_preview_reason: String = ""

# For HUD: last server build rejection (briefly displayed).
var _hud_build_reject_kind: String = ""
var _hud_build_reject_reason: String = ""
var _hud_build_reject_slope: float = 0.0
var _hud_build_reject_msec: int = -1

# Mouse -> network input
var _mouse_yaw_accum: float = 0.0
var _aim_pitch: float = 0.0

# Latched one-s
var _speed_setting: int = 7
var _queued_vehicle_toggle: bool = false

# Latched one-shot inputs so they aren't missed between network sends.
var _queued_hunter: bool = false
var _queued_flare: bool = false
var _queued_mine: bool = false
var _queued_spawn_crate: bool = false
var _queued_build_pc: bool = false
var _queued_build_turret: bool = false
var _queued_repair: bool = false

# Aimed building for interactions (repair)
var _aim_building_id: int = -1
var _aim_building_type: String = ""
var _aim_building_team: int = -1
var _aim_building_hp: float = 0.0
var _aim_building_hpmax: float = 0.0

# For smoother first-person camera feel between snapshots.
var _pred_yaw: float = 0.0

enum CameraMode { COCKPIT, CHASE }
var _camera_mode: int = CameraMode.COCKPIT

const TRACER_SCENE: PackedScene = preload("res://game/fx/Tracer3D.tscn")
const MISSILE_SCENE: PackedScene = preload("res://game/actors/MissileProjectile.tscn")
const MINE_SCENE: PackedScene = preload("res://game/actors/MineActor.tscn")
const ShapeLib: Script = preload("res://game/wulfram/WulframShapeLibrary.gd")
const PointCloudScript: Script = preload("res://game/wulfram/WulframPointCloud.gd")
const TERRAIN_SHADER: Shader = preload("res://game/shaders/terrain_wulfram.gdshader")
const TERRAIN_DEBUG_SHADER: Shader = preload("res://game/shaders/terrain_debug.gdshader")
const TEX_GRASS_FALLBACK: Texture2D = preload("res://game/textures/placeholders/grass.png")
const TEX_DIRT_FALLBACK: Texture2D = preload("res://game/textures/placeholders/dirt.png")
const TEX_ROCK_FALLBACK: Texture2D = preload("res://game/textures/placeholders/rock.png")
const TEX_METAL_FALLBACK: Texture2D = preload("res://game/textures/placeholders/metal.png")
const WULFRAM_METAL_EXTRACTED := "res://assets/wulfram_textures/extracted/dark-grey_44.png"
const SKY_AURORA_EXTRACTED := "res://assets/wulfram_textures/extracted/aurora001.png"
const SKY_AURORA_FALLBACK: Texture2D = preload("res://game/textures/placeholders/aurora001.png")

# Preferred extracted Wulfram textures (created by tools/extract_wulfram_bitmaps.py)
const WULFRAM_TERRAIN_GRASS := "res://assets/wulfram_textures/extracted/greenmartian001.png"
const WULFRAM_TERRAIN_DIRT := "res://assets/wulfram_textures/extracted/2marsdirt001.png"
const WULFRAM_TERRAIN_ROCK := "res://assets/wulfram_textures/extracted/marsrock001.png"

const WULFRAM_CRATE_TOP := "res://assets/wulfram_textures/extracted/cargotops.png"
const WULFRAM_CRATE_SIDE := "res://assets/wulfram_textures/extracted/cargosd.png"

const WULFRAM_COMM_RED_CANDIDATES := [
	"res://assets/wulfram_textures/extracted/commred4.png",
	"res://assets/wulfram_textures/extracted/commred3.png",
	"res://assets/wulfram_textures/extracted/commred2.png",
	"res://assets/wulfram_textures/extracted/commred1.png",
]
const WULFRAM_COMM_BLUE_CANDIDATES := [
	"res://assets/wulfram_textures/extracted/commblue3.png",
	"res://assets/wulfram_textures/extracted/commblue2.png",
	"res://assets/wulfram_textures/extracted/commblue1.png",
]




func _ready() -> void:
	_ensure_input_actions()
	_ensure_skybox_locked()

	# Avoid far-clip artifacts on large maps.
	camera.near = 0.1
	camera.far = 20000.0

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_load_map()
	_setup_lighting()
	_connect_signals()
	_parse_cmdline_overrides()
	_connect_to_server()

func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Speed setting (0-9). Wulfram-style: 7 is neutral.
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			_speed_setting = int(event.keycode - KEY_0)
			return
		if event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			_speed_setting = int(event.keycode - KEY_KP_0)
			return
		# Toggle vehicle (Tank <-> Scout)
		if event.keycode == KEY_C:
			_queued_vehicle_toggle = true
			return

		# Terrain debug / tuning keys (client visuals only)
		if event.keycode == KEY_F4:
			_terrain_debug_enabled = not _terrain_debug_enabled
			if _map_root != null:
				_apply_terrain_visuals(_map_root)
			if is_instance_valid(hud):
				hud.call("flash_message", "Terrain shader: %s" % ("DEBUG" if _terrain_debug_enabled else "WULFRAM"), 1.2)
			return
		if event.keycode == KEY_F6:
			terrain_uv_scale_micro = clamp(terrain_uv_scale_micro * 0.90, 0.005, 0.25)
			if _map_root != null and not _terrain_debug_enabled:
				_apply_terrain_visuals(_map_root)
			if is_instance_valid(hud):
				hud.call("flash_message", "Terrain micro tiling: %.3f" % terrain_uv_scale_micro, 1.0)
			return
		if event.keycode == KEY_F7:
			terrain_uv_scale_micro = clamp(terrain_uv_scale_micro * 1.10, 0.005, 0.25)
			if _map_root != null and not _terrain_debug_enabled:
				_apply_terrain_visuals(_map_root)
			if is_instance_valid(hud):
				hud.call("flash_message", "Terrain micro tiling: %.3f" % terrain_uv_scale_micro, 1.0)
			return
		if event.keycode == KEY_F8:
			terrain_contours_enabled = not terrain_contours_enabled
			if _map_root != null and not _terrain_debug_enabled:
				_apply_terrain_visuals(_map_root)
			if is_instance_valid(hud):
				hud.call("flash_message", "Terrain contours: %s" % ("ON" if terrain_contours_enabled else "OFF"), 1.0)
			return


		if InputMap.event_is_action(event, "cycle_target"):
			_cycle_target()
			return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Accumulate yaw delta since the last network send.
		var dyaw: float = -event.relative.x * mouse_sensitivity
		_mouse_yaw_accum += dyaw
		_pred_yaw += dyaw

		# Pitch for aiming (client sends absolute pitch).
		_aim_pitch = clamp(_aim_pitch + (-event.relative.y * mouse_sensitivity), -pitch_limit, pitch_limit)

func _connect_signals() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Snapshots/events are delivered via RPC.

func _parse_cmdline_overrides() -> void:
	# Example: -- --connect 192.168.1.10 --port 2456 --map aberdour
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--connect" and i + 1 < args.size():
			host = args[i + 1]
		elif args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif args[i] == "--map" and i + 1 < args.size():
			var m := args[i + 1]
			if not m.ends_with(".tscn"):
				m += ".tscn"
			map_scene_path = "res://imported_maps/%s" % m

func _connect_to_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		hud.set_text("Failed to create client peer. err=%s" % str(err))
		return
	multiplayer.multiplayer_peer = peer
	hud.set_text("Connecting to %s:%d ..." % [host, port])

func _on_connected() -> void:
	_connected = true
	var msg := "Connected. Your peer_id=%d
Controls: WASD move, Mouse aim+turn, LMB autocannon, RMB pulse (tank) / beam (scout)
TAB target, E hunter missile, F flare, G drop mine
	B build powercell (uses cargo), T build turret (uses cargo) (hold B/T to preview), R repair aimed friendly building (uses 1 cargo), K spawn cargo crate (test)
L reload Wulfram shapes (after extraction)
F3 toggle shape debug
Q/Z hover height, C toggle scout/tank, V toggles camera, Esc releases mouse
Fuel drains when overdriving (spd 8-9) and when firing; powercells regen fuel/HP (and scout charge)" % multiplayer.get_unique_id()
	msg += "\nTexture source: %s  Meshes: %s  (Sky: aurora001)" % _get_texture_source_tag()
	_base_hud_text = msg
	hud.set_text(_base_hud_text)
	hud.set_status("")

func _on_connect_failed() -> void:
	_connected = false
	hud.set_text("Connection failed. Is the server running?\nRun the server scene: res://server/ServerMain.tscn")

func _on_server_disconnected() -> void:
	_connected = false
	hud.set_text("Disconnected from server.")

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if Input.is_action_just_pressed("toggle_camera"):
		_camera_mode = CameraMode.CHASE if _camera_mode == CameraMode.COCKPIT else CameraMode.COCKPIT
		hud.set_reticle_visible(_camera_mode == CameraMode.COCKPIT)

	if Input.is_action_just_pressed("reload_shapes"):
		_reload_wulfram_shapes()

	if Input.is_action_just_pressed("toggle_shape_debug"):
		_show_shape_debug = not _show_shape_debug
		if is_instance_valid(hud):
			hud.flash_message("Shape debug: %s" % ("ON" if _show_shape_debug else "OFF"), 1.0)

	if not _connected:
		return

	# Latch one-shot actions between network sends.
	if Input.is_action_just_pressed("fire_hunter"):
		_queued_hunter = true
	if Input.is_action_just_pressed("flare"):
		_queued_flare = true
	if Input.is_action_just_pressed("drop_mine"):
		_queued_mine = true
	if Input.is_action_just_pressed("spawn_crate"):
		_queued_spawn_crate = true
	if Input.is_action_just_pressed("build_powercell"):
		_queued_build_pc = true
	if Input.is_action_just_pressed("build_turret"):
		_queued_build_turret = true
	if Input.is_action_just_pressed("repair_building"):
		_queued_repair = true

	_send_accum += delta
	while _send_accum >= _send_dt:
		_send_accum -= _send_dt
		_send_input()

	_update_camera(delta)
	_update_build_preview(delta)
	_update_skybox()
	_update_target_hud(delta)


func _update_target_hud(delta: float) -> void:
	# Client-side only: Wulfram-style target box + lock indicator.
	if not is_instance_valid(hud):
		return
	if not hud.has_method("set_target"):
		return
	if _last_snapshot.is_empty():
		hud.call("set_target", false, false, Vector2.ZERO, Vector2(0, -1), 0.0, 0.0, 1.0, 0, "", -1, true, 0.0, false)
		return
	var me_id: int = multiplayer.get_unique_id()
	var me_key: String = str(me_id)
	if not _last_snapshot.has(me_key):
		return
	var me: Dictionary = _last_snapshot[me_key]
	var my_team: int = int(me.get("team", 0))

	var has_tgt: bool = (_target_peer_id >= 0 and _last_snapshot.has(str(_target_peer_id)))
	if not has_tgt:
		_lock_target_id = -1
		_lock_level = 0.0
		_lock_ready = false
		hud.call("set_target", false, false, Vector2.ZERO, Vector2(0, -1), 0.0, 0.0, 1.0, 0, "", -1, true, 0.0, false)
		return

	var tp: Dictionary = _last_snapshot[str(_target_peer_id)]
	var tpos: Vector3 = Vector3(tp.get("pos", Vector3.ZERO))
	var thp: float = float(tp.get("hp", 0.0))
	var thpmax: float = float(tp.get("hpmax", 100.0))
	var tteam: int = int(tp.get("team", 0))
	var tveh: String = str(tp.get("veh", ""))
	var is_enemy: bool = (tteam != my_team)

	# Reset lock when switching target.
	if _lock_target_id != _target_peer_id:
		_lock_target_id = _target_peer_id
		_lock_level = 0.0
		_lock_ready = false

	# Screen projection + direction for off-screen indicator.
	var cam_xf: Transform3D = camera.global_transform
	var rel: Vector3 = tpos - cam_xf.origin
	var dist: float = rel.length()
	# Godot 4.x: Basis has no xform_inv(); use inverse-basis multiplication.
	# We want the target position in camera-local space.
	var local: Vector3 = cam_xf.basis.inverse() * rel
	var behind: bool = (local.z > 0.0)
	var screen_pos: Vector2 = camera.unproject_position(tpos)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var on_screen: bool = (not behind and screen_pos.x >= 0.0 and screen_pos.y >= 0.0 and screen_pos.x <= vp_size.x and screen_pos.y <= vp_size.y)
	var dir_screen: Vector2 = Vector2(local.x, -local.y)
	if dir_screen.length() < 0.001:
		dir_screen = Vector2(0, -1)
	else:
		dir_screen = dir_screen.normalized()
	if behind:
		dir_screen = -dir_screen

	# Lock buildup: only for enemy targets and when near the reticle.
	var lock_build_time: float = 0.65
	var lock_decay_time: float = 0.35
	var lock_fov_deg: float = 7.5
	var ok: bool = false
	if is_enemy and dist > 0.1 and not behind:
		var aim: Vector3 = _aim_dir(_pred_yaw, _aim_pitch)
		var to_t: Vector3 = rel / dist
		var dot: float = aim.dot(to_t)
		var need: float = cos(deg_to_rad(lock_fov_deg))
		ok = (dot >= need and dist <= 450.0)

	if ok:
		_lock_level = clamp(_lock_level + (delta / lock_build_time), 0.0, 1.0)
	else:
		_lock_level = clamp(_lock_level - (delta / lock_decay_time), 0.0, 1.0)
	_lock_ready = (_lock_level >= 0.999)
	if not is_enemy:
		_lock_level = 0.0
		_lock_ready = false

	hud.call(
		"set_target",
		true,
		on_screen,
		screen_pos,
		dir_screen,
		dist,
		thp,
		thpmax,
		tteam,
		tveh,
		_target_peer_id,
		is_enemy,
		_lock_level,
		_lock_ready
	)

func _send_input() -> void:
	var mx := 0.0
	var mz := 0.0
	var my := 0.0

	if Input.is_action_pressed("move_left"):
		mx -= 1.0
	if Input.is_action_pressed("move_right"):
		mx += 1.0
	if Input.is_action_pressed("move_forward"):
		mz += 1.0
	if Input.is_action_pressed("move_back"):
		mz -= 1.0
	if Input.is_action_pressed("altitude_up"):
		my += 1.0
	if Input.is_action_pressed("altitude_down"):
		my -= 1.0

	# Mouse turning: server expects a yaw *rate* (rad/s).
	var turn_rate: float = _mouse_yaw_accum / _send_dt
	_mouse_yaw_accum = 0.0

	var firing: bool = Input.is_action_pressed("fire_primary")

	var cmd := {
		"mx": mx,
		"mz": mz,
		"turn": turn_rate,
		"alt": my,
		"pitch": _aim_pitch,
		"fire": firing,
		"fire2": Input.is_action_pressed("fire_secondary"),
		"hunter": _queued_hunter,
		"flare": _queued_flare,
		"mine": _queued_mine,
		"spawn_crate": _queued_spawn_crate,
		"build_pc": _queued_build_pc,
		"build_turret": _queued_build_turret,
		"repair": _queued_repair,
		"repair_bid": _aim_building_id,
		"tgt": _target_peer_id,
		"spd": _speed_setting,
		"veh_toggle": _queued_vehicle_toggle,
	}
	_queued_hunter = false
	_queued_flare = false
	_queued_mine = false
	_queued_spawn_crate = false
	_queued_build_pc = false
	_queued_build_turret = false
	_queued_repair = false
	_queued_vehicle_toggle = false
	# Send to authoritative server (peer_id 1) via RPC.
	c_input.rpc_id(1, cmd)


# --- RPC bridge ---
# NOTE: In Godot's high-level multiplayer, RPC calls are routed by NodePath.
# To avoid "Requested node was not found" errors, the client and server must both
# have a node at the same path with the same RPC methods.
# We solve this by making the client root node also named "ServerMain" (see GameClient.tscn).

# We never expect the server to call this on clients, but we define it so the
# client has RPC configuration for calling it remotely.
@rpc("any_peer", "call_remote", "unreliable")
func c_input(_cmd: Dictionary) -> void:
	pass

# Server -> client snapshots.
@rpc("authority", "call_remote", "unreliable")
func s_snapshot(snap: Dictionary) -> void:
	_on_snapshot(snap)

# Server -> client FX/events (shots, kills, etc.)
@rpc("authority", "call_remote", "unreliable")
func s_events(events: Array) -> void:
	_on_events(events)

func _on_snapshot(snap: Dictionary) -> void:
	_last_snapshot = snap
	_last_snapshot_msec = Time.get_ticks_msec()
	# Server-provided config (optional).
	if snap.has("_cfg") and typeof(snap["_cfg"]) == TYPE_DICTIONARY:
		var cfg: Dictionary = snap["_cfg"]
		_cfg_cargo_max = int(cfg.get("cargo_max", _cfg_cargo_max))
		_cfg_cargo_pickup_radius = float(cfg.get("cargo_pickup_radius", _cfg_cargo_pickup_radius))
		_cfg_fuel_max = float(cfg.get("fuel_max", _cfg_fuel_max))
		_cfg_charge_max = float(cfg.get("charge_max", _cfg_charge_max))
		# Weapon HUD config
		_cfg_auto_rate_hz = float(cfg.get("auto_rate_hz", _cfg_auto_rate_hz))
		_cfg_pulse_cooldown = float(cfg.get("pulse_cooldown", _cfg_pulse_cooldown))
		_cfg_hunter_cooldown = float(cfg.get("hunter_cooldown", _cfg_hunter_cooldown))
		_cfg_flare_cooldown = float(cfg.get("flare_cooldown", _cfg_flare_cooldown))
		_cfg_mine_cooldown = float(cfg.get("mine_cooldown", _cfg_mine_cooldown))
		_cfg_fuel_cost_autocannon = float(cfg.get("fuel_cost_autocannon_shot", _cfg_fuel_cost_autocannon))
		_cfg_fuel_cost_pulse = float(cfg.get("fuel_cost_pulse", _cfg_fuel_cost_pulse))
		_cfg_fuel_cost_hunter = float(cfg.get("fuel_cost_hunter", _cfg_fuel_cost_hunter))
		_cfg_fuel_cost_flare = float(cfg.get("fuel_cost_flare", _cfg_fuel_cost_flare))
		_cfg_fuel_cost_mine = float(cfg.get("fuel_cost_mine", _cfg_fuel_cost_mine))
		_cfg_beam_fuel_cost_per_s = float(cfg.get("beam_fuel_cost_per_s", _cfg_beam_fuel_cost_per_s))
		_cfg_build_distance = float(cfg.get("build_distance", _cfg_build_distance))
		_cfg_build_max_slope_deg = float(cfg.get("build_max_slope_deg", _cfg_build_max_slope_deg))
		_cfg_build_min_spacing = float(cfg.get("build_min_spacing", _cfg_build_min_spacing))
		_cfg_powercell_radius = float(cfg.get("powercell_radius", _cfg_powercell_radius))
		_cfg_turret_range = float(cfg.get("turret_range", _cfg_turret_range))
		_cfg_turret_build_cost = int(cfg.get("turret_build_cost", _cfg_turret_build_cost))
		_cfg_powercell_build_cost = int(cfg.get("powercell_build_cost", _cfg_powercell_build_cost))
	# snap keys are strings of peer_id
	# Create/update avatars
	var seen: Dictionary = {}
	var my_id: int = multiplayer.get_unique_id()

	for k in snap.keys():
		if str(k).begins_with("_"):
			continue
		var id := int(k)
		seen[id] = true
		var entry: Dictionary = snap[k]
		var pos: Vector3 = entry.get("pos", Vector3.ZERO)
		var yaw: float = float(entry.get("yaw", 0.0))
		var team: int = int(entry.get("team", 0))
		var veh: String = str(entry.get("veh", "tank"))

		var av = _avatars.get(id)
		if av != null and av.has_method("vehicle_kind"):
			var cur_kind: String = str(av.call("vehicle_kind"))
			if cur_kind != veh:
				(av as Node).queue_free()
				av = null
		if av == null:
			av = _spawn_avatar(id, team, veh)
		_avatars[id] = av
		av.set_target(pos, yaw)

		# Snap our camera yaw to the authoritative yaw so drift doesn't accumulate.
		if id == my_id:
			_pred_yaw = yaw

	# Remove avatars not in snapshot
	for id in _avatars.keys():
		if not seen.has(id):
			(_avatars[id] as Node).queue_free()
			_avatars.erase(id)

	# Keep target markers in sync (new avatars may have appeared).
	_update_target_markers()

	# --- Projectiles ---
	_process_projectiles_from_snapshot(snap)
	_process_missiles_from_snapshot(snap)
	_process_mines_from_snapshot(snap)
	_process_crates_from_snapshot(snap)
	_process_buildings_from_snapshot(snap)

	# Update HUD status for local player.
	_update_status_from_snapshot(snap)


func _on_events(events: Array) -> void:
	if events.is_empty():
		return
	var my_id: int = multiplayer.get_unique_id()
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var t: String = str(d.get("t", ""))
		if t == "shot":
			var from_v: Vector3 = Vector3(d.get("from", Vector3.ZERO))
			var to_v: Vector3 = Vector3(d.get("to", Vector3.ZERO))
			if show_tracers:
				_spawn_tracer(from_v, to_v)


			# Turret shots: small muzzle flash + small impact ping (less noisy than full explosions)
			var src: String = str(d.get("src", ""))
			if src == "turret":
				var tm: int = int(d.get("team", 0))
				_spawn_muzzle_fx(from_v, tm)
				_spawn_impact_fx(to_v, tm)

			var shooter: int = int(d.get("sh", -1))
			var hit_id: int = int(d.get("hit", -1))
			var credited: bool = (shooter == my_id)

			# Turret shots use negative shooter ids (-building_id). Attribute hit marker to the turret owner when known.
			if not credited and shooter < 0:
				var bid: int = -shooter
				if _buildings.has(bid):
					var bn: Node = _buildings[bid]
					if bn != null and bn.has_meta("owner"):
						credited = (int(bn.get_meta("owner")) == my_id)

			if credited and hit_id != -1:
				hud.show_hit()
		elif t == "pulse_fire":
			if show_tracers:
				var f: Vector3 = Vector3(d.get("from", Vector3.ZERO))
				var dir: Vector3 = Vector3(d.get("dir", Vector3.FORWARD))
				_spawn_tracer(f, f + dir.normalized() * 24.0)
		elif t == "explosion":
			var pos: Vector3 = Vector3(d.get("pos", Vector3.ZERO))
			var r: float = float(d.get("r", 8.0))
			_spawn_explosion_fx(pos, r)
			var shooter2: int = int(d.get("sh", -1))
			var hits: Array = d.get("hits", [])
			if shooter2 == my_id and hits.size() > 0:
				hud.show_hit(0.24)
		elif t == "flare":
			var pid: int = int(d.get("id", -1))
			var av = _avatars.get(pid)
			if av:
				_spawn_explosion_fx((av as Node3D).global_position, 6.0)
		elif t == "hunter_fire":
			if show_tracers:
				var f2: Vector3 = Vector3(d.get("from", Vector3.ZERO))
				var dir2: Vector3 = Vector3(d.get("dir", Vector3.FORWARD))
				_spawn_tracer(f2, f2 + dir2.normalized() * 30.0)
		elif t == "beam":
			if show_tracers:
				var f3: Vector3 = Vector3(d.get("from", Vector3.ZERO))
				var p3: Vector3 = Vector3(d.get("pos", Vector3.ZERO))
				_spawn_tracer(f3, p3)
		elif t == "mine_place":
			pass
		elif t == "lock_break":
			pass
		elif t == "cargo_pick":
			var pid2: int = int(d.get("id", -1))
			if pid2 == my_id and is_instance_valid(hud) and hud.has_method("flash_message"):
				var c: int = int(d.get("cargo", 0))
				hud.call("flash_message", "+1 Cargo (now %d/%d)" % [c, _cfg_cargo_max], 0.9)
		elif t == "cargo_spend":
			var pid3: int = int(d.get("id", -1))
			if pid3 == my_id and is_instance_valid(hud) and hud.has_method("flash_message"):
				var c2: int = int(d.get("cargo", 0))
				var kind: String = str(d.get("kind", ""))
				hud.call("flash_message", "-1 Cargo (%s) (now %d/%d)" % [kind, c2, _cfg_cargo_max], 1.1)

		elif t == "b_repair":
			var who: int = int(d.get("id", -1))
			if who == my_id and is_instance_valid(hud) and hud.has_method("flash_message"):
				var bt2: String = str(d.get("type", "building"))
				var bid2: int = int(d.get("bid", -1))
				var hp2: int = int(round(float(d.get("hp", 0.0))))
				var hm2: int = int(round(float(d.get("hpmax", 0.0))))
				hud.call("flash_message", "Repaired %s#%d (%d/%d)" % [bt2, bid2, hp2, hm2], 1.1)
		elif t == "repair_reject":
			var who2: int = int(d.get("id", -1))
			if who2 == my_id and is_instance_valid(hud) and hud.has_method("flash_message"):
				var reason2: String = str(d.get("reason", "BLOCKED"))
				hud.call("flash_message", "Repair blocked: %s" % reason2, 1.1)

		elif t == "build_reject":
			var pidr: int = int(d.get("id", -1))
			if pidr == my_id and is_instance_valid(hud) and hud.has_method("flash_message"):
				var kind: String = str(d.get("kind", "build"))
				var reason: String = str(d.get("reason", "BLOCKED"))
				var slope: float = float(d.get("slope", 0.0))
				_hud_build_reject_kind = kind
				_hud_build_reject_reason = reason
				_hud_build_reject_slope = slope
				_hud_build_reject_msec = Time.get_ticks_msec()
				var msg: String = "Build %s blocked: %s" % [kind, reason]
				if reason == "SLOPE":
					msg = "Build %s blocked: %s (%.1f°)" % [kind, reason, slope]
				hud.call("flash_message", msg, 1.3)
		elif t == "b_destroy":
			var bid: int = int(d.get("id", -1))
			var pos2: Vector3 = Vector3(d.get("pos", Vector3.ZERO))
			_spawn_explosion_fx(pos2, 10.0)
			if _buildings.has(bid):
				var bn: Node = _buildings[bid]
				if bn:
					bn.queue_free()
				_buildings.erase(bid)
			var killer: int = int(d.get("sh", -1))
			if killer == my_id and is_instance_valid(hud) and hud.has_method("flash_message"):
				var bt: String = str(d.get("type", "building"))
				hud.call("flash_message", "Destroyed %s" % bt, 1.2)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var n: Node = TRACER_SCENE.instantiate()
	world_root.add_child(n)
	if n.has_method("setup"):
		n.call("setup", from, to)

func _spawn_avatar(id: int, team: int, veh: String) -> Node:
	var ps_path := "res://game/actors/TankAvatar.tscn"
	if veh == "scout":
		ps_path = "res://game/actors/ScoutAvatar.tscn"
	var ps: PackedScene = load(ps_path)
	var av = ps.instantiate()
	world_root.add_child(av)
	av.configure(id, team)
	av.global_position = Vector3(0, 20, 0)
	return av

func _load_map() -> void:
	if map_scene_path == "" or not ResourceLoader.exists(map_scene_path):
		push_warning("Map scene not found: %s" % map_scene_path)
		return
	var ps: PackedScene = load(map_scene_path)
	var map_instance: Node = ps.instantiate()
	world_root.add_child(map_instance)
	_map_root = map_instance
	_fix_terrain_collision(map_instance)
	_rebuild_terrain_mesh(map_instance)
	_apply_terrain_visuals(map_instance)


func _fix_terrain_collision(map_root: Node) -> void:
	# Fix mismatch between visual mesh spacing and HeightMapShape3D collision spacing.
	#
	# HeightMapShape3D samples are 1 unit apart in local space. Our terrain is authored in
	# world units (world_width/world_depth). GodotPhysics requires UNIFORM scaling for
	# HeightMapShape3D, so we scale the body by the sample spacing and compensate by
	# scaling the height samples inversely.
	var meta: WulframMapMeta = map_root.get_node_or_null("TerrainRoot/MapMeta") as WulframMapMeta
	if meta == null:
		return
	var body: Node3D = map_root.get_node_or_null("TerrainRoot/TerrainBody") as Node3D
	var col: CollisionShape3D = map_root.get_node_or_null("TerrainRoot/TerrainBody/TerrainCollision") as CollisionShape3D
	if body == null or col == null:
		return
	var hm: HeightMapShape3D = col.shape as HeightMapShape3D
	if hm == null:
		return
	var grid_w: int = meta.grid_width
	var grid_d: int = meta.grid_depth
	var world_w: float = meta.world_width
	var world_d: float = meta.world_depth
	if grid_w <= 1 or grid_d <= 1 or world_w <= 0.0 or world_d <= 0.0:
		return
	var dx: float = world_w / float(grid_w - 1)
	var dz: float = world_d / float(grid_d - 1)
	var target_spacing: float = meta.collision_spacing
	if target_spacing <= 0.0:
		target_spacing = (dx + dz) * 0.5
	# Ensure HeightMap dimensions match metadata.
	hm.map_width = grid_w
	hm.map_depth = grid_d
	var current_scale: float = body.scale.x
	if current_scale <= 0.0001:
		current_scale = 1.0
	var data: PackedFloat32Array = hm.map_data
	# Sanity: if the body is already scaled but the height samples look un-normalized, normalize.
	var max_abs: float = 0.0
	for v in data:
		max_abs = maxf(max_abs, absf(v))
	if absf(current_scale - target_spacing) <= 0.001 and max_abs > 50.0 and target_spacing > 5.0:
		# Likely: heights are still in world units on a scaled body. Normalize them.
		for i in range(data.size()):
			data[i] = data[i] / maxf(target_spacing, 0.0001)
		hm.map_data = data
		col.shape = hm
	elif absf(current_scale - target_spacing) > 0.001:
		# Rescale heights to preserve world-space collision when we change the body scale.
		var factor: float = current_scale / maxf(target_spacing, 0.0001)
		for i in range(data.size()):
			data[i] = data[i] * factor
		hm.map_data = data
		col.shape = hm
	body.scale = Vector3(target_spacing, target_spacing, target_spacing)
	meta.collision_spacing = target_spacing # runtime only
func _rebuild_terrain_mesh(map_root: Node) -> void:
	# Some older imported map scenes contain baked meshes with occasional gaps/artifacts.
	# Rebuilding the mesh from the (now-correct) heightfield makes the terrain reliable and
	# keeps visuals and collision in sync.
	var meta: WulframMapMeta = map_root.get_node_or_null("TerrainRoot/MapMeta") as WulframMapMeta
	if meta == null:
		return
	var terrain: MeshInstance3D = map_root.get_node_or_null("TerrainRoot/Terrain") as MeshInstance3D
	if terrain == null:
		terrain = _find_first_mesh_instance(map_root, "Terrain")
	if terrain == null:
		return
	var body: Node3D = map_root.get_node_or_null("TerrainRoot/TerrainBody") as Node3D
	var col: CollisionShape3D = map_root.get_node_or_null("TerrainRoot/TerrainBody/TerrainCollision") as CollisionShape3D
	if body == null or col == null:
		return
	var hm: HeightMapShape3D = col.shape as HeightMapShape3D
	if hm == null:
		return
	var grid_w: int = meta.grid_width
	var grid_d: int = meta.grid_depth
	var world_w: float = meta.world_width
	var world_d: float = meta.world_depth
	if grid_w <= 1 or grid_d <= 1 or world_w <= 0.0 or world_d <= 0.0:
		return
	var dx: float = world_w / float(grid_w - 1)
	var dz: float = world_d / float(grid_d - 1)
	var x0: float = -world_w * 0.5
	var z0: float = -world_d * 0.5
	var data: PackedFloat32Array = hm.map_data
	if data.size() != grid_w * grid_d:
		return
	# Convert to world heights (collision data is in local space, scaled by body.scale).
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(data.size())
	var sy: float = body.scale.y
	for i in range(data.size()):
		heights[i] = data[i] * sy
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	verts.resize(grid_w * grid_d)
	norms.resize(grid_w * grid_d)
	uvs.resize(grid_w * grid_d)
	for z in range(grid_d):
		for x in range(grid_w):
			var idx: int = z * grid_w + x
			var h: float = heights[idx]
			verts[idx] = Vector3(x0 + float(x) * dx, h, z0 + float(z) * dz)
			uvs[idx] = Vector2(float(x) / float(grid_w - 1), float(z) / float(grid_d - 1))
	# Normals (heightfield gradient approximation)
	for z in range(grid_d):
		for x in range(grid_w):
			var idx: int = z * grid_w + x
			var xl: int = max(x - 1, 0)
			var xr: int = min(x + 1, grid_w - 1)
			var zd: int = max(z - 1, 0)
			var zu: int = min(z + 1, grid_d - 1)
			var hl: float = heights[z * grid_w + xl]
			var hr: float = heights[z * grid_w + xr]
			var hd: float = heights[zd * grid_w + x]
			var hu: float = heights[zu * grid_w + x]
			var denom_x: float = maxf(2.0 * dx, 0.0001)
			var denom_z: float = maxf(2.0 * dz, 0.0001)
			var sx: float = (hr - hl) / denom_x
			var sz: float = (hu - hd) / denom_z
			var n: Vector3 = Vector3(-sx, 1.0, -sz).normalized()
			norms[idx] = n
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((grid_w - 1) * (grid_d - 1) * 6)
	var ii: int = 0
	for z in range(grid_d - 1):
		for x in range(grid_w - 1):
			var i0: int = z * grid_w + x
			var i1: int = i0 + 1
			var i2: int = (z + 1) * grid_w + x
			var i3: int = i2 + 1
			# CCW winding for an upward-facing surface
			indices[ii + 0] = i0
			indices[ii + 1] = i1
			indices[ii + 2] = i2
			indices[ii + 3] = i1
			indices[ii + 4] = i3
			indices[ii + 5] = i2
			ii += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain.mesh = mesh
func _apply_terrain_visuals(map_root: Node) -> void:
	# Apply a simple terrain material.
	# If you run tools/extract_wulfram_bitmaps.py, this will automatically start using Wulfram 2 textures.
	var terrain: MeshInstance3D = map_root.get_node_or_null("TerrainRoot/Terrain")
	if terrain == null:
		terrain = _find_first_mesh_instance(map_root, "Terrain")
	if terrain == null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = (TERRAIN_DEBUG_SHADER if _terrain_debug_enabled else TERRAIN_SHADER)

	# Advanced terrain parameters (only used by terrain_wulfram.gdshader)
	if not _terrain_debug_enabled:
		mat.set_shader_parameter("uv_scale_micro", terrain_uv_scale_micro)
		mat.set_shader_parameter("uv_scale_macro", terrain_uv_scale_macro)
		mat.set_shader_parameter("macro_strength", terrain_macro_strength)
		mat.set_shader_parameter("macro_distance_start", terrain_macro_distance_start)
		mat.set_shader_parameter("macro_distance_end", terrain_macro_distance_end)
		mat.set_shader_parameter("contours_enabled", terrain_contours_enabled)
		mat.set_shader_parameter("contour_period", terrain_contour_period)
		mat.set_shader_parameter("contour_strength", terrain_contour_strength)
		mat.set_shader_parameter("slope_ao_strength", terrain_slope_ao_strength)

	# Prefer extracted Wulfram textures if present.
	var grass_path := WULFRAM_TERRAIN_GRASS
	var dirt_path := WULFRAM_TERRAIN_DIRT
	var rock_path := WULFRAM_TERRAIN_ROCK

	var grass_tex: Texture2D = TEX_GRASS_FALLBACK
	var dirt_tex: Texture2D = TEX_DIRT_FALLBACK
	var rock_tex: Texture2D = TEX_ROCK_FALLBACK

	if ResourceLoader.exists(grass_path):
		grass_tex = load(grass_path)
	if ResourceLoader.exists(dirt_path):
		dirt_tex = load(dirt_path)
	if ResourceLoader.exists(rock_path):
		rock_tex = load(rock_path)

	_tex_terrain_tag = "Wulfram" if (ResourceLoader.exists(grass_path) or ResourceLoader.exists(dirt_path) or ResourceLoader.exists(rock_path)) else "Placeholder"

	mat.set_shader_parameter("tex_grass", grass_tex)
	mat.set_shader_parameter("tex_dirt", dirt_tex)
	mat.set_shader_parameter("tex_rock", rock_tex)

	terrain.material_override = mat

func _find_first_mesh_instance(n: Node, name_hint: String = "") -> MeshInstance3D:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if name_hint == "" or mi.name == name_hint:
			return mi
	for c in n.get_children():
		var r := _find_first_mesh_instance(c, name_hint)
		if r != null:
			return r
	return null

func _setup_lighting() -> void:
	# Basic sun light + environment so gray-screen issues are easier to diagnose.
	if get_node_or_null("DirectionalLight3D") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		add_child(sun)
		sun.rotation_degrees = Vector3(-55, 45, 0)

	if get_node_or_null("WorldEnvironment") == null:
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.04, 0.05, 0.07)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		we.environment = env
		add_child(we)

func _update_camera(_delta: float) -> void:
	# Follow the local player's avatar (our own peer_id)
	var my_id := multiplayer.get_unique_id()
	var av = _avatars.get(my_id)
	if av == null:
		return

	var av_node := av as Node3D
	var pos: Vector3 = av_node.global_position

	if _camera_mode == CameraMode.COCKPIT:
		# First-person-ish camera, looking where you aim.
		var cam_pos: Vector3 = pos + Vector3(0, 8, 0)
		camera.global_position = cam_pos
		var dir: Vector3 = _aim_dir(_pred_yaw, _aim_pitch)
		camera.look_at(cam_pos + dir * 60.0, Vector3.UP)
	else:
		# Chase cam for debugging / wide view.
		var desired := pos + Vector3(0, 60, -95)
		camera.global_position = desired
		camera.look_at(pos, Vector3.UP)

func _aim_dir(yaw: float, pitch: float) -> Vector3:
	# Yaw matches server: forward is +Z when yaw=0.
	var cp: float = cos(pitch)
	var sp: float = sin(pitch)
	var dir := Vector3(sin(yaw) * cp, sp, cos(yaw) * cp)
	return dir.normalized()


func _get_metal_texture() -> Texture2D:
	if _cached_metal_tex != null:
		return _cached_metal_tex
	if ResourceLoader.exists(WULFRAM_METAL_EXTRACTED):
		_cached_metal_tex = load(WULFRAM_METAL_EXTRACTED)
		_tex_vehicle_tag = "Wulfram"
	else:
		_cached_metal_tex = TEX_METAL_FALLBACK
		_tex_vehicle_tag = "Placeholder"
	return _cached_metal_tex

func _get_sky_texture_locked() -> Texture2D:
	if _cached_sky_tex != null:
		return _cached_sky_tex
	if ResourceLoader.exists(SKY_AURORA_EXTRACTED):
		_cached_sky_tex = load(SKY_AURORA_EXTRACTED)
		_tex_sky_tag = "Wulfram"
	else:
		_cached_sky_tex = SKY_AURORA_FALLBACK
		_tex_sky_tag = "Placeholder"
	return _cached_sky_tex


func _get_texture_source_tag() -> String:
	# We consider textures "Wulfram" if the extracted texture pack is present.
	# (You create it by running tools/extract_wulfram_bitmaps.py)
	if ResourceLoader.exists(WULFRAM_TERRAIN_GRASS) or ResourceLoader.exists(SKY_AURORA_EXTRACTED) or ResourceLoader.exists(WULFRAM_METAL_EXTRACTED):
		return "Wulfram"
	return "Placeholder"


func _wulfram_shapes_ok() -> bool:
	if not ShapeLib.shapes_ready():
		return false
	# Core silhouettes we expect for the point-cloud pass.
	return ShapeLib.has_shape("tank_1") and ShapeLib.has_shape("tank_2") and ShapeLib.has_shape("scout_1") and ShapeLib.has_shape("scout_2") and ShapeLib.has_shape("cargo") and ShapeLib.has_shape("energy_1") and ShapeLib.has_shape("energy_2")


func _get_mesh_source_tag() -> String:
	if not ShapeLib.shapes_ready():
		return "Primitive"
	return "Wulfram shapes (OK)" if _wulfram_shapes_ok() else "Wulfram shapes (Missing)"

func _get_crate_texture() -> Texture2D:
	# Cargo crate textures (if extracted); falls back to generic metal.
	if ResourceLoader.exists(WULFRAM_CRATE_TOP):
		return load(WULFRAM_CRATE_TOP)
	if ResourceLoader.exists(WULFRAM_CRATE_SIDE):
		return load(WULFRAM_CRATE_SIDE)
	return _get_metal_texture()

func _get_comm_texture(team_id: int) -> Texture2D:
	# Building/uplink textures (if extracted).
	var candidates: Array = WULFRAM_COMM_RED_CANDIDATES if team_id == 0 else WULFRAM_COMM_BLUE_CANDIDATES
	for p in candidates:
		if ResourceLoader.exists(str(p)):
			return load(str(p))
	return _get_metal_texture()

func _ensure_skybox_locked() -> void:
	# We use a large inside-visible sphere instead of Godot's PanoramaSkyMaterial,
	# because the original Wulfram skies are not equirectangular panoramas.
	var world_root := get_node_or_null("World") as Node3D
	if world_root == null:
		world_root = self
	var sky_root: Node3D = world_root.get_node_or_null("Skybox") as Node3D
	if sky_root == null:
		sky_root = Node3D.new()
		sky_root.name = "Skybox"
		world_root.add_child(sky_root)

	var mi: MeshInstance3D = sky_root.get_node_or_null("SkySphere") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "SkySphere"
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky_root.add_child(mi)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _get_sky_texture_locked()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	mi.material_override = mat
	mi.scale = Vector3.ONE * 2500.0
	_skybox_sphere = mi

func _update_skybox() -> void:
	if _skybox_sphere == null:
		return
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	_skybox_sphere.global_position = cam.global_position

func _ensure_input_actions() -> void:
	# Safety net so the project still works even if Input Map didn't import.
	if not InputMap.has_action("fire_primary"):
		InputMap.add_action("fire_primary")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire_primary", mb)

	if not InputMap.has_action("fire_secondary"):
		InputMap.add_action("fire_secondary")
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("fire_secondary", mb2)

	if not InputMap.has_action("fire_hunter"):
		InputMap.add_action("fire_hunter")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("fire_hunter", e)

	if not InputMap.has_action("flare"):
		InputMap.add_action("flare")
		var f := InputEventKey.new()
		f.physical_keycode = KEY_F
		InputMap.action_add_event("flare", f)

	if not InputMap.has_action("drop_mine"):
		InputMap.add_action("drop_mine")
		var g := InputEventKey.new()
		g.physical_keycode = KEY_G
		InputMap.action_add_event("drop_mine", g)

	if not InputMap.has_action("spawn_crate"):
		InputMap.add_action("spawn_crate")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_K
		InputMap.action_add_event("spawn_crate", k)

	if not InputMap.has_action("build_powercell"):
		InputMap.add_action("build_powercell")
		var b := InputEventKey.new()
		b.physical_keycode = KEY_B
		InputMap.action_add_event("build_powercell", b)

	if not InputMap.has_action("build_turret"):
		InputMap.add_action("build_turret")
		var t := InputEventKey.new()
		t.physical_keycode = KEY_T
		InputMap.action_add_event("build_turret", t)

	if not InputMap.has_action("repair_building"):
		InputMap.add_action("repair_building")
		var r := InputEventKey.new()
		r.physical_keycode = KEY_R
		InputMap.action_add_event("repair_building", r)

	if not InputMap.has_action("cycle_target"):
		InputMap.add_action("cycle_target")
		var tab := InputEventKey.new()
		tab.physical_keycode = KEY_TAB
		InputMap.action_add_event("cycle_target", tab)

	if not InputMap.has_action("toggle_camera"):
		InputMap.add_action("toggle_camera")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_V
		InputMap.action_add_event("toggle_camera", ev)

	if not InputMap.has_action("reload_shapes"):
		InputMap.add_action("reload_shapes")
		var l := InputEventKey.new()
		l.physical_keycode = KEY_L
		InputMap.action_add_event("reload_shapes", l)

	if not InputMap.has_action("toggle_shape_debug"):
		InputMap.add_action("toggle_shape_debug")
		var f3 := InputEventKey.new()
		f3.physical_keycode = KEY_F3
		InputMap.action_add_event("toggle_shape_debug", f3)

	# Default to cockpit reticle visible.
	hud.set_reticle_visible(_camera_mode == CameraMode.COCKPIT)


func _process_projectiles_from_snapshot(snap: Dictionary) -> void:
	var arr: Array = []
	if snap.has("_proj"):
		arr = snap["_proj"]
	# Mark seen
	var seen: Dictionary = {}
	for p in arr:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pid: int = int(p.get("id", -1))
		if pid < 0:
			continue
		seen[pid] = true
		var pos: Vector3 = Vector3(p.get("pos", Vector3.ZERO))
		if not _projectiles.has(pid):
			var ps: PackedScene = load("res://game/actors/PulseProjectile.tscn")
			var node = ps.instantiate()
			world_root.add_child(node)
			node.configure(pid)
			node.global_position = pos
			_projectiles[pid] = node
		var n = _projectiles[pid]
		if n and n.has_method("set_target"):
			n.set_target(pos)
		elif n:
			n.global_position = pos

	# Remove missing
	for pid in _projectiles.keys():
		if not seen.has(pid):
			var n = _projectiles[pid]
			if n:
				n.queue_free()
			_projectiles.erase(pid)

func _process_missiles_from_snapshot(snap: Dictionary) -> void:
	var arr: Array = []
	if snap.has("_mis"):
		arr = snap["_mis"]
	var seen: Dictionary = {}
	for m in arr:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid: int = int(m.get("id", -1))
		if mid < 0:
			continue
		seen[mid] = true
		var pos: Vector3 = Vector3(m.get("pos", Vector3.ZERO))
		if not _missiles.has(mid):
			var node: Node = MISSILE_SCENE.instantiate()
			world_root.add_child(node)
			if node.has_method("configure"):
				node.call("configure", mid)
			node.global_position = pos
			_missiles[mid] = node
		var n = _missiles[mid]
		if n and n.has_method("set_target"):
			n.set_target(pos)
		elif n:
			n.global_position = pos
	for mid2 in _missiles.keys():
		if not seen.has(mid2):
			var n2 = _missiles[mid2]
			if n2:
				n2.queue_free()
			_missiles.erase(mid2)

func _process_mines_from_snapshot(snap: Dictionary) -> void:
	var arr: Array = []
	if snap.has("_mines"):
		arr = snap["_mines"]
	var seen: Dictionary = {}
	for m in arr:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid: int = int(m.get("id", -1))
		if mid < 0:
			continue
		seen[mid] = true
		var pos: Vector3 = Vector3(m.get("pos", Vector3.ZERO))
		if not _mines.has(mid):
			var node: Node = MINE_SCENE.instantiate()
			world_root.add_child(node)
			if node.has_method("configure"):
				node.call("configure", mid)
			node.global_position = pos
			_mines[mid] = node
		var n = _mines[mid]
		if n and n.has_method("set_target"):
			n.set_target(pos)
		elif n:
			n.global_position = pos
	for mid2 in _mines.keys():
		if not seen.has(mid2):
			var n2 = _mines[mid2]
			if n2:
				n2.queue_free()
			_mines.erase(mid2)


func _ensure_world_child(name: String) -> Node3D:
	var n: Node = world_root.get_node_or_null(name)
	if n == null:
		var nn: Node3D = Node3D.new()
		nn.name = name
		world_root.add_child(nn)
		return nn
	return n as Node3D


func _maybe_add_shape_pointcloud(parent: Node3D, shape_name: String, team: int, point_size: float, neutral: bool = false) -> void:
	if parent == null:
		return
	if not ShapeLib.shapes_ready():
		return
	if not ShapeLib.has_shape(shape_name):
		return

	var child_name: String = "W2Shape_%s" % shape_name
	var existing: Node = parent.get_node_or_null(child_name)
	if existing != null and existing.has_method("configure"):
		var t: int = team
		if neutral:
			t = 2
		existing.call("configure", shape_name, t)
		existing.set("point_size", point_size)
		return

	var pc: Node3D = PointCloudScript.new()
	pc.name = child_name
	pc.set("shape_name", shape_name)
	pc.set("team", team)
	pc.set("point_size", point_size)
	pc.set("max_points", 0)
	if neutral:
		pc.set("team", 2)
	parent.add_child(pc)


func _shape_for_vehicle(veh: String, team_id: int) -> String:
	var v: String = veh.to_lower()
	if v == "tank":
		return "tank_1" if team_id == 0 else "tank_2"
	if v == "scout":
		return "scout_1" if team_id == 0 else "scout_2"
	# Fallback
	return "tank_1" if team_id == 0 else "tank_2"

func _shape_for_building(btype: String, team_id: int) -> String:
	var t: String = btype.to_lower()
	if t == "turret" or t.ends_with("turret"):
		return "gun_turret_1"
	if t == "powercell" or t == "energy" or t.begins_with("power"):
		return "energy_1" if team_id == 0 else "energy_2"
	if t == "uplink":
		return "uplinkred" if team_id == 0 else "uplinkblue"
	# Default: treat unknown buildables as energy-like for now.
	return "energy_1" if team_id == 0 else "energy_2"

func _point_size_for_shape(shape: String) -> float:
	var s: String = shape.to_lower()
	if s.begins_with("tank"):
		return 0.08
	if s.begins_with("scout"):
		return 0.075
	if s.begins_with("cargo"):
		return 0.10
	if s.begins_with("gun_turret"):
		return 0.06
	if s.begins_with("uplink"):
		return 0.07
	return 0.08

func _reload_wulfram_shapes() -> void:
	# Hot-reload: run the extractor, then press L in the client.
	# This clears cached vertex buffers and forces any point-cloud nodes to rebuild.
	ShapeLib.clear_cache()
	# Also clear cached placeholder meshes/multimeshes so changes on disk are reflected.
	if PointCloudScript != null and PointCloudScript.has_method("clear_render_cache"):
		PointCloudScript.call("clear_render_cache")

	for n in get_tree().get_nodes_in_group("wulfram_pointcloud"):
		if n != null and n.has_method("reload_from_library"):
			n.call("reload_from_library")
		elif n != null and n.has_method("rebuild"):
			n.call("rebuild")

	# Ensure overlays get attached to objects that were spawned before extraction.
	if not _last_snapshot.is_empty():
		_process_crates_from_snapshot(_last_snapshot)
		_process_buildings_from_snapshot(_last_snapshot)
		for k in _avatars.keys():
			var av = _avatars.get(k)
			if av != null and av.has_method("_maybe_enable_wulfram_shape"):
				av.call("_maybe_enable_wulfram_shape")

	if is_instance_valid(hud):
		hud.set_status("Reloaded shapes. Meshes: %s" % _get_mesh_source_tag())

func _process_crates_from_snapshot(snap: Dictionary) -> void:
	var arr: Array = []
	if snap.has("_crates"):
		arr = snap["_crates"]
	var root := _ensure_world_child("CratesRoot")
	var seen: Dictionary = {}
	for c in arr:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cid: int = int(c.get("id", -1))
		if cid < 0:
			continue
		seen[cid] = true
		var posv = c.get("pos", Vector3.ZERO)
		var pos: Vector3 = posv if typeof(posv) == TYPE_VECTOR3 else Vector3.ZERO
		if not _crates.has(cid):
			var n := Node3D.new()
			n.name = "Crate_%d" % cid
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.2, 1.2, 1.2)
			mi.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_texture = _get_crate_texture()
			mat.albedo_color = Color(1.0, 1.0, 1.0)
			mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
			mi.material_override = mat
			n.add_child(mi)
			# Optional Wulfram silhouette overlay (if shapes extracted)
			_maybe_add_shape_pointcloud(n, "cargo", 2, 0.10, true)
			root.add_child(n)
			_crates[cid] = n
		var node: Node3D = _crates[cid]
		node.global_position = pos
		# If shapes were extracted mid-session, attach/update the overlay now.
		_maybe_add_shape_pointcloud(node, "cargo", 2, 0.10, true)

	for cid2 in _crates.keys():
		if not seen.has(cid2):
			var n2: Node = _crates[cid2]
			if n2:
				n2.queue_free()
			_crates.erase(cid2)


func _process_buildings_from_snapshot(snap: Dictionary) -> void:
	var arr: Array = []
	if snap.has("_bld"):
		arr = snap["_bld"]
	var root := _ensure_world_child("BuildingsRoot")
	var seen: Dictionary = {}
	for b in arr:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var bid: int = int(bd.get("id", -1))
		if bid < 0:
			continue
		seen[bid] = true
		var btype: String = str(bd.get("type", ""))
		var posv = bd.get("pos", Vector3.ZERO)
		var pos: Vector3 = posv if typeof(posv) == TYPE_VECTOR3 else Vector3.ZERO
		var team: int = int(bd.get("team", 0))
		var owner: int = int(bd.get("owner", -1))
		var byaw: float = float(bd.get("yaw", 0.0))
		var radius: float = float(bd.get("radius", 0.0))
		var hp: float = float(bd.get("hp", 0.0))
		var hpmax: float = float(bd.get("hpmax", max(1.0, hp)))

		if not _buildings.has(bid):
			var n := Node3D.new()
			n.name = "Building_%d" % bid

			# Body
			var body := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			var bt: String = btype.to_lower()
			if bt == "turret" or bt.ends_with("turret"):
				cm.top_radius = 0.65
				cm.bottom_radius = 0.85
				cm.height = 2.2
			else:
				cm.top_radius = 1.0
				cm.bottom_radius = 1.0
				cm.height = 1.8
			body.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_texture = _get_comm_texture(team)
			mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
			body.material_override = mat
			body.position = Vector3(0, 1.1, 0) if (bt == "turret" or bt.ends_with("turret")) else Vector3(0, 0.9, 0)
			n.add_child(body)

			# Radius ring
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.ring_radius = 1.0
			tm.pipe_radius = 0.03
			ring.mesh = tm
			var rmat := StandardMaterial3D.new()
			rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rmat.albedo_color = (Color(1.0, 0.25, 0.25, 0.35) if team == 0 else Color(0.2, 0.8, 1.0, 0.35))
			ring.material_override = rmat
			ring.rotation_degrees = Vector3(90, 0, 0)
			ring.position = Vector3(0, 0.05, 0)
			if radius > 0.0:
				ring.scale = Vector3(radius, 1.0, radius)
			n.add_child(ring)

			# Optional Wulfram silhouette overlay for building
			var shape_name: String = _shape_for_building(bt, team)
			var psize: float = _point_size_for_shape(shape_name)
			_maybe_add_shape_pointcloud(n, shape_name, team, psize, false)

			# Debug HP label
			var lbl := Label3D.new()
			lbl.name = "HPLabel"
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.pixel_size = 0.01
			lbl.position = Vector3(0, 3.1, 0)
			lbl.modulate = Color(1.0, 1.0, 1.0, 0.9)
			lbl.visible = false
			n.add_child(lbl)

			root.add_child(n)
			_buildings[bid] = n

		var node: Node3D = _buildings[bid]
		node.global_position = pos
		node.set_meta("owner", owner)
		if btype.to_lower() == "turret" or btype.to_lower().ends_with("turret"):
			node.rotation.y = byaw

		# Keep ring scale updated if radius changes.
		if radius > 0.0 and node.get_child_count() >= 2:
			var ring2 := node.get_child(1)
			if ring2 is MeshInstance3D:
				ring2.scale = Vector3(radius, 1.0, radius)

		# Update silhouette overlay if shapes become available.
		var shape_name2: String = _shape_for_building(btype.to_lower(), team)
		var psize2: float = _point_size_for_shape(shape_name2)
		_maybe_add_shape_pointcloud(node, shape_name2, team, psize2, false)

		# Visual intensity by HP
		var frac: float = 1.0
		if hpmax > 0.0001:
			frac = clamp(hp / hpmax, 0.0, 1.0)
		if node.get_child_count() >= 1:
			var body2 := node.get_child(0)
			if body2 is MeshInstance3D:
				var mm: Material = (body2 as MeshInstance3D).material_override
				if mm is StandardMaterial3D:
					var intensity: float = 0.35 + 0.65 * frac
					(mm as StandardMaterial3D).albedo_color = Color(intensity, intensity, intensity, 1.0)

		# Debug HP label update
		var lbl2: Label3D = node.get_node_or_null("HPLabel") as Label3D
		if lbl2 != null:
			lbl2.visible = _show_shape_debug
			lbl2.text = "%s %d/%d" % [btype, int(round(hp)), int(round(hpmax))]

	for bid2 in _buildings.keys():
		if not seen.has(bid2):
			var n2: Node = _buildings[bid2]
			if n2:
				n2.queue_free()
			_buildings.erase(bid2)



func _bar(v: float, vmax: float, width: int = 14) -> String:
	var w: int = max(1, width)
	var frac: float = 0.0
	if vmax > 0.0001:
		frac = clamp(v / vmax, 0.0, 1.0)
	var filled: int = int(round(frac * float(w)))
	filled = clamp(filled, 0, w)
	return "[" + "█".repeat(filled) + "░".repeat(w - filled) + "]"

func _compute_aimed_building(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	# Client-side ray vs building hit spheres using last snapshot.
	if _last_snapshot.is_empty() or (not _last_snapshot.has("_bld")) or typeof(_last_snapshot["_bld"]) != TYPE_ARRAY:
		return {}
	var arr: Array = _last_snapshot["_bld"]
	var best_t: float = max_dist + 1.0
	var best: Dictionary = {}
	for b in arr:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		var c: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
		# Hit center slightly above ground.
		c.y += 1.2
		var r: float = float(bd.get("hit_r", 3.5))
		# Ray-sphere intersection.
		var oc: Vector3 = from - c
		var bdot: float = oc.dot(dir)
		var cterm: float = oc.dot(oc) - r * r
		var disc: float = bdot * bdot - cterm
		if disc < 0.0:
			continue
		var sdisc: float = sqrt(disc)
		var t0: float = -bdot - sdisc
		var t1: float = -bdot + sdisc
		var t: float = t0
		if t < 0.0:
			t = t1
		if t < 0.0 or t > max_dist:
			continue
		if t < best_t:
			best_t = t
			best = {
				"id": int(bd.get("id", -1)),
				"type": str(bd.get("type", "")),
				"team": int(bd.get("team", 0)),
				"hp": float(bd.get("hp", 0.0)),
				"hpmax": float(bd.get("hpmax", 1.0)),
				"dist": best_t,
			}
	return best


func _is_in_friendly_powercell(team: int, pos: Vector3, snap: Dictionary) -> bool:
	if not snap.has("_bld") or typeof(snap["_bld"]) != TYPE_ARRAY:
		return false
	var arr: Array = snap["_bld"]
	for b in arr:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = b
		if str(bd.get("type", "")) != "powercell":
			continue
		if int(bd.get("team", -1)) != team:
			continue
		var bp: Vector3 = Vector3(bd.get("pos", Vector3.ZERO))
		var r: float = float(bd.get("radius", 0.0))
		if r <= 0.0:
			continue
		if pos.distance_to(bp) <= r:
			return true
	return false

func _update_status_from_snapshot(snap: Dictionary) -> void:

	var me := multiplayer.get_unique_id()
	var key := str(me)
	if not snap.has(key):
		return
	var p: Dictionary = snap[key]
	var hp: float = float(p.get("hp", 0.0))
	var hpmax: float = float(p.get("hpmax", 100.0))
	var pos: Vector3 = Vector3(p.get("pos", Vector3.ZERO))
	var spd: int = int(p.get("spd", 7))
	var fuel: float = float(p.get("fuel", _cfg_fuel_max))
	var veh: String = str(p.get("veh", "tank"))
	var charge: float = float(p.get("charge", 0.0))
	var cargo: int = int(p.get("cargo", 0))
	var team: int = int(p.get("team", 0))

	# Weapon cooldowns (server-authoritative)
	var cd_fire: float = float(p.get("cd_fire", 0.0))
	var cd_pulse: float = float(p.get("cd_pulse", 0.0))
	var cd_hunter: float = float(p.get("cd_hunter", 0.0))
	var cd_flare: float = float(p.get("cd_flare", 0.0))
	var cd_mine: float = float(p.get("cd_mine", 0.0))

	# Nearest cargo crate (for pickup debugging).
	var cnear: String = ""
	var best_d: float = 999999.0
	if snap.has("_crates") and typeof(snap["_crates"]) == TYPE_ARRAY:
		var carr: Array = snap["_crates"]
		for ce in carr:
			if typeof(ce) != TYPE_DICTIONARY:
				continue
			var cp: Vector3 = Vector3((ce as Dictionary).get("pos", Vector3.ZERO))
			var d2: float = Vector2(pos.x, pos.z).distance_to(Vector2(cp.x, cp.z))
			if d2 < best_d:
				best_d = d2
	if best_d < 999998.0 and best_d <= 60.0:
		cnear = "  CargoNear:%.0fm" % best_d

	var tinfo := ""
	if _target_peer_id >= 0 and snap.has(str(_target_peer_id)):
		var tp: Dictionary = snap[str(_target_peer_id)]
		var tpos: Vector3 = Vector3(tp.get("pos", Vector3.ZERO))
		var d: float = pos.distance_to(tpos)
		tinfo = "  Target: %d  (%.0fm)" % [_target_peer_id, d]

	# Hunter requires an enemy target.
	var has_valid_target: bool = false
	if _target_peer_id >= 0 and snap.has(str(_target_peer_id)):
		var tp2: Dictionary = snap[str(_target_peer_id)]
		var tteam: int = int(tp2.get("team", -999))
		has_valid_target = (tteam != team)

	var in_power: bool = _is_in_friendly_powercell(team, pos, snap)
	var power_tag: String = "  POWER" if in_power else ""

	var fuel_bar: String = _bar(fuel, _cfg_fuel_max, 18)
	var charge_bar: String = _bar(charge, _cfg_charge_max, 18)

	var line1: String = "HP %.0f  Fuel %.0f/%.0f %s  Spd:%d  Veh:%s%s" % [hp, fuel, _cfg_fuel_max, fuel_bar, spd, veh, power_tag]
	var line2: String = "Cargo %d/%d" % [cargo, _cfg_cargo_max]
	if veh == "scout":
		line2 += "  Charge %.0f/%.0f %s" % [charge, _cfg_charge_max, charge_bar]

	# Aimed building (for repair UX)
	var aim_info: Dictionary = _compute_aimed_building(pos + Vector3(0, 7.0, 0), _aim_dir(_pred_yaw, _aim_pitch).normalized(), 45.0)
	_aim_building_id = int(aim_info.get("id", -1))
	_aim_building_type = str(aim_info.get("type", ""))
	_aim_building_team = int(aim_info.get("team", -1))
	_aim_building_hp = float(aim_info.get("hp", 0.0))
	_aim_building_hpmax = float(aim_info.get("hpmax", 0.0))
	var aim_tag: String = ""
	if _aim_building_id >= 0:
		var team_tag: String = ("RED" if _aim_building_team == 0 else "BLUE")
		aim_tag = "  AimBld:%s#%d %s %d/%d" % [_aim_building_type, _aim_building_id, team_tag, int(round(_aim_building_hp)), int(round(_aim_building_hpmax))]
		if _aim_building_team == team and cargo > 0 and _aim_building_hp < _aim_building_hpmax - 0.5:
			aim_tag += "  (R repair)"

	var line3: String = "Pos:[%.0f,%.0f,%.0f]%s%s%s" % [pos.x, pos.y, pos.z, tinfo, cnear, aim_tag]
	var line4: String = "Texture source: %s  Meshes: %s" % [_get_texture_source_tag(), _get_mesh_source_tag()]
	var line5: String = ""
	if _show_shape_debug and ShapeLib.shapes_ready():
		var sname: String = _shape_for_vehicle(veh, team)
		if ShapeLib.has_shape(sname):
			var info: Dictionary = ShapeLib.get_decode_info(sname)
			var tri_ct: int = int(info.get("tri_count", 0))
			var stride: int = int(info.get("stride", 0))
			var phase: int = int(info.get("phase", 0))
			var mr: float = float(info.get("mat_ratio", 0.0))
			var uses: bool = bool(info.get("uses_mat_ids", false))
			line5 = "ShapeDecode: %s  tris:%d  s:%d p:%d  mats:%.0f%%  mode:%s" % [sname, tri_ct, stride, phase, mr * 100.0, ("MatIDs" if uses else "Buckets")]

	if is_instance_valid(hud):
		# Structured HUD widgets (if present)
		var fps: int = Engine.get_frames_per_second()
		var age_ms: int = 0
		if _last_snapshot_msec > 0:
			age_ms = max(0, Time.get_ticks_msec() - _last_snapshot_msec)
		if hud.has_method("set_stats"):
			hud.call("set_stats", hp, hpmax, fuel, _cfg_fuel_max, charge, _cfg_charge_max, cargo, _cfg_cargo_max, spd, veh, in_power)
		if hud.has_method("set_net"):
			hud.call("set_net", me, fps, age_ms, _connected)

		# Weapon widget (cooldowns/availability), Wulfram-inspired.
		if hud.has_method("set_weapons"):
			var has_tgt: bool = false
			if _target_peer_id >= 0 and snap.has(str(_target_peer_id)):
				var tp: Dictionary = snap[str(_target_peer_id)]
				var tteam: int = int(tp.get("team", -1))
				has_tgt = (tteam != -1 and tteam != team)
			var prim_down: bool = Input.is_action_pressed("fire_primary")
			var sec_down: bool = Input.is_action_pressed("fire_secondary")
			hud.call(
				"set_weapons",
				veh,
				team,
			fuel,
				_cfg_fuel_max,
				charge,
				_cfg_charge_max,
				cd_fire,
				cd_pulse,
				cd_hunter,
				cd_flare,
				cd_mine,
				_cfg_auto_rate_hz,
				_cfg_pulse_cooldown,
				_cfg_hunter_cooldown,
				_cfg_flare_cooldown,
				_cfg_mine_cooldown,
				_cfg_fuel_cost_autocannon,
				_cfg_fuel_cost_pulse,
				_cfg_fuel_cost_hunter,
				_cfg_fuel_cost_flare,
				_cfg_fuel_cost_mine,
				_cfg_beam_fuel_cost_per_s,
				has_tgt,
				prim_down,
				sec_down
			)

		# Minimap stub (Wulfram-style radar).
		if hud.has_method("set_minimap"):
			var players: Array = []
			for k in snap.keys():
				var ks := str(k)
				if ks.begins_with("_"):
					continue
				var pid: int = int(ks)
				var pd: Dictionary = snap[ks]
				players.append({"id": pid, "pos": Vector3(pd.get("pos", Vector3.ZERO)), "team": int(pd.get("team", 0)), "veh": str(pd.get("veh", ""))})
			var crates: Array = []
			if snap.has("_crates") and typeof(snap["_crates"]) == TYPE_ARRAY:
				for ce in (snap["_crates"] as Array):
					if typeof(ce) != TYPE_DICTIONARY: continue
					crates.append({"pos": Vector3((ce as Dictionary).get("pos", Vector3.ZERO))})
			var bld: Array = []
			if snap.has("_bld") and typeof(snap["_bld"]) == TYPE_ARRAY:
				for be in (snap["_bld"] as Array):
					if typeof(be) != TYPE_DICTIONARY: continue
					var bd: Dictionary = be
					bld.append({"id": int(bd.get("id", -1)), "pos": Vector3(bd.get("pos", Vector3.ZERO)), "team": int(bd.get("team", 0)), "type": str(bd.get("type", ""))})
			hud.call("set_minimap", pos, _pred_yaw, team, players, crates, bld, _target_peer_id)

		# Build HUD (graphical). Shows build costs + placement preview + recent server rejection.
		if hud.has_method("set_build"):
			var pk: String = ""
			if Input.is_action_pressed("build_turret"):
				pk = "turret"
			elif Input.is_action_pressed("build_powercell"):
				pk = "powercell"
			var pok: bool = false
			var preason: String = ""
			if not pk.is_empty():
				var pres: Dictionary = _compute_build_preview_pose(pk)
				pok = bool(pres.get("ok", false))
				preason = str(pres.get("reason", "BLOCKED"))

			var rage: float = -1.0
			if _hud_build_reject_msec >= 0:
				rage = float(max(0, Time.get_ticks_msec() - _hud_build_reject_msec)) / 1000.0

			var can_repair: bool = (_aim_building_id >= 0 and _aim_building_team == team and cargo > 0 and _aim_building_hp < _aim_building_hpmax - 0.5)
			hud.call(
				"set_build",
				cargo,
				_cfg_cargo_max,
				1,
				_cfg_turret_build_cost,
				pk,
				pok,
				preason,
				_hud_build_reject_kind,
				_hud_build_reject_reason,
				_hud_build_reject_slope,
				rage,
				can_repair,
				1
			)

		if line5.is_empty():
			hud.set_status("%s\n%s\n%s\n%s" % [line1, line2, line3, line4])
		else:
			hud.set_status("%s\n%s\n%s\n%s\n%s" % [line1, line2, line3, line4, line5])

func _cycle_target() -> void:
	if _last_snapshot.is_empty():
		return
	var me := multiplayer.get_unique_id()
	var ids: Array = []
	for k in _last_snapshot.keys():
		var ks := str(k)
		if ks.begins_with("_"):
			continue
		var id := int(ks)
		if id != me:
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		_target_peer_id = -1
		_update_target_markers()
		return
	if _target_peer_id < 0 or not ids.has(_target_peer_id):
		_target_peer_id = ids[0]
		_update_target_markers()
		return
	var idx := ids.find(_target_peer_id)
	idx = (idx + 1) % ids.size()
	_target_peer_id = ids[idx]
	_update_target_markers()

func _update_target_markers() -> void:
	for id in _avatars.keys():
		var av = _avatars.get(id)
		if av and av.has_method("set_targeted"):
			av.call("set_targeted", int(id) == _target_peer_id)


func _update_build_preview(_delta: float) -> void:
	# Client-side preview only. The server is authoritative and may still reject a build.
	var want_kind: String = ""
	if Input.is_action_pressed("build_turret"):
		want_kind = "turret"
	elif Input.is_action_pressed("build_powercell"):
		want_kind = "powercell"

	if want_kind == "":
		_clear_build_preview()
		return

	# Need at least one snapshot and our avatar to preview placement.
	if _last_snapshot.is_empty() or not _avatars.has(multiplayer.get_unique_id()):
		_clear_build_preview()
		return

	_ensure_build_preview(want_kind)
	var res: Dictionary = _compute_build_preview_pose(want_kind)
	var ok: bool = bool(res.get("ok", false))
	var pos: Vector3 = Vector3(res.get("pos", Vector3.ZERO))
	var reason: String = str(res.get("reason", "BLOCKED"))
	if _build_preview != null:
		_build_preview.global_position = pos
		_set_build_preview_ok(ok)
		_set_build_preview_label("%s: %s" % [want_kind, ("OK" if ok else reason)])

	# Toast only when the reason changes (prevents spam).
	var new_reason: String = "%s|%s" % [want_kind, ("OK" if ok else reason)]
	if new_reason != _build_preview_reason:
		_build_preview_reason = new_reason
		if is_instance_valid(hud) and hud.has_method("flash_message"):
			hud.call("flash_message", "Build %s: %s" % [want_kind, ("OK" if ok else reason)], 0.55)


func _ensure_build_preview(kind: String) -> void:
	if _build_preview != null and is_instance_valid(_build_preview) and _build_preview_kind == kind:
		return
	_clear_build_preview()
	_build_preview_kind = kind
	var root := _ensure_world_child("BuildPreviewRoot")
	var n := Node3D.new()
	n.name = "BuildPreview"
	root.add_child(n)

	# Body
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 1.8
	body.mesh = cm
	body.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.25, 0.45)
	body.material_override = mat
	n.add_child(body)

	# Radius ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.ring_radius = 1.0
	tm.pipe_radius = 0.035
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(0, 0.08, 0)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.2, 1.0, 0.25, 0.45)
	ring.material_override = rmat
	n.add_child(ring)

	# Label
	var lbl := Label3D.new()
	lbl.name = "PreviewLabel"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.01
	lbl.position = Vector3(0, 2.8, 0)
	lbl.modulate = Color(1, 1, 1, 0.95)
	n.add_child(lbl)

	_build_preview = n
	_set_build_preview_radius(kind)


func _set_build_preview_radius(kind: String) -> void:
	if _build_preview == null:
		return
	var ring := _build_preview.get_child(1)
	if not (ring is MeshInstance3D):
		return
	var r: float = _cfg_powercell_radius if kind == "powercell" else _cfg_turret_range
	if r > 0.0:
		(ring as MeshInstance3D).scale = Vector3(r, 1.0, r)


func _set_build_preview_label(text: String) -> void:
	if _build_preview == null:
		return
	var lbl: Label3D = _build_preview.get_node_or_null("PreviewLabel") as Label3D
	if lbl != null:
		lbl.text = text


func _set_build_preview_ok(ok: bool) -> void:
	if _build_preview == null:
		return
	var col: Color = Color(0.2, 1.0, 0.25, 0.45) if ok else Color(1.0, 0.25, 0.25, 0.45)
	var body := _build_preview.get_child(0)
	if body is MeshInstance3D:
		var m: Material = (body as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = col
	var ring := _build_preview.get_child(1)
	if ring is MeshInstance3D:
		var m2: Material = (ring as MeshInstance3D).material_override
		if m2 is StandardMaterial3D:
			(m2 as StandardMaterial3D).albedo_color = col


func _clear_build_preview() -> void:
	if _build_preview != null and is_instance_valid(_build_preview):
		_build_preview.queue_free()
	_build_preview = null
	_build_preview_kind = ""
	_build_preview_reason = ""


func _compute_build_preview_pose(kind: String) -> Dictionary:
	var me: int = multiplayer.get_unique_id()
	var av: Node3D = _avatars.get(me) as Node3D
	if av == null:
		return {"ok": false, "reason": "NO_AVATAR", "pos": Vector3.ZERO}
	var yaw: float = _pred_yaw
	var forward: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	var desired: Vector3 = av.global_position + forward * _cfg_build_distance
	return _validate_build_preview(kind, desired)


func _validate_build_preview(kind: String, desired: Vector3) -> Dictionary:
	# 1) Cargo check from last snapshot
	var me: int = multiplayer.get_unique_id()
	var key: String = str(me)
	var cargo: int = 0
	if _last_snapshot.has(key):
		cargo = int((_last_snapshot[key] as Dictionary).get("cargo", 0))
	var need: int = _cfg_powercell_build_cost
	if kind == "turret":
		need = _cfg_turret_build_cost
	if cargo < need:
		return {"ok": false, "reason": "NO_CARGO", "pos": desired}

	# 2) Ground raycast + slope
	var space := get_world_3d().direct_space_state
	var from: Vector3 = desired + Vector3(0, 250, 0)
	var to: Vector3 = desired + Vector3(0, -250, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "NO_GROUND", "pos": desired}
	var p: Vector3 = Vector3(hit.get("position", desired))
	var n: Vector3 = Vector3(hit.get("normal", Vector3.UP)).normalized()
	var slope: float = rad_to_deg(acos(clamp(n.dot(Vector3.UP), -1.0, 1.0)))
	if slope > _cfg_build_max_slope_deg:
		return {"ok": false, "reason": "SLOPE", "pos": p}

	# 3) Overlap against existing buildings (approx)
	for bid in _buildings.keys():
		var bn: Node3D = _buildings[bid] as Node3D
		if bn == null:
			continue
		if bn.global_position.distance_to(p) < _cfg_build_min_spacing:
			return {"ok": false, "reason": "OVERLAP", "pos": p}

	return {"ok": true, "reason": "OK", "pos": p}


func _spawn_muzzle_fx(pos: Vector3, team: int) -> void:
	_spawn_ping_fx(pos, 0.55, team)


func _spawn_impact_fx(pos: Vector3, team: int) -> void:
	_spawn_ping_fx(pos, 0.35, team)


func _spawn_ping_fx(pos: Vector3, size: float, team: int) -> void:
	# Lightweight “ping” FX: a small unshaded sphere that quickly scales down and frees.
	var n := Node3D.new()
	n.global_position = pos
	world_root.add_child(n)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if team == 0:
		mat.albedo_color = Color(1.0, 0.35, 0.35, 0.85)
	else:
		mat.albedo_color = Color(0.35, 0.85, 1.0, 0.85)
	mi.material_override = mat
	n.add_child(mi)
	n.scale = Vector3.ONE * size
	var tw := get_tree().create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * max(0.02, size * 0.1), 0.12)
	tw.tween_callback(Callable(n, "queue_free"))

func _spawn_explosion_fx(pos: Vector3, radius: float) -> void:
	# Minimal debug FX: expanding sphere that auto-frees.
	var n := Node3D.new()
	n.global_position = pos
	world_root.add_child(n)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	n.add_child(mi)
	var tw := get_tree().create_tween()
	n.scale = Vector3.ONE * 0.2
	tw.tween_property(n, "scale", Vector3.ONE * max(0.25, radius * 0.12), 0.25)
	# Note: typed return annotations are not supported on function literals in some 4.x builds.
	# Keep this untyped for maximum compatibility.
	tw.tween_callback(Callable(n, "queue_free"))