# CLAUDE.md

This repo uses **`AGENTS.md`** as the single source of truth for conventions, architecture rules, run/test instructions, and workflow. **Read `AGENTS.md` first** — everything in it applies to Claude. This file only adds Claude-specific reminders so the two never drift.

## Claude-specific reminders

- **Check decisions before changing settled things.** Grep `docs/decisions/` (ADRs) before altering anything architectural. If a task would contradict an ADR or change a shared interface/schema, stop and propose a new ADR instead of silently diverging.
- **Treat acceptance criteria as the spec.** When given a delegated task, implement exactly its criteria and add GUT tests that prove each one. Don't expand scope or refactor neighbors.
- **Data over code.** Never hardcode balance values; put them in resources under `/data` per `docs/systems/data-schemas.md`.
- **Extend, don't greenfield.** Prefer building on documented template/base code, kept behind our own interfaces and recorded in `/third_party/<name>/PROVENANCE.md`.
- **Verify before done.** Run the headless GUT suite and confirm it passes before marking a task complete.

## Pointers

- Vision: `docs/concept/concept-brief.md`
- Decisions: `docs/decisions/`
- System specs: `docs/systems/`
- Conventions, layout, guardrails, run/test: `AGENTS.md`

*Keep this file short. Any guidance that grows belongs in `AGENTS.md` (or an ADR), not here — one source of truth per fact.*
