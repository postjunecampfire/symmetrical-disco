# Implementation readiness — ADR-0019…0026 + block economy

*2026-06-09. Per-item: what exists in code, what must be resolved before coding to a
testable (GUT/harness) state. Grounded against the actual source, HANDOFF, the conflict
review, and `act-1-3-balance-proposal.md`.*

**Legend:** 🔴 blocking decision · 🟡 provisional value needed (pick one, tune later) · 🔧 pure engineering, no decision needed.

---

## 1. ADR-0020 — `stat_mult` on Effect

**Code today:** `Effect` (`src/data/effect.gd`) has `type/amount/status/stacks/params` — no `stat_mult`. Scaling is hardcoded in `battle_state.gd` `modified_damage()` (base + attack_stat + Strength, ×Weak) and `modified_block()` (base + DEX, Frail-halved).

**Resolve to start:**
- 🔴 **Strength interaction.** ADR formula is `base + floor(stat × stat_mult)` — does the mult apply to stat only (Strength added after, unmultiplied) or to (stat + Strength)? Recommend stat-only: keeps Strength relics from compounding with Class-C cards. One line, but it's the formula the tests assert.
- 🔴 **Neutral cards.** ADR-0016 says neutrals ignore scaling. Decide: validator **rejects** `stat_mult ≠ 1.0` on `character_tag: neutral` cards (recommended — fail loud at load) vs. silently inert.
- 🟡 Defense parity (exact mirror vs. slightly held back) and Class-C ceiling (×3 vs ×4) — **not blocking**; these are authored data values on cards that don't exist yet. Ship the field with defaults.
- 🔧 Add field (typed float, default 1.0, validate ≥ 0 in `ContentDatabase._parse_card`), apply in the two `modified_*` paths, GUT: default-1.0 leaves all 251 existing tests' expectations unchanged; a ×2 fixture card; neutral rejection fixture.

**Testable as:** pure unit tests, no UI, no content. Smallest item; do first — 0022 (Ascension) and 0020's card pools both read it.

---

## 2. ADR-0021 part 1 — races = base templates, classes = overlays

**Code today:** inverted from the target. `CharacterData` (= class) holds base stats and `run.party = [&"fighter", …]` — **party identity is keyed off the class id** (`start_run` → `get_character(cid)`). `RaceData` is a small modifier + 1 custom card.

**Resolve to start:**
- 🔴 **The party-member entity.** Member id can no longer be the class id (classless Acts 1–3, two members may share a race). Define the new `RunState` shape: member = generated id + `race_id` + `class_id: nullable` + level/XP/allocated/promotions keyed by member id. This is the refactor everything else hangs off — settle the schema before touching code.
- 🔴 **Pre-class `attack_stat` rule** (highest stat vs. race default) — open in the ADR; can't code pre-class Strike scaling without it. Recommend highest-stat (self-balancing, no new data field).
- 🔴 **Save policy.** This breaks every saved run. Decide once for the whole batch: prototype = detect schema version, discard old saves (recommended) vs. migrate.
- 🟡 Race stat lines + allocation budget: HANDOFF already pins Human 3/3/3/3 · Elf 2/5/2/5 · Orc 5/3/4/2 · `hp_per_con 2`. Adopt as v1 data.
- 🟡 Class-overlay JSON schema: `{stat_bonus, attack_stat, unlocked_card_tag}` — write it now even though the pick lands in part 2, so loaders/tests are stable.
- ⚠️ **Sequencing:** `CharacterData.starting_deck`/`innate_actions` are reshaped again by 0026 (skill kits). Decide whether part 1 lands the member-entity refactor only and lets 0026 own the kit fields (recommended), or you touch them twice.

**Testable as:** loader + `PartyStats` + `Leveling` GUT tests against the new member entity; no creation-screen work needed yet (that's part 2).

---

## 3. ADR-0025 — per-character energy pools

**Code today:** `BattleState.energy` is one shared int; refill `= config.energy_per_turn` (3) at player-phase start; `RelicEngine` `turn_start` can add energy.

**Resolve to start:**
- 🟡 **Per-character base.** ADR deliberately left it open (likely 2). Pick 2 as the provisional `energy_per_character` in `battle_config.json`; harness re-tunes.
- 🔴 **Cost attribution before 0026 lands.** With the shared deck still live, *whose* pool pays for a neutral card? Cleanest: **implement 0025 in the same change as 0026** so every card has an owner and the question never exists. If 0025 must go first, define the interim rule (card `character_tag` owner pays; neutral → active/selecting character) and accept throwaway code.
- 🔴 **`gain_energy` effects and energy relics: which pool?** Recommend: card effects credit the card's owner; relics credit their... (relics are party-level today) — simplest v1: relic energy credits each pool? No — that doubles relic value. Decide: relic picks a holder at acquisition, or energy relics credit one designated pool. Must be answered to keep "+1 energy ≈ 33%" math meaningful per pool.
- 🔧 Schema: per-member pool on `BattleState` (Dict member_id → int), refill loop, spend checks in `CardPlay`. Solo-Act-1 single pool falls out automatically once 0024 exists.

**Testable as:** GUT — refill per pool, spend isolation (A's play never debits B), recast-brake per pool (return-card spam capped by own pool).

---

## 4. ADR-0026 — derived decks from skill loadouts

**Code today:** one shared `Deck`; `run_deck` is a flat card-id list; Strike/Defend are `innate: true` and **excluded** from deck assembly (ADR-0005, now reversed); `CardReward` drafts cards; rest = upgrade-a-card via `upgrade_of`.

**Resolve to start:**
- 🔴 **What is a "skill" in data?** Recommend: a skill *is* a `CardData` id (rarity already exists on CardData) — no new entity; `derive_deck()` maps loadout ids → copies by rarity. But then **every existing card needs a correct rarity** (29 cards; rarity must match its 0020 class A/B/C). Audit/author that mapping before coding.
- 🔴 **Hand/draw per character.** ADR assumes hand 5; with two characters that's 10 cards on screen and the 20-card cycle math depends on it. Confirm 5/5, or pick smaller per-char draw. Blocking — `derive_deck` floor rationale (20) is derived from it.
- 🔴 **Block economy first** (item 10): Defend's energy cost, auto-fill ratio, and the defense-multiplier ladder set how much block a derived deck yields. Decide before freezing 0026's data values, or you'll re-author the fill rules.
- 🔴 **Upgrade representation.** "Upgrade a skill upgrades all copies" — store upgrade as an annotation on the collection entry (skill id + tier) and have `derive_deck()` project the upgraded card (`upgrade_of` chain inverted). Settle this; it's also the pattern Ascension (0022) reuses.
- 🟡 Provisional values (all in ADR): 10 slots fixed, copies 3/2/1, floor 20, fill 1:1 Strike:Defend.
- 🔧 `derive_deck()` deterministic (sorted projection, shuffle happens in `Deck` with seed) — spec the ordering so tests are exact. ADR-0005 reversal = delete the innate action-bar path, un-flag `innate`. CardReward → skill draft (same screen, draft adds to *collection*). Defer the injected-card layer (curses/consumables) entirely — open question in ADR, no content depends on it yet.

**Testable as:** GUT on `derive_deck()` (rarity→copies, floor fill, all-rare loadout, upgrade projection), deck-cycle integration, bricked-turn frequency probe in the harness (the ADR's named risk).

---

## 5. ADR-0024 — solo Act 1 + Act-2 recruitment

**Code today:** nothing. Creation screen hard-requires 2 classes; encounters/balance assume a party of 2; `advance_act()` exists.

**Resolve to start:**
- 🔴 **Candidate schema + kit content.** Candidate = race + starting kit (skills, per 0026) + derived deck. Needs at least one authored kit per race — small content task, but zero kits exist. Define `data/recruits/` (or generate candidates from race + kit table).
- 🔴 **Creation-screen interim.** 0024 needs a *solo* start, but race-only creation is scheduled in 0021 part 2 (after this, per your order). Either pull "creation = 1 character" forward into this item (race-only can wait, single-character can't), or swap items 5↔6. Recommend: minimal change here — creation picks 1 member; full race-only rework stays in part 2.
- 🔴 **Solo TPK rule.** ADR-0011 downed-not-dead: solo character downed in Act 1 = TPK ends run? Confirm (almost certainly yes; one line, but the run-loop test asserts it).
- 🟡 Offer trigger (start of Act 2, before class pick), candidate count 3, starting pool size — defaults are in the ADR; pool-eligibility state needs a field in `MetaState` (new boon type "unlock recruit" already half-exists as `unlock`).
- 🔧 Offer roll seeded from run seed (deterministic GUT test); offer UI hooks into `MapView` at act-advance.

**Testable as:** GUT — offer generated exactly once at Act-2 boundary, 3 distinct candidates from eligible pool, recruit arrives with own pool/deck (depends on 0025/0026), solo-Act-1 invariants.

---

## 6. ADR-0021 part 2 — race-only creation + Act-3 class pick + draft-pool gating

**Resolve to start:**
- 🔴 **Pool-gating data model.** Pre-class draft pool = neutral + race; post-pick adds class tag; 0020 says big multipliers are also *crossover-gated by tier*. Cards need pool metadata (tag exists; tier/act eligibility doesn't). Define how a draft pool is assembled per (act, member): function of `character_tag` ∈ {neutral, race, chosen class} × rarity weights per tier (0020's A→B→C weighting). This is the real design gap here.
- 🔴 **Class-pick stat bumps** per class (Fighter/Mage/Rogue) — numbers don't exist. Provisional values needed (the balance proposal holds final tuning until Act 1–3 reads right).
- 🟡 Free choice vs. stat-gated pick: ADR open question — take free-choice for v1 (recommended in ADR spirit).
- 🔧 Pick flow surfaces after Act-3 boss, before Act-4 descent — reuse the promotion-offer slot in `MapView`; both members pick on one screen (0024 makes it two picks, one beat). Creation screen: race-only, single member (single-member part possibly already pulled into item 5). `attack_stat` locks at pick; pre-class rule from part 1 switches off.

**Testable as:** GUT — pool assembly per act/member state (classless member never offered class-tagged or B/C cards; post-pick pool includes them), pick applies bump + lock, navigator offers pick exactly at Act-3 boundary.

---

## 7. ADR-0022 — progression trees (6/9/12) + Act-15 Ascension + 24 Ults

**Code today:** flat `eligible_promotions/apply_promotion` keyed on `promotion_level` (level 20 accrual), 6 old placeholder branches in `data/promotions/` (superseded).

**Resolve to start:**
- 🔴 **Eligibility switch: act boundary, not level.** ADR leans act/tier boundary; `promotion_level` becomes dead config. Decide and delete — half-keeping both is how the old and new systems fight.
- 🔴 **Content is the long pole:** 3 roots + 6 archetypes + 12 specializations + 24 capstones with per-node `stat_bonus` + `unlocked_card_ids` (skills, per 0026) + 24 Ult cards. The *names/structure* exist in `class-progression.md`; the **numbers and card designs don't**. The balance proposal explicitly holds `stat_bonus`/`ascension_stat_mult` until Act 1–3 calibration reads right — so: build the **schema, loader, tree-walk, and Ascension code path now with placeholder data**, author real numbers after item 9's harness pass.
- 🟡 `ascension_stat_mult` magnitude, Ult scaling, branch-locked-for-run (assume yes), Act-6 always-a-choice (yes) — provisional/confirm.
- 🔧 Tree schema (node = parent + grants; capstone += `ult_card_id`, `ascension_stat_mult`); generalize plumbing to tree-walk by act; Ascension = distinct path (annotate skills with the mult — reuses 0026's upgrade-annotation pattern, so **build after 0026**) + append Ult to collection as a rare (1-copy) skill.

**Testable as:** GUT — tree integrity validation on load (binary at each beat, 8 capstones/line), walk respects parent, Ascension applies mult to every derived card + injects Ult once.

---

## 8. ADR-0023 remainder — shop/currency + treasure

**Code today:** zero — no currency field anywhere, no shop/treasure node kinds (`map_node.gd` knows combat/elite/rest/event/boss + `hidden`), fog refinement is done.

**Resolve to start:**
- 🔴 **What does a shop sell in a skill world?** 0026 changed the answer: "buy cards" → **buy skills (into collection)**; StS-style "remove a card" is mostly obsoleted by loadouts (deactivation is free at rests). Decide shop inventory v1: skills + relics + (heal?). Removal service only matters once the injected-card layer (curses) exists — defer with it.
- 🔴 **Currency earn/spend numbers**: earn per combat/elite/event, price curve by rarity/act. No numbers exist anywhere. Author a provisional table (it's pure data) — blocking only in the sense that the shop is untestable without *some* prices.
- 🟡 Placement: guaranteed shop per act? treasure frequency? → per-act `MapGenConfig.type_weights` + a `guarantees` entry (the `rest_before_boss` pattern already exists to copy).
- 🔧 `currency` on `RunState` (+ save), earn hook in `finish_combat`/event resolver, `shop`/`treasure` node kinds + handlers + a minimal buy-list screen, treasure reward table. Also: apply the conflict-review **C4 fix** (0023's Consequences still describe the superseded `revealed` model) before coding from that ADR.

**Testable as:** GUT — earn on win, transaction (sufficient/insufficient funds), generator placement guarantees, treasure grant; shop screen stays thin.

---

## 9. ADR-0019 remainder — rosters/pools, XP & meta re-tune, act-parameterized harness

**Code today:** curve data + loader + validation ✅, `EnemyScaler` ✅. *(Correction 2026-06-09: `battle_config.json` **does** now carry `enemy_scale_baseline_level: 8` / `enemy_scale_exponent: 1.0`, and `begin_combat` wires the scaler per band — the calibration gap flagged in `act-1-3-balance-proposal.md` §0 has since been closed. Confirming the values stands as an owner sign-off, not missing code.)* Harness `tools/attrition_sim.gd` still runs one act, unscaled.

**Resolve to start:**
- 🔴 **Confirm baseline 8 / exponent 1.0** (the standing proposal — hits both ADR-0021 anchors: A1 ×0.25 → A3 ×1.0). Two JSON keys; everything else here measures against it.
- 🔴 **Act-3 boss policy**: option A (keep curve, classless "graduation exam") vs B (soften tier-1 boss levels — touches ADR-0019 invariants). Proposal recommends A first; confirm so the harness targets are defined.
- 🔴 **Per-act rosters**: which enemies appear per act/tier — pure content authoring against the level bands, but nothing exists beyond the single-act pool. Minimum viable: tier-level pool tables in `data/acts/` (`encounter_pool` per act), reusing the 19-enemy roster scaled.
- 🟡 **XP + `meta_cash_out_acts` re-tune**: `meta_cash_out_acts: 9` predates depth-18; XP curve (`xp_per_combat`, base/step) was tuned for one act. Note: if 0022 moves promotion eligibility to act boundaries, leveling's *only* job becomes stat points — re-derive points-per-act target first, then set XP numbers. Provisional: cash-out 6 (one boon per 2 tiers)?  — owner call, but pick one to make the harness runnable.
- 🔧 **Harness extension** (the proposal's §7, verbatim): wire `EnemyScaler.apply_to(…, band_level(act, role))` into the cohort runner; parameterize by act; run A1/A2/A3 × cohorts (greedy/defensive/turtle/dex-turtle) with a classless race-base party; add the **lockstep GUT assertion** (enemy-damage : DEX-block ratio ~constant across levels — the anti-turtle guard).
- ⚠️ Note the harness party must be the *new* member entity (item 2) for the "classless race-base party" cohort to exist — sequence after part 1.

**Testable as:** this item *is* the test infrastructure — its deliverable is the act-parameterized harness + curve assertions everything else tunes against.

---

## 10. Block economy (held decision — decide before 0026 data freezes)

**Standing finding (HANDOFF §5):** a perfect turtle is unbeatable via enemy content while block fully negates; (d)+poison was chosen, but the structural question — cap/scarcity — was explicitly deferred as a feel decision. 0025/0026/0020 now reshape every input: per-char energy ≈ 2 (Defend = half a turn's economy by itself), Defend arrives as auto-fill copies (availability is now deck-frequency, not an always-on innate), and 0020 wants a *defense multiplier ladder*.

**The actual decision to make (then write the ADR superseding the relevant slice of 0017/HANDOFF-direction):**
1. **Is block-per-turn capped or chip-pierced?** (a) soft turn-cap / escalating unblockable chip, (b) enemy block-piercing, (c) scarcer block via cost, or (d-continued) rely on structure + poison — now with the knowledge that 0026 already makes block scarcer (drawn, not innate).
2. **Defend's energy cost under a 2-energy pool** — at cost 1, blocking = 50% of a character's turn. That may *already be* option (c) by accident; decide deliberately.
3. **Does the 0020 defense ladder ship at parity or held back?** (0020's open "defense parity" question is really a block-economy question — fold it in here.)

**Why before 0026 ships:** auto-fill ratio (Strike:Defend 1:1?), Defend's cost, rarity of block skills, and the defense-multiplier gating are all 0026/0020 data values that encode this decision. Decide once, author once.

**Inputs ready:** dex-turtle cohort in `attrition_sim.gd`, the block-vs-incoming mechanic check in HANDOFF §5, and (after item 9) per-act harness reads.

---

## Cross-cutting resolutions (decide once, apply to all)

1. **Save compatibility:** nearly every item rewrites `RunState`. Recommend: version the save, discard on mismatch, for the whole batch.
2. **Schema epoch:** items 2+3+4 (member entity, per-char energy, derived decks) are one coupled refactor of party/deck/energy state. Land them as one epoch (in that order, behind the block-economy decision) rather than three interim shims — 0025's cost-attribution ambiguity literally disappears if 0026 is in the same change.
3. **Doc hygiene before coding from the ADRs:** conflict-review C4 (0023's stale `revealed` text) is the only one that can mislead an implementer; C3/C5 are batchable. C1/C2 are resolved (0025/0026 accepted, statuses applied).
4. **Order check:** your sequence is right with one swap consideration — item 5 (0024) needs single-character creation, nominally part of item 6. Pull "creation = 1 member" forward into item 5; leave race-only + class-pick in 6.
5. **Everything stays headless-testable:** every item above lands as data + GUT + harness first; the only UI that *must* exist is thin (recruit offer, class pick, loadout screen, shop list). The Godot binary gate (human GUT run) still applies per HANDOFF.

## Blocking-decision shortlist (the actual to-decide queue)

| # | Decision | Item |
|---|----------|------|
| 1 | Block economy: cap / cost / pierce / structural — and Defend's cost at 2 energy | 10 |
| 2 | `stat_mult`: Strength excluded from the mult? neutral cards rejected at load? | 1 |
| 3 | Party-member entity schema (id ≠ class id) + save-discard policy | 2 |
| 4 | Pre-class `attack_stat` = highest stat? | 2 |
| 5 | Per-char energy base = 2; energy-relic/`gain_energy` pool attribution | 3 |
| 6 | Skill = CardData (rarity audit of 29 cards); hand/draw 5 per character? | 4 |
| 7 | Upgrade/Ascension as skill-annotation projection | 4, 7 |
| 8 | Creation goes single-member in item 5 (race-only later)? solo-downed = TPK? | 5 |
| 9 | Draft-pool assembly rule (tag × tier × rarity weights) | 6 |
| 10 | Promotion eligibility → act boundary (retire `promotion_level`) | 7 |
| 11 | Shop sells skills; currency earn/price provisional table | 8 |
| 12 | Scaler baseline 8 / exp 1.0; Act-3 boss option A; `meta_cash_out_acts` + XP provisional | 9 |
