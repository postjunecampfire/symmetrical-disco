class_name GridModel
extends RefCounted
## A tile grid for tactical combat: per-tile terrain + optional occupant tracking,
## coordinate<->world mapping, and in-bounds checks (data-schemas.md §6).
##
## Clean in-house implementation behind a swappable interface (ADR-0007). No
## vetted external template was available to fetch in this environment, so the
## grid is implemented directly with standard, well-trodden techniques. The
## public surface (terrain queries, occupant tracking, coord<->world mapping,
## move-cost lookup) is deliberately small so a third-party tactical template
## could be vendored under /third_party and slotted in behind this same API
## later without touching the Pathfinder or callers. See src/grid/README.md.
##
## Scope note: terrain cost tables and elevation are DEFERRED. Tiles are treated
## as `plains` (cost 1) except `blocked` (impassable). Cost lookup is routed
## through `get_move_cost()` so a data-driven cost table can replace the body
## later without changing the seam.

## Terrain kinds the prototype distinguishes. `plains` is passable at the
## default cost; `blocked` is impassable. Other kinds from the schema
## (`cover`, `hazard`) are accepted but treated as plains for movement until the
## deferred terrain-cost table lands.
const TERRAIN_PLAINS: StringName = &"plains"
const TERRAIN_BLOCKED: StringName = &"blocked"

## Default per-tile entry cost for passable terrain. Kept as a named constant
## (not an inline literal) so it reads as a tuning seam, not balance baked into
## logic. The real per-terrain cost table is deferred to data (§6).
const DEFAULT_MOVE_COST: int = 1

## Sentinel returned by `get_move_cost()` for impassable tiles. Pathfinding
## treats any cost < 0 as "cannot enter".
const IMPASSABLE_COST: int = -1

## Grid dimensions in tiles (columns x rows). Set at construction.
var size: Vector2i = Vector2i(6, 6)

## Pixel size of one tile, used for coord<->world mapping. Square by default.
var tile_size: Vector2 = Vector2(64, 64)

## Sparse terrain overrides keyed by tile coord. Tiles absent from the map are
## `plains`. Keeping it sparse mirrors EncounterData.terrain (§6), which only
## stores overrides.
var _terrain: Dictionary = {}

## Optional occupant registry keyed by tile coord -> occupant (any value the
## caller supplies, e.g. a unit id or node). A tile with an occupant may be
## treated as blocked by the pathfinder when `block_occupied` is requested.
var _occupants: Dictionary = {}


func _init(grid_size: Vector2i = Vector2i(6, 6), tile_px: Vector2 = Vector2(64, 64)) -> void:
	size = grid_size
	tile_size = tile_px


# --- Bounds -----------------------------------------------------------------

## True if `cell` lies inside the grid.
func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


# --- Terrain ----------------------------------------------------------------

## Set the terrain kind of a tile. Out-of-bounds writes are ignored.
func set_terrain(cell: Vector2i, terrain: StringName) -> void:
	if not in_bounds(cell):
		return
	if terrain == TERRAIN_PLAINS:
		# Keep the override map sparse: plains is the implicit default.
		_terrain.erase(cell)
	else:
		_terrain[cell] = terrain


## The terrain kind of a tile. Unset / out-of-bounds tiles read as `plains`.
func get_terrain(cell: Vector2i) -> StringName:
	return _terrain.get(cell, TERRAIN_PLAINS)


## Mark a tile blocked/impassable. Convenience wrapper over `set_terrain`.
func set_blocked(cell: Vector2i, blocked: bool = true) -> void:
	set_terrain(cell, TERRAIN_BLOCKED if blocked else TERRAIN_PLAINS)


## True if a tile's terrain itself is impassable (ignores occupants).
func is_blocked(cell: Vector2i) -> bool:
	return get_terrain(cell) == TERRAIN_BLOCKED


# --- Occupants --------------------------------------------------------------

## Record an occupant on a tile. Out-of-bounds writes are ignored.
func set_occupant(cell: Vector2i, occupant: Variant) -> void:
	if not in_bounds(cell):
		return
	_occupants[cell] = occupant


## Remove any occupant from a tile.
func clear_occupant(cell: Vector2i) -> void:
	_occupants.erase(cell)


## True if a tile currently has an occupant recorded.
func is_occupied(cell: Vector2i) -> bool:
	return _occupants.has(cell)


## The occupant on a tile, or `null` if none.
func get_occupant(cell: Vector2i) -> Variant:
	return _occupants.get(cell, null)


# --- Passability / cost -----------------------------------------------------

## Cost to ENTER `cell`, or `IMPASSABLE_COST` if it cannot be entered.
##
## `block_occupied` makes occupied tiles impassable (the common case when
## planning a unit's move through a crowded field). `ignore` lets a caller
## exempt specific tiles from the occupant check — e.g. the mover's own start
## tile, or a target tile the mover intends to swap into.
func get_move_cost(cell: Vector2i, block_occupied: bool = false, ignore: Array[Vector2i] = []) -> int:
	if not in_bounds(cell):
		return IMPASSABLE_COST
	if is_blocked(cell):
		return IMPASSABLE_COST
	if block_occupied and is_occupied(cell) and not ignore.has(cell):
		return IMPASSABLE_COST
	# Deferred: per-terrain cost table. Until then every passable tile is plains.
	return DEFAULT_MOVE_COST


## Convenience predicate combining bounds + terrain + (optional) occupant rules.
func is_passable(cell: Vector2i, block_occupied: bool = false, ignore: Array[Vector2i] = []) -> bool:
	return get_move_cost(cell, block_occupied, ignore) >= 0


## The 4-connected (orthogonal) in-bounds neighbours of `cell`. Diagonal
## movement is intentionally excluded for the prototype's tactical grid.
func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + delta
		if in_bounds(n):
			result.append(n)
	return result


# --- Coordinate <-> world mapping ------------------------------------------

## World position of a tile's CENTER, given the grid's `tile_size`.
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * tile_size.x,
		(float(cell.y) + 0.5) * tile_size.y
	)


## The tile that contains world position `world`. Not clamped to bounds; pair
## with `in_bounds()` when you need a valid tile. Round-trips exactly with
## `cell_to_world` for any in-bounds cell.
func world_to_cell(world: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world.x / tile_size.x)),
		int(floor(world.y / tile_size.y))
	)
