extends Camera3D
@export var target_path: NodePath; @export var smooth_speed: float = 5.0; @export var offset: Vector3 = Vector3(0, 6, 10); var target: Node3D; var shake_amount=0.0
func _ready(): if target_path and has_node(target_path): target = get_node(target_path)
func shake(a): shake_amount=a
func _physics_process(delta):
	if !target: return
	var target_pos = target.global_transform.origin; var target_basis = target.global_transform.basis; var desired_pos = target_pos + (target_basis * offset)
	if shake_amount>0: desired_pos+=Vector3(randf_range(-1,1)*shake_amount, randf_range(-1,1)*shake_amount,0); shake_amount=lerp(shake_amount,0.0,5.0*delta)
	global_transform.origin = global_transform.origin.lerp(desired_pos, smooth_speed * delta); look_at(target_pos + Vector3(0, 1, 0), Vector3.UP)
