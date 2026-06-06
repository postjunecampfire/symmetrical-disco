extends "res://addons/gut/test.gd"
## GUT suite for src/grid/ (task P1·05): reachable-set correctness on a fixture
## map with blocked tiles and a move-range limit, A* path correctness (and no
## path when blocked), and coord<->world round-trip.
##
## Fixture map (5x5, x = column, y = row). `#` = blocked, `.` = plains.
## A vertical wall at column x=2 spans rows 0..3, leaving a single gap at (2,4),
## so the only way from the left half to the right half is around the bottom.
##
##     x: 0 1 2 3 4
##   y=0  . . # . .
##   y=1  . . # . .
##   y=2  . . # . .
##   y=3  . . # . .
##   y=4  . . . . .   <- gap at (2,4)

const GridModelScript := preload("res://src/grid/grid_model.gd")
const PathfinderScript := preload("res://src/grid/pathfinder.gd")

const WALL_COLUMN: int = 2
const GRID_SIZE := Vector2i(5, 5)


## Build the fixture grid described above.
func _make_fixture() -> GridModel:
	var grid: GridModel = GridModelScript.new(GRID_SIZE)
	for y in range(4):  # rows 0..3 blocked at the wall column; (2,4) stays open.
		grid.set_blocked(Vector2i(WALL_COLUMN, y), true)
	return grid


# --- Bounds & terrain -------------------------------------------------------

func test_in_bounds() -> void:
	var grid: GridModel = _make_fixture()
	assert_true(grid.in_bounds(Vector2i(0, 0)), "Origin is in bounds.")
	assert_true(grid.in_bounds(Vector2i(4, 4)), "Far corner is in bounds.")
	assert_false(grid.in_bounds(Vector2i(5, 0)), "x == size.x is out of bounds.")
	assert_false(grid.in_bounds(Vector2i(-1, 0)), "Negative x is out of bounds.")
	assert_false(grid.in_bounds(Vector2i(0, 5)), "y == size.y is out of bounds.")


func test_terrain_defaults_to_plains() -> void:
	var grid: GridModel = _make_fixture()
	assert_eq(grid.get_terrain(Vector2i(0, 0)), GridModelScript.TERRAIN_PLAINS,
		"Unset tile reads as plains.")
	assert_true(grid.is_blocked(Vector2i(WALL_COLUMN, 0)), "Wall tile is blocked.")
	assert_false(grid.is_blocked(Vector2i(2, 4)), "Gap tile is not blocked.")


func test_blocked_tile_is_impassable_cost() -> void:
	var grid: GridModel = _make_fixture()
	assert_eq(grid.get_move_cost(Vector2i(WALL_COLUMN, 0)),
		GridModelScript.IMPASSABLE_COST, "Blocked tile costs IMPASSABLE_COST.")
	assert_eq(grid.get_move_cost(Vector2i(0, 0)),
		GridModelScript.DEFAULT_MOVE_COST, "Plains tile costs the default (1).")


# --- Coord <-> world round-trip --------------------------------------------

func test_coord_world_round_trip() -> void:
	var grid: GridModel = GridModelScript.new(Vector2i(6, 6), Vector2(64, 64))
	for cell in [Vector2i(0, 0), Vector2i(3, 4), Vector2i(5, 5), Vector2i(2, 0)]:
		var world: Vector2 = grid.cell_to_world(cell)
		assert_eq(grid.world_to_cell(world), cell,
			"cell_to_world -> world_to_cell round-trips for %s." % cell)


func test_cell_to_world_is_tile_center() -> void:
	var grid: GridModel = GridModelScript.new(Vector2i(6, 6), Vector2(64, 64))
	assert_eq(grid.cell_to_world(Vector2i(0, 0)), Vector2(32, 32),
		"Tile (0,0) center is at half a tile in each axis.")
	assert_eq(grid.cell_to_world(Vector2i(1, 2)), Vector2(96, 160),
		"Tile (1,2) center accounts for tile_size.")


func test_world_to_cell_handles_non_origin_tile_size() -> void:
	var grid: GridModel = GridModelScript.new(Vector2i(10, 10), Vector2(48, 32))
	for cell in [Vector2i(0, 0), Vector2i(7, 9), Vector2i(4, 1)]:
		assert_eq(grid.world_to_cell(grid.cell_to_world(cell)), cell,
			"Round-trip holds for non-square tile_size at %s." % cell)


# --- Reachable tiles --------------------------------------------------------

func test_reachable_open_grid_diamond() -> void:
	# On a fully open grid, budget 2 from center yields the Manhattan-disk of
	# radius 2: 13 tiles (1 + 4 + 8) including the start.
	var grid: GridModel = GridModelScript.new(Vector2i(7, 7))
	var pf: Pathfinder = PathfinderScript.new(grid)
	var reach: Dictionary = pf.reachable_tiles(Vector2i(3, 3), 2)
	assert_eq(reach.size(), 13, "Budget 2 on open grid reaches 13 tiles.")
	assert_eq(int(reach[Vector2i(3, 3)]), 0, "Start tile is cost 0.")
	assert_eq(int(reach[Vector2i(3, 1)]), 2, "Two tiles up costs 2.")
	assert_false(reach.has(Vector2i(3, 0)), "Three tiles away is outside budget 2.")


func test_reachable_respects_blocked_and_budget() -> void:
	# From (0,2), budget 3. The wall (column 2, rows 0..3) cannot be crossed and
	# the bottom gap (2,4) is 4 steps away, so the whole right half is
	# unreachable within budget 3. Reachable = left-half tiles within 3 steps.
	var grid: GridModel = _make_fixture()
	var pf: Pathfinder = PathfinderScript.new(grid)
	var reach: Dictionary = pf.reachable_tiles(Vector2i(0, 2), 3)

	# A representative reachable tile on the left side.
	assert_true(reach.has(Vector2i(1, 0)), "(1,0) is reachable (cost 3) on the left.")
	assert_eq(int(reach[Vector2i(1, 0)]), 3, "(1,0) costs exactly 3 from (0,2).")

	# Blocked tiles are never in the reachable set.
	assert_false(reach.has(Vector2i(2, 0)), "Wall tile (2,0) is never reachable.")
	assert_false(reach.has(Vector2i(2, 2)), "Wall tile (2,2) is never reachable.")

	# The right half is walled off beyond this budget.
	assert_false(reach.has(Vector2i(3, 2)), "Right-half tile is unreachable within budget 3.")
	assert_false(reach.has(Vector2i(2, 4)), "Bottom gap (dist 4) is outside budget 3.")


func test_reachable_can_round_the_wall_with_budget() -> void:
	# With a large budget, the path rounds through the bottom gap (2,4) and the
	# right half becomes reachable, proving the flood fill follows real paths.
	var grid: GridModel = _make_fixture()
	var pf: Pathfinder = PathfinderScript.new(grid)
	var reach: Dictionary = pf.reachable_tiles(Vector2i(0, 2), 20)
	assert_true(reach.has(Vector2i(3, 2)), "Right half is reachable with a big budget.")
	# (0,2)->(0,4)=2, ->(1,4)=3, ->(2,4)=4, ->(3,4)=5, ->(3,3)=6, ->(3,2)=7.
	assert_eq(int(reach[Vector2i(3, 2)]), 7, "(3,2) costs 7 routing around the wall.")


func test_reachable_optionally_blocks_occupants() -> void:
	var grid: GridModel = GridModelScript.new(Vector2i(5, 1))
	grid.set_occupant(Vector2i(2, 0), &"blocker")
	var pf: Pathfinder = PathfinderScript.new(grid)

	# Occupant ignored: the corridor is fully reachable.
	var ignored: Dictionary = pf.reachable_tiles(Vector2i(0, 0), 4, false)
	assert_true(ignored.has(Vector2i(4, 0)), "Far end reachable when occupants ignored.")

	# Occupant respected: it walls off everything past column 2.
	var blocked: Dictionary = pf.reachable_tiles(Vector2i(0, 0), 4, true)
	assert_false(blocked.has(Vector2i(2, 0)), "Occupied tile not entered when block_occupied.")
	assert_false(blocked.has(Vector2i(3, 0)), "Tiles past the occupant are cut off.")
	assert_true(blocked.has(Vector2i(1, 0)), "Tiles before the occupant stay reachable.")


# --- A* path ----------------------------------------------------------------

func test_path_straight_line() -> void:
	var grid: GridModel = GridModelScript.new(Vector2i(5, 1))
	var pf: Pathfinder = PathfinderScript.new(grid)
	var path: Array[Vector2i] = pf.find_path(Vector2i(0, 0), Vector2i(4, 0))
	assert_eq(path, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)
	], "Straight corridor yields the direct 5-tile path.")


func test_path_same_start_and_goal() -> void:
	var grid: GridModel = _make_fixture()
	var pf: Pathfinder = PathfinderScript.new(grid)
	var path: Array[Vector2i] = pf.find_path(Vector2i(1, 1), Vector2i(1, 1))
	assert_eq(path, [Vector2i(1, 1)], "Path to self is a single-tile path.")


func test_path_routes_around_wall() -> void:
	# Left side to right side must detour through the bottom gap (2,4).
	var grid: GridModel = _make_fixture()
	var pf: Pathfinder = PathfinderScript.new(grid)
	var path: Array[Vector2i] = pf.find_path(Vector2i(1, 2), Vector2i(3, 2))

	assert_gt(path.size(), 0, "A path exists around the wall.")
	assert_eq(path.front(), Vector2i(1, 2), "Path starts at the start tile.")
	assert_eq(path.back(), Vector2i(3, 2), "Path ends at the goal tile.")
	# Must pass through the only gap, and never step on a blocked tile.
	assert_true(path.has(Vector2i(2, 4)), "Path uses the single bottom gap.")
	for cell in path:
		assert_false(grid.is_blocked(cell), "Path never crosses a blocked tile (%s)." % cell)
	# Cost = tiles entered after the start = path length - 1.
	# (1,2)->(1,3)->(1,4)->(2,4)->(3,4)->(3,3)->(3,2): 6 steps around the wall.
	assert_eq(path.size() - 1, 6, "Shortest detour around the wall costs 6 steps.")


func test_no_path_when_fully_walled() -> void:
	# Seal the bottom gap too: the right half becomes unreachable.
	var grid: GridModel = _make_fixture()
	grid.set_blocked(Vector2i(WALL_COLUMN, 4), true)
	var pf: Pathfinder = PathfinderScript.new(grid)
	var path: Array[Vector2i] = pf.find_path(Vector2i(1, 2), Vector2i(3, 2))
	assert_eq(path, [], "No path exists when the wall fully separates the halves.")


func test_no_path_to_blocked_goal() -> void:
	var grid: GridModel = _make_fixture()
	var pf: Pathfinder = PathfinderScript.new(grid)
	var path: Array[Vector2i] = pf.find_path(Vector2i(0, 0), Vector2i(WALL_COLUMN, 1))
	assert_eq(path, [], "No path when the goal tile itself is blocked.")


func test_path_optionally_respects_occupants() -> void:
	var grid: GridModel = GridModelScript.new(Vector2i(3, 3))
	# Occupy the two middle tiles of the only short routes, forcing a detour.
	grid.set_occupant(Vector2i(1, 0), &"unit")
	grid.set_occupant(Vector2i(1, 1), &"unit")
	var pf: Pathfinder = PathfinderScript.new(grid)

	# Occupants ignored: direct path across the top row.
	var direct: Array[Vector2i] = pf.find_path(Vector2i(0, 0), Vector2i(2, 0), false)
	assert_eq(direct, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"Ignoring occupants gives the direct path.")

	# Occupants respected: must route through the open bottom row.
	var detour: Array[Vector2i] = pf.find_path(Vector2i(0, 0), Vector2i(2, 0), true)
	assert_gt(detour.size(), 0, "A detour path exists with occupants respected.")
	assert_false(detour.has(Vector2i(1, 0)), "Detour avoids the occupied tile (1,0).")
	assert_false(detour.has(Vector2i(1, 1)), "Detour avoids the occupied tile (1,1).")
	assert_eq(detour.back(), Vector2i(2, 0), "Detour still reaches the goal.")
