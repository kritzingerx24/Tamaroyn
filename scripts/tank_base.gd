extends RigidBody3D
class_name TankBase

signal stats_changed(health, max_health)
signal died()

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

var input_move = 0.0
var input_turn = 0.0
var input_jump = false
var input_fire = false

func _ready():
	current_health = max_health
	mass = 50.0
	gravity_scale = 1.0
	linear_damp = 0.5
	angular_damp = 2.0
	raycast.target_position = Vector3(0, -(hover_height + 2.0), 0)
	emit_signal("stats_changed", current_health, max_health)

func _physics_process(delta):
	# Child classes (Player/AI) update inputs before this
	apply_suspension_force()
	apply_movement(delta)
	
	if input_fire:
		weapon_sys.fire(linear_velocity)

func apply_suspension_force():
	if raycast.is_colliding():
		var hit_point = raycast.get_collision_point()
		var compression = hover_height - (global_position.y - hit_point.y)
		if compression > 0:
			var spring_force = 120.0 * compression
			var damping = 5.0 * linear_velocity.y
			apply_central_force(Vector3.UP * (spring_force - damping))

func apply_movement(delta):
	apply_torque(Vector3.UP * input_turn * turn_speed * mass)
	if input_move != 0:
		apply_central_force(-transform.basis.z * input_move * move_speed * mass * delta * 60)
	if input_jump:
		apply_central_force(Vector3.UP * jump_jet_force * mass * 0.1)

func take_damage(amount):
	current_health -= amount
	emit_signal("stats_changed", current_health, max_health)
	if current_health <= 0:
		die()

func die():
	print("Tank Destroyed")
	emit_signal("died")
	# Spawn explosion (handled by spawner or self)
	queue_free()

func repair(amount):
	if current_health < max_health:
		current_health = min(current_health + amount, max_health)
		emit_signal("stats_changed", current_health, max_health)
		return true
	return false

func refuel(amount):
	return weapon_sys.add_ammo(amount)
