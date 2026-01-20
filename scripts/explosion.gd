extends Node3D
@onready var audio = $AudioStreamPlayer3D; @onready var particles = $Particles
func _ready():
	particles.emitting = true; if audio: audio.play()
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		var dist = global_position.distance_to(cam.global_position)
		if dist < 50.0: cam.shake(1.0 - (dist/50.0))
	await get_tree().create_timer(3.0).timeout; queue_free()
