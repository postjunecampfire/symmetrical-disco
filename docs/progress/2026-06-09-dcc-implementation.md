# 2026-06-09 — DCC adaptation: Phases 0–3 implemented

*Session record for [ADR-0028](../decisions/0028-dcc-carl-donut-class-lines.md) /
[`dcc-adaptation.md`](../systems/dcc-adaptation.md) /
[`dcc-integration-roadmap.md`](../systems/dcc-integration-roadmap.md). Source
material: the Dungeon Crawler Carl StS mod at `~/Claude/Crawl/Crawler`.*

## Result

**GUT: 338/338 passing** (was 316 before the session; +22 tests across
`tests/combat/test_dcc_mechanics.gd` (13) and `tests/run/test_fame.gd` (9),
plus the extended progression-tree loop). Run with Godot 4.6 headless:
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`.

## What shipped

**Phase 0 — content (58 data files).** Brawler (Carl, STR) and Charmer (Donut, INT)
class characters + 14-node progression trees ending in the book classes
(Compensated Anarchist, Former Child Actor, Royal Bodyguard, Princess…); Cat race
(+ Pounce); 49 cards incl. 16 capstone Ults; `charm` status; 4 Sponsor-tier relics;
placeholder 32×32 sprites for brawler / charmer / cat.

**Phase 1 — enablement.** `map_view._show_class_pick` is db-driven: every
CharacterData is a pickable class line at the Act-3 boundary (5 lines now).

**Phase 2 — engine.** Five new effect kinds (registry + resolver + contract docs):

| Kind | Behaviour |
|---|---|
| `self_damage` | bomb tax — once per card, on the caster; block absorbs; never stat-amplified |
| `self_block` | caster-side block rider (Gut Check), DEX-scaled |
| `charm_damage` | attack applying Charm equal to UNBLOCKED damage (block soaks both) |
| `consume_status_damage` | Coup de Grace — damage = target's stacks of `status`, then remove them |
| `add_card` | token generation into the caster's hand (Magic Missile engines) |

Charm behaviour in `BattleState`: +2 Vulnerable / +2 Weak per 10 stacks crossed;
execute (hp→0 through block) at stacks ≥ max HP, counted in `battle.charm_executes`.
**Rode along:** Vulnerable now actually amplifies card/intent attacks —
`apply_effects` folds `VULNERABLE_MULT`; previously only the unused
`deal_damage_from` path did, so the status was inert in live combat.

**Phase 3 — run layer.** `RunState.fame` (per-act, cap 50, serialized). Triggers in
`RunController.finish_combat`: flawless +2, ≤2-turn win +1, elite band +3 (the node
band now rides on `battle.band`), +2 per Charm execute. `advance_act` opens the
Sponsor Box: Bronze 10+ → common relic, Silver 25+ → uncommon/rare, Gold 50 → boss;
seeded pick, owned-relic dedupe, telemetry (`sponsor_box` event, `fame_gained` /
`fame` on `combat_result`), announced via the act-transition banner
(`last_sponsor_relic`). Cards swapped to the real mechanics: bombs carry taxes
again, Hex/Incantation/Grand Incantation/Bewitching Gaze apply Charm, Play to the
Crowd is a `charm_damage` attack, Coup de Grace cash-in added, Spell Weave /
Arcane Dodge generate Magic Missiles.

## Files touched (code)

`content_database.gd` (effect registry + add_card/consume validation),
`effect_resolver.gd`, `battle_context.gd`, `battle_state.gd`,
`encounter_assembler.gd` (card_lookup injection), `run_controller.gd` (fame +
sponsor box + band stamp), `run_state.gd` (fame persistence), `map_view.gd`
(db-driven class pick + sponsor banner), plus ~20 card JSONs and 2 new test files.

## Next (per the roadmap)

- **Playtest gates** for Phases 1–3 are now the blocker: class pick rates, bomb-tax
  feel, Charm execute frequency (should be over-investment, not the default kill),
  Fame tier distribution. Telemetry fields are in place.
- **UI debt:** Charm shows as a generic status count — the mod's purple charm bar
  is the polish target. Sponsor Box is auto-granted; a 1-of-2 pick overlay would
  match the promotion-chain pattern.
- **Phase 4 go/no-go** (conditionals / Powers layer) after those playtests; Phase 5
  flavor pass independent.
