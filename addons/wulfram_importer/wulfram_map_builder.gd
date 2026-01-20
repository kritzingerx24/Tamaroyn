@tool
extends RefCounted

const META_SCRIPT := preload("res://addons/wulfram_importer/wulfram_map_meta.gd")

# Tune this if the vertical scale feels wrong once you view a map.
const HEIGHT_SCALE := 1.0

static func build_map_from_files(land_path: String, state_path: String, root: Node3D, map_name: String) -> int:
	var land := FileAccess.open(land_path, FileAccess.READ)
	if land == null:
		return FileAccess.get_open_error()

	# Line 1: "129x129"
	var line1 := _next_nonempty_line(land)
	if line1 == "":
		return ERR_PARSE_ERROR
	var dims := line1.split("x", false)
	if dims.size() != 2:
		return ERR_PARSE_ERROR
	var grid_w := int(dims[0])
	var grid_d := int(dims[1])

	# Line 2: "5600x5600"
	var line2 := _next_nonempty_line(land)
	if line2 == "":
		return ERR_PARSE_ERROR
	var world := line2.split("x", false)
	if world.size() != 2:
		return ERR_PARSE_ERROR
	var world_w := float(world[0])
	var world_d := float(world[1])

	# Read grid_w*grid_d lines: "<template_id> <height>"
	var count := grid_w * grid_d
	var heights := PackedFloat32Array()
	heights.resize(count)
	var templates := PackedInt32Array()
	templates.resize(count)

	var i := 0
	while i < count and not land.eof_reached():
		var ln := land.get_line().strip_edges()
		if ln == "":
			continue
		ln = ln.replace("\t", " ")
		var parts := ln.split(" ", false)
		if parts.size() < 2:
			continue
		templates[i] = int(parts[0])
		heights[i] = float(parts[1]) * HEIGHT_SCALE
		i += 1

	if i != count:
		return ERR_FILE_EOF

	# Build nodes
	var terrain_root := Node3D.new()
	terrain_root.name = "TerrainRoot"
	root.add_child(terrain_root)

	var meta := META_SCRIPT.new()
	meta.name = "MapMeta"
	meta.world_width = world_w
	meta.world_depth = world_d
	meta.grid_width = grid_w
	meta.grid_depth = grid_d
	meta.collision_spacing = (world_w / float(grid_w - 1) + world_d / float(grid_d - 1)) * 0.5
	terrain_root.add_child(meta)

	# Make terrain mesh + collision
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Terrain"
	mesh_inst.mesh = _build_heightfield_mesh(grid_w, grid_d, world_w, world_d, heights)
	terrain_root.add_child(mesh_inst)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	shape.name = "TerrainCollision"

	var hm := HeightMapShape3D.new()
	hm.map_width = grid_w
	hm.map_depth = grid_d
	hm.map_data = heights

	# HeightMapShape3D uses 1 unit spacing between samples. Our mesh is built in world units (dx/dz).
	# GodotPhysics3D requires UNIFORM scaling; if dx ~= dz we scale the StaticBody uniformly by dx
	# and divide height samples so vertical scale stays consistent with the mesh.
	var dx := world_w / float(grid_w - 1)
	var dz := world_d / float(grid_d - 1)
	var spacing := (dx + dz) * 0.5
	if abs(dx - dz) > 0.001:
		push_warning("Non-square terrain spacing (dx=%s dz=%s). Using average spacing for collision." % [dx, dz])
	# Copy heights for collision and normalize by spacing so uniform scale doesn't exaggerate Y.
	var hm_heights := heights.duplicate()
	for hi in range(hm_heights.size()):
		hm_heights[hi] = hm_heights[hi] / max(spacing, 0.0001)
	hm.map_data = hm_heights
	body.scale = Vector3(spacing, spacing, spacing)
	shape.shape = hm

	body.add_child(shape)
	terrain_root.add_child(body)

	# Place state objects as placeholders
	_import_state_objects(state_path, root, world_w, world_d)

	# Ensure nodes get saved in PackedScene
	_set_owner_recursive(root, root)

	return OK

static func _next_nonempty_line(f: FileAccess) -> String:
	while not f.eof_reached():
		var s := f.get_line().strip_edges()
		if s != "":
			return s
	return ""

static func _build_heightfield_mesh(grid_w: int, grid_d: int, world_w: float, world_d: float, heights: PackedFloat32Array) -> ArrayMesh:
	var dx := world_w / float(grid_w - 1)
	var dz := world_d / float(grid_d - 1)
	var x0 := -world_w * 0.5
	var z0 := -world_d * 0.5

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(grid_w * grid_d)
	norms.resize(grid_w * grid_d)
	uvs.resize(grid_w * grid_d)

	# Vertices + UVs
	for z in range(grid_d):
		for x in range(grid_w):
			var idx := z * grid_w + x
			var h := heights[idx]
			verts[idx] = Vector3(x0 + x * dx, h, z0 + z * dz)
			uvs[idx] = Vector2(float(x) / float(grid_w - 1), float(z) / float(grid_d - 1))

	# Normals (heightfield gradient approximation)
	for z in range(grid_d):
		for x in range(grid_w):
			var idx := z * grid_w + x
			var xl := max(x - 1, 0)
			var xr := min(x + 1, grid_w - 1)
			var zd := max(z - 1, 0)
			var zu := min(z + 1, grid_d - 1)

			var hl := heights[z * grid_w + xl]
			var hr := heights[z * grid_w + xr]
			var hd := heights[zd * grid_w + x]
			var hu := heights[zu * grid_w + x]

			var denom_x: float = maxf(2.0 * dx, 0.0001)
			var denom_z: float = maxf(2.0 * dz, 0.0001)
			var sx: float = (hr - hl) / denom_x
			var sz: float = (hu - hd) / denom_z

			var n := Vector3(-sx, 1.0, -sz).normalized()
			norms[idx] = n

	# Indices
	var indices := PackedInt32Array()
	indices.resize((grid_w - 1) * (grid_d - 1) * 6)
	var ii := 0
	for z in range(grid_d - 1):
		for x in range(grid_w - 1):
			var i0 := z * grid_w + x
			var i1 := i0 + 1
			var i2 := (z + 1) * grid_w + x
			var i3 := i2 + 1
			# two triangles
			indices[ii + 0] = i0
			indices[ii + 1] = i2
			indices[ii + 2] = i1
			indices[ii + 3] = i1
			indices[ii + 4] = i2
			indices[ii + 5] = i3
			ii += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mesh.surface_set_material(0, mat)

	return mesh

static func _import_state_objects(state_path: String, root: Node3D, world_w: float, world_d: float) -> void:
	if not FileAccess.file_exists(state_path):
		return

	var f := FileAccess.open(state_path, FileAccess.READ)
	if f == null:
		return

	var x0 := -world_w * 0.5
	var z0 := -world_d * 0.5

	var objects_root := Node3D.new()
	objects_root.name = "MapObjects"
	root.add_child(objects_root)

	while not f.eof_reached():
		var ln := f.get_line().strip_edges()
		if ln == "" or ln.begins_with("#"):
			continue

		ln = ln.replace("\t", " ")
		var parts := ln.split(" ", false)
		if parts.size() < 5:
			continue

		# Some lines appear to start with "c"
		if parts[0] == "c" and parts.size() >= 6:
			parts.remove_at(0)

		var code := parts[0]            # e.g. "e"
		var subtype := parts[1]         # numeric-ish
		var x := float(parts[2]) + x0
		var z := float(parts[3]) + z0
		var y := float(parts[4])

		var rx := 0.0
		var ry := 0.0
		var rz := 0.0
		if parts.size() >= 8:
			rx = float(parts[5])
			ry = float(parts[6])
			rz = float(parts[7])

		var n := Node3D.new()
		n.name = "%s_%s" % [code, subtype]
		n.position = Vector3(x, y, z)
		n.rotation_degrees = Vector3(rx, ry, rz)

		# placeholder visual
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(8, 8, 8)
		mi.mesh = bm
		n.add_child(mi)

		objects_root.add_child(n)

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for c in node.get_children():
		_set_owner_recursive(c, owner)