extends "res://scripts/building_base.gd"

@export var missile_scene: PackedScene
@export var launch_sound: AudioStreamPlayer3D
@export var launch_interval: float = 15.0

var timer = 0.0

func _ready():
	super._ready()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	$MeshInstance3D.material_override = mat

func _process(delta):
	if !multiplayer.is_server(): return
	
	timer += delta
	if timer > launch_interval:
		timer = 0
		fire_strategic_missile()

func fire_strategic_missile():
	# Find target: Enemy Repair Pad > Power Cell > Turret
	var pads = get_tree().get_nodes_in_group("repair_pad")
	var target = null
	
	for p in pads:
		if p.team != team:
			target = p
			break
			
	if !target:
		var cells = get_tree().get_nodes_in_group("power_cell")
		for c in cells:
			if c.team != team:
				target = c
				break
				
	if target:
		fire_rpc.rpc(target.global_position)

@rpc("call_local")
func fire_rpc(target_pos):
	if launch_sound: launch_sound.play()
	
	var m = missile_scene.instantiate()
	m.team = team
	m.target_pos = target_pos
	get_tree().root.add_child(m)
	m.global_position = global_position + Vector3(0, 10, 0)
	# Eject Up
	m.linear_velocity = Vector3(0, 30, 0)
