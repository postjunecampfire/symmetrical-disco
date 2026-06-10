# 2026-06-10 — M3 exit gate, automated half: per-line cohort sweep

> **Scope**: this is the AUTOMATED half of the M3 exit gate ("no line/archetype
> >15pp win-rate ahead at its tier"). The **blind-playtest half is OUT OF
> SCOPE here** — it needs the human owner and is still open.

Harness: [`tools/cohort_sweep.gd`](../../tools/cohort_sweep.gd) (CLI driver) +
[`tools/cohort_lib.gd`](../../tools/cohort_lib.gd) (cohort construction +
cell runner), pinned by `tests/run/test_cohort_sweep.gd` (+6 tests).
Machine-readable results: [`2026-06-10-cohort-sweep.json`](2026-06-10-cohort-sweep.json)
(every cell of both reads, per-tier spreads, verdicts).

## 1. Headline verdict — honest version

**Every tier is VACUOUS on the win-rate bar, not a pass.** Under this harness
(kit + emulated drafts + levels, policy bots, no shop/rest/relic economy
beyond one elite relic) **zero of the 40 cohorts ever clears a wall act —
0% wins in all 480 gate-read cells**, confirmed at 0/60 seeds for the two
strongest act-3 cohorts. A 0pp spread among all-zero cells satisfies "≤15pp"
trivially and certifies nothing.

The deepest tier with ANY automated signal is **tier 3 (act 9), via ladder
progress (avg fights cleared of 6)**, which separates cohorts cleanly at acts
3–9. Acts 12/15/18 are fully degenerate (every cohort loses its FIRST fight —
0.00 cleared), consistent with the designed near-unwinnable deep tiers but
also with the harness floor. Applied to ladder *progress* instead of win rate,
**tier 2 (act 6) FAILS the 15pp bar wide** (spread 57.5pp of the ladder) with
**charmer the clear laggard**, not any line dominantly ahead.

## 2. Matrix actually swept (no cuts)

* **40 cohorts** — 4 races (human/orc/elf/cat — the task said 3; content has 4,
  all included) × 5 lines × 2 act-6 archetypes:
  fighter brigand/knight, rogue assassin/thief, mage elementalist/sorcerer,
  brawler demolitionist/pugilist, charmer enchanter/evoker.
* **Acts**: 3, 6, 9, 12, 15, 18 (each tier's last act). **Seeds: N = 20 per
  cohort-act-policy cell** (+60-seed confirms at act 3).
* **Policies**: greedy AND defensive run for every cell; a cohort-act scores
  the **max of the two** (documented below). Turtle/dex-turtle are degenerate
  stress bots, excluded from the gate read.
* Runtime was not prohibitive (≈90s total in chunks), so the full matrix ran —
  the human-only fallback wasn't needed.

## 3. Win-rate table (cohort × tier) — gate read, K = 1.3 drafts/act

Win% (avg fights cleared of 6), averaged over the 4 races, best policy per
cell. Full per-race detail is in the JSON.

| line/archetype | act 3 | act 6 | act 9 | act 12 | act 15 | act 18 |
|---|---|---|---|---|---|---|
| fighter/brigand | 0% (4.49) | 0% (2.99) | 0% (0.20) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| fighter/knight | 0% (4.30) | 0% (2.58) | 0% (0.09) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| rogue/assassin | 0% (4.85) | 0% (2.60) | 0% (0.28) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| rogue/thief | 0% (4.84) | 0% (2.88) | 0% (0.26) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| mage/elementalist | 0% (4.72) | 0% (2.10) | 0% (0.09) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| mage/sorcerer | 0% (4.61) | 0% (2.05) | 0% (0.11) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| brawler/demolitionist | 0% (4.69) | 0% (3.10) | 0% (0.17) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| brawler/pugilist | 0% (4.75) | 0% (3.38) | 0% (0.11) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| charmer/enchanter | 0% (3.54) | 0% (0.78) | 0% (0.01) | 0% (0.00) | 0% (0.00) | 0% (0.00) |
| charmer/evoker | 0% (3.54) | 0% (1.27) | 0% (0.03) | 0% (0.00) | 0% (0.00) | 0% (0.00) |

**Sensitivity read at K = 6.0 drafts/act** (≈ a real act's draft volume; acts
3–12 only) does NOT change the verdict — still 0% wins everywhere — but
confirms the ranking: rogue/thief 3.00 > rogue/assassin 2.95 > brawler 2.55–2.90
> fighter 1.55–1.95 ≈ mage 1.49–1.53 > charmer 0.62–1.07 at act 6.

## 4. Per-tier spread + verdicts

| tier (act) | win-rate spread | ≤15pp verdict | progress spread (of 6-fight ladder) |
|---|---|---|---|
| 1 (3) | 0.0pp (all 0%) | **VACUOUS** — not a pass | 1.90 fights = 31.7pp (charmer bottom) |
| 2 (6) | 0.0pp (all 0%) | **VACUOUS** — not a pass | 3.45 fights = **57.5pp** (pugilist top, enchanter bottom) |
| 3 (9) | 0.0pp (all 0%) | **VACUOUS** — not a pass | 0.35 fights = 5.8pp (rogue top, charmer 0) |
| 4 (12) | 0.0pp (all 0.00 cleared) | **VACUOUS/DEGENERATE** | 0pp — no cohort wins fight 1 |
| 5 (15) | 0.0pp (all 0.00 cleared) | **VACUOUS/DEGENERATE** | 0pp — no cohort wins fight 1 |
| 6 (18) | 0.0pp (all 0.00 cleared) | **VACUOUS/DEGENERATE** | 0pp — designed near-unwinnable; expected |

Tier 6 being all-zero was anticipated (A18 one-shots kit parties); tiers
1–5 being all-zero on WINS was not — it is a harness-floor finding, not a
balance finding (see §7).

## 5. Ranked offender list (by the signal that exists: ladder progress)

1. **charmer (both archetypes) — consistent LAGGARD, every tier with signal.**
   Act 3: 3.54 vs pack 4.3–4.9; act 6: 0.62–1.27 vs pack 1.5–3.4; act 9 ~0.
   Suspected causes, per the pool-hygiene watch list: (a) **thin pool watch
   #1** — 13 draftable skills, −40% vs class mean; (b) the kit's deliberate
   sub-1.0 stat_mult (magic_missile 0.4–0.5); (c) **harness blindness** — the
   bots only play damage/block cards, so charmer's control/Charm-execute
   identity (hex, play_to_the_crowd) is dead weight to them. Charmer dies on
   plain trash (enc_combat_02 ×116, warband ×139 at act 6), not on elites.
   Needs the human-playtest half before any buff decision.
2. **rogue/thief + rogue/assassin — ahead at depth** (top progress at acts 3,
   9; top at 6 under K=6). Matches **watch #3 (uncommon-heavy pool**: 17/28
   uncommons = 2-copy scaled cards densify the deck) and **watch #5 (DEX
   double-dip)** — greedy DEX allocation feeds attack AND slip_away-class
   block. Margin over brawler is small (≤0.4 fights); no dominance >15pp
   provable from win rates.
3. **brawler/pugilist + demolitionist — ahead at act 6** (3.10–3.38 at K=1.3,
   best-in-tier). Matches **watch #2 (multi-hit × STR)** and the AoE-leaning
   kit (cobbled_bomb, cheap_shot Vulnerable) against tier-2 multi-enemy
   warbands. The thin-pool watch (#1) did NOT hurt brawler here — its KIT
   carries it; pool depth only bites when drafts matter more than kits.
4. **fighter/brigand > fighter/knight** mildly everywhere (greedy STR beats
   defensive CON under band-scaled rosters); **mage mid-low** (its draft pool
   is draw/engine-heavy — the bots can't pilot kindle/mana_surge engines).
5. **Race spread is small and orderly** (cat > orc ≈ elf > human progress at
   acts 3–6, ≤0.7 fights) — no race calls for action at this read's fidelity.

## 6. Goldilocks re-check (act 1, 40 seeds, grown pool)

`attrition_sim` ordering **still holds**: defensive 87.5% > greedy 72.5% >
turtle 25.0% > dex-turtle 17.5%. Balanced play beats both rushing and
turtling; the dex-turtle double-dip remains the worst seat.

## 7. What this means for the gate (recommendation)

* The 15pp win-rate bar **cannot be certified by this harness** at any tier:
  the kit+drafts lower bound never beats a wall-act boss (act-3 boss is
  enemy level 18 vs party level ~3; 0/60 for the best cohort). The missing
  power is the run economy the harness doesn't emulate — shop/treasure relics
  (runs own 1 here), rest upgrades, consumables, curated synergy — plus bots
  that can pilot engine/control cards.
* The automated half therefore **reads as: no line/archetype is >15pp AHEAD
  anywhere (nothing dominates); the only out-of-band cohort is charmer,
  BEHIND on progress at tiers 1–3.** The gate decision should ride on the
  blind-playtest half plus a follow-up harness fidelity task (relic/upgrade
  emulation or mechanic-aware bots) — both owner calls, per task rules no
  balance patches were made here.
* One sweep-meaningful artifact for that follow-up: at K=6, fighter/mage
  progress DROPS vs K=1.3 (e.g. brigand 2.99 → 1.95 at act 6) — the
  rarity-first loadout curation swaps 3-copy scaled commons for 1–2-copy
  rares/utilities the bots can't use. Draft volume only helps lines whose
  pools are dense in bot-playable damage/block (rogue). Harness shaping, not
  game balance — but it bounds how literally these rankings should be read.

## 8. Harness design choices (for reproducibility)

* **Cohort** = race × line × act-6 archetype; party = **2 members of the same
  race+line** (isolates the line; encounters are tuned for 2). All grants go
  through the real seams: `start_run` (race kit), `choose_class` (kit skills),
  `apply_progression` (stat bonus + signature `unlock_cards`), `ascend` (ULT).
* **Boundary nudge**: a pick whose beat act IS the sweep act (class @3,
  archetype @6, spec @9, capstone @12, ascension @15) is applied before the
  ladder — uniform for all cohorts, so spreads are unaffected. Deeper
  spec/capstone picks are sampled seeded-uniform among the children.
* **Draft emulation (the known gap, minimum honest version)**: K =
  roundi(1.3 × acts_cleared) seeded drafts via the REAL `CardReward` path —
  `eligible_pool` + `weights_for_act(a)` per emulated act a, so min_act
  gating, signature exclusion and classless-neutral-only acts 1–2 all apply;
  ownership alternates members; rarity copy rules apply via the normal
  `SkillLoadout.acquire`/`derive_deck`. K is a CLI dial (`drafts_per_act`);
  the labeled sensitivity read used 6.0.
* **Loadout curation**: collection → top `skill_slots` ranked signature >
  rarity > latest-acquired (uniform "keep the shiny stuff" player).
* **Pre-leveling**: 3 pts × acts cleared; greedy puts 2/3 into the class
  attack_stat (STR/DEX/INT per line), defensive into CON; remainder CON; HP
  tops to effective max. Same shape as `attrition_sim`.
* **Policy mapping**: every cell ran greedy AND defensive; score = max.
  Observed best-fit: rogue/mage/brawler → greedy (19/24, 20/24, 16/24 cells),
  fighter → defensive (16/24), charmer → split (12/12).
* **Ladder**: the act's 4 combats + first elite + first boss, band-scaled via
  EnemyScaler; iron_brand granted after the elite (same as attrition_sim).

## 9. Bugs found & fixed (harness-side; zero content changes)

* `validate_cohort`: an unknown line/archetype id previously ran a
  **silently classless party** (choose_class fails quietly) and would have
  poisoned the spread read — found live via an arg typo. Now refused; the
  CLI driver exits 1. No product-code bug found: kits, signatures, drafts,
  stat bonuses and ascension all granted correctly through the real seams
  (pinned by the new tests).

## 10. Tests

`tests/run/test_cohort_sweep.gd` — **+6 tests / 82 asserts** pinning: act-6
cohort construction (class, archetype walk, signature, curated loadout, max
HP), K-dial draft counts + min_act respect, pre-level allocation on top of
node bonuses, per-seed determinism, invalid-cohort refusal, and a 2-seed
act-1 `run_cell` smoke with deterministic output. Full gate: 494 green
(488 baseline + 6).
