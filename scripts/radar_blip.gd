extends Node3D
@export var color: Color = Color.RED; @export var is_player: bool = false
func _ready():
	var mesh = MeshInstance3D.new(); var sphere = SphereMesh.new(); var mat = StandardMaterial3D.new()
	sphere.radius = 4.0 if is_player else 3.0; sphere.height = sphere.radius * 2; mat.albedo_color = color; mat.emission_enabled = true; mat.emission = color
	mesh.mesh = sphere; mesh.material_override = mat; add_child(mesh); mesh.layers = 512
