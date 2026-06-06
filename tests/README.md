# Tests — GUT harness

This project uses **GUT (Godot Unit Test)** for automated tests, per
[`AGENTS.md`](../AGENTS.md) ("Tests: GUT, under `res://tests/`") and
[ADR-0002](../docs/decisions/0002-engine-godot-gdscript.md).

GUT is a **third-party addon** and is intentionally **not vendored in this
repo**. You install it once locally (it lives under `addons/gut/`, which is not
required to be committed), then run the suite. Engine version is pinned to the
value in [`.godot-version`](../.godot-version) (Godot **4.6**).

---

## 1. Install GUT (one-time)

Pick **one** of the two options.

### Option A — Godot editor AssetLib (recommended)

1. Open the project in the Godot editor (`godot --path .` or open
   `project.godot`).
2. Go to the **AssetLib** tab (top of the editor).
3. Search for **"Gut"** (author: *bitwes*), download, and install it. Godot
   places it at `addons/gut/`.
4. Open **Project → Project Settings → Plugins** and **enable** "Gut".

### Option B — Clone into `addons/gut/`

From the repo root:

```sh
git clone https://github.com/bitwes/Gut.git /tmp/gut
mkdir -p addons
cp -r /tmp/gut/addons/gut addons/gut
```

Then enable the plugin in **Project → Project Settings → Plugins**.

> Pin a release compatible with Godot 4.x (the `9.x` line targets Godot 4).
> Check the GUT releases page and check out a tagged release rather than
> `HEAD` if you want reproducibility.

### Provenance / license note (per [ADR-0007](../docs/decisions/0007-build-on-existing-templates.md))

GUT is **MIT-licensed** — permissive, so it is safe to depend on (no copyleft
flag needed). GUT is **tooling**, not shipped game code, so it does not require
a `/third_party/<name>/PROVENANCE.md` wrapper the way borrowed *runtime* bases
do. If you ever vendor (commit) GUT into the repo rather than installing it
locally, add `third_party/gut/PROVENANCE.md` recording the source URL
(`https://github.com/bitwes/Gut`), the exact version/commit you vendored, its
MIT license, and any changes (expected: none — use it unmodified).

---

## 2. Run the tests (headless)

The canonical command from [`AGENTS.md`](../AGENTS.md) ("How to run and test"):

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

This discovers every `test_*.gd` under `res://tests` (recursively) and exits
when done. Run it from the repo root.

Defaults (test dir, prefix/suffix, recursion, exit-on-finish) are also set in
[`.gutconfig.json`](../.gutconfig.json) at the repo root, so the editor's GUT
panel and `gut_cmdln.gd` share one configuration.

---

## 3. Layout

`/tests` mirrors `/src` — one folder per system:

```
tests/
  cards/      combat/    grid/
  units/      ui/        data/
  unit/       test_smoke.gd   ← minimal harness proof
```

Add a system's tests under its matching folder (e.g. grid pathfinding tests in
`tests/grid/`). The naming convention is `test_<thing>.gd` with test methods
named `test_*`. `test_smoke.gd` is a trivial passing test that confirms the
harness itself works once GUT is installed — keep it green.
