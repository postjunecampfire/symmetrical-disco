# HANDOFF — start-of-session brief

*Authoritative "where things stand" doc. Last updated 2026-06-10. Read this, then
`AGENTS.md` and the ADRs, before picking up work.*

> **2026-06-10 session — the 0021-pt1 → 0025 → 0026 schema epoch + StS-style UI
> (298 GUT green, run in-sandbox on Godot 4.6 arm64; human gate still advised).**
> - **ADR-0029 LIVE (M3 injected card layer — agent decision, owner to ratify):**
>   per-member CURSES (`RunState.member_curses`) count toward the derived-deck
>   floor (each displaces one Strike/Defend fill; above the floor they swell);
>   party CONSUMABLES (`RunState.consumables`) inject ON TOP into the first
>   member's deck, exhaust + are consumed from the inventory when played.
>   `card_kind: skill|curse|consumable` on CardData (non-skill NEVER in reward
>   pools); `unplayable` keyword = dead draw (CardPlay + hand-UI guard);
>   `on_draw_damage` for active curses (hex_mark/vertigo). New effects
>   `inflict_curse`/`cleanse`/`gain_gold`; event ops `add_curse`/`remove_curse`/
>   `add_consumable`; shop sells 2 consumables + "Remove a curse"
>   (`shop_price_curse_removal` 75, the ONLY card removal — skills stay free via
>   loadout); treasure can roll an item; relic effect `floor_reduction`
>   ("Travel Light", −4, min floor 12). Content: 8 curses, 10 consumables;
>   hexer/coven_witch inflict; evt_cursed_shrine now curses; evt_peddlers_cache
>   new. Old saves remain compatible (new keys default empty).
> - **ADR-0021 pt1 LIVE:** races are BASE stat templates (pinned: Human 3/3/3/3 ·
>   Elf 2/5/2/5 · Orc 5/3/4/2; JSON uses plain stat keys, legacy `*_mod` still
>   parses); classes are small overlays (+2/+1 style). HP = **`base_hp` (new
>   knob, 4) + CON × hp_per_con** — fighter 6, orc-fighter 14, elf-mage 8. The
>   party is now genuinely fragile; **scaled Act-1 fights are winnable
>   (20/20 scripted greedy)**, unscaled authored blocks are deadly (by design).
> - **ADR-0025 LIVE:** per-character energy (`energy_per_character: 2`;
>   `energy_per_turn` is dead config). `BattleState.energy` is GONE → use
>   `energy_of(unit)` / `spend_energy` / `add_energy(n, unit)`; CardPlay = owner
>   pays. `gain_energy` credits the caster; party-level relics credit the FIRST
>   living player (provisional until relics get holders).
> - **ADR-0026 LIVE:** per-member skill collections + active loadouts on
>   RunState (`run_deck` is GONE); `SkillLoadout.derive_deck()` = copies by
>   rarity (3/2/1) + alternating Strike/Defend auto-fill to the 20 floor (knobs
>   on BattleConfig). Strike/Defend are ordinary commons (ADR-0005 reversed;
>   `play_innate` deleted). Drafts/events/boons/promotions grant SKILLS
>   (auto-activate while ≤10 slots free — **loadout editor UI still TODO**);
>   rest-upgrade swaps the skill id (all copies upgrade). Rarity audit done
>   (mana_surge → uncommon = the engine-stacking cap from the playtest).
>   **Per-fight seeds + assembly shuffle landed** (the repeated-opening-hand bug
>   is fixed); old saves are incompatible (run_deck removed) — delete stale
>   `user://saves`.
> - **StS-style UI (owner reference screenshots):** map = parchment sheet,
>   icon-only inked nodes, dashed paths (`MapSheet._draw`), red reachable rings,
>   bigger boss glyph; **all 18 acts now 17 rows + boss**. Combat = enemies
>   LEFT / party RIGHT, big DCSS sprites with **HP bars + captions underneath**,
>   card fan bottom-center (icon-top cards), per-member energy in captions.
>   Post-combat = **"Rewards!" popup** (take Gold / relic-on-elite / "Add a
>   card") → **"Choose a Card"** with three big visual cards. **Run currency
>   (Gold) added** (ADR-0023 slice): `RunState.currency`, earn knobs
>   `gold_per_combat/elite/boss` (12/25/40 ±25%), shown on the map header.
>   Shop/treasure nodes still TODO.
> - **Harness act-parameterized (proposal §7, DONE):** `attrition_sim [seeds]
>   [act]` (args after `--`) now band-scales every fight via the EnemyScaler
>   (act 0 = legacy unscaled) and pre-levels the party ~1 level per prior act.
>   `resolve_combat` gained an optional `band` arg. New GUT **lockstep guard**:
>   `test_factor_is_linear_lockstep` fails if the factor shape ever goes
>   non-linear (the dex-turtle re-opener). **First reads under the new economy
>   (40/20 seeds, kit-only decks — a LOWER bound, drafts not emulated):**
>   - **Act 1: defensive 35% > greedy 12.5% > dex-turtle 2.5% > turtle 0%.**
>     The Goldilocks ORDERING the attrition thesis wants, and the perfect-turtle
>     dominance is **dead** — under 0026/0025 block is drawn (not innate) and
>     costs half a per-character pool. The block-economy "feel decision"
>     (HANDOFF §5) may be resolved structurally; re-confirm after drafts.
>   - **Acts 2–3 (pre-rosters): 0%, everyone at `enc_combat_04`** → fixed by
>     the per-act rosters below; see the updated reads there.
> - **Per-act encounter rosters LIVE (ADR-0019 content remainder, 2026-06-10):**
>   `act_progression.json` gains **`tier_pools`** (per-tier combat/elite/boss
>   id lists; per-act `encounters` key overrides); loader attaches them to
>   `ActConfig.encounter_pool` + validates every id resolves;
>   `RunNavigator.encounter_for` draws from the CURRENT act's roster (global
>   `encounter_pool.json` = fallback only). **14 new encounters** authored
>   (enc_t1_* light Weak-only fights … enc_t6_legion), Hard templates pushed to
>   tier 3+. Harness fights each act's authored ladder now.
>   **Reads with rosters (20 seeds, kit-only lower bound):**
>   - **Act 1: defensive 80% · greedy/turtle/dex-turtle 25%.** Forgiving, with
>     balanced play clearly best — on the proposal's target.
>   - **Act 2: defensive reaches the boss 20/20 and dies there (×1.375);
>     Act 3: deaths move up to the elite (×1.75).** The within-tier ramp walls
>     a kit-only autoplay party; real parties carry ~4 drafts + upgrades +
>     relics by then, which the sim does NOT emulate — next harness improvement
>     is draft emulation. If real play confirms the wall, the data knob is the
>     tier-1 elite/boss band levels (proposal option B) — owner call.
> - **Shop + treasure nodes LIVE (ADR-0023 COMPLETE, 2026-06-10):** `shop` /
>   `treasure` node kinds with per-act weights + **guarantees** (≥1 of each per
>   act, `_ensure_type_present` reuse); both stay fog-visible per the ADR
>   refinement. `src/run/shop.gd` (`Shop`): deterministic per-node offers —
>   3 skills (CardReward draft) + 1 un-owned relic + party heal — priced from
>   BattleConfig (`shop_price_*`, common 55 / uncommon 85 / rare 140 / relic
>   120 / heal 35) × `(1 + shop_act_scale·(act−1))`; buys deduct gold, grant
>   into collections, refuse cleanly when short. Treasure: seeded roll of
>   relic / gold pile (25–60) / skill, applied via `take_treasure`. Merchant +
>   Treasure screens in `map_view` (big-card stock w/ price tags, SOLD states,
>   live gold label). Suite: 306 green (test_shop + generator placement).
>   Gold now has its sink — the Act 2–3 player-power injection the harness
>   flagged. StS "remove a card" deliberately NOT built (loadout deactivation
>   is free; revisit with the injected-curse layer).
> - **Scaling + growth pass (owner, 2026-06-10; 306 GUT green):**
>   (1) **Neutral-flat rule retired** (superseded ADR-0016 clause): every player
>   card now scales with its ACTOR (CardPlay passes scale=true) — fixes the
>   post-0026 regression where basics stopped scaling and **Defend granted 0
>   block**. (2) **Dynamic card totals**: the hand shows REAL damage/block via
>   modified_damage/_block (stat × stat_mult + Strength/Weak); reward/shop
>   previews keep base numbers (no actor context). (3) **Auto-growth**: new
>   `auto_stats_per_level` (1) — every stat +1 per level-up before the 3 chosen
>   points, recorded into allocated_stats so HP/heals/combat all see it.
>   **Reads:** A1 ≈ free for all cohorts (final-HP still orders def 34 > greedy
>   21 ≈ turtle 21 > dex-turtle 15 — turtle stays non-dominant even with DEX
>   Defend back); A2–A3 kit-only cohorts now clear everything and die ONLY at
>   the boss. Remaining pinch = boss fights; real decks (drafts + shop +
>   upgrades) are the intended closer — re-read after a real playtest before
>   touching boss bands (proposal option B) / auto growth 2 / hp_per_con 3.
> - **THE FULL DESIGN ARC LANDED (2026-06-10 session 2; 316 GUT green, full
>   flow repro'd headless):**
>   - **ADR-0024 + ADR-0021 pt2 LIVE:** member ids are stable handles
>     (`hero_1/2`, `PartyMember.character_for` synthesizes race base + class
>     overlay; legacy class-keyed ids still work). Creation = ONE race ("Choose
>     Your Origin"); **Act 1 is solo**; the **RNG 1-of-3 recruit offer** fires
>     on entering Act 2; **both classless members pick Fighter/Rogue/Mage after
>     the Act-3 boss** (pick = overlay stats + locked attack_stat + class kit
>     skills). Pre-class attacks use the HIGHEST stat (`attack_stat:
>     &"highest"`). **Draft pools are gated**: origin tier = neutral-only;
>     class pools unlock at the pick. Race origin kits (`RaceData.starting_kit`).
>   - **ADR-0022 LIVE:** `data/progression/*.json` (2+4+8 nodes per line, the
>     full class-progression.md table) + 24 ULT cards; 1-of-2 picks chain at the
>     Act 6/9/12 boundaries; **Act-15 Ascension** = "Ascended X", flat
>     `ascension_mult` step on every card (compounds via the 0020 ladder in
>     apply_effects) + the capstone Ult as a rare skill. Old promotion_level
>     plumbing remains only as dormant legacy.
>   - **ADR-0020 content + AoE rule (owner: "mage autopick"):** 12 B/C cards
>     authored (×1.5 hybrids / ×2.5 exhaust multipliers, offense+defense per
>     class); **AoE damage scales at 0.6× stat** and big AoE costs 2
>     (frost_nova, firestorm, fan_of_knives + plus variants); mage gains
>     single-target identity (Focused Ray / Arcane Overload). Draft + shop
>     rarities now **depth-weighted** (`CardReward.weights_for_act`: all-common
>     tier 1 → rare-heavy tier 6).
>   - **Party INSPECT menu:** per-member Inspect button (map strip) → stats
>     (race+class+growth breakdown), skill collection vs loadout with
>     copies-per-deck, and **relics with their actual trigger/effect/amount**;
>     loadout TOGGLING at rest nodes ("Manage skills", ADR-0026).
>   - Old saves invalid again (member model). Loadout editing elsewhere, boss
>     variety, music wiring, harness draft-emulation still open.
> - **All starting cards upgradeable (owner, 2026-06-10):** 13 new `_plus`
>   variants (all class kits + race customs; +3 dmg/block/heal, +1
>   draw/energy/stacks). Draft pool now EXCLUDES upgrade variants (rest-only).
>   Strike/Defend deliberately have no variants (slotless auto-fill).
> - **Sandbox note:** a Godot 4.6 arm64 binary now runs the full GUT gate +
>   headless flow repros in the dev sandbox; this session's suite is green there.

> **2026-06-09 session — the dungeon is real (committed f143639, 285 GUT green).**
> - **18-act act-advance flow LIVE (ADR-0019):** boss win → next act (new map from
>   the act's authored `MapGenConfig`, late_row_bias implemented; HP/deck/relics/levels
>   carry; position/cleared reset; `RunState.act` persisted); no act 19 → true victory.
>   Playtest confirmed Acts 1→5 in one run.
> - **Enemy band scaling LIVE:** `begin_combat(id, band)` scales enemies to the act's
>   trash/elite/boss level via EnemyScaler; **calibrated baseline 8 / exponent 1.0**
>   (act-1-3-balance-proposal §1 adopted): Act-1 trash ×0.25 → Act-3 trash ×1.0.
>   Empty band (sim/tests) = unscaled. Mid-fight summons spawn unscaled (v1 note).
> - **stat_mult ladder LIVE (ADR-0020):** `Effect.stat_mult` (default 1.0 == old
>   behavior exactly); damage/block = base + floor(stat × mult). Class B/C cards are
>   now pure data; none authored yet.
> - **Balance pass 1 (data):** enemy HP ×1.4 (boss ×1.6), ramps flattened (+1/+2 per
>   4t), recovery 7/8/16. Sim: greedy 70% · defensive 42.5% (policy artifact) ·
>   turtle 70% · dex-turtle 100% (block-economy hold). Boss fights now bite (playtest:
>   A3 boss downed the mage; A4 boss dealt 68). Trash still 1-turns at all depths —
>   root cause is unbounded engine stacking (mana_surge ×6 + AoE), which ADR-0026's
>   rarity copy caps (3/2/1) eliminate; deliberately NOT tuned around.
> - **Telemetry:** interactive runs fully logged (turns, pre-heal damage_taken, every
>   card_played, act_advanced); editor runs write to `telemetry_dump/` in the repo.
> - **ADR-0026 accepted** (derived decks from skill loadouts; supersedes 0004/0016
>   deck model, reverses 0005 innate Strike/Defend) — owner re-confirmed from playtest
>   ("starting decks too strong; current cards should be pickups"). Implementation
>   chain is tasked + dependency-linked in Asana.
> - **NEXT:** ADR-0025 per-character energy pools → ADR-0026 deck arc → ADR-0024
>   recruitment + ADR-0021 creation/class-pick rework → ADR-0022 trees. Build order
>   of record: 0020 ✓ → 0021-pt1 → 0025 → 0026 → 0024 → 0021-pt2 → 0022 → 0023 →
>   0019 content remainder.

> **Asset pass (2026-06-09, parallel session) — first real art/audio, license-safe.**
> New `assets/` tree (87 files, ~13 MB; all CC0 except game-icons.net CC-BY — see
> `CREDITS.md`): DCSS sprites for all 19 enemies + 3 classes, resolved **by game id**
> (`assets/sprites/enemies/<id>.png` ↔ `data/enemies/<id>.json` — drop a file, no
> schema/loader change); game-icons for all 24 cards / 7 statuses / 6 relics / 8 map
> glyphs; Kenney card frame + 8 SFX; 5 CC0 music tracks (title/map/combat/boss/rest —
> staged, **not yet wired**). Code: `src/ui/ui_assets.gd` (guarded by-id resolver —
> missing/unimported file ⇒ null ⇒ views stay text-only, suite never depends on
> imports), `src/ui/sfx_player.gd` (round-robin pool, silent fallback). `battle_view`:
> unit sprites on panels, card icons + Kenney 9-slice frame (tinted by playability;
> armed keeps the flat border), innate icons, SFX on draw/reshuffle/play/hit/block/
> victory/defeat. `map_view`: node glyphs incl. the `?` fog glyph. Tests:
> `tests/ui/test_ui_assets.gd` (fallback contract only; positive loads need the
> importer). **Pending: human GUT run + one editor boot to import assets.** Sourcing
> rationale + RPG Maker exclusion: `docs/progress/2026-06-09-asset-sourcing.md`.
> **Known bug, NOT fixed here (owner to green-light):** the combat deck's initial
> shuffle is never invoked (`Deck.start_battle()` has zero callers — draws come
> back-to-front off assembly order) and `begin_combat` reuses `run.seed` every fight,
> so per-fight draw order repeats. Fix = `deck.start_battle()` in
> `EncounterAssembler.build` + a per-fight derived seed; both touch seed-sensitive
> test expectations, so land them with the suite runnable.

> **Playtest-driven implementation pass (2026-06-08, in progress).** After the
> 2026-06-08 playtest (`docs/progress/2026-06-08-playtest-review.md`) we began
> implementing the agreed view-layer fixes, doc-first. **NOTE: this dev sandbox has
> no Godot binary — code + GUT tests are written but the headless gate
> (`godot --headless -s addons/gut/gut_cmdln.gd …`) must be run by a human before
> commit.** Status:
> - **(1) Map orientation flip bottom-up [ADR-0023] — DONE.** `map_view._refresh_map`
>   now renders rows descending (`rows.reverse()`): boss at the top, start row at the
>   bottom, player climbs up. View-only; the only map_view test is a boot smoke test
>   (no render-order assertion), so it's unaffected.
> - **(2) Enemy intent + target telegraph [review §9] — DONE.** `battle_view` already
>   showed the intent icon+amount; now it also appends the **targeted ally** (`→ Name`,
>   or `→ all` for AoE) using the existing `Telegraph.target`, and each ally panel shows
>   **`◀ Incoming N`** (summed telegraphed damage aimed at them) so blocking is a legible
>   choice. Additive display only; the underlying targeting is covered by `enemy_ai` tests.
> - **(3) Combat layout frame — ALREADY PRESENT.** `battle_view` is already allies-left /
>   enemies-right / hand-bottom; matching the StS *look* (screenshot 6) is an **art pass**,
>   not layout logic — deferred to art.
> - **(4) Map selective fog [ADR-0023 refinement] — DONE.** `MapNode.hidden` (serialized);
>   `MapGenerator._apply_fog` marks every `event` + a deterministic ~⅓ of mid-run `combat`
>   nodes hidden (elites/rests/boss/start stay visible); `map_view` renders hidden-uncleared
>   nodes as `?` and shows a legend. New GUT test `test_fog_hides_events_and_spares_visible_types`;
>   the determinism test still holds (`hidden` is in `to_dict`). Node-type weights were left
>   untouched so `test_node_type_distribution_is_sane` (combat must stay plurality) is unaffected.
> - **(5) shop/treasure/currency [ADR-0023]** — not started (own pieces; needs a currency + shop screen).
> - **(6) character-creation rework — DEFERRED, now coupled to ADR-0024.** The run layer keys
>   identity off the **class** (`run.party = [&"fighter", …]`, `start_run` does `get_character(cid)`);
>   ADR-0021's race-only model inverts that, and the class is now picked at Act 3 **and** the 2nd
>   member arrives via **ADR-0024 recruitment at Act 2** (solo Act 1). A race-only creation screen
>   today would leave members classless with no pick flow — it needs the act-advance + Act-2/3 flow
>   first. **Provisional race base-stat lines pinned for when we build it** (tune later, per owner):
>   **Human 3/3/3/3 · Elf 2/5/2/5 · Orc 5/3/4/2 · `hp_per_con` 2** (ADR-0021 illustrative). Build it
>   alongside the act-flow + ADR-0024/0025, not as an isolated piece.
> - **(7) balance pass** — not started (gated as before on the Act 1–3 work).
> Each piece tracked in Asana.

> **Class progression design locked (2026-06-08, ADR-0022) — design only, code pending.**
> The promotion *structure* of ADR-0021 is now fleshed out and the pacing fixed. Class is
> picked at Act 3 (Fighter/Mage/Rogue), then a **pick-1-of-2 at Acts 6 / 9 / 12** (archetype →
> specialize → capstone; binary tree 1→2→4→8 = **8 capstones per line, 24 total**), and **Act 15
> is universal "Ascension"** — *not* a branch: your capstone becomes "Ascended X" with a **flat
> `stat_mult` boost to every owned card + a signature "Ult" card** (one per capstone, 24 Ults).
> This shifts the first real *choice* up from Act 9 (was too slow) to Act 6. Full spec +
> 24 capstone/Ult table + data model: `docs/systems/class-progression.md`; visual:
> `docs/systems/class-progression-matrix.html`. Engine work (tree-walk promotion, Ascension
> step, progression data schema/loader, Ult cards, GUT tests) is **not started** — tracked in
> the Asana "Unnamed Game" project.

> **This session (2026-06-08) — 18-act dungeon, design only.** Mapped the full
> dungeon progression: the run goes from single-act to an **18-act descent**, 6
> tiers of 3 acts, with a noticeable difficulty ramp every 3 acts and a boss-level
> power curve **anchored at Act 12 = 250** (runs 5 → 1300 across A1–A18). Shipped
> *design + data only* (no gameplay code, by request — stopped at the wireframe):
> **ADR-0019** (supersedes the single-act scope of ADR-0012), the
> `docs/systems/act-progression.md` wireframe (per-act rows/elites/node-weighting,
> enemy level bands, data contract, act-advance flow), the authored curve at
> `data/acts/act_progression.json`, and typed resource shells
> (`src/run/act_config.gd`, `act_progression.gd`). Engine work (loader, map-gen,
> level→stat scaler, act-advance flow, tests) is **not started** — it's broken into
> tasks in the Asana "Unnamed Game" project and summarised in gap #0 below.

> **Progression-design arc (2026-06-08, ADR-0019 → 0021) — read these before building.**
> The run's identity/power model was redesigned. **ADR-0020** (card scaling): cards
> go flat → hybrid → multiplier via a single `stat_mult` field, symmetric on offense
> (attack_stat) and defense (DEX); the deck is the player's geometric answer to the
> curve. **ADR-0021** (deferred class): character creation picks **race only — one
> race for the whole pair, no mix-and-match** — you start as a low-stat "normal
> person"; **class is chosen at the end of Act 3** (unlocks the class card pool +
> attack_stat), with **promotions at the end of Acts 6/9/12/15**, each beat feeding
> the tier wall just after it. Act 1 is a **linearly-reduced entry within the 18
> acts** (recalibrate the `EnemyScaler` baseline so Act 1 ≈ ×0.25 of today's
> enemies, back to ×1.0 by ~Act 3 — no literal "Act 0"; A12=250 holds). This
> **supersedes the class-as-base-template model of ADR-0015** (race is now the base
> template; class is a mid-run overlay). **Implemented this session:** the act
> **loader + §5 validation** (`ContentDatabase` → typed `ActConfig`/`MapGenConfig`,
> `get_act_progression`/`get_act`) and the **`EnemyScaler`** (`src/run/enemy_scaler.gd`),
> both with GUT tests, both pending a human GUT run. Still TODO: per-act map-gen,
> the `stat_mult` effect, act-advance flow, and the creation/class-pick rework.

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
# Currently: 251 passing.

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
- **Enemy roster (tiered kit redesign, 2026-06-08):** every archetype follows an
  **Attack · Debuff · Defend** kit; higher tiers are *scaled variants* of a base
  (Skirmisher→Hardened Skirmisher→Blademaster; Brute→Ogre; Gremlin→Hobgoblin;
  Ooze→Elder Ooze) rather than new concepts. 19 enemies across Weak/Medium/Strong/
  Very-Strong. Debuff slot uses **Weak / Vulnerable (+50% dmg taken) / Frail (−50%
  block gained)** — Vulnerable+Frail are new statuses in `BattleState`. Encounters
  rebuilt to Basic (3–4 Weak / 2 Medium / 1 Strong), Hard (2 Strong / 1 Strong+2
  Medium), Boss (Very-Strong + 2–3 Weak minions). Design source:
  `enemy_design_review.xlsx` in the project folder.
- **Class promotion** (P3·06, ADR-0015): at an act boundary an eligible character
  picks 1 of 2 branches, folding a stat bump + signature card into the run.
  `RunController.eligible_promotions/apply_promotion`; offered in `MapView` at the
  boss. **The branch *content* is now defined by ADR-0022** (Acts 6/9/12 trees →
  24 capstones; the old placeholder Berserker/Guardian, Assassin/Duelist,
  Pyromancer/Sage branches are superseded) — the plumbing carries forward, generalized
  to walk a per-line tree by act + an Ascension step at Act 15. Dormant until multi-act
  content reaches the thresholds (data knob).
- **Save / resume** (P2·02): `MapView` checkpoints the run between nodes and clears
  it on run end; `CharacterCreation` offers **Continue Run** from the saved slot.
- **Cross-run meta** (P3·08, ADR-0018): `MetaState` (own persistent slot) tracks
  acts cleared; every `meta_cash_out_acts` (default 9) you bank one player-chosen
  boon (relic / +1 card / +stat / unlock) that applies at every future run start
  (`MetaProgress.apply_boons`). Dormant until multi-act content exists.
- **Telemetry** (`src/telemetry/`): combat/run events; used to produce the attrition read.

## 4. Known gaps / deferred (NOT yet done)

0. **18-act dungeon progression — SPECCED 2026-06-08, code pending.** The run is no
   longer single-act: **ADR-0019** adopts an **18-act descent** (supersedes the
   single-act scope of ADR-0012). Structure + power curve are fully specified in
   `docs/systems/act-progression.md` (6 tiers of 3 acts; noticeable ramp every 3
   acts; **boss level curve anchored at Act 12 = 250**, running 5 → 1300 across A1–A18;
   per-act rows/elites/node-weighting escalation; enemy level bands). The curve is
   authored data at `data/acts/act_progression.json` and the typed shells exist
   (`src/run/act_config.gd`, `act_progression.gd`). **Loader + §5 validation DONE
   2026-06-08** — `ContentDatabase` now parses the curve into typed
   `ActConfig`/`MapGenConfig` (incl. `late_row_bias`), exposes `get_act_progression()`
   / `get_act(n)`, and validates every §5 invariant on load via
   `ActProgression.validation_errors` (count/contiguity, tier formula, anchor A12==250,
   strictly-increasing boss levels, tier-gate steeper than within-tier, rest_before_boss).
   Tests in `tests/run/test_act_progression.gd` (happy path on real data + one fixture per
   broken invariant). *Needs the human GUT run to confirm green.* **Still TODO (engine-side,
   tracked in Asana "Unnamed Game"):** map-gen per-act config + late-row
   bias, an enemy level→stat scaler, the RunController act-advance flow (boss win → next
   act; A18 → true victory), and GUT tests for advance/scaler. Enemy *rosters* per act
   and the exact level→stat function are deferred to a balancing/content pass.
   This also un-blocks the "dormant until multi-act content exists" items below
   (promotion at L20, meta cash-out every `meta_cash_out_acts`) — revisit
   `meta_cash_out_acts` (default 9) against the new depth of 18.


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
4. ~~**Class promotion (P3·06)**~~ **DONE 2026-06-08 (d58e3f5).** Pick-1-of-2 branch
   per class at an act boundary, eligible at `BattleConfig.promotion_level * N`
   (default 20, accrues). A promotion folds stat mods into `allocated_stats` + adds
   a signature card to `run_deck` (no new wiring). **Dormant at default threshold**
   until multi-act content reaches L20. ~~**Exit-package meta (P3·08)**~~ **DONE
   2026-06-08 (9632ce4)** — `MetaState` (persistent, own save slot) + `MetaProgress`:
   bank a chosen boon (relic / +1 card / +stat / unlock) every `meta_cash_out_acts`
   (default 9) acts cleared; boons apply at each future run start. Dormant until
   ~9 acts exist.
5. ~~**Save/resume** … isn't wired.~~ **DONE 2026-06-08 (23dfe04).** `MapView`
   checkpoints the run between nodes + clears on run end; `CharacterCreation` shows
   **Continue Run** when a save exists. (Saves are between-node; a mid-combat quit
   rewinds to the node start.)

## 5. The balance finding (important)

The run loop's purpose was to test the **attrition thesis** (does greed get punished
across a run?). There's a repeatable harness for this now:

```
godot --headless --script res://tools/attrition_sim.gd [seeds]   # default 40
```

`tools/attrition_sim.gd` runs **three** cohorts over the same 6-fight act
(`enc_combat_01..04, elite_01, boss_01`) under identical seeds, full loop live
(run decks, leveling, relic after elite): **greedy** (all offense), **defensive**
(block once then attack), and **turtle** (block hard, chip slowly). The goal is a
"Goldilocks" result — balanced play beats BOTH rushing and turtling.

**Enemy damage ramp is built (engine).** `EnemyData.ramp_amount/ramp_every/
ramp_passive`, applied in `EncounterBattle._apply_enemy_ramp`:
- **Scheduled buff turn** (Medium every 4 turns/+2 Str, Strong every 3/+3): every
  Nth turn the enemy gains Strength INSTEAD of acting. Greedy ends fights before it
  fires (faces full burst); turtling eats it repeatedly.
- **Passive ramp** (boss, +1 Str/turn, free): no action cost, the boss still
  attacks — boss fights are a race.
This replaced the old roll-based `buildup` intent (which cannibalised attacks).

**Read (40 seeds, 2026-06-08, engine ramp):** greedy 95% (2 deaths @ elite) ·
defensive 100% · turtle 100% (final HP greedy 28 < defensive 37 < turtle 42).
**Greed is punished; turtling still isn't.**

**Anti-turtle levers built (all tested, all data-tunable):** Frail/Vulnerable
layered into the hard fights (Twin = Ogre+Coven Witch; Elite = Captain+Occultist+
Ooze); the **Captain summons gremlin reinforcements** (`EnemyData.summon_id/
summon_every/summon_max`, `EncounterBattle._apply_enemy_summon`). Result: greedy
**90%** (4 deaths @ elite) — clearly punished — but **turtle stays 100%.**

**ROOT FINDING — block economy dominates.** A maximal turtle blocks ~2×/turn
(every turn, fully negating damage) AND kills ~1 enemy/turn — so it kills Frail
appliers and summoned minions as fast as they arrive, and out-sustains ramp. No
amount of debuff/ramp/summon tuning cracks a *perfect* turtle because block is
free-enough and total. Cracking it is a **design decision about block**, not a
number: options — (a) a soft per-fight **turn cap / escalating unblockable chip**;
(b) **block-piercing** attacks on some enemies; (c) make block **scarcer** (higher
energy cost / cap per turn); (d) accept that a perfect turtle is a valid slow line
and let the **run structure** tax it (fewer rests, status bleed) — which the
single-fight harness doesn't model. Owner's call. (Note: the harness turtle blocks
*optimally* every turn — more than a real hand/energy usually allows.)

**DECISION (2026-06-08): chose (d) + poison.** **Poison now IGNORES block** —
poison ticks deal direct HP (`BattleState.deal_unblockable`), the one chip a turtle
can't soak (and a real block-pierce tool for player poison builds too). The boss's
hex now stacks Poison, and between-fight recovery was leaned down
(`post_combat_heal` 5→4, `revive_hp` 8→6) so run-level attrition carries.
**Final read (40 seeds):** greedy **80%** (8 deaths @ elite) · defensive **100%**
(HP 30) · turtle **100%** (HP 43). Balanced play is now the safe sweet spot and
greed is genuinely risky; the **idealised harness turtle still wins** — but that
turtle blocks perfectly every turn (unreachable in real play), and poison-ignores-
block means an *imperfect* real turtle bleeds. **Definitive:** you cannot make the
perfect-block turtle lose via enemy content while block fully negates attacks —
that needs a block-economy change (turn cap / scarcer block), a separate feel
decision. Tuning knobs trade off (leaner heals over-punished greedy to 70% without
moving turtle). The elite (Captain's Guard) may be over-punishing rushers (8/40) —
soften if aggressive play should be more viable. All data-tunable.

**DIRECTION (2026-06-08): pure-DEX Defend + scale DEX and damage in lockstep.**
Innate Defend now grants block = **DEX only** (no flat base; `defend.json` amount
0 — it already DEX-scales). Free block becomes an opportunity-cost stat investment
instead of a universal freebie: to turtle you must pour level points into DEX,
which (for STR/INT classes) buys no offense, so a non-killing turtle bleeds to
poison. Mechanic check (block vs incoming dmg/turn over the act): old Defend gave
20 block/turn — ≥ incoming on *every* fight (total negation, why the perfect
turtle was unbeatable); new Defend gives ~10, exceeded by all three hard fights
(Twin 19.5, Elite 13.3, Boss 12.2) — block flips from negation to partial
mitigation.
**Guiding balance invariant: DEX (block) and the attack stat (damage) must scale
in line with one another** — reward balancing defense against offense so neither
pure turtling nor pure aggression dominates; the sweet spot is the mix. For the
18-act enemy level→stat scaler this means **enemy-damage growth must keep pace
with DEX→block growth** (otherwise a high-DEX turtle re-negates everything at
depth) — bake it in as an explicit GUT assertion. Verify with the new
**`dex-turtle`** cohort added to `tools/attrition_sim.gd`. Owned block cards
(Bulwark/Aegis) left flat intentionally — they're *drawn* (scarce), the right
shape for reliable earned block. *Needs a Godot/GUT harness run to confirm
win-rates.*

**(earlier finding) punishing turtle is also a BLOCK-DENIAL problem.**
A dedicated turtle blocks ~2× per turn and out-sustains even ramped enemies in
fights short enough to win; raising ramp amounts barely moved it (turtle 44→42).
The hard fights (brute+ogre, captain's guard) have **no Frail applier**, so the
turtle's block is never cut. Levers to close it (owner design call): (a) put a
**Frail/Vulnerable applier in every Hard/elite fight** so block gets halved; (b) a
**soft per-fight turn pressure** (escalating chip after N turns); (c) anti-block
mechanics (attacks that ignore/break block). The single-fight harness also
under-counts run-level turtle costs (limited rests, more enemy turns = more chip).
All amounts are data (`data/enemies/*`, `data/battle_config.json`); re-run the
3-cohort harness after each tweak.

**Read after the enemy-kit redesign (40 seeds, 2026-06-08): greedy 95% (2 deaths at
the elite) vs defensive 100%; HP gap def−greedy ≈ +6.2.** First time greed is
punished at all — the new tiered roster (Attack/Debuff/Defend kit, scaled variants;
Vulnerable/Frail debuffs) + rebuilt encounters (Basic/Hard/Boss templates) put real
pressure on. But the gap is still **marginal** (5% win-rate). To make the attrition
thesis decisively testable, keep tuning: the elite (Captain's Guard) is the current
pinch point — push enemy damage / cut `post_combat_heal`+`revive_hp` / add a 2nd
hard fight, re-running the harness after each tweak. All knobs are data
(`data/battle_config.json`, `data/enemies/*`, `data/encounters/*`). **Final balance
targets are the owner-led design call.**

## 6. Suggested next priorities (pick based on goal)

| Want to… | Do this |
|----------|---------|
| ~~Make builds matter (cards from races/rewards show up)~~ | ~~Wire `run_deck` → combat deck~~ **DONE (gap #1, 4cdbac0)** |
| ~~Deepen characters (XP + stat allocation)~~ | ~~Leveling (P3·05)~~ **DONE (gap #2)** — UI to allocate is part of P2·10 |
| ~~Make it feel like a *run*, not one fight~~ | ~~Map/run UI (P2·10)~~ **DONE** — creation → full run in `MapView` |
| Make combat threatening (attrition real) | **Balance pass** — tune enemies/encounters/healing/relics in data |
| Build the actual dungeon depth | **Implement the 18-act progression** (gap #0) — loader, per-act map-gen, enemy level→stat scaler, RunController act-advance, tests. Design is done (ADR-0019 + `act-progression.md` + `data/acts/`). |
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
               enemies, encounters, races, events, relics, promotions, boons, statuses, battle_config, encounter_pool)
src/combat/    BattleState (turns/energy/status/targeting), EffectResolver, Combatant,
               EnemyAI, EncounterAssembler/Battle, RelicEngine
src/cards/     Deck, CardPlay
src/run/       RunController, RunState, RunNavigator, Leveling, PartyStats, MetaState/MetaProgress, EventResolver, RestResolver, MapGraph/MapGenerator, CardReward, ActConfig/ActProgression (18-act shells, ADR-0019)
data/acts/     act_progression.json — the 18-act curve + per-act structure (ADR-0019)
src/ui/        character_creation → map_view (run) → battle_view (code-driven, asset-free)
src/telemetry/ TelemetryLogger
data/          all authored content (see data/README.md)
docs/          concept-brief, decisions/ (ADRs), systems/ (schemas; incl. class-progression.md + .html matrix), progress/, this file
tests/         GUT suites mirroring src/  (251 passing)
```
