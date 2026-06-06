class_name Pathfinder
extends RefCounted
## Movement queries over a GridModel: reachable-tiles (weighted flood fill /
## Dijkstra within a move budget) and A* shortest path between two tiles. Both
## respect blocked terrain and, optionally, occupants — all passability and
## cost decisions are delegated to GridModel.get_move_cost() so terrain/cost
## rules live in exactly one place (data-schemas.md §6).
##
## Clean in-house implementation behind a swappable interface (ADR-0007). No
## vetted external template was available to fetch here, so these are standard,
## textbook algorithms (Dijkstra flood fill + A* with a Manhattan heuristic).
## The Pathfinder talks to the grid ONLY through GridModel's public API, so a
## third-party tactical-movement template could replace either side
## independently. See src/grid/README.md.

## The grid this pathfinder queries. Injected so the same instance can be reused
## or swapped without rebuilding the pathfinder.
var grid: GridModel


func _init(grid_model: GridModel = null) -> void:
	grid = grid_model


# --- Reachable tiles (weighted flood fill / Dijkstra) -----------------------

## All tiles reachable FROM `start` for `move_budget` total movement points,
## as a Dictionary {Vector2i -> int cost_to_reach}. `start` itself is included
## at cost 0. A tile is included only if the cheapest path to it costs <=
## `move_budget`. Costs come from GridModel.get_move_cost(), so blocked terrain
## (and, when `block_occupied` is true, occupied tiles) are excluded.
##
## The mover's own start tile is always exempt from the occupant check so a
## standing unit can compute its own range. Pass extra exempt tiles via
## `ignore` (e.g. an ally you intend to swap with).
func reachable_tiles(
	start: Vector2i,
	move_budget: int,
	block_occupied: bool = false,
	ignore: Array[Vector2i] = []
) -> Dictionary:
	var result: Dictionary = {}
	if grid == null or not grid.in_bounds(start) or move_budget < 0:
		return result

	# The start tile is the mover's own tile; never let its occupant block it.
	var exempt: Array[Vector2i] = ignore.duplicate()
	if not exempt.has(start):
		exempt.append(start)

	# best_cost[cell] = cheapest known movement cost to reach cell.
	var best_cost: Dictionary = {start: 0}
	# Frontier as [cost, cell] pairs; pop the cheapest each step (Dijkstra).
	# A small array + linear-min scan is fine for the prototype's small grids.
	var frontier: Array = [[0, start]]

	while not frontier.is_empty():
		var min_index: int = 0
		for i in range(1, frontier.size()):
			if frontier[i][0] < frontier[min_index][0]:
				min_index = i
		var entry: Array = frontier[min_index]
		frontier.remove_at(min_index)

		var cost: int = entry[0]
		var cell: Vector2i = entry[1]

		# Stale frontier entry (a cheaper path was found after this was queued).
		if cost > int(best_cost[cell]):
			continue

		for neighbor in grid.neighbors(cell):
			var step: int = grid.get_move_cost(neighbor, block_occupied, exempt)
			if step < 0:
				continue  # impassable
			var next_cost: int = cost + step
			if next_cost > move_budget:
				continue  # outside the budget
			if not best_cost.has(neighbor) or next_cost < int(best_cost[neighbor]):
				best_cost[neighbor] = next_cost
				frontier.append([next_cost, neighbor])

	return best_cost


# --- A* shortest path -------------------------------------------------------

## The cheapest path from `start` to `goal` as an ordered Array[Vector2i]
## INCLUDING both endpoints, or an EMPTY array if no path exists (or either
## endpoint is invalid/impassable). Uses A* with a Manhattan-distance heuristic,
## admissible for 4-connected grids with unit-or-greater step costs.
##
## Passability follows GridModel.get_move_cost() with the same `block_occupied`
## / `ignore` semantics as reachable_tiles(). `start` and `goal` are always
## exempt from the occupant check so a unit can path out of its own tile and
## onto an intended destination.
func find_path(
	start: Vector2i,
	goal: Vector2i,
	block_occupied: bool = false,
	ignore: Array[Vector2i] = []
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if grid == null:
		return empty
	if not grid.in_bounds(start) or not grid.in_bounds(goal):
		return empty
	if grid.is_blocked(start) or grid.is_blocked(goal):
		return empty

	if start == goal:
		var trivial: Array[Vector2i] = [start]
		return trivial

	# Endpoints are exempt from the occupant rule (you start/finish on them).
	var exempt: Array[Vector2i] = ignore.duplicate()
	if not exempt.has(start):
		exempt.append(start)
	if not exempt.has(goal):
		exempt.append(goal)

	var g_cost: Dictionary = {start: 0}            # cheapest known cost to reach
	var came_from: Dictionary = {}                  # cell -> predecessor cell
	# Open set as [f_cost, cell]; pop the lowest f each step.
	var open_set: Array = [[_heuristic(start, goal), start]]

	while not open_set.is_empty():
		var min_index: int = 0
		for i in range(1, open_set.size()):
			if open_set[i][0] < open_set[min_index][0]:
				min_index = i
		var entry: Array = open_set[min_index]
		open_set.remove_at(min_index)
		var current: Vector2i = entry[1]

		if current == goal:
			return _reconstruct(came_from, current)

		for neighbor in grid.neighbors(current):
			var step: int = grid.get_move_cost(neighbor, block_occupied, exempt)
			if step < 0:
				continue
			var tentative: int = int(g_cost[current]) + step
			if not g_cost.has(neighbor) or tentative < int(g_cost[neighbor]):
				g_cost[neighbor] = tentative
				came_from[neighbor] = current
				open_set.append([tentative + _heuristic(neighbor, goal), neighbor])

	return empty  # goal unreachable


## Manhattan distance — admissible heuristic for a 4-connected grid whose
## minimum step cost is >= 1.
func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


## Walk `came_from` back from `current` to the start, returning start->goal order.
func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path
