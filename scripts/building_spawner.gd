extends Node

@export var cargo_box_scene: PackedScene
@export var buildings: Array[PackedScene]

func spawn_box(type, pos):
	var ground_pos = _get_ground_pos(pos)
	var box = cargo_box_scene.instantiate()
	box.building_type = type
	get_parent().add_child(box)
	box.global_position = ground_pos + Vector3(0, 1, 0)

func spawn_building(type, pos, rot, team):
	if type < buildings.size():
		var b = buildings[type].instantiate()
		if "team" in b: b.team = team
		get_parent().add_child(b)
		var ground_pos = _get_ground_pos(pos)
		b.global_position = ground_pos
		b.global_rotation.y = rot.y

func _get_ground_pos(start_pos: Vector3) -> Vector3:
	var space = get_tree().current_scene.get_world_3d().direct_space_state
	var from = Vector3(start_pos.x, 1000, start_pos.z)
	var to = Vector3(start_pos.x, -1000, start_pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 # World Layer
	var result = space.intersect_ray(query)
	if result:
		return result.position
	return Vector3(start_pos.x, 0, start_pos.z)
