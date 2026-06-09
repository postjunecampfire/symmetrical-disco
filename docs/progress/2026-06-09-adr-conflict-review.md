# ADR Conflict Review — 2026-06-09

A pass over all 25 ADRs in `docs/decisions/` plus the index `README.md`, looking for
contradictions, broken supersession chains, and decisions that depend on undecided ones.
Findings are ordered by severity. Each lists the exact ADRs in tension and what has to
be decided to clear it.

---

## C1 — An *Accepted* ADR (0024) is load-bearing on a *Proposed* ADR (0025) — **blocking**

ADR-0024 (Act-structured squad recruitment) is **Accepted**, but its mechanism for making
the Act-2 recruit playable from turn one rests entirely on ADR-0025:

- 0024 header: "**Depends on** [ADR-0025] for how a recruit acts reliably from turn one."
- 0024 Decision: a candidate is "a bundled **race + starting kit + its own deck** ([ADR-0025])."
- 0024 Consequences: "this motivates per-character decks ([ADR-0025]). The recruit ships with
  its **own** deck/hand (and, per 0025, its own energy)."

ADR-0025 (Per-character decks and hands) is **Proposed — pending owner confirmation.**

So a fully accepted decision is built on an unaccepted one. If 0025 is rejected, 0024's core
claim — that a recruit can act reliably on arrival — has no supporting mechanism, because 0025
itself documents that injecting 2–3 recruit cards into one shared deck *cannot* make the recruit
act reliably (its Context and rejected Option #1).

**To resolve:** decide ADR-0025. If accepted, 0024 stands as written and the status updates in
C2 must be applied. If rejected, 0024 must be reopened to specify a different recruit-reliability
mechanism (e.g. the "per-character draw-guarantee rule" 0025 considered and rejected), or 0024
itself is partly invalidated.

---

## C2 — The canonical deck + energy model is currently self-contradictory — **blocking**

Until 0025 is accepted, the binding decisions are still the **shared** model:

- ADR-0016 (Accepted): "**Shared deck, one hand, one energy pool** — unchanged." Not yet superseded.
- ADR-0017 (Accepted): "Energy: base 3, **shared**." Not yet superseded.

But ADR-0024 (Accepted) already presumes the **per-character** model (own deck, own hand, own
energy — see C1). And ADR-0025 (Proposed) is the only ADR that would actually supersede the shared
core of 0004/0016 and the shared energy of 0017.

Net effect: the current accepted set says *both* "shared deck + shared energy" (0016/0017) *and*
"per-character deck + energy" (0024) are the design. An implementer reading only the Accepted ADRs
gets a contradiction.

**To resolve:** this is downstream of C1. On accepting 0025, perform the status updates 0025 itself
lists:
- mark the shared-deck core of **0004** and **0016** superseded by 0025;
- mark the **shared** energy pool of **0017** superseded by 0025 (its base-3 amount and rare-relic
  model carry forward; only "shared" changes);
- update the index table in `README.md`.

If 0025 is rejected instead, 0024 must be edited so it no longer asserts per-character decks/energy
(ties back to C1).

Note for tuning: 0025 explicitly warns the per-character energy base is **not** a straight copy of
0017's "3" (two pools ≈ double the board energy; +1 energy ≈ 33% throughput per 0017). Whoever
accepts 0025 should record the per-character base as an open balance value, not inherit "3."

---

## C3 — `README.md` index is stale against the ADR files it indexes — **medium**

The index understates two supersessions that the ADR bodies already record:

- **0021 row** lists only "promotion structure refined by 0022; supersedes class-as-template of
  0015." It omits that **0024 supersedes 0021's one-race-for-the-pair / no-mix-and-match rule** —
  which the 0021 file's own Status line *does* state. The index should add that note.
- **0017 row** carries no pointer to 0025. This is acceptable only while 0025 is Proposed; it must
  be updated the moment C2 is actioned.

Because the README opens by declaring ADRs append-only and the index the source of truth for status,
a stale index is a correctness problem, not cosmetics.

**To resolve:** sync the index rows for 0021 (and 0017/0004/0016 once C2 lands) to match the Status
lines in the files.

---

## C4 — ADR-0023 contradicts itself: `hidden` refinement vs. `revealed` baseline — **medium**

Within a single ADR, the fog-of-war model is described two incompatible ways:

- Original **Decision** (and **Consequences**): a per-node **`revealed`** flag, "baseline reveal:
  the **next row only**," everything else hidden. Consequences lists "per-node `revealed` + reveal
  hooks … next-row baseline" as the code to build.
- **Refinement (2026-06-09)**: a per-node **`hidden`** flag that "**supersedes the
  `revealed`/next-row-baseline framing above**." Most nodes are visible; only all `event` nodes plus
  ~⅓ of mid-run combat nodes are hidden.

The Refinement says it replaces the baseline, but the **Consequences** section was never updated —
it still instructs building the superseded `revealed` + next-row model. An implementer reading top
to bottom gets two different flag names and two different default-visibility rules.

**To resolve:** edit 0023's Consequences (and the stale clauses in the original Decision block) so the
whole ADR speaks only in terms of the `hidden` flag and selective fog. This is an in-place wording
fix to an Accepted ADR's *non-decisional* text (the decision itself is settled by the Refinement),
so it does not need a new ADR — but confirm that reading with the owner given the append-only rule.

---

## C5 — Stale "party of 2–3" references in early ADRs never annotated — **low**

ADR-0016 fixed the party at **2** and annotated **0004**. But three earlier ADRs still speak of a
2–3 party and were not annotated:

- **0001**: "A **small party (2–3)**."
- **0006**: "reinforcing the **2–3 party cap** from [ADR-0004]."
- **0011**: Context "**Small party (2–3)**" (its reasoning about finishing "at 50–66% strength"
  assumes a possible party of 3).

These don't change any decision — 0016 is unambiguous and supersedes the range — but the cross-refs
point readers at 0004's outdated number. The README's pivot note only flags the *concept brief* as
stale, not these ADRs.

**To resolve:** add a one-line "(party fixed at 2 by [ADR-0016])" annotation to the 2–3 mentions in
0001, 0006, and 0011, or accept them as historical context (consistent with append-only) and rely on
the index. Either is fine; pick one and be consistent.

---

## Open tensions worth tracking (not yet conflicts)

- **`meta_cash_out_acts` depth.** 0018 leaves the exit threshold tunable; 0019 notes the current
  value `9` predates the 18-act depth and flags it for revisit. Not contradictory, but the number
  should be re-set deliberately once depth is locked.
- **"Party reduction to 1" still dangling.** 0021's open questions keep "possible later reduction to
  1" alive, while 0024 and 0025 now bake "exactly 2" deep into recruitment and the deck/energy model.
  Reviving the 1-party idea later would now be expensive — worth either closing the 0021 question or
  noting the new cost.
- **Turn order is explicitly "prototype" (0010).** No conflict today; 0010 itself says interleaved
  initiative would require a superseding ADR. Flagged only so it isn't mistaken for a final decision.

---

## Suggested resolution order

1. **Decide ADR-0025** (clears C1, unblocks C2). This is the single highest-leverage action — two
   blocking conflicts collapse the moment its status flips.
2. **Apply the C2 status updates** to 0004/0016/0017 (or edit 0024) per the 0025 outcome.
3. **Sync the README index** (C3) in the same commit, so the index never lags the files.
4. **Clean up 0023's Consequences** (C4) to the `hidden` model.
5. **Annotate the stale 2–3 references** (C5) — low priority, batch with the next docs pass.
