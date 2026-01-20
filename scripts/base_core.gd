extends StaticBody3D
@export var team: int = 0; @export var max_health: int = 2000; var current_health: int
func _ready():
	current_health = max_health; var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0) if team == 0 else Color(0, 0, 1); $MeshInstance3D.material_override = mat
	add_to_group("power_cell")
func take_damage(amount, attacker_team):
	if attacker_team == team: return
	current_health -= amount
	if current_health <= 0: die(attacker_team)
func die(killer_team): NetworkManager.trigger_game_over.rpc(killer_team); queue_free()
