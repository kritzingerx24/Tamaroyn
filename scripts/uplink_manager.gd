extends Node3D

@export var tank_path: NodePath
@export var dropship_scene: PackedScene
@export var buildings: Array[PackedScene]

var tank
var is_menu_open = false
signal menu_toggled(is_open)

func _ready(): tank = get_node(tank_path)

func _process(delta):
	if !is_multiplayer_authority(): return
	if !tank.is_in_group("tank"): return
	
	if Input.is_action_just_pressed("toggle_uplink"):
		is_menu_open = !is_menu_open
		emit_signal("menu_toggled", is_menu_open)
	
	if is_menu_open:
		var idx = -1
		if Input.is_action_just_pressed("select_item_1"): idx = 0
		elif Input.is_action_just_pressed("select_item_2"): idx = 1
		elif Input.is_action_just_pressed("select_item_3"): idx = 2
		elif Input.is_action_just_pressed("select_item_4"): idx = 3
		elif Input.is_action_just_pressed("select_item_5"): idx = 4
		elif Input.is_action_just_pressed("select_item_6"): idx = 5
		elif Input.is_action_just_pressed("select_item_7"): idx = 6 
		elif Input.is_action_just_pressed("select_item_8"): idx = 7
		elif Input.is_action_just_pressed("select_item_9"): idx = 8 # Portal
		elif Input.is_action_just_pressed("select_item_10"): idx = 9 # Silo
		
		if idx != -1:
			attempt_spawn(idx)

func attempt_spawn(idx):
	var grid = get_tree().current_scene.get_node("OrbitalGrid")
	if grid:
		var req_val = tank.team + 1
		var aim_pos = tank.get_aim_point()
		var grid_val = grid.get_team_at(aim_pos)
		
		if grid_val == req_val:
			spawn_drop.rpc(aim_pos, idx)
			is_menu_open = false
			emit_signal("menu_toggled", false)

@rpc("call_local", "reliable")
func spawn_drop(pos, cargo_type):
	var ship = dropship_scene.instantiate()
	get_tree().root.add_child(ship)
	ship.setup_delivery(pos, cargo_type)
