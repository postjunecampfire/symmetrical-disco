extends "res://addons/gut/test.gd"
## GUT suite for the tile-target degrade in src/combat/battle_state.gd.
##
## Regression coverage for the Frost Nova crash: a TILE/AREA card resolves to a
## Vector2i cell, so the resolver hands a unit-targeting BattleContext method a
## tile rather than a Combatant. The old `target as Combatant` was a HARD error
## (casting a built-in Variant to an Object class), not a graceful null. The fix
## routes every unit-target method through `_resolve_unit()`, which:
##   - returns a Combatant passed directly (no regression),
##   - degrades a tile to the SINGLE occupant of that tile, and
##   - safely no-ops on an empty tile (or any non-unit value).
##
## True multi-tile AoE (radius > 0) remains deferred per data-schemas §11; this
## proves the single-occupant degrade and the no-crash contract.

const BattleStateScript := preload("res://src/combat/battle_state.gd")
const CombatantScript := preload("res://src/combat/combatant.gd")


# --- Fixtures (mirrors test_battle_state.gd) --------------------------------

func _config(energy: int = 3, draw: int = 0) -> BattleConfig:
	var c := BattleConfig.new()
	c.energy_per_turn = energy
	c.draw_per_turn = draw
	c.max_hand = 10
	c.reshuffle_discard = true
	return c


func _status_defs() -> Dictionary:
	var defs := {}
	defs[&"poison"] = _status(&"poison", &"intensity", true)
	defs[&"block"] = _status(&"block", &"intensity", true)
	defs[&"stun"] = _status(&"stun", &"duration", true)
	defs[&"strength"] = _status(&"strength", &"intensity", false)
	defs[&"weak"] = _status(&"weak", &"duration", true)
	return defs


func _status(id: StringName, stacking: StringName, decays: bool) -> StatusData:
	var s := StatusData.new()
	s.id = id
	s.display_name = String(id)
	s.stacking = stacking
	s.decays_each_turn = decays
	return s


func _character(hp: int, move_range: int = 3) -> CharacterData:
	var d := CharacterData.new()
	d.id = &"hero"
	d.display_name = "Hero"
	d.max_hp = hp
	d.move_range = move_range
	return d


func _enemy_data(hp: int, move_range: int = 2) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"grunt"
	d.display_name = "Grunt"
	d.max_hp = hp
	d.move_range = move_range
	return d


func _state(energy: int = 3, draw: int = 0) -> BattleState:
	var cfg := _config(energy, draw)
	var grid := GridModel.new(Vector2i(8, 8))
	var deck := Deck.new(cfg)
	return BattleStateScript.new(cfg, grid, deck, _status_defs())


func _add_player(state: BattleState, hp: int, pos: Vector2i) -> Combatant:
	var unit := CombatantScript.from_character(_character(hp), pos)
	return state.add_combatant(unit)


func _add_enemy(state: BattleState, hp: int, pos: Vector2i) -> Combatant:
	var unit := CombatantScript.from_enemy(_enemy_data(hp), pos)
	return state.add_combatant(unit)


# --- deal_damage by tile ----------------------------------------------------

func test_deal_damage_by_tile_hits_the_occupant() -> void:
	# Frost Nova case: the resolver passes a Vector2i cell, not the Combatant. The
	# damage must land on whoever stands on that tile.
	var state := _state()
	var tile := Vector2i(4, 4)
	var enemy := _add_enemy(state, 20, tile)

	state.deal_damage(tile, 7)

	assert_eq(enemy.hp, 13, "tile-targeted damage hit the tile's occupant")


func test_deal_damage_on_empty_tile_is_a_safe_noop() -> void:
	# The original crash: `some_vector2i as Combatant` is a hard error. An empty
	# tile must resolve to null and no-op — no crash, nothing changes.
	var state := _state()
	var enemy := _add_enemy(state, 20, Vector2i(4, 4))

	state.deal_damage(Vector2i(0, 0), 7)  # nobody on (0,0)

	assert_eq(enemy.hp, 20, "no occupant on the empty tile means nothing took damage")


func test_deal_damage_by_tile_can_kill_and_frees_tile() -> void:
	var state := _state()
	var tile := Vector2i(3, 5)
	var enemy := _add_enemy(state, 5, tile)

	state.deal_damage(tile, 99)

	assert_eq(enemy.hp, 0, "tile-targeted lethal clamps at 0")
	assert_false(enemy.is_alive())
	assert_false(state.grid.is_occupied(tile), "dead unit freed its tile")


# --- apply_status by tile ---------------------------------------------------

func test_apply_status_by_tile_affects_the_occupant() -> void:
	var state := _state()
	var tile := Vector2i(2, 6)
	var enemy := _add_enemy(state, 20, tile)

	state.apply_status(tile, &"poison", 3)

	assert_eq(enemy.status_stacks(&"poison"), 3, "tile-targeted status hit the occupant")


func test_apply_status_on_empty_tile_is_a_safe_noop() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 20, Vector2i(2, 6))

	state.apply_status(Vector2i(7, 7), &"poison", 3)  # empty tile

	assert_eq(enemy.status_stacks(&"poison"), 0, "no occupant means no status applied")


# --- add_block / heal by tile -----------------------------------------------

func test_add_block_by_tile_affects_the_occupant() -> void:
	var state := _state()
	var tile := Vector2i(1, 1)
	var player := _add_player(state, 30, tile)

	state.add_block(tile, 4)

	assert_eq(player.block, 4, "tile-targeted block hit the occupant")


func test_heal_by_tile_affects_the_occupant() -> void:
	var state := _state()
	var tile := Vector2i(1, 2)
	var player := _add_player(state, 30, tile)
	state.deal_damage(player, 10)
	assert_eq(player.hp, 20)

	state.heal(tile, 5)

	assert_eq(player.hp, 25, "tile-targeted heal hit the occupant")


# --- no regression: a Combatant passed directly still works -----------------

func test_deal_damage_with_combatant_directly_still_works() -> void:
	# The common path: the resolver hands a real Combatant. _resolve_unit must
	# return it unchanged so unit-targeted cards are unaffected by the fix.
	var state := _state()
	var enemy := _add_enemy(state, 20, Vector2i(4, 4))

	state.deal_damage(enemy, 8)

	assert_eq(enemy.hp, 12, "direct Combatant target still takes damage")


func test_apply_status_with_combatant_directly_still_works() -> void:
	var state := _state()
	var enemy := _add_enemy(state, 20, Vector2i(4, 4))

	state.apply_status(enemy, &"weak", 2)

	assert_eq(enemy.status_stacks(&"weak"), 2, "direct Combatant status still applies")
