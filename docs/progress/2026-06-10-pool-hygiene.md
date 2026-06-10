# 2026-06-10 — Pool hygiene: rarity audit + draft/relic weight re-tune (M3)

Audit tool: [`tools/pool_audit.py`](../../tools/pool_audit.py) (reusable; exit 1
on hard flags, accepted exceptions print as watches). Run it any time the card
pool grows: `python3 tools/pool_audit.py`.

Gate: 488 GUT tests green across all 43 scripts (477 baseline + 11 new).

## 1. Headline finding: 46 progression-only cards leaked into draft pools

The dominant pool problem was not rarity mis-tuning — it was **40 capstone ULT
cards and all 6 promotion signature cards missing the `signature: true` flag**,
so `CardReward.eligible_pool` offered them in drafts/shops. ULTs arrive only
via Act-15 Ascension (ADR-0022, `ult_card_id`); promotion signatures only via
`take_promotion`. Both are ×2.0–3.5 `stat_mult` rares that could be drafted at
tier 2. Flagging them shrinks the draftable pool 172 → 126 and explains most
of the apparent "fighter pool grew most" imbalance and the rare-heavy spreads.

## 2. Before / after

Draftable = `card_kind == "skill"`, not signature, not innate, no `upgrade_of`.

**Before (49 flags):**

| line | total | common | uncommon | rare |
|---|---|---|---|---|
| brawler | 21 | 7 | 4 | 10 |
| charmer | 21 | 4 | 6 | 11 |
| fighter | 37 | 12 | 10 | 15 |
| mage | 38 | 11 | 12 | 15 |
| neutral | 17 | 14 | 3 | 0 |
| rogue | 38 | 10 | 13 | 15 |

Class mean 31.0, ±30% band [21.7, 40.3]. brawler/charmer −32%; rare counts
inflated by 8 leaked ULTs per line; charmer had only 4 commons.

**After (0 flags, 5 accepted watches):**

| line | total | common | uncommon | rare |
|---|---|---|---|---|
| brawler | 13 | 6 | 5 | 2 |
| charmer | 13 | 5 | 5 | 3 |
| fighter | 27 | 11 | 11 | 5 |
| mage | 28 | 10 | 13 | 5 |
| neutral | 17 | 13 | 4 | 0 |
| rogue | 28 | 6 | 17 | 5 |

Class mean 21.8, ±30% band [15.3, 28.3]. fighter/mage/rogue all inside the
band — the "+20 on ~10" fighter flag was an artifact of the signature leak.

## 3. Every change

### Signature flags (progression-only cards out of draft pools)

| id → change | why |
|---|---|
| `ult_*` ×40 → `signature: true` | Ascension-only (ADR-0022); were draftable ×2.0–3.5 rares |
| `assassin_ambush`, `berserker_rampage`, `duelist_riposte`, `guardian_aegis`, `pyromancer_firestorm`, `sage_insight` → `signature: true` | promotion-only (`PromotionData.signature_card`); were draftable |

### Re-rarity (flag d — 0-cost at common = 3 free copies per derived deck)

mana_surge precedent: free-economy / engine-stacking cards sit at uncommon
(2 copies), so a deck can't passively hold 3 free plays of an engine piece.

| id → change | why |
|---|---|
| `flicker_strike` rogue common → uncommon | 0-cost scaled damage ×3 copies (the flagged rogue 0-cost economy) |
| `hunters_mark` rogue common → uncommon | 0-cost Mark engine ×3 |
| `poison_tip` rogue common → uncommon | 0-cost Poison stacking ×3 |
| `slip_away` rogue common → uncommon | 0-cost scaled block ×3 — dex-turtle fuel |
| `kindle` mage common → uncommon | 0-cost Burn engine ×3 |
| `reckless_swing` fighter common → uncommon | 0-cost 5+STR damage ×3 (drawback doesn't offset free scaled damage) |
| `cheap_shot` brawler common → uncommon | 0-cost damage + Vulnerable ×3 |
| `human_versatility` neutral common → uncommon | 0-cost free cycle ×3 — pure deck-thinning engine |

Kept at common, allowlisted in the tool: `fleet_footwork` / `rock_throw`
(neutral = flat, never stat-scales per ADR-0016 — honest chaff) and
`magic_missile` (0.5 stat_mult + Exhaust is its own guardrail; it is the
spell_weave/arcane_dodge token; charmer's commons floor needs it).

### Re-rarity (flag b — commons floor)

| id → change | why |
|---|---|
| `cats_grace` charmer uncommon → common | charmer had 4 draftable commons (< 5); 5 Block + draw 1 is common-shaped (cf. rogue common `evasive_roll`) |

### Crossover gating (flag c — new `min_act` field, see §4)

| id → change | why |
|---|---|
| `crimson_harvest`, `mortal_strike` → `min_act: 7` | ×2.0 stat_mult → tier 3 (card-scaling.md §4) |
| `arcane_overload`, `assassinate`, `berserkers_gambit`, `death_from_shadow`, `disintegrate`, `executioners_swing`, `ghost_guard`, `immovable` → `min_act: 10` | ×2.5 stat_mult → tier 4 |

### Description fixes (flag e — text must match numbers)

| id → change | why |
|---|---|
| `assassin_ambush` → "Deal 12 damage. Exhaust." | description was empty |
| `berserker_rampage` → "Deal 16 damage. Exhaust." | empty |
| `duelist_riposte` → "Deal 8 damage and apply 2 Weak." | empty |
| `guardian_aegis` → "Gain 16 Block." | empty |
| `sage_insight` → "Draw 2 cards and gain 1 Energy." | empty |
| `pyromancer_firestorm` → full text | description held only the scaling note |
| `cobbled_bomb`, `cobbled_bomb_plus`, `demolition_charge`, `scorched_earth`, `ult_missile_storm` → append "Hits ALL, at reduced stat scaling." | sub-1.0 stat_mult (0.6–0.8) read as flat damage (firecracker convention) |
| `magic_missile`, `magic_missile_plus`, `missile_barrage`, `xistera`, `ult_combination` → append "At reduced stat scaling." | sub-1.0 stat_mult (0.4–0.8) read as flat |

No numeric amount/stacks mismatches found; `guardians_oath` was a tool false
positive (block 6 + self_block 3 are both authored), fixed in the tool.

## 4. Crossover conclusion (ADR-0020 §3 of the task)

**Rarity weighting alone is NOT sufficient.** `weights_for_act` gives rares
weight 0 only at tier 1; from tier 2 (acts 4–6) rares carry weight 1/10, so
×2.0–2.5 multiplier cards could appear two tiers before their "earliest sane
tier" (card-scaling.md §4: ×2 → T3–4, ×3 → T4+). With starting stats ~8 and
4 pts/level these are not even trap picks early — they are bombs, exactly
what ADR-0020 says must "never be freely available early."

Smallest honest mechanism added: an optional **`min_act` int on CardData**
(default 0 = ungated, parsed/validated by the loader), checked in
`CardReward.eligible_pool` (`run_state.act < min_act` → skip). It is data, not
a code-side stat_mult sniff, so future cards tune their own gate; direct
grants (signatures, ULTs, events, starting kits) bypass it by design. Authored
gates: ×2.0 → act 7, ×2.5 → act 10 (×3.0+ would be act 13; none are draftable
— all ×3+ cards are Ascension ULTs). Enforced by GUT
(`test_no_draftable_high_multiplier_below_rare_or_ungated`) and by the audit
tool's flag (c).

## 5. Per-class pool balance (§4 of the task)

After the signature fixes no line exceeds +30% of the class mean, so **no
cards were re-tagged to neutral** — the over-pool flag was the leak artifact.
Honest moves were also scarce: nearly every fighter/mage/rogue card is
stat-scaled (re-tagging to neutral changes mechanics, ADR-0016) and the wave
cards' tags are pinned by `test_m3_skill_waves`.

brawler and charmer sit ~40% **under** the mean (13 vs 21.8) — an authoring
gap, not a rarity problem: they never received a 20-card M3 wave. Left as a
watch; needs a content wave (~8–10 cards each, common-leaning), not hygiene.

## 6. Relic roll weighting (carried flag)

Elite and treasure relic rolls were a uniform pick over the un-owned non-boss
pool; with the rare-heavy authored spread (7c/15u/10r/4b) a "reward" roll was
more likely rare than common. Now:

- **BattleConfig knobs**: `relic_weight_common` 50 / `relic_weight_uncommon`
  35 / `relic_weight_rare` 15 (in `data/battle_config.json`).
- **`Shop.weighted_relic_pick`** (static): picks a rarity *bucket* by weight
  among buckets with un-owned relics left, then uniform within — deterministic
  per rng state, uniform fallback if all weights are 0.
- Wired into `Shop.treasure_roll`, and `RunController.roll_relic` (used by
  both map_view elite grant paths). The **shop shelf stays uniform** — it
  already prices by rarity; the Sponsor Box keeps its own Fame-tier gate
  (ADR-0028); boss rarity still never reaches these rolls.

## 7. New tests (+11, total 488 across 43 scripts)

- `test_card_reward.gd` (+2): min_act gates a card out below its act and in
  at/after it; min_act 0 keeps act-1 pools intact.
- `test_m3_skill_waves.gd` (+5): no draftable ≥2.0 stat_mult below rare or
  without its crossover min_act; every line (incl. neutral) ≥5 draftable
  commons; ULTs + promotion signatures are signature-flagged; a full
  five-class act-18 eligible pool contains only clean skills (no
  signature/curse/consumable/innate/_plus); ×2.0/×2.5 rares absent at act 4,
  present at act 10 against real data.
- `test_shop.gd` (+4): weighted pick determinism + membership + no boss;
  distribution sanity over 600 seeds (commons out-roll rares, rares still
  roll); empty pool returns `&""`; `RunController.roll_relic` rolls un-owned
  non-boss relics.

## 8. Remaining watches for the cohort sweep (next task)

1. **brawler/charmer pool depth** (−40% vs class mean) — content wave needed;
   expect thinner draft variety in those lines to show up as cohort spread.
2. **Multi-hit × Strength superlinear** (carried) — `perforate`-style
   ×N-hit cards pay the stat per hit at stat_mult 1.0 each; not touched by
   this audit (they pass flag (c) at <2.0) but the sweep should compare
   multi-hit vs single-hit lines at depth.
3. **Rogue uncommon density** (17 of 28) — after the 0-cost demotions the
   rogue line is uncommon-heavy; if tier-1–2 rogue drafts feel starved
   (commons 6), promote one honest flat common rather than re-buffing
   0-costs.
4. **×1.5 hybrids at tier 1** — uncommons carry weight 2/10 at tier 1, so
   hybrid cards can appear before their S>20 crossover. They are traps, not
   bombs (skill-test picks), so left ungated; revisit if the sweep shows
   early hybrid picks sinking win rates.
5. **Rogue DEX double-dip** (ADR-0020 open question) — `ghost_guard`/
   `sidestep`-style defense multipliers now gate at act 10+, but the dex-turtle
   cohort still needs measuring.
6. **Neutral has 0 rares** — by design (neutral never stat-scales, ADR-0016;
   tier-1 origin drafts are all-common), recorded here so the audit's (b)
   check stays scoped to class lines.
