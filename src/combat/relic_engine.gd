class_name RelicEngine
extends RefCounted
## Applies relic effects at their triggers (run-structure.md §7/§8, P2·12). This is
## an ADDITIVE wrapper around an assembled battle — it never edits BattleState's
## resolved rules; the assembler calls the combat_start / passive hooks once, and
## EncounterBattle calls the turn_start hook at each player turn.
##
## It depends only on BattleState + RelicData (no run layer), so it lives in
## src/combat. Each hook ignores relics whose trigger doesn't match, so the same
## relic list can be handed to every hook.

## combat_start relics: gain_block / add_strength to each living party member.
func apply_combat_start(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"combat_start":
			continue
		match relic.effect:
			&"gain_block":
				for unit in battle.living_players():
					unit.block += relic.amount
			&"add_strength":
				for unit in battle.living_players():
					unit.add_status_stacks(&"strength", relic.amount)
			_:
				pass


## passive relics: max_hp_up raises each member's max HP (and current HP so a fresh
## spawn stays full). Applied before carried HP so the carried value clamps to the
## raised max.
func apply_passive(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"passive":
			continue
		if relic.effect == &"max_hp_up":
			for unit in battle.living_players():
				unit.max_hp += relic.amount
				unit.hp += relic.amount


## turn_start relics: gain_energy / draw_extra, applied after the base
## start_player_turn has refilled energy and drawn the hand.
func apply_turn_start(battle: BattleState, relics: Array) -> void:
	for relic in relics:
		if relic == null or relic.trigger != &"turn_start":
			continue
		match relic.effect:
			&"gain_energy":
				battle.add_energy(relic.amount)
			&"draw_extra":
				battle.draw_cards(relic.amount)
			_:
				pass
