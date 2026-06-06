# ADR-0009: Toolchain & version control

**Status:** Accepted
**Date:** 2026-06-05
**Deciders:** Michael (owner); Claude (build partner)

## Context

A solo + agent-delegated build needs a reproducible environment and a real repository from day one. The Godot "Create New Project" dialog's *Version Control Metadata: Git* option only **generates `.gitignore` and `.gitattributes`** — it does **not** run `git init`, make a commit, or create a remote. So "we picked Git" is not yet a working repo. This ADR pins the toolchain and defines the git setup.

## Decision

**Engine & renderer**
- Pin the **exact Godot 4.x version** in a `.godot-version` file and via the project's features in `project.godot`. All contributors and agents use the same version.
- Renderer: **Compatibility** (see [ADR-0008](0008-target-platforms-distribution.md)).

**Repository**
- The **Godot project root is the git repo root.**
- `git init` now; make a **first commit** containing `project.godot`, `.gitignore`, `.gitattributes`, `AGENTS.md`, `CLAUDE.md`, and `/docs`.
- **Remote: a private GitHub repository** — for backup, and so delegated agents can work against a shared source with PR review.
- Keep Godot's generated `.gitignore` rule for the `.godot/` import cache (it must never be committed).

**Assets**
- Start **without Git LFS** while art is small placeholder pixel work. **Adopt Git LFS before committing large or numerous binaries** (sprites, audio).

**Workflow**
- Small, focused commits that reference the relevant Asana task. Trunk-based with short-lived branches.

**Editors**
- Godot editor for scenes/resources; **IntelliJ IDEA (GDScript plugin)** or **Rider** as the external script editor, set via Godot's external-editor setting.

## Options Considered

- **Rely on Godot's generated git metadata alone** — Rejected; it isn't an initialized repo and has no history or backup.
- **Local git only, no remote** — Rejected; no backup and no shared source for delegated agents.
- **Git + private GitHub remote, LFS-when-needed** — **Chosen.** Reproducible, backed up, agent- and review-friendly, with minimal upfront overhead.

## Consequences

- Reproducible environment; agents and the owner build against one shared remote.
- Provenance and review become possible (PRs, history).
- A minor one-time LFS migration when the art volume grows.
- The `/docs` tree and agent-context files live *inside* the repo, so documentation and code version together.

## Action Items

1. [ ] Move `AGENTS.md`, `CLAUDE.md`, and `/docs` into the Godot project root.
2. [ ] `git init`; verify `.godot/` is ignored; first commit.
3. [ ] Create a private GitHub repo; add as remote; push.
4. [ ] Add `.godot-version` with the pinned engine version.
5. [ ] (Later) Configure Git LFS; (near release) Steamworks.
