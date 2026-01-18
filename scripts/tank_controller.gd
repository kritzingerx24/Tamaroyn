extends RigidBody3D

signal stats_changed(health, max_health)

@export_group("Stats")
@export var max_health: float = 200.0
var current_health: float

@export_group("Movement")
@export var move_speed: float = 40.0
@export var turn_speed: float = 2.0
@export var jump_jet_force: float = 30.0
@export var hover_height: float = 3.0

@onready var weapon_sys: Node3D = $WeaponSystem
@onready var raycast: RayCast3D = $SuspensionRay
@onready var turret_node: Node3D = $Visuals/TurretPivot
@onready var camera: Camera3D = $"../Camera3D"

func _ready():
	current_health = max_health
	mass = 50.0
	gravity_scale = 1.0
	linear_damp = 0.5
	angular_damp = 2.0
	raycast.target_position = Vector3(0, -(hover_height + 2.0), 0)
	emit_signal("stats_changed", current_health, max_health)

func _physics_process(delta):
	apply_suspension_force()
	handle_movement(delta)
	handle_jump_jets()
	handle_combat()
	handle_turret_aim()

func handle_turret_aim():
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

func apply_suspension_force():
	if raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var compression = hover_height - (global_position.y - hit_point.y)
		if compression > 0:
			var spring_force = 120.0 * compression
			var damping = 5.0 * linear_velocity.y
			apply_central_force(Vector3.UP * (spring_force - damping))

func handle_movement(delta):
	var turn = Input.get_axis("turn_right", "turn_left")
	apply_torque(Vector3.UP * turn * turn_speed * mass)
	var move = Input.get_axis("move_backward", "move_forward")
	if move != 0:
		apply_central_force(-transform.basis.z * move * move_speed * mass * delta * 60)

func handle_jump_jets():
	if Input.is_action_pressed("jump_jets"):
		apply_central_force(Vector3.UP * jump_jet_force * mass * 0.1)

func handle_combat():
	if Input.is_action_just_pressed("select_weapon_1"): weapon_sys.switch_weapon(0)
	if Input.is_action_just_pressed("select_weapon_2"): weapon_sys.switch_weapon(1)
	if Input.is_action_pressed("fire_primary"): weapon_sys.fire(linear_velocity)

func take_damage(amount):
	current_health -= amount
	emit_signal("stats_changed", current_health, max_health)

func repair(amount):
	if current_health < max_health:
		current_health = min(current_health + amount, max_health)
		emit_signal("stats_changed", current_health, max_health)
		return true
	return false

func refuel(amount):
	return weapon_sys.add_ammo(amount)
