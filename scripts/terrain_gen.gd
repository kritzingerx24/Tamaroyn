extends StaticBody3D
@export var size: int = 256
@export var scale_factor: float = 2.0
@export var height_scale: float = 15.0
@export var material: Material
func _ready():
	var noise = FastNoiseLite.new(); noise.seed = randi(); noise.frequency = 0.02
	var surface = SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if material: surface.set_material(material)
	var off = -size/2.0
	for z in range(size):
		for x in range(size):
			var px = (x+off)*scale_factor; var pz = (z+off)*scale_factor
			var h1 = noise.get_noise_2d(x,z)*height_scale; var h2 = noise.get_noise_2d(x+1,z)*height_scale
			var h3 = noise.get_noise_2d(x,z+1)*height_scale; var h4 = noise.get_noise_2d(x+1,z+1)*height_scale
			surface.add_vertex(Vector3(px,h1,pz)); surface.add_vertex(Vector3(px+scale_factor,h2,pz)); surface.add_vertex(Vector3(px,h3,pz+scale_factor))
			surface.add_vertex(Vector3(px+scale_factor,h2,pz)); surface.add_vertex(Vector3(px+scale_factor,h4,pz+scale_factor)); surface.add_vertex(Vector3(px,h3,pz+scale_factor))
	surface.generate_normals()
	var m = MeshInstance3D.new(); m.mesh = surface.commit(); add_child(m)
	var c = CollisionShape3D.new(); c.shape = m.mesh.create_trimesh_shape(); add_child(c)
