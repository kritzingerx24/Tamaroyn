extends StaticBody3D

@export var size: int = 256
@export var scale_factor: float = 2.0
@export var height_scale: float = 20.0
@export var material: Material

var noise: FastNoiseLite

func _ready():
	noise = FastNoiseLite.new()
	noise.seed = 12345 # Consistent seed for testing, or randi()
	noise.frequency = 0.015
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	_gen_mesh()
	_connect_grid()

func get_height(x, z) -> float:
	# Convert world coords to height
	# Grid centers on 0,0
	if !noise: return 0.0
	
	# Mapping world space to noise space
	# Our mesh generation maps: (index_x + offset) * scale -> World
	# So World / scale - offset = index
	var offset = -size / 2.0
	var idx_x = (x / scale_factor) - offset
	var idx_z = (z / scale_factor) - offset
	
	return noise.get_noise_2d(idx_x, idx_z) * height_scale

func _connect_grid():
	await get_tree().process_frame
	var g = get_tree().current_scene.get_node("OrbitalGrid")
	if g:
		g.grid_updated.connect(_on_grid_updated)
		if g.map_texture: _on_grid_updated(g.map_texture)

func _on_grid_updated(t):
	if material is ShaderMaterial:
		material.set_shader_parameter("map_data", t)

func _gen_mesh():
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if material: surface.set_material(material)
	
	var offset = -size / 2.0
	
	for z in range(size):
		for x in range(size):
			var px = (x+offset)*scale_factor
			var pz = (z+offset)*scale_factor
			
			var h1 = noise.get_noise_2d(x, z) * height_scale
			var h2 = noise.get_noise_2d(x+1, z) * height_scale
			var h3 = noise.get_noise_2d(x, z+1) * height_scale
			var h4 = noise.get_noise_2d(x+1, z+1) * height_scale
			
			# Tri 1
			surface.set_uv(Vector2(0,0))
			surface.add_vertex(Vector3(px, h1, pz))
			surface.set_uv(Vector2(1,0))
			surface.add_vertex(Vector3(px+scale_factor, h2, pz))
			surface.set_uv(Vector2(0,1))
			surface.add_vertex(Vector3(px, h3, pz+scale_factor))
			
			# Tri 2
			surface.set_uv(Vector2(1,0))
			surface.add_vertex(Vector3(px+scale_factor, h2, pz))
			surface.set_uv(Vector2(1,1))
			surface.add_vertex(Vector3(px+scale_factor, h4, pz+scale_factor))
			surface.set_uv(Vector2(0,1))
			surface.add_vertex(Vector3(px, h3, pz+scale_factor))
	
	surface.generate_normals()
	var m = MeshInstance3D.new()
	m.mesh = surface.commit()
	add_child(m)
	
	# Physics
	var c = CollisionShape3D.new()
	c.shape = m.mesh.create_trimesh_shape()
	add_child(c)
