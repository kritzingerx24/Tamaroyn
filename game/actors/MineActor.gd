extends Node3D

@export var interp_speed: float = 12.0

var mine_id: int = -1
var target_pos: Vector3

@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	target_pos = global_position
	_apply_material()

func configure(id: int) -> void:
	mine_id = id

func set_target(pos: Vector3) -> void:
	target_pos = pos

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_pos, 1.0 - exp(-interp_speed * delta))

func _apply_material() -> void:
	if _mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	_mesh.material_override = mat
