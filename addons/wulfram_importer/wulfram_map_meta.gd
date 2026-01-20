@tool
extends Node
class_name WulframMapMeta

@export var world_width: float = 0.0
@export var world_depth: float = 0.0
@export var grid_width: int = 0
@export var grid_depth: int = 0
@export var collision_spacing: float = 0.0

const SECTORS := 6

func sector_size() -> Vector2:
	if world_width <= 0.0 or world_depth <= 0.0:
		return Vector2.ZERO
	return Vector2(world_width / SECTORS, world_depth / SECTORS)

func sector_from_world(world_pos: Vector3) -> Vector2i:
	# world is centered at (0,0,0) in importer
	var lx := world_pos.x + world_width * 0.5
	var lz := world_pos.z + world_depth * 0.5
	var sx := int(floor(lx / max(world_width / SECTORS, 0.0001)))
	var sz := int(floor(lz / max(world_depth / SECTORS, 0.0001)))
	sx = clamp(sx, 0, SECTORS - 1)
	sz = clamp(sz, 0, SECTORS - 1)
	return Vector2i(sx, sz)

func sector_center(sector: Vector2i) -> Vector3:
	var s := sector_size()
	var cx := -world_width * 0.5 + (sector.x + 0.5) * s.x
	var cz := -world_depth * 0.5 + (sector.y + 0.5) * s.y
	return Vector3(cx, 0.0, cz)