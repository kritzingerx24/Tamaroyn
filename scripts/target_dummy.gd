extends RigidBody3D

@export var max_health: int = 100
var current_health: int

@onready var mesh = $MeshInstance3D

func _ready():
	current_health = max_health

func take_damage(amount):
	current_health -= amount
	flash_color()
	print("Dummy hit! Health: ", current_health)
	
	if current_health <= 0:
		die()

func flash_color():
	var mat = mesh.get_active_material(0) as StandardMaterial3D
	if mat:
		var original_color = mat.albedo_color
		mat.albedo_color = Color.RED
		mat.emission_enabled = true
		mat.emission = Color.RED
		mat.emission_energy_multiplier = 2.0
		
		await get_tree().create_timer(0.1).timeout
		
		if is_instance_valid(mat):
			mat.albedo_color = original_color
			mat.emission_enabled = false

func die():
	print("Target Destroyed")
	queue_free()
