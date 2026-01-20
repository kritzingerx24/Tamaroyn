extends RigidBody3D

var team = -1
var is_thumper = false
var is_piercer = false
@export var damage: float = 80.0
@export var turn_speed: float = 3.0
@export var acceleration: float = 40.0
@export var max_speed: float = 120.0
@export var explosion_scene: PackedScene

var target: Node3D = null
var timer = 0.0

@onready var trail = $Trail3D # Using simple Trail node or LineRenderer emulation

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	if is_piercer:
		max_speed = 200.0; acceleration = 100.0; damage = 150.0; turn_speed = 0
	await get_tree().create_timer(5.0).timeout; queue_free()

func _physics_process(delta):
	timer += delta
	if !is_thumper and !is_piercer and is_instance_valid(target) and timer > 0.5:
		var target_dir = (target.global_position - global_position).normalized()
		var new_basis = global_transform.basis.slerp(global_transform.looking_at(target.global_position, Vector3.UP).basis, turn_speed * delta)
		global_transform.basis = new_basis
	if linear_velocity.length() < max_speed:
		apply_central_force(-global_transform.basis.z * acceleration)

func _on_body_entered(body): explode()

func explode():
	if explosion_scene: var ex = explosion_scene.instantiate(); get_tree().root.add_child(ex); ex.global_position = global_position
	var space = get_world_3d().direct_space_state; var query = PhysicsShapeQueryParameters3D.new(); var shape = SphereShape3D.new(); shape.radius = 10.0; query.shape = shape; query.transform = global_transform; query.collision_mask = 2 + 8
	var results = space.intersect_shape(query)
	for data in results:
		var hit = data.collider
		if hit.has_method("take_damage"): if "team" in hit and hit.team == team: continue; hit.take_damage(damage, team); if is_thumper and hit is RigidBody3D: hit.apply_torque_impulse(Vector3(0, 5000, 0)); hit.apply_central_impulse(Vector3(0, 1000, 0))
	queue_free()
