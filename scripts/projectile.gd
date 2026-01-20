extends RigidBody3D

@export var team: int = -1
@export var damage: int = 25
var is_pulse = false

@export var impact_vfx: PackedScene

func _ready():
	await get_tree().create_timer(3.0).timeout
	queue_free()

func _on_body_entered(body):
	if body.has_method("take_damage"):
		if "team" in body and body.team == team:
			pass
		else:
			body.take_damage(damage, team)
			_spawn_impact()
			queue_free()
	else:
		_spawn_impact()
		queue_free()

func _spawn_impact():
	# VFX instantiation here if needed
	pass
