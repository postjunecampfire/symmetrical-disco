# ADR-0028 — Dungeon Crawler Carl adaptation: Brawler & Charmer class lines + Cat race

**Status:** Accepted — Phases 0–3 implemented 2026-06-09 (see `docs/systems/dcc-integration-roadmap.md`)
**Date:** 2026-06-09
**Amends:** [ADR-0015](0015-classes-races-leveling.md), [ADR-0022](0022-class-progression-trees-ascension.md) (three-line assumption)
**Source material:** the Dungeon Crawler Carl Slay-the-Spire mod (`~/Claude/Crawl/Crawler`) — two shipped, playtested characters (Carl, Donut) with ~111 cards across five archetypes.

## Decision

Adapt Carl and Donut from the DCC StS mod into the Unnamed Game's **race + class + progression-tree** framework rather than as preset characters:

1. **Two new class lines** alongside Fighter/Mage/Rogue:
   - **Brawler** (STR) — Carl's kit: bombs (AOE with a cost), bare-knuckle multi-hit, block-as-weapon survival. Tree terminates in his book class, **Compensated Anarchist**, and the party-protect capstone **Royal Bodyguard**.
   - **Charmer** (INT) — Donut's kit: charm/debuff control, magic-missile chip damage, fame/celebrity party support. Tree terminates in her book class, **Former Child Actor**, and **Princess**.
2. **One new race: Cat** (DEX 6 / INT 5 / CON 2 / STR 1, custom card *Pounce*) — Donut's species; enters the Act-2 recruit pool automatically. Carl is Human + Brawler; "playing Carl & Donut" = Human/Brawler + Cat/Charmer, no preset system needed.
3. **DCC run-scale systems (Charm thresholds, Fame, Sponsor Boxes) arrive in later phases** as engine extensions, per the roadmap (`docs/systems/dcc-integration-roadmap.md`). Phase-0 data ships only mechanics the current effect registry supports.

## Rationale

- The mod's five archetypes decompose cleanly onto the binary progression tree (1→2→4→8), and its two characters map onto the party-of-2 / recruit structure better than they did onto solo StS — Royal Bodyguard and party-buff Fame payoffs were unbuildable in StS and are natural here.
- Reusing race+class keeps ADR-0021's "any race may pick any class" invariant: a Cat Brawler or Orc Charmer is a legitimate, interesting combination, which a preset-character design would forbid.
- The mod's playtest record (Carl 25% win rate with an Act-2 wall; Donut 50%) gives us pre-tuned relative numbers and known failure modes to avoid (see design doc §6).

## Consequences

- ~~The Act-3 class pick UI must be extended before the lines are playable~~ **Done:** `_show_class_pick` is now db-driven — all five lines are offered.
- ~~`test_progression_tree.gd` iterates the three original lines~~ **Done:** the loop covers all five lines (40 Ults total).
- Five class lines instead of three at the Act-3 pick — UI row fits, but choice pacing is a playtest question.
- ~~Charm ships as a data-only status (inert)~~ **Done (Phase 2):** Charm thresholds/execute, `charm_damage`, the Coup de Grace cash-in, bomb `self_damage` taxes, Gut Check (`self_block`), token generation (`add_card`), Fame + Sponsor Boxes are all live.
