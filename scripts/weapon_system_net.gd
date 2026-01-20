extends Node3D

enum WeaponType { PROJECTILE, BEAM, MISSILE, DEPLOYABLE }
@export var weapon_type: WeaponType = WeaponType.PROJECTILE

@export var projectile_scene: PackedScene
@export var missile_scene: PackedScene
@export var mine_scene: PackedScene
@export var caltrop_scene: PackedScene

@export var muzzle_point: Node3D
@export var drop_point: Node3D
@export var shoot_sound: AudioStreamPlayer3D
@export var drop_sound: AudioStreamPlayer3D
@export var lock_sound: AudioStreamPlayer3D
@export var beam_mesh: MeshInstance3D

@onready var muzzle_flash = $MuzzleFlash

var locked_target: Node3D = null
var last_fire = 0.0
var firing_beam = false

var ammo_counts = {0: 200, 1: 50, 2: 10, 3: 10, 4: 5, 5: 5, 6: 5}
var max_ammo = {0: 400, 1: 100, 2: 20, 3: 20, 4: 10, 5: 10, 6: 10}

func _ready():
	if beam_mesh: beam_mesh.visible = false
	if muzzle_flash: muzzle_flash.visible = false

func _process(delta):
	if weapon_type == WeaponType.BEAM:
		if firing_beam:
			if shoot_sound and !shoot_sound.playing: shoot_sound.play()
			beam_mesh.visible = true
		else:
			if shoot_sound: shoot_sound.stop()
			beam_mesh.visible = false
		firing_beam = false

func has_ammo(slot):
	return ammo_counts.get(slot, 0) > 0

@rpc("call_local")
func consume_ammo(slot):
	if ammo_counts.has(slot):
		ammo_counts[slot] = max(0, ammo_counts[slot] - 1)

func refuel(amount_scale=1.0):
	for k in ammo_counts.keys():
		var amount = 1 * amount_scale
		if k == 0: amount = 5 * amount_scale
		ammo_counts[k] = min(ammo_counts[k] + amount, max_ammo[k])

@rpc("call_local")
func fire_projectile(vel, team_id, is_pulse=false, slot=0):
	if _check_cooldown(0.25): return
	if !has_ammo(slot): return
	consume_ammo(slot)
	
	_play_flash()
	if shoot_sound: shoot_sound.play()
	
	var p = projectile_scene.instantiate()
	p.team = team_id
	p.is_pulse = is_pulse
	get_tree().root.add_child(p)
	p.global_transform = muzzle_point.global_transform
	p.linear_velocity = (-muzzle_point.global_transform.basis.z * 150.0) + vel

@rpc("call_local")
func fire_missile(vel, team_id, target_path, is_thumper=false, is_piercer=false, slot=3):
	if _check_cooldown(1.5): return
	if !has_ammo(slot): return
	consume_ammo(slot)
	
	_play_flash()
	if shoot_sound: shoot_sound.play()
	
	var m = missile_scene.instantiate()
	m.team = team_id
	m.is_thumper = is_thumper
	m.is_piercer = is_piercer
	if !is_thumper and !is_piercer and target_path != NodePath(""):
		m.target = get_node_or_null(target_path)
	get_tree().root.add_child(m)
	m.global_transform = muzzle_point.global_transform
	m.linear_velocity = (-muzzle_point.global_transform.basis.z * 40.0) + vel

@rpc("call_local")
func deploy_mine(team_id, slot=4):
	if _check_cooldown(2.0): return
	if !has_ammo(slot): return
	consume_ammo(slot)
	
	if drop_sound: drop_sound.play()
	var m = mine_scene.instantiate()
	m.team = team_id
	get_tree().root.add_child(m)
	m.global_transform = drop_point.global_transform

@rpc("call_local")
func deploy_caltrop(team_id, slot=5):
	if _check_cooldown(1.0): return
	if !has_ammo(slot): return
	consume_ammo(slot)
	
	if drop_sound: drop_sound.play()
	for i in range(3):
		var c = caltrop_scene.instantiate()
		get_tree().root.add_child(c)
		var offset = Vector3(randf_range(-2,2), 0, randf_range(-2,2))
		c.global_position = drop_point.global_position + offset
		c.apply_impulse(Vector3(randf(), 2, randf()))

func _play_flash():
	if muzzle_flash:
		muzzle_flash.visible = true
		await get_tree().create_timer(0.05).timeout
		muzzle_flash.visible = false

func _check_cooldown(t):
	var time = Time.get_ticks_msec()/1000.0
	if time - last_fire < t: return true
	last_fire = time
	return false

@rpc("call_local")
func fire_beam(origin, direction, team_id, delta_time):
	firing_beam = true
	var space = get_world_3d().direct_space_state
	var end = origin + (direction * 300.0)
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 2 + 8
	var result = space.intersect_ray(query)
	var hit_pos = end
	if result:
		hit_pos = result.position
		var collider = result.collider
		if collider.has_method("take_damage") and "team" in collider:
			if collider.team == team_id:
				if collider.has_method("repair"): collider.repair(10.0 * delta_time)
				set_beam_color(Color(0,1,0))
			else:
				collider.take_damage(20.0 * delta_time, team_id)
				set_beam_color(Color(1,0,0))
		else: set_beam_color(Color(0,1,1))
	else: set_beam_color(Color(0,0,1))
	update_beam_visual(origin, hit_pos)

func set_beam_color(c):
	if beam_mesh and beam_mesh.get_active_material(0):
		if beam_mesh.get_active_material(0) is ShaderMaterial:
			beam_mesh.get_active_material(0).set_shader_parameter("color", c)
		else:
			beam_mesh.get_active_material(0).albedo_color = c

func update_beam_visual(start, end):
	if beam_mesh:
		var length = start.distance_to(end)
		beam_mesh.global_position = (start + end) / 2.0
		beam_mesh.look_at(end, Vector3.UP)
		beam_mesh.scale.z = length
		beam_mesh.rotation.x -= PI/2
