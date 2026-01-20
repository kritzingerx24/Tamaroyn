extends RigidBody3D
var team = -1; @export var damage: float = 60.0; @export var splash_radius: float = 15.0; @export var explosion_scene: PackedScene
func _ready(): contact_monitor = true; max_contacts_reported = 1; await get_tree().create_timer(3.0).timeout; queue_free()
func _on_body_entered(body): explode()
func explode():
	if explosion_scene: var ex = explosion_scene.instantiate(); get_tree().root.add_child(ex); ex.global_position = global_position
	var space = get_world_3d().direct_space_state; var query = PhysicsShapeQueryParameters3D.new(); var shape = SphereShape3D.new(); shape.radius = splash_radius; query.shape = shape; query.transform = global_transform; query.collision_mask = 2 + 8
	var results = space.intersect_shape(query)
	for data in results:
		var hit = data.collider
		if hit.has_method("take_damage"):
			if "team" in hit and hit.team == team: continue
			var dist = global_position.distance_to(hit.global_position); var dmg = damage * (1.0 - (dist / splash_radius))
			if dmg > 0: hit.take_damage(dmg, team)
	queue_free()
