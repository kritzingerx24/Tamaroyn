@tool
extends EditorPlugin

const MapBuilder := preload("res://addons/wulfram_importer/wulfram_map_builder.gd")

var _import_dialog: EditorFileDialog = null

const MENU_TEXT := "Wulfram -> Import Map (choose land file)..."

func _enter_tree() -> void:
	add_tool_menu_item(MENU_TEXT, Callable(self, "_on_import_map_pressed"))

func _exit_tree() -> void:
	remove_tool_menu_item(MENU_TEXT)
	if is_instance_valid(_import_dialog):
		_import_dialog.queue_free()
	_import_dialog = null

func _on_import_map_pressed() -> void:
	if not is_instance_valid(_import_dialog):
		_import_dialog = EditorFileDialog.new()
		_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_import_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_import_dialog.title = "Select a Wulfram map 'land' file"
		_import_dialog.filters = PackedStringArray(["*"]) # file is literally named "land"
		_import_dialog.file_selected.connect(Callable(self, "_on_land_selected"))
		get_editor_interface().get_base_control().add_child(_import_dialog)

	_import_dialog.popup_centered_ratio(0.7)

func _on_land_selected(res_path: String) -> void:
	var land_path: String = res_path
	var base_dir: String = res_path.get_base_dir()
	var state_path: String = base_dir.path_join("state")
	var map_name: String = base_dir.get_file()

	var root := Node3D.new()
	root.name = "WulframMap_%s" % map_name

	var err: int = MapBuilder.build_map_from_files(land_path, state_path, root, map_name)
	if err != OK:
		push_error("Wulfram import failed. Error=%s" % str(err))
		return

	# Pack + Save
	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		push_error("PackedScene.pack failed. Error=%s" % str(pack_err))
		return

	var out_dir := "res://imported_maps"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var out_scene_path := "%s/%s.tscn" % [out_dir, map_name]
	var save_err: int = ResourceSaver.save(packed, out_scene_path)
	if save_err != OK:
		push_error("ResourceSaver.save failed. Error=%s Path=%s" % [str(save_err), out_scene_path])
		return

	push_warning("Saved map scene: %s" % out_scene_path)
	get_editor_interface().get_resource_filesystem().scan()
