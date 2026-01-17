extends Node3D

# Placeholder renderer for Wulfram shapes.
#
# v1  : point-cloud silhouettes (MultiMesh of tiny cubes).
# v2  : best-effort triangulated meshes (ArrayMesh) using decoded triangle indices.
# v2.1: multi-surface + projected UVs (bucketed by face normal) for more Wulfram-like texturing.
# v2.4: when per-triangle material IDs are available, split surfaces by material id.
#       (Still falls back to normal-buckets when mat IDs are missing.)
#
# IMPORTANT: Keep this file strictly typed. Some build setups treat certain GDScript
# warnings (especially Variant inference) as errors.

@export var shape_name: String = ""
@export var team: int = 0 # 0=Crimson, 1=Azure, 2=Neutral

@export var prefer_trimesh: bool = true

# LOD: render TriMesh nearby, point-cloud farther away. (Client-side visuals only.)
@export var enable_lod: bool = true
@export var lod_mesh_end: float = 90.0
@export var lod_points_begin: float = 80.0
@export var lod_points_end: float = 260.0
@export var lod_points_max_points: int = 900

# Performance: cap triangles used to build the placeholder mesh (0 = no cap).
@export var mesh_triangle_cap: int = 0

# Projected UV tiling (higher = smaller texture features).
@export var uv_scale: float = 1.0

# Rendering flags for placeholder visuals.
@export var unshaded: bool = true
@export var disable_culling: bool = true

# Point-cloud fallback controls.
@export var point_size: float = 0.10
@export var max_points: int = 0 # 0 = no cap
@export var neutral_tint: Color = Color(1.0, 1.0, 0.35)

const ShapeLib: Script = preload("res://game/wulfram/WulframShapeLibrary.gd")

# Face buckets (based on triangle normal) for UV projection & fallback texture selection.
const BUCKET_TOP: int = 0
const BUCKET_BOTTOM: int = 1
const BUCKET_LEFT: int = 2
const BUCKET_RIGHT: int = 3
const BUCKET_FRONT: int = 4
const BUCKET_BACK: int = 5
const BUCKET_OTHER: int = 6

const SURFACE_MODE_BUCKETS: int = 0
const SURFACE_MODE_MATIDS: int = 1


class MeshGeomCacheEntry:
	# surface_ids is either bucket indices (SURFACE_MODE_BUCKETS) or material IDs (SURFACE_MODE_MATIDS).
	var mesh: ArrayMesh
	var surface_mode: int
	var surface_ids: PackedInt32Array

	func _init(p_mesh: ArrayMesh = null, p_surface_mode: int = SURFACE_MODE_BUCKETS, p_surface_ids: PackedInt32Array = PackedInt32Array()) -> void:
		mesh = p_mesh
		surface_mode = p_surface_mode
		surface_ids = p_surface_ids


static var _mesh_geom_cache: Dictionary[String, MeshGeomCacheEntry] = {}
static var _point_mm_cache: Dictionary[String, MultiMesh] = {}
static var _bucket_material_cache: Dictionary[String, StandardMaterial3D] = {}
static var _matid_material_cache: Dictionary[String, StandardMaterial3D] = {}
static var _pc_material_cache: Dictionary[int, StandardMaterial3D] = {}


static func clear_render_cache() -> void:
	_mesh_geom_cache.clear()
	_point_mm_cache.clear()
	_bucket_material_cache.clear()
	_matid_material_cache.clear()
	_pc_material_cache.clear()


var _mmi: MultiMeshInstance3D = null
var _mesh_inst: MeshInstance3D = null


func _ready() -> void:
	add_to_group("wulfram_pointcloud")
	rebuild()


func configure(p_shape_name: String, p_team: int) -> void:
	shape_name = p_shape_name
	team = p_team
	rebuild()


func reload_from_library() -> void:
	# Convenience for hot-reload (e.g., after running the extractor while the game is open).
	rebuild()


func rebuild() -> void:
	_clear_nodes()

	if shape_name.is_empty():
		return
	if not ShapeLib.has_shape(shape_name):
		return

	var verts: PackedVector3Array = ShapeLib.get_vertices(shape_name)
	if verts.is_empty():
		return

	var built_mesh: bool = false
	if prefer_trimesh:
		var tris: PackedInt32Array = ShapeLib.get_triangles(shape_name)
		if tris.size() >= 3:
			var tri_mats: PackedInt32Array = ShapeLib.get_triangle_material_ids(shape_name)
			built_mesh = _build_trimesh_v24(verts, tris, tri_mats)
			if built_mesh and enable_lod:
				_build_pointcloud_lod(verts)
			if built_mesh:
				return

	_build_pointcloud_fallback(verts)


func _clear_nodes() -> void:
	if _mmi != null and is_instance_valid(_mmi):
		_mmi.queue_free()
	_mmi = null

	if _mesh_inst != null and is_instance_valid(_mesh_inst):
		_mesh_inst.queue_free()
		_mesh_inst = null


func _build_trimesh_v24(verts: PackedVector3Array, tris: PackedInt32Array, tri_mats: PackedInt32Array) -> bool:
	var use_tris: PackedInt32Array = tris
	if mesh_triangle_cap > 0:
		use_tris = _decimate_triangles(tris, mesh_triangle_cap)
		if use_tris.size() < 3:
			use_tris = tris

	var tri_count: int = int(use_tris.size() / 3)
	var mats: PackedStringArray = ShapeLib.get_materials(shape_name)
	var mat_count: int = mats.size()

	# Use mat-id surface splitting only if the decode produced a plausible per-triangle mat stream.
	var use_mat_ids: bool = false
	if tri_mats.size() == tri_count and mat_count > 0:
		var info: Dictionary = ShapeLib.get_decode_info(shape_name)
		if info.has("uses_mat_ids"):
			use_mat_ids = bool(info["uses_mat_ids"])
		else:
			use_mat_ids = true

	var key: String = _mesh_cache_key(shape_name, uv_scale, mesh_triangle_cap, use_mat_ids)
	var entry: MeshGeomCacheEntry = null
	if _mesh_geom_cache.has(key):
		entry = _mesh_geom_cache[key]
	else:
		entry = _build_mesh_geom_entry(verts, use_tris, tri_mats, mat_count, use_mat_ids)
		if entry == null or entry.mesh == null or entry.mesh.get_surface_count() == 0:
			return false
		_mesh_geom_cache[key] = entry

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = entry.mesh
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if enable_lod and lod_mesh_end > 0.0:
		_mesh_inst.visibility_range_begin = 0.0
		_mesh_inst.visibility_range_end = lod_mesh_end

	# Assign per-surface materials.
	var sidx: int = 0
	while sidx < entry.surface_ids.size() and sidx < entry.mesh.get_surface_count():
		var sid: int = int(entry.surface_ids[sidx])
		if entry.surface_mode == SURFACE_MODE_MATIDS:
			_mesh_inst.set_surface_override_material(sidx, _get_matid_material_cached(shape_name, mats, sid))
		else:
			_mesh_inst.set_surface_override_material(sidx, _get_bucket_material_cached(shape_name, mats, sid))
		sidx += 1

	add_child(_mesh_inst)
	return true


static func _mesh_cache_key(p_shape: String, p_uv_scale: float, p_cap: int, p_use_mat_ids: bool) -> String:
	var uv_q: int = int(round(p_uv_scale * 1000.0))
	var mode: int = 1 if p_use_mat_ids else 0
	return "%s|uv=%d|cap=%d|mat=%d" % [p_shape, uv_q, p_cap, mode]


func _build_mesh_geom_entry(verts: PackedVector3Array, tris: PackedInt32Array, tri_mats: PackedInt32Array, mat_count: int, use_mat_ids: bool) -> MeshGeomCacheEntry:
	# Compute bounds (verts are already normalized/centered in the library).
	var minv: Vector3 = Vector3(INF, INF, INF)
	var maxv: Vector3 = Vector3(-INF, -INF, -INF)
	for v: Vector3 in verts:
		minv = Vector3(min(minv.x, v.x), min(minv.y, v.y), min(minv.z, v.z))
		maxv = Vector3(max(maxv.x, v.x), max(maxv.y, v.y), max(maxv.z, v.z))

	var eps_area: float = 0.0000001
	var mesh: ArrayMesh = ArrayMesh.new()
	var surface_ids: PackedInt32Array = PackedInt32Array()

	if use_mat_ids:
		# Build one surface per material id (plus a fallback surface id = -1).
		var tools: Dictionary[int, SurfaceTool] = {}
		var counts: Dictionary[int, int] = {}

		var tri_idx: int = 0
		var i: int = 0
		while (i + 2) < tris.size():
			var a: int = tris[i + 0]
			var b: int = tris[i + 1]
			var c: int = tris[i + 2]
			i += 3

			if a < 0 or b < 0 or c < 0:
				tri_idx += 1
				continue
			if a >= verts.size() or b >= verts.size() or c >= verts.size():
				tri_idx += 1
				continue
			if a == b or b == c or a == c:
				tri_idx += 1
				continue

			var va: Vector3 = verts[a]
			var vb: Vector3 = verts[b]
			var vc: Vector3 = verts[c]

			var n: Vector3 = (vb - va).cross(vc - va)
			var area2: float = n.length()
			if area2 <= eps_area:
				tri_idx += 1
				continue
			var normal: Vector3 = n / area2
			var bucket: int = _bucket_for_normal(normal)

			var mid: int = -1
			if tri_mats.size() > tri_idx:
				mid = int(tri_mats[tri_idx])
			if mid < 0 or mid >= mat_count:
				mid = -1

			if not tools.has(mid):
				var st: SurfaceTool = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mid] = st
				counts[mid] = 0

			var st2: SurfaceTool = tools[mid]
			# Flat-shaded face: duplicate verts with the same normal.
			var uva: Vector2 = _project_uv(bucket, va, minv, maxv)
			var uvb: Vector2 = _project_uv(bucket, vb, minv, maxv)
			var uvc: Vector2 = _project_uv(bucket, vc, minv, maxv)

			st2.add_normal(normal)
			st2.add_uv(uva)
			st2.add_vertex(va)

			st2.add_normal(normal)
			st2.add_uv(uvb)
			st2.add_vertex(vb)

			st2.add_normal(normal)
			st2.add_uv(uvc)
			st2.add_vertex(vc)

			counts[mid] = int(counts[mid]) + 1
			tri_idx += 1

		# Commit surfaces in a stable order: 0..mat_count-1 then -1.
		var order: Array[int] = []
		for k in tools.keys():
			order.append(int(k))
		order.sort()
		# Ensure -1 comes last.
		if order.has(-1):
			order.erase(-1)
			order.append(-1)

		for mid2: int in order:
			var tri_ct: int = int(counts.get(mid2, 0))
			if tri_ct <= 0:
				continue
			var st3: SurfaceTool = tools[mid2]
			st3.commit(mesh)
			surface_ids.append(mid2)

		return MeshGeomCacheEntry.new(mesh, SURFACE_MODE_MATIDS, surface_ids)

	# Fallback: bucketed-by-normal surfaces (v2.1 behavior).
	var bucket_tools: Dictionary[int, SurfaceTool] = {}
	var bucket_counts: Dictionary[int, int] = {}
	for bkt: int in [BUCKET_TOP, BUCKET_BOTTOM, BUCKET_LEFT, BUCKET_RIGHT, BUCKET_FRONT, BUCKET_BACK, BUCKET_OTHER]:
		var st0: SurfaceTool = SurfaceTool.new()
		st0.begin(Mesh.PRIMITIVE_TRIANGLES)
		bucket_tools[bkt] = st0
		bucket_counts[bkt] = 0

	var j: int = 0
	while (j + 2) < tris.size():
		var a2: int = tris[j + 0]
		var b2: int = tris[j + 1]
		var c2: int = tris[j + 2]
		j += 3

		if a2 < 0 or b2 < 0 or c2 < 0:
			continue
		if a2 >= verts.size() or b2 >= verts.size() or c2 >= verts.size():
			continue
		if a2 == b2 or b2 == c2 or a2 == c2:
			continue

		var va2: Vector3 = verts[a2]
		var vb2: Vector3 = verts[b2]
		var vc2: Vector3 = verts[c2]

		var n2: Vector3 = (vb2 - va2).cross(vc2 - va2)
		var area22: float = n2.length()
		if area22 <= eps_area:
			continue

		var normal2: Vector3 = n2 / area22
		var bucket2: int = _bucket_for_normal(normal2)
		var st4: SurfaceTool = bucket_tools[bucket2]

		var uva2: Vector2 = _project_uv(bucket2, va2, minv, maxv)
		var uvb2: Vector2 = _project_uv(bucket2, vb2, minv, maxv)
		var uvc2: Vector2 = _project_uv(bucket2, vc2, minv, maxv)

		st4.add_normal(normal2)
		st4.add_uv(uva2)
		st4.add_vertex(va2)

		st4.add_normal(normal2)
		st4.add_uv(uvb2)
		st4.add_vertex(vb2)

		st4.add_normal(normal2)
		st4.add_uv(uvc2)
		st4.add_vertex(vc2)

		bucket_counts[bucket2] = int(bucket_counts[bucket2]) + 1

	var bucket_order: Array[int] = [BUCKET_TOP, BUCKET_BOTTOM, BUCKET_LEFT, BUCKET_RIGHT, BUCKET_FRONT, BUCKET_BACK, BUCKET_OTHER]
	for b3: int in bucket_order:
		var tri_ct2: int = int(bucket_counts[b3])
		if tri_ct2 <= 0:
			continue
		var st5: SurfaceTool = bucket_tools[b3]
		st5.commit(mesh)
		surface_ids.append(b3)

	return MeshGeomCacheEntry.new(mesh, SURFACE_MODE_BUCKETS, surface_ids)


static func _decimate_triangles(tris: PackedInt32Array, cap_tris: int) -> PackedInt32Array:
	if cap_tris <= 0:
		return tris
	var tri_count: int = int(tris.size() / 3)
	if tri_count <= cap_tris:
		return tris

	var stride: int = int(ceil(float(tri_count) / float(cap_tris)))
	stride = max(1, stride)

	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t < tri_count and int(out.size() / 3) < cap_tris:
		var base: int = t * 3
		out.append(tris[base + 0])
		out.append(tris[base + 1])
		out.append(tris[base + 2])
		t += stride
	return out


func _bucket_for_normal(n: Vector3) -> int:
	var ax: float = abs(n.x)
	var ay: float = abs(n.y)
	var az: float = abs(n.z)

	if ay >= ax and ay >= az:
		return BUCKET_TOP if n.y >= 0.0 else BUCKET_BOTTOM
	if ax >= az:
		return BUCKET_RIGHT if n.x >= 0.0 else BUCKET_LEFT
	return BUCKET_FRONT if n.z >= 0.0 else BUCKET_BACK


func _project_uv(bucket: int, v: Vector3, minv: Vector3, maxv: Vector3) -> Vector2:
	var sx: float = max(0.0001, maxv.x - minv.x)
	var sy: float = max(0.0001, maxv.y - minv.y)
	var sz: float = max(0.0001, maxv.z - minv.z)

	var u: float = 0.0
	var t: float = 0.0

	if bucket == BUCKET_TOP or bucket == BUCKET_BOTTOM:
		u = (v.x - minv.x) / sx
		t = (v.z - minv.z) / sz
	elif bucket == BUCKET_LEFT or bucket == BUCKET_RIGHT:
		u = (v.z - minv.z) / sz
		t = (v.y - minv.y) / sy
	elif bucket == BUCKET_FRONT or bucket == BUCKET_BACK:
		u = (v.x - minv.x) / sx
		t = (v.y - minv.y) / sy
	else:
		u = (v.x - minv.x) / sx
		t = (v.z - minv.z) / sz

	# Apply tiling.
	u = clamp(u, 0.0, 1.0) * uv_scale
	t = clamp(t, 0.0, 1.0) * uv_scale

	return Vector2(u, t)


func _get_bucket_material_cached(p_shape_name: String, mats: PackedStringArray, bucket: int) -> StandardMaterial3D:
	var key: String = "%s|b=%d|team=%d|unsh=%d|cull=%d" % [p_shape_name, bucket, team, int(unshaded), int(disable_culling)]
	if _bucket_material_cache.has(key):
		return _bucket_material_cache[key]
	var m: StandardMaterial3D = _make_bucket_material(p_shape_name, mats, bucket)
	_bucket_material_cache[key] = m
	return m


func _get_matid_material_cached(p_shape_name: String, mats: PackedStringArray, mat_id: int) -> StandardMaterial3D:
	var key: String = "%s|mid=%d|team=%d|unsh=%d|cull=%d" % [p_shape_name, mat_id, team, int(unshaded), int(disable_culling)]
	if _matid_material_cache.has(key):
		return _matid_material_cache[key]
	var m: StandardMaterial3D = _make_matid_material(p_shape_name, mats, mat_id)
	_matid_material_cache[key] = m
	return m


func _make_bucket_material(p_shape_name: String, mats: PackedStringArray, bucket: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.albedo_color = _pick_tint()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if disable_culling else BaseMaterial3D.CULL_BACK

	var tex: Texture2D = _pick_bucket_texture(p_shape_name, mats, bucket)
	if tex != null:
		mat.albedo_texture = tex

	return mat


func _make_matid_material(p_shape_name: String, mats: PackedStringArray, mat_id: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.albedo_color = _pick_tint()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED if disable_culling else BaseMaterial3D.CULL_BACK

	var tex: Texture2D = null
	if mat_id >= 0 and mat_id < mats.size():
		var mname: String = mats[mat_id]
		var path: String = "res://assets/wulfram_textures/extracted/%s.png" % mname
		if ResourceLoader.exists(path):
			var r: Resource = load(path)
			if r is Texture2D:
				tex = r

	# If that texture isn't present, fall back to anything we can find.
	if tex == null:
		tex = _pick_bucket_texture(p_shape_name, mats, BUCKET_OTHER)

	if tex != null:
		mat.albedo_texture = tex

	return mat


func _pick_bucket_texture(p_shape_name: String, mats: PackedStringArray, bucket: int) -> Texture2D:
	# Prefer a texture whose name suggests the bucket (top/btm/side/front/back).
	var keywords: PackedStringArray = PackedStringArray()
	if bucket == BUCKET_TOP:
		keywords = PackedStringArray(["top", "_top", "topp", "up"])
	elif bucket == BUCKET_BOTTOM:
		keywords = PackedStringArray(["btm", "bottom", "bot"])
	elif bucket == BUCKET_LEFT or bucket == BUCKET_RIGHT:
		keywords = PackedStringArray(["sd", "side", "sides", "_sd", "_side"])
	elif bucket == BUCKET_FRONT:
		keywords = PackedStringArray(["front", "_fr"])
	elif bucket == BUCKET_BACK:
		keywords = PackedStringArray(["back", "_bk", "_bck"])
	else:
		keywords = PackedStringArray()

	var best: Texture2D = _find_texture_by_keywords(mats, keywords)
	if best != null:
		return best

	# Fallback: any existing texture from the material list.
	var any_tex: Texture2D = _find_texture_by_keywords(mats, PackedStringArray())
	if any_tex != null:
		return any_tex

	return null


func _find_texture_by_keywords(mats: PackedStringArray, keywords: PackedStringArray) -> Texture2D:
	# If keywords is empty, return the first existing texture.
	var want: bool = keywords.size() > 0
	for m: String in mats:
		var ml: String = m.to_lower()
		if want:
			var ok: bool = false
			for k: String in keywords:
				if ml.find(k) >= 0:
					ok = true
					break
			if not ok:
				continue

		var path: String = "res://assets/wulfram_textures/extracted/%s.png" % m
		if ResourceLoader.exists(path):
			var r: Resource = load(path)
			if r is Texture2D:
				return r
	return null


func _build_pointcloud_lod(verts: PackedVector3Array) -> void:
	_build_pointcloud_cached(verts, lod_points_max_points, lod_points_begin, lod_points_end)


func _build_pointcloud_fallback(verts: PackedVector3Array) -> void:
	_build_pointcloud_cached(verts, max_points, 0.0, 0.0)


func _build_pointcloud_cached(verts: PackedVector3Array, cap_points: int, vr_begin: float, vr_end: float) -> void:
	var mm: MultiMesh = _get_or_build_point_multimesh(verts, cap_points)
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	if vr_end > 0.0 and vr_end > vr_begin:
		_mmi.visibility_range_begin = max(0.0, vr_begin)
		_mmi.visibility_range_end = vr_end

	_mmi.material_override = _get_pointcloud_material_cached()
	add_child(_mmi)


static func _point_cache_key(p_shape: String, p_point_size: float, cap_points: int) -> String:
	var ps_q: int = int(round(p_point_size * 1000.0))
	return "%s|ps=%d|cap=%d" % [p_shape, ps_q, cap_points]


func _get_or_build_point_multimesh(verts: PackedVector3Array, cap_points: int) -> MultiMesh:
	var key: String = _point_cache_key(shape_name, point_size, cap_points)
	if _point_mm_cache.has(key):
		return _point_mm_cache[key]

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE * max(0.01, point_size)

	var mm: MultiMesh = MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D

	var src_count: int = verts.size()
	var stride: int = 1
	var inst_count: int = src_count
	if cap_points > 0 and src_count > cap_points:
		stride = int(ceil(float(src_count) / float(cap_points)))
		inst_count = int(ceil(float(src_count) / float(stride)))
	mm.instance_count = inst_count

	var idx: int = 0
	var vi: int = 0
	while vi < src_count and idx < inst_count:
		var t: Transform3D = Transform3D(Basis.IDENTITY, verts[vi])
		mm.set_instance_transform(idx, t)
		vi += stride
		idx += 1

	_point_mm_cache[key] = mm
	return mm


func _get_pointcloud_material_cached() -> StandardMaterial3D:
	# Cache point-cloud materials by team.
	var tid: int = team
	if _pc_material_cache.has(tid):
		return _pc_material_cache[tid]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.albedo_color = _pick_tint()
	_pc_material_cache[tid] = mat
	return mat


func _pick_tint() -> Color:
	if team == 0:
		return Color(1.0, 0.45, 0.45)
	if team == 1:
		return Color(0.35, 0.8, 1.0)
	return neutral_tint
