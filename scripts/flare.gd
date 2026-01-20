extends RigidBody3D
func _ready(): add_to_group("flare"); await get_tree().create_timer(3.0).timeout; queue_free()
