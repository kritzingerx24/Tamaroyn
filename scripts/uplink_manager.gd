extends Node3D
@export var tank_path: NodePath
@export var dropship_scene: PackedScene
@export var buildings: Array[PackedScene]
var tank; var is_menu_open=false; signal menu_toggled(o)
func _ready(): tank = get_node(tank_path)
func _process(d):
	if Input.is_action_just_pressed("toggle_uplink"): is_menu_open=!is_menu_open; emit_signal("menu_toggled", is_menu_open)
	if is_menu_open and Input.is_action_just_pressed("select_weapon_1"): 
		var ship = dropship_scene.instantiate(); get_tree().root.add_child(ship); ship.setup_delivery(tank.get_aim_point(), buildings[0])
		is_menu_open=false; emit_signal("menu_toggled",false)
