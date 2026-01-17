extends Node3D

@export var interp_speed: float = 10.0

var peer_id: int = -1
var team: int = 0 # 0=Crimson, 1=Azure

var target_pos: Vector3
var target_yaw: float

const TEX_FALLBACK: Texture2D = preload("res://game/textures/placeholders/metal.png")

# Optional: if you extract Wulfram shapes, we can render a point-cloud silhouette
# using those vertices for more authentic vehicle readability.
const ShapeLib: Script = preload("res://game/wulfram/WulframShapeLibrary.gd")
const PointCloudScript: Script = preload("res://game/wulfram/WulframPointCloud.gd")
var _shape_pc: Node3D = null

# Wulfram-ish scout textures (optional; populated by tools/extract_wulfram_bitmaps.py)
const SCOUT_RED_TEX_CANDIDATES: Array[String] = [
	"res://assets/wulfram_textures/extracted/SC1front.png",
	"res://assets/wulfram_textures/extracted/SC1wing.png",
	"res://assets/wulfram_textures/extracted/SC1jets.png",
]
const SCOUT_BLUE_TEX_CANDIDATES: Array[String] = [
	"res://assets/wulfram_textures/extracted/SC2front.png",
	"res://assets/wulfram_textures/extracted/SC2back.png",
	"res://assets/wulfram_textures/extracted/SC2wingtpfront.png",
]

@onready var _label: Label3D = $Label3D
@onready var _marker: MeshInstance3D = $TargetMarker

var _paint_meshes: Array[MeshInstance3D] = []

func vehicle_kind() -> String:
	return "scout"

func _ready() -> void:
	target_pos = global_position
	target_yaw = rotation.y
	_collect_paint_meshes()
	_update_label()
	_apply_team_materials()
	_maybe_enable_wulfram_shape()

func configure(id: int, team_id: int) -> void:
	peer_id = id
	team = team_id
	_update_label()
	_apply_team_materials()
	_maybe_enable_wulfram_shape()

func set_target(pos: Vector3, yaw: float) -> void:
	target_pos = pos
	target_yaw = yaw

func set_targeted(v: bool) -> void:
	if _marker != null:
		_marker.visible = v

func _process(delta: float) -> void:
	global_position = global_position.lerp(target_pos, clamp(interp_speed * delta, 0.0, 1.0))
	var cur: float = rotation.y
	var diff: float = wrapf(target_yaw - cur, -PI, PI)
	rotation.y = cur + diff * clamp(interp_speed * delta, 0.0, 1.0)

func _update_label() -> void:
	if _label == null:
		return
	_label.text = str(peer_id)

func _collect_paint_meshes() -> void:
	_paint_meshes.clear()
	for c: Node in get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c as MeshInstance3D
			if mi.name != "TargetMarker":
				_paint_meshes.append(mi)

func _pick_team_texture() -> Texture2D:
	var candidates: Array[String] = SCOUT_RED_TEX_CANDIDATES if team == 0 else SCOUT_BLUE_TEX_CANDIDATES
	for p: String in candidates:
		if ResourceLoader.exists(p):
			var res: Resource = load(p)
			if res is Texture2D:
				return res as Texture2D

	# fallback to extracted metal
	var metal_path: String = "res://assets/wulfram_textures/extracted/dark-grey_44.png"
	if ResourceLoader.exists(metal_path):
		var res2: Resource = load(metal_path)
		if res2 is Texture2D:
			return res2 as Texture2D
	return TEX_FALLBACK

func _apply_team_materials() -> void:
	if _paint_meshes.is_empty():
		return

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.albedo_texture = _pick_team_texture()
	mat.albedo_color = Color(1.0, 0.75, 0.7) if team == 0 else Color(0.7, 0.9, 1.0)
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)

	for mi: MeshInstance3D in _paint_meshes:
		if mi != null:
			mi.material_override = mat

	if _marker != null:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.95, 0.25)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.65
		_marker.material_override = m


func _desired_shape_name() -> String:
	# Wulfram has multiple scout shapes; we use a simple team mapping.
	return "scout_1" if team == 0 else "scout_2"

func _maybe_enable_wulfram_shape() -> void:
	var desired: String = _desired_shape_name()

	# If already enabled, just update shape + team tint.
	if _shape_pc != null and is_instance_valid(_shape_pc):
		if _shape_pc.has_method("configure"):
			_shape_pc.call("configure", desired, team)
			_shape_pc.set("point_size", 0.075)
			_shape_pc.set("max_points", 5500)
		return

	if not ShapeLib.shapes_ready():
		return

	var shape: String = desired
	if not ShapeLib.has_shape(shape):
		# Fallback: at least show some scout silhouette.
		shape = "scout_1"
		if not ShapeLib.has_shape(shape):
			return

	var pc: Node3D = PointCloudScript.new()
	pc.set("shape_name", shape)
	pc.set("team", team)
	pc.set("point_size", 0.075)
	pc.set("max_points", 5500)
	add_child(pc)
	_shape_pc = pc

	for mi: MeshInstance3D in _paint_meshes:
		if mi != null:
			mi.visible = false
