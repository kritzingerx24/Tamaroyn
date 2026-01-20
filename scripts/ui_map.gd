extends Control
@export var grid_path: NodePath; var grid; var local_player_team = 0
func _ready(): grid = get_node(grid_path)
func _process(delta):
	var players = get_tree().get_nodes_in_group("player"); for p in players: if p.is_multiplayer_authority(): local_player_team = p.team; break
	queue_redraw()
func _draw():
	if !grid: return
	var rect_size = size; var cell_w = rect_size.x / grid.grid_size; var cell_h = rect_size.y / grid.grid_size
	for y in range(grid.grid_size):
		for x in range(grid.grid_size):
			var val = grid.grid_data[y * grid.grid_size + x]; var col = Color(0, 0, 0, 0.5)
			if val == 1: col = Color(0.8, 0.1, 0.1, 0.6)
			elif val == 2: col = Color(0.1, 0.3, 0.8, 0.6)
			draw_rect(Rect2(x * cell_w, y * cell_h, cell_w, cell_h), col); draw_rect(Rect2(x * cell_w, y * cell_h, cell_w, cell_h), Color(1,1,1,0.1), false)
	var players = get_tree().get_nodes_in_group("player"); var half_map = (grid.grid_size * grid.sector_size) / 2.0; var map_width = grid.grid_size * grid.sector_size
	for p in players:
		if "team" in p and p.team != local_player_team: if "is_cloaked" in p and p.is_cloaked: continue
		var uv_x = (p.global_position.x + half_map) / map_width; var uv_y = (p.global_position.z + half_map) / map_width
		var blip_pos = Vector2(uv_x * size.x, uv_y * size.y); var p_col = Color.GREEN
		if "team" in p: p_col = Color.RED if p.team == 0 else Color.BLUE
		draw_circle(blip_pos, 4.0, p_col)
