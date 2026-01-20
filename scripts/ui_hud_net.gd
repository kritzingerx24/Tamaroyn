extends Control

@export var player_path: NodePath
var player

@onready var status_lbl = $BottomBar/CenterPanel/StatusLabel
@onready var radar_cam = $BottomBar/LeftPanel/RadarContainer/SubViewport/RadarCamera
@onready var lock_ui = $LockIndicator
@onready var hit_marker = $CenterContainer/HitMarker

func _ready():
	# Default radar position if map isn't ready
	radar_cam.size = 200.0

func setup_radar(center_pos: Vector3, size: float):
	radar_cam.global_position = center_pos + Vector3(0, 100, 0)
	radar_cam.size = size # Orthographic Size
	# Ensure it looks down
	radar_cam.look_at(center_pos, Vector3.FORWARD) # Wait, UP is Z in top-down?
	# Standard top down:
	radar_cam.rotation_degrees = Vector3(-90, 0, 0)

func _process(delta):
	if !player:
		var nodes = get_tree().get_nodes_in_group("player")
		for n in nodes:
			if n.is_multiplayer_authority():
				player = n
				break
	
	if player:
		_update_hud()
		_update_lock()

func _update_hud():
	var info = ""
	info += "HP: " + str(player.max_health) + " | ENG: " + str(int(player.current_energy)) + "\n"
	
	var ws = player.get_node("WeaponSystem")
	var slot = player.selected_slot
	var w_name = "WEAPON"
	if "weapon_names" in player: w_name = player.weapon_names[slot]
	var ammo = 0
	if ws and "ammo_counts" in ws: ammo = ws.ammo_counts.get(slot, 0)
	
	info += w_name + ": " + str(ammo) + " | "
	
	var txt="EMPTY"
	if "carried_cargo" in player:
		var c = player.carried_cargo
		if c==0: txt="POWER"
		elif c==1: txt="TURRET"
		elif c==2: txt="REPAIR"
		elif c==3: txt="DARK"
		elif c==4: txt="REFUEL"
		elif c==5: txt="FLAK"
		elif c==6: txt="SKYPUMP"
		elif c==7: txt="MISSILE"
		elif c==8: txt="PORTAL"
		elif c==9: txt="SILO"
	info += "CARGO: " + txt
	
	status_lbl.text = info

func _update_lock():
	var ws = player.get_node("WeaponSystem")
	if ws and ws.locked_target:
		lock_ui.visible = true
		var cam = get_viewport().get_camera_3d()
		if cam and !cam.is_position_behind(ws.locked_target.global_position):
			lock_ui.position = cam.unproject_position(ws.locked_target.global_position)
		else: lock_ui.visible = false
	else: lock_ui.visible = false

func flash_crosshair():
	hit_marker.visible = true
	await get_tree().create_timer(0.1).timeout
	hit_marker.visible = false
