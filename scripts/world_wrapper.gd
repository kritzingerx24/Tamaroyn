extends Node3D

@onready var map_container = $MapContainer

func load_map_scene(path):
	print("Loading Map: " + path)
	for c in map_container.get_children():
		c.queue_free()
		
	if !FileAccess.file_exists(path):
		var floor = CSGBox3D.new()
		floor.size = Vector3(2000, 1, 2000)
		floor.use_collision = true
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.5, 0.2)
		floor.material = mat
		map_container.add_child(floor)
		
		# Fallback light
		var sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, 45, 0)
		map_container.add_child(sun)
		return

	var scene = load(path)
	if scene:
		var instance = scene.instantiate()
		map_container.add_child(instance)
		
		# Ensure we analyze it
		var gm = get_parent().get_node_or_null("GameManager")
		if gm and gm.has_method("analyze_map"):
			gm.analyze_map()
