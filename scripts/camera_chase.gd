extends Camera3D
@export var target_path: NodePath
@export var smooth_speed: float = 5.0
@export var offset: Vector3 = Vector3(0, 6, 10)
var target: Node3D
func _ready():
	if target_path: target = get_node(target_path)
func _physics_process(delta):
	if !target: return
	var target_pos = target.global_transform.origin
	var target_basis = target.global_transform.basis
	var desired_pos = target_pos + (target_basis * offset)
	global_transform.origin = global_transform.origin.lerp(desired_pos, smooth_speed * delta)
	look_at(target_pos + Vector3(0, 1, 0), Vector3.UP)
