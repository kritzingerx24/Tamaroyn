extends RigidBody3D

@export_group("Stats")
@export var max_health: int = 2500
@export var team: int = 0 : set = set_team
var carried_cargo = -1 
var is_cloaked = false

var move_speed = 50.0
var turn_speed = 2.0
var jump_force = 40.0
var hover_height = 3.0

enum State { IDLE, EXPAND, RETRIEVE_CARGO, COMBAT, REPAIR, REFUEL }
var current_state = State.IDLE
var target_pos: Vector3 = Vector3.ZERO
var target_entity: Node3D = null
var think_timer = 0.0

@onready var visuals = $Visuals
@onready var weapon_sys = $WeaponSystem
@onready var raycast = $SuspensionRay

# Whisker Raycasts for avoidance
var whisker_l: RayCast3D
var whisker_r: RayCast3D
var whisker_c: RayCast3D

func _enter_tree(): set_multiplayer_authority(1)

func _ready():
	add_to_group("player")
	add_to_group("tank")
	apply_team_color()
	
	whisker_c = RayCast3D.new()
	whisker_c.target_position = Vector3(0, 0, -20)
	whisker_c.collision_mask = 1
	add_child(whisker_c)
	
	whisker_l = RayCast3D.new()
	whisker_l.target_position = Vector3(-15, 0, -15)
	whisker_l.collision_mask = 1
	add_child(whisker_l)
	
	whisker_r = RayCast3D.new()
	whisker_r.target_position = Vector3(15, 0, -15)
	whisker_r.collision_mask = 1
	add_child(whisker_r)

func set_team(val):
	team = val
	apply_team_color()

func apply_team_color():
	if !visuals: return
	var mat = StandardMaterial3D.new()
	if team == 0:
		mat.albedo_color = Color(0.9, 0.1, 0.1)
	else:
		mat.albedo_color = Color(0.1, 0.3, 1.0)
	for c in visuals.get_children():
		if c is CSGCombiner3D:
			for k in c.get_children():
				if k is CSGPrimitive3D: k.material = mat

func set_cloaked(v):
	is_cloaked = v
	if v:
		visuals.visible = false
	else:
		visuals.visible = true

func _physics_process(delta):
	if !multiplayer.is_server():
		_apply_suspension()
		return
	think_timer += delta
	if think_timer > 1.0:
		think_timer = 0
		_brain_think()
	_execute_state(delta)
	_apply_suspension()

func _brain_think():
	var gm = get_tree().current_scene
	if max_health < 800:
		current_state = State.REPAIR
		var pads = get_tree().get_nodes_in_group("repair_pad")
		target_entity = null
		var min_dist = 9999.0
		for p in pads:
			if p.team == team:
				var d = global_position.distance_to(p.global_position)
				if d < min_dist:
					min_dist = d
					target_entity = p
		return

	if !weapon_sys.has_ammo(0):
		current_state = State.REFUEL
		var pads = get_tree().get_nodes_in_group("refuel_pad")
		target_entity = null
		var min_dist = 9999.0
		for p in pads:
			if p.team == team:
				var d = global_position.distance_to(p.global_position)
				if d < min_dist:
					min_dist = d
					target_entity = p
		if target_entity: return

	var enemies = get_tree().get_nodes_in_group("player")
	var enemy_pads = get_tree().get_nodes_in_group("repair_pad")
	var closest_target = null
	var min_dist = 250.0
	
	for p in enemy_pads:
		if p.team != team:
			var d = global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest_target = p
	if !closest_target:
		for e in enemies:
			if "team" in e and e.team != team:
				if "is_cloaked" in e and e.is_cloaked: continue
				if "max_health" in e and e.max_health <= 0: continue
				var d = global_position.distance_to(e.global_position)
				if d < min_dist:
					min_dist = d
					closest_target = e
	
	if closest_target:
		current_state = State.COMBAT
		target_entity = closest_target
		return

	if current_state == State.COMBAT:
		current_state = State.IDLE
		
	if carried_cargo == -1:
		var my_pad_count = gm.red_pads if team == 0 else gm.blue_pads
		var boxes = get_tree().get_nodes_in_group("cargo")
		var nearest = null
		var box_dist = 100.0
		for b in boxes:
			var d = global_position.distance_to(b.global_position)
			if d < box_dist:
				box_dist = d
				nearest = b
		if nearest:
			current_state = State.RETRIEVE_CARGO
			target_entity = nearest
		else:
			var desired_type = 0
			if my_pad_count < 2:
				desired_type = 2
			elif randf() < 0.3:
				desired_type = 1
			_call_logistics(desired_type)
			current_state = State.IDLE
	else:
		current_state = State.EXPAND
		target_pos = _find_best_expansion_target()

func _find_best_expansion_target() -> Vector3:
	var grid = get_tree().current_scene.get_node("OrbitalGrid")
	if !grid: return global_position
	var my_grid_id = team + 1
	var best_pos = global_position
	var min_dist = 9999.0
	for y in range(0, grid.grid_size, 2):
		for x in range(0, grid.grid_size, 2):
			var idx = y * grid.grid_size + x
			if grid.grid_data[idx] == my_grid_id:
				var neighbors = grid.get_neighbors(x, y, grid.grid_data)
				for n in neighbors:
					if n == 0:
						var w_pos = grid.get_world_pos(x, y)
						var dist = global_position.distance_to(Vector3(w_pos.x, 0, w_pos.y))
						if dist < min_dist:
							min_dist = dist
							best_pos = Vector3(w_pos.x, 5, w_pos.y)
	return best_pos

func _call_logistics(type):
	var spawner = get_tree().current_scene.get_node("BuildingSpawner")
	if spawner:
		spawner.spawn_box(type, global_position + (-transform.basis.z * 10.0) + Vector3(0, 20, 0))

func _execute_state(delta):
	match current_state:
		State.IDLE:
			_drive_to(global_position, delta, true)
		State.RETRIEVE_CARGO:
			if is_instance_valid(target_entity):
				_drive_to(target_entity.global_position, delta)
			else:
				current_state = State.IDLE
		State.EXPAND:
			var dist = _drive_to(target_pos, delta)
			if dist < 5.0:
				var spawner = get_tree().current_scene.get_node("BuildingSpawner")
				if spawner:
					spawner.spawn_building(carried_cargo, global_position, rotation, team)
				carried_cargo = -1
				current_state = State.IDLE
		State.COMBAT:
			if is_instance_valid(target_entity):
				var aim_pos = target_entity.global_position
				$Visuals/TurretPivot.look_at(aim_pos, Vector3.UP)
				$Visuals/TurretPivot.rotation.x = 0
				var d = global_position.distance_to(target_entity.global_position)
				if d < 120:
					weapon_sys.fire_projectile.rpc(linear_velocity, team, false, 0)
				if d > 50:
					_drive_to(target_entity.global_position, delta)
				else:
					_drive_to(global_position, delta, true)
			else:
				current_state = State.IDLE
		State.REPAIR:
			if is_instance_valid(target_entity):
				_drive_to(target_entity.global_position, delta)
		State.REFUEL:
			if is_instance_valid(target_entity):
				_drive_to(target_entity.global_position, delta)

func _drive_to(pos: Vector3, delta: float, stop: bool = false):
	var dist = global_position.distance_to(pos)
	if stop:
		linear_velocity = linear_velocity.move_toward(Vector3.ZERO, 20.0 * delta)
		return 0.0
	
	var target_dir = (pos - global_position).normalized()
	var forward = -transform.basis.z
	var angle = forward.signed_angle_to(target_dir, Vector3.UP)
	
	if abs(angle) > 0.1:
		apply_torque(Vector3.UP * (1.0 if angle > 0 else -1.0) * turn_speed * mass)
	if abs(angle) < 1.0:
		apply_central_force(forward * move_speed * mass * delta * 60.0)
	return dist

func _apply_suspension():
	if raycast.is_colliding():
		var dist = global_position.y - raycast.get_collision_point().y
		var compression = hover_height - dist
		if compression > 0:
			apply_central_force(Vector3.UP * compression * 120.0 - Vector3.UP * linear_velocity.y * 5.0)

func pickup_cargo(type_id):
	if carried_cargo == -1:
		carried_cargo = type_id
		return true
	return false

func repair(amount):
	if max_health < 2500:
		max_health += amount

func refuel(amt):
	weapon_sys.refuel(amt)

@rpc("any_peer", "call_local")
func take_damage(amount, attacker_team):
	if attacker_team == team: return
	max_health -= amount
	if max_health <= 0:
		_respawn()

func _respawn():
	var pads = get_tree().get_nodes_in_group("repair_pad")
	var my_pads = []
	for p in pads:
		if p.team == team:
			my_pads.append(p)
	if my_pads.size() > 0:
		var t = my_pads.pick_random()
		position = t.global_position + Vector3(0, 5, 0)
		max_health = 2500
		carried_cargo = -1
		current_state = State.IDLE
	else:
		queue_free()
