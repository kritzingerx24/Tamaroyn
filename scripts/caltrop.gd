extends RigidBody3D

func _on_body_entered(body):
	if body.has_method("apply_snare"):
		body.apply_snare(2.0) # 2 seconds snare
		# Caltrop destroyed on impact? Or stays?
		# Let's destroy it to clear clutter
		queue_free()
