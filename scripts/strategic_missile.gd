extends RigidBody3D

var team = -1
var target_pos = Vector3.ZERO
@export var explosion_scene: PackedScene

var phase = 0 # 0:Ascend, 1:Cruise, 2:Descend

func _ready():
	gravity_scale = 0
	contact_monitor = true
	max_contacts_reported = 1

func _physics_process(delta):
	if phase == 0:
		if global_position.y > 100:
			phase = 1
			global_position.y = 100
			linear_velocity = Vector3.ZERO
	elif phase == 1:
		# Cruise to XZ of target
		var target_flat = Vector3(target_pos.x, 100, target_pos.z)
		var dir = (target_flat - global_position).normalized()
		linear_velocity = dir * 60.0
		look_at(target_flat, Vector3.UP)
		
		if global_position.distance_to(target_flat) < 5.0:
			phase = 2
			linear_velocity = Vector3.ZERO
	elif phase == 2:
		# Drop
		linear_velocity = Vector3(0, -60, 0)
		look_at(global_position + Vector3(0, -1, 0), Vector3.UP)

func _on_body_entered(body):
	explode()

func explode():
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_tree().root.add_child(ex)
		ex.global_position = global_position
		ex.scale = Vector3(5, 5, 5) # Big boom
	
	var space = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 50.0
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 2 + 8
	
	var results = space.intersect_shape(query)
	for data in results:
		var hit = data.collider
		if hit.has_method("take_damage"):
			# Strategic missiles hurt EVERYONE (Friendly Fire ON for nukes)
			hit.take_damage(2000, -1)
	
	queue_free()
