# HANDOFF — start-of-session brief

*Authoritative "where things stand" doc. Last updated 2026-06-08. Read this, then
`AGENTS.md` and the ADRs, before picking up work.*

---

## 1. What this is

A **card-driven, positionless tactical roguelite** with an RPG progression layer
(see `docs/concept/concept-brief.md` for the original vision; the 2026-06-07 pivot
that made it positionless + stat-driven is recorded in **ADR-0013–0018**). Built in
**Godot 4.6 + GDScript**, data-driven, GUT-tested.

## 2. Run / test / push

```
# Play it (character creation → a full branching RUN: map, combat, rest, events):
godot --path .            # or open project.godot in the editor and press Play

# Run the whole test suite headless (the gate — must be green before any commit):
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
# Currently: 215 passing.

# Push (remote + SSH already configured):
git push
```

Note: an agent built this with a Godot 4.6 binary installed in its sandbox, so it
could self-test. A human/agent without that runs the headless line above as the gate.

## 3. Current state — what works

- **Positionless combat** (ADR-0013): no grid; targeting by kind (`enemy`,
  `all_enemies`, `self`, `ally`, …). The old grid + first UI are quarantined in
  `/attic` behind a `.gdignore` (recoverable, out of build).
- **Stats** (ADR-0014): STR/DEX/CON/INT + `attack_stat` (`str|dex|int`). HP derives
  from CON. The innate Strike/Defend floor and **owned** cards scale with the
  owner's attack stat; **neutral** cards are flat; enemies are flat.
- **`return` exploit closed** (ADR-0017): loader bans `return` on owned damage cards.
- **Classes** (ADR-0015/0016): a class *is* the base character template —
  **Fighter** (STR), **Rogue** (DEX, new finesse kit), **Mage** (INT). A run fields 2.
- **Races** (ADR-0015): **Human / Elf / Orc** placeholders — stat modifier + 1 custom card.
- **Character creation screen** (`src/ui/character_creation.gd`, the `main.tscn`
  entry): pick 2 distinct classes + a race each → launches the run.
- **Map/run UI** (`src/ui/map_view.gd`, P2·10): creation now flows into a full
  branching act — pick a reachable node on the generated map; combat opens the
  interactive `BattleView` on the run's `RunController` (carried HP / run deck /
  races / allocated stats), wins offer a card-reward draft; rest nodes heal or
  upgrade a card; events present choices; level-ups are spent from the party strip;
  clearing the boss wins, a TPK ends the run. Flow logic is in `RunNavigator`
  (tested); the screen is the asset-free view.
- **Run loop** (`src/run/run_controller.gd`, ADR-0011/0012): carries HP across an
  encounter sequence — survivors heal post-win, downed revive at low HP, TPK ends
  the run. Combat split into `begin_combat`/`finish_combat` so the UI drives turns
  interactively; `resolve_combat` composes them for the headless auto-runner.
- **Relics** (ADR-0012, P2·12): light trigger+effect run modifiers (`RelicData`,
  `data/relics/`). `RelicEngine` applies `combat_start` (block/strength) and
  `passive` (max HP) at assembly and `turn_start` (energy/draw) each player turn —
  additive hooks around `EncounterBattle`, no change to `BattleState`. Elites grant
  one; events can too (`add_relic`). Held in `RunState.relics`.
- **Telemetry** (`src/telemetry/`): combat/run events; used to produce the attrition read.

## 4. Known gaps / deferred (NOT yet done)

1. ~~**`run_deck` → combat deck injection.**~~ **DONE 2026-06-08 (commit 4cdbac0).**
   `RunController.resolve_combat` now feeds `run.run_deck` to
   `EncounterAssembler.build`, which assembles the combat deck via the new
   `Deck.assemble_from_card_ids` (falls back to class starting decks if the run
   deck is empty). Race **custom cards** (and any future **drafted** cards) now
   appear in fights. 147 GUT green. *Note: needs `git push` from a machine with the
   repo's SSH key — committed locally, 1 ahead of origin.*
2. ~~**Leveling (P3·05):**~~ **DONE 2026-06-08.** XP from won combats levels each
   surviving member on a linear curve; each level-up grants stat points the player
   allocates across STR/DEX/CON/INT (default 3/level). Allocated points apply on
   top of class + race each fight (CON also raises max HP). Engine in
   `src/run/leveling.gd`; `RunController` awards XP + exposes
   `allocate_stat_point(cid, stat)`; state persists in `RunState`. All knobs on
   `BattleConfig` (`stat_points_per_level`, `xp_per_combat`, `xp_curve_base/step`).
   *Still TODO: a level-up/allocation UI (part of the map/run UI, P2·10) — the
   model + API are ready for a screen or auto-policy to call.* Class **promotion**
   (P3·06) builds on this.
3. ~~**Run is single-fight in the UI.**~~ **DONE 2026-06-08 (P2·10).** Creation now
   flows into a full branching run via `MapView`: generated map, node selection,
   interactive combat through the run layer, card-reward drafts, rest (heal/upgrade)
   and event screens, in-UI level-up allocation, and a win/defeat end screen. All
   node *handlers* exist: combat (P2·06), event (P2·08), rest (P2·07).
   **Relics (P2·12) ✓ DONE 2026-06-08** — see "Relics" in §3.
4. **Class promotion (P3·06)** and **exit-package meta (P3·08, ADR-0018)** — not built.
5. **Save/resume** exists on `RunState` but isn't wired into the run loop.

## 5. The balance finding (important)

The run loop's purpose was to test the **attrition thesis** (does greed get punished
across a run?). Auto-running greedy vs. defensive policies over a full act (40 seeds
each): **both win 100%.** The P3·02 stat buffs (Strike 4→10, scaling cards) made the
current encounters trivial, so the thesis **isn't testable until balance is harder**
(tougher/more enemies, less healing, more fights). **Tabled as a playtest/design call.**
All the knobs are data (`data/battle_config.json`, `data/enemies/*`, `data/encounters/*`).

## 6. Suggested next priorities (pick based on goal)

| Want to… | Do this |
|----------|---------|
| ~~Make builds matter (cards from races/rewards show up)~~ | ~~Wire `run_deck` → combat deck~~ **DONE (gap #1, 4cdbac0)** |
| ~~Deepen characters (XP + stat allocation)~~ | ~~Leveling (P3·05)~~ **DONE (gap #2)** — UI to allocate is part of P2·10 |
| ~~Make it feel like a *run*, not one fight~~ | ~~Map/run UI (P2·10)~~ **DONE** — creation → full run in `MapView` |
| Make combat threatening (attrition real) | **Balance pass** — tune enemies/encounters/healing/relics in data |
| Amplify identity further | **Class promotion (P3·06)** — builds on leveling |
| ~~Add run modifiers~~ | ~~Relic system (P2·12)~~ **DONE** — `RelicEngine` + authored relics |

My recommendation for next session: **balance pass** (cheap, in data, makes
playtesting meaningful) — the whole loop is now playable end-to-end (map → fights
→ rewards/rest/events/relics → boss) with run decks + leveling live, so this is the
moment to playtest and tune (relics that boost the economy will amplify the
still-easy combat — tune together). Then **class promotion (P3·06)**.

## 7. Gotchas / conventions

- **Warnings-as-errors, typed GDScript** — see `AGENTS.md`. No `:=` inferred from `Variant`.
- The class rename **vanguard → fighter** is done in real data; the loader **test
  fixtures still use `vanguard`** intentionally (they test the loader, not content) —
  don't "fix" them.
- **ADRs are append-only.** To change a settled decision, write a new superseding ADR.
- `/attic` is gdignored — don't reference its classes (GridModel/Pathfinder/old battle_view).
- Every non-trivial change ships with GUT tests and must leave the suite green.

## 8. Map of the code

```
src/data/      content resources + ContentDatabase loader (cards, characters=classes,
               enemies, encounters, races, events, relics, statuses, battle_config, encounter_pool)
src/combat/    BattleState (turns/energy/status/targeting), EffectResolver, Combatant,
               EnemyAI, EncounterAssembler/Battle, RelicEngine
src/cards/     Deck, CardPlay
src/run/       RunController, RunState, RunNavigator, Leveling, EventResolver, RestResolver, MapGraph/MapGenerator, CardReward
src/ui/        character_creation → map_view (run) → battle_view (code-driven, asset-free)
src/telemetry/ TelemetryLogger
data/          all authored content (see data/README.md)
docs/          concept-brief, decisions/ (ADRs), systems/ (schemas), progress/, this file
tests/         GUT suites mirroring src/  (215 passing)
```
