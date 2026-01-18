extends Node3D

@export var enemy_scene: PackedScene
@export var explosion_scene: PackedScene

func _ready():
	spawn_enemy()

func spawn_enemy():
	await get_tree().create_timer(3.0).timeout
	var e = enemy_scene.instantiate()
	add_child(e)
	e.global_position = Vector3(randf_range(-50, 50), 10, randf_range(-50, -100))
	e.died.connect(_on_enemy_died.bind(e.global_position))

func _on_enemy_died(pos):
	if explosion_scene:
		var ex = explosion_scene.instantiate()
		get_tree().root.add_child(ex)
		ex.global_position = pos
	spawn_enemy()
