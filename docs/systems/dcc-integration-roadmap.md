# DCC Integration Roadmap

*Phased plan for landing the Carl/Donut adaptation. Pairs with
[ADR-0028](../decisions/0028-dcc-carl-donut-class-lines.md) and
[`dcc-adaptation.md`](dcc-adaptation.md). Each phase is independently shippable and
ends with the GUT suite green plus a playtest gate before the next phase starts —
the mod's history says tune what shipped before adding the next system.*

## Phase 0 — Data landing (✅ shipped 2026-06-09, this commit)

58 data files: 2 class characters, 2 progression trees (14 nodes each), Cat race +
Pounce, 47 cards, charm status (inert), 4 relics. Validated against every
ContentDatabase rule (effect registry, status/tag/upgrade/ult references, tree
fanout, return-ban). **Deliberately inert:** nothing offers the new classes yet.
Cat *does* enter the Act-2 recruit pool immediately (it's db-driven) — acceptable,
she's a plain stat template until classed.

## Phase 1 — Enable & first playtest (✅ shipped 2026-06-09)

- Extend `map_view.gd::_show_class_pick` (`[fighter, rogue, mage]` → db-driven or
  append `brawler`, `charmer`). This is the kill-switch flip.
- Add the two lines to `test_progression_tree.gd`'s loop; placeholder class sprites
  (`assets/characters/brawler.png`, `charmer.png` — UiAssets falls back to null safely).
- Playtest gate: both lines complete Acts 1–6 as "plain stat classes with good cards."
  Telemetry to watch: class pick rate, win rate vs Fighter/Mage/Rogue baselines,
  AOE card pick rates (bomb costs are Exhaust-only right now — expect them strong).

## Phase 2 — Charm core + caster-side effects (✅ shipped 2026-06-09)

Two effect-kind extensions (data-schemas §2.3 says: new mechanic = new effect type + handler):

1. **`self_damage`** — applies to the caster regardless of card target; block absorbs,
   STR never amplifies (the mod's THORNS rule). Then: restore bomb taxes (Cobbled
   Bomb/Demolition Charge/Scorched Earth lose Exhaust, gain the tax), add Gut Check.
2. **Charm behavior** — `BattleContext.apply_status` hook: on charm gain, every 10
   stacks crossed applies 2 Vulnerable + 2 Weak; if charm ≥ target max HP, lethal
   HP-loss (bypasses block). Plus `charm_damage` (apply charm = unblocked damage)
   for CHARM-tagged attacks, and a real Coup de Grace pool card (damage = charm, consume it).
- Swap charm into the Charmer cards (Hex, Pounce variant, Incantation) — card JSON
  diffs are pre-specified in dcc-adaptation.md §4.
- Tests: threshold proc boundaries (9→10, 19→20), execute vs block, self_damage
  block interaction. UI: charm needs a visible per-enemy counter (the mod's charm
  bar) — minimal version is the status icon with stacks.
- Playtest gate (mod numbers as reference): charm executes should be rare
  over-investment payoffs, not the default kill path.

## Phase 3 — Fame, Sponsor Boxes, missile tokens (✅ shipped 2026-06-09)

- **Fame counter** on `RunState` (per-act, cap 50, reset at act boundary). Passive
  triggers: no-damage combat +2, fast win +1, elite +3, charm-execute +2.
- **Sponsor Box**: at act-boss kill, tier from final Fame (Bronze 10–24 / Silver
  25–49 / Gold 50) grants a pick from tiered relic pools — the 4 shipped relics
  seed the pools; author ~5 more (gold/shop relics map to this game's Gold economy).
- **`add_card` effect** (generated cards into hand): SpellWeave, Missile Barrage
  X-cost analog, Arcane Dodge's missile rider. Keep missile scaling flat/linear
  (mod lesson #2); revisit **unblockable** only here, instrumented.
- Hooks live in `_resolve_act_end` / `run_controller` next to the existing
  promotion chain; telemetry mirrors the mod's `fame_per_act`, `missiles_generated`.

### Implementation notes (Phases 1–3, 2026-06-09)

Shipped against a green 338-test GUT suite (`docs/progress/2026-06-09-dcc-implementation.md`).
Deviations from the plan as written:

- The class pick is fully **db-driven** (every CharacterData is offered), not an appended array.
- New effect kinds landed as `self_damage`, `self_block`, `charm_damage`,
  `consume_status_damage`, `add_card` — registry + contract updated in `data-schemas.md` §2.3.
- **Vulnerable fix rode along:** card/intent attacks now amplify on Vulnerable targets
  (`apply_effects` folds `VULNERABLE_MULT`); previously only the unused `deal_damage_from`
  path applied it, so the status was inert in real combat.
- **Sponsor Box pools are keyed by relic RARITY** (Bronze→common, Silver→uncommon/rare,
  Gold→boss) instead of bespoke pool data — zero new schema, dedupes owned relics,
  seeded pick. Authoring more relics enriches the pools automatically.
- **Spell Weave is a one-shot "add 2 Magic Missiles to hand"** rather than the mod's
  per-turn engine power (no Powers layer yet — that's the Phase 4 question).
- Fame/Charm tuning numbers live as named constants (`RunController` / `BattleState`),
  the Weak/Vulnerable precedent; promote to data knobs if playtests demand iteration.

## Phase 4 — Conditional & reactive layer (the expensive one; decide scope after Phase 3)

`conditional` effect framework, then in rough value order: Tripwire (intent-read
block), Haymaker pool card (damage = current block), Smush (on-fatal permanent
scaling, **hard-capped**), Counter, Enthrall re-arm aura. A persistent **Powers
layer** (Bomber Studio, Infusion, charm auras) is the biggest ask — cut it if
Phases 2–3 already make the lines feel complete.

## Phase 5 — Flavor & polish

Naming pass (keep ids, change display strings — decide DCC-skin vs own-skin, §7 of
the design doc), card/class art, DCC-flavored events (`data/events/` already
supports add_card/remove_card/heal/damage outcomes — an "AI Announcer" event chain
is pure data), optional meta-unlock gating for the two lines.

## Risk register

| Risk | Mitigation |
|---|---|
| Five-way Act-3 pick overwhelms | meta-unlock gate (Phase 5) or 3-of-5 random offer |
| Charm execute warps boss fights | max-HP rule + telemetry from day one (mod hit this exact wall) |
| Powers layer scope creep | explicitly optional; Phase 4 go/no-go after Phase 3 playtest |
| Exhaust-only bombs overtuned in Phase 1 | known interim state; numbers sit low (4 @0.6) until the tax lands |
| ADR conflicts (0022 three-line wording) | ADR-0028 amends it; review before Phase 1 merge |
