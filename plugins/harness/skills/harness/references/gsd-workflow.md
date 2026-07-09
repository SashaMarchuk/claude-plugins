# Driving GSD from the harness — discovery-first, never hardcoded

The harness drives GSD (get-shit-done) but **must not hardcode `/gsd-*` command names** — they
change over time. Resolve the current surface at runtime and drive through GSD's own high-level,
stable entry points. This file is loaded by the orchestrator and worker prompts.

## 1. Discover before you drive (every run)

1. `bash {{HBIN}}/harness-gsd.sh discover` — prints the GSD commands installed **right now** and
   whether the `mcp__gsd__*` tools are available.
2. If the `mcp__gsd__*` tools are in your tool list, **prefer them** — the MCP layer is the most
   drift-resistant interface (e.g. a progress/advance tool, a plan tool, an execute tool, a
   status/roadmap tool). Otherwise use the discovered skills.
3. When unsure of a command's exact current name or flags, run the **help/index** command
   (`/gsd-help` today) and read it — never guess a name from memory.

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

## 4. Unattended-safe rule (critical)

Interactive GSD entry points call AskUserQuestion and **hang** an unattended session. So:

- Always prefer the `--auto` / autonomous variant of any stage command.
- If only an interactive variant exists for something you need, do NOT run it. Either use the
  `mcp__gsd__*` tool for that operation, or author the `.planning/` artifact by hand following
  the repo's existing convention, then continue with the autonomous execute/verify commands.
- `/gsd-help` and `discover` tell you which is which; when in doubt, check the command's own doc
  for an `--auto` flag before invoking it.

## 5. Impactful commands worth using proactively (not just the cycle)

These pay off over a long-running project and are easy to skip — use them when they fit:

- **`/gsd-map-codebase`** / **`/gsd-docs-update`** — run before planning a phase in an unfamiliar
  or drifted area, so plans are grounded in current reality (and docs stay true).
- **`/gsd-workstreams`** — whenever ≥2 independent lanes exist; it beats ad-hoc parallelism.
- **`/gsd-extract-learnings`** + **`/gsd-mempalace-capture`** — at the end of each milestone, so
  the next run starts smarter.
- **`/gsd-health`** / **`/gsd-doctor`** (if present) — if `.planning/` state looks inconsistent or
  a command behaves oddly, diagnose before pushing on.
- **`/gsd-roadmap-reassess`** (if present) — when scope shifted materially mid-run.

## 6. Where the harness fits

The harness owns terminals, rate-limit pausing, the ticket queue, and the safety envelope. GSD
owns the *engineering workflow inside each lane*. A worker's job is: pick up its lane's tickets →
discover the current GSD commands → drive the full cycle autonomously (workstream-scoped) →
reach gates-green + a finalize commit → set its marker. Never reimplement GSD; drive it.
