# Autonomous build session — 2026-06-07 (P3·01 → run loop)

Worked autonomously from the positionless pivot through a measurable run loop, each
step Godot-4.6-headless test-gated and committed. Suite grew 148 → **140 passing**
(net of the quarantined grid/UI tests + many added).

## Commits (on `main`)
1. `6edaaeb` docs(adr): the positionless + RPG-layer pivot (ADR-0013–0018)
2. `1b7bfed` feat(combat): **positionless combat** — retire the grid (ADR-0013)
3. `a2a635c` feat(ui): **minimal positionless combat screen** (playable single fight)
4. `373e5ac` feat(combat): **stat system** — STR/DEX/CON/INT power the floor (ADR-0014)
5. `86ce2d0` feat(combat): **neutral-flat + ban return on scaling damage** (ADR-0016/0017)
6. `2dd2e1c` feat(content): **placeholder races** — Human/Elf/Orc (ADR-0015)
7. `e35cffc` feat(run): **run controller + HP attrition** across fights (P2·04/05, ADR-0011/0012)
8. `c3c33e8` test(run): **run-level telemetry** wiring (P2·11)

## What's now true
- Combat is **positionless**: target-kind enum, AoE, no grid/move/push; grid + old UI in `/attic`.
- Characters have **STR/DEX/CON/INT** + `attack_stat`; HP derives from CON; the innate
  Strike/Defend floor and owned cards scale; neutral cards are flat; enemies stay flat.
- The `return` **exploit is closed** (loader bans it on owned damage cards).
- Three **races** (Human/Elf/Orc) as data + `apply_race`.
- A **RunController** carries HP across an act: survivors heal post-win, downed revive at
  low HP, TPK ends the run; combat is driven by an injected policy (auto-runner or UI).
- A **playable single-fight UI** (run the project) reflects all of the above.

## Attrition read (the thesis test)
Ran greedy (all-offense) vs varied (defends/heals when low) auto-policies over a full act
(4 combat → elite → boss), 40 seeds each:

| policy | win rate | avg nodes cleared |
|--------|----------|-------------------|
| GREEDY | 40/40 (100%) | 6.00 / 6 |
| VARIED | 40/40 (100%) | 6.00 / 6 |

**Finding:** at current numbers the party steamrolls the act regardless of how it plays —
the P3·02 stat buffs (Strike 4→10, cards scaling) made the existing encounters trivial. So
the attrition thesis (does greed get punished?) **isn't yet testable**; it needs balance
tuning — tougher/more enemies, less healing, or a weaker party. **Tabled per owner: this is
a playtest/design call, revisit together.** The loop and telemetry are ready to measure it
the moment the knobs move.

## Stopping point — needs owner input
- **Classes (P3·04 remaining):** races are placeholders, but the class roster and what each
  class *is* is the owner's creative vision. Blocked on that.
- **Balance tuning:** see attrition read above — playtest call.

## Clean follow-ups (autonomous-able later)
- Run-start **creation flow** (pick class+race per slot; apply race mods + grant custom card; persist to RunState) — needs classes first.
- **Leveling** (P3·05): XP + player-allocated stat points.
- **Map/run UI** (P2·10) + node handlers (rest/event/relic, P2·07/08/12) + run-deck drafting into combat.
