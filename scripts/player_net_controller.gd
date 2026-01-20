extends RigidBody3D

@export_group("Stats")
@export var max_health: int = 2500
@export var team: int = 0 : set = set_team
var carried_cargo = -1 
var is_cloaked = false : set = set_cloaked

@export var max_energy: float = 100.0
var current_energy: float = 100.0
@export var energy_regen_rate: float = 10.0

var throttle_idx: int = 0
var target_speed: float = 0.0
var snare_timer: float = 0.0

@export_group("Physics")
@export var max_speed: float = 60.0 
@export var turn_speed: float = 2.0
@export var acceleration: float = 80.0
@export var jump_force: float = 40.0
@export var hover_height: float = 3.0

var selected_slot = 0
var weapon_names = ["AUTO", "PULSE", "THUMP", "HUNT", "MINE", "CALT", "PIERCE"]

@onready var weapon_sys = $WeaponSystem
@onready var visuals = $Visuals
@onready var camera = $Camera3D
@onready var cargo_sound = $CargoSound

@export var spectator_scene: PackedScene

func _enter_tree(): set_multiplayer_authority(name.to_int())

func _ready():
	if is_multiplayer_authority(): 
		camera.current = true
		visuals.visible = true # FORCE VISIBLE for Chase Cam
	
	apply_team_color()
	if is_in_group("tank"): 
		add_to_group("logistics")
		max_health = 2500
	elif is_in_group("scout"):
		max_health = 600
	current_energy = max_energy

func set_team(val): team = val; apply_team_color()
func apply_team_color():
	if !visuals: return
	var mat = StandardMaterial3D.new()
	if team == 0: mat.albedo_color = Color(0.9, 0.1, 0.1)
	else: mat.albedo_color = Color(0.1, 0.3, 1.0)
	for c in visuals.get_children():
		if c is CSGCombiner3D: for k in c.get_children(): if k is CSGPrimitive3D: k.material = mat

func set_cloaked(val):
	is_cloaked = val
	# Only affect visibility if NOT local authority
	if !is_multiplayer_authority():
		visuals.visible = !val

func _physics_process(delta):
	if is_multiplayer_authority():
		var chat = get_tree().get_first_node_in_group("chat_ui")
		if chat and chat.is_typing: return

		if max_health <= 0: return

		handle_input(delta)
		handle_energy(delta)
		handle_movement(delta)
	
	if max_health > 0:
		_suspension()
	
	if is_multiplayer_authority():
		# Chase Logic
		var desired_pos = global_position + (-transform.basis.z * -12.0) + Vector3(0, 8, 0)
		camera.global_position = camera.global_position.lerp(desired_pos, 10.0 * delta)
		camera.look_at(global_position + Vector3(0, 2, 0), Vector3.UP)

func handle_input(delta):
	for i in range(10):
		if Input.is_action_just_pressed("throttle_" + str(i)): throttle_idx = i
	
	if Input.is_action_just_pressed("nudge_forward") and throttle_idx < 9: throttle_idx += 1
	if Input.is_action_just_pressed("nudge_backward") and throttle_idx > 0: throttle_idx -= 1

	var turn = Input.get_axis("turn_right", "turn_left")
	apply_torque(Vector3.UP * turn * turn_speed * mass)

	if Input.is_action_just_pressed("jump_jets") and current_energy >= 15.0:
		current_energy -= 15.0
		apply_central_force(Vector3.UP * jump_force * mass * 0.8)

	if Input.is_action_just_pressed("select_weapon_1"): selected_slot = 0
	if Input.is_action_just_pressed("select_weapon_2"): selected_slot = 1
	if Input.is_action_just_pressed("select_weapon_3"): selected_slot = 2
	if Input.is_action_just_pressed("select_weapon_4"): selected_slot = 3
	if Input.is_action_just_pressed("select_weapon_5"): selected_slot = 4
	if Input.is_action_just_pressed("select_weapon_6"): selected_slot = 6

	if Input.is_action_pressed("fire_primary"):
		fire_current_weapon()

	if Input.is_action_just_pressed("use_flare") and current_energy >= 20.0:
		current_energy -= 20.0
		drop_flare.rpc()
		
	if Input.is_action_just_pressed("cargo_deploy"): try_deploy_cargo()
	if Input.is_action_just_pressed("cargo_drop"): try_drop_cargo()
	
	if Input.is_action_just_pressed("toggle_map"):
		var map = get_tree().current_scene.get_node_or_null("UI/MapScreen")
		if map: map.visible = !map.visible

func fire_current_weapon():
	match selected_slot:
		0: weapon_sys.fire_projectile.rpc(linear_velocity, team, false, 0)
		1: weapon_sys.fire_projectile.rpc(linear_velocity, team, true, 1)
		2: weapon_sys.fire_missile.rpc(linear_velocity, team, NodePath(""), true, false, 2)
		3: 
			var target_path = NodePath("")
			if weapon_sys.locked_target: target_path = weapon_sys.locked_target.get_path()
			weapon_sys.fire_missile.rpc(linear_velocity, team, target_path, false, false, 3)
		4: weapon_sys.deploy_mine.rpc(team, 4)
		5: weapon_sys.deploy_caltrop.rpc(team, 5)
		6: weapon_sys.fire_missile.rpc(linear_velocity, team, NodePath(""), false, true, 6)

@rpc("call_local")
func drop_flare():
	if weapon_sys.flare_scene:
		var f = weapon_sys.flare_scene.instantiate()
		get_tree().root.add_child(f)
		f.global_transform = global_transform
		f.apply_impulse(Vector3(0, 10, 0) + (-transform.basis.z * -10))

func handle_energy(delta):
	var consuming = false
	if throttle_idx >= 8:
		consuming = true
		current_energy -= (15.0 if throttle_idx==9 else 5.0) * delta
		if current_energy <= 0: current_energy = 0; throttle_idx = 7
	if !consuming and current_energy < max_energy: current_energy += energy_regen_rate * delta

func handle_movement(delta):
	if snare_timer > 0:
		snare_timer -= delta; target_speed = 0; throttle_idx = 0
	else:
		target_speed = (float(throttle_idx) / 9.0) * max_speed
		
	var current_forward = -linear_velocity.dot(transform.basis.z)
	var speed_diff = target_speed - current_forward
	if abs(speed_diff) > 1.0:
		apply_central_force(-transform.basis.z * sign(speed_diff) * acceleration * mass * delta)

func _suspension():
	var ray = $SuspensionRay
	if ray.is_colliding():
		var dist = global_position.y - ray.get_collision_point().y
		var compression = hover_height - dist
		if compression > 0:
			apply_central_force(Vector3.UP * compression * 120.0 - Vector3.UP * linear_velocity.y * 5.0)

func apply_snare(duration): snare_timer = duration; throttle_idx = 0

func pickup_cargo(t):
	if carried_cargo == -1:
		carried_cargo = t
		if cargo_sound: cargo_sound.play()
		return true
	return false

func try_deploy_cargo():
	if carried_cargo != -1:
		request_build.rpc_id(1, carried_cargo, global_position, rotation, team)
		carried_cargo = -1

func try_drop_cargo():
	if carried_cargo != -1:
		request_drop_box.rpc_id(1, carried_cargo, global_position)
		carried_cargo = -1

func get_aim_point() -> Vector3:
	var m=get_viewport().get_mouse_position(); var o=camera.project_ray_origin(m); var e=o+camera.project_ray_normal(m)*2000; var s=get_world_3d().direct_space_state; var q=PhysicsRayQueryParameters3D.create(o,e); q.collision_mask=1; var r=s.intersect_ray(q); if r: return r.position; return Vector3.ZERO
func refuel(amt): weapon_sys.refuel(amt)
@rpc("any_peer", "call_local") func request_build(t,p,r,tm): if multiplayer.is_server(): get_tree().current_scene.get_node("BuildingSpawner").spawn_building(t,p,r,tm)
@rpc("any_peer", "call_local") func request_drop_box(t,p): if multiplayer.is_server(): get_tree().current_scene.get_node("BuildingSpawner").spawn_box(t,p+Vector3(0,2,0))

@rpc("call_local")
func show_hit_marker():
	if is_multiplayer_authority():
		var hud = get_tree().get_first_node_in_group("hud")
		if hud: hud.flash_crosshair()

@rpc("any_peer", "call_local")
func take_damage(amount, attacker_team, attacker_id=0):
	if attacker_team == team: return
	if attacker_id != 0:
		var attacker = get_parent().get_node_or_null(str(attacker_id))
		if attacker: attacker.show_hit_marker.rpc_id(attacker_id)
	max_health -= amount
	if max_health <= 0: die(attacker_id)

func repair(amount): if max_health < 2500: max_health += amount

func die(killer_id):
	NetworkManager.broadcast_kill.rpc(killer_id, name.to_int(), team, team)
	max_health = 0
	carried_cargo = -1
	current_energy = max_energy
	if multiplayer.is_server():
		var gm = get_tree().current_scene
		if gm.has_method("_find_spawn_point"):
			gm.check_win_condition()
			var pads = get_tree().get_nodes_in_group("repair_pad"); var my_pads = []
			for p in pads: if p.team == team: my_pads.append(p)
			if my_pads.size() > 0: 
				var t = my_pads.pick_random(); position = t.global_position + Vector3(0, 5, 0); max_health = 2500 if is_in_group("tank") else 600
			else: 
				print("NO PADS - SPECTATING")
				spawn_spectator.rpc_id(name.to_int())

@rpc("call_local")
func spawn_spectator():
	if spectator_scene:
		var s = spectator_scene.instantiate()
		s.name = "SpectatorCam"
		get_parent().add_child(s)
		s.global_position = global_position + Vector3(0, 10, 0)
		queue_free()
