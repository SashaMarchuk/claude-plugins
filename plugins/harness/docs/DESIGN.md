# harness — Design

Universal autonomous orchestration harness: runs Claude Code sessions in real terminals to
execute tickets end-to-end (GSD-flavored by default), unattended, with deterministic
rate-limit pausing and safe terminal lifecycle. One plugin, any project, any number of accounts
(including exactly one — the default).

This document records the decisions and the *why*. The lessons ledger at the bottom encodes
real incidents from three prior harness generations (aut-infra `.night-session`,
`aut-web-harness`, Subscription-Telegram-Bot `coordination/`) — every engine rule below that
cites `L<n>` exists because that failure actually happened.

## 1. Shape

Three layers, strictly separated:

| Layer | What | Determinism |
|---|---|---|
| `bin/` engine | bash verbs: config, term, spawn, limits, tickets, state, run, model | fully deterministic — no LLM decides anything here |
| skills/commands | `/harness:onboard,init,add,run,status,stop,resume` — wizards and the orchestration playbook | LLM-driven, but every side effect goes through `bin/` verbs |
| agents | `spawn-validator` (sonnet), `context-summarizer` (sonnet) | advisory gates; never author commands |

The orchestrator and workers are ordinary Claude Code sessions spawned into terminals.
All coordination is file-based (markers + state + heartbeats — three channels, never one
overloaded log) under `<project>/.harness/runs/<run-id>/`.

## 2. Config: user + project, deterministic merge

- **User config** `~/.claude/harness/config.json` — how *this person's machine* behaves:
  terminal app + layout, account launcher, limit policy defaults. Written by `/harness:onboard`.
- **Project config** `<project>/.harness/config.json` — what *this project* is: repos, ticket
  source, model chains, parallelism, guardrails. Written by `/harness:init`.
- Resolution order for `cfg()`-read keys (per key): **project > user > built-in default**
  (`hlib.sh::cfg`). Duplicating such a key at both levels is fine and expected. NOTE: the
  orchestrator reads a few project-shape keys straight from the project file (`repos`,
  `workflow`, `parallel`, `guardrails.owner_gated`/`never_push`, `tickets`) — these are
  project-level only, with no user fallback.
- Both files follow the house schema discipline: `schemaVersion`, atomic tmp+rename writes,
  unknown keys preserved. State always lives outside the plugin dir (survives `/plugin update`).

## 3. Accounts — optional by design

Default is **one account, zero ceremony**: the launcher runs plain `claude`, using whatever
login the machine has. Multi-account support is a single universal hook:

```json
"accounts": { "env_command": "", "label": "" }
```

`env_command` is any command that prints `export`-style env vars (e.g. cloak's
`cloak switch --print-env work`); the generated launcher `eval`s it before `exec claude`,
preflighted with a loud, distinguishable failure (exit 9, L7). Empty = single account.
No account rotation, no headroom-chasing: prior runs proved rotation "works technically but
caused enough confusion the owner banned it" (L14) — and per-account role *separation* is
still possible by giving a different `env_command` per role in project config.

## 4. Models — `|` means OR

Any model value may be a fallback chain: `"fable|mythos|opus"`. Rules:

- `model.sh resolve <chain>` maps aliases (`fable`, `mythos`, `opus`, `sonnet`, or full IDs)
  and returns the chain as an ordered list. `haiku` is rejected (policy).
- **Spawn-time fallback (interactive sessions):** the generated launcher tries candidates in
  order; if `claude` exits non-zero within the boot grace window (45s), the next candidate is
  tried and the fallback is logged. A restricted/absent model (e.g. Fable off-subscription)
  falls through automatically — no config edit needed the morning it changes back.
- **Print-mode sessions** additionally get native `--fallback-model <rest-of-chain>`
  (comma-separated; CLI-verified: only works with `--print`).
- Default chains: orchestrator `opus`, worker `opus`, validator `fable|mythos|opus`,
  summarizer `sonnet`. Sonnet is reserved for validation + big-context summarization
  (e.g. n8n workflow JSON) — never for build work.

## 5. Terminals

`term.sh` backends: `iterm2` (AppleScript), `terminal` (Terminal.app), `tmux`. Chosen by user
config; first-run detection via `$TERM_PROGRAM` (deterministic: it names the terminal the
user actually runs Claude in), overridable any time.

- **Layout**: roles map to window groups (default `two-windows`:
  `control` = orchestrator + watch, `work` = everything else). First spawn in a group creates
  a window (optionally sized to full screen bounds); later spawns become tabs of that window.
  Window identity is tracked by id *and* re-resolved through the tty of a member session,
  because iTerm window ids drift/collide (L10).
- **Sessions are addressed by tty**, recorded at boot verification, never by window id or
  process-grep patterns (L10, L4).
- **Spawn = generated launcher file**, never inline heredoc/`write text` command strings:
  `.harness/runs/<id>/launchers/<name>.sh`, `bash -n`-linted before use (L1), absolute paths
  only (L2), `cd <dir> || exit 66` before anything else — the "claude opened in `$HOME`/PC
  root" class of bug is structurally impossible (L3).
- **Boot verification**: after spawn, poll for the `claude` process with the expected
  `--session-id` for up to 45s; write the registry entry (name, role, tty, session UUID,
  window group, cwd, model) only on BOOT-VERIFIED; report BOOT-FAILED loudly otherwise (L4).
- **Close protocol** (the "confirm dialog closed everything" fix, L11): to close a session,
  send `/exit` into it (double-Enter pattern — fast key bursts are treated as paste, L5),
  wait for its job to end, then close *that session only* via the backend. A session whose
  job won't die is left open and reported — the harness never force-closes, never closes a
  window, and never touches sessions absent from its own registry (L12).

## 6. Limits — pause, don't stop

`limits.sh` reads the **active account's OAuth token from the macOS Keychain first**
(`Claude Code-credentials`), falling back to `~/.claude/.credentials.json` — the file goes
stale after refresh on macOS and 401s (L6). It hits `api.anthropic.com/api/oauth/usage`
and reads the structured `limits[]` array (session + weekly + model-scoped entries).

Policy (config, defaults shown):

```json
"limits": {
  "pause_next_spawn_at": 90,
  "resume_margin_seconds": 90,
  "stop_at": null,
  "on_unreadable": "proceed"
}
```

- At/above `pause_next_spawn_at`: **existing sessions keep running; new spawns return
  exit 75** with the reset time. The orchestrator calls `limits.sh wait`, which sleeps until
  the API's `resets_at` + margin (authoritative ISO timestamp — no terminal-text time
  parsing, L8) and re-checks before returning.
- `stop_at: null` means the harness **never voluntarily stops** — matching the standing
  owner directive from real runs (L13). Set a number to opt into a hard stop.
- Unreadable/`null` API responses are "can't observe", not "no limit": log WARN and follow
  `on_unreadable` (`proceed`|`hold`).
- The watch loop additionally detects the interactive limit banner in session text and
  clears it after reset using the guarded escape-then-continue pattern — only when the
  session is idle (no `esc to interrupt` footer), never mid-turn (L9).

## 7. Tickets — GitHub by default, local files as floor

- `tickets.source: "github"`: labeled issues are the queue —
  `harness:ready → harness:in-progress → harness:done|blocked|needs-review` — listed with
  `--json ... --jq 'sort_by(.number)'` (deterministic FIFO), claimed via label swap +
  `--add-assignee @me`, progress via one in-place status comment
  (`--edit-last --create-if-none`). Labels are bootstrapped idempotently by `/harness:init`.
- `tickets.source: "local"`: `.harness/tickets/<n>-<slug>.md` with a `status:` frontmatter
  field and the same state machine — for projects without a queue repo (e.g. a folder of
  repos). Same verbs, same ordering.
- ClickUp stays human-mediated by policy: the user copies a ClickUp ticket into
  `/harness:add` (or writes the GH issue manually). The harness never reads ClickUp.
- **Projects v2 is deliberately not the queue**: a state change costs a 4-step opaque-ID
  lookup chain vs one label flag; labeled issues appear on any board the user attaches.

## 8. The grill gate — first, always

A ticket is executed only after the readiness checklist (outcome, scope/repos, acceptance
criteria, out-of-scope, references). Enforcement is layered: a deterministic engine floor
(`tickets.sh` refuses to create a `ready` ticket whose body lacks the Outcome/Scope/Acceptance
headers) under the LLM grill that does the real quality judgment. Points:

1. `/harness:add "implement X"` — the gate runs *before* the ticket is created: interactive
   grilling via AskUserQuestion until the checklist is satisfied (or the user explicitly
   accepts defaults, which is recorded in the body). Insufficient + non-interactive →
   created as `harness:blocked` with an `## Open questions` section.
2. Run-time preflight — the orchestrator re-checks the checklist as the **first** action on
   every claimed ticket; failure → `harness:blocked` + a questions comment + skip. Never
   guess (L15).

## 9. Run lifecycle

- `run.sh start`: preflight (configs present, gh auth if github source, terminal automation
  probe, limits snapshot, `bash -n` self-lint) → create run dir → copy prompt templates into
  the run (shipped templates are never edited in place) → start caffeinate (harness-managed,
  no `-t`, respawned by watch if dead — L16) → start the deterministic watch loop → spawn the
  orchestrator.
- **Watch loop is plain bash, not an LLM**: every 60s checks STOP file, heartbeat staleness,
  session liveness (tty ps), limit banner, caffeinate. It nudges and reports; it never kills.
- `run.sh stop` (also `/harness:stop`): touch STOP → graceful-close every registry session
  (workers first, orchestrator last) → stop watch + caffeinate. STOP is checked before every
  spawn and every watch tick.
- `run.sh resume`: relaunch watch, respawn dead sessions with `--resume <recorded-session-id>`
  (exact continuation; `--continue` is cwd-ambiguous with parallel sessions, L17).
- Heartbeats: each session appends `<utc-ts> <step>` to its heartbeat file every ~10 min
  (prompt-enforced) — but stall verdicts always cross-check ground truth (git/CI state)
  before alarming (L18).

## 10. Orchestration playbook (prompt templates)

Shipped in `templates/prompts/`, copied per-run, substituted from config:

- **Orchestrator**: claim tickets FIFO → grill gate → derive parallel lanes (by repo and
  file-surface overlap) → one git worktree per lane, branched from `origin/<default_branch>`
  (L19) → spawn workers via `spawn.sh` only → gate cycle (verify → independent review → fix →
  re-verify) → merge lanes locally; **never push, never merge to default branch** unless
  project config explicitly allows → ticket comments as it goes → RUN-REPORT.md +
  OWNER-ACTIONS.md at the end (one consolidated "needs your hands" list, L20).
  Completion signal for any multi-wave step is the *finalize commit*, never the first
  commit (L21). AskUserQuestion is banned during runs; ambiguity → decision log with
  rationale (council pattern for hard calls) or `harness:blocked`. Irreversible/prod actions
  are always owner-gated regardless (L22).
- **Worker**: single lane, GSD-flavored (`workflow: "gsd"`): headless `--auto` GSD entry
  points only — interactive GSD commands hang unattended sessions (L23). Definition of done
  = gates green + finalize commit + pr-ready marker.
- **Validator**: independent session (optionally different account label), re-verifies
  against actual code, never trusts builder status files (L24).

## 10a. GSD is driven by discovery, never hardcoded

GSD command names drift, so the harness never bakes them in. `harness-gsd.sh discover` enumerates
the currently-installed `/gsd-*` skills (and flags whether the `mcp__gsd__*` tools are present) at
runtime; the worker/orchestrator prompts load `skills/harness/references/gsd-workflow.md`, which
tells the session to (a) discover the surface, (b) prefer the drift-resistant MCP tools and the
high-level unified drivers (a progress/intent-dispatch command, the autonomous full-cycle command,
the workstreams command) over naming each stage, (c) verify exact names via `/gsd-help`, and
(d) always use the `--auto`/autonomous variant. Harness lanes map to **GSD workstreams**; the full
cycle (research → plan → execute → verify → learn) runs per workstream, with context refresh
(map-codebase / docs-update) up front and learnings capture (extract-learnings / mempalace) at the
end. The harness owns terminals/limits/tickets/safety; GSD owns the engineering workflow inside
each lane.

## 10b. Trust dialogs and secrets

- **Trust dialog** ("Do you trust the files in this folder?"): the harness **pre-trusts** each
  worktree it creates by setting `hasTrustDialogAccepted` for that path in `~/.claude.json` — but
  only for paths verified inside the project, via a merge that preserves every other key. The
  watch loop is the backstop: a dialog that appears anyway is answered yes only after a
  deterministic in-project check AND a Sonnet confirmation; anything outside is surfaced to the
  operator, never auto-trusted.
- **Passwords / sudo**: never typed. The watch loop detects a password/passphrase/sudo prompt and
  owner-gates it (ATTENTION + OWNER-ACTIONS.md); prompts recommend passwordless setups (macOS
  Docker Desktop needs no sudo; else `docker` group / scoped `NOPASSWD`). Typing a secret into a
  terminal is the one thing the harness will not do on the user's behalf.

## 11. What was deliberately left out (anti-overengineering)

- No LLM watchdog (deterministic bash is cheaper and can't hang on the same modal as its
  ward — L9's root cause).
- No account rotation / headroom chasing (L14 + ToS exposure).
- No Projects v2 write-path, no ClickUp integration, no iTerm2 Python API dependency
  (AppleScript covers spawn/tab/close-single-session; the Python API needs a user-enabled
  setting and a pip install — revisit only if AppleScript proves insufficient).
- No plugin `monitors/` (always-on background processes are the wrong default for a
  sometimes-used harness).
- No cross-run daemon: a run is a directory; the machine's only long-lived artifacts are
  the watch loop and caffeinate, both owned by the run and stopped with it.

## 12. Lessons ledger (evidence → rule)

| # | Incident (real, logged) | Engine rule |
|---|---|---|
| L1 | bash 3.2 heredoc + apostrophe killed two workers silently at boot; heartbeat lied | prompts live in files; launchers are generated + `bash -n`-linted; never inline prompt text in AppleScript |
| L2 | `cd "~/Work/…"` — tilde doesn't expand in quotes; relative `cat` in `~`-cwd booted Claude with an empty prompt (twice) | absolute paths only, enforced by spawn preflight |
| L3 | terminal opened at `$HOME`/PC root and ran claude there | `cd <dir> \|\| exit 66` inside the launcher; cwd validated (absolute, exists, not `$HOME`/`/`, inside project) before spawn; sonnet validator as second net |
| L4 | reap glob matched sibling gate terminals → closed 3 mid-flight; window-id drift blinded the reaper | tty-keyed registry written only after boot verification; close only registry members, by exact name |
| L5 | fast send-keys burst treated as paste; trailing Enter swallowed | `term.sh send` uses text-then-separate-Enter with delay |
| L6 | `~/.claude/.credentials.json` stale → usage API 401 → "no limit" assumption fed the 01:45 crash | Keychain first; 401/null = UNKNOWN, never OK |
| L7 | cloak wrapper swallowed failures → pane died silently | `env_command` preflighted; exit 9 + launcher.log on failure |
| L8 | community tools parse "resets 3pm" pane text with DST math | wait on the API's ISO `resets_at` + margin; never parse terminal time strings |
| L9 | orchestrator AND its watchdog froze on the same limit modal ~3h | watch is deterministic bash; modal cleared only when session idle; timing from the API |
| L10 | iTerm `id of window` collisions observed; ids drift | window group re-resolved via member-session tty; sessions addressed by tty |
| L11 | close-confirmation dialog → user clicked → whole window (all tabs) died | `/exit`-then-close-single-session protocol; never close windows; leave stuck sessions open |
| L12 | a concurrent unrelated fleet on the same machine | never touch sessions outside the run registry |
| L13 | owner's standing directive: "run flat out; never voluntarily slow down" | `stop_at: null` default; pause-next-spawn is the only automatic brake |
| L14 | profile rotation "fully retired — caused confusion" | single account default; per-role `env_command` allowed; no rotation logic |
| L15 | agents hallucinated "clean logs"; guessed scope drifted | grill gate first; blocked > guessed |
| L16 | `caffeinate -t 15000` expired silently mid-run | harness-managed caffeinate without `-t`, liveness-checked by watch |
| L17 | `--continue` grabs "most recent session in cwd" — ambiguous with parallel sessions | pre-generated `--session-id` UUIDs; resume via `--resume <id>` |
| L18 | clock-skewed heartbeats caused a false stall alarm | stall verdicts cross-check git/CI ground truth |
| L19 | worktrees stacked on uncommitted sibling HEADs | worktrees branch from `origin/<default_branch>` |
| L20 | owner actions scattered across state files | OWNER-ACTIONS.md template: why/command/verify per item |
| L21 | executor raced planner's checker loop (13 min dual-commit) | finalize-commit is the only completion signal |
| L22 | "ignore all limits" override must not unlock prod writes | owner-gated list survives every override |
| L23 | interactive GSD entry points hang all night | headless `--auto` GSD only, listed explicitly in worker prompts |
| L24 | 2 CRITICAL prod bugs found only by the independent final pass | validator role re-verifies against code, never status files |

### Review-wave hardening (Opus + Fable adversarial review of this plugin)

| # | Latent defect the review caught | Fix |
|---|---|---|
| R1 | `if ! validate; then rc=$?` captures the `!`-negation (0), not the validator's 65 → REJECT silently ignored | capture `$?` directly; 65 → return 65, other non-zero → infra-error/proceed |
| R2 | worker in a sibling worktree can't find `.harness/` (walk-up fails) → every engine call dies | launcher exports `HARNESS_PROJECT`; a `.harness-project` pointer is dropped into the worktree |
| R3 | `github && gh_verb \|\| l_verb` silently ran the empty local queue on any gh hiccup | strict `if/else` per verb — gh failures propagate |
| R4 | `do_start` treated rate-pause (75) as fatal → the harness stops itself at 91% | catch 75, `limits.sh wait`, retry the orchestrator spawn |
| R5 | resumed sessions sit idle (restored transcript, no prompt re-trigger); bare Enter is a no-op | after resume boot-verify, `term.sh send "continue"` |
| R6 | liveness/job-end keyed on any `node` on the tty (MCP/dev-server children mask it) | track the claude pid at boot; `kill -0 $pid` is the liveness signal |
| R7 | `cfg`'s `// empty` erased a real `false`/`0` config value | read raw, reject only literal `null` |
| R8 | integer `[ -ge ]` on a fractional percent errored silently → brake never engaged | `awk` numeric compare, no error suppression |
| R9 | Terminal.app auto-selected but can't send `/exit`/nudges → silent no-op stop/watch | auto prefers tmux over Terminal.app; preflight warns if Terminal.app is forced |
| R10 | orchestrator could leave `{{LANE}}` literals in a worker prompt → marker/name rejects | explicit fill+grep contract in the prompt; engine refuses a `--prompt` containing `{{` |
| R11 | `limits.sh wait` (hours) told to run foreground, but the Bash tool caps at ~10 min | orchestrator runs the wait with `run_in_background` |
| R12 | model can't `/exit` itself (assistant text ≠ CLI command) | prompts say "stop working"; the engine's `close` delivers `/exit` to the tty |
| R13 | rate reader metered the machine-default account, not the switched one | `token()` applies `accounts.env_command`, prefers its `CLAUDE_CONFIG_DIR`/`CLAUDE_CODE_OAUTH_TOKEN` |
| R14 | first-run `--dangerously-skip-permissions` hangs on the one-time acceptance dialog | preflight warns unless prior acceptance is confirmed; documented in README |
| R15 | cwd with shell metacharacters would execute inside the generated `cd "$cwd"` | screen cwd for metacharacters before generating the launcher |
| R16 | sibling-cwd allowance admitted every unrelated project under the parent dir | allow a sibling only if it is a git worktree whose main repo is inside the project |
