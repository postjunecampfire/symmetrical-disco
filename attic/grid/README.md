# Grid, movement & range (`src/grid/`)

Tile grid + movement queries for tactical combat (task **P1·05**), implemented
against the grid/terrain contract in
[`docs/systems/data-schemas.md` §6](../../docs/systems/data-schemas.md).

## Files

- **`grid_model.gd`** (`GridModel`) — configurable-size tile grid with per-tile
  terrain (`plains` vs `blocked`), optional occupant tracking, coord↔world
  mapping, in-bounds checks, and a single `get_move_cost()` seam for movement
  cost.
- **`pathfinder.gd`** (`Pathfinder`) — `reachable_tiles()` (weighted flood fill /
  Dijkstra within a move budget) and `find_path()` (A\* shortest path). Both
  respect blocked terrain and, optionally, occupants, delegating every
  passability/cost decision to `GridModel`.

## Swappable by design (ADR-0007)

These are **clean in-house implementations behind a small, self-owned
interface**. [ADR-0007](../../docs/decisions/0007-build-on-existing-templates.md)
prefers vendoring a proven open-source tactical-movement base; **no vetted
external template was available to fetch in this environment**, so the
algorithms are standard and written directly here. The `GridModel` ↔
`Pathfinder` seam is deliberately narrow (terrain/occupant queries, coord↔world
mapping, `get_move_cost()`), so a third-party template may later be **vendored
under `/third_party/<name>/`** (with a `PROVENANCE.md`) and slotted in behind
this same API without changing callers.

## Deferred

Per data-schemas.md §6, the per-terrain **cost table** and **elevation** are
out of scope here: tiles are treated as `plains` (cost 1) except `blocked`
(impassable). Cost lookups route through `GridModel.get_move_cost()` so a
data-driven cost table can replace the body without touching the pathfinder.

## Tests

GUT suites live in [`tests/grid/`](../../tests/grid/). Run headless from the
repo root:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```
