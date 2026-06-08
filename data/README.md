# Data — Sample Content Pack (P1·11)

Authored content for the first playable prototype. All files are JSON authoring sources that
conform to the contract in [`docs/systems/data-schemas.md`](../docs/systems/data-schemas.md)
(§2–§7) and respect ADR-0004 (shared deck), ADR-0005 (innate Strike/Defend), and
ADR-0006 (draw = cooldown). Only prototype effect types (§2.3) and prototype statuses (§2.4)
are used. No code, no project settings, no docs were modified.

## Statuses (`status/`)
StatusData per §2.4.

| id | display_name | stacking | decays_each_turn |
|----|--------------|----------|------------------|
| `block` | Block | intensity | true |
| `poison` | Poison | intensity | true |
| `stun` | Stun | duration | true |
| `strength` | Strength | intensity | false |
| `weak` | Weak | duration | true |

## Cards (`cards/`)
CardData per §3. Two innate actions (`innate: true`, `character_tag: neutral`) plus 8 skill cards.
Positionless (ADR-0013): targets are by kind (`enemy` / `self` / `ally` / `all_enemies`); no range.
`cleaving_blow` (push) and `reposition` (move) were **cut** with the grid — their knockback /
repositioning concepts will return as positionless-native cards later.

| id | character_tag | cost | keywords | innate | target | effects summary |
|----|---------------|------|----------|--------|--------|-----------------|
| `strike` | neutral | 1 | — | yes | enemy | 4 damage |
| `defend` | neutral | 1 | — | yes | self | 5 block |
| `shield_bash` | fighter | 1 | exhaust | no | enemy | 6 damage + 1 stun |
| `bulwark` | fighter | 1 | — | no | self | 8 block + 1 strength |
| `rallying_shout` | fighter | 1 | — | no | self | 4 block + draw 1 |
| `quick_stab` | rogue | 1 | — | no | enemy | 4 damage |
| `venom_strike` | rogue | 1 | — | no | enemy | 3 damage + 3 poison |
| `shadowstep` | rogue | 1 | — | no | self | 4 block + draw 1 |
| `fan_of_knives` | rogue | 2 | exhaust | no | all_enemies | 3 damage (AoE) |
| `arcane_bolt` | mage | 1 | — | no | enemy | 5 damage |
| `venom_dart` | mage | 1 | — | no | enemy | 3 damage + 4 poison |
| `frost_nova` | mage | 2 | exhaust | no | all_enemies | 4 damage + 1 weak (AoE) |
| `mana_surge` | mage | 0 | exhaust | no | self | +2 energy + draw 2 |
| `field_dressing` | neutral | 1 | — | no | ally | heal 6 |

Owned card damage scales with its owner's `attack_stat` (fighter→STR, rogue→DEX, mage→INT); neutral cards are flat (ADR-0014/0016).

Keyword coverage: `exhaust` ×3 (`shield_bash`, `frost_nova`, `mana_surge`). `return` is reserved for low/no-damage utility — banned on owned (stat-scaling) damage cards (ADR-0017), so no current card uses it.

## Classes / Characters (`characters/`)
CharacterData per §4 — in this game a **class** *is* the base character template
(ADR-0015). All share innate `["strike","defend"]`. Stats (ADR-0014): STR/DEX/CON/INT
+ `attack_stat` (`str` \| `dex` \| `int`). `max_hp` is derived (CON × `hp_per_con`=2).

| id | STR | DEX | CON | INT | attack_stat | max_hp | starting_deck |
|----|-----|-----|-----|-----|-------------|--------|---------------|
| `fighter` | 6 | 5 | 17 | 1 | str | 34 | shield_bash, bulwark, rallying_shout, field_dressing |
| `rogue` | 2 | 6 | 12 | 2 | dex | 24 | quick_stab, venom_strike, shadowstep, field_dressing |
| `mage` | 1 | 3 | 12 | 6 | int | 24 | arcane_bolt, venom_dart, frost_nova, mana_surge, field_dressing |

A run fields **2** of these (ADR-0016); the shared deck is the union of the chosen
classes' `starting_deck` lists. Race (above) modifies the chosen class at creation.

## Races (`races/`)
RaceData (ADR-0015) — a small stat modifier + one custom (neutral) card, applied to a
character at creation. **Placeholders — replace/extend freely.**

| id | STR | DEX | CON | INT | custom_card |
|----|-----|-----|-----|-----|-------------|
| `human` | +1 | +1 | +1 | +1 | human_versatility (draw 1) |
| `elf` | +0 | +2 | +0 | +2 | elven_focus (+1 energy, exhaust) |
| `orc` | +2 | +0 | +2 | +0 | orcish_rage (+1 Strength) |

## Enemies (`enemies/`)
EnemyData per §5, all `intent_pattern: random_weighted`.

| id | max_hp | intents |
|----|--------|---------|
| `grunt` | 22 | slash (7 dmg, w3), guard (6 block, w1) |
| `archer` | 16 | shot (5 dmg, w3), crippling shot (2 dmg + weak, w2) |
| `brute` | 38 | smash (11 dmg, w3), roar (+2 strength, w1) |

(`push`/`move` effects were removed from intents with the grid, ADR-0013.)

## Encounter (`encounters/`)
EncounterData per §6.

- `skirmish_01` — "Ambush at the Ford", enemies: grunt, archer, brute (positionless),
  `win_condition: defeat_all`.

## Events (`events/`)
EventData (run-structure.md §6, P2·08) — a minimal event node: title/body + 2–3
choices, each a label plus typed outcome deltas
(`heal`/`damage_party`/`add_card`/`remove_card`/`add_relic`/`nothing`). Resolved
by `EventResolver` against the RunState.

- `evt_wandering_medic` — heal 8 / take a `field_dressing` card / walk away.
- `evt_cursed_shrine` — take damage + a relic / trade a card for a heal / leave.

## Battle config (`battle_config.json`)
BattleConfig per §7: `energy_per_turn: 3`, `draw_per_turn: 5`, `max_hand: 10`,
`reshuffle_discard: true`, `rest_heal: 12` (rest-node heal, P2·07). Leveling knobs
(ADR-0015 / P3·05): `stat_points_per_level: 3`, `xp_per_combat: 10`,
`xp_curve_base: 30`, `xp_curve_step: 20`.

## Card upgrades (`cards/*.json` with `upgrade_of`)
A card may declare `upgrade_of: <base_card_id>`, marking it the upgraded variant
of that base (run-structure.md §5, P2·07). A rest node's "upgrade" choice swaps a
base copy in the run deck for its variant. Example: `shield_bash_plus`
(`upgrade_of: shield_bash`) — 9 dmg + Stun 2 vs. the base 6 dmg + Stun 1.
**Numbers are placeholder/tunable.**

## Reference integrity
- Every card `character_tag` is `neutral` or an existing character id (`vanguard`/`mage`).
- Every `effect.type` is in the §2.3 prototype registry.
- Every `effect.status` resolves to a defined StatusData id.
- Every character `starting_deck` / `innate_actions` id is a defined card.
- Every encounter `enemies` id is a defined enemy id.
- All ids are snake_case and globally unique.
