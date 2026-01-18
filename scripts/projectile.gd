extends RigidBody3D
@export var damage: int = 25
@export var life_time: float = 3.0
func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	await get_tree().create_timer(life_time).timeout
	queue_free()
func _on_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
