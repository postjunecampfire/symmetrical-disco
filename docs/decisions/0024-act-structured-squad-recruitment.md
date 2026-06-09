# ADR-0024: Act-structured squad recruitment — solo start, RNG recruit at Act 2

**Status:** Accepted
**Date:** 2026-06-09
**Deciders:** Michael (owner); Claude (build partner)
**Supersedes:** the *"one race for the whole starting pair — no mix-and-match"* constraint of [ADR-0021](0021-deferred-class-race-origin.md) (see Decision and Consequences). The rest of 0021 — race-base origin, classless Acts 1–3, class chosen at end of Act 3, promotion cadence — is **retained**.
**Relates to:** [ADR-0016](0016-party-size-two-owner-tagged-cards.md) (party of 2), [ADR-0021](0021-deferred-class-race-origin.md) (race-base origin, deferred class), [ADR-0018](0018-meta-progression-exit-package.md) (meta-progression), [ADR-0019](0019-eighteen-act-dungeon-progression.md) (act/power curve). **Depends on** [ADR-0025](0025-per-character-decks-and-hands.md) for how a recruit acts reliably from turn one. *(Update 2026-06-09: ADR-0025 was split — its per-character **energy** decision is accepted, so the recruit's independent energy economy is settled. The per-character **deck/hand** mechanism is now settled by [ADR-0026](0026-derived-decks-from-skill-loadouts.md): the recruit arrives with its own skill collection, loadout, and derived deck — the own-deck assumption is **confirmed**.)*

## Context

The party is fixed at 2 ([ADR-0016](0016-party-size-two-owner-tagged-cards.md)), but *when* and *how* the second slot fills was unspecified. [ADR-0021](0021-deferred-class-race-origin.md) assumed both characters exist at run start and **share a single race** ("no mix-and-match," to stop players cherry-picking a complementary Orc-tank/Elf-mage pair). That assumption is what this ADR revisits: filling both slots at creation front-loads complexity, wastes the onboarding ramp a single character provides, and makes the second slot a static loadout rather than an in-run event. We want the second character to arrive as a designed mid-run beat that forks the run's identity.

## Decision

- **Act 1 is solo.** The run begins with one controllable character — the origin character, **race-base and classless** per [ADR-0021](0021-deferred-class-race-origin.md). One character means the player learns cards, energy, innate Strike/Defend ([ADR-0005](0005-innate-strike-defend.md)), and the run loop without managing two units.
- **A recruit is offered at the start of Act 2.** The player is shown **3 candidates** and picks **1**. This is the run's second identity-defining draft moment (origin character × recruit).
- **Each candidate is a whole person, defined by RACE only — not a class.** A candidate is a bundled **race + starting kit + its own deck** ([ADR-0025](0025-per-character-decks-and-hands.md)). The player reads one card and makes one decision; race supplies the stat template and passive layer ([ADR-0021](0021-deferred-class-race-origin.md), [ADR-0015](0015-classes-races-leveling.md)). The recruit is **classless on arrival, exactly like the origin character** — no pre-classing.
- **Both characters choose class together at the end of Act 3.** The recruit joins in Act 2 and reaches the Act-3 class pick ([ADR-0021](0021-deferred-class-race-origin.md)) alongside the origin character, so the player picks **two classes at the same beat** and can deliberately choose a **complementary pair** (e.g. a physical/caster two-pole, the contrast [ADR-0016](0016-party-size-two-owner-tagged-cards.md) calls for). Identity is symmetric: both are "a normal person of race X" in Acts 2–3, both *become* a class at Act 3.
- **Mixed-race pairs are now possible — but RNG-gated, not cherry-picked.** Because the second slot is filled by a random 1-of-3 offer rather than a free creation-screen choice, the origin's race and the recruit's race may differ (Orc origin + Elf recruit is now reachable). This **supersedes 0021's one-race-for-the-pair rule**, but 0021's intent — *don't let players freely assemble an optimal race combo* — is preserved by the RNG: you adapt to the races you're offered, you don't shop for them.
- **Pure RNG, no re-rolls.** The 3 candidates (each a race, with its kit and deck) are rolled randomly from the eligible pool; the player adapts to what's offered. Adaptation is the intended challenge. (Chosen over complementarity-weighted offers.)
- **The offer pool grows via meta-progression.** The set of possible recruit races/builds starts small and widens as candidates are unlocked across runs ([ADR-0018](0018-meta-progression-exit-package.md)). Run-to-run variety comes from a deepening pool, not from re-rolls within a run.
- **Party caps at 2.** No third recruit in later acts — the card-cycling constraints behind the party-of-2 cap still bind ([ADR-0016](0016-party-size-two-owner-tagged-cards.md), [ADR-0006](0006-draw-as-cooldown-model.md)). The arc is **Act 1 solo → Act 2 onward, party of 2 → Act 3 both classed**.

## Options Considered

| Option | Verdict |
|--------|---------|
| Both slots chosen at run start (one shared race, per [ADR-0021](0021-deferred-class-race-origin.md)) | Rejected — front-loads complexity, wastes the solo onboarding ramp, makes slot 2 a static loadout. |
| Recruit arrives **pre-classed** (race + class bundle) | Rejected — creates an origin/recruit asymmetry (one classed, one not) and skips the recruit past the deliberate classless origin tier; race-only keeps both symmetric and lets them class complementarily at Act 3. |
| Free choice of recruit race (shop the offer) | Rejected — reintroduces exactly the complementary-pair cherry-picking [ADR-0021](0021-deferred-class-race-origin.md) banned. RNG 1-of-3 keeps the adaptation tradeoff. |
| Recurring recruits each act (party grows to 3+) | Rejected — violates the party-of-2 cap and its deck-cycling math ([ADR-0006](0006-draw-as-cooldown-model.md), [ADR-0016](0016-party-size-two-owner-tagged-cards.md)). |
| **Solo Act 1 → RNG 1-of-3 race-only recruit at Act 2, both class at Act 3, pool grows via meta** | **Chosen.** |

## Consequences

- **Two-stage run identity.** A run is defined by origin race × recruit-race-from-a-growing-pool, then by the two complementary classes chosen at Act 3 — a strong variety engine at low content cost, and a concrete answer to "what does the meta-progression pool feed?" ([ADR-0018](0018-meta-progression-exit-package.md)).
- **Mixed-race pairs return as a feature.** The shared-racial-floor / divergent-class-ceiling framing of [ADR-0021](0021-deferred-class-race-origin.md) no longer holds — the two characters can have different racial floors. Per-character stat lines and HP (CON-driven lethality, [ADR-0021](0021-deferred-class-race-origin.md)) must be balanced for heterogeneous pairs, not one shared race template.
- **Difficulty re-tunes at the act boundary.** Act 1 is balanced around one (fragile, classless) unit; Act 2+ assumes two. The 1→2 action-economy jump makes the Act 1/Act 2 seam a deliberate power-curve reset.
- **The recruit must be self-sufficient on arrival.** A 2–3 card injection into one shared deck can't make a new character act reliably; this motivates per-character decks ([ADR-0025](0025-per-character-decks-and-hands.md)). The recruit ships with its **own** deck/hand (and, per 0025, its own energy) so it contributes from its first turn.
- **Symmetric class beat.** Because both characters are classless until Act 3, the class pick is a single two-character decision — simpler to present than staggered class choices, and the natural place to surface complementary-pair guidance.
- **Permadeath interaction.** Losing the recruit is bounded by the downed-not-dead rule ([ADR-0011](0011-death-downed-and-hp-attrition.md)): a downed recruit returns next encounter, so an unlucky RNG recruit is never run-ending.
- **New data entities:** a recruit-candidate definition (race + starting kit + its deck), an Act-2 offer-generation step (roll N from eligible pool), and pool-eligibility state in meta-progression — all data ([ADR-0003](0003-data-driven-content-architecture.md)).
- **Tunable:** the recruit-offer trigger (start of Act 2 default; must sit before the Act-3 class choice so the recruit reaches it), candidate count (default 3), and starting-pool size.
