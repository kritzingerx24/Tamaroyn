extends "res://scripts/building_base.gd"

@export var warp_sound: AudioStreamPlayer3D
var cooldown_bodies = []

func _ready():
	add_to_group("portal")
	super._ready()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 1, 0.5) # Cyan transparency
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0, 1, 1)
	if has_node("MeshInstance3D"):
		$MeshInstance3D.material_override = mat

func _on_area_body_entered(body):
	if !multiplayer.is_server(): return
	if body in cooldown_bodies: return
	
	if "team" in body and body.team == team:
		teleport(body)

func teleport(body):
	# Find nearest OTHER portal
	var portals = get_tree().get_nodes_in_group("portal")
	var best_portal = null
	var min_dist = 99999.0
	
	for p in portals:
		if p == self: continue
		if p.team != team: continue
		
		var d = global_position.distance_to(p.global_position)
		# We want nearest, or maybe random? Design doc implies travel.
		# Let's go to nearest for now, or cycle.
		if d < min_dist:
			min_dist = d
			best_portal = p
			
	if best_portal:
		# Teleport!
		var exit_pos = best_portal.global_position + (best_portal.transform.basis.z * 5.0) + Vector3(0, 2, 0)
		body.global_position = exit_pos
		
		# Add cooldown to prevent instant bounce back
		best_portal.add_cooldown(body)
		
		play_warp_sound.rpc()

func add_cooldown(body):
	cooldown_bodies.append(body)
	await get_tree().create_timer(3.0).timeout
	cooldown_bodies.erase(body)

@rpc("call_local")
func play_warp_sound():
	if warp_sound: warp_sound.play()
