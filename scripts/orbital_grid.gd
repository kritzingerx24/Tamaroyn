extends Node

var grid_data: PackedByteArray = PackedByteArray()
var grid_size: int = 32
var sector_size: float = 50.0

@export var sync_data: PackedByteArray : set = _on_sync_data_changed

var map_origin: Vector2 = Vector2.ZERO
var map_width: float = 1600.0
var map_depth: float = 1600.0

var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 2.0
var map_image: Image
var map_texture: ImageTexture
signal grid_updated(texture)

func _ready():
	grid_data.resize(grid_size * grid_size)
	grid_data.fill(0)
	map_image = Image.create(grid_size, grid_size, false, Image.FORMAT_R8)
	map_texture = ImageTexture.create_from_image(map_image)

# THIS METHOD MUST EXIST FOR GAMEMANAGER TO CALL IT
func setup_world_bounds(aabb: AABB):
	map_origin = Vector2(aabb.position.x, aabb.position.z)
	map_width = aabb.size.x
	map_depth = aabb.size.z
	
	var max_dim = max(map_width, map_depth)
	if max_dim <= 0: max_dim = 1000.0 # Safety
	
	sector_size = max_dim / float(grid_size)
	
	print("Grid configured: Origin " + str(map_origin) + " SectorSize " + str(sector_size))
	
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.is_multiplayer_authority():
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("setup_radar"):
				var center = Vector3(map_origin.x + map_width/2.0, 0, map_origin.y + map_depth/2.0)
				hud.setup_radar(center, max_dim)

	if multiplayer.is_server():
		grid_data.fill(0)
		set_sector_at(Vector3(map_origin.x + 10, 0, map_origin.y + 10), 1)
		set_sector_at(Vector3(map_origin.x + map_width - 10, 0, map_origin.y + map_depth - 10), 2)
		sync_data = grid_data

func _process(delta):
	if multiplayer.is_server():
		update_timer += delta
		if update_timer > UPDATE_INTERVAL:
			update_timer = 0
			run_simulation()
			sync_data = grid_data

func run_simulation():
	var new_grid = grid_data.duplicate()
	var cells = get_tree().get_nodes_in_group("power_cell")
	var skypumps = get_tree().get_nodes_in_group("skypump")
	
	for pc in cells:
		_claim_radius(new_grid, pc.global_position, pc.team + 1, 1)
	for sp in skypumps:
		_claim_radius(new_grid, sp.global_position, sp.team + 1, 3)

	var final_grid = new_grid.duplicate()
	for y in range(grid_size):
		for x in range(grid_size):
			var idx = y * grid_size + x
			var current = new_grid[idx]
			if current == 0: continue
			
			if _is_pos_anchored(x, y, cells, skypumps):
				continue
			
			var enemies = 0
			var neighbors = get_neighbors(x, y, new_grid)
			for n_val in neighbors:
				if n_val != 0 and n_val != current:
					enemies += 1
			
			if enemies >= 2:
				final_grid[idx] = 0
				
	grid_data = final_grid

func _claim_radius(grid_ref, world_pos, val, radius_sectors):
	var center = get_grid_coords(world_pos)
	if center.x == -1: return
	var r = int(radius_sectors / 2.0)
	if radius_sectors == 1: r = 0
	
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if x >= 0 and x < grid_size and y >= 0 and y < grid_size:
				grid_ref[y * grid_size + x] = val

func _is_pos_anchored(gx, gy, pcs, sps):
	var w_pos = get_world_pos(gx, gy)
	var w_vec2 = Vector2(w_pos.x, w_pos.z)
	for pc in pcs:
		if Vector2(pc.global_position.x, pc.global_position.z).distance_to(w_vec2) < sector_size * 0.8:
			return true
	for sp in sps:
		if Vector2(sp.global_position.x, sp.global_position.z).distance_to(w_vec2) < sector_size * 2.5:
			return true
	return false

func get_neighbors(cx, cy, grid):
	var list = []
	for y in range(cy-1, cy+2):
		for x in range(cx-1, cx+2):
			if x == cx and y == cy: continue
			if x >= 0 and x < grid_size and y >= 0 and y < grid_size:
				list.append(grid[y * grid_size + x])
	return list

func set_sector_at(pos: Vector3, val: int):
	var coords = get_grid_coords(pos)
	if coords.x != -1:
		grid_data[coords.y * grid_size + coords.x] = val
		if multiplayer.is_server():
			sync_data = grid_data

func get_team_at(pos: Vector3) -> int:
	var coords = get_grid_coords(pos)
	if coords.x == -1: return 0
	return grid_data[coords.y * grid_size + coords.x]

func get_grid_coords(pos: Vector3) -> Vector2i:
	var x_pct = (pos.x - map_origin.x) / map_width
	var y_pct = (pos.z - map_origin.y) / map_depth
	var x = int(x_pct * grid_size)
	var y = int(y_pct * grid_size)
	if x >= 0 and x < grid_size and y >= 0 and y < grid_size:
		return Vector2i(x, y)
	return Vector2i(-1, -1)

func get_world_pos(gx, gy) -> Vector3:
	var x = (float(gx) / grid_size) * map_width + map_origin.x
	var z = (float(gy) / grid_size) * map_depth + map_origin.y
	return Vector3(x + (sector_size/2.0), 0, z + (sector_size/2.0))

func _on_sync_data_changed(val):
	grid_data = val
	update_texture()

func update_texture():
	for i in range(grid_data.size()):
		var val = grid_data[i]
		var color_val = 0
		if val == 1: color_val = 100
		elif val == 2: color_val = 200
		map_image.set_pixel(i % grid_size, i / grid_size, Color8(color_val, 0, 0))
	map_texture.update(map_image)
	emit_signal("grid_updated", map_texture)
