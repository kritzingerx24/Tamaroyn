extends Node3D

func _ready():
	$Particles.emitting = true
	await get_tree().create_timer(2.0).timeout
	queue_free()
