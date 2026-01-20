extends Node3D

@export var tank_scene: PackedScene
@export var scout_scene: PackedScene
@export var bot_tank_scene: PackedScene
@export var ui_game_over: Control

var game_active = true
var bot_counter = 100
var red_pads = 0
var blue_pads = 0

# Dynamic Map Bounds
var map_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
var red_base_pos = Vector3.ZERO
var blue_base_pos = Vector3.ZERO

func _ready():
	NetworkManager.game_over.connect(_on_game_over)
	
	if multiplayer.is_server():
		# Wait for map to load
		await get_tree().create_timer(1.0).timeout
		analyze_map()
		setup_bases()
		spawn_player(1, NetworkManager.local_info)
		NetworkManager.player_connected.connect(spawn_player)

func analyze_map():
	print("Analyzing Map Geometry...")
	var container = get_node_or_null("../MapContainer")
	if !container: 
		print("No MapContainer found!")
		return
	
	var combined_aabb = AABB()
	var first = true
	
	# Recursively find meshes to determine size
	var nodes = container.get_children()
	var stack = []
	for n in nodes: stack.append(n)
	
	while stack.size() > 0:
		var node = stack.pop_back()
		stack.append_array(node.get_children())
		
		if node is VisualInstance3D:
			var bounds = node.get_aabb()
			bounds.position += node.global_position
			
			if first:
				combined_aabb = bounds
				first = false
			else:
				combined_aabb = combined_aabb.merge(bounds)
	
	if !first: 
		map_aabb = combined_aabb
		print("Map Bounds: " + str(map_aabb))
	else:
		print("No geometry found, using default bounds.")
	
	# Update Orbital Grid
	var grid = get_node_or_null("../OrbitalGrid")
	if grid:
		if grid.has_method("setup_world_bounds"):
			grid.setup_world_bounds(map_aabb)
		else:
			print("Error: OrbitalGrid script missing setup_world_bounds")

func setup_bases():
	var buffer = 50.0
	var red_target = Vector3(map_aabb.position.x + buffer, 100, map_aabb.position.z + buffer)
	var blue_target = Vector3(map_aabb.end.x - buffer, 100, map_aabb.end.z - buffer)
	
	red_base_pos = get_ground_height(red_target)
	blue_base_pos = get_ground_height(blue_target)
	
	var red_node = get_node_or_null("../Players/RedBase")
	var blue_node = get_node_or_null("../Players/BlueBase")
	
	if red_node: red_node.global_position = red_base_pos
	if blue_node: blue_node.global_position = blue_base_pos

func _process(delta):
	if multiplayer.is_server() and game_active:
		if Input.is_action_just_pressed("spawn_bot_red"):
			spawn_bot(0)
		if Input.is_action_just_pressed("spawn_bot_blue"):
			spawn_bot(1)

func register_pad(t, adding):
	if !multiplayer.is_server(): return
	if t == 0:
		red_pads += 1 if adding else -1
	else:
		blue_pads += 1 if adding else -1
	check_win()

func check_win():
	if !game_active: return
	var players = get_tree().get_nodes_in_group("player")
	var red_live = 0
	var blue_live = 0
	for p in players:
		if "max_health" in p and p.max_health > 0:
			if p.team == 0:
				red_live += 1
			else:
				blue_live += 1
	
	if red_pads <= 0 and red_live == 0:
		NetworkManager.trigger_game_over.rpc(1)
	elif blue_pads <= 0 and blue_live == 0:
		NetworkManager.trigger_game_over.rpc(0)

func spawn_player(id, info):
	if !game_active: return
	
	# SAFETY CHECK
	if tank_scene == null or scout_scene == null:
		print("CRITICAL: Player scenes are null in GameManager!")
		return

	var t = info["team"]
	var p
	if info["class"] == 0:
		p = tank_scene.instantiate()
	else:
		p = scout_scene.instantiate()
		
	p.name = str(id)
	p.team = t
	$Players.add_child(p)
	_find_spawn_point(p)

func spawn_bot(t):
	if !game_active: return
	
	if bot_tank_scene == null:
		print("CRITICAL: Bot scene is null in GameManager")
		return

	var p = bot_tank_scene.instantiate()
	p.name = "Bot_" + str(bot_counter)
	bot_counter += 1
	p.team = t
	$Players.add_child(p)
	_find_spawn_point(p)

func _find_spawn_point(p):
	var pads = get_tree().get_nodes_in_group("repair_pad")
	var team_pads = []
	for x in pads:
		if x.team == p.team:
			team_pads.append(x)
	
	var target = Vector3(0, 50, 0)
	if team_pads.size() > 0:
		target = team_pads.pick_random().global_position + Vector3(0, 5, 0)
	else:
		target = Vector3(randf_range(-100, 100), 50, randf_range(-100, 100))
		
	var g = get_ground_height(target)
	p.global_position = g + Vector3(0, 2, 0)

func get_ground_height(sp):
	var space = get_world_3d().direct_space_state
	var from = Vector3(sp.x, 1000, sp.z)
	var to = Vector3(sp.x, -1000, sp.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result = space.intersect_ray(query)
	if result:
		return result.position
	return Vector3(sp.x, 0, sp.z)

func _on_game_over(w):
	game_active = false
	if ui_game_over:
		ui_game_over.show_winner(w)
	if multiplayer.is_server():
		await get_tree().create_timer(8.0).timeout
		NetworkManager.host_game(NetworkManager.local_info)
