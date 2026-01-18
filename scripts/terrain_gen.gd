extends StaticBody3D

@export var size: int = 256
@export var scale_factor: float = 2.0
@export var height_scale: float = 15.0
@export var material: Material

func _ready():
	generate_terrain()

func generate_terrain():
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if material:
		surface_tool.set_material(material)
	
	var offset = -size / 2.0
	
	# Generate Grid
	for z in range(size):
		for x in range(size):
			var pos_x = (x + offset) * scale_factor
			var pos_z = (z + offset) * scale_factor
			
			# Create 2 triangles for a quad
			# Vertices
			var h1 = noise.get_noise_2d(x, z) * height_scale
			var h2 = noise.get_noise_2d(x + 1, z) * height_scale
			var h3 = noise.get_noise_2d(x, z + 1) * height_scale
			var h4 = noise.get_noise_2d(x + 1, z + 1) * height_scale
			
			var v1 = Vector3(pos_x, h1, pos_z)
			var v2 = Vector3(pos_x + scale_factor, h2, pos_z)
			var v3 = Vector3(pos_x, h3, pos_z + scale_factor)
			var v4 = Vector3(pos_x + scale_factor, h4, pos_z + scale_factor)
			
			# Triangle 1
			surface_tool.add_vertex(v1)
			surface_tool.add_vertex(v2)
			surface_tool.add_vertex(v3)
			
			# Triangle 2
			surface_tool.add_vertex(v2)
			surface_tool.add_vertex(v4)
			surface_tool.add_vertex(v3)
			
	surface_tool.generate_normals()
	
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = surface_tool.commit()
	add_child(mesh_inst)
	
	# Collision
	var shape = mesh_inst.mesh.create_trimesh_shape()
	var col = CollisionShape3D.new()
	col.shape = shape
	add_child(col)
