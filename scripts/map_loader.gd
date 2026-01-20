extends Node
const MAP_DIR="res://maps/"
func get_map_list():
	var maps=[]; var dir=DirAccess.open(MAP_DIR)
	if dir:
		dir.list_dir_begin(); var file_name=dir.get_next()
		while file_name!="":
			if !dir.current_is_dir() and (file_name.ends_with(".tscn") or file_name.ends_with(".scn")): maps.append(file_name)
			file_name=dir.get_next()
	return maps
