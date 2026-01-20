extends StaticBody3D
@export var team: int = 0; @export var max_health: float = 2000.0; var current_health: float
func _ready():
	current_health = max_health; var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0) if team == 0 else Color(0, 0, 1)
	if has_node("MeshInstance3D"): $MeshInstance3D.material_override = mat
	if is_in_group("repair_pad") and multiplayer.is_server():
		var gm = get_tree().current_scene
		if gm.has_method("register_pad"): gm.register_pad(team, true)
func _exit_tree():
	if is_in_group("repair_pad") and multiplayer.is_server():
		var gm = get_tree().current_scene
		if gm.has_method("register_pad"): gm.register_pad(team, false)
func take_damage(amount, attacker_team):
	if attacker_team == team: return
	current_health -= amount
	if current_health <= 0: queue_free()
func repair(amount): if current_health < max_health: current_health += amount
