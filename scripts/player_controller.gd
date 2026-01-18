extends "res://scripts/tank_base.gd"

@onready var camera: Camera3D = $"../Camera3D"

func _physics_process(delta):
	input_turn = Input.get_axis("turn_right", "turn_left")
	input_move = Input.get_axis("move_backward", "move_forward")
	input_jump = Input.is_action_pressed("jump_jets")
	input_fire = Input.is_action_pressed("fire_primary")
	
	if Input.is_action_just_pressed("select_weapon_1"): weapon_sys.switch_weapon(0)
	if Input.is_action_just_pressed("select_weapon_2"): weapon_sys.switch_weapon(1)
	
	handle_turret_aim()
	super._physics_process(delta)

func handle_turret_aim():
	if !camera: return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 2000.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result:
		var look_target = result.position
		look_target.y = turret_node.global_position.y
		var target_xform = turret_node.global_transform.looking_at(look_target, Vector3.UP)
		turret_node.global_transform = turret_node.global_transform.interpolate_with(target_xform, 0.1)

func get_aim_point() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_pos) * 2000.0
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result: return result.position
	return Vector3.ZERO
