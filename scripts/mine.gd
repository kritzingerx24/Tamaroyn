extends Area3D

var team = -1
@export var damage: float = 100.0
@export var explosion_scene: PackedScene

func _ready():
	# Arming delay
	await get_tree().create_timer(1.0).timeout
	collision_mask = 2 + 32 # Player + Cargo/Vehicles

func _on_body_entered(body):
	if body.has_method("take_damage"):
		# Mines hit EVERYONE, even friends (Area Denial)
		body.take_damage(damage, -1) # -1 Attacker ID implies Neutral/World damage
		explode()

func explode():
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_tree().root.add_child(ex)
		ex.global_position = global_position
	queue_free()
