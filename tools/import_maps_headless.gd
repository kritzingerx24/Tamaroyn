extends SceneTree

const BUILDER := preload("res://addons/wulfram_importer/wulfram_map_builder.gd")

func _init() -> void:
	var cfg: Dictionary = _parse_args(OS.get_cmdline_user_args())

	var data_root: String = str(cfg.get("data_root", ""))
	if data_root == "":
		data_root = "res://wulfram_data"

	var out_root: String = str(cfg.get("out_root", "res://imported_maps"))
	var maps_csv: String = str(cfg.get("maps", ""))

	var maps_root: String = _resolve_maps_root(data_root)
	if maps_root == "":
		push_error("Could not find maps root. Expected either <data_root>/maps or <data_root>/data/maps. data_root=" + data_root)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_root))

	var maps: PackedStringArray = PackedStringArray()
	if maps_csv != "":
		for m in maps_csv.split(",", false):
			maps.append(m.strip_edges())
	else:
		maps = _list_map_folders(maps_root)

	if maps.is_empty():
		push_error("No maps found under: " + maps_root)
		quit(1)
		return

	var ok_count: int = 0
	var fail_count: int = 0

	for map_name in maps:
		var map_dir: String = maps_root.path_join(map_name)
		var land_path: String = map_dir.path_join("land")
		var state_path: String = map_dir.path_join("state")

		if not FileAccess.file_exists(land_path):
			push_warning("Skipping (no land): " + land_path)
			continue

		var root := Node3D.new()
		root.name = "WulframMap_%s" % map_name

		var build_err: int = BUILDER.build_map_from_files(land_path, state_path, root, map_name)
		if build_err != OK:
			push_error("Build failed map=" + map_name + " err=" + str(build_err))
			fail_count += 1
			continue

		# Pack + Save (IMPORTANT: pack() returns Error int)
		var packed := PackedScene.new()
		var pack_err: int = packed.pack(root)
		if pack_err != OK:
			push_error("Pack failed map=" + map_name + " err=" + str(pack_err))
			fail_count += 1
			continue

		var out_scene_path: String = out_root.path_join(map_name + ".tscn")
		var save_err: int = ResourceSaver.save(packed, out_scene_path)
		if save_err != OK:
			push_error("Save failed map=" + map_name + " err=" + str(save_err) + " path=" + out_scene_path)
			fail_count += 1
			continue

		print("Saved: " + out_scene_path)
		ok_count += 1

	print("Import complete. ok=%d fail=%d" % [ok_count, fail_count])
	quit(0)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var d: Dictionary = {}
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--"):
			var key: String = a.substr(2)
			var val: String = ""
			if i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
				val = str(args[i + 1])
				i += 1
			d[key] = val
		i += 1
	return d

func _resolve_maps_root(data_root: String) -> String:
	# Accept either:
	#   res://wulfram_data/maps/<map>
	# OR
	#   res://wulfram_data/data/maps/<map>
	var a: String = data_root.path_join("maps")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(a)):
		return a
	var b: String = data_root.path_join("data").path_join("maps")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(b)):
		return b
	return ""

func _list_map_folders(maps_root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(maps_root)
	if da == null:
		return out
	da.list_dir_begin()
	while true:
		var name := da.get_next()
		if name == "":
			break
		if da.current_is_dir() and not name.begins_with("."):
			out.append(name)
	da.list_dir_end()
	out.sort()
	return out
