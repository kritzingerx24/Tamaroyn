extends Control
@onready var team_opt = $Panel/VBox/HBoxTeam/TeamOpt; @onready var class_opt = $Panel/VBox/HBoxClass/ClassOpt; @onready var addr_box = $Panel/VBox/Address; @onready var map_opt = $Panel/VBox/HBoxMap/MapOpt; var maps = []
func _ready():
	var loader = preload("res://scripts/map_loader.gd").new(); maps = loader.get_map_list(); map_opt.clear()
	for m in maps: map_opt.add_item(m)
	if maps.size()==0: map_opt.add_item("No Maps Found")
func get_info():
	var map_file = "res://scenes/test_arena_phase26.tscn"
	if maps.size() > 0 and map_opt.selected >= 0: map_file = "res://maps/" + maps[map_opt.selected]
	return {"team": team_opt.selected, "class": class_opt.selected, "map": map_file}
func _on_host_pressed(): NetworkManager.host_game(get_info())
func _on_join_pressed(): var ip=addr_box.text; if ip=="": ip="127.0.0.1"; NetworkManager.join_game(ip, get_info())
