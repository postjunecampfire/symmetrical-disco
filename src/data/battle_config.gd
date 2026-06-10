class_name BattleConfig
extends Resource
## Global battle tunables (data-schemas.md §7).

## SUPERSEDED by energy_per_character (ADR-0025) — kept only so legacy fixtures
## parse; nothing reads it at runtime.
@export var energy_per_turn: int = 3
## Per-character energy refilled at player-phase start (ADR-0025). Deliberately
## NOT a copy of 0017's shared 3: two pools ≈ double board energy and +1 energy
## ≈ a 33%% throughput swing, so the per-character base starts at 2 (re-tuned in
## prototyping, per the ADR).
@export var energy_per_character: int = 2
@export var draw_per_turn: int = 5

# --- Derived decks from skill loadouts (ADR-0026) ----------------------------
## Active loadout slots per member — the global cooldown dial (ADR-0006), now a
## player-facing build knob. 10 slots × 3 copies = 30-card ceiling.
@export var skill_slots: int = 10
## Copies contributed to the derived deck per skill, by rarity (ADR-0026: the
## rare ×-multiplier appears once per shuffle — the ADR-0020 guardrail for free).
@export var copies_common: int = 3
@export var copies_uncommon: int = 2
@export var copies_rare: int = 1
## Minimum derived deck size; shortfalls auto-fill with basic Strike/Defend
## (alternating). At hand 5 a 20-card deck cycles in 4 turns — rares stay rare.
@export var derived_deck_floor: int = 20
## Hard lower bound on the auto-fill floor after relic `floor_reduction` effects
## (ADR-0029): the earned path back to the small-deck archetype can never push
## the floor below this.
@export var derived_deck_floor_min: int = 12

# --- Run currency (ADR-0023 slice) -------------------------------------------
## Gold earned for clearing a node of each kind (jittered ±25% by the run RNG).
@export var gold_per_combat: int = 12
@export var gold_per_elite: int = 25
@export var gold_per_boss: int = 40
## Shop prices by skill rarity, plus relic and heal services (ADR-0023). Each is
## scaled by (1 + shop_act_scale * (act - 1)) so deeper merchants charge more.
@export var shop_price_common: int = 55
@export var shop_price_uncommon: int = 85
@export var shop_price_rare: int = 140
@export var shop_price_relic: int = 120
@export var shop_price_heal: int = 35
## ADR-0029: consumable item cards on the shelf, and the "remove a curse"
## service — StS-style removal returns ONLY for curses (loadout deactivation
## stays the free knob for skills). Scaled by shop_act_scale like other prices.
@export var shop_price_consumable: int = 40
@export var shop_price_curse_removal: int = 75
@export var shop_act_scale: float = 0.15
## Treasure-node gold pile bounds (ADR-0023).
@export var treasure_gold_min: int = 25
@export var treasure_gold_max: int = 60
@export var max_hand: int = 10
@export var reshuffle_discard: bool = true
## HP granted per point of CON (ADR-0014: CON -> max HP). A character's max_hp is
## derived as `base_hp + constitution * hp_per_con` (ADR-0021 pt1).
@export var hp_per_con: int = 2
## Flat HP floor added once per member (ADR-0021 pt1): with races as low base
## templates (CON 2–5), pure CON×hp_per_con bottoms out at one-shot range; this
## keeps the fragile origin survivable. Tuning partner of hp_per_con
## (act-1-3-balance-proposal §4).
@export var base_hp: int = 4
## HP a downed unit revives at for the next encounter (ADR-0011, run layer).
@export var revive_hp: int = 8
## Fixed HP restored to each surviving unit after a won combat (ADR-0011).
@export var post_combat_heal: int = 5
## HP restored to each living party member by the "heal" choice at a rest node
## (run-structure.md §5, P2·07). Tunable; larger than post_combat_heal by design.
@export var rest_heal: int = 12

# --- Leveling (ADR-0015, P3·05) ---------------------------------------------
## Stat points a character may allocate on each level-up (ADR-0015 default 3).
@export var stat_points_per_level: int = 3
## Automatic growth (owner, 2026-06-10): EVERY stat also rises by this much on
## each level-up, before the player's 3 chosen points — keeps the party's HP
## and output floor tracking the act curve without making allocation moot.
## CON's share flows into max HP via hp_per_con like any other CON.
@export var auto_stats_per_level: int = 1
## XP awarded to each surviving party member for winning a combat.
@export var xp_per_combat: int = 10
## XP required to advance from level 1 to level 2 (the curve's base step).
@export var xp_curve_base: int = 30
## Extra XP added to each successive level's requirement: the XP to go from
## level L to L+1 is `xp_curve_base + xp_curve_step * (L - 1)` (a linear ramp).
@export var xp_curve_step: int = 20
## Levels per class promotion (P3·06): a character may take its Nth promotion once
## it reaches `promotion_level * N`. Default 20 (≈2–3 acts to the first).
@export var promotion_level: int = 20
## Acts cleared per cross-run meta cash-out (P3·08): the Nth boon unlocks after
## `meta_cash_out_acts * N` total acts cleared across runs. Default 9.
@export var meta_cash_out_acts: int = 9

# --- Enemy level scaling (ADR-0019, EnemyScaler) ----------------------------
## The enemy level at which base enemy stat blocks (data/enemies/*) are authored:
## EnemyScaler.factor(baseline) == 1.0, so an enemy fought at its baseline level is
## unscaled. The per-act level CURVE (and its tier-gate spikes) is authored in
## act_progression.json; this only sets where "1.0x" sits. Calibrating the baseline
## against the authored Act-1 roster is a balance/roster-pass decision (ADR-0019).
@export var enemy_scale_baseline_level: int = 1
## Convexity of the level->stat factor (EnemyScaler): `factor = (level/baseline) ^
## exponent`. 1.0 == stats track level proportionally (the "linear" ADR-0019
## option, since the gate spikes already live in the level bands); > 1.0 ==
## mild-exponential. The final value is a balance decision.
@export var enemy_scale_exponent: float = 1.0
