extends Camera3D

@export var player_path: NodePath
var player

func _ready():
	player = get_node(player_path)

func _process(delta):
	if player:
		global_position.x = player.global_position.x
		global_position.z = player.global_position.z
