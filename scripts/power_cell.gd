extends RigidBody3D

# Simple logic: If this object exists, it emits 'power' via the Area3D.
# When destroyed, the Area3D disappears, updating overlapping buildings.

@export var max_health: int = 200
var current_health: int

func _ready():
	current_health = max_health

func take_damage(amount):
	current_health -= amount
	if current_health <= 0:
		die()

func die():
	print("Power Cell Destroyed! Grid failing...")
	queue_free()
