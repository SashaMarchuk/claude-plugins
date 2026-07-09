# Driving GSD from the harness — discovery-first, never hardcoded

The harness drives GSD (get-shit-done) but **must not hardcode `/gsd-*` command names** — they
change over time. Resolve the current surface at runtime and drive through GSD's own high-level,
stable entry points. This file is loaded by the orchestrator and worker prompts.

## 1. Discover before you drive (every run)

1. `bash {{HBIN}}/harness-gsd.sh discover` — prints the GSD surface installed **right now**.
2. **Prefer the `mcp__gsd__*` tools** if they are in your tool list — that layer is a
   separately-versioned API contract (`@opengsd/contracts`), the most drift-resistant interface
   (`gsd_progress`, `gsd_status`, `gsd_roadmap`, `gsd_execute`, `gsd_doctor`, the
   `gsd_*_plan`/`gsd_*_complete` family, `gsd_reassess_roadmap`).
3. For the live command registry, use `gsd-tools capability list` (JSON) — **not `/gsd-help`,
   which is a hand-maintained static catalog** that can lag what's actually installed.
4. Only fall back to skill names (`/gsd-*`) when neither of the above is available; never guess a
   name from memory.

## 2. Prefer the unified, high-level drivers (they absorb naming drift)

Instead of scripting each stage by name, drive GSD through its highest-level commands and let it
route to the right step:

- **Unified progress / intent dispatch** (`/gsd-progress` today, or the `gsd_progress` MCP tool):
  the situational command — tell it the intent ("advance the current phase", "what's next") and
  it picks the correct step. This is your default driver.
- **Autonomous full-cycle** (`/gsd-autonomous` today): runs all remaining phases
  discuss→plan→execute per phase, unattended. Use it to execute a milestone end-to-end when the
  roadmap already exists.
- **Workstreams** (`/gsd-workstreams` today): GSD's own parallelism — list / create / switch /
  status / progress / complete / resume. **Map each harness lane to a GSD workstream** rather
  than inventing a parallel scheme; let GSD own cross-workstream sequencing.

## 3. The full cycle — by intent, resolved to current commands

Follow GSD's real cycle; resolve each stage to whatever the discovered surface calls it today:

| Stage | Intent | Typical current command (verify via help) |
|---|---|---|
| Bootstrap | start a milestone / project if none is active | `/gsd-new-milestone`, `/gsd-new-project` |
| Context | refresh the codebase/doc picture before planning | `/gsd-map-codebase`, `/gsd-docs-update`, `/gsd-ingest-docs` |
| Research | investigate how to implement the phase | part of plan-phase / `/gsd-discuss-phase --auto` |
| Plan | produce the phase plan | `/gsd-plan-phase --auto` |
| Execute | implement the plan | `/gsd-execute-phase --auto`, or `/gsd-autonomous` for all phases |
| Verify | prove the phase goal is met | `/gsd-verify-work`, `/gsd-code-review` |
| Learn | capture decisions/lessons for the long run | `/gsd-extract-learnings`, `/gsd-mempalace-capture` |

## 4. Unattended-safe recipe (critical — `--auto` alone is NOT enough)

Interactive GSD entry points call AskUserQuestion and **hang** an unattended session, and a
single `--auto` flag does **not** silence every prompt (plan-phase's split/decision-coverage
gates and discuss's per-area questions still fire). The reliable recipe:

1. **Seed `.planning/config.json`** before driving: `workflow.skip_discuss=true` (the only way to
   silence discuss's per-area questions) and `workflow.auto_advance=true` (sets AUTO_MODE in
   execute — auto-approves human-verify, auto-selects the first option on decision checkpoints).
2. **Drive the milestone through the autonomous command** (`/gsd-autonomous` today) rather than
   the individual stage commands — it substitutes the automated `gsd-verifier` for the
   interactive `verify-work` conversation, avoiding that stage's hard interactivity. Or chain with
   the progress command's `--next --auto` (hands-free plan→execute→verify until a real blocker).
3. **Bootstrap by hand when there's no auto path.** `new-milestone` has no autonomous variant and
   `new-project --auto` still asks ~10 setup questions — so if a milestone/roadmap must be created
   unattended, **seed `.planning/config.json` / `PROJECT.md` / `ROADMAP.md` directly** following
   the repo's existing convention instead of running those commands.
4. **Accept the irreducible pauses** — GSD deliberately stops on: a blocker (any step failure), a
   `human_needed`/`gaps_found` verification item, a `human-action` checkpoint (auth/2FA — genuinely
   unautomatable), and milestone-audit gaps. When you hit one, do NOT force past it: record it via
   `{{HBIN}}/harness-state.sh owner-action ...` (or block the ticket) and move on. These map
   exactly to the harness's owner-gated list.

## 5. Impactful commands worth using proactively (not just the cycle)

These pay off over a long-running project and are easy to skip — use them when they fit:

- **`/gsd-map-codebase`** / **`/gsd-docs-update`** — run before planning a phase in an unfamiliar
  or drifted area, so plans are grounded in current reality (and docs stay true).
- **`/gsd-workstreams`** — whenever ≥2 independent lanes exist; it beats ad-hoc parallelism.
- **`/gsd-extract-learnings`** + **`/gsd-mempalace-capture`** — at the end of each milestone, so
  the next run starts smarter.
- **`gsd_doctor`** (MCP, DB-only, no session dependency) — run after every slice/phase as a cheap
  structural check; escalate to `/gsd-health --repair` after a crash or if state looks inconsistent.
- **Roadmap reassess** is **MCP-only** (`gsd_reassess_roadmap` / `gsd_roadmap_reassess`, no skill) —
  call it right after each slice/phase completes in DB-backed projects when scope has shifted.

## 6. Where the harness fits

The harness owns terminals, rate-limit pausing, the ticket queue, and the safety envelope. GSD
owns the *engineering workflow inside each lane*. A worker's job is: pick up its lane's tickets →
discover the current GSD commands → drive the full cycle autonomously (workstream-scoped) →
reach gates-green + a finalize commit → set its marker. Never reimplement GSD; drive it.
