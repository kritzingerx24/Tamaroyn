extends "res://scripts/turret_ai.gd"
@export var flak_sound: AudioStreamPlayer3D
func _ready(): fire_rate = 0.2; range = 150.0; super._ready(); var mat = StandardMaterial3D.new(); mat.albedo_color = Color(1, 0.5, 0); $BaseMesh.material_override = mat
func find_target():
	var missiles = get_tree().get_nodes_in_group("missile")
	for m in missiles: if "team" in m and m.team != team: if global_position.distance_to(m.global_position) < range: target = m; return
	var players = get_tree().get_nodes_in_group("scout")
	for p in players: if p.team != team and global_position.distance_to(p.global_position) < range: target = p; return
	super.find_target()
func _on_fire():
	if is_instance_valid(target) and multiplayer.is_server():
		var aim_pos = target.global_position
		if "linear_velocity" in target: aim_pos += target.linear_velocity * (global_position.distance_to(aim_pos) / 200.0)
		head.look_at(aim_pos, Vector3.UP); fire_flak_rpc.rpc()
@rpc("call_local") func fire_flak_rpc(): if flak_sound: flak_sound.play(); var p = projectile_scene.instantiate(); p.team = team; p.damage = 10; p.life_time = 0.8; get_tree().root.add_child(p); p.global_transform = muzzle.global_transform; p.linear_velocity = -muzzle.global_transform.basis.z * 200.0
