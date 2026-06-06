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
CardData per §3. Two innate actions (`innate: true`, `character_tag: neutral`) plus 10 skill cards.

| id | character_tag | cost | keywords | innate | effects summary |
|----|---------------|------|----------|--------|-----------------|
| `strike` | neutral | 1 | — | yes | 4 damage, melee |
| `defend` | neutral | 1 | — | yes | 5 block, self |
| `shield_bash` | vanguard | 1 | exhaust | no | 6 damage + 1 stun |
| `bulwark` | vanguard | 1 | — | no | 8 block + 1 strength (self) |
| `cleaving_blow` | vanguard | 2 | — | no | 9 damage + push 1 |
| `rallying_shout` | vanguard | 1 | — | no | 4 block + draw 1 (self) |
| `arcane_bolt` | mage | 1 | return | no | 5 damage at range |
| `venom_dart` | mage | 1 | — | no | 3 damage + 4 poison |
| `frost_nova` | mage | 2 | exhaust | no | 4 damage + 1 weak (area r1) |
| `mana_surge` | mage | 0 | exhaust | no | +2 energy + draw 2 (self) |
| `field_dressing` | neutral | 1 | — | no | heal 6 (ally) |
| `reposition` | neutral | 0 | — | no | move + draw 1 |

Keyword coverage: `exhaust` ×3 (`shield_bash`, `frost_nova`, `mana_surge`); `return` ×1 (`arcane_bolt`).

## Characters (`characters/`)
CharacterData per §4. Both share innate actions `["strike","defend"]`.

| id | max_hp | move_range | tags | starting_deck |
|----|--------|------------|------|---------------|
| `vanguard` | 34 | 3 | melee | shield_bash, bulwark, cleaving_blow, rallying_shout, field_dressing, reposition |
| `mage` | 24 | 3 | caster | arcane_bolt, venom_dart, frost_nova, mana_surge, field_dressing, reposition |

The assembled shared deck for the prototype party = union of both `starting_deck` lists.

## Enemies (`enemies/`)
EnemyData per §5, all `intent_pattern: random_weighted`.

| id | max_hp | move_range | intents |
|----|--------|------------|---------|
| `grunt` | 22 | 2 | slash (7 dmg, w3), guard (6 block, w1) |
| `archer` | 16 | 3 | shot (5 dmg ranged, w3), crippling shot (2 dmg + weak, w2) |
| `brute` | 38 | 2 | smash (11 dmg + push, w3), roar (+2 strength, w1) |

## Encounter (`encounters/`)
EncounterData per §6.

- `skirmish_01` — "Ambush at the Ford", grid 6×6, 2 player spawns, 3 enemy spawns
  (grunt, archer, brute), `win_condition: defeat_all`.

## Battle config (`battle_config.json`)
BattleConfig per §7: `energy_per_turn: 3`, `draw_per_turn: 5`, `max_hand: 10`,
`reshuffle_discard: true`.

## Reference integrity
- Every card `character_tag` is `neutral` or an existing character id (`vanguard`/`mage`).
- Every `effect.type` is in the §2.3 prototype registry.
- Every `effect.status` resolves to a defined StatusData id.
- Every character `starting_deck` / `innate_actions` id is a defined card.
- Every encounter `enemy_spawns.enemy` is a defined enemy id.
- All ids are snake_case and globally unique.
