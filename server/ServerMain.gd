extends Node3D

const DEFAULT_PORT: int = 2456
const TICK_RATE: int = 30
const SNAPSHOT_RATE: int = 10

const HIT_BUILDING_OFFSET: int = 100000

const DEFAULT_MAP_SCENE := "res://imported_maps/aberdour.tscn"

@export var map_scene_path: String = DEFAULT_MAP_SCENE

# --- Strategic starships (Uplink-controlled in classic Wulfram) ---
# Server-authoritative placeholder model so the client UI can render orbit sectors
# consistently (orbit sector == ship sector).
const MAX_STARSHIPS_PER_TEAM: int = 3
var starships: Array = []

# --- Vehicle sim parameters (placeholder tank) ---
@export var max_speed: float = 75.0
@export var accel: float = 140.0
@export var friction: float = 85.0

# --- Scout chassis (fast, light) ---
@export var scout_max_speed: float = 105.0
@export var scout_accel: float = 210.0
@export var scout_friction: float = 120.0
@export var tank_max_hp: float = 100.0
@export var scout_max_hp: float = 70.0

# --- Fuel / Energy (Wulfram-style speed 7 neutral) ---
@export var fuel_max: float = 100.0
@export var fuel_regen_per_step: float = 1.2 # per second per step below 7
@export var fuel_drain_per_step: float = 1.6 # per second per step above 7
@export var overdrive_speed_bonus: float = 0.08 # +8% max speed per step above 7

# --- Weapon fuel costs (tunable) ---
@export var fuel_cost_autocannon_shot: float = 0.25
@export var fuel_cost_pulse: float = 6.0
@export var fuel_cost_hunter: float = 10.0
@export var fuel_cost_mine: float = 4.0
@export var fuel_cost_flare: float = 2.0

# --- Cargo + Base Building (early prototype) ---
@export var cargo_max: int = 5
@export var cargo_pickup_radius: float = 4.0
@export var cargo_drop_distance: float = 10.0
@export var crate_ttl: float = 120.0

@export var initial_cargo_crates: int = 16
@export var initial_cargo_spread: float = 180.0

@export var build_distance: float = 12.0
@export var powercell_radius: float = 35.0
@export var powercell_max_hp: float = 220.0
@export var powercell_fuel_regen_bonus: float = 10.0 # flat fuel/sec inside radius
@export var powercell_hp_regen_bonus: float = 2.0 # hp/sec inside radius
@export var powercell_charge_regen_bonus: float = 22.0 # charge/sec inside radius (scout)

# --- Defensive turret (buildable using cargo) ---
@export var turret_build_cost: int = 1
@export var powercell_build_cost: int = 1
@export var repair_cost: int = 1
@export var turret_max_hp: float = 140.0
@export var turret_range: float = 55.0
@export var turret_fire_rate_hz: float = 2.5
@export var turret_damage: float = 6.0
@export var turret_muzzle_height: float = 6.0

# --- Skypump (stabilizes orbit sectors; strategic layer) ---
@export var skypump_build_cost: int = 1
@export var skypump_max_hp: float = 120.0
@export var skypump_hit_radius: float = 4.0

# --- Uplink (base/strategic control point) ---
@export var uplink_max_hp: float = 260.0
@export var uplink_hit_radius: float = 6.0

# Turret aim feel (server-authoritative)
@export var turret_turn_rate_deg: float = 180.0
@export var turret_fire_cone_deg: float = 10.0


# --- Building damage + hit volumes (server authoritative) ---
@export var powercell_hit_radius: float = 6.0
@export var turret_hit_radius: float = 3.5
@export var building_damage_mult_autocannon: float = 0.85
@export var building_damage_mult_beam: float = 0.65
@export var building_damage_mult_explosion: float = 1.0
@export var powercell_drop_crates: int = 2
@export var turret_drop_crates: int = 1

# --- Build placement validation (server-authoritative) ---
@export var build_max_slope_deg: float = 24.0
@export var build_sample_spacing: float = 2.0
@export var build_min_spacing: float = 6.0

# --- Building interaction: repair (uses cargo) ---
@export var repair_range: float = 18.0
@export var repair_amount_powercell: float = 80.0
@export var repair_amount_turret: float = 55.0

# --- Scout repair beam (RMB while in scout) ---
@export var beam_range: float = 450.0
@export var beam_damage_per_s: float = 12.0
@export var beam_heal_per_s: float = 16.0
@export var beam_charge_gain_per_s: float = 14.0
@export var beam_charge_max: float = 100.0
@export var beam_fuel_cost_per_s: float = 2.5


# Hover spring (PD controller).
@export var hover_default: float = 20.0
@export var hover_min: float = 8.0
@export var hover_max: float = 45.0
@export var hover_adjust_speed: float = 18.0
@export var hover_k: float = 45.0
@export var hover_d: float = 10.0

# --- Weapons (Milestone: basic autocannon) ---
@export var auto_rate_hz: float = 10.0
@export var auto_damage: float = 8.0
@export var auto_range: float = 650.0
@export var auto_hit_radius: float = 2.75
@export var muzzle_height: float = 7.0

# --- Weapons: Pulse Cannon (projectile + AoE) ---
@export var pulse_cooldown: float = 1.25
@export var pulse_speed: float = 240.0
@export var pulse_damage: float = 55.0
@export var pulse_radius: float = 14.0
@export var pulse_ttl: float = 4.0
@export var pulse_hit_radius: float = 2.0

# --- Weapons: Hunter missile (guided + countered by flares) ---
@export var hunter_cooldown: float = 3.5
@export var hunter_speed: float = 210.0
@export var hunter_turn_rate: float = 2.6 # rad/s
@export var hunter_damage: float = 95.0
@export var hunter_radius: float = 18.0
@export var hunter_ttl: float = 7.5
@export var hunter_hit_radius: float = 2.5

# --- Countermeasure: Flare ---
@export var flare_duration: float = 1.25
@export var flare_cooldown: float = 4.5

# --- Deployables: Mines (first deployable) ---
@export var mine_cooldown: float = 2.0
@export var mine_arm_delay: float = 0.35
@export var mine_trigger_radius: float = 12.0
@export var mine_damage: float = 85.0
@export var mine_radius: float = 12.0
@export var mine_ttl: float = 45.0

var port: int = DEFAULT_PORT

var _tick_accum: float = 0.0
var _tick_dt: float = 1.0 / float(TICK_RATE)
var _snap_accum: float = 0.0
var _snap_dt: float = 1.0 / float(SNAPSHOT_RATE)

# peer_id -> Dictionary(
#   "pos": Vector3, "vel": Vector3, "yaw": float, "pitch": float,
#   "hover": float, "hp": float, "fire_cd": float,
#   "team": int, "_last_input": Dictionary
# )
var players: Dictionary = {}

# proj_id -> Dictionary("pos":Vector3,"vel":Vector3,"ttl":float,"sh":int)
var projectiles: Dictionary = {}
var _next_proj_id: int = 1

# mid_id -> Dictionary("pos":Vector3,"dir":Vector3,"ttl":float,"sh":int,"tgt":int,"locked":bool)
var missiles: Dictionary = {}
var _next_missile_id: int = 1

# mine_id -> Dictionary("pos":Vector3,"ttl":float,"arm":float,"sh":int,"team":int)
var mines: Dictionary = {}
var _next_mine_id: int = 1

var crates: Dictionary = {} # cid -> {"id":int,"pos":Vector3,"ttl":float}
var _next_crate_id: int = 1

var buildings: Dictionary = {} # bid -> {"id":int,"type":String,"pos":Vector3,"team":int,"hp":float,"radius":float}
var _next_building_id: int = 1

var _seeded_uplinks: bool = false


var _events: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var world_root: Node3D = $World

# Cached terrain height bounds for robust raycasts.
var _terrain_min_y: float = -2000.0
var _terrain_max_y: float = 2000.0
var _terrain_has_bounds: bool = false

# Cached map dimensions (used for strategic sector mapping).
var _map_world_w: float = 0.0
var _map_world_d: float = 0.0

func _ready() -> void:
	_rng.randomize()

	# Read command line args like: -- --port 2456 --map aberdour
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif args[i] == "--map" and i + 1 < args.size():
			var m := args[i + 1]
			if not m.ends_with(".tscn"):
				m += ".tscn"
			map_scene_path = "res://imported_maps/%s" % m

	# Start ENet server
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, 256)
	if err != OK:
		push_error("Failed to start server. err=%s" % str(err))
		get_tree().quit(1)
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("Server listening on port %d" % port)
	_load_map()
	_init_starships()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_tick_accum += delta
	_snap_accum += delta

	while _tick_accum >= _tick_dt:
		_tick_accum -= _tick_dt
		_sim_tick(_tick_dt)

	if _snap_accum >= _snap_dt:
		_snap_accum = 0.0
		_send_snapshot_and_events()

func _on_peer_connected(id: int) -> void:
	var team_id: int = id % 2
	players[id] = {
		"pos": _pick_spawn_pos_team(team_id, 80.0),
		"vel": Vector3.ZERO,
		"yaw": 0.0,
		"pitch": 0.0,
		"hover": hover_default,
		"hp": tank_max_hp,
		"veh": "tank",
		"spd": 7,
		"fuel": fuel_max,
		"cargo": 0,
		"charge": 0.0,
		"veh_cd": 0.0,
		"fire_cd": 0.0,
		"pulse_cd": 0.0,
		"hunter_cd": 0.0,
		"flare_cd": 0.0,
		"flare_t": 0.0,
		"mine_cd": 0.0,
		"team": team_id,
		"_last_input": {}
	}
	print("Peer connected: ", id)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	print("Peer disconnected: ", id)





func _do_scout_beam(shooter_id: int, shooter_pos: Vector3, yaw: float, pitch: float, dt: float) -> void:
	# Continuous beam: damage enemies to build charge; spend charge to heal allies.
	if not players.has(shooter_id):
		return
	var p: Dictionary = players[shooter_id]
	var from: Vector3 = shooter_pos + Vector3(0, muzzle_height, 0)
	var dir: Vector3 = _aim_dir(yaw, pitch).normalized()

	var my_team: int = int(p.get("team", shooter_id % 2))
	var charge: float = float(p.get("charge", 0.0))

	# Find nearest hit among players + buildings.
	var phit: Dictionary = _ray_hit_player(from, dir, beam_range, shooter_id, 4.0)
	var bhit: Dictionary = _ray_hit_building(from, dir, beam_range, shooter_id, true)

	var hit_player: bool = (not phit.is_empty())
	var hit_building: bool = (not bhit.is_empty())
	if not hit_player and not hit_building:
		return

	var pdist: float = float(phit.get("dist", beam_range + 1.0))
	var bdist: float = float(bhit.get("dist", beam_range + 1.0))

	if hit_player and (not hit_building or pdist <= bdist):
		var hit_id: int = int(phit["id"])
		if not players.has(hit_id):
			return
		var tp: Dictionary = players[hit_id]
		var their_team: int = int(tp.get("team", hit_id % 2))
		if their_team == my_team:
			if charge <= 0.0:
				return
			var heal_amt: float = min(charge, beam_heal_per_s * dt)
			var max_hp: float = _veh_max_hp(str(tp.get("veh", "tank")))
			var hp: float = float(tp.get("hp", max_hp))
			hp = min(max_hp, hp + heal_amt)
			charge = max(0.0, charge - heal_amt)
			tp["hp"] = hp
			players[hit_id] = tp
			p["charge"] = charge
			players[shooter_id] = p
			_events.append({"t":"beam", "sh": shooter_id, "to": hit_id, "from": from, "pos": Vector3(phit["pos"])})
		else:
			var dmg: float = beam_damage_per_s * dt
			var hp2: float = float(tp.get("hp", _veh_max_hp(str(tp.get("veh","tank")))))
			hp2 -= dmg
			tp["hp"] = hp2
			players[hit_id] = tp
			charge = min(beam_charge_max, charge + beam_charge_gain_per_s * dt)
			p["charge"] = charge
			players[shooter_id] = p
			_events.append({"t":"beam", "sh": shooter_id, "to": hit_id, "from": from, "pos": Vector3(phit["pos"])})
			if hp2 <= 0.0:
				_respawn_player(hit_id)
		return

	# Building hit
	var bid: int = int(bhit["id"])
	if not buildings.has(bid):
		return
	var b: Dictionary = buildings[bid]
	var bteam: int = int(b.get("team", 0))
	var hpmax: float = float(b.get("hpmax", max(1.0, float(b.get("hp", 1.0)))))
	var bhp: float = float(b.get("hp", hpmax))
	if bteam == my_team:
		if charge <= 0.0:
			return
		var heal_amt2: float = min(charge, beam_heal_per_s * dt)
		bhp = min(hpmax, bhp + heal_amt2)
		charge = max(0.0, charge - heal_amt2)
		b["hp"] = bhp
		buildings[bid] = b
		p["charge"] = charge
		players[shooter_id] = p
		_events.append({"t":"beam", "sh": shooter_id, "to": -(HIT_BUILDING_OFFSET + bid), "from": from, "pos": Vector3(bhit["pos"])})
	else:
		var dmg2: float = beam_damage_per_s * dt * building_damage_mult_beam
		bhp -= dmg2
		b["hp"] = bhp
		buildings[bid] = b
		charge = min(beam_charge_max, charge + beam_charge_gain_per_s * dt)
		p["charge"] = charge
		players[shooter_id] = p
		_events.append({"t":"beam", "sh": shooter_id, "to": -(HIT_BUILDING_OFFSET + bid), "from": from, "pos": Vector3(bhit["pos"])})
		if bhp <= 0.0:
			_destroy_building(bid, shooter_id)


func _do_pulse_fire(shooter_id: int, shooter_pos: Vector3, yaw: float, pitch: float) -> void:
	var from: Vector3 = shooter_pos + Vector3(0, muzzle_height, 0)
	var dir: Vector3 = _aim_dir(yaw, pitch).normalized()

	var pid: int = _next_proj_id
	_next_proj_id += 1

	var pr: Dictionary = {
		"pos": from,
		"vel": dir * pulse_speed,
		"ttl": pulse_ttl,
		"sh": shooter_id,
	}
	projectiles[pid] = pr

	_events.append({
		"t": "pulse_fire",
		"sh": shooter_id,
		"from": from,
		"dir": dir,
	})

func _simulate_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	var to_remove: Array = []
	for pid in projectiles.keys():
		var pr: Dictionary = projectiles[pid]
		var ttl: float = float(pr.get("ttl", 0.0)) - dt
		if ttl <= 0.0:
			to_remove.append(pid)
			continue
		var from: Vector3 = Vector3(pr.get("pos", Vector3.ZERO))
		var vel: Vector3 = Vector3(pr.get("vel", Vector3.ZERO))
		var to: Vector3 = from + vel * dt
		var seg: Vector3 = to - from
		var dist: float = seg.length()
		if dist <= 0.0001:
			pr["ttl"] = ttl
			projectiles[pid] = pr
			continue
		var dir: Vector3 = seg / dist
		var sh: int = int(pr.get("sh", -1))

		# Check player hit
		var best_dist: float = dist + 0.001
		var best_pos: Vector3 = to
		var hit_any: bool = false

		var phit: Dictionary = _ray_hit_player(from, dir, dist, sh, pulse_hit_radius)
		if not phit.is_empty():
			best_dist = float(phit["dist"])
			best_pos = Vector3(phit["pos"])
			hit_any = true

		# Check world hit
		var whit: Dictionary = _ray_hit_world(from, dir, dist)
		if not whit.is_empty():
			var wdist: float = float(whit.get("dist", dist))
			if wdist < best_dist:
				best_dist = wdist
				best_pos = Vector3(whit.get("pos", best_pos))
				hit_any = true

		if hit_any:
			_do_explosion(sh, best_pos, pulse_radius, pulse_damage)
			to_remove.append(pid)
			continue

		# No hit: advance.
		pr["pos"] = to
		pr["ttl"] = ttl
		projectiles[pid] = pr

	for pid in to_remove:
		projectiles.erase(pid)


func _do_explosion(shooter_id: int, pos: Vector3, radius: float, damage: float) -> void:
	var hits: Array = []

	# Damage players
	for id in players.keys():
		var pid: int = int(id)
		var p: Dictionary = players[pid]
		var ppos: Vector3 = Vector3(p.get("pos", Vector3.ZERO))
		var d: float = ppos.distance_to(pos)
		if d <= radius:
			var falloff: float = 1.0 - (d / radius)
			var dmg: float = damage * max(0.0, falloff)
			var hp: float = float(p.get("hp", 100.0)) - dmg
			p["hp"] = hp
			players[pid] = p
			if pid != shooter_id:
				hits.append(pid)
			if hp <= 0.0:
				_respawn_player(pid)

	# Damage buildings (no friendly-fire by default)
	var shooter_team: int = -999
	if players.has(shooter_id):
		var sp: Dictionary = players[shooter_id]
		shooter_team = int(sp.get("team", shooter_id % 2))
	if not buildings.is_empty():
		var to_apply: Array = []
		for bid in buildings.keys():
			to_apply.append(int(bid))
		for bid2 in to_apply:
			if not buildings.has(bid2):
				continue
			var b: Dictionary = buildings[bid2]
			var bteam: int = int(b.get("team", 0))
			if shooter_team != -999 and bteam == shooter_team:
				continue
			var c: Vector3 = _building_hit_center(b)
			var d2: float = c.distance_to(pos)
			if d2 > radius:
				continue
			var fall2: float = 1.0 - (d2 / radius)
			var dmg2: float = damage * max(0.0, fall2) * building_damage_mult_explosion
			_damage_building(bid2, shooter_id, dmg2)

	_events.append({
		"t": "explosion",
		"sh": shooter_id,
		"pos": pos,
		"r": radius,
		"hits": hits,
	})


func _do_flare(user_id: int) -> void:
	if not players.has(user_id):
		return
	var p: Dictionary = players[user_id]
	p["flare_t"] = flare_duration
	_events.append({"t": "flare", "id": user_id, "dur": flare_duration})
	players[user_id] = p

func _do_hunter_fire(shooter_id: int, shooter_pos: Vector3, yaw: float, pitch: float, target_id: int) -> void:
	var from: Vector3 = shooter_pos + Vector3(0, muzzle_height, 0)
	var dir: Vector3 = _aim_dir(yaw, pitch).normalized()
	var mid: int = _next_missile_id
	_next_missile_id += 1
	missiles[mid] = {
		"pos": from,
		"dir": dir,
		"ttl": hunter_ttl,
		"sh": shooter_id,
		"tgt": target_id,
		"locked": true,
	}
	_events.append({"t": "hunter_fire", "sh": shooter_id, "id": mid, "from": from, "dir": dir, "tgt": target_id})

func _simulate_missiles(dt: float) -> void:
	if missiles.is_empty():
		return
	var to_remove: Array = []
	for mid in missiles.keys():
		var m: Dictionary = missiles[mid]
		var ttl: float = float(m.get("ttl", 0.0)) - dt
		if ttl <= 0.0:
			to_remove.append(mid)
			continue
		var pos: Vector3 = Vector3(m.get("pos", Vector3.ZERO))
		var dir: Vector3 = Vector3(m.get("dir", Vector3.FORWARD)).normalized()
		var sh: int = int(m.get("sh", -1))
		var tgt: int = int(m.get("tgt", -1))
		var locked: bool = bool(m.get("locked", false))

		# Countermeasure: if target is flaring, break lock.
		if locked and tgt >= 0 and players.has(tgt):
			var tp: Dictionary = players[tgt]
			var flare_t: float = float(tp.get("flare_t", 0.0))
			if flare_t > 0.0:
				locked = false
				m["locked"] = false
				_events.append({"t": "lock_break", "id": int(mid), "tgt": tgt})

		# Guidance: steer toward target position when locked.
		if locked and tgt >= 0 and players.has(tgt):
			var tp2: Dictionary = players[tgt]
			var tpos: Vector3 = Vector3(tp2.get("pos", Vector3.ZERO)) + Vector3(0, muzzle_height * 0.5, 0)
			var desired_dir: Vector3 = (tpos - pos)
			if desired_dir.length() > 0.001:
				desired_dir = desired_dir.normalized()
				# Turn-limited slerp (approx)
				var max_ang: float = hunter_turn_rate * dt
				var dotv: float = clamp(dir.dot(desired_dir), -1.0, 1.0)
				var ang: float = acos(dotv)
				if ang > 0.0001:
					var t: float = min(1.0, max_ang / ang)
					dir = dir.slerp(desired_dir, t).normalized()

		# Move + hit check (segment)
		var from: Vector3 = pos
		var to: Vector3 = pos + dir * hunter_speed * dt
		var seg: Vector3 = to - from
		var dist: float = seg.length()
		if dist < 0.0001:
			m["pos"] = pos
			m["dir"] = dir
			m["ttl"] = ttl
			missiles[mid] = m
			continue
		var ndir: Vector3 = seg / dist

		var best_dist: float = dist + 0.001
		var best_pos: Vector3 = to
		var hit_any: bool = false

		var phit: Dictionary = _ray_hit_player(from, ndir, dist, sh, hunter_hit_radius)
		if not phit.is_empty():
			best_dist = float(phit["dist"])
			best_pos = Vector3(phit["pos"])
			hit_any = true
		var whit: Dictionary = _ray_hit_world(from, ndir, dist)
		if not whit.is_empty():
			var wdist: float = float(whit.get("dist", dist))
			if wdist < best_dist:
				best_dist = wdist
				best_pos = Vector3(whit.get("pos", best_pos))
				hit_any = true

		if hit_any:
			_do_explosion(sh, best_pos, hunter_radius, hunter_damage)
			to_remove.append(mid)
			continue

		m["pos"] = to
		m["dir"] = dir
		m["ttl"] = ttl
		missiles[mid] = m

	for mid in to_remove:
		missiles.erase(mid)

func _place_mine(user_id: int, pos: Vector3) -> void:
	var mine_pos: Vector3 = pos
	var gy: float = _sample_ground_y(pos)
	if not is_nan(gy):
		mine_pos.y = gy + 1.0
	var p: Dictionary = players[user_id]
	var mid: int = _next_mine_id
	_next_mine_id += 1
	mines[mid] = {
		"pos": mine_pos,
		"ttl": mine_ttl,
		"arm": mine_arm_delay,
		"sh": user_id,
		"team": int(p.get("team", user_id % 2)),
	}
	_events.append({"t": "mine_place", "id": mid, "sh": user_id, "pos": mine_pos})

func _simulate_mines(dt: float) -> void:
	if mines.is_empty():
		return
	var to_remove: Array = []
	for mid in mines.keys():
		var m: Dictionary = mines[mid]
		var ttl: float = float(m.get("ttl", 0.0)) - dt
		if ttl <= 0.0:
			to_remove.append(mid)
			continue
		var arm: float = float(m.get("arm", 0.0))
		arm = max(0.0, arm - dt)
		m["ttl"] = ttl
		m["arm"] = arm
		mines[mid] = m
		if arm > 0.0:
			continue
		var mpos: Vector3 = Vector3(m.get("pos", Vector3.ZERO))
		var team: int = int(m.get("team", 0))
		var sh: int = int(m.get("sh", -1))
		var triggered: bool = false
		for id in players.keys():
			var pid: int = int(id)
			var p: Dictionary = players[pid]
			var pteam: int = int(p.get("team", pid % 2))
			if pteam == team:
				continue
			var ppos: Vector3 = Vector3(p.get("pos", Vector3.ZERO))
			if ppos.distance_to(mpos) <= mine_trigger_radius:
				triggered = true
				break
		if triggered:
			_do_explosion(sh, mpos, mine_radius, mine_damage)
			to_remove.append(mid)

	for mid in to_remove:
		mines.erase(mid)

func _simulate_turrets(dt: float) -> void:
	if buildings.is_empty():
		return
	if turret_fire_rate_hz <= 0.0:
		return
	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		if str(b.get("type", "")) != "turret":
			continue
		var cd: float = float(b.get("cd", 0.0)) - dt
		cd = max(0.0, cd)
		if cd > 0.0:
			b["cd"] = cd
			buildings[bid] = b
			continue
		var team: int = int(b.get("team", 0))
		var bpos: Vector3 = Vector3(b.get("pos", Vector3.ZERO))
		var from: Vector3 = bpos + Vector3(0, turret_muzzle_height, 0)
		var best_id: int = -1
		var best_dist: float = turret_range
		var best_to: Vector3 = from
		for id in players.keys():
			var pid: int = int(id)
			var p: Dictionary = players[pid]
			var pteam: int = int(p.get("team", pid % 2))
			if pteam == team:
				continue
			var ppos: Vector3 = Vector3(p.get("pos", Vector3.ZERO)) + Vector3(0, muzzle_height, 0)
			var d: float = from.distance_to(ppos)
			if d <= 0.001 or d > best_dist:
				continue
			# Simple line-of-sight vs terrain.
			var dir: Vector3 = (ppos - from) / d
			var whit: Dictionary = _ray_hit_world(from, dir, d)
			if not whit.is_empty() and float(whit.get("dist", d)) < d - 0.2:
				continue
			best_dist = d
			best_id = pid
			best_to = ppos

		# Aim smoothing + fire cone.
		var desired_yaw: float = float(b.get("yaw", 0.0))
		var aim_dir: Vector3 = (best_to - from)
		if aim_dir.length() > 0.001:
			desired_yaw = atan2(aim_dir.x, aim_dir.z)
		var cur_yaw: float = float(b.get("yaw", 0.0))
		var max_step: float = deg_to_rad(max(0.0, turret_turn_rate_deg)) * dt
		var diff: float = wrapf(desired_yaw - cur_yaw, -PI, PI)
		diff = clamp(diff, -max_step, max_step)
		cur_yaw = cur_yaw + diff
		b["yaw"] = cur_yaw

		var can_fire: bool = false
		if best_id != -1:
			var cone: float = deg_to_rad(max(0.0, turret_fire_cone_deg))
			var err: float = absf(wrapf(desired_yaw - cur_yaw, -PI, PI))
			can_fire = err <= cone

		if can_fire and best_id != -1 and players.has(best_id):
			var tp: Dictionary = players[best_id]
			var hp: float = float(tp.get("hp", 100.0))
			hp -= turret_damage
			tp["hp"] = hp
			players[best_id] = tp
			if hp <= 0.0:
				_respawn_player(best_id)
			_events.append({
				"t": "shot",
				"sh": -int(bid),
				"from": from,
				"to": best_to,
				"hit": best_id,
				"src": "turret",
				"bid": int(bid),
				"team": team,
			})
			cd = 1.0 / turret_fire_rate_hz
		b["cd"] = cd
		buildings[bid] = b

@rpc("any_peer", "call_remote", "unreliable")
func c_input(cmd: Dictionary) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	p["_last_input"] = cmd
	players[id] = p


@rpc("any_peer", "call_remote", "reliable")
func c_uplink_move_ship(slot: int, sx: int, sy: int) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var team: int = int(p.get("team", id % 2))
	var sd: Dictionary = _ship_for_team_slot(team, slot)
	if sd.is_empty():
		_events.append({"t": "ship_reject", "id": id, "reason": "NO_SHIP", "slot": slot})
		return
	if sx < 0 or sx >= 6 or sy < 0 or sy >= 6:
		_events.append({"t": "ship_reject", "id": id, "reason": "BAD_SECTOR", "slot": slot})
		return
	var counts: Dictionary = _skypump_counts_by_sector(team)
	var key: String = "%d,%d" % [sx, sy]
	if int(counts.get(key, 0)) < 1:
		_events.append({"t": "ship_reject", "id": id, "reason": "UNSTABLE", "slot": slot, "sx": sx, "sy": sy})
		return
	# Apply move
	sd["sx"] = sx
	sd["sy"] = sy
	# Write back
	for i in range(starships.size()):
		var it = starships[i]
		if typeof(it) == TYPE_DICTIONARY and int(it.get("team", -1)) == team and int(it.get("slot", -1)) == slot:
			starships[i] = sd
			break
	_events.append({"t": "ship_move", "team": team, "slot": slot, "sx": sx, "sy": sy})


@rpc("any_peer", "call_remote", "reliable")
func c_uplink_request_ship(slot: int, sx: int, sy: int) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var team: int = int(p.get("team", id % 2))
	if sx < 0 or sx >= 6 or sy < 0 or sy >= 6:
		_events.append({"t": "ship_reject", "id": id, "reason": "BAD_SECTOR", "slot": slot})
		return
	if slot < 0 or slot >= MAX_STARSHIPS_PER_TEAM:
		_events.append({"t": "ship_reject", "id": id, "reason": "BAD_SLOT", "slot": slot})
		return
	# Slot must be empty
	if not _ship_for_team_slot(team, slot).is_empty():
		_events.append({"t": "ship_reject", "id": id, "reason": "SLOT_FULL", "slot": slot})
		return
	var counts: Dictionary = _skypump_counts_by_sector(team)
	var key: String = "%d,%d" % [sx, sy]
	if int(counts.get(key, 0)) < 2:
		_events.append({"t": "ship_reject", "id": id, "reason": "NO_WARP", "slot": slot, "sx": sx, "sy": sy})
		return
	var sid: int = team * 10 + slot
	var ship: Dictionary = {"id": sid, "team": team, "slot": slot, "sx": sx, "sy": sy, "state": "online"}
	starships.append(ship)
	_events.append({"t": "ship_warp", "team": team, "slot": slot, "sx": sx, "sy": sy})

func _sim_tick(dt: float) -> void:
	for id in players.keys():
		var p: Dictionary = players[id]
		var inp: Dictionary = p.get("_last_input", {})

		var mx: float = float(inp.get("mx", 0.0))
		var mz: float = float(inp.get("mz", 0.0))
		var turn: float = float(inp.get("turn", 0.0))
		var alt: float = float(inp.get("alt", 0.0))
		var pitch: float = float(inp.get("pitch", 0.0))
		var firing: bool = bool(inp.get("fire", false))
		var firing2: bool = bool(inp.get("fire2", false))
		var fire_hunter: bool = bool(inp.get("hunter", false))
		var do_flare: bool = bool(inp.get("flare", false))
		var drop_mine: bool = bool(inp.get("mine", false))
		var tgt_id: int = int(inp.get("tgt", -1))
		var spd: int = int(inp.get("spd", int(p.get("spd", 7))))
		spd = clamp(spd, 0, 9)
		var veh_toggle: bool = bool(inp.get("veh_toggle", false))
		var spawn_crate: bool = bool(inp.get("spawn_crate", false))
		var build_pc: bool = bool(inp.get("build_pc", false))
		var build_turret: bool = bool(inp.get("build_turret", false))
		var build_skypump: bool = bool(inp.get("build_skypump", false))
		var do_repair: bool = bool(inp.get("repair", false))
		var repair_bid: int = int(inp.get("repair_bid", -1))
		var veh: String = str(p.get("veh", "tank"))
		var veh_cd: float = float(p.get("veh_cd", 0.0))
		veh_cd = max(0.0, veh_cd - dt)
		if veh_toggle and veh_cd <= 0.0:
			veh_cd = 1.0
			veh = "scout" if veh == "tank" else "tank"
			p["veh"] = veh
			p["hp"] = min(float(p.get("hp", _veh_max_hp(veh))), _veh_max_hp(veh))
			p["charge"] = 0.0
		p["veh_cd"] = veh_cd

		var fuel: float = float(p.get("fuel", fuel_max))
		if spd > 7:
			fuel -= float(spd - 7) * fuel_drain_per_step * dt
		elif spd < 7:
			fuel += float(7 - spd) * fuel_regen_per_step * dt
		fuel = clamp(fuel, 0.0, fuel_max)
		# Friendly powercell bonus (prototype): inside radius we regen fuel and HP.
		var team_i: int = int(p.get("team", int(id) % 2))
		if _in_friendly_power(team_i, p.get("pos", Vector3.ZERO)):
			fuel = clamp(fuel + powercell_fuel_regen_bonus * dt, 0.0, fuel_max)
			var cur_veh: String = str(p.get("veh", "tank"))
			var hp_max: float = scout_max_hp if cur_veh == "scout" else tank_max_hp
			p["hp"] = clamp(float(p.get("hp", hp_max)) + powercell_hp_regen_bonus * dt, 0.0, hp_max)
			if cur_veh == "scout":
				p["charge"] = clamp(float(p.get("charge", 0.0)) + powercell_charge_regen_bonus * dt, 0.0, beam_charge_max)
		if fuel <= 0.0 and spd > 7:
			spd = 7
		p["fuel"] = fuel
		p["spd"] = spd

		# Yaw integration (client sends rad/s)
		var yaw: float = float(p["yaw"]) + turn * dt
		p["yaw"] = yaw
		p["pitch"] = pitch

		# Desired movement vector in XZ plane.
		var forward := Vector3(sin(yaw), 0.0, cos(yaw))
		var right := Vector3(-forward.z, 0.0, forward.x)  # fixed: ensure A=left, D=right
		var wish := (right * mx + forward * mz)
		if wish.length() > 1.0:
			wish = wish.normalized()

		var pos_before: Vector3 = Vector3(p["pos"])
		var pos: Vector3 = pos_before
		var vel: Vector3 = Vector3(p.get("vel", Vector3.ZERO))

		# Horizontal acceleration + friction.
		var hv := Vector3(vel.x, 0.0, vel.z)
		var base_max: float = scout_max_speed if veh == "scout" else max_speed
		var base_accel: float = scout_accel if veh == "scout" else accel
		var base_fric: float = scout_friction if veh == "scout" else friction
		var eff_mul: float = 1.0
		if spd <= 7:
			eff_mul = float(spd) / 7.0
		else:
			eff_mul = 1.0 + overdrive_speed_bonus * float(spd - 7)
		var desired_vel: Vector3 = wish * (base_max * eff_mul)
		hv = hv.move_toward(desired_vel, base_accel * eff_mul * dt)
		if wish.length() < 0.01:
			hv = hv.move_toward(Vector3.ZERO, base_fric * dt)

		pos.x += hv.x * dt
		pos.z += hv.z * dt

		# Hover height adjust (Q/Z input nudges target hover height).
		var hover_h: float = float(p.get("hover", hover_default))
		hover_h = clamp(hover_h + alt * hover_adjust_speed * dt, hover_min, hover_max)
		p["hover"] = hover_h

		# Spring toward ground + hover_h.
		var ground_y: float = _sample_ground_y(pos)
		if not is_nan(ground_y):
			var target_y: float = ground_y + hover_h
			var vy: float = vel.y
			var err: float = target_y - pos.y
			var ay: float = err * hover_k - vy * hover_d
			vy += ay * dt
			pos.y += vy * dt
			vel.y = vy

			# Safety clamp: never let the vehicle sink below the ground due to spring overshoot.
			var min_y: float = ground_y + max(0.25, hover_h * 0.20)
			if pos.y < min_y:
				pos.y = min_y
				vel.y = 0.0

		vel.x = hv.x
		vel.z = hv.z
		p["pos"] = pos
		p["vel"] = vel

		# --- Cargo / Building inputs (one-shot) ---
		if spawn_crate:
			_spawn_crate(pos + forward * cargo_drop_distance)
		if build_pc:
			var cargo_i: int = int(p.get("cargo", 0))
			if cargo_i >= powercell_build_cost:
				var team_b: int = int(p.get("team", int(id) % 2))
				var desired: Vector3 = pos + forward * build_distance
				var vr: Dictionary = _validate_build("powercell", desired)
				if bool(vr.get("ok", false)):
					var bid: int = _spawn_powercell(team_b, Vector3(vr.get("pos", desired)), int(id))
					p["cargo"] = cargo_i - powercell_build_cost
					_events.append({"t": "cargo_spend", "id": id, "cargo": int(p.get("cargo", 0)), "kind": "powercell", "bid": bid})
				else:
					_events.append({"t": "build_reject", "id": id, "kind": "powercell", "reason": str(vr.get("reason", "BLOCKED")), "slope": float(vr.get("slope_deg", 0.0))})
			else:
				_events.append({"t": "build_reject", "id": id, "kind": "powercell", "reason": "NO_CARGO", "slope": 0.0})

		if build_turret:
			var cargo_t: int = int(p.get("cargo", 0))
			if cargo_t >= turret_build_cost:
				var team_t: int = int(p.get("team", int(id) % 2))
				var desired_t: Vector3 = pos + forward * build_distance
				var vr_t: Dictionary = _validate_build("turret", desired_t)
				if bool(vr_t.get("ok", false)):
					var bid_t: int = _spawn_turret(team_t, Vector3(vr_t.get("pos", desired_t)), int(id))
					p["cargo"] = cargo_t - turret_build_cost
					_events.append({"t": "cargo_spend", "id": id, "cargo": int(p.get("cargo", 0)), "kind": "turret", "bid": bid_t})
				else:
					_events.append({"t": "build_reject", "id": id, "kind": "turret", "reason": str(vr_t.get("reason", "BLOCKED")), "slope": float(vr_t.get("slope_deg", 0.0))})
			else:
				_events.append({"t": "build_reject", "id": id, "kind": "turret", "reason": "NO_CARGO", "slope": 0.0})

		if build_skypump:
			var cargo_s: int = int(p.get("cargo", 0))
			if cargo_s >= skypump_build_cost:
				var team_s: int = int(p.get("team", int(id) % 2))
				var desired_s: Vector3 = pos + forward * build_distance
				var vr_s: Dictionary = _validate_build("skypump", desired_s)
				if bool(vr_s.get("ok", false)):
					var bid_s: int = _spawn_skypump(team_s, Vector3(vr_s.get("pos", desired_s)), int(id))
					p["cargo"] = cargo_s - skypump_build_cost
					_events.append({"t": "cargo_spend", "id": id, "cargo": int(p.get("cargo", 0)), "kind": "skypump", "bid": bid_s})
				else:
					_events.append({"t": "build_reject", "id": id, "kind": "skypump", "reason": str(vr_s.get("reason", "BLOCKED")), "slope": float(vr_s.get("slope_deg", 0.0))})
			else:
				_events.append({"t": "build_reject", "id": id, "kind": "skypump", "reason": "NO_CARGO", "slope": 0.0})


		# --- Repair building (uses cargo; server authoritative) ---
		if do_repair:
			_try_repair_building(id, p, repair_bid, pos)

		# --- Cargo pickup (robust, segment-based) ---
		_try_pickup_cargo(id, p, pos_before, pos)

		# Timers (flare + cooldowns)
		var flare_t: float = float(p.get("flare_t", 0.0))
		flare_t = max(0.0, flare_t - dt)
		p["flare_t"] = flare_t

		# --- Autocannon firing ---
		# Pull local fuel so weapon costs apply this tick (the speed loop already updated fuel earlier).
		fuel = float(p.get("fuel", fuel_max))
		var fire_cd: float = float(p.get("fire_cd", 0.0))
		fire_cd = max(0.0, fire_cd - dt)

		if firing and fire_cd <= 0.0 and auto_rate_hz > 0.0 and fuel >= fuel_cost_autocannon_shot:
			fuel -= fuel_cost_autocannon_shot
			fire_cd = 1.0 / auto_rate_hz
			_do_autocannon_shot(id, pos, yaw, pitch)

		p["fire_cd"] = fire_cd
		p["fuel"] = fuel

		# --- RMB: tank pulse OR scout repair beam ---
		if veh == "tank":
			var pulse_cd: float = float(p.get("pulse_cd", 0.0))
			pulse_cd = max(0.0, pulse_cd - dt)
			if firing2 and pulse_cd <= 0.0 and fuel >= fuel_cost_pulse:
				fuel -= fuel_cost_pulse
				pulse_cd = pulse_cooldown
				_do_pulse_fire(id, pos, yaw, pitch)
			p["pulse_cd"] = pulse_cd
			p["fuel"] = fuel
		else:
			if firing2 and fuel >= beam_fuel_cost_per_s * dt:
				fuel -= beam_fuel_cost_per_s * dt
				_do_scout_beam(id, pos, yaw, pitch, dt)
			p["fuel"] = fuel
		# --- Flare (countermeasure) ---
		var flare_cd: float = float(p.get("flare_cd", 0.0))
		flare_cd = max(0.0, flare_cd - dt)
		if do_flare and flare_cd <= 0.0 and float(p.get("fuel", fuel_max)) >= fuel_cost_flare:
			p["fuel"] = float(p.get("fuel", fuel_max)) - fuel_cost_flare
			flare_cd = flare_cooldown
			_do_flare(id)
		p["flare_cd"] = flare_cd

		# --- Hunter missile (guided) ---
		var hunter_cd: float = float(p.get("hunter_cd", 0.0))
		hunter_cd = max(0.0, hunter_cd - dt)
		var valid_target: bool = (tgt_id >= 0 and tgt_id != id and players.has(tgt_id))
		if fire_hunter and hunter_cd <= 0.0 and valid_target and float(p.get("fuel", fuel_max)) >= fuel_cost_hunter:
			p["fuel"] = float(p.get("fuel", fuel_max)) - fuel_cost_hunter
			hunter_cd = hunter_cooldown
			_do_hunter_fire(id, pos, yaw, pitch, tgt_id)
		p["hunter_cd"] = hunter_cd

		# --- Mine deploy ---
		var mine_cd: float = float(p.get("mine_cd", 0.0))
		mine_cd = max(0.0, mine_cd - dt)
		if drop_mine and mine_cd <= 0.0 and float(p.get("fuel", fuel_max)) >= fuel_cost_mine:
			p["fuel"] = float(p.get("fuel", fuel_max)) - fuel_cost_mine
			mine_cd = mine_cooldown
			_place_mine(id, pos)
		p["mine_cd"] = mine_cd

		players[id] = p

	# Simulate non-player entities after players update.
	_simulate_projectiles(dt)
	_simulate_missiles(dt)
	_simulate_mines(dt)
	_simulate_turrets(dt)

	# Cleanup crates TTL
	var dead_crates: Array = []
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		c["ttl"] = float(c.get("ttl", crate_ttl)) - dt
		crates[cid] = c
		if float(c.get("ttl", 0.0)) <= 0.0:
			dead_crates.append(cid)
	for cid in dead_crates:
		crates.erase(cid)


func _do_autocannon_shot(shooter_id: int, shooter_pos: Vector3, yaw: float, pitch: float) -> void:
	var from: Vector3 = shooter_pos + Vector3(0, muzzle_height, 0)
	var dir: Vector3 = _aim_dir(yaw, pitch).normalized()

	var best_dist: float = auto_range
	var best_pos: Vector3 = from + dir * auto_range
	var hit_id: int = -1  # peer id, or -(HIT_BUILDING_OFFSET+bid)

	# 1) Hit players
	var phit: Dictionary = _ray_hit_player(from, dir, auto_range, shooter_id, auto_hit_radius)
	if not phit.is_empty():
		best_dist = float(phit["dist"])
		best_pos = Vector3(phit["pos"])
		hit_id = int(phit["id"])

	# 2) Hit buildings (closer than player hit)
	var bhit: Dictionary = _ray_hit_building(from, dir, auto_range, shooter_id)
	if not bhit.is_empty():
		var bdist: float = float(bhit["dist"])
		if bdist < best_dist:
			best_dist = bdist
			best_pos = Vector3(bhit["pos"])
			var bid: int = int(bhit["id"])
			hit_id = -(HIT_BUILDING_OFFSET + bid)

	# 3) Hit world (closest wins)
	var whit: Dictionary = _ray_hit_world(from, dir, auto_range)
	if not whit.is_empty():
		var wdist: float = float(whit["dist"])
		if wdist < best_dist:
			best_dist = wdist
			best_pos = Vector3(whit["pos"])
			hit_id = -1

	# Apply damage.
	if hit_id > 0 and players.has(hit_id):
		var tp: Dictionary = players[hit_id]
		var hp: float = float(tp.get("hp", 100.0)) - auto_damage
		tp["hp"] = hp
		players[hit_id] = tp
		if hp <= 0.0:
			_respawn_player(hit_id)
	elif hit_id < -1:
		var bid2: int = -hit_id - HIT_BUILDING_OFFSET
		_damage_building(bid2, shooter_id, auto_damage * building_damage_mult_autocannon)

	_events.append({
		"t": "shot",
		"sh": shooter_id,
		"from": from,
		"to": best_pos,
		"hit": hit_id,
	})


func _veh_max_hp(veh: String) -> float:
	if veh == "scout":
		return scout_max_hp
	return tank_max_hp

func _respawn_player(id: int) -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var veh: String = str(p.get("veh", "tank"))
	p["hp"] = _veh_max_hp(veh)
	p["fuel"] = fuel_max
	p["charge"] = 0.0
	p["vel"] = Vector3.ZERO
	var team_id: int = int(p.get("team", int(id) % 2))
	p["pos"] = _pick_spawn_pos_team(team_id, 120.0)
	players[id] = p
	_events.append({"t": "respawn", "id": id})

func _pick_spawn_pos(spread: float) -> Vector3:
	var pos := Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
	var gy: float = _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + hover_default + 4.0
	else:
		pos.y = 40.0
	return pos

func _team_anchor_world(team: int) -> Vector3:
	# Prefer the team's actual uplink position if present; otherwise fall back to the
	# classic corner sectors (Blue=A1, Red=F6) as a reasonable approximation.
	var up: Dictionary = _find_uplink_pos(team)
	if bool(up.get("ok", false)):
		return Vector3(up.get("pos", Vector3.ZERO))
	if team == 1:
		return _world_center_for_sector(0, 0)
	return _world_center_for_sector(5, 5)

func _pick_spawn_pos_team(team: int, spread: float) -> Vector3:
	var base: Vector3 = _team_anchor_world(team)
	var pos := base + Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
	var gy: float = _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + hover_default + 4.0
	else:
		pos.y = 40.0
	return pos

func _aim_dir(yaw: float, pitch: float) -> Vector3:
	var cp: float = cos(pitch)
	var sp: float = sin(pitch)
	var d := Vector3(sin(yaw) * cp, sp, cos(yaw) * cp)
	return d.normalized()

func _ray_hit_player(from: Vector3, dir: Vector3, max_dist: float, shooter_id: int, radius: float) -> Dictionary:
	# Returns {"id": int, "dist": float, "pos": Vector3} or {}.
	var best_t: float = max_dist + 1.0
	var best_id: int = -1
	var best_pos: Vector3 = Vector3.ZERO

	for id in players.keys():
		if int(id) == shooter_id:
			continue
		var p: Dictionary = players[id]
		var c: Vector3 = Vector3(p.get("pos", Vector3.ZERO)) + Vector3(0, muzzle_height * 0.5, 0)

		# Ray-sphere intersection (dir assumed normalized)
		var oc: Vector3 = from - c
		var b: float = 2.0 * oc.dot(dir)
		var cterm: float = oc.dot(oc) - radius * radius
		var disc: float = b * b - 4.0 * cterm
		if disc < 0.0:
			continue
		var sqrt_disc: float = sqrt(disc)
		var t0: float = (-b - sqrt_disc) * 0.5
		var t1: float = (-b + sqrt_disc) * 0.5
		var t: float = t0
		if t < 0.0:
			t = t1
		if t < 0.0:
			continue
		if t <= max_dist and t < best_t:
			best_t = t
			best_id = int(id)
			best_pos = from + dir * t

	if best_id == -1:
		return {}
	return {"id": best_id, "dist": best_t, "pos": best_pos}



func _building_hit_center(b: Dictionary) -> Vector3:
	var p: Vector3 = Vector3(b.get("pos", Vector3.ZERO))	
	var t: String = str(b.get("type", ""))
	# Rough center offsets for our simple meshes.
	if t == "turret":
		return p + Vector3(0, 1.1, 0)
	return p + Vector3(0, 0.9, 0)

func _ray_hit_building(from: Vector3, dir: Vector3, max_dist: float, shooter_id: int, allow_friendly: bool = false) -> Dictionary:
	# Returns {"bid": int, "dist": float, "pos": Vector3} or {}.
	if buildings.is_empty():
		return {}
	var shooter_team: int = -1
	if shooter_id >= 0 and players.has(shooter_id):
		shooter_team = int(players[shooter_id].get("team", shooter_id % 2))
	var best_t: float = max_dist + 1.0
	var best_id: int = -1
	var best_pos: Vector3 = Vector3.ZERO

	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		var bteam: int = int(b.get("team", 0))
		if (not allow_friendly) and shooter_team != -1 and bteam == shooter_team:
			continue
		var c: Vector3 = _building_hit_center(b)
		var r: float = float(b.get("hit_r", 4.0))
		# Ray-sphere intersection
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
			best_id = int(bid)
			best_pos = from + dir * t

	if best_id == -1:
		return {}
	return {"id": best_id, "dist": best_t, "pos": best_pos}

func _try_repair_building(pid: int, p: Dictionary, bid: int, at_pos: Vector3) -> void:
	if bid < 0 or not buildings.has(bid):
		_events.append({"t": "repair_reject", "id": pid, "reason": "NO_TARGET"})
		return
	var b: Dictionary = buildings[bid]
	var team_p: int = int(p.get("team", pid % 2))
	var team_b: int = int(b.get("team", 0))
	if team_b != team_p:
		_events.append({"t": "repair_reject", "id": pid, "reason": "ENEMY"})
		return
	var bpos: Vector3 = Vector3(b.get("pos", Vector3.ZERO))
	if at_pos.distance_to(bpos) > repair_range:
		_events.append({"t": "repair_reject", "id": pid, "reason": "TOO_FAR"})
		return
	var cargo_i: int = int(p.get("cargo", 0))
	if cargo_i <= 0:
		_events.append({"t": "repair_reject", "id": pid, "reason": "NO_CARGO"})
		return
	var hp: float = float(b.get("hp", 0.0))
	var hpmax: float = float(b.get("hpmax", hp))
	if hpmax <= 0.001 or hp >= hpmax - 0.01:
		_events.append({"t": "repair_reject", "id": pid, "reason": "FULL"})
		return
	var bt: String = str(b.get("type", ""))
	var amt: float = 50.0
	if bt == "powercell":
		amt = repair_amount_powercell
	elif bt == "turret":
		amt = repair_amount_turret
	b["hp"] = min(hpmax, hp + amt)
	buildings[bid] = b
	p["cargo"] = cargo_i - repair_cost
	_events.append({"t": "cargo_spend", "id": pid, "cargo": int(p.get("cargo", 0)), "kind": "repair", "bid": bid})
	_events.append({"t": "b_repair", "id": pid, "bid": bid, "type": bt, "hp": float(b.get("hp", 0.0)), "hpmax": hpmax})

func _damage_building(bid: int, attacker_id: int, dmg: float, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if dmg <= 0.0:
		return
	if not buildings.has(bid):
		return
	var b: Dictionary = buildings[bid]
	var hp: float = float(b.get("hp", 0.0)) - dmg
	b["hp"] = hp
	buildings[bid] = b
	if hp <= 0.0:
		_destroy_building(bid, attacker_id, hit_pos)

func _destroy_building(bid: int, attacker_id: int, at_pos: Vector3 = Vector3.ZERO) -> void:
	if not buildings.has(bid):
		return
	var b: Dictionary = buildings[bid]
	var btype: String = str(b.get("type", ""))
	var team: int = int(b.get("team", 0))
	var pos: Vector3 = Vector3(b.get("pos", at_pos))
	buildings.erase(bid)

	# Visual + feedback
	_events.append({"t": "b_destroy", "id": bid, "type": btype, "team": team, "pos": pos, "sh": attacker_id})
	_events.append({"t": "explosion", "sh": attacker_id, "pos": pos, "r": 10.0, "hits": []})

	# Salvage crates (reward to keep the economy loop alive)
	var n: int = 0
	if btype == "powercell":
		n = powercell_drop_crates
	elif btype == "turret":
		n = turret_drop_crates
	elif btype == "skypump":
		n = 0
	else:
		n = 1
	for i in range(n):
		var off := Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0))
		_spawn_crate(pos + off)
func _ray_hit_world(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	# Returns {"dist": float, "pos": Vector3} or {}.
	var w: World3D = get_world_3d()
	if w == null:
		return {}
	var space: PhysicsDirectSpaceState3D = w.direct_space_state
	var to: Vector3 = from + dir * max_dist
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.hit_from_inside = true
	q.hit_back_faces = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var p: Vector3 = Vector3(hit["position"])
	return {"dist": (p - from).length(), "pos": p}

func _load_map() -> void:
	if map_scene_path == "" or not ResourceLoader.exists(map_scene_path):
		push_warning("Server map scene not found: %s" % map_scene_path)
		return
	var ps: PackedScene = load(map_scene_path)
	var map_instance := ps.instantiate()
	world_root.add_child(map_instance)
	_fix_terrain_collision(map_instance)
	_seed_initial_cargo()
	_seed_initial_uplinks()


func _fix_terrain_collision(map_root: Node) -> void:
	# Fix mismatch between visual mesh spacing and HeightMapShape3D collision spacing.
	# Older imported maps were authored with unit spacing; we correct it at runtime using MapMeta.
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
	_map_world_w = world_w
	_map_world_d = world_d
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
	var max_abs: float = 0.0
	for v in data:
		max_abs = maxf(max_abs, absf(v))
	if absf(current_scale - target_spacing) <= 0.001 and max_abs > 50.0 and target_spacing > 5.0:
		# Heights are still in world units on a scaled body. Normalize them.
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
	# Cache bounds for robust ground raycasts.
	var min_y: float = 1.0e20
	var max_y: float = -1.0e20
	var sy: float = body.scale.y
	var data2: PackedFloat32Array = hm.map_data
	for v2 in data2:
		var y: float = v2 * sy
		if y < min_y:
			min_y = y
		if y > max_y:
			max_y = y
	_terrain_min_y = min_y
	_terrain_max_y = max_y
	_terrain_has_bounds = true
func _sample_ground_y(at_pos: Vector3) -> float:
	# Returns ground Y at the given XZ, or NAN if nothing hit.
	var w: World3D = get_world_3d()
	if w == null:
		return NAN
	var space: PhysicsDirectSpaceState3D = w.direct_space_state
	var from_y: float = at_pos.y + 500.0
	var to_y: float = at_pos.y - 2000.0
	if _terrain_has_bounds:
		from_y = maxf(from_y, _terrain_max_y + 2000.0)
		to_y = minf(to_y, _terrain_min_y - 4000.0)
	else:
		from_y = maxf(from_y, 8000.0)
		to_y = minf(to_y, -8000.0)
	var from: Vector3 = Vector3(at_pos.x, from_y, at_pos.z)
	var to: Vector3 = Vector3(at_pos.x, to_y, at_pos.z)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.hit_from_inside = true
	q.hit_back_faces = true
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	var hit_pos: Vector3 = Vector3(hit["position"])
	return hit_pos.y


func _seed_initial_cargo() -> void:
	# Seed a few crates so the pickup loop can be tested immediately.
	# These are server-authoritative entities replicated via snapshots.
	if initial_cargo_crates <= 0:
		return
	if crates.size() > 0:
		return
	for i in range(initial_cargo_crates):
		var p: Vector3 = Vector3(
			_rng.randf_range(-initial_cargo_spread, initial_cargo_spread),
			0.0,
			_rng.randf_range(-initial_cargo_spread, initial_cargo_spread)
		)
		_spawn_crate(p)


func _world_center_for_sector(sx: int, sy: int) -> Vector3:
	# Sector grid is 6x6. Convert a sector index (0..5) to the sector center in world XZ.
	sx = clamp(sx, 0, 5)
	sy = clamp(sy, 0, 5)
	if _map_world_w > 0.0 and _map_world_d > 0.0:
		var x0: float = -_map_world_w * 0.5
		var z0: float = -_map_world_d * 0.5
		var u: float = (float(sx) + 0.5) / 6.0
		var v: float = (float(sy) + 0.5) / 6.0
		return Vector3(x0 + u * _map_world_w, 0.0, z0 + v * _map_world_d)
	# Fallback: legacy 1024-ish world.
	return Vector3(-512.0 + (float(sx) + 0.5) * (1024.0 / 6.0), 0.0, -512.0 + (float(sy) + 0.5) * (1024.0 / 6.0))


func _find_uplink_pos(team: int) -> Dictionary:
	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		if int(b.get("team", -1)) != team:
			continue
		var typ: String = str(b.get("type", "")).to_lower()
		if typ.find("uplink") == -1:
			continue
		return {"ok": true, "pos": Vector3(b.get("pos", Vector3.ZERO))}
	return {"ok": false}


func _seed_initial_uplinks() -> void:
	# Spawn a visible Uplink for each team so the strategic layer has a real anchor
	# (and to remove the prior DEV override).
	if _seeded_uplinks:
		return
	var blue_has: bool = bool(_find_uplink_pos(1).get("ok", false))
	var red_has: bool = bool(_find_uplink_pos(0).get("ok", false))
	if blue_has and red_has:
		_seeded_uplinks = true
		return
	if not blue_has:
		_spawn_uplink(1, _world_center_for_sector(0, 0), -1) # A1
	if not red_has:
		_spawn_uplink(0, _world_center_for_sector(5, 5), -1) # F6
	_seeded_uplinks = true



func _sector_xy_for_world(pos: Vector3) -> Vector2i:
	if _map_world_w <= 0.0 or _map_world_d <= 0.0:
		return Vector2i(0, 0)
	var x0: float = -_map_world_w * 0.5
	var z0: float = -_map_world_d * 0.5
	var u: float = clamp((pos.x - x0) / _map_world_w, 0.0, 0.9999)
	var v: float = clamp((pos.z - z0) / _map_world_d, 0.0, 0.9999)
	return Vector2i(int(floor(u * 6.0)), int(floor(v * 6.0)))

func _skypump_counts_by_sector(team: int) -> Dictionary:
	var out: Dictionary = {}
	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		if int(b.get("team", -1)) != team:
			continue
		var typ: String = str(b.get("type", "")).to_lower()
		if typ.find("skypump") == -1:
			continue
		var xy: Vector2i = _sector_xy_for_world(Vector3(b.get("pos", Vector3.ZERO)))
		var k: String = "%d,%d" % [xy.x, xy.y]
		out[k] = int(out.get(k, 0)) + 1
	return out

func _has_stabilized_sector(team: int, min_pumps: int) -> bool:
	var d: Dictionary = _skypump_counts_by_sector(team)
	for k in d.keys():
		if int(d.get(k, 0)) >= min_pumps:
			return true
	return false

func _ship_for_team_slot(team: int, slot: int) -> Dictionary:
	for s in starships:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		if int(sd.get("team", -1)) == team and int(sd.get("slot", -1)) == slot:
			return sd
	return {}

func _init_starships() -> void:
	# In classic Wulfram, these are controlled by the Uplink (the Linker), and skypumps
	# enable moving the ship / bringing in another one. We start each team with one ship
	# so the strategic UI can show orbit sectors immediately.
	if starships.size() > 0:
		return
	# Default starting orbit sectors are anchored to the team's Uplink sector.
	# If the uplink doesn't exist yet (dev/test), fall back to A1 (Blue) / F6 (Red).
	var blue_xy: Vector2i = Vector2i(0, 0)
	var red_xy: Vector2i = Vector2i(5, 5)
	var bpos: Dictionary = _find_uplink_pos(1)
	if bool(bpos.get("ok", false)):
		blue_xy = _sector_xy_for_world(Vector3(bpos.get("pos", Vector3.ZERO)))
	var rpos: Dictionary = _find_uplink_pos(0)
	if bool(rpos.get("ok", false)):
		red_xy = _sector_xy_for_world(Vector3(rpos.get("pos", Vector3.ZERO)))
	starships = [
		{"id": 0, "team": 1, "slot": 0, "sx": blue_xy.x, "sy": blue_xy.y, "state": "online"},
		{"id": 1, "team": 0, "slot": 0, "sx": red_xy.x, "sy": red_xy.y, "state": "online"},
	]


func _dist_sq_point_to_seg(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var ap: Vector2 = p - a
	var ab_len_sq: float = ab.length_squared()
	var t: float = 0.0
	if ab_len_sq > 0.000001:
		t = clamp(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var c: Vector2 = a + ab * t
	return (p - c).length_squared()


func _try_pickup_cargo(pid: int, p: Dictionary, from_pos: Vector3, to_pos: Vector3) -> void:
	var cur: int = int(p.get("cargo", 0))
	if cur >= cargo_max:
		return
	if crates.is_empty():
		return
	var a: Vector2 = Vector2(from_pos.x, from_pos.z)
	var b: Vector2 = Vector2(to_pos.x, to_pos.z)
	var r: float = cargo_pickup_radius
	var best_cid: int = -1
	var best_d2: float = r * r
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		var cp: Vector3 = c.get("pos", Vector3.ZERO)
		var d2: float = _dist_sq_point_to_seg(a, b, Vector2(cp.x, cp.z))
		if d2 <= best_d2:
			best_d2 = d2
			best_cid = int(cid)
	if best_cid == -1:
		return

	crates.erase(best_cid)
	var new_cargo: int = min(cargo_max, cur + 1)
	p["cargo"] = new_cargo
	_events.append({"t": "cargo_pick", "id": pid, "cargo": new_cargo, "cid": best_cid})

func _spawn_crate(at_pos: Vector3) -> int:
	var pos := at_pos
	var gy := _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + 1.0
	var cid := _next_crate_id
	_next_crate_id += 1
	crates[cid] = {"id": cid, "pos": pos, "ttl": crate_ttl}
	return int(cid)


func _validate_build(kind: String, desired_pos: Vector3) -> Dictionary:
	# Returns { "ok": bool, "pos": Vector3, "reason": String, "slope_deg": float }
	var out: Dictionary = {"ok": false, "pos": desired_pos, "reason": "UNKNOWN", "slope_deg": 0.0}
	var pos: Vector3 = desired_pos

	# Snap to ground
	var gy: float = _sample_ground_y(pos)
	if is_nan(gy):
		out["reason"] = "NO_GROUND"
		return out
	pos.y = gy + 0.1

	# Slope estimate via finite differences on the heightfield.
	var e: float = max(0.5, build_sample_spacing)
	var hx1: float = _sample_ground_y(pos + Vector3(e, 0, 0))
	var hx0: float = _sample_ground_y(pos + Vector3(-e, 0, 0))
	var hz1: float = _sample_ground_y(pos + Vector3(0, 0, e))
	var hz0: float = _sample_ground_y(pos + Vector3(0, 0, -e))
	if is_nan(hx1) or is_nan(hx0) or is_nan(hz1) or is_nan(hz0):
		out["reason"] = "NO_GROUND"
		return out
	var gx: float = (hx1 - hx0) / (2.0 * e)
	var gz: float = (hz1 - hz0) / (2.0 * e)
	var grad: float = sqrt(gx * gx + gz * gz)
	var slope_deg: float = rad_to_deg(atan(grad))
	out["slope_deg"] = slope_deg
	if slope_deg > build_max_slope_deg:
		out["reason"] = "SLOPE"
		out["pos"] = pos
		return out

	# Overlap check against existing buildings (XZ distance)
	var my_r: float = 3.0
	if kind == "turret":
		my_r = turret_hit_radius
	elif kind == "powercell":
		my_r = powercell_hit_radius
	elif kind == "skypump":
		my_r = skypump_hit_radius
	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		var bp: Vector3 = b.get("pos", Vector3.ZERO)
		var br: float = float(b.get("hit_r", 3.0))
		var dx: float = bp.x - pos.x
		var dz: float = bp.z - pos.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d < (build_min_spacing + my_r + br):
			out["reason"] = "OVERLAP"
			out["pos"] = pos
			return out

	out["ok"] = true
	out["reason"] = "OK"
	out["pos"] = pos
	return out


func _spawn_powercell(team: int, at_pos: Vector3, owner: int = -1) -> int:
	var pos := at_pos
	var gy := _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + 0.1
	var bid := _next_building_id
	_next_building_id += 1
	buildings[bid] = {
		"id": bid,
		"type": "powercell",
		"pos": pos,
		"team": team,
		"owner": owner,
		"hp": powercell_max_hp,
		"hpmax": powercell_max_hp,
		"hit_r": powercell_hit_radius,
		"radius": powercell_radius,
	}
	return int(bid)

func _spawn_turret(team: int, at_pos: Vector3, owner: int = -1) -> int:
	var pos := at_pos
	var gy := _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + 0.1
	var bid := _next_building_id
	_next_building_id += 1
	buildings[bid] = {
		"id": bid,
		"type": "turret",
		"pos": pos,
		"team": team,
		"owner": owner,
		"yaw": 0.0,
		"hp": turret_max_hp,
		"hpmax": turret_max_hp,
		"hit_r": turret_hit_radius,
		"radius": turret_range,
		"cd": 0.0,
	}
	return int(bid)

func _spawn_skypump(team: int, at_pos: Vector3, owner: int = -1) -> int:
	var pos := at_pos
	var gy := _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + 0.1
	var bid := _next_building_id
	_next_building_id += 1
	buildings[bid] = {
		"id": bid,
		"type": "skypump",
		"pos": pos,
		"team": team,
		"owner": owner,
		"hp": skypump_max_hp,
		"hpmax": skypump_max_hp,
		"hit_r": skypump_hit_radius,
		"radius": 0.0,
	}
	return int(bid)

func _spawn_uplink(team: int, at_pos: Vector3, owner: int = -1) -> int:
	var pos := at_pos
	var gy := _sample_ground_y(pos)
	if not is_nan(gy):
		pos.y = gy + 0.1
	var bid := _next_building_id
	_next_building_id += 1
	buildings[bid] = {
		"id": bid,
		"type": "uplink",
		"pos": pos,
		"team": team,
		"owner": owner,
		"hp": uplink_max_hp,
		"hpmax": uplink_max_hp,
		"hit_r": uplink_hit_radius,
		"radius": 0.0,
	}
	return int(bid)

func _in_friendly_power(team: int, at_pos: Vector3) -> bool:
	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		if int(b.get("team", -1)) != team:
			continue
		if str(b.get("type", "")) != "powercell":
			continue
		var bp: Vector3 = b.get("pos", Vector3.ZERO)
		var r: float = float(b.get("radius", powercell_radius))
		if at_pos.distance_to(bp) <= r:
			return true
	return false


func _send_snapshot_and_events() -> void:
	var snap: Dictionary = {}
	for id in players.keys():
		var p: Dictionary = players[id]
		snap[str(id)] = {
			"pos": p["pos"],
			"yaw": p["yaw"],
			"team": p.get("team", int(id) % 2),
			"hp": p.get("hp", tank_max_hp),
			"veh": p.get("veh", "tank"),
			"spd": p.get("spd", 7),
			"fuel": p.get("fuel", fuel_max),
			"cargo": p.get("cargo", 0),
			"charge": p.get("charge", 0.0),
			# Weapon cooldowns (for Wulfram-style HUD widgets).
			"cd_fire": float(p.get("fire_cd", 0.0)),
			"cd_pulse": float(p.get("pulse_cd", 0.0)),
			"cd_hunter": float(p.get("hunter_cd", 0.0)),
			"cd_flare": float(p.get("flare_cd", 0.0)),
			"cd_mine": float(p.get("mine_cd", 0.0)),
		}

	# Projectiles
	var parr: Array = []
	for pid in projectiles.keys():
		var pr: Dictionary = projectiles[pid]
		parr.append({"id": int(pid), "pos": pr.get("pos", Vector3.ZERO)})
	snap["_proj"] = parr

	# Missiles
	var marr: Array = []
	for mid in missiles.keys():
		var m: Dictionary = missiles[mid]
		marr.append({"id": int(mid), "pos": m.get("pos", Vector3.ZERO)})
	snap["_mis"] = marr

	# Mines
	var minarr: Array = []
	for mine_id in mines.keys():
		var mn: Dictionary = mines[mine_id]
		minarr.append({"id": int(mine_id), "pos": mn.get("pos", Vector3.ZERO)})
	snap["_mines"] = minarr

	# Cargo crates
	var carr: Array = []
	for cid in crates.keys():
		var c: Dictionary = crates[cid]
		carr.append({"id": int(cid), "pos": c.get("pos", Vector3.ZERO)})
	snap["_crates"] = carr

	# Buildings
	var barr: Array = []
	for bid in buildings.keys():
		var b: Dictionary = buildings[bid]
		barr.append({
			"id": int(bid),
			"type": str(b.get("type", "")),
			"pos": b.get("pos", Vector3.ZERO),
			"team": int(b.get("team", 0)),
			"owner": int(b.get("owner", -1)),
			"yaw": float(b.get("yaw", 0.0)),
			"hp": float(b.get("hp", 0.0)),
			"hpmax": float(b.get("hpmax", float(b.get("hp", 0.0)))),
			"hit_r": float(b.get("hit_r", 3.0)),
			"radius": float(b.get("radius", 0.0)),
		})
	snap["_bld"] = barr

	# Starships (strategic/Uplink). Orbit sector is determined by ship's (sx,sy).
	var sharr: Array = []
	for s in starships:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		sharr.append({
			"id": int(sd.get("id", 0)),
			"team": int(sd.get("team", 0)),
			"slot": int(sd.get("slot", 0)),
			"sx": int(sd.get("sx", 0)),
			"sy": int(sd.get("sy", 0)),
			"state": str(sd.get("state", "online")),
		})
	snap["_ships"] = sharr

	# Lightweight config so clients can show correct HUD maxima without hardcoding.
	snap["_cfg"] = {
		"cargo_max": cargo_max,
		"cargo_pickup_radius": cargo_pickup_radius,
		"fuel_max": fuel_max,
		"charge_max": beam_charge_max,
		# Weapon config (cooldowns + costs) so HUD can render accurate timers.
		"auto_rate_hz": auto_rate_hz,
		"pulse_cooldown": pulse_cooldown,
		"hunter_cooldown": hunter_cooldown,
		"flare_cooldown": flare_cooldown,
		"mine_cooldown": mine_cooldown,
		"fuel_cost_autocannon_shot": fuel_cost_autocannon_shot,
		"fuel_cost_pulse": fuel_cost_pulse,
		"fuel_cost_hunter": fuel_cost_hunter,
		"fuel_cost_flare": fuel_cost_flare,
		"fuel_cost_mine": fuel_cost_mine,
		"beam_fuel_cost_per_s": beam_fuel_cost_per_s,
		"build_distance": build_distance,
		"build_max_slope_deg": build_max_slope_deg,
		"build_min_spacing": build_min_spacing,
		"powercell_radius": powercell_radius,
		"turret_range": turret_range,
		"turret_build_cost": turret_build_cost,
		"powercell_build_cost": powercell_build_cost,
		"skypump_build_cost": skypump_build_cost,
		"repair_cost": repair_cost,
		"repair_range": repair_range,
	}

	# Send state.
	rpc("s_snapshot", snap)

	# Send one-shot FX events.
	if not _events.is_empty():
		rpc("s_events", _events)
		_events.clear()

@rpc("authority", "call_remote", "unreliable")
func s_snapshot(_snap: Dictionary) -> void:
	# Server does not implement this (clients do).
	pass

@rpc("authority", "call_remote", "unreliable")
func s_events(_events_in: Array) -> void:
	# Server does not implement this (clients do).
	pass