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
| `shield_bash` | vanguard | 1 | exhaust | no | enemy | 6 damage + 1 stun |
| `bulwark` | vanguard | 1 | — | no | self | 8 block + 1 strength |
| `rallying_shout` | vanguard | 1 | — | no | self | 4 block + draw 1 |
| `arcane_bolt` | mage | 1 | return | no | enemy | 5 damage |
| `venom_dart` | mage | 1 | — | no | enemy | 3 damage + 4 poison |
| `frost_nova` | mage | 2 | exhaust | no | all_enemies | 4 damage + 1 weak (AoE) |
| `mana_surge` | mage | 0 | exhaust | no | self | +2 energy + draw 2 |
| `field_dressing` | neutral | 1 | — | no | ally | heal 6 |

Keyword coverage: `exhaust` ×3 (`shield_bash`, `frost_nova`, `mana_surge`); `return` ×1 (`arcane_bolt`).

## Characters (`characters/`)
CharacterData per §4. Both share innate actions `["strike","defend"]`.

Stats (ADR-0014): STR/DEX/CON/INT + `attack_stat`. `max_hp` is derived (CON × `hp_per_con`=2).

| id | STR | DEX | CON | INT | attack_stat | max_hp | tags | starting_deck |
|----|-----|-----|-----|-----|-------------|--------|------|---------------|
| `vanguard` | 6 | 5 | 17 | 1 | str | 34 | melee | shield_bash, bulwark, rallying_shout, field_dressing |
| `mage` | 1 | 3 | 12 | 6 | int | 24 | caster | arcane_bolt, venom_dart, frost_nova, mana_surge, field_dressing |

The assembled shared deck for the prototype party = union of both `starting_deck` lists.

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

## Battle config (`battle_config.json`)
BattleConfig per §7: `energy_per_turn: 3`, `draw_per_turn: 5`, `max_hand: 10`,
`reshuffle_discard: true`.

## Reference integrity
- Every card `character_tag` is `neutral` or an existing character id (`vanguard`/`mage`).
- Every `effect.type` is in the §2.3 prototype registry.
- Every `effect.status` resolves to a defined StatusData id.
- Every character `starting_deck` / `innate_actions` id is a defined card.
- Every encounter `enemies` id is a defined enemy id.
- All ids are snake_case and globally unique.
