# Tamaroyn - Headless server bootstrap.
#
# Usage (example):
#   Godot_v4.5.1-stable_win64.exe --headless --path <ProjectDir> -s res://tools/boot_server.gd -- --port 2456 --map aberdour
#
# The ServerMain scene parses OS.get_cmdline_user_args() in its _ready(), so this script
# just loads that scene and keeps the SceneTree running.

extends SceneTree

const SERVER_SCENE_PATH: String = "res://server/ServerMain.tscn"

func _initialize() -> void:
	if not ResourceLoader.exists(SERVER_SCENE_PATH):
		push_error("Server scene not found: %s" % SERVER_SCENE_PATH)
		quit(1)
		return

	var ps: PackedScene = load(SERVER_SCENE_PATH)
	var root: Node = get_root()
	var inst: Node = ps.instantiate()
	root.add_child(inst)

func _finalize() -> void:
	# Nothing to cleanup.
	pass
