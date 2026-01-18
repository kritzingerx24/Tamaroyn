extends RigidBody3D
func _ready(): await get_tree().create_timer(3.0).timeout; queue_free()
func _on_body_entered(body): queue_free()
