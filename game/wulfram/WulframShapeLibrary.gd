extends Node

# Loads extracted Wulfram "shape" binaries produced by tools/extract_wulfram_shapes.py
# and exposes placeholder geometry for Tamaroyn.
#
# v1  : vertices + materials
# v2  : best-effort triangle decode (stride/phase scan)
# v2.3: improved stride/phase scoring (edge-manifold heuristic) + best-effort
#       per-triangle material-id inference (when face records contain mat ids).
#
# IMPORTANT: Keep this file strictly typed. Some build setups treat certain GDScript
# warnings (especially Variant inference) as errors.

class ShapeData:
	var vertices: PackedVector3Array
	var materials: PackedStringArray
	var triangles: PackedInt32Array
	var tri_material_ids: PackedInt32Array # per-triangle material id, -1 if unknown
	var decode_stride: int
	var decode_phase: int
	var decode_mat_ratio: float
	var decode_score: int
	var decode_uses_mat_ids: bool

	func _init(
			p_vertices: PackedVector3Array = PackedVector3Array(),
			p_materials: PackedStringArray = PackedStringArray(),
			p_triangles: PackedInt32Array = PackedInt32Array(),
			p_tri_material_ids: PackedInt32Array = PackedInt32Array(),
			p_decode_stride: int = 0,
			p_decode_phase: int = 0,
			p_decode_mat_ratio: float = 0.0,
			p_decode_score: int = 0,
			p_decode_uses_mat_ids: bool = false
	) -> void:
		vertices = p_vertices
		materials = p_materials
		triangles = p_triangles
		tri_material_ids = p_tri_material_ids
		decode_stride = p_decode_stride
		decode_phase = p_decode_phase
		decode_mat_ratio = p_decode_mat_ratio
		decode_score = p_decode_score
		decode_uses_mat_ids = p_decode_uses_mat_ids


class CStringReadResult:
	var text: String = ""
	var next: int = 0

	func _init(p_text: String = "", p_next: int = 0) -> void:
		text = p_text
		next = p_next


class TriExtractResult:
	var triangles: PackedInt32Array = PackedInt32Array()
	var tri_material_ids: PackedInt32Array = PackedInt32Array()
	var stride: int = 0
	var phase: int = 0
	var mat_ratio: float = 0.0
	var score: int = 0
	var uses_mat_ids: bool = false

	func _init() -> void:
		pass


static var _cache_vertices: Dictionary[String, PackedVector3Array] = {} # shape_name -> vertices
static var _cache_mats: Dictionary[String, PackedStringArray] = {}      # shape_name -> materials
static var _cache_tris: Dictionary[String, PackedInt32Array] = {}       # shape_name -> triangles
static var _cache_tri_mats: Dictionary[String, PackedInt32Array] = {}   # shape_name -> tri material ids
static var _cache_decode: Dictionary[String, Dictionary] = {}           # shape_name -> decode info dict


static func shapes_ready() -> bool:
	return FileAccess.file_exists("res://assets/wulfram_shapes/extracted/manifest.json")


static func clear_cache() -> void:
	_cache_vertices.clear()
	_cache_mats.clear()
	_cache_tris.clear()
	_cache_tri_mats.clear()
	_cache_decode.clear()


static func has_shape(shape_name: String) -> bool:
	return FileAccess.file_exists(_shape_path(shape_name))


static func get_vertices(shape_name: String) -> PackedVector3Array:
	if _cache_vertices.has(shape_name):
		return _cache_vertices[shape_name]
	var data: ShapeData = _load_shape_data(shape_name)
	_put_cache(shape_name, data)
	return data.vertices


static func get_materials(shape_name: String) -> PackedStringArray:
	if _cache_mats.has(shape_name):
		return _cache_mats[shape_name]
	var data: ShapeData = _load_shape_data(shape_name)
	_put_cache(shape_name, data)
	return data.materials


static func get_triangles(shape_name: String) -> PackedInt32Array:
	if _cache_tris.has(shape_name):
		return _cache_tris[shape_name]
	var data: ShapeData = _load_shape_data(shape_name)
	_put_cache(shape_name, data)
	return data.triangles


static func get_triangle_material_ids(shape_name: String) -> PackedInt32Array:
	if _cache_tri_mats.has(shape_name):
		return _cache_tri_mats[shape_name]
	var data: ShapeData = _load_shape_data(shape_name)
	_put_cache(shape_name, data)
	return data.tri_material_ids


static func get_decode_info(shape_name: String) -> Dictionary:
	# Returns: { stride:int, phase:int, tri_count:int, mat_ratio:float, uses_mat_ids:bool, score:int }
	if _cache_decode.has(shape_name):
		return _cache_decode[shape_name]
	var data: ShapeData = _load_shape_data(shape_name)
	_put_cache(shape_name, data)
	return _cache_decode.get(shape_name, {})


static func _put_cache(shape_name: String, data: ShapeData) -> void:
	_cache_vertices[shape_name] = data.vertices
	_cache_mats[shape_name] = data.materials
	_cache_tris[shape_name] = data.triangles
	_cache_tri_mats[shape_name] = data.tri_material_ids
	var d: Dictionary = {}
	d["stride"] = data.decode_stride
	d["phase"] = data.decode_phase
	d["tri_count"] = int(data.triangles.size() / 3)
	d["mat_ratio"] = data.decode_mat_ratio
	d["uses_mat_ids"] = data.decode_uses_mat_ids
	d["score"] = data.decode_score
	_cache_decode[shape_name] = d


static func _shape_path(shape_name: String) -> String:
	return "res://assets/wulfram_shapes/extracted/%s.bin" % shape_name


static func _load_shape_data(shape_name: String) -> ShapeData:
	var path: String = _shape_path(shape_name)
	if not FileAccess.file_exists(path):
		return ShapeData.new()

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ShapeData.new()

	var data_bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	return _parse_shape_bytes(data_bytes, shape_name)


static func _parse_shape_bytes(data: PackedByteArray, shape_name: String) -> ShapeData:
	var off: int = 0

	# name (cstring)
	var name_res: CStringReadResult = _read_cstring(data, off, 128)
	off = name_res.next

	# material count
	if off + 2 > data.size():
		return ShapeData.new()
	var mat_count: int = _u16_le(data, off)
	off += 2

	var mats: PackedStringArray = PackedStringArray()
	for i: int in range(mat_count):
		var mres: CStringReadResult = _read_cstring(data, off, 128)
		off = mres.next
		if mres.text.length() > 0:
			mats.append(mres.text)

	# vertex count
	if off + 2 > data.size():
		return ShapeData.new(PackedVector3Array(), mats)
	var vcount: int = _u16_le(data, off)
	off += 2

	# vertices (i32 x3 fixed 16.16)
	var verts: PackedVector3Array = PackedVector3Array()
	verts.resize(vcount)

	var minv: Vector3 = Vector3(INF, INF, INF)
	var maxv: Vector3 = Vector3(-INF, -INF, -INF)

	var vi: int = 0
	while vi < vcount and (off + 12) <= data.size():
		var x: float = float(_i32_le(data, off + 0)) / 65536.0
		var y: float = float(_i32_le(data, off + 4)) / 65536.0
		var z: float = float(_i32_le(data, off + 8)) / 65536.0
		var v: Vector3 = Vector3(x, y, z)
		verts[vi] = v
		minv = Vector3(min(minv.x, v.x), min(minv.y, v.y), min(minv.z, v.z))
		maxv = Vector3(max(maxv.x, v.x), max(maxv.y, v.y), max(maxv.z, v.z))
		off += 12
		vi += 1

	# Normalize size/center for consistent readability in Tamaroyn.
	var target: float = _target_size_for(shape_name)
	if vcount > 0:
		var center: Vector3 = (minv + maxv) * 0.5
		var ext: Vector3 = maxv - minv
		var max_dim: float = max(ext.x, max(ext.y, ext.z))
		var scale: float = 1.0
		if max_dim > 0.0001:
			scale = target / max_dim
		for j: int in range(vcount):
			verts[j] = (verts[j] - center) * scale

	# Triangles (best-effort). We scan the remainder of the file for u16 index streams.
	var tri_res: TriExtractResult = _extract_triangles_best_effort(data, off, verts, vcount, mats.size(), target)
	return ShapeData.new(
		verts,
		mats,
		tri_res.triangles,
		tri_res.tri_material_ids,
		tri_res.stride,
		tri_res.phase,
		tri_res.mat_ratio,
		tri_res.score,
		tri_res.uses_mat_ids
	)


static func _extract_triangles_best_effort(data: PackedByteArray, start_off: int, verts: PackedVector3Array, vcount: int, mat_count: int, max_dim: float) -> TriExtractResult:
	var best: TriExtractResult = TriExtractResult.new()
	best.score = -2147483648

	if vcount <= 0:
		return best
	if start_off >= data.size():
		return best

	# Interpret remaining bytes as u16 stream.
	var rem_bytes: int = data.size() - start_off
	var word_count: int = int(rem_bytes / 2)
	if word_count < 6:
		return best

	var words: PackedInt32Array = PackedInt32Array()
	words.resize(word_count)
	var wi: int = 0
	var bo: int = start_off
	while wi < word_count and (bo + 1) < data.size():
		words[wi] = _u16_le(data, bo)
		wi += 1
		bo += 2

	var max_edge: float = max(0.001, max_dim * 0.95)
	var max_edge2: float = max_edge * max_edge

	# Scan candidate record strides.
	for stride in range(3, 10):
		var stride_i: int = int(stride)
		for phase in range(stride_i):
			var phase_i: int = int(phase)
			var cand: TriExtractResult = _extract_candidate(words, verts, vcount, mat_count, stride_i, phase_i, max_edge2)
			if cand.score > best.score:
				best = cand

	# Soft cap to prevent pathological cases.
	var max_tris: int = 8000
	if best.triangles.size() > (max_tris * 3):
		best.triangles = best.triangles.slice(0, max_tris * 3)
		if best.tri_material_ids.size() > max_tris:
			best.tri_material_ids = best.tri_material_ids.slice(0, max_tris)

	return best


static func _extract_candidate(words: PackedInt32Array, verts: PackedVector3Array, vcount: int, mat_count: int, stride: int, phase: int, max_edge2: float) -> TriExtractResult:
	var res: TriExtractResult = TriExtractResult.new()
	res.stride = stride
	res.phase = phase

	var seen: Dictionary[String, bool] = {}
	var out_tris: PackedInt32Array = PackedInt32Array()
	var out_mats: PackedInt32Array = PackedInt32Array()
	var eps_area: float = 0.00001
	var mat_hits: int = 0

	var i: int = phase
	while (i + 2) < words.size():
		var a: int = words[i + 0]
		var b: int = words[i + 1]
		var c: int = words[i + 2]
		if a >= 0 and b >= 0 and c >= 0 and a < vcount and b < vcount and c < vcount:
			if a != b and b != c and a != c:
				var va: Vector3 = verts[a]
				var vb: Vector3 = verts[b]
				var vc: Vector3 = verts[c]

				# Filter very long edges (spikes from wrong connectivity).
				var ab2: float = (vb - va).length_squared()
				var bc2: float = (vc - vb).length_squared()
				var ca2: float = (va - vc).length_squared()
				if ab2 <= max_edge2 and bc2 <= max_edge2 and ca2 <= max_edge2:
					var n: Vector3 = (vb - va).cross(vc - va)
					var area2: float = n.length()
					if area2 > eps_area:
						# Force outward-ish winding relative to origin (verts are centered during normalization).
						var centroid: Vector3 = (va + vb + vc) / 3.0
						if n.dot(centroid) < 0.0:
							var tmp: int = b
							b = c
							c = tmp

						var key: String = _tri_key(a, b, c)
						if not seen.has(key):
							seen[key] = true
							out_tris.append(a)
							out_tris.append(b)
							out_tris.append(c)

							var mid: int = -1
							if mat_count > 0 and stride >= 4 and (i + 3) < words.size():
								var mval: int = words[i + 3]
								if mval >= 0 and mval < mat_count:
									mid = mval
									mat_hits += 1
							out_mats.append(mid)

		i += stride

	res.triangles = out_tris
	res.tri_material_ids = out_mats

	var tri_count: int = int(out_tris.size() / 3)
	if tri_count <= 0:
		res.score = -2147483648
		return res

	# Material ratio heuristic: if the 4th word looks like a material index often enough,
	# prefer this stride/phase.
	res.mat_ratio = float(mat_hits) / float(tri_count) if mat_count > 0 else 0.0
	res.uses_mat_ids = res.mat_ratio >= 0.60

	# Edge-manifold heuristic: a good triangle stream tends to reuse edges ~2 times.
	var edge_counts: Dictionary[int, int] = {}
	var t: int = 0
	while (t + 2) < out_tris.size():
		var a2: int = out_tris[t + 0]
		var b2: int = out_tris[t + 1]
		var c2: int = out_tris[t + 2]
		_add_edge(edge_counts, a2, b2)
		_add_edge(edge_counts, b2, c2)
		_add_edge(edge_counts, c2, a2)
		t += 3

	var good_edges: int = 0
	var open_edges: int = 0
	var bad_edges: int = 0
	for k in edge_counts.keys():
		var kk: int = int(k)
		var cnt: int = int(edge_counts[kk])
		if cnt == 2:
			good_edges += 1
		elif cnt == 1:
			open_edges += 1
		elif cnt > 2:
			bad_edges += 1

	# Combine into a score.
	var mat_bonus: int = int(round(res.mat_ratio * 1000.0))
	res.score = tri_count * 1000 + good_edges * 350 - open_edges * 120 - bad_edges * 1200 + mat_bonus * 400

	return res


static func _add_edge(edge_counts: Dictionary[int, int], a: int, b: int) -> void:
	var mn: int = a
	var mx: int = b
	if mn > mx:
		var t: int = mn
		mn = mx
		mx = t
	var key: int = (mn << 32) | mx
	if edge_counts.has(key):
		edge_counts[key] = int(edge_counts[key]) + 1
	else:
		edge_counts[key] = 1


static func _tri_key(a: int, b: int, c: int) -> String:
	# Unordered key so we can dedupe triangles regardless of winding.
	var i0: int = a
	var i1: int = b
	var i2: int = c
	# Sort 3 ints.
	if i0 > i1:
		var t0: int = i0
		i0 = i1
		i1 = t0
	if i1 > i2:
		var t1: int = i1
		i1 = i2
		i2 = t1
	if i0 > i1:
		var t2: int = i0
		i0 = i1
		i1 = t2
	return "%d,%d,%d" % [i0, i1, i2]


static func _target_size_for(shape_name: String) -> float:
	var s: String = shape_name.to_lower()
	if s.begins_with("tank"):
		return 4.2
	if s.begins_with("scout"):
		return 3.6
	if s.begins_with("cargo"):
		return 1.2
	if s.begins_with("energy"):
		return 2.4
	if s.begins_with("uplink"):
		return 2.8
	return 3.0


static func _read_cstring(data: PackedByteArray, offset: int, max_len: int) -> CStringReadResult:
	var out: PackedByteArray = PackedByteArray()
	var i: int = offset
	var end: int = min(data.size(), offset + max_len)
	while i < end and data[i] != 0:
		out.append(data[i])
		i += 1
	if i < data.size() and data[i] == 0:
		i += 1
	return CStringReadResult.new(out.get_string_from_ascii(), i)


static func _u16_le(data: PackedByteArray, off: int) -> int:
	if off + 1 >= data.size():
		return 0
	return int(data[off]) | (int(data[off + 1]) << 8)


static func _i32_le(data: PackedByteArray, off: int) -> int:
	if off + 3 >= data.size():
		return 0

	var v: int = int(data[off]) | (int(data[off + 1]) << 8) | (int(data[off + 2]) << 16) | (int(data[off + 3]) << 24)
	# Convert unsigned to signed.
	if (v & 0x80000000) != 0:
		v -= 0x100000000
	return v
