extends Node3D
var target_pos: Vector3
var building_scene: PackedScene
var state = 0
func setup_delivery(pos, b):
	target_pos = pos
	building_scene = b
	global_position = pos + Vector3(0, 100, 0)
func _process(delta):
	if state == 0:
		global_position = global_position.move_toward(target_pos + Vector3(0, 10, 0), 30 * delta)
		if global_position.distance_to(target_pos + Vector3(0,10,0)) < 1.0:
			var b = building_scene.instantiate()
			get_tree().root.add_child(b)
			b.global_position = target_pos
			state = 1
	elif state == 1:
		global_position += Vector3.UP * 30 * delta
		if global_position.y > 150: queue_free()
