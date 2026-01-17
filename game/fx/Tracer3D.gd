extends Node3D

@export var lifetime: float = 0.06
@export var thickness: float = 0.12

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Bright unshaded material so tracers read clearly.
	if mesh_instance != null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 1.0, 0.95)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mesh_instance.material_override = mat

	# Auto-despawn
	get_tree().create_timer(lifetime).timeout.connect(func() -> void:
		queue_free()
	)

func setup(from: Vector3, to: Vector3) -> void:
	# Draw a thin box between two points.
	var dir: Vector3 = to - from
	var len: float = dir.length()
	if len < 0.001:
		global_position = from
		return
	var mid: Vector3 = from + dir * 0.5
	global_position = mid
	look_at(to, Vector3.UP)

	var bm := mesh_instance.mesh as BoxMesh
	if bm != null:
		bm.size = Vector3(thickness, thickness, len)
	# Make sure it doesn't cast shadows (keeps it cheap/visible)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
