# ZONA — Project Rules

## A: Changes via scripts only
Every change to the ZONA setup must live inside the relevant `.sh` script. Never a raw terminal command, a git operation, or a manual edit handed to the user. Assume zero technical audience: no AI, no git, no Linux knowledge beyond what the scripts themselves teach.

**Contingency — when a step can't be fully automated:**
Some steps are inherently manual (GUI dialogs, PortProton windows, first-game-launch). When that's the case:
- The script must add or modify a step that walks the user through it — printed instructions, exact values, exact button/menu names — and pauses until they confirm it's done (see Rule B).
- All dependencies required by that step must be fetched or verified by the script **before** the step runs, not assumed present. If a binary, package, or file is needed, the script installs/downloads it first, checks it exists, and only then proceeds. A missing dependency is a script bug, not a user problem.

## B: Script self-sufficiency (A/B rule)
Every step a user must take falls into exactly one of:
- **A — Scripted:** the script does it directly, possibly pausing for the user to paste a value (e.g. a GDrive link) or press Enter.
- **B — Manual but fully prompted:** the script prints exact, self-contained instructions (menu paths, button names, exact values) and pauses with `read`/`enter` for confirmation before continuing.

Nothing may rely on the user asking Claude or reading external documentation. If you find yourself explaining something conversationally that isn't already printed by a script, that explanation belongs in the script first.

## C: Working game before performance — one change at a time
Priority order is always:
1. Game launches and is playable (no crashes, no missing renderer, correct prefix/DXGI config).
2. Performance tuning (perf.sh, CPU governor, DXVK config, engine binary, A-Life radius, etc.).

When making changes:
- Do **one modification tree at a time** — a single logical change (one script section, one config value, one ppdb field).
- Track what the last change was so it can be reverted if something breaks before moving on.
- Never layer a second change on top of an unverified first change.

---

# REFERENCE methodology.md
