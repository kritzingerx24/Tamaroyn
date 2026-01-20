extends StaticBody3D
@export var team: int = 0; @export var range: float = 100.0; @export var fire_rate: float = 1.0
@onready var head = $Head; @onready var muzzle = $Head/Muzzle; @onready var timer = $Timer
@export var projectile_scene: PackedScene; var target = null
func _ready(): timer.wait_time = fire_rate; timer.timeout.connect(_on_fire); timer.start(); var mat = StandardMaterial3D.new(); mat.albedo_color = Color(1,0,0) if team == 0 else Color(0,0,1); $BaseMesh.material_override = mat
func _process(delta):
	if !is_instance_valid(target): find_target()
	else: head.look_at(target.global_position, Vector3.UP); if global_position.distance_to(target.global_position) > range: target = null
func find_target():
	var nodes = get_tree().get_nodes_in_group("player")
	for n in nodes: 
		if n.team != team:
			if "is_cloaked" in n and n.is_cloaked: continue
			if global_position.distance_to(n.global_position) < range: target = n; return
func _on_fire(): if is_instance_valid(target) and multiplayer.is_server(): fire_rpc.rpc()
@rpc("call_local") func fire_rpc(): var p = projectile_scene.instantiate(); p.team = team; get_tree().root.add_child(p); p.global_transform = muzzle.global_transform; p.linear_velocity = -muzzle.global_transform.basis.z * 80.0
func take_damage(amt, atk): if atk != team: queue_free()
