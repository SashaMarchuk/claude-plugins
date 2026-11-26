# SPEC-repo — plugin anatomy, migration, and the first walking skeleton

**Date:** 2026-09-19 · **Plugin name:** `orchestrator` · **Target repo:** `/Users/sasha-marchuk/Work/claude-plugins`
**Status:** implementation specification. An implementer should be able to build from this without asking a
question. Where a question was unavoidable I invented an answer, marked it, and put it in §15 as a plain
Ukrainian question for round 2.

**Authority, in this order.**
1. `../../round-1/ANALYSIS-01.md` and `../../round-1/TRANSCRIPT-01.md` — what the owner wants. Nothing below
   replaces a decision of his; where a decision is expensive or awkward, the price is named and the decision
   is kept.
2. `JUDGE-cost.md`, `JUDGE-fidelity.md`, `JUDGE-survival.md` — which design won and what to graft.
3. `ARCH-minimal.md` — the winning design. This document does not restate it; it specifies how it becomes a
   plugin in this repository.
4. `<baseline-marketplace>/requirements/OWNER-DECISIONS.md`
   and `docs/config-levels.md` — the owner's own plugin architecture rules (Д1 [416]).
5. `CONTRIBUTING.md` and `CLAUDE.md` in the target repo — this repo's conventions.

**Evidence tags.** **VERIFIED** — read in a primary source on this machine, or a command executed here today
(2026-09-19). **CLAIMED** — a document asserts it and I did not run it. **INFERRED** — my reasoning from the
above; an estimate, not a fact, stated so it can be rejected.

**Defaults.** Every value the owner did not state is marked **DEFAULT-PROPOSED** with a one-line rationale.
Nothing marked that way is a decision. §12 is the complete register and it is a **contract**: nothing outside
it may invent a default at run time, and a test enforces that (§7, test `O-31`).

---

## 1. The decision this is built on

### 1.1 The verdict

| Judge | Axis | 1st | 2nd | 3rd | 4th |
|---|---|---|---|---|---|
| `JUDGE-cost` | cost to build / run | **ARCH-minimal (9)** | operability (7) | reliability (5) | adapters (4) |
| `JUDGE-fidelity` | fidelity to his words | **ARCH-minimal (8)** | reliability (7) | adapters (6) | operability (5) |
| `JUDGE-survival` | behaviour on a bad night | operability (8) | adapters (7) | reliability (6) | **ARCH-minimal (5)** |

**I build on `ARCH-minimal`.** Two of three judges rank it first, and the two that do are the two the owner
argued for himself four separate times — «тут нічого надприроднього не потрібно вигадувати» [171],
«це має бути дуже простий процес» [189], «це має бути надійна річ, дуже проста» [300],
«дуже якісь простий та надійний варіант» [370].

### 1.2 Where the judges disagree, and which one I followed

`JUDGE-survival` ranks the winner **last**, and its objection is not stylistic: it walks the winner through
seven verified nights from `plugins/harness/docs/FIELD-NOTES.md` and finds two failure classes **OPEN by
default** — the alive-but-useless lane (F3, `w-phase-19`: 3,466 of 3,626 Bash calls were the literal string
`echo idle`, 445k tokens, 77 % of all context growth in that window, every liveness signal reading healthy)
and the operation that reports success and moves nothing (F6, `Already up to date` on a merge that ran the
phase branch against itself). `JUDGE-cost` §9.2 concedes the first one against its own winner, in its own
words: *"The winner's cheapness and its weakest point are the same property."*

**My resolution, stated so it can be argued with.** I follow cost and fidelity on the **architecture** — one
bash supervisor, a one-shot judge, no resident model session — and I follow survival on the **build order**.
Concretely:

- Survival's grafts are **not optional extras scheduled after the first night**. Three of them (`G1` evidence
  gating, `G3` the sleep fence, `G14` the teardown-argument lint) are inside the walking skeleton in §11,
  because each closes a failure that cost a whole recorded night, and each is under 40 lines in the narrow
  form specified here.
- Where survival wants a **general** mechanism and cost prices it out, I ship the **narrow** form: `ops.json`
  with three rows for the skeleton's three mutating operations rather than reliability's eight evidence kinds
  and four-phase reconciler (§11 WS-8). That is cost's G5/G6 bought at survival's structural guarantee for
  roughly a tenth of reliability's price. If the owner later adds a mutating operation, adding a row is a
  load-time requirement, so the guarantee generalises for free.
- Where survival wants a **recurring live proof** (`G4`, `adapter.verify_max_age_hours: 24`, a daily live
  smoke per adapter for ever) and cost calls that "a second product", I ship the verifier but run it **at
  preflight** instead of daily: DEFAULT-PROPOSED `adapter.verify_max_age_hours: 0` = verify on every run
  start. Cheaper than daily-forever, stricter than never, and it still catches Amp's five releases in fifteen
  hours because a run that starts today verified today.
- Cost §9.2's own correction (**G2b**) and §9.3's sentinel are treated differently: **G2b is in the skeleton**
  (two lines in the fact-sheet renderer: `Δpct/hour` and `top repeated tool call in the last N events`),
  because it is the single cheapest thing in the whole judgement set that would have caught `w-phase-19`. The
  sentinel ships as a **key set to off** (§12, `sentinel.interval_hours: 0`) with its rationale recorded,
  because it needs a separate account, if the user configures one.

### 1.3 The graft ledger — what lands, when, and from where

`S` = in the walking skeleton (§11). `P` = post-skeleton, keyed and defaulted now so it is not a rewrite later.
`D` = deferred with the tension recorded.

| # | Graft | Source | Phase | Where it lands |
|---|---|---|---|---|
| 1 | Trip watermark `trips/<sha>.json`, `O_EXCL` before the wake | cost G1 / fidelity G3 | **S** | WS-11 |
| 2 | Wake budget `judge.max_calls_per_hour: 12` + `on_budget_exhausted: notify` | cost G1 | **S** | WS-11 |
| 3 | Three-tier change detection, scout on the diff only | cost G2 / fidelity G8 | P | `watch.*` keys, §12 |
| 4 | GSD probe as named commands with the contract pinned | cost G3 | **S** | WS-7 |
| 5 | `control.ack.json` | cost G4 / fidelity G9 | **S** | WS-9 |
| 6 | Dedup key written into the side effect (`orchestrator-action:` trailer) | cost G5 | **S** | WS-8 |
| 7 | Merge-landed assertion | cost G6 | P | `ops.json` row, arrives with the delivery step |
| 8 | BD-1 lint: `pkill` / `killall` / unscoped `docker compose down` fail the build | cost G7 / survival G14 | **S** | WS-0, test `O-40` |
| 8b | Teardown arguments must come from `ledger.jsonl`, never from the environment | survival G14 (the added clause) | **S** | WS-10, test `O-41` |
| 9 | `HARVEST` — a third answer between exit code and done | cost G8 | **S** | WS-6 |
| 10 | `ops.json`, two columns of it (`mutating`, `admissible[]`) | cost G9 / survival G1 | **S** | WS-8 |
| 11 | Detector scorecard in the report; unfired ⇒ `unproven`, never `clean` | cost G10 | **S** | WS-12 |
| 12 | Three capability values (`native \| emulated \| impossible`) + `on_unknown: impossible` | cost G11 | **S** | WS-5 |
| 13 | **G2b** `Δpct/hour` + top repeated tool call on the fact sheet | cost §9.2 | **S** | WS-11 |
| 14 | Sentinel, one call every four hours on a separate account | cost §9.3 | D | key, off |
| 15 | Confidence/ratification register gating the build order | fidelity G1 | **S** | WS-0, `docs/RATIFICATION.md` |
| 16 | `judge.mode: oneshot \| resident` | fidelity G2 | P | key, `oneshot` |
| 17 | `probes.json` — liveness/identity/capacity probes as data | fidelity G4 | P | key path reserved |
| 18 | `plan.json` with `weakened[]` / `denied[]`, each row carrying `owner_item` | fidelity G5 / survival G9 | **S** | WS-5 |
| 19 | Defaults register as a contract, with `scope` and `apply` columns | fidelity G6 | **S** | WS-2, test `O-31` |
| 20 | Board write-back with `board_readback` as the only admissible evidence | fidelity G7 | P | `ops.json` row |
| 21 | `context.basis` as a required key | fidelity G10 | **S** | WS-2 |
| 22 | `context.post_compact_prompt` as **his** key | fidelity G11 | P | key, §12 |
| 23 | Doctor steps 2 and 3 (journal growth; completed-work counter) | survival G2 | **S** | WS-12 |
| 24 | The sleep fence — `mono` beside `at` on every journal record | survival G3 | **S** | WS-3 |
| 25 | `orchestrator:adapter verify`, run at preflight | survival G4 | **S** | WS-5 |
| 26 | `limits.max_concurrent_builds: 1` with `heavy: true` step tags | survival G5 | P | key, §12 |
| 27 | The supervisor spawns lanes; a model never does | survival G6 | **S** | WS-6, test `O-42` |
| 28 | GSD oracle non-self-attribution (`verified_by: the lane that built the phase` is rejected) | survival G7 | **S** | WS-7 |
| 29 | Preflight gate 7 — account distinctness | survival G8 / minimal §11.1 | **S** | WS-5 |
| 30 | The `unsafe` idempotency class | survival G10 | **S** | WS-8 (column in `ops.json`) |
| 31 | Never log the trigger phrases | survival G11 | **S** | WS-3, test `O-43` |
| 32 | `capacity.reserve_pct: 0` shipped as a printed open question | survival G12 / minimal §5.1 | **S** | WS-4 |
| 33 | Claim ordering as a tested invariant | survival G13 / minimal §4 | **S** | WS-6, test `O-44` |

---

## 2. Plugin identity and registration in this repository

### 2.1 Identity

| Field | Value | Note |
|---|---|---|
| Directory | `plugins/orchestrator/` | must equal `plugin.json.name` and the `marketplace.json` entry name (CONTRIBUTING, VERIFIED) |
| `plugin.json.name` | `orchestrator` | |
| First version | `0.1.0` | beta starts at `0.x` and the description is prefixed `(beta)` (CONTRIBUTING, VERIFIED) |
| Category | `development` | matches `harness`, `ultra`, `claude-migrate` in `marketplace.json` (VERIFIED) |
| License | MIT, a copy at `plugins/orchestrator/LICENSE` | |
| Homepage | `https://github.com/SashaMarchuk/claude-plugins/tree/main/plugins/orchestrator` | |
| Dependencies | **none** | it must not require `ultra`; the judge is a `-p` call to a configured model, not a swarm |

**DEFAULT-PROPOSED name `orchestrator`.** It is the word the owner uses throughout the transcript
(«оркестратор», [036], [149], [234], [508]) and the word his own stop commands are built from
(`orchestrator:status`, [508], VERIFIED verbatim). It does not collide with `harness`, which keeps its name,
its install and its state (§9).

`plugins/orchestrator/.claude-plugin/plugin.json`:

```json
{
  "name": "orchestrator",
  "version": "0.1.0",
  "description": "(beta) Unattended multi-agent orchestrator. One bash supervisor owns all state and does all bookkeeping; a model is invoked one question at a time, only when a tick has something no rule answers. Drives an engine it does not own (GSD out of the box, superpowers or your own step list by config), claims one ticket per lane, proves the account and the channel before it starts, stops cleanly when the queue empties, and tears down only what it recorded creating. Platform-agnostic through a six-script adapter directory; provider, platform, account and role are four separate axes.",
  "author": { "name": "Sasha Marchuk", "url": "https://github.com/SashaMarchuk" },
  "homepage": "https://github.com/SashaMarchuk/claude-plugins/tree/main/plugins/orchestrator",
  "license": "MIT"
}
```

### 2.2 The five registration points (CONTRIBUTING §"Adding a new plugin", VERIFIED)

1. `plugins/orchestrator/` with `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `LICENSE`.
2. One entry in `.claude-plugin/marketplace.json` → `plugins[]`: `name`, `description`, `author.name`,
   `source: "./plugins/orchestrator"`, `category`, `homepage`.
3. No `plugin.json.dependencies` (nothing here depends on another plugin in this marketplace).
4. `plugins/orchestrator/tests/run.sh`, and `orchestrator` appended to the `PLUGINS=(...)` array in
   `tests/run-all.sh`. **Without the array entry the plugin is invisible to the regression harness**
   (VERIFIED: `tests/run-all.sh` iterates only that array, and a missing runner is counted as a FAIL, not a
   skip).
5. A row in the root `README.md` Plugins table, and a row in the README's state-paths table
   (`README.md:65` carries one per plugin, VERIFIED) naming `~/.orchestrator/` and
   `<project>/.orchestrator/`.

### 2.3 Process

- **PR only.** `CLAUDE.md` (repo, VERIFIED): *"shipped via PR (no direct pushes to `main`)"*. Branch from
  `main`, one focused PR.
- **`bash tests/run-all.sh` green before the PR**, and the aggregate count must rise by the orchestrator's own
  PASS count and by nothing else. Existing memory: the repo currently runs 475 tests across 11 plugins.
- **A migration note** in `CHANGELOG.md` for every registry-visible change (§9.4).
- **Git push over HTTPS via the `gh` credential helper** (repo memory `project_git_push_over_https`), and
  never `gh auth switch` (global `CLAUDE.md`, VERIFIED): this repo lives outside the work tree,
  so folder routing picks the personal identity automatically.
- **Attribution line** on every commit, as the session harness specifies.

---

## 3. The repo layout

Every file, its purpose, and an INFERRED size. Sizes are estimates for one person who knows this repository;
`JUDGE-cost` §9.1 warns they may be uniformly low.

```
plugins/orchestrator/
  .claude-plugin/
    plugin.json                       # §2.1
  README.md                           # what it is, the five commands, the state paths, the exit codes   ~180
  CHANGELOG.md                        # 0.1.0 + the migration note (§9.4)                                 ~40
  LICENSE                             # MIT
  REQUIREMENTS.md                     # owner items this version implements, by code, with row anchors   ~200
  commands/
    run.md            # /orchestrator:run      — thin wrapper, delegates to the skill                      6
    status.md         # /orchestrator:status   — thin wrapper, runs bin/orc-status.sh VERBATIM (§6.2)      8
    stop.md           # /orchestrator:stop     — --hard | --soft | --custom <ref>                          8
    config.md         # /orchestrator:config   — the config verb (snf OWNER-DECISIONS 6.5)                 6
    doctor.md         # /orchestrator:doctor   — one-shot health check, installs the schedule              6
    adapter.md        # /orchestrator:adapter  — list | verify <id>                                        6
  skills/
    orchestrator/
      SKILL.md                        # the only skill; routes the six verbs, holds nothing stateful     ~220
      references/
        config.md                     # the six slots, the run scope, the defaults contract              ~200
        adapters.md                   # how to write an adapter directory; the six scripts               ~180
        engines.md                    # how to drive an engine you do not own; the probe contract        ~120
        run-anatomy.md                # the run directory, every file, every field                       ~260
        recovery.md                   # restart, orphans, the doctor, the sleep fence                    ~120
  bin/
    orc-lock.py                       # 18-line flock holder; execs the real command under the lock        18
    orc-run.sh                        # THE supervisor: preflight, the tick loop, dispatch, teardown     ~380
    orc-lane.sh                       # one wrapper process per claimed ticket                           ~140
    orc-judge.sh                      # render fact sheet -> one model call -> parse one JSON verdict     ~90
    orc-ctl.sh                        # append one entry to control.json under the lock                   ~70
    orc-status.sh                     # print status.json. ZERO model turns. The only thing he runs often ~60
    orc-preflight.sh                  # the refusal gate (§11 WS-5)                                      ~180
    orc-doctor.sh                     # try the lock; journal growth; completed-work counter              ~60
    orc-config.sh                     # resolve the six snf slots + the run scope; show; set             ~160
    orc-tickets.sh                    # the local registry reader + the readiness predicate               ~90
    orc-report.sh                     # write report.md at finish, including the detector scorecard       ~80
    orclib.sh                         # shared helpers: atomic write, sha1, mono clock, journal append   ~180
  adapters/
    claude/                           # the shipped default adapter (ADAPTER-CONTRACT §5, first to build)
      caps.sh  preflight.sh  launch.sh  normalize.sh  capacity.sh  compact.sh  fixtures/   ~60 each
    acpx-claude/                      # OPTIONAL, opt-in. Same six scripts over `acpx` (§10)    ~50 each
  probe/
    gsd.sh                            # the GSD completion oracle, one line of output              ~25
    none.sh                           # `state=running` always; the honest no-oracle case          ~5
  capacity/
    anthropic-subscription.sh         # the OAuth usage endpoint reader                            ~40
    none.sh                           # prints `kind=unknown reason=no_reader`                     ~5
  config/
    recommended.json                  # ADVISORY ONLY. Connector catalogue. Supplies no value.    ~120
    defaults.json                     # THE defaults register as data (§12). One row per key.     ~200
    ops.json                          # mutating operations + admissible evidence (§11 WS-8)       ~60
    requirements.json                 # owner items -> capability axis -> on_impossible (§11 WS-5) ~90
  templates/
    RULES.md.example                  # R1-15's red-line file, with the two things it cannot cover  ~40
    ticket.md.example                 # the local registry ticket shape                             ~25
    orchestrator.json.example         # a filled slot-4 config, every key, commented                ~90
  docs/
    DESIGN.md                         # pointer + delta to ARCH-minimal; not a second copy         ~120
    RATIFICATION.md                   # every requirement this build rests on + ratified/unratified ~90
    MIGRATION-from-harness.md         # §9, shipped so a user can read it without the repo         ~140
  tests/
    run.sh                            # the regression harness (§7)                               ~420
    fixtures/                         # ticket fixtures, a fake adapter, a recorded event stream
```

**INFERRED total: ~1,750 lines of shell + Python across `bin/`, `adapters/`, `probe/`, `capacity/`.** For
comparison, VERIFIED on this machine today: `plugins/harness/bin/*.sh` is 1,879 lines and
`plugins/harness` as a whole is 3,960 lines across 36 files. The rebuild is therefore **smaller in code than
the thing it replaces**, and the growth is in `docs/`, `config/` and `tests/`, which is the intended
direction.

### 3.1 Two rules about the layout, both from this repo's own conventions

1. **`${CLAUDE_PLUGIN_ROOT}` for everything inside the plugin.** No absolute path, no `~/.claude/plugins/...`
   (CONTRIBUTING, VERIFIED; snf OWNER-DECISIONS 3.3 additionally forbids `~/.claude/plugins/` because Claude
   Code owns that folder).
2. **A thin command plus a hidden skill** (snf OWNER-DECISIONS 6.6). The command carries `argument-hint` and
   `description` and delegates with `$ARGUMENTS` verbatim. The one deliberate exception is `status`, §6.2.

---

## 4. Where state lives, and the one place I depart from the repo's convention

### 4.1 The three locations

| What | Path | Why there |
|---|---|---|
| **Run state** | `~/.orchestrator/` | Outside the plugin, so `/plugin update` cannot wipe it; outside the work tree, so a git worktree cannot fork it; **outside the Claude config root**, see §4.2 |
| **Project-facing, committed** | `<project>/.orchestrator/RULES.md`, `<project>/.orchestrator/CORRECTIONS.md`, `<project>/.orchestrator/tickets/*.md` | R1-15's red lines are the project's; the local registry is the project's work |
| **Config** | the six snf slots (§5) | Д1 [416] |

The run-state tree is `ARCH-minimal` §2.1 verbatim; `references/run-anatomy.md` is where it is documented for
the user. Two additions this spec makes to it, both from the graft ledger:

```
~/.orchestrator/runs/<run-id>/
  ...                                  # as ARCH-minimal §2.1
  control.ack.json                     # graft 5: the supervisor's reply to a control entry
  plan.json                            # graft 18: immutable; weakened[] / denied[] per lane, with owner_item
  trips/<sha1>.json                    # graft 1: one file per predicate firing, created O_EXCL BEFORE the act
  ledger.jsonl                         # ARCH-minimal calls this owned.ndjson; renamed for graft 8b's rule
```

**Naming note:** `ARCH-minimal` calls the resource ledger `owned.ndjson`; `JUDGE-survival` G14 states its rule
against `ledger.jsonl`. I use **`ledger.jsonl`** and say so once, because the invariant is easier to state and
to lint when the file's name is the word in the rule: *every identifier in a teardown command comes from a
`ledger.jsonl` field*.

### 4.2 Why not `~/.claude/orchestrator/` — a measured reason, not a preference

`README.md:65` and every shipped plugin here put user state under `~/.claude/<plugin>/` (VERIFIED). The
orchestrator does not, and the reason is measurable on this machine **today**:

- `CLAUDE_CONFIG_DIR=<profile-dir>` in this very session (**VERIFIED**).
- a profile switcher keeps several profiles (**VERIFIED**), and each is a complete Claude config root.
- `CLAUDE_CONFIG_DIR` moves the whole of `~/.claude` (snf OWNER-DECISIONS 3.3, VERIFIED).

So run state under the config root would be **a different tree per profile**. R1-10 [246] requires a health
check **on a different subscription** — which under a profile switcher means a different `CLAUDE_CONFIG_DIR` — and that
doctor must be able to find the run it is checking. Under `~/.claude/orchestrator/` it structurally cannot.
The lock, the index and the run dirs therefore hang off `$HOME` directly, resolved as
`${ORCHESTRATOR_HOME:-$HOME/.orchestrator}`, which no profile switch moves.

**This is a deviation from a written repo convention, and it is recorded as such** (§14, tension T-8) and put
to the owner (§15, Q9).

### 4.3 A second finding from the same check, and it is worse

The snf user band is slots 3 and 4: `<config-root>/shared/identity.json` and
`<config-root>/shared/plugins/<plugin>.json`. **VERIFIED on this machine today:** none of the profile switcher's
profiles contains a `shared/` directory at all; each holds `identity.json` at its own root. The real shared
config is at `~/.claude/shared/identity.json` and `~/.claude/shared/plugins/` — which is *not* the config root
this session is running under.

**Consequence, stated plainly: under a profile switcher, snf slots 3 and 4 resolve to files that do not exist, and the
entire user band is silently empty.** Every plugin in this marketplace that resolves config by the snf rule
has this behaviour right now; it is not caused by the orchestrator.

**What the orchestrator does about it, and it is the minimum:**

1. Resolve slots 3 and 4 from the config root, exactly as snf specifies.
2. If the config root has no `shared/` directory **and** `$HOME/.claude/shared/` exists, also read the same two
   files from `$HOME/.claude/shared/`, at the **same** slot precedence, and record both paths in
   `config.sources.json` with a `fallback: true` marker.
3. `orchestrator:config show` prints every key with its value, the file it came from, and whether that file was
   reached by the fallback. Nothing is silent.

DEFAULT-PROPOSED `config.user_band_home_fallback: true`. **Rationale:** without it the user band is empty
under every switcher profile, which is indistinguishable from "he configured nothing". **Tension:** it adds a
seventh read path to a scheme snf states has exactly six (OWNER-DECISIONS 3.6), so it is a deviation from Д1
and it is put to him as §15 Q1.

---

## 5. Configuration

### 5.1 The six slots, unchanged

Plugin name `orchestrator`, so the per-plugin files are (snf `docs/config-levels.md` §2, VERIFIED):

| Slot | Path | Band |
|---|---|---|
| 1 | `./.claude/shared/identity.json` | project, committed |
| 2 | `./.claude/shared/plugins/orchestrator.json` | project, committed |
| 3 | `<config-root>/shared/identity.json` (+ the §4.3 fallback) | user |
| 4 | `<config-root>/shared/plugins/orchestrator.json` (+ the §4.3 fallback) | user |
| 5 | `./.claude/shared/identity.local.json` | personal, this project, gitignored |
| 6 | `./.claude/shared/plugins/orchestrator.local.json` | personal, this project, gitignored |

Rules taken verbatim and not re-litigated: the higher slot wins; deep merge except `use`; `never` accumulates;
personal beats committed; resolution is mandatory on every invocation; the resolver never writes;
`plugins/orchestrator/config/recommended.json` is **advisory and supplies no value to any resolved config**
(OWNER-DECISIONS 3.8).

**What goes where (OWNER-DECISIONS 3.4, "reusability is the test"):**

- `identity.json` (slots 1/3/5): accounts and their platform/provider bindings, the notification channel, the
  questions channel, the board connector. All of these are usable by more than one plugin and several already
  are (`~/.claude/shared/tooling.json` holds the Slack transport today, VERIFIED).
- `orchestrator.json` (slots 2/4/6): everything in §12 that is not one of the above — tick interval,
  thresholds, `judge.*`, `worktree.*`, `process.*`, `tickets.*`.

### 5.2 The fourth scope, which is not a config file

He requires three scopes including *this run* (cross-cutting requirement 1; [331], [075]). snf states its three
levels are the whole set (OWNER-DECISIONS 3.6). **Reconciliation, unchanged from `ARCH-minimal` §8.1: the run
scope is not configuration.** It is per-invocation state: `--set key=value` arguments captured into
`runs/<run-id>/config.run.json`, layered on top of the resolver's output by the orchestrator itself, written to
no config file, gone when the run ends. Recorded as tension T-2.

### 5.3 The config verb

`/orchestrator:config` with no argument runs the wizard, and it **re-asks whether what is already set is still
current** (OWNER-DECISIONS 6.2). It writes the answer to **the person's own file** and asks which one
(OWNER-DECISIONS 3.9): slot 6 when inside a project he wants it scoped to, slot 4 otherwise. Sub-verbs:

| Invocation | Effect |
|---|---|
| `config` | the wizard |
| `config show` | every key: value, source file, slot, `scope`, `apply` class, and whether it is the default |
| `config set <key> <value> [--slot 4\|6]` | one key, written to a person's own file, re-resolved and printed back |
| `config doctor` | every slot path, whether it exists, whether it parsed, and whether the §4.3 fallback fired |

`config show` is the only honest answer to *"is the guaranteed-compaction thing still holding tonight"* at
04:00 without a model, so it prints `plan.json`'s `weakened[]` and `denied[]` when a run is live.

### 5.4 The defaults register is a contract

`config/defaults.json` is data, one row per key, and it is **the only place a default may exist**:

```json
{
  "version": 1,
  "keys": {
    "tick.interval_seconds": {
      "default": 60, "type": "integer", "scope": "run", "apply": "live",
      "protects": "a tick cheap enough to run all night with no model in it; one-minute worst-case stop latency",
      "owner_item": null, "proposed": true
    },
    "capacity.soft_pct": {
      "default": 80, "type": "integer", "scope": "user", "apply": "live",
      "protects": "his own worked number", "owner_item": "R1-06[171]", "proposed": false
    }
  }
}
```

- `scope` ∈ `user | project | run` — the highest band at which setting the key is meaningful.
- `apply` ∈ `live | boundary | frozen` — `ARCH-minimal` §8.2's three classes, which it computes but does not
  record. Recording them is fidelity graft 19.
- `proposed: true` means **DEFAULT-PROPOSED** — the owner never stated it. `config show` prints these with a
  marker so he can see, in one screen, every number this build invented on his behalf.

Enforced by test `O-31`: every key name that appears in `bin/*.sh` as a config lookup must exist in
`defaults.json`, and no literal fallback (`${x:-<value>}` over a config value) may appear outside `orclib.sh`'s
single register reader.

---

## 6. Commands, and the zero-token status path

### 6.1 The six commands

| Command | Argument hint | Delegates to |
|---|---|---|
| `/orchestrator:run` | `[--set k=v ...] [--allow-shared-account] [--allow-readonly-board] [--once]` | the skill, which execs `orc-run.sh` under the lock |
| `/orchestrator:status` | `[--run <id>] [--why <lane>]` | **`bin/orc-status.sh` directly**, §6.2 |
| `/orchestrator:stop` | `--hard \| --soft \| --custom <ref>` | `orc-ctl.sh` |
| `/orchestrator:config` | `[show \| set <k> <v> \| doctor]` | the skill (it is a conversation) |
| `/orchestrator:doctor` | `[install \| run \| uninstall]` | `orc-doctor.sh` |
| `/orchestrator:adapter` | `list \| verify <id>` | `orc-preflight.sh adapter-verify` |

The command set is a recommendation, not a restriction (OWNER-DECISIONS 6.4): a user adding a seventh is
correct behaviour, not a violation.

### 6.2 Status must not cost a model turn, and here is exactly how

Д11 [508] is a *pull* surface and [512] asks for «мінімальну кількість аутпуту і стокінгів». `ARCH-minimal`
§12 records the shipped defect (VERIFIED in `plugins/harness/commands/status.md`): status routes through a
skill while the bash underneath it needs no terminal and no network, so ten status checks in a night cost ten
model turns.

**The rule, in three parts:**

1. `bin/orc-status.sh` is pure `bash` + `jq` over `status.json`. It opens no network connection, spawns no
   model, and works with the supervisor dead.
2. `README.md` documents the **true** zero-token path first, before the slash command:
   `~/.orchestrator/bin/orc-status` (a symlink `orc-run.sh` creates at first run), run from any terminal,
   including from inside a lane's worktree — `git rev-parse --git-common-dir` resolves the project from a
   worktree to the main checkout (VERIFIED, git 2.33.0 on this machine).
3. `commands/status.md` exists for discoverability and its body is exactly: *run
   `${CLAUDE_PLUGIN_ROOT}/bin/orc-status.sh $ARGUMENTS` and print its stdout verbatim; do not summarise it, do
   not read any other file, do not call any other tool.* One cheap turn, not a skill.

Test `O-20` asserts `commands/status.md` contains no `Skill` delegation and names `orc-status.sh`.

### 6.3 Exit codes — one table, used by every entry point

From `ARCH-minimal` (69, 70), `acpx`'s stable table (§10.2), and this spec for the rest. They are a published
contract: `README.md` carries the table and test `O-21` pins it.

| Code | Meaning |
|---|---|
| `0` | did what was asked |
| `2` | ambiguous run reference (more than one match in `index.tsv`) |
| `3` | timeout |
| `4` | no such run |
| `5` | blocked on a human |
| `10` | the doctor relaunched a dead run |
| `12` | the doctor found the supervisor alive but not ticking |
| `65` | contract violation found by `adapter verify` |
| `69` | the lock is held (`EX_UNAVAILABLE`) |
| `70` | preflight refused (`EX_SOFTWARE`) |
| `130` | interrupted |

---

## 7. Tests

### 7.1 The shape the repo already uses, and its known weakness

`tests/run-all.sh` runs `plugins/<name>/tests/run.sh` per plugin, greps `PASS=<n>` / `FAIL=<m>` from the final
line, and exits non-zero if any runner fails (VERIFIED). Every existing runner is a set of **static contract
assertions over the plugin source** — `plugins/interview-handoff/tests/run.sh` says so in its own header:
*"these are file contracts, not behaviour tests"* (VERIFIED).

The repo's own memory records the hazard: **the harness greps prose, so tests can pass vacuously**
(`project_contract_tests_mutation_check`). `JUDGE-survival` §7.4 restates it against all four designs:
FIELD-NOTES §11.9 records that every commit gate was found broken *by mutation*, not by failing.

**So this plugin's suite has two halves, and the second is the one that matters.**

### 7.2 Half one — contract assertions (static, fast, no network, no terminals)

| Id | Assertion |
|---|---|
| `O-01` | `bash -n` parses every `bin/*.sh`, `adapters/**/*.sh`, `probe/*.sh`, `capacity/*.sh` |
| `O-02` | `shellcheck -S warning` clean (skipped with a PASS when shellcheck is absent, as `harness` does) |
| `O-03` | `python3 -m py_compile bin/orc-lock.py` |
| `O-04` | `plugin.json` is valid JSON and its `version` matches the head of `CHANGELOG.md` |
| `O-05` | `marketplace.json` has exactly one `orchestrator` entry and its `source` is `./plugins/orchestrator` |
| `O-06` | the directory name, `plugin.json.name` and the marketplace entry name are all `orchestrator` |
| `O-07` | `orchestrator` is present in the `PLUGINS=(...)` array in `tests/run-all.sh` |
| `O-08` | `config/defaults.json`, `config/ops.json`, `config/requirements.json`, `config/recommended.json` are valid JSON |
| `O-09` | `recommended.json` carries a `strength` field on every row, with at least two distinct values (OWNER-DECISIONS 2.3) |
| `O-10` | no `bin/` script reads `recommended.json` (OWNER-DECISIONS 3.8: it supplies no value) |
| `O-20` | `commands/status.md` names `orc-status.sh` and contains no `Skill` delegation |
| `O-21` | `README.md`'s exit-code table matches `orclib.sh`'s constants exactly |
| `O-30` | every adapter directory contains all six scripts and each is executable |
| `O-31` | **defaults contract:** every config key referenced in `bin/`, `skills/` or `adapters/` exists in `defaults.json`; no literal default outside `orclib.sh`'s register reader |
| `O-32` | every `defaults.json` row has `type`, `scope`, `apply`, `protects` and `proposed` |
| `O-33` | every `requirements.json` row names an existing `owner_item` code and an `on_impossible` from the closed set |
| `O-34` | every `ops.json` row declares `mutating`, `idempotency` and a non-empty `admissible[]` |
| `O-40` | **BD-1:** the literal patterns `pkill`, `killall`, and `docker compose down` without an explicit `-p` appear nowhere in plugin source |
| `O-41` | **BD-1b:** no teardown command is constructed from an environment variable; every identifier in a teardown path is read from a `ledger.jsonl` field |
| `O-42` | no process-spawning call (`launch.sh`, `nohup`, `&`) appears in `orc-judge.sh` or in any file under `skills/` — the supervisor spawns lanes, a model never does |
| `O-43` | the strings `/compact`, `rate-limit`, `usage limit` and `context low` are never written by a logging helper into a file a detector reads |
| `O-44` | the claim ordering appears in `orc-run.sh` in the order `mkdir` → `start.json` → launch → `ledger` → `result.json` → `mv` |
| `O-50` | `docs/RATIFICATION.md` has a row for every `owner_item` named in `requirements.json`, each marked `ratified` or `unratified` |
| `O-51` | no em-dash in any shipped file under `plugins/orchestrator/` (this repo's style rule, CONTRIBUTING) |

### 7.3 Half two — behaviour tests over fixtures, and the mutation gate

Five tests that run real code against a sandboxed `$ORCHESTRATOR_HOME` in a temp dir. No network, no model, no
terminal.

| Id | What runs | Pass criterion |
|---|---|---|
| `O-60` | `orc-lock.py` twice concurrently on one lock file | the second prints `LOCK HELD: <pid> <epoch> <argv>` and exits **69**; after the first exits, the third acquires immediately |
| `O-61` | `orc-tickets.sh ready` over `tests/fixtures/tickets/` (3 ready, 1 missing `Acceptance`, 1 with an unmet `depends_on`) | exactly the 3 ready ids, in file order |
| `O-62` | the claim primitive: 20 concurrent `orc-run.sh --claim-only <id>` | exactly one succeeds, 19 exit non-zero, exactly one `lanes/<id>/` exists |
| `O-63` | a fake lane (`sleep 2`) driven through `orc-lane.sh` with a fake adapter | `start.json` before the pid exists, `result.json` last, dir moved to `lanes.done/`, ledger entries in creation order |
| `O-64` | teardown against a ledger holding a `compose` entry whose project name is *not* in the environment | the emitted command contains `-p <name-from-ledger>`; with `COMPOSE_PROJECT_NAME` set to something else in the environment, the emitted command is **unchanged** |

**The mutation gate, and it is a required step in the PR, not a suggestion.** For each of `O-31`, `O-40`,
`O-41`, `O-42`, `O-43`, `O-44`, `O-60`, `O-62`, `O-64`: break the contract on purpose in a scratch copy,
confirm the suite goes **red**, restore. The PR description lists the nine mutations and their observed
results. Repo memory is explicit that this step exists because the harness greps prose, and equally explicit
about the hazard in performing it: **never `git checkout` a file that holds uncommitted work** — mutate in a
`git worktree` or a `cp -R` of the plugin directory, never in place.

`JUDGE-survival` §7.4 is the sentence to keep in `docs/DESIGN.md` verbatim: *until those tests exist and are
verified by mutation, this architecture is a claim, not a property.*

---

## 8. What is borrowed from `plugins/harness`, and what is abandoned

The rebuild exists because patching the previous generation was judged net-negative. That judgement does not
make every line in it wrong, and it does not make copying safe. **The default is abandon.** A file is borrowed
only when a named mechanism inside it is still correct against `FIELD-NOTES.md`.

Sizes VERIFIED today with `wc -l`.

### 8.1 The engine — `plugins/harness/bin/`

| File | Lines | Verdict | Reason |
|---|---|---|---|
| `harness-term.sh` | 235 | **ABANDON, entirely** | It is the terminal séance: `spawn` / `send` / `key` against iTerm2, Terminal.app and tmux. Six FIELD-NOTES records descend from it — §1.3 typed text that never arrived (**five instructions never delivered**, two of them the owner's own), §1.4 a nudge that cannot submit stranded text, §1.5 heartbeat staleness read as a stall (six nudges to six healthy sessions), §1.6 a finished session nobody could close (idle 1 day 4 hours), §2.2 a shell that cannot exit reading as work, §12.1 a 149-minute stall because an Enter never landed. `ARCH-minimal` deletes the capability rather than fixing it. Nothing here is borrowed, including the paste-swallow workaround, because the workaround is evidence the channel is wrong |
| `harness-spawn.sh` | 322 | **ABANDON the file, BORROW two rules** | Borrowed as rules, not code: (a) pin the model and the version on every spawn; (b) never inherit stdin. Abandoned: the boot-verify dance, the trust-dialog handling, and specifically `harness-spawn.sh:32-39`, which defaults to `--dangerously-skip-permissions` **and falls back to it for an unrecognised value** (VERIFIED, C8-A4). In the rebuild an unrecognised permission value is a config error and the default is `inherit` (R1-15 [357]) |
| `harness-trust.sh` | 48 | **ABANDON** | It exists to get past an interactive dialog. A headless `-p` lane never sees one. Keeping it would keep the interactive path alive by accident |
| `harness-run.sh` | 412 | **ABANDON the file, BORROW the shape of one loop** | Its `watch` loop is the ancestor of the tick, and the 60-second cadence is borrowed as `tick.interval_seconds: 60`. Everything else goes: the nudge, the heartbeat staleness heuristic, the attention file (`state/attention` was `: >`-truncated **every cycle**, destroying a night of a second process's corrections, FIELD-NOTES §2.1), and the `healthy` computation built on it (§C9-A4: it would have printed `healthy: true` for all 85 minutes of the loop in which the log read `NO ONE IS BEING TOLD`) |
| `harness-limits.sh` | 120 | **ABANDON the file, BORROW the intent** | The intent — pause, do not stop — is the owner's [007] and survives as the `paused` state. The file is the single worst-performing component in the record: it demands a `.limits` array the live endpoint no longer has, so `snapshot` returns `UNREADABLE` on **every** call; `on_unreadable: proceed` then returns 0 immediately; and `stop_at` is parsed out of the literal string `SESSION=?`, so the hard stop **can never fire** (FIELD-NOTES §11.7, VERIFIED). The rebuild replaces it with `capacity/<provider>.sh` printing one line and a `Capacity = Window \| Credit \| Unknown` type whose `Unknown` variant holds dispatch |
| `harness-tickets.sh` | 221 | **BORROW one function, ABANDON the rest** | Borrowed: the readiness headings `Outcome` / `Acceptance` / `Scope` (`harness-tickets.sh:29-36`, VERIFIED), measured clean across **327 tickets, 288 done, 15 of 15 ready tickets passing, zero violations**. That is the strongest empirical result in the whole corpus and it becomes `tickets.ready_requires`. Abandoned: the two-source state machine that writes status **into the ticket body**, which is C3-A1's self-write loop and C3-A2's 327 dirty tracked files |
| `harness-state.sh` | 53 | **ABANDON** | Markers + heartbeats + logs, "three channels, never one overloaded file". The rebuild has no heartbeats at all (liveness is a pid and a growing event file) and no markers (the claim is a directory). What it protected against — one overloaded file — is preserved by `journal.ndjson` being append-only and never rewritten |
| `harness-gsd.sh` | 60 | **BORROW the idea, REWRITE small** | Discovering the GSD surface at run time so prompts never hardcode drifting command names is right and stays right. It becomes `probe/gsd.sh`, ~25 lines, pinned to three named commands with `engine.gsd.exit_contract: v1` (cost graft 4), because six subprocess calls per lane per tick where three answer is a cost the tick cannot carry |
| `harness-model.sh` | 41 | **ABANDON** | Model OR-chains (`fable\|mythos\|opus`) are a fallback mechanism for a resident session. The rebuild pins one model per role and fails loudly; a silent fallback to a different model is exactly the class ADAPTER-CONTRACT invariant 6 forbids (an inherited `model = "gpt-6-astra"` produced a 100 %-failing Codex run) |
| `harness-validate.sh` | 58 | **ABANDON** | A second model asked to approve the first model's command. R1-13 [344] gives verification to the process and forbids the orchestrator adding checks of its own. It is also the shape FIELD-NOTES §12.7 records failing: 26 refusal events in an audit log that never occurred |
| `harness-guide.sh` | 97 | **ABANDON** | Advisory path-listing for a session's prompt. The rebuild's equivalent is `RULES.md`, which is the owner's own file and his only policy surface (R1-15) |
| `hlib.sh` | 212 | **ABANDON the file, BORROW three helpers** | Borrowed as ~30 lines inside `orclib.sh`: atomic write (`mktemp` in the same directory, then `mv`), the project-root walk, and the config-path lookup shape. Abandoned: `.harness/CURRENT` and its self-healing (`hlib.sh:86-102`, VERIFIED) — a single-value pointer file that repairs itself by guessing is a state machine pretending to be a variable; the rebuild resolves a run from `index.tsv` and exits **2** on ambiguity rather than picking |

### 8.2 Prompts, agents, templates

| File | Verdict | Reason |
|---|---|---|
| `templates/prompts/orchestrator.md` (152) | **ABANDON** | It is the resident orchestrator's system prompt, and the rebuild has no resident orchestrator. It also carries the `"<70% sure"` escalation predicate (VERIFIED, lines 19-21), which C1-A1 shows is a self-report no second party can check |
| `templates/prompts/worker.md` (67) | **ABANDON as a template, KEEP the job** | A lane's prompt is now composed from the ticket body + `RULES.md` + the engine's own entry command. A shipped worker persona is one more thing that drifts from GSD |
| `templates/prompts/validator.md` (30) | **ABANDON** | The validator role is deleted (R1-13) |
| `agents/context-summarizer.md` (20) | **ABANDON** | There is no orchestrator context to summarise |
| `agents/council-advisor.md` (18) | **ABANDON** | The council is deleted |
| `templates/user-config.example.json` (57) | **ABANDON, cite once** | It is the source of `"on_unreadable": "proceed"` (VERIFIED), which made the limiter inert for days. `docs/DESIGN.md` cites it once as the reason the rebuild's default is `hold_dispatch` |
| `templates/project-config.example.json` (59) | **ABANDON** | Superseded by the six snf slots |

### 8.3 Docs and tests

| File | Verdict | Reason |
|---|---|---|
| `docs/FIELD-NOTES.md` (704) | **BORROW, by reference — do not copy** | It is the validated record the rebuild exists because of, and `CLAUDE.md` requires reading it in full before touching `plugins/harness/`. It **stays where it is**. `plugins/orchestrator/docs/DESIGN.md` links to it; copying it would fork the record, which is the exact failure §12.5 describes (`QUESTIONS.md` forking into a worktree copy) |
| `docs/DESIGN.md` (331) | **ABANDON as content, BORROW as a form** | A per-plugin design doc with numbered sections that the test suite and the prompts cite by number is a good habit. The orchestrator's version is a **delta** against `ARCH-minimal.md`, not a second copy of it |
| `tests/run.sh` (382) | **BORROW the harness shape, ABANDON the assertions** | Borrowed: `ok()` / `bad()`, the `PASS=<n> FAIL=<m>` final line the master runner greps, `bash -n` over all scripts, the shellcheck-if-present pattern, the plugin.json/CHANGELOG version check. Abandoned: everything asserting the previous architecture |
| `skills/harness/SKILL.md` (133), `references/gsd-workflow.md` (90) | **ABANDON** | The skill is the flag router for a design that no longer exists. The GSD reference is superseded by `probe/gsd.sh` plus `references/engines.md` |
| `commands/*.md` (7 files) | **ABANDON** | Different verb set; `status.md` in particular is abandoned *because* of what it does (§6.2) |

### 8.4 The one thing borrowed that is not code

**The lessons.** `FIELD-NOTES.md` is a conclusion-free record; the rebuild's `docs/DESIGN.md` carries a short
table mapping each of the seven failure classes (`JUDGE-survival` §1, F1–F7) to the mechanism in this build
that closes it and to the test id that proves the mechanism is still there. That table is the only place the
two plugins are coupled, and it is a citation, not a dependency.

---

## 9. Migration

### 9.1 The shape: coexistence, not an upgrade

`orchestrator` is a **new plugin**, not a new version of `harness`. Both can be installed at once and they do
not collide:

| | `harness` | `orchestrator` |
|---|---|---|
| Commands | `/harness:*` | `/orchestrator:*` |
| User state | `~/.claude/harness/config.json` (VERIFIED, `README.md:65`) | `~/.orchestrator/` |
| Project state | `<project>/.harness/` (VERIFIED, `hlib.sh:17-102`) | `<project>/.orchestrator/` + `~/.orchestrator/runs/` |
| Config | its own JSON files | the six snf slots |
| Lock | none (a `CURRENT` pointer file) | `~/.orchestrator/locks/<sha1(project-root)>.lock` |

**Nothing in the orchestrator reads, writes or deletes anything under `.harness/` or `~/.claude/harness/`.**
That is not politeness; it is R1-16 [370] and Д3 [430] applied to the plugin itself. Test `O-45`: the string
`.harness` appears nowhere in `plugins/orchestrator/` except in `docs/MIGRATION-from-harness.md`.

### 9.2 What a user has to do, in order

1. `/plugin install orchestrator` from the same marketplace.
2. `/orchestrator:config` — the wizard. It asks the six questions that have no default (the questions channel,
   the notification channel, the accounts per role, the board connector, the engine, the platform) and writes
   the answers to a file it names out loud.
3. **Move the tickets.** `orchestrator:config migrate-tickets [--from <dir>]` reads
   `<project>/.harness/tickets/*.md` and writes `<project>/.orchestrator/tickets/*.md`. It is a **copy**, never
   a move, and it never touches the source. Algorithm:
   1. For each `<n>-<slug>.md`: read the frontmatter `status:` line.
   2. Map `harness:ready | ready → ready`; `in-progress → ready` (a half-done ticket is re-offered, never
      resumed, because the rebuild has no record of what the old lane did); `done → done`;
      `blocked | needs-review → blocked`.
   3. Check the body for the three `ready_requires` headings. Missing one ⇒ write the file with
      `status: draft` and list it in the migration report. **Never invent a heading.**
   4. Write `depends_on: []` when absent; the old format has no dependency field.
   5. Print a table: id, old status, new status, and the reason for any downgrade.
4. **Move the red lines.** If `<project>/.harness/` holds a rules or guidance file, it is *shown*, not copied,
   with the instruction to author `<project>/.orchestrator/RULES.md` by hand. R1-15's file is a policy
   document; copying one automatically is how a policy silently changes.
5. **Nothing else migrates.** Not run state, not heartbeats, not markers, not reports, not the session
   registry. Explicitly: a live `harness` run is **not** adopted. If one is running, `/orchestrator:run`
   refuses at preflight with the exact sentence and the command to stop it, because two orchestrators against
   one project is the failure R1-10 [300] names by name («не може бути такого, що вже якісь існуючі
   оркестратор і спускається наступний ... Це треба відслідковувати і **не дозволяти**»).
6. Leave `harness` installed until a full night has run on the orchestrator. Then `/plugin uninstall harness`,
   and delete `~/.claude/harness/` and `<project>/.harness/` **by hand**. The orchestrator will not do it:
   FIELD-NOTES §11.11 records ~150 orphaned Docker volume pairs produced by a cleanup path acting on residue
   it did not create, and Д3 [430] confines teardown to what the run started.

### 9.3 What `harness` does in the meantime

**Nothing changes in `plugins/harness/` in this PR.** Not the version, not the description, not one file. The
repo's `CLAUDE.md` requires reading `FIELD-NOTES.md` in full before changing anything under that directory,
and this change does not need to. A later PR may add one line to its README pointing at the successor; that is
a separate, registry-visible change with its own migration note.

### 9.4 The migration note (goes in `plugins/orchestrator/CHANGELOG.md` under `0.1.0`)

> **Migration.** `orchestrator` is a new plugin, not an upgrade of `harness`. Install it alongside; nothing is
> removed and nothing is read from `.harness/`. Run `/orchestrator:config` once, then
> `/orchestrator:config migrate-tickets` to copy your local ticket queue into `<project>/.orchestrator/tickets/`
> (a copy: the originals are untouched, and any ticket missing one of the three required headings arrives as
> `status: draft` with the reason printed). Author `<project>/.orchestrator/RULES.md` yourself; red lines are
> not copied automatically. Run state lives in `~/.orchestrator/`, deliberately outside `CLAUDE_CONFIG_DIR`, so
> a watchdog on a second account can find the run it is checking. `harness` is unchanged and keeps working;
> uninstall it by hand once you have had a good night on this one.

---

## 10. The `acpx` adoption

### 10.1 The recommendation, and the size it is kept to

`ADOPTION-VERDICT.md` §5 Change 1 calls adopting `acpx@0.17.0` pinned *"the single highest-value,
lowest-commitment move in the entire research, and the only 'adopt' recommendation on the table"*.
`ARCH-minimal` §7.4 accepts it and shrinks it: **`acpx` is one legal value of an adapter's `launch.sh`, not a
structural dependency.** This spec follows `ARCH-minimal`, and the reason is the same project's own record:
**40 `### Breaking` sections in 44 releases** (CLAIMED in `ADOPTION-VERDICT.md` §3), one of which required
recreating existing sessions.

**VERIFIED on this machine today (2026-09-19):** `npm view acpx version` → `0.17.0`, `dist-tags.latest` →
`0.17.0`. `acpx` is **not** currently installed here (`command -v acpx` → nothing), so every behavioural claim
about it below is **CLAIMED** from `ADOPTION-VERDICT.md`, not re-executed.

### 10.2 The seam — exactly where it plugs in

```
plugins/orchestrator/adapters/
  claude/            # the default. Drives `claude -p --verbose --output-format stream-json` directly.
  acpx-claude/       # opt-in. Same six scripts. Only launch.sh, normalize.sh and compact.sh differ.
```

`adapters/acpx-claude/launch.sh`, the whole seam:

```bash
#!/usr/bin/env bash
# adapters/acpx-claude/launch.sh <lane-dir>
set -uo pipefail
. "$(dirname "$0")/../../bin/orclib.sh"
lane="$1"; . "$lane/env"          # ticket, worktree, session_id, model, timeout_s, account

"$ACPX_BIN" claude sessions ensure --name "$session_id" >/dev/null || exit 70
exec "$ACPX_BIN" --format json --json-strict --timeout "$timeout_s" \
     claude -s "$session_id" --cwd "$worktree" \
     --permission-policy "$permission_policy" \
     "$(cat "$lane/prompt.txt")" < /dev/null
```

and the exit-code mapping, which is the only thing the core learns about `acpx`:

| `acpx` exit | Lane outcome | Note |
|---|---|---|
| `0` | `done` — subject to the harvest check (§11 WS-6) | exit 0 is never sufficient on its own |
| `1` | `failed` (`reason: agent_runtime`) | |
| `2` | `failed` (`reason: usage`) — a config error, refuse to retry | |
| `3` | `failed` (`reason: timeout`) | maps onto the orchestrator's own `3` |
| `4` | `failed` (`reason: no_session`) — the session id was lost; reseed | |
| `5` | **`blocked_on_human`** | a first-class state, not an error (§10.3) |
| `130` | `stopped` (`stopped_by: signal`) | |

**Claimed stability:** across 44 published versions the CHANGELOG contains no entry that changes an exit code
(`ADOPTION-VERDICT.md`, VERIFIED by its author, CLAIMED here).

### 10.3 The four rules that come with it, kept verbatim

1. **Pin `acpx@0.17.0` exactly.** `adapters/acpx-claude/preflight.sh` reads `acpx --version` and **exits 70**
   on any other version, naming both. DEFAULT-PROPOSED `acpx.version: "0.17.0"`, DEFAULT-PROPOSED
   `acpx.on_version_drift: refuse`. An unpinned `acpx` in an overnight run is a run-ending risk.
2. **Depend only on the stable triple:** subcommand names, exit codes, `--format json --json-strict`. Not the
   runtime API, not the session-journal schema — both have already broken. Test `O-46`: nothing under
   `adapters/acpx-claude/` references `acpx`'s session-journal paths or its Node API.
3. **Exit `5` is a first-class outcome.** A lane that asks a fixed-choice question does not wait; it fails the
   turn, and the orchestrator writes `blocked_on_human`, files the question in the Д6 channel, and **holds
   that ticket while other tickets continue** ([449]). `LANDSCAPE.md` §5 sharpens this: the field is **split**,
   not unanimous — Sortie ADR 0025 makes a human-input request a non-retryable terminal, claudexor parks it as
   a durable pending interaction answerable later. This build takes Sortie's side for the skeleton and keeps
   claudexor's as the post-skeleton option behind `questions.answer` (§12).
4. **Keep the queue, the stop verbs, the board write-back and the quota policy in your own code.** `acpx` is a
   session layer. It is never allowed to own a ticket, a claim, a stop or a number.

### 10.4 The exit path, costed

`ADOPTION-VERDICT.md`: *"delete the dependency and go back to driving terminals. You lose a capability, not a
run. The reversal is an afternoon."* In this layout it is smaller than that, and it is a config change:

1. `config set platforms.<lane>.adapter claude` — one key, `apply: boundary`, so it takes effect at the next
   lane launch and a live lane keeps what it booted with.
2. `rm -rf plugins/orchestrator/adapters/acpx-claude/` and `npm rm -g acpx`.
3. Nothing in `bin/` changes, because nothing in `bin/` names `acpx`. Test `O-47` pins that: the string `acpx`
   appears in `plugins/orchestrator/` only under `adapters/acpx-claude/`, `config/defaults.json`,
   `config/recommended.json` and `docs/`.

**INFERRED: under an hour, and provably zero core edits.** That property is the reason the adoption is
acceptable at all, and test `O-47` is what keeps it true.

### 10.5 What is deliberately *not* adopted

- **The OpenClaw Gateway.** Rejected by `ADOPTION-VERDICT.md` on its own maturity scorecard and on **722
  lifetime security advisories** (CLAIMED), against a `VISION.md` that states *"We do not keep long-lived
  aliases or compatibility branches"* — pinning to stay stable and patching to stay safe are mutually
  exclusive there.
- **DeepSeek Harness as a runtime.** Not in this category: it brings its own loop, and its only Claude Code
  path is one-shot. Three of its *designs* are borrowed as rules and cost nothing: the settings-file write
  protocol (read under the lock, temp sibling, `rename`), *boot fails loud / reload keeps last good*, and
  *append `start` first, `end` last*.
- **`acpx` as the default.** The default adapter is `claude`, driving the CLI directly. `acpx-claude` is
  opt-in. DEFAULT-PROPOSED `platform.default_adapter: claude`. **Rationale:** the first night must not depend
  on a dependency published four days into its current major, and `ARCH-minimal`'s design does not need it.

---

## 11. The walking skeleton

### 11.1 What it is, precisely

**One ticket, one lane, one platform, one engine, through to a clean stop.**

| Axis | The skeleton's single value |
|---|---|
| Ticket | one local-registry ticket at `<project>/.orchestrator/tickets/001-<slug>.md`, `status: ready`, carrying `Outcome` / `Acceptance` / `Scope` |
| Lane | `concurrency.max_lanes: 1` for the skeleton run (the shipped default stays 2) |
| Platform | `claude`, driven directly — `claude -p --verbose --output-format stream-json` |
| Provider | the platform's own account; no provider lane, no `base_url` override |
| Engine | `gsd`, with `probe/gsd.sh` as the completion oracle |
| Board | none; `tickets.source: local`, `board.writeback: false` |
| Questions | `questions.channel: <project>/QUESTIONS.md` |
| Notifications | `notify.channel: terminal` |
| Judge | one predicate only: `lane-silent` |
| Stop | `stop-soft`, applied on the next tick, draining to a clean finish |

**Definition of done for the skeleton, as an observable checklist.** Every line must be true of one real run
before the skeleton is called finished:

1. `/orchestrator:run` acquires the lock, and a second invocation exits **69** naming the holder.
2. Preflight proves the account identity, refuses on a shared account, and prints
   `(platform, base_url, account-identity)` per role.
3. Exactly one `lanes/<id>/` directory exists, with `start.json` written **before** the pid exists.
4. `events.norm.ndjson` grows during the lane's turn and carries at least one `context` event with a real
   `used_pct`.
5. `probe/gsd.sh` prints a `state=` line every tick, at zero model cost.
6. A `stop-soft` typed in a second terminal appears in `control.ack.json` as `applied` within 90 seconds.
7. The run drains, tears down exactly what `ledger.jsonl` lists, asserts each teardown by observation, writes
   `report.md`, deregisters from `index.tsv`, releases the lock, and exits **0**.
8. `orc-status.sh` is run ten times during the night and the model-turn count for those ten runs is **zero**.
9. `report.md`'s detector scorecard lists every predicate and marks the ones that never fired `unproven`,
   never `clean`.
10. `bash tests/run-all.sh` is green, and the nine mutations of §7.3 were each observed to turn it red.

**What the skeleton deliberately does not have:** no board, no second platform, no provider lane, no attached
terminal, no doctor schedule, no sentinel, no scout tier, no stacked PRs, no compaction beyond the soft
threshold set at launch, no resident judge. Each is a key that exists and is off (§12).

### 11.2 Build order

Twelve steps. Each is **independently demonstrable** — it has one command a person can run and one thing they
can look at — and each leaves the repo green. The order is chosen so that nothing is built before the thing it
needs to be proven against.

---

**WS-0 — Scaffold, registration, and the two gates that fail the build.** *(~1 day)*

Build: the directory tree of §3 with every file present but stubbed; `plugin.json`; the marketplace entry; the
README row; `tests/run.sh` with §7.2's static half; `orchestrator` in the `PLUGINS` array;
`docs/RATIFICATION.md` with one row per owner item this build rests on. Both build-failing lints land **now**,
before there is any code to violate them: `O-40` (BD-1: `pkill`, `killall`, unscoped `docker compose down`) and
`O-43` (never log a trigger phrase).

Demo: `bash tests/run-all.sh` — the aggregate count rises by the orchestrator's PASS count, `FAIL=0`.
Then mutate: add `pkill -f foo` to a stub and confirm `O-40` goes red.

Proves: the plugin exists in the registry and in the harness, and the two invariants that protect the owner's
machine are enforced from the first commit rather than retrofitted.

**Gate on `docs/RATIFICATION.md` (fidelity graft 15).** Д12 is recorded **UNRATIFIED** in `ANALYSIS-01.md` —
the session ended on it and the interviewer noted *"підтвердження залишається відкритим"* [525]. R1-06's
hard/soft vocabulary was restated at [176]/[177], answered with «Повтори, будь ласка», and never re-put. The
skeleton needs a stop, so it cannot wait for round 2. **The rule instead: the stop mechanism is built, and the
owner's vocabulary is kept in a replaceable mapping table**, `config/defaults.json` key
`stop.verb_map` — `{"stop-hard": {"verb":"stop","scope":"run","apply":"now"}, ...}`. If round 2 changes what
«хард» means, that is a table edit, not a rewrite. Nothing else in the skeleton depends on an unratified
vocabulary.

---

**WS-1 — The lock.** *(~0.5 day)*

Build: `bin/orc-lock.py` (18 lines): acquire an exclusive `fcntl.flock` on the lock file, write
`pid epoch argv` into it, set the fd inheritable, `execvp` the real command. On contention: print
`LOCK HELD: <pid> <epoch> <argv>` and exit **69**.

**VERIFIED today on this machine:** `flock(1)` is **not installed**; `/usr/bin/shlock` exists but is PID-based
and PID-recyclable; `python3` is 3.9.6 and `node` is v22.18.0. So the Python holder is not a preference, it is
the only correct primitive available without a new dependency.

Demo: `python3 bin/orc-lock.py /tmp/x.lock -- sleep 5 &` then the same command again — the second prints the
holder and exits 69; after the first exits, a third acquires immediately. **No TTL, no stale-lock timeout, no
heartbeat.**

Proves: R1-10's «не дозволяти» is a syscall, not a heuristic — and the lock *being acquirable* is itself the
proof that a previous supervisor is gone, which is what makes recovery (WS-12) deterministic.

---

**WS-2 — Config resolution and the defaults contract.** *(~1.5 days)*

Build: `bin/orc-config.sh` and `config/defaults.json`. Algorithm for `resolve`:

1. Determine the config root: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Never assemble `$HOME/.claude` when the
   variable is set (snf OWNER-DECISIONS 3.3).
2. Determine the project root: `git rev-parse --git-common-dir`, then its parent. **VERIFIED on git 2.33.0
   today:** from inside a worktree this returns the main repo's `.git`, so the resolution is correct from a
   lane's worktree.
3. Read slots 1 → 6 in order. A missing file is empty, not an error. A malformed file is a **loud refusal**
   naming the file and the parse error (dsh's rule: boot fails loud).
4. If the config root has no `shared/` and `$HOME/.claude/shared/` exists, read slots 3 and 4 from there too,
   at the same precedence, marking `fallback: true` (§4.3).
5. Deep-merge, higher slot wins; `use` replaces; `never` accumulates.
6. Layer `config.run.json` (the `--set` arguments) on top. Record its keys separately so `config show` can say
   "this run only".
7. For every key not set anywhere, take the value from `config/defaults.json`. **A key absent from the register
   is a fatal error, not a `null`.**
8. Write `config.resolved.json`, `config.sources.json` (the six or eight paths with `(mtime,size)`), and
   `config.run.json` into the run directory.

Also lands here: `context.basis` as a **required** key (fidelity graft 21) — `raw_window |
usable_after_reserve | statusline` — because C5-A2 measured two percentages ~13 points apart on this machine
and a threshold is meaningless without saying which scale it is on. `config set context.raw_pct_threshold`
prints **both** numbers for a live session at the moment he sets it.

Demo: `orchestrator:config show` on a project with slots 2, 4 and 6 populated — every key prints with its
value, its source path, its slot, its `scope`, its `apply` class, and `(proposed)` where the owner never stated
it. Then `config doctor` prints all eight candidate paths and which ones the fallback reached.

Proves: Д1 is obeyed, the fourth scope exists without a fourth file, and every invented number is visible in
one screen.

---

**WS-3 — The run directory, the journal, the sleep fence, and the status renderer.** *(~1.5 days)*

Build: `orclib.sh` (atomic write, sha1, journal append, the mono clock), the run-directory creator,
`index.tsv` registration, `bin/orc-status.sh`, and `orc-run.sh --once` — a supervisor that ticks exactly once
over an empty queue and exits.

**The sleep fence (survival graft 24), and it lands here because every later duration depends on it.** Every
journal record carries `mono` beside `at`. `mono` comes from `python3 -c 'import time;print(int(time.monotonic()))'`,
which is one ~30 ms subprocess per tick at a 60-second cadence — INFERRED as negligible, and it is the only
portable monotonic clock in this toolchain (macOS `date` has none). Every duration is computed on `mono`; wall
clock is for display only. A tick where `wall_delta - mono_delta > sleep.gap_seconds` writes
`observation: machine.wake` with the gap, and for `sleep.grace_seconds` afterwards **no lane may be judged dead
and no capacity reading taken before the wake is authoritative**. DEFAULT-PROPOSED `sleep.gap_seconds: 60`,
`sleep.grace_seconds: 120`.

This is not defensive decoration: FIELD-NOTES §10.1 records that the previous run ended
`orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`. Sleep is literally how the
last run died.

Demo: `orc-run.sh --once` on a project with no tickets. Look at `~/.orchestrator/runs/<id>/`: `journal.ndjson`
has one tick line carrying both `at` and `mono`; `status.json` exists and has **no `healthy` field**;
`orc-status.sh` prints twelve lines. Then `pmset sleepnow`, wake the machine, run `--once` again and read
`observation: machine.wake` with the measured gap in the journal.

Proves: the zero-token pull surface works with no model anywhere in the path, and durations survive the way
the machine actually behaves.

---

**WS-4 — Tickets, readiness, and capacity.** *(~1.5 days)*

Build: `bin/orc-tickets.sh` and `capacity/anthropic-subscription.sh`.

**Readiness** is the structure he assigned at [145]/[146], and it is a grep:

> A ticket is ready iff **(a)** its frontmatter `status:` equals the configured ready state, **and (b)** its
> body, with frontmatter stripped, contains every heading in `tickets.ready_requires`, **and (c)** every id in
> its `depends_on:` list resolves to a ticket whose status is `done`.

DEFAULT-PROPOSED `tickets.ready_requires: ["Outcome", "Acceptance", "Scope"]` — the previous generation's
three headings (VERIFIED, `harness-tickets.sh:29-36`), measured clean across 327 tickets, 288 done, 15 of 15
ready tickets passing, zero violations.

**Capacity** prints one line and exits 0:

```
kind=window  bucket=seven_day used_pct=62 reset_epoch=1789923599 prov=measured
kind=credit  remaining=41.20 unit=USD prov=measured
kind=unknown reason=http_429
```

Three things land with it, each closing a measured failure:

1. **`Unknown` is a variant, not a zero.** DEFAULT-PROPOSED `capacity.on_unknown: hold_dispatch` — finish what
   is running, start nothing new, notify once. This is the deliberate inversion of the shipped
   `"on_unreadable": "proceed"` (VERIFIED) that made the limiter inert for days.
2. **`capacity.cache_seconds: 900`, one read per account per tick maximum.** C4-A3 is a VERIFIED measurement:
   a *single* well-formed call to the Anthropic OAuth usage endpoint returned `rate_limit_error` because
   another process had polled a minute earlier — and the owner's own global `CLAUDE.md` instructs *every*
   Claude Code session to poll that endpoint. The cache protects the reader from the owner's own fleet.
3. **A threshold on a bucket the provider does not report is a configuration error**, loud at preflight and
   loud again on the first tick that cannot find it. C4-A5, VERIFIED: across 7,379 Codex `rate_limits` records
   on this machine, `primary` is the 5-hour window in 471 records and the weekly window in 1,098 within the
   same plan, and on the current plan the 5-hour window is absent from **3,030 of 3,030** records. A threshold
   on a vanished bucket is indistinguishable from a bucket at 0 %.

Also here, survival graft 32: DEFAULT-PROPOSED `capacity.reserve_pct: 0`, **and preflight prints one line
naming it as an open question with the exact wording to put to him** (§15 Q4). The interviewer dropped that
sub-question; this build will not invent a reserve for an account he also works in.

Demo: `orc-tickets.sh ready` over a five-ticket fixture prints exactly the three ready ids and, for each
rejection, the clause that failed. `capacity/anthropic-subscription.sh <account>` prints one line; with the
network unplugged it prints `kind=unknown reason=<why>` and **never** `used_pct=0`.

Proves: the two inputs that decide whether anything is dispatched at all are deterministic, cheap, and honest
about not knowing.

---

**WS-5 — The adapter, preflight, `requirements.json` and `plan.json`.** *(~2.5 days)*

Build: `adapters/claude/` (all six scripts), `bin/orc-preflight.sh`, `config/requirements.json`,
`orchestrator:adapter verify`.

`caps.sh` prints one line of static facts, with **three** values per axis, not two (cost graft 12):

```
launch=native identity=native transcript=native context=native quota=native \
accounts=native intervene=emulated guardrails=native extend=native ops=native \
quotaModel=window idAssignment=client attachable=yes sandbox=no
```

Two rules on it, both from ADAPTER-CONTRACT §2.0: it must be derivable **without a network call or a model
token**, and it must **never report `native` for a capability whose only implementation is a regex over
English prose**. DEFAULT-PROPOSED `negotiate.on_unknown: impossible` and
`negotiate.on_undocumented: probe_then_impossible` — so adding a new requirement row makes every existing
adapter answer `unknown` and that degrades **closed**, which is the property that stops a new safety rule
passing silently on an old adapter.

`config/requirements.json` is the one place platforms are **not** named — one row per owner item:

```json
{ "R1-08.hard-compact": { "axis": "context", "needed_when": "context.mode == 'hard'",
    "on_impossible": "degrade", "degrade_to": "reseed", "owner_item": "R1-08[204]" },
  "R1-07.account-switch": { "axis": "accounts", "needed_when": "always",
    "on_impossible": "refuse-run", "owner_item": "R1-07[199]" },
  "R1-11.answer-question": { "axis": "intervene", "needed_when": "questions.answer == 'always'",
    "on_impossible": "deny-role", "owner_item": "R1-11[324]" } }
```

**Preflight, in order. It spends zero model tokens and it refuses loudly.**

1. Acquire the lock, or exit **69** naming the holder.
2. Resolve config (WS-2). Refuse on a malformed slot file.
3. `process.kind` is exactly one of `engine | steps`. Both set is a config error — R1-03's
   «комбінувати ні, тут або або» [118] as a one-line check.
4. `adapters/<p>/preflight.sh <account>` per configured role. It must prove **which account** a spawn would
   use, from the platform's own report, not from the variable that was set.
5. **Gate 7, account distinctness (survival graft 29).** Refuse when two roles the config separates resolve to
   one account identity, naming both profiles and the shared id, unless `--allow-shared-account`.
   Two profiles can be the **same account** — two config dirs, two keychain entries, **one quota pool**. Without this gate the per-role
   thresholds compute correctly against a pool that is silently shared.
6. `orchestrator:adapter verify <id>` (survival graft 25) against `adapters/<id>/fixtures/` plus one live
   read-only smoke. Exit `0` pass / `65` named contract violation / `70` environment. Three checks carry it:
   `compact` must return a **Proof**; `send` must report `accepted` and nothing stronger; `readCapacity` must
   return the sum type and a 200 it cannot parse must **raise**, never return zero.
   DEFAULT-PROPOSED `adapter.verify_max_age_hours: 0` — verify at every run start.
7. Negotiate `requirements.json` against each lane's `caps.sh` map. Write **immutable** `plan.json` with
   `weakened[]` and `denied[]`, each row carrying `owner_item`, the axis, from what to what, and the
   consequence. Print it at start, carry it in `status.json`, and show it in `config show`.
8. The notification channel **delivers a real message**. A `getMe`-shaped check is refused as proof: C9-A5
   records Telegram's `getMe` passing for a bot that had been kicked from the chat.
9. `RULES.md` is readable from the **main checkout**. Unreadable ⇒ refuse (R1-15 is «в обов'язковому
   порядку»; C8-A5 notes the failure branch was undefined, and *refuse* is the fail-closed side).
10. The worktree base ref exists, and every env var and service named in `lane.requires` is present (Д4 [433]).
11. `probe` exists when `process.kind = engine`.
12. List residue from a previous run as `orphans_from: <run-id>` with one exact command per item **for the
    owner to run**. Never reclaim it: FIELD-NOTES §11.11 records ~150 orphaned Docker volume pairs, and Д3
    plus R1-16 together define a set nobody may clean.

Demo: run preflight against a deliberately broken config four ways — two roles on one account, a threshold on
a vanished bucket, a notification channel that answers `getMe` but cannot post, an `RULES.md` that is absent.
Each refuses at the point of the break with a named sentence and exit **70**, and nothing is created.

Proves: cross-cutting requirement 5 («verify before you run») as a single gate, and the difference between
refusing at 22:00 and degrading at 03:00 — which is the whole of `JUDGE-survival`'s case against the winner.

---

**WS-6 — The claim, the lane, and the harvest.** *(~2 days)*

Build: `orc-lane.sh` and the claim/dispatch half of `orc-run.sh`.

**The claim ordering is an invariant with a test (survival graft 33, test `O-44`):**

1. `mkdir lanes/<lane-id>` — the claim. Atomic on POSIX, succeeds exactly once. Fails ⇒ someone has it, move
   on. C3 measured the read-then-write alternative at **27 winners out of 50**, and FIELD-NOTES §10.2 records
   two concurrent adds producing two files under one id in **five rounds out of five**. `mkdir` is one syscall
   and cannot do that.
2. Write `start.json` **before the platform is launched**: `ticket`, `ticket_sha1`, `platform`, `account`,
   `worktree`, `base_sha`, `compose_project`, `session_id` (where the platform lets the client name it),
   `cmd`, `started_at`, `mono_started`.
3. Launch. Append every created resource to `ledger.jsonl` **as it is created**.
4. On exit write `result.json` — **last**. Then `mv lanes/<id> lanes.done/<id>`.

Nothing is written after `result.json`; the directory move is the only commit point. A crash therefore leaves
a **detectable orphan** — a lane dir with `start.json` and no `result.json` — rather than a false claim of
completion.

**The supervisor spawns lanes; a model never does (survival graft 27, test `O-42`).** The judge may *request*
a spawn or a stop; `orc-run.sh` executes it, writes the ledger line and owns the handle. F2 in the corpus
happened because a model-spawned session outlived the model's attention and the process that could have closed
it *"had no remit"*.

**Outcome is never the exit code alone.** ADAPTER-CONTRACT §2.4 invariant 1 records four platforms that exit 0
on failure (Aider on auth failure and rate limit; pi `--mode json` on provider failure; GLM on quota
exhaustion *with* `subtype:"success"`; MiMoCode always). So:

```
outcome = f(exit_code, terminal_event_in_events.norm.ndjson)
```

and when the two disagree the outcome is `unknown`, the lane is `failed` with `reason: "contradictory"`, and
the fact is on the judge's next fact sheet. **Silence is never success.**

**HARVEST — the third answer (cost graft 9).** Between "exit code says 0" and "done" sits a check:
DEFAULT-PROPOSED `harvest_evidence: observed` (of `observed | strict | off`). `observed` withholds `done` only
on **positively observed emptiness** — the lane produced no commit, no file change in the worktree, and no
engine state advance. Such a lane goes to `HARVEST`, which is a fact on the judge's sheet, not a verdict.

Demo: a fake adapter whose `launch.sh` is `sleep 3; echo '{"type":"turn_completed"}'`. Claim, launch, watch
`start.json` appear before the pid exists, `ledger.jsonl` grow, `result.json` arrive last, the directory move.
Then 20 concurrent claims on one ticket id: exactly one wins.

Proves: the recovery story, because the three things on disk that make restart deterministic are created here
in the order that makes them meaningful.

---

**WS-7 — The engine probe, and the oracle that does not believe itself.** *(~1 day)*

Build: `probe/gsd.sh` (~25 lines) and `probe/none.sh`.

The probe prints **one line** and exits 0:

```
state=running  detail=phase 12 plan 3
state=blocked  detail=awaiting user approval
state=done     detail=phase 12 verified
state=failed   detail=plan 3 rejected
```

**VERIFIED on this machine today:** `node ~/.claude/gsd-core/bin/gsd-tools.cjs state --project-dir <p>` exits
0 and prints JSON whose `state_raw` carries `status:`, `current_phase:`, `current_plan:`, `stopped_at:`,
`last_updated:` and `state_head:` (a git SHA). Zero model tokens, no side effects, and it is GSD's own record —
which is R1-06 part 3's rule: reference the chosen process's accounting, keep your own only where there is
none [171]/[189]. DEFAULT-PROPOSED `engine.gsd.probe_calls: [smart-entry, state, windows status]` and
`engine.gsd.exit_contract: v1` (cost graft 4): three calls per lane per tick where six would answer the same
question, and a pinned contract so a GSD upgrade cannot silently change what an exit code means.

**The non-self-attribution clause (survival graft 28), one string comparison, and the cheapest high-value line
in the whole graft set.** `state=done` is accepted only when the phase's verification artifact exists **and
does not self-attribute**: a `NN-VERIFICATION.md` carrying `verified_by: the lane that built the phase` is
rejected and the lane reports `state=blocked detail=verification_self_attributed`. FIELD-NOTES §11.4: phases
14–18 shipped with the engine reporting done and the verification self-attributed, and *"no automated check
caught it; manual review did."*

**One warning belongs in the probe's own file** (VERIFIED, C9-A2): under a host-created worktree GSD returns
`dispatch-isolation: harness-worktree` and runs no git of its own, and `worktree base-check` on a real project
returns `{"shouldDegrade": true, "reason": "head-diverged-from-fork"}`. So a lane whose worktree is cut from a
base GSD does not expect will either silently serialise or fork its sub-worktrees from `origin/HEAD`. The
probe prints that as `detail=`, and preflight refuses a GSD lane whose `base_ref` disagrees with GSD's.

**When there is no probe, the oracle is the process exiting, and `status.json` says so:**
`"completion_oracle": "process_exit"`. C9-A1 is a blocker in the *requirements*, not in the implementation:
R1-13 [344] gives verification to the process, R1-03 [118] makes "no verification at all" a legal process, and
nothing anywhere says how the orchestrator learns that work finished as distinct from the session ending. The
answer here is to name which oracle he got, out loud, and add no check of the orchestrator's own.

Demo: `probe/gsd.sh <a real <work-project> worktree>` prints one line in under a second with no network. Hand-edit
a `NN-VERIFICATION.md` to self-attribute and watch `state=done` become `state=blocked`.

Proves: R1-03 — drive an engine you do not own — and the one place the previous generation shipped five
unverified phases.

---

**WS-8 — `ops.json`: no `ok` without evidence.** *(~1 day)*

Build: `config/ops.json` and the one function in `orclib.sh` that appends a result.

This is the narrow form of `JUDGE-survival`'s highest-ranked graft, priced at cost's level. One row per
mutating operation, in **data**, not in code:

```json
{ "version": 1, "ops": {
  "lane.teardown.process":  { "mutating": true, "idempotency": "by_ref",
                              "admissible": ["process_absent"], "timeout_s": 30 },
  "lane.teardown.compose":  { "mutating": true, "idempotency": "by_ref",
                              "admissible": ["process_absent", "file_digest"], "timeout_s": 120 },
  "ticket.status.write":    { "mutating": true, "idempotency": "by_readback",
                              "admissible": ["file_digest", "board_readback"], "timeout_s": 20 } } }
```

**The rule, and it is a refusal in the one code path every result passes through:** the function that appends
a `step.result` **refuses** `outcome: "ok"` on a mutating op that carries no evidence object of a declared
admissible kind. Adding an op without declaring its evidence is a **load-time error** (test `O-34`).

Evidence kinds in the skeleton: `process_absent` (`kill -0` fails), `file_digest` (sha1 re-read after the
write), `git_ref {ref, before, after, read_back_at}`, `board_readback` (the item re-fetched and the field
compared). The four that reliability adds for the general case are not built now and the gap is accepted.

**The `unsafe` idempotency class (survival graft 30).** A fourth value beside `by_ref`, `by_readback`,
`by_session_id`. On an orphan whose class is `unsafe`, the orchestrator **escalates to the Д6 channel and
holds the lane — never replays.** The worked case is exact: a crash between opening a PR and recording it
produces a second PR, and R1-12 [331] *wants* stacked PRs, so nothing downstream finds a duplicate suspicious.

**The dedup key written into the side effect (cost graft 6).** Every board comment, commit message and branch
name the orchestrator creates carries a trailer: DEFAULT-PROPOSED `dedup.trailer_prefix:
"orchestrator-action:"` followed by the `action_id`. A replayed effect after a crash is then findable by
searching the side effect itself.

**Keep this paragraph verbatim when it is written up**, because it is what keeps the mechanism on the right
side of R1-13: *evidence gating does not verify the work; it verifies that the orchestrator's own operation
happened.* The distinction was never put to the owner, and it is §15 Q7.

Demo: hand-edit `ops.json` to drop `admissible` from one row and watch the load fail. Then make a teardown
call return success while the process is still alive, and watch the appender refuse to write `ok`.

Proves: F6 — the merge that printed `Already up to date` and moved nothing — is unreachable for the three
operations the skeleton performs, and reachable only by adding a row that lies.

---

**WS-9 — The control plane, the stops, and the acknowledgement.** *(~1.5 days)*

Build: `bin/orc-ctl.sh`, `control.json`, `control.applied.ndjson`, `control.ack.json`, the three stop verbs.

`control.json` carries `verb` + `scope` + `apply` as three orthogonal fields, and **his command names are
preserved unchanged** through `stop.verb_map`:

| Command | Entry written | Effect | Applied within |
|---|---|---|---|
| `orchestrator:stop --hard` | `{stop, run, now}` | each lane gets `SIGTERM`; its trap tears down what `ledger.jsonl` lists **for it**, writes `result.json` with `stopped_by: "control"`; then the run tears down and the supervisor exits, releasing the lock | one tick |
| `orchestrator:stop --soft` | `{stop, run, boundary}` | `running` → `draining`. Dispatch stops, lanes run to completion | one tick |
| `orchestrator:stop --custom <ref>` | `{custom, run, custom, ref}` | executable ⇒ run it under `custom.timeout_s` with `ORCH_RUN` exported; text ⇒ hand it to the judge to translate into zero or more entries from the allowed vocabulary, and **untranslatable text produces a journal line, a notification and no action** | one tick |

**None of them signals a process.** The file is the actuation channel and the tick is the clock — that is
Д12's whole mechanism [195]/[520].

**Write protocol** (every writer, including a hand edit through the command): take `orc-lock.py control.lock`,
re-read under the lock, append the entry, write a sibling temp file in the same directory, `rename()` over the
destination, release. A reader is never blocked and never sees half a file.

**Read protocol:** `stat` each tick; on `(mtime,size)` change, parse. A parse failure **keeps the last good
entries, applies nothing new, and sets `status.json.control_error`** with the error and the file's mtime — it
never takes the run down. Every applied entry moves to `control.applied.ndjson` with `applied_at` and is
removed from `entries`; **an entry is applied exactly once, by id**, which is what stops the re-fire class
behind the 85-minute loop.

**`control.ack.json` (graft 5), and it is the half the previous generation was missing.** After each control
read the supervisor writes:

```json
{ "read_at": "...", "mono": 918233, "doc_sha256": "...", "epoch": 3,
  "applied": ["c-0012"], "deferred": [{"key":"roles.executor.account","until":"next_launch"}],
  "rejected": [{"key":"process.kind","reason":"frozen"}], "parse": "ok" }
```

`orchestrator:stop` and `orchestrator:config set` then **read it back** and report whether the change landed,
was deferred to a boundary, or was refused as frozen. DEFAULT-PROPOSED `stop.ack_timeout_seconds: 90` — one
60-second tick plus margin. The previous generation printed *"applied within 60s"*, which is a promise;
FIELD-NOTES §11.2 records two real operator instructions recorded as delivered and never executed.

**Mid-run change, three classes** (`ARCH-minimal` §8.2, now recorded per key in `defaults.json`):
**Live** (`concurrency`, thresholds, `judge.*`, `notify.*`, `when_only_blocked`, `questions.*`) next tick;
**Boundary** (`roles.*.account`, `roles.*.model`, `process.*`, `context.*`, `red_lines.*`) at the next lane
launch; **Frozen** (project root, `process.kind`, `tickets.source`, run id) reported and never applied.
The Boundary class is a platform fact, not a preference: ADAPTER-CONTRACT §3 F records that changing a running
session's account is **impossible on all fifteen platforms**, and FIELD-NOTES §8 measured the same. An
`apply: now` account change is therefore a stop + relaunch + reseed, and the command says so **before** it
writes the entry.

Demo: with a lane live, type `orchestrator:stop --soft` in a second terminal. Within 90 seconds
`control.ack.json` lists it in `applied`, `status.json.phase` is `draining`, and no new lane is dispatched
while the live one finishes. Then `config set process.kind steps` and watch it arrive in `rejected` as
`frozen`.

Proves: Д12 and Д7 end to end, with the acknowledgement that closes the loop back to him.

---

**WS-10 — Teardown, the terminal condition, and the clean stop.** *(~1.5 days)*

Build: the teardown walker and the terminal check.

**Terminal condition**, checked every tick: **no live lanes** AND **no claimable ready ticket** AND (no
human-blocked items OR `when_only_blocked: finish`). `LANDSCAPE.md` §5 records that this — *run a queue
unattended for hours, stop cleanly when it empties, and kill only what you started* — is **still unowned in
the whole field**: every multi-ticket tool surveyed returns zero hits for
`drainAndExit | exitWhenIdle | shutdownWhenEmpty | queueEmptyExit`. It is nine lines here because the queue and
the lane set are both directories.

**Teardown walks `ledger.jsonl` in reverse, stops each entry, and asserts it by observation:**

| kind | stop | assert |
|---|---|---|
| `process` | `SIGTERM`, then `SIGKILL` after `grace_s` | `kill -0` fails |
| `compose` | `docker compose -p <recorded name> down` | `docker ps -q -f label=com.docker.compose.project=<name>` is empty |
| `worktree` | `git worktree remove`, or leave, per config | the path is gone |
| `session` | the adapter's stop | the adapter reports gone |

**Two rules, both from the record, and both enforced by a test.**

- **Every identifier comes from `ledger.jsonl`, never from the environment (survival graft 8b, test `O-41`).**
  FIELD-NOTES §11.5, VERIFIED: the owner's default Docker stack was destroyed by a `docker compose down -v`
  with no `COMPOSE_PROJECT_NAME` exported, so the command resolved to the **default** project; the actor was
  never identified, and a session had refused that exact action as owner-only two minutes earlier. §12.4
  establishes the general case: detached scripts inherit no environment at all. A lint on the three verbs
  would not have caught this. A lint on teardown arguments sourced from the environment does.
- **Assert by observation, not by the command's word.** ADAPTER-CONTRACT §2.4 invariant 10 records
  `cursor-agent worker kill` reporting success and leaving the process at 100 % CPU.

Anything that fails to stop is listed in `report.md` and in `status.json`, never swallowed. Residue from a
*previous* run is **not touched** — it is listed with one exact command per item for the owner to run.

DEFAULT-PROPOSED `worktree.remove_on_done: false`. **Rationale:** removing a tree with uncommitted work is
irreversible; preflight lists leftovers instead.

Demo: start a run whose fake lane creates a compose project and a worktree. Let the queue drain. Watch
teardown emit `docker compose -p <the ledger's name> down` **even with `COMPOSE_PROJECT_NAME` set to something
else in the environment**, assert both, write `report.md`, deregister, release the lock, exit **0**.

Proves: Д3 [430] — «щоби не залишати хвостів» — and the one incident that destroyed the owner's own work.

---

**WS-11 — The judge, the trip watermark, and the fact sheet.** *(~2 days)*

Build: `bin/orc-judge.sh` and the fact-sheet renderer.

One predicate in the skeleton: **`lane-silent`** — alive, event file has not grown for
`liveness.silence_minutes`, and the last normalized event is not `waiting_on_human`. DEFAULT-PROPOSED
`liveness.silence_minutes: 20` — the previous `run.stall_minutes` (VERIFIED) — with the difference that
**nothing is nudged.** A silent lane becomes an item on a fact sheet.

**Three signals, all free, all from processes and files the supervisor owns:** process identity
(`kill -0 <pid>` **and** `ps -o lstart= -p <pid>` matching `start.json` — a pid alone is recyclable);
event-file growth (which moves *during* a turn, the thing a heartbeat cannot do — FIELD-NOTES §1.5 records a
validator running a 14-minute suite that heartbeats not at all, and the watch nudging six healthy sessions);
and the engine probe.

**Plus G2b, which is two lines and the cheapest coverage in the judgement set.** The renderer also prints
`Δpct/hour` over the last three ticks and **the top repeated tool call in the last N events**, with
DEFAULT-PROPOSED `ctx_refill_alarm: 20` (%/h) and `facts.repeat_window_events: 200`. This is the one signal
that would have caught `w-phase-19`, which issued **3,466 of its 3,626 Bash calls as the literal command
`echo idle`**, added 445k tokens (77 % of all context growth in that window), reached 91 % — and read
*healthy* against every one of the other three signals.

The fact sheet, per open item:

```
ITEM lane-silent  lane=t-118 ticket=118
  process: alive pid=40977 start=Fri Sep 19 22:41:03 2026 (matches)
  events:  last grew 00:24:11 ago; 1,412 events; last 5 normalized:
           tool_call(Bash) x4 "echo idle"   turn_started   tool_call(Bash) "echo idle"
  repeats: top tool call in last 200 events: Bash "echo idle" x 187   <-- G2b
  context: 41% raw (measured, 22s old); +26 pct/hour over the last 3 ticks  <-- G2b, alarm at 20
  engine:  state=running detail="phase 12 plan 3" (22s old, gsd probe)
  history: 0 prior reseeds; 0 prior failures on this ticket; claimed 02:11 ago
  rules consulted: liveness.silence(20m) matched; no configured rule resolves this
  allowed verdicts: wait | reseed | stop | escalate
```

One model call per tick at most, all open items batched, **skipped entirely on a tick where nothing is open**,
which is most ticks. Output is one JSON object per item. An unparseable or timed-out response is `defer` — do
nothing this tick. **Waiting is the fail-safe everywhere**, because the alternative builds a loop for itself: a
validator restarted at minute 12 of a 14-minute suite stalls again at minute 12.

**The trip watermark (grafts 1 and 2), which is four lines and answers a different question than a budget
does.** Before the wake, create `trips/<sha1(predicate, subject, run_epoch, armed_at)>.json` with
`set -o noclobber`. A trip already present does not re-fire. A ceiling answers *how much*; a watermark answers
*again?* — and re-firing on its own effect is the mechanism of the 85-minute loop, not its volume.
DEFAULT-PROPOSED `judge.max_calls_per_tick: 1`, `judge.max_calls_per_hour: 12` (cost lowered it from
`ARCH-minimal`'s 30), and `judge.on_budget_exhausted: notify` + `status.json.blocked_on`, **keep ticking** —
a budget that silently stops the only thing that judges is worse than the loop it prevents.

Demo: a fixture lane that goes silent. One fact sheet is rendered, one model call is made, one verdict lands in
`decisions.ndjson` with the sha1 of the fact sheet it saw, and one file appears under `trips/`. Tick again:
**no second call**, because the trip is present. Delete the trip file: it fires once more.

Proves: the central bet — bash renders the facts, a model judges only what bash rendered — and the bound that
keeps it from spending the night.

---

**WS-12 — The report, the scorecard, the doctor, and the first real night.** *(~1.5 days)*

Build: `bin/orc-report.sh`, `bin/orc-doctor.sh`, and then run the thing.

`report.md`, written once at finish: what was claimed, what completed, each lane's outcome **and its completion
oracle**, every judge verdict with its reason, every resource torn down and every one that resisted, the quota
position at start and end, `plan.json`'s `weakened[]` and `denied[]`, and the open questions still in the Д6
channel.

**The detector scorecard (cost graft 11), and the naming matters.** Every predicate is listed with how many
times it was evaluated and how many times it fired. DEFAULT-PROPOSED `report.scorecard: true` and
`report.mark_unfired_as: unproven` — **never `clean`**. A probe that can never succeed and never complains is
the shape of FIELD-NOTES §11.7, where the limiter returned `UNREADABLE` on every call for days while nothing
reported anything wrong. Reading zero firings as health is how that survives a review.

**The doctor** (`ARCH-minimal` §10.3 plus survival graft 23), a ~60-line script on a `launchd`
`StartInterval`, running under a **different account** as R1-10 [246] requires. It does three things:

1. **Try the lock.** Acquired ⇒ the supervisor is dead, provably, with no timeout and no heuristic ⇒ relaunch
   and notify, exit **10**. Refused ⇒ alive, exit **0**, silent.
2. If alive: compare `journal.ndjson`'s byte size against the value recorded on the last visit. Not grown ⇒
   alive but not ticking ⇒ write `{stop, run, now}` and notify, exit **12**. *This is the only mechanism in
   any of the four designs that acts on a wedged-but-alive holder, and it costs one `stat` and one integer.*
3. If alive and journalling: compare `status.json.queue.done_this_run` across two visits. Unchanged ⇒
   **notify only, never kill.** Slow and stuck are not distinguishable from outside.

DEFAULT-PROPOSED `doctor.enabled: false`, `doctor.interval_hours: 2`. Off because it needs a separate account, if the user
configures one; two hours because a four-hour window swallows an 85-minute loop whole.

Also here: `caffeinate -i` bound to the **supervisor's own pid**, not to a watcher's — the previous generation
bound it to the watch loop, so when the watch died the machine slept (INFERRED from the plugin structure).

**Then run the first real night**, against the checklist in §11.1, and write what happened into
`docs/FIELD-NOTES.md`'s successor — a new, conclusion-free record for this generation, at
`plugins/orchestrator/docs/FIELD-NOTES.md`. The previous one earned its keep; this one starts empty and earns
its own.

### 11.3 The schedule, and the honest caveat

INFERRED: **WS-0 to WS-12 is ~18 engineer-days** for one person who knows this repository, against
`JUDGE-cost`'s ~10–15-day estimate for the same core plus grafts. My number is higher because it includes the
mutation gate, the two verify paths and the first real night. `JUDGE-cost` §9.1 warns that its own estimates
may be uniformly low because the previous generation was *smaller* than three of the four designs while being
demonstrably insufficient. Treat the **order** as the deliverable and the **dates** as an estimate.

**The first demonstrable end-to-end run is at WS-10**, not WS-12: at that point a ticket goes in, a lane runs,
the queue drains, teardown asserts, and the process exits 0. WS-11 and WS-12 add the judge and the watchdog,
both of which the run works without — badly, and only for one night.

---

## 12. The defaults register

**This table is the contract.** Nothing outside it may invent a default at run time (test `O-31`). Every row
carries `scope` (the highest band at which setting it is meaningful), `apply` (`live` / `boundary` / `frozen`),
and whether it is **DEFAULT-PROPOSED** — meaning the owner never stated it. `config show` prints the proposed
ones with a marker so he can audit every invented number in one screen.

`S` marks a key the walking skeleton actually reads; the rest ship with a default and are inert until the
feature lands.

### 12.1 Run and repo shape

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `tick.interval_seconds` | `60` | run | live | S | A tick cheap enough to run all night with no model in it; one-minute worst-case stop latency |
| `run.mode` | `controlled` | run | boundary | S | He named three values [075] and no default. `ask` cannot be the default: a 04:00 restart has nobody to ask |
| `concurrency.max_lanes` | `2` | project | live | S | Two lanes ran cleanly twice in the record; two concurrent image builds OOM-killed his own container. Machine resources are deferred by him [160] |
| `limits.max_concurrent_builds` | `1` | project | live | | Serialises only steps a lane declares `heavy: true`, so the one real resource incident is closed without losing the parallelism that worked |
| `orchestrator.home` | `$HOME/.orchestrator` | user | frozen | S | Run state a profile switch cannot move, so a doctor on a second account can find the run (§4.2) |
| `config.user_band_home_fallback` | `true` | user | frozen | S | Under a profile switcher, snf slots 3 and 4 resolve to files that do not exist and the user band is silently empty (§4.3, VERIFIED) |

### 12.2 Work intake

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `tickets.source` | `local` | project | frozen | S | The skeleton has no board; local is the only source proven end to end |
| `tickets.ready_requires` | `["Outcome","Acceptance","Scope"]` | project | live | S | A one-line ticket eating four hours. Measured clean over 327 tickets |
| `tickets.max_claims_per_run` | `0` (unbounded) | run | live | S | His behaviour: Д2 is unconditional pickup. A cap is a brake he did not ask for |
| `tickets.notify_on_queue_growth` | `50` | project | live | | The 236→327 overnight queue growth that needed a human to brake it. A notification is not a brake; it is the signal he acted on |
| `board.writeback` | `true` for a board source, **`false`** for the local registry | project | boundary | S | The tool's own log inside a ticket body firing its own change detector |
| `watch.tier0_interval` | every tick | run | live | | Paying a model to read an unchanged ticket. A `stat` or a 304 is free |
| `watch.scout_model` | the cheapest model the pinned provider offers | user | boundary | | Д8 [466] made a key rather than an instinct |
| `watch.scout_input` | `diff_only` | run | live | | Sending two full bodies where a diff answers the question |

### 12.3 Capacity

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `capacity.soft_pct` | `80` | user | live | S | **His own number** [171]. Not proposed — stated |
| `capacity.hard_pct` | `95` | user | live | S | He used 80 for *both* soft and hard in one breath, which cannot both hold |
| `capacity.on_unknown` | `hold_dispatch` | user | live | S | The shipped `proceed`, which made the limiter inert for days |
| `capacity.unknown_grace_minutes` | `30` | user | live | S | `hold_dispatch` silently idling a whole night on one 429 |
| `capacity.cache_seconds` | `900` | user | live | S | A measured one-call `rate_limit_error` with four standing pollers on this machine |
| `capacity.reserve_pct` | `0`, **and preflight prints the question** | user | live | S | Inventing a reserve for an account he also works in. The question was dropped by the interviewer (§15 Q4) |
| `capacity.credit_ceiling` | `null` = **refuse to dispatch to a credit lane until a ceiling is set** | user | boundary | | "Wait for the reset" waits forever on a credit platform |
| `capacity.margin_s` | `90` | user | live | S | Resuming at the exact reset second and being refused |

### 12.4 Context and compaction

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `context.basis` | `raw_window` (**required**, of `raw_window \| usable_after_reserve \| statusline`) | user | boundary | S | Two percentages ~13 points apart on this machine; a threshold is meaningless without its scale |
| `context.raw_pct_threshold` | `75`, **per role** | user | boundary | S | Refill rates differing 13x by role; the orchestrator acting before the platform pre-empts it |
| `context.mode` | `soft`, `context.fallback: reseed` | user | boundary | S | Hard mode is not implementable on four platforms |
| `context.post_compact_prompt` | the red-line re-injection; `null` disables | user | boundary | | [204] names this as **his** setting, and all four designs turned it into plugin behaviour |
| `ctx_refill_alarm` | `20` (%/h) | run | live | S | The lane that is alive, busy, spending money and producing nothing |
| `facts.repeat_window_events` | `200` | run | live | S | The same tool call repeated thousands of times reading as work |

### 12.5 Liveness, judgement, failure

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `liveness.silence_minutes` | `20` | run | live | S | Long enough not to fire on a 14-minute test suite |
| `judge.mode` | `oneshot` (of `oneshot \| resident`) | user | boundary | S | Keeps the central bet; restores the choice [204] gives him as a switch rather than a rebuild |
| `judge.model` | the `roles.watcher` pin | user | boundary | S | His cheap-model instinct, Д8 [466] |
| `judge.timeout_s` | `120` | run | live | S | A hung model call holding a tick |
| `judge.max_calls_per_tick` | `1` | run | live | S | More than one question per tick is a conversation, and the judge holds no state |
| `judge.max_calls_per_hour` | `12` | run | live | S | A judge in a disagreement loop spending the night |
| `judge.trip_scope` | `(item, subject, run_epoch)`, `O_EXCL` before the wake | run | live | S | A detector re-firing on its own effect |
| `judge.on_budget_exhausted` | `notify` + `blocked_on`, keep ticking | run | live | S | A budget that silently stops the only thing that judges |
| `judge.on_unparseable` | `defer` | run | live | S | A malformed verdict acting. Waiting is always the fail-safe |
| `failures.repeat_threshold` | `3` | project | live | S | **His number, exactly** [442] |
| `failures.action` | `notify_and_stop` | project | live | S | He offered notify+stop or just stop [442]; the noisier one is safer at 03:00 |
| `sentinel.interval_hours` | `0` (off) | user | boundary | | Off because it needs a separate account, if the user configures one. It is the only judgement in the set not derived from a predicate somebody wrote in advance, and it is the thing that catches a run that is alive and useless |
| `sleep.gap_seconds` | `60` | run | live | S | A wake read as a stall; sleep is how the previous run ended |
| `sleep.grace_seconds` | `120` | run | live | S | Every liveness reading going stale at the same instant on wake |

### 12.6 Execution, engine, delivery

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `process.kind` | `engine` | project | frozen | S | R1-03's «або або» [118] |
| `engine.id` | `gsd` | project | frozen | S | The engine he names most often |
| `engine.gsd.probe_calls` | `[smart-entry, state, windows status]` | project | boundary | S | Six subprocess calls per lane per tick where three answer |
| `engine.gsd.exit_contract` | `v1` | project | boundary | S | A GSD upgrade silently changing what an exit code means |
| `harvest_evidence` | `observed` (of `observed \| strict \| off`) | run | live | S | A lane that exits 0 having produced nothing taking the done path |
| `worktree.enabled` | `true` | project | boundary | S | Д4's «абсолютно все» [433] |
| `worktree.base_ref` | the repo's default branch | project | boundary | S | Д4 [433] |
| `worktree.remove_on_done` | `false` | project | boundary | S | Removing a tree with uncommitted work |
| `session.permissions` | `inherit` | user | boundary | S | The shipped `bypass` default and its bypass-on-unknown fallback. R1-15 [357] taken literally |
| `trunk.policy` | `pr_only` | project | boundary | | On his own repos no machine source states the rule (`rulesets` → `[]`, `branches/main/protection` → 404) while `CLAUDE.md` says PR-only |
| `delivery.assert_landed` | `true` | project | live | | A merge that prints `Already up to date` and moves nothing |
| `stacked_prs` | `false` | project | boundary | | `--update-refs` needs git >= 2.38; **this machine has 2.33.0** (VERIFIED) |
| `dedup.trailer_prefix` | `orchestrator-action:` | run | live | S | A replayed board comment or commit after a crash |

### 12.7 Platform and adapter

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `platform.default_adapter` | `claude` | user | boundary | S | The first night depending on a dependency four days into its current major |
| `adapter.verify_max_age_hours` | `0` (verify at every run start) | user | boundary | S | An adapter that reports `native` and degrades at 03:00; a run that starts on one flag surface and finishes on another |
| `negotiate.on_unknown` | `impossible` | user | boundary | S | A new requirement passing silently on every adapter written before it |
| `negotiate.on_undocumented` | `probe_then_impossible` | user | boundary | S | Telling him a platform "declares no X" when the resolver failed |
| `acpx.version` | `0.17.0` | user | boundary | | 40 `### Breaking` sections in 44 releases |
| `acpx.on_version_drift` | `refuse` | user | boundary | | An unpinned session layer in an overnight run |
| `attach.enabled` | `false` | project | boundary | | Headless-first. Takeover of a running headless lane is a handoff and costs one restart (tension T-5) |

### 12.8 People, channels, output

| Key | DEFAULT-PROPOSED | scope | apply | S | Protects against |
|---|---|---|---|---|---|
| `questions.channel` | unset → preflight asks once | project | boundary | S | Д6 [449] says the configurator should ask |
| `questions.answer` | `when_native` | user | boundary | S | Answering by keystroke with no acknowledgement. The field is split and refusing is the cheap side |
| `when_only_blocked` | `wait`, `wait_max_minutes: 0` | run | live | S | **His own recommendation** [455] |
| `notify.channel` | `terminal` | user | live | S | `none` + wait-forever + silence = an indefinite block nobody is told about |
| `notify.events` | `["run_stopped","quota_hard","capacity_unknown_grace","repeated_failure","only_blocked_work_left","board_sync_degraded","doctor_relaunched"]` | user | live | S | R1-17's substantive half was never answered; preflight prints the list with an invitation to cut it (§15 Q6) |
| `red_lines.path` | `<project>/.orchestrator/RULES.md`, read from the **main checkout** | project | boundary | S | The worktree fork that hid an owner-facing question for an hour |
| `red_lines.apply` | `next_launch` | project | boundary | S | A mid-run edit reaching a running lane requires a reseed; quiet by default, with `now` available |
| `report.scorecard` | `true` | run | live | S | A probe that can never succeed and never complains |
| `report.mark_unfired_as` | `unproven` (never `clean`) | run | live | S | Reading zero firings as health |
| `custom.timeout_s` | `120` | run | live | S | A user's custom stop script holding the tick for ever |
| `stop.ack_timeout_seconds` | `90` | run | live | S | An owner believing a stop was applied when it was not |
| `stop.verb_map` | `{"stop-hard":{"verb":"stop","scope":"run","apply":"now"}, "stop-soft":{...,"apply":"boundary"}, "stop-custom":{"verb":"custom",...}}` | user | live | S | Д12 is **unratified**; a round-2 change to his vocabulary must be a table edit, not a rewrite |
| `doctor.enabled` | `false` | user | boundary | | It needs a separate account, if the user configures one |
| `doctor.interval_hours` | `2` | user | boundary | | A four-hour window swallows an 85-minute loop whole |
| `recovery.probe_before_judge` | `true` | run | live | S | A model call per orphan on every restart, when restarts are expected |

**Count: 77 keys, of which 58 are read by the walking skeleton and 73 are DEFAULT-PROPOSED.** The four that are
not proposed — `capacity.soft_pct: 80`, `failures.repeat_threshold: 3`, `when_only_blocked: wait`,
`worktree.enabled: true` — are values he stated out loud, and the register records the row anchor for each.

---

## 13. Worked examples

### 13.1 The one ticket the skeleton runs

`<project>/.orchestrator/tickets/001-add-health-endpoint.md`:

```markdown
---
id: 001
status: ready
depends_on: []
---
# Add a health endpoint

## Outcome
`GET /healthz` returns 200 with `{"status":"ok"}` and the commit sha.

## Acceptance
- A request to `/healthz` on a locally started server returns 200 and the two fields.
- A test covering it passes in the existing suite.

## Scope
`src/server/routes/` and its test file. No dependency changes, no config changes.
```

### 13.2 The run directory after a clean night

```
~/.orchestrator/
  locks/3f2a9c…​.lock                       # empty after the supervisor exits; acquirable
  runs/index.tsv                            # one row, state=finished
  runs/<work-project>-20260919-224100Z/
    config.resolved.json  config.run.json  config.sources.json
    plan.json                               # weakened[] empty, denied[] empty
    control.json                            # entries: []  (c-0007 was applied and moved)
    control.applied.ndjson                  # 1 line: the stop-soft, with applied_at
    control.ack.json                        # applied:["c-0007"], deferred:[], rejected:[]
    journal.ndjson                          # 812 lines, every one carrying at + mono
    status.json                             # phase=finished
    decisions.ndjson                        # 1 line: the lane-silent verdict + fact-sheet sha1
    answers.ndjson                          # empty
    ledger.jsonl                            # 3 lines: worktree, process, compose
    trips/9ab1…​.json                        # 1 file: the one lane-silent firing
    capacity/<profile-B>.json
    lanes.done/t-001/
      start.json  events.ndjson  events.norm.ndjson  sessions.ndjson
      stdout.log  stderr.log  result.json
    report.md
```

### 13.3 `status.json` mid-run, read at 03:00 with no model

```json
{ "run_id": "<work-project>-20260919-224100Z",
  "project": "/Users/sasha-marchuk/Work/.../<work-project>",
  "supervisor": { "pid": 40311, "started_at": "2026-09-19T22:41:00Z",
                  "ticks": 312, "last_tick": "2026-09-20T03:52:04Z", "interval_s": 60 },
  "mode": "controlled", "phase": "running",
  "lanes": [ { "id": "t-001", "ticket": "001", "state": "working",
               "pid": 40977, "pid_started": "Fri Sep 19 22:41:03 2026",
               "platform": "claude", "account": "<profile-B>",
               "worktree": "/Users/.../<work-project>-wt/t-001",
               "events_last_grew": "2026-09-20T03:51:41Z",
               "context": { "pct": 41, "basis": "raw_window", "prov": "measured",
                            "age_s": 22, "delta_pct_per_hour": 9 },
               "repeats": { "top_call": "Bash \"npm test\"", "count": 4, "window": 200 },
               "engine": { "state": "running", "detail": "phase 12 plan 3", "age_s": 22 } } ],
  "queue": { "ready": 0, "blocked_by_deps": 0, "blocked_on_human": 0, "done_this_run": 0 },
  "capacity": [ { "account": "<profile-B>", "kind": "window", "bucket": "seven_day",
                  "used_pct": 62, "reset_at": "2026-09-22T09:00:00Z",
                  "read_at": "2026-09-20T03:45:00Z", "age_s": 424, "prov": "measured" } ],
  "blocked_on": [], "control_error": null, "board_sync": "n/a",
  "completion_oracle": "engine_probe:gsd",
  "plan": { "weakened": [], "denied": [] },
  "last_judge": { "at": "2026-09-20T02:14:00Z", "verdict": "wait", "lane": "t-001" } }
```

**There is no `healthy` field, and that is the point.** The previous generation computed `healthy` from an
attention file its own watch loop truncated every cycle, so it would have printed `healthy: true` for all 85
minutes of the loop in which its log read `NO ONE IS BEING TOLD`. A surface that cannot express health cannot
lie about it. `blocked_on` is a list of named facts and the owner reads the list.

Every number carries `age_s` and `prov` (`measured | estimated | unknown`), and **`missing != zero`**: an
absent capacity reading is `kind: "unknown"` with a reason, never `used_pct: 0`.

### 13.4 `plan.json` when a capability is missing

```json
{ "run_id": "<work-project>-20260919-224100Z", "written_at": "2026-09-19T22:41:02Z", "immutable": true,
  "weakened": [ { "lane": "t-001", "owner_item": "R1-08[204]", "requirement": "R1-08.hard-compact",
                  "axis": "context", "from": "native", "to": "reseed",
                  "consequence": "a compaction costs one session restart and the in-flight turn is lost" } ],
  "denied": [] }
```

This is the file that answers, from disk and with no model, the 04:00 question *"is the guaranteed-compaction
thing he asked for still holding on this lane tonight, and if not, what did it become?"*

### 13.5 The migration table `migrate-tickets` prints

```
  id   file                              old status          new status  reason
  001  001-add-health-endpoint.md        harness:ready       ready       -
  002  002-refactor-auth.md              in-progress         ready       re-offered; no record of the old lane
  003  003-fix-typo.md                   harness:ready       draft       missing heading: Acceptance
  004  004-upgrade-node.md               done                done        -
  005  005-investigate-oom.md            needs-review        blocked     -

  5 copied into <project>/.orchestrator/tickets/. Nothing under .harness/ was modified.
  1 arrived as draft. Add the missing heading, then set status: ready.
```

---

## 14. Tensions kept, not resolved

Each is a decision of his that this build implements while something about it stays uncomfortable. None is
quietly substituted. `ARCH-minimal` §14 holds the full set; these are the ones this document adds or sharpens.

| # | Tension | What it costs, exactly |
|---|---|---|
| **T-1** | **«Оркестратор» is bash, not an agent.** He pictured three windows — context watcher, orchestrator, executor — as sessions [036], [195], [204]. Here the roles survive as model+account pins; two of the three are no longer sessions | He cannot open the orchestrator's window and read what it is thinking. He reads `status.json`, `journal.ndjson` and `decisions.ndjson` instead. What it buys: R1-08's hardest case does not arise, because there is no orchestrator context window to compact |
| **T-2** | **A fourth scope exists and it is not a config file.** snf says three levels are the whole set; he requires a per-run scope | The run scope is per-invocation state, gone when the run ends. He cannot persist a run-scope value, and `config show` labels those keys "this run only" |
| **T-3** | **Д12 is unratified and the skeleton needs a stop.** The session ended on it [525] | Built anyway, with his vocabulary in `stop.verb_map` so round 2 changes a table, not a design. If «хард» turns out to mean something else, the cost is one edit |
| **T-4** | **The board is a mirror.** [149] frames it as the orchestrator's «помічник» — a working surface | The run directory is the working surface; a board write failure sets `board_sync: degraded`, notifies once, and changes nothing about execution. A human reading the board at 09:00 may see a state the run has moved past |
| **T-5** | **Interactive terminals are an exception, not a mode.** R1-11 asks for interactive / headless / hybrid **per platform** [324] | Headless-first. Takeover of a running headless lane is a handoff — stop, relaunch attached, reseed — costing one restart and the in-flight turn. This is the largest single deviation from a decision he confirmed at [328] |
| **T-6** | **R1-08's «гарантовано» holds only via reseed** on Amp, Gemini CLI, Cursor and dsh, where no external compaction trigger exists at all | The context is paid for a second time and ticket→session becomes a lineage rather than a field. That is the whole price, and `plan.json` names it per lane |
| **T-7** | **Two runs against one project are refused** (the lock is keyed on the project) | He cannot run two milestones of one repository concurrently. The alternative is two runs on one board, both claiming, both merging |
| **T-8** | **Run state is at `~/.orchestrator/`, not `~/.claude/orchestrator/`** — a departure from this repo's own convention | A user looking for it where every other plugin here keeps its state will not find it. The reason is R1-10 [246]: under a profile switcher, `~/.claude` is a different tree per profile, and a doctor on a second account could not find the run it is checking (§4.2, §15 Q9) |
| **T-9** | **`config.user_band_home_fallback` adds a seventh read path** to a scheme snf states has exactly six | A deviation from Д1. Without it, the user band is empty under every switcher profile on this machine (VERIFIED), which is indistinguishable from "he configured nothing" (§4.3, §15 Q1) |
| **T-10** | **Evidence gating verifies the orchestrator's operation, not the work** | R1-13 [344] gives verification to the process and forbids the orchestrator adding checks of its own. `ops.json` stays on the right side of that line by design, and the distinction was never put to him (§15 Q7) |
| **T-11** | **The learning loop survives only as a file.** [062] «якщо це не підходить, то треба вчити» is the only place in the session where feedback changes future behaviour, and it is absent from the analysis entirely | `decisions.ndjson` records every verdict with its fact sheet, and a **hand-maintained** `<project>/.orchestrator/CORRECTIONS.md` is read into the decision basis. The system does not learn by itself, and the deciding party is never allowed to write to the basis it decides on |
| **T-12** | **The fact sheet is the ceiling.** Everything removed from the model moves into bash, and everything bash cannot see the model is never shown | G2b raises the ceiling by two lines and does not remove it. The design's coverage is exactly the list of things someone thought to render. `report.mark_unfired_as: unproven` is the admission of that in the artifact he reads |

### 14.1 What nothing in this build survives

Named because a specification that implies full coverage would be its own quiet failure.

1. **Secrets reaching a place nobody scans.** Two local role passwords printed in clear text into a session
   transcript by Playwright's `--trace on`; *"no automated secret scan covers tool output or transcripts."*
   No line writable in `RULES.md` would have prevented it.
2. **File-level collision with his own editing in the same checkout** (R1-16 case 2). `LANDSCAPE.md` §5
   confirms it is unsolved across the entire field and must be invented. He routed it to a separate agent
   [378], [381], and nothing here invents it.
3. **A lane running `pkill` itself.** BD-1 lints plugin source; it cannot lint what a model types into a shell
   at 03:00. `RULES.md` is the only barrier, and on some platforms there is no sandbox beneath it.
4. **The mutation class.** Every commit gate in the previous generation was found broken by mutation rather
   than by failing. §7.3's nine mutations cover this build's own invariants; nothing covers the ones nobody
   thought to write.

---

## 15. Needs the owner — round 2

Every place I had to invent something he never decided. Each is a plain Ukrainian question, ready to ask, with
what I did in the meantime so he can correct it rather than start from nothing.

**Q1 — Конфіг під перемикачем профілів.** Я перевірив на твоїй машині: `CLAUDE_CONFIG_DIR` вказує на профіль перемикача профілів, і в
жодному з профілів немає теки `shared/` — тобто два з шести конфіг-слотів зараз завжди порожні, а
справжній спільний конфіг лежить у `~/.claude/shared/`. Я зробив так, що оркестратор читає обидва місця і
показує, звідки взялося кожне значення. Це відступ від правила твого маркетплейсу, де слотів рівно шість.
Залишаємо так, чи ти хочеш замість цього перенести `shared/` у кожен профіль?

**Q2 — Де має жити стан запуску.** Я поклав стан не в `~/.claude/orchestrator/`, як у решти твоїх плагінів, а
в `~/.orchestrator/`, бо інакше сторож на другому акаунті (це інший `CLAUDE_CONFIG_DIR`) фізично не знайде
ран, який він перевіряє. Через це стан лежить не там, де ти звик його шукати. Це правильний компроміс, чи ти
хочеш однаковості з рештою плагінів і сторож тоді отримує шлях окремим параметром?

**Q3 — Ім'я плагіна і доля старого.** Я назвав новий плагін `orchestrator` і не змінив у `harness` жодного
файлу: вони живуть поруч, стан у них різний, нічого не перетинається. Ти видаляєш `harness` сам, коли новий
відпрацює нормальну ніч. Так і лишаємо, чи ти хочеш, щоб `harness` одразу став позначений як застарілий?

**Q4 — Запас ліміту.** Питання, яке інтерв'юер тоді загубив: чи можна витрачати ліміт до нуля, чи треба
лишати запас на твою власну роботу? Я поставив `reserve_pct: 0` — тобто запасу немає — і зробив так, що
преflight щоразу друкує це питання, доки ти на нього не відповіси. Яке число?

**Q5 — Що значить «стоп» на цьому тижні.** Ти назвав `stop-hard`, `stop-soft`, `stop-custom`, але сесія
обірвалася до підтвердження. Я реалізував: hard — зупинити зараз, soft — дати поточному завданню
дописатися і нічого нового не брати, custom — прочитати твій файл. Імена команд я лишив твої, а їхнє значення
виніс в окрему таблицю, щоб змінити його було одним рядком. Підтверджуєш ці три значення?

**Q6 — За що будити тебе вночі.** Ти сказав, що сповіщення мають бути, але не сказав, за що саме. Я вибрав сім
подій: ран зупинився, жорсткий ліміт, ліміт неможливо прочитати довше пів години, три однакові падіння,
лишилася тільки заблокована людиною робота, дошка розсинхронилася, сторож перезапустив мертвий ран. Що з
цього прибрати і чого бракує?

**Q7 — Чия це перевірка.** Ти сказав, що перевірку робить сам процес, а оркестратор своїх перевірок не
додає. Я додав одну річ, яка виглядає як перевірка, але нею не є: оркестратор відмовляється записати «успіх»
про **власну** дію (зупинив процес, записав статус), якщо не бачить доказу, що ця дія справді сталася. Роботу
агента він не перевіряє. Це в межах твого правила, чи це вже те, чого ти не хотів?

**Q8 — Перший запуск.** Я описав найменший наскрізний шлях: один тікет, одна доріжка, одна платформа
(Claude Code), один двигун (GSD), локальні тікети, без дошки, до чистої зупинки. Це та перша ніч, яку ти
хочеш побачити, чи для тебе «працює» починається з чогось іншого — наприклад, одразу з двох акаунтів або з
дошки?

**Q9 — Скільки доріжок одночасно.** Я поставив за замовчуванням дві, бо в записі дві доріжки двічі
відпрацювали чисто, і окремо обмежив до однієї ті кроки, які лейн сам позначає як важкі (складання образів),
бо саме два одночасні збирання вбили твій контейнер. Ти казав, що ресурси машини поки не чіпаємо. Це
достатньо обережно?

**Q10 — Що робити з `acpx`.** Є готовий шар для запуску сесій, який знімає цілий клас наших минулих поломок,
але в нього 40 ламких релізів з 44. Я зробив його необов'язковим: за замовчуванням ми запускаємо Claude Code
напряму, а `acpx` — це окрема тека, яку вмикають одним ключем і вимикають за годину. Хочеш, щоб він був
увімкнений одразу, чи лишаємо як є?

**Q11 — Компакт і промпт після нього.** Ти казав, що людина налаштовує, чи відправляється якийсь промпт
одразу після компакту. Жоден з чотирьох варіантів архітектури не зробив з цього твій ключ — усі вшили це в
поведінку. Я повернув це як ключ і поставив за замовчуванням повторне читання файлу з червоними лініями. Це
те, що ти мав на увазі?

**Q12 — Що вважати «контрольованим» і «автономним».** Ти просив принести тобі варіанти, а не вирішувати за
тебе. Пропозиція одна: режим — це політика над однією подією — оркестратор зараз має діяти, і жодне
налаштоване правило не дає відповіді. «Контрольований» кладе цей момент у канал питань і тримає **цей**
тікет, решта йдуть далі. «Автономний» дозволяє судді вирішити і записує рішення разом з фактами, які він
бачив. Другий варіант ще не написаний — потрібен?

---

## 16. Verification log

Everything executed on this machine today, 2026-09-19, that a claim above rests on.

| Claim | Command | Result |
|---|---|---|
| `flock(1)` absent; the Python lock holder is the only primitive | `command -v flock` | nothing |
| `tmux` is present (so the attached path is possible, just not default) | `command -v tmux` | `/usr/local/bin/tmux` |
| Toolchain | `git --version`, `node --version`, `jq --version`, `python3 --version` | `2.33.0`, `v22.18.0`, `jq-1.8.1`, `3.9.6` |
| `stacked_prs: false` is forced, not chosen | git 2.33.0 < 2.38 required by `--update-refs` | VERIFIED |
| `acpx` pinned version exists and is current | `npm view acpx version dist-tags` | `0.17.0`, `latest: 0.17.0` |
| `acpx` is **not** installed here | `command -v acpx` | nothing |
| The config root is a switcher profile in this very session | `echo $CLAUDE_CONFIG_DIR` | `<profile-dir>` |
| several switcher profiles exist | `ls -d ~/.<switcher>/profiles/*/` | several profile dirs |
| **No switcher profile has a `shared/` directory**; each has `identity.json` at its root | `ls ~/.<switcher>/profiles/*/` | VERIFIED — §4.3 |
| The real shared config is outside the config root | `ls ~/.claude/shared/` | `identity.json`, `plugins/`, `tooling.json` |
| The previous generation's size | `wc -l plugins/harness/bin/*.sh` and over all its files | 1,879 lines of bash; 3,960 lines across 36 files |
| The repo runs its plugins from one array | `head -20 tests/run-all.sh` | `PLUGINS=(clickup g-event ultra ultra-analyzer claude-migrate find-call log-time harness ig-dm-export-analyzer interview-handoff)` — 10 entries, `orchestrator` must be added |
| The registration checklist | `CONTRIBUTING.md` | five steps, quoted in §2.2 |
| The status defect being fixed | `plugins/harness/commands/status.md` | routes status through a skill |
| The readiness headings | `plugins/harness/bin/harness-tickets.sh:29-36` | `Outcome` / `Acceptance` / `Scope` |
| The permission default being reversed | `plugins/harness/bin/harness-spawn.sh:32-39` | defaults to `--dangerously-skip-permissions`, falls back to it on an unrecognised value |
| The limiter default being reversed | `plugins/harness/templates/user-config.example.json` | `"on_unreadable": "proceed"` |
| `.harness` state paths | `plugins/harness/bin/hlib.sh:17-102` | `<project>/.harness/`, `CURRENT` pointer with self-healing |
| GSD's probe surface | `node ~/.claude/gsd-core/bin/gsd-tools.cjs state --project-dir <p>` | exit 0, JSON with `status:`, `current_phase:`, `state_head:` (cited from `ARCH-minimal` §6.2, re-checked as a path) |

**Sources read in full for this document:** `JUDGE-cost.md`, `JUDGE-fidelity.md`, `JUDGE-survival.md`,
`ARCH-minimal.md`, `ADOPTION-VERDICT.md` (§3–§5), `LANDSCAPE.md` §5, `ADAPTER-CONTRACT.md` §2 and §5,
`round-1/ANALYSIS-01.md`, `CONTRIBUTING.md`, `tests/run-all.sh`, `.claude-plugin/marketplace.json`,
`plugins/harness/**` (file list, headers and sizes), `plugins/interview-handoff/tests/run.sh`,
snf `requirements/OWNER-DECISIONS.md` §2, §3, §6, §9, §10 and snf `docs/config-levels.md` Parts One and Two.

`ARCH-adapters.md`, `ARCH-operability.md` and `ARCH-reliability.md` were read **through the judges** rather
than in full, because the judges name what to graft and this document's scope is the plugin, not the
architecture. Where a graft's mechanism is described above, the description is the judge's, and the source
design is named so an implementer can open it.
