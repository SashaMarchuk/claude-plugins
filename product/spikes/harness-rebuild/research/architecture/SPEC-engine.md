# SPEC-engine — engine integration without ownership

**Date:** 2026-09-19. **Status:** buildable specification. **Scope:** how the orchestrator drives
GSD, superpowers, another marketplace's tooling, or a user-defined process, **without owning any of
them** (R1-03), and what it is nevertheless allowed to assert about its own actions (R1-13, N2).

**Owner items this document implements:** R1-03 (who owns the process, no mixing), R1-13
(verification belongs to the process), N2 (not only code), R1-06.3 (reference the process's own
accounting), Д4 (worktrees, aligned with the chosen process), R1-12 (reaching the trunk), R1-10
(resumability after the orchestrator dies), Д3 (stop only what it started), Д5 (three identical
failures).

**Out of scope, owned by sibling specs:** the control file and tick protocol, capacity/quota,
context and compaction, platform adapters (`Platform × Provider × Account × Role`), the work source
and board, notifications, stops, and the run/lane state machines. Where this document needs one of
those it names the interface and nothing more. The one file this spec shares with the control plane
is `journal.ndjson`, whose `engine.*` line shapes are defined in §9.4 and nowhere else.

**Evidence tags.** **VERIFIED** — executed on this machine today (2026-09-19) or read in source on
this machine. **CLAIMED** — a document asserts it and I did not re-derive it. **INFERRED** — my
reasoning. Every command in §6.2 and §10.3 was run today; the appendix lists them for re-checking.

**Defaults.** The owner stated almost none of the settings below. Every value this document proposes
is marked **DEFAULT-PROPOSED** with a one-line rationale and appears in the contract table in §17.
**Nothing outside §17 may invent a default at runtime** (the rule is `ARCH-adapters` §17's, adopted
verbatim; a test enforces it, §16.4).

---

## 0. Which design this builds on, and where the judges disagreed

Three judgments were read first, as instructed.

| Judge | Winner | This document follows |
|---|---|---|
| `JUDGE-fidelity` | `ARCH-minimal` (8/10) | yes |
| `JUDGE-cost` | `ARCH-minimal` (9/10) | yes |
| `JUDGE-survival` | `ARCH-operability` (8/10); minimal last (5/10) | its engine-scoped grafts, not its fleet |

**Consensus taken:** two of three judges rank `ARCH-minimal` first, and they are the two axes the
owner himself pressed four separate times — «тут нічого надприроднього не потрібно вигадувати»
[171], «це має бути дуже простий процес» [189], «це має бути надійна річ, дуже проста» [300], «я не
хочу якихось детерміністського варіанту … дуже складний оверінжиринг, але дуже якісь простий та
надійний варіант» [370] (all four VERIFIED in `TRANSCRIPT-01.md`). So the skeleton here is minimal's:
**the engine adapter is data, not code; the observation path costs zero model tokens; the tick loop
is `bash` + `jq`.**

**Where the judges disagree, and which I followed.**

1. **Completion detection.** `JUDGE-survival` ranks minimal last partly because it computes
   `outcome = f(exit_code, terminal_event)` and cannot see "agreement that is wrong" — a lane that
   exits 0, emits `turn_completed`, and produced nothing. Cost G8 and survival's reading of Sortie
   both say graft the three-valued harvest. **Followed survival.** §8 ships a three-valued oracle
   with `indeterminate` and `engine.on_indeterminate: needs_review`. Cost: one extra engine probe at
   terminal, ~25 lines. It is the asymmetry argument, not a preference: advancing an empty ticket
   costs the owner a morning, withholding costs a tick.
2. **Whether the orchestrator may assert anything at all.** `ARCH-minimal` reads R1-13 broadly and
   adds no merge assertion; `JUDGE-cost` G6, `JUDGE-survival` G1 and `JUDGE-fidelity` all say that
   reading is too broad — R1-13 is about verifying *the work*, not the orchestrator's own git
   operations. **Followed the two judges that rank minimal first**, since both of them say to graft
   it. §11 ships a **closed list of seven self-assertions**, each of which passes three tests, and
   §19.1 records the tension and §20 Q3 puts it to the owner in his own words. This is the single
   largest place where this document adds something he did not decide, and it is flagged three
   times.
3. **Worktree default.** `ARCH-reliability` defaults `worktree.policy: engine`, which
   `JUDGE-fidelity` §5.2 lists as **not defensible as his** — Д4 [433] states the opposite default
   and GSD is the engine he will actually run. **Followed fidelity.** §10 defaults
   `branching.owner: orchestrator`, prices the loss of GSD's intra-phase parallelism out loud, and
   refuses at preflight rather than degrading at 03:00.
4. **Descriptor richness.** `JUDGE-cost` marks `ARCH-adapters` down to 4/10 for 255 contract points
   across fifteen platforms. That verdict is about *platform* adapters. Its **engine** seam (§9.1,
   eight declarative points, only `start` mandatory) is cheap — it is a JSON file per engine and no
   executable — and `JUDGE-cost` G3 independently recommends exactly the GSD surface it names.
   **Followed adapters for the engine seam only**, with the point count and the mandatory set held
   to the minimum in §5.

---

## 1. The decisions this implements, and what grade of evidence each carries

`JUDGE-fidelity` G1 requires this register: nothing whose vocabulary is unratified gets built before
round 2 re-confirms it. Status is read from `extract/corrections.md` §C and the ratified list at its
line 107 (VERIFIED).

| Item | The decision, in one line | Row | Ratified? |
|---|---|---|---|
| R1-03 | One process: an existing one **or** a fully custom one. No mixing. | [118] → [123] «Так, погоджуюсь» | **RATIFIED** (VERIFIED) |
| R1-13 | Verification belongs to the configured process; the orchestrator imposes none. | [344] → [348] «Так, підтверджую» | **RATIFIED** (VERIFIED) |
| N2 | May be used for work that is not code; there may be no tests, and that is okay. | [344] (same answer) | **RATIFIED** via [348] |
| R1-06.3 | Reference the process's own records; keep own only where it has none. | [187]→[189] «Так, правильно» | **RATIFIED** for the narrow form; the config-time research duty [191]/[192] is **UNRATIFIED** |
| Д4 | Worktrees configurable and aligned with the process; default = every task in its own worktree off the main branch. | [433] | **His own words; the restatement [435]/[436] was declared confirmed at [437] without a yes — UNRATIFIED** (VERIFIED) |
| R1-12 | Trunk access is a setting; repo rules bind; stack PRs where git allows. | [331]→[336] «Так, підтверджую» | **RATIFIED** |
| R1-04 readiness | The orchestrator must invent a structure and follow it. | [145]/[146] | His own words; undesigned by his own statement |
| Д5 | Three identical failures → act per configuration. | [442] | Count firm; **«В який момент не знаю»** — the moment is delegated |

**Build-order gate.** §10 (worktrees) and §9.2 (the accounting reference beyond the narrow form) rest
on unratified restatements. They are implemented here so an implementer is not blocked, and they are
listed in §20 as the first two things to re-confirm. Nothing else in this document depends on an
unratified row.

**One hedge kept as a hedge.** [118] names YAML and hedges it in the same breath — «Це може
налаштовуватись з допомогою якогось ямл файлу … Можливо, не так, тут треба буде подумати, як саме»
(VERIFIED). §12 therefore accepts **YAML or JSON** for a custom process and claims neither as his
choice.

---

## 2. The boundary, stated as one rule

> **The orchestrator decides which unit of work, in which place, on which account, and when to stop.
> The engine decides what to do with it, and whether it is done.**

Three corollaries, each of which is enforced somewhere in this document rather than merely stated:

1. **The orchestrator never inspects the work.** It does not read a diff for quality, does not run a
   test suite to form an opinion, does not parse a test summary, does not override a verdict. §16.4
   lints for the absence of the verbs that would let it.
2. **The orchestrator verifies its own actions.** A merge either moved a ref or it did not, on any
   project, with or without tests. The list is closed and is in §11.
3. **The engine's records are read, never written.** The orchestrator never edits `.planning/`,
   never writes into an engine's state file, never patches an engine. Where it needs a signal the
   engine does not publish, it installs one through the engine's own published extension point
   (§6.3) or does without it.

---

## 3. The object model, and the no-mixing invariant

### 3.1 Five objects, four of which belong to other specs

```
Provider  = { base_url, auth_ref, model, small_model, context_window, capacity_model }   # sibling spec
Platform  = { adapter_id, binary, transport, home_env, capabilities{} }                  # sibling spec
Lane      = Platform × Provider × Account × Role                                         # sibling spec
Process   = the thing this spec drives:  kind ∈ { engine, steps }                        # HERE
Engine    = a named, externally-owned Process (gsd, superpowers, feature-dev, …)         # HERE
```

A **unit of work** is what the engine does for one ticket. For GSD that is a phase; for a custom
process it is one pass through the declared steps; for `feature-dev` it is one session. The
orchestrator never subdivides a unit of work it did not define.

### 3.2 Invariant EN-1 — no mixing, checked mechanically

> `process.kind` has exactly one value. A resolved run configuration that sets both `process.engine`
> and `process.steps` is a **preflight refusal**, exit 64, with a message naming both keys and both
> config slots they came from.

That is R1-03's «комбінувати ні, тут або або» [118] as a one-line check
(`ARCH-minimal` §6.1 and `ARCH-adapters` §9.3, same mechanism, adopted).

**The one thing that is not a second process**, stated here so nobody argues about it at 03:00: the
orchestrator's own internal steps — claim, dispatch, observe, compact, deliver, teardown — are not a
process. They are the harness. If they were an engine, R1-03 would forbid the plugin from existing.
(`ARCH-adapters` §9.3, quoted because it is the right sentence.)

### 3.3 Invariant EN-2 — one engine per run, not per lane

> `plan/engine.json` carries exactly one `engine.id` for the whole run. Two lanes in one run never
> run different engines.

INFERRED from [118]: he chose the process at the level of «людина може налаштувати», not per ticket.
A per-ticket engine is a mixing mechanism wearing a scheduler's clothes. **DEFAULT-PROPOSED:**
`process.per_ticket_override: false` — refuse a ticket that names an engine other than the run's;
`true` would reopen EN-1 through the back door. See §20 Q1.

---

## 4. Where an engine lives, and how it is discovered

### 4.1 Paths

An **engine adapter is one directory** containing a descriptor and, optionally, a prose fragment.
**It contains no executable.** A new engine is a JSON file, not a code change — which is the
concrete meaning of agnosticism under `<baseline-marketplace>` OWNER-DECISIONS 2.1.

```
<engine-dir>/
  engine.json          required — the descriptor (§5)
  engine.md            optional — prose rendered into the start prompt, ≤ 8 KiB
  fixtures/            optional — recorded outputs for `orchestrator:engine verify` (§16.3)
```

**Search path, highest priority first.** This mirrors OWNER-DECISIONS 4.15 (a person's own files beat
the project's committed files; among a person's own files the project beats the home folder) without
pretending to be one of the six binding config slots — a descriptor is an artefact, not a settings
bag, and §4.3 states plainly where snf's rules do not reach.

| # | Path | Band |
|---|---|---|
| 1 | `./.claude/orchestrator/engines.local/<id>/engine.json` | project, personal (gitignored) |
| 2 | `<config-root>/orchestrator/engines/<id>/engine.json` | user, this machine |
| 3 | `./.claude/orchestrator/engines/<id>/engine.json` | project, committed |
| 4 | `<plugin-root>/engines/<id>/engine.json` | shipped with the plugin |

`<config-root>` is resolved exactly as OWNER-DECISIONS 3.3 requires: from `CLAUDE_CONFIG_DIR` when
set, otherwise `os.homedir()` + `/.claude`, never a literal `~` in a file call.
`<plugin-root>` is the installed plugin directory.

### 4.2 Resolution is whole-file, never a merge

**DEFAULT-PROPOSED:** `engines.resolution: whole_file` — the highest-priority `engine.json` found for
an id is used **entire**; lower ones are ignored. Rationale: a deep-merged descriptor is a
Frankenstein contract nobody wrote or tested, and a half-overridden `completion` block is exactly the
silent failure this plugin exists to stop. The `orchestrator:engine which <id>` verb prints the
resolved path and the three it shadowed.

### 4.3 Where snf's rules do not reach, said out loud

Д1 [416] defers configuration wholesale to his own marketplace, and its rules cover **values**. They
do not cover artefact directories, and OWNER-DECISIONS 3.3 forbids using `~/.claude/plugins/` for
anything of ours. The four paths above are this document's invention, built to the same ranking.
They are in §20 Q2. What *is* ordinary snf config — and therefore lives in the six slots unchanged —
is the selection and the tuning:

```jsonc
// ./.claude/shared/plugins/orchestrator.json   (slot 2) or any of the six slots
{
  "process": {
    "kind": "engine",              // engine | steps
    "engine": { "id": "gsd" },     // when kind = engine
    "on_indeterminate": "needs_review",
    "per_ticket_override": false
  },
  "branching": { "owner": "orchestrator", "base_ref": "auto" }
}
```

### 4.4 Discovery — the algorithm

`orchestrator:engine discover` and preflight both run this. Zero model tokens.

1. Read the resolved configuration (six slots, per OWNER-DECISIONS 4.15). Take `process.kind`.
2. If `process.kind` is absent → **not an error**: `kind` defaults to `engine` and `engine.id`
   defaults to `none` (§17), which means "the unit of work is the platform's own session and nothing
   is declared". Emit `engine.resolved` with `id: "none"` and continue.
3. If both `process.engine` and `process.steps` are set → **exit 64**, EN-1 (§3.2).
4. If `kind = steps` → go to §12.4 (compile the custom process) and skip 5–9.
5. Walk the four paths of §4.1 in order; the first `engine.json` found wins. None found → **exit 66**
   with the four paths printed and the sentence `engine "<id>" is configured but not installed`.
6. Validate the descriptor against §5.3. Any unknown top-level key that does not start with `x-` →
   **exit 64** (OWNER-DECISIONS 4.9's rule, borrowed for this file).
7. Run `identity.cmd` if declared (§6.1). Record `engine.version`. A failure here is **not** fatal:
   record `version: "undocumented"` and continue — a version probe is a nicety, not a capability.
8. Compute the **effective points**: for each of the ten points of §5.2, `declared` if the descriptor
   carries it, `undocumented` if it does not. `undocumented` is never rewritten to `none` (§5.4).
9. Freeze the result into `<run>/plan/engine.json` (§7.2) before any lane starts. The file is
   written once per run and is read-only thereafter.

---

## 5. The descriptor — `engine.json`

### 5.1 A legal descriptor is three lines

```json
{ "id": "feature-dev", "protocol_version": 1,
  "points": { "start": { "kind": "command", "value": "/feature-dev {{ticket.title}}" } } }
```

That is the whole contract for an engine that publishes nothing about itself. **VERIFIED** that this
is not a straw man: `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev/commands/feature-dev.md`
is 125 lines of prose with no state file, no status command, no git and no resumability (read on this
machine today). If the contract cannot express `feature-dev`, it is a GSD-shaped contract wearing a
generic name. **GSD is the outlier, not the norm.**

### 5.2 Ten points, one of them required

| Point | Backs the operation | Required | What the engine declares |
|---|---|---|---|
| `identity` | discover | no | a command printing its own name/version |
| `start` | start a unit of work | **yes** | how to begin one unit of work |
| `step` | observe | no | what a step boundary is and how it is signalled |
| `progress` | observe | no | a command returning machine-readable progress |
| `escalation` | observe | no | how the engine says "a human is needed" |
| `completion` | detect completion | no | how done / failed / needs-human is signalled |
| `records` | resumability, accounting | no | where its own record lives, and the witness anchor |
| `branching` | worktrees | no | who creates branches and worktrees, from which base |
| `verification` | — (read only) | no | whether it verifies, and how to read its verdict |
| `delivery` | reaching the trunk | no | whether it opens PRs or merges |

### 5.3 Field-by-field

```jsonc
{
  "id": "gsd",                     // string, required, matches ^[a-z0-9][a-z0-9_-]{0,31}$
  "name": "Get Shit Done",         // string, optional, display only
  "protocol_version": 1,           // integer, required, this document defines 1
  "runtime": "@opengsd/gsd-core",  // string, optional, the package that must be installed
  "exit_contract": "v1",           // string|null, optional — see §5.5
  "prompt_fragment": "engine.md",  // string|null, optional, path relative to <engine-dir>
  "timeouts": {                    // object, optional; per-kind wall clock, seconds
    "identity": 10, "progress": 15, "completion": 15,
    "escalation": 15, "records": 10, "branching": 15
  },
  "points": { /* §5.6 — each value is a Point object */ },
  "x-anything": { }                // ignored by the loader; anything else is exit 64
}
```

A **Point** is one of three shapes, and the shape is named by `kind`:

```jsonc
// kind = "command" — the orchestrator runs argv and reads stdout
{ "kind": "command",
  "argv": ["gsd-tools", "progress"],     // array of strings; {{…}} templates per §5.7
  "cwd": "{{worktree}}",                 // optional, default {{worktree}}
  "format": "json",                      // json | line | none   (default: none)
  "map": { "percent": "$.percent" },     // optional; JSONPath-lite, see §5.8
  "ok_when": "exit==0",                  // optional predicate on the declared contract, §5.5
  "timeout_s": 15 }                      // optional; falls back to timeouts.<point>

// kind = "invoke" — a prompt handed to a session; the orchestrator runs nothing
{ "kind": "invoke",
  "value": "/gsd:execute-phase {{ticket.ref}}",
  "autonomous": "/gsd:autonomous",       // optional alternative used when run.mode = autonomous
  "expect": ["turn_completed"] }         // optional; normalised platform events that end the unit

// kind = "file" — a path the orchestrator reads, never writes
{ "kind": "file",
  "path": ".planning/STATE.md",
  "format": "frontmatter",               // frontmatter | json | yaml | text
  "anchor": "state_head",                // the witness field, §9.2
  "anchor_kind": "git-sha" }             // git-sha | digest | timestamp | none
```

### 5.4 Four rules taken from GSD's own host-integration protocol

**VERIFIED** in `~/.claude/gsd-core/bin/lib/host-integration.cjs` on this machine:
`PROTOCOL_VERSION = 1`, an `UNDOCUMENTED` constant that *"VALIDATES … but NEVER propagates into
effective axes"*, `SAFE_DEFAULTS` described as *"the most restrictive known value per axis …
degrade-closed, never assume capability"*, and `degradationFor()` which *"NEVER throws"*. Inverted —
the engine declares, the orchestrator negotiates — those become:

1. **Closed vocabulary per field.** An out-of-vocabulary value is not a verdict; it is exit 64 at
   load, never a silently-accepted string at 03:00.
2. **`undocumented` ≠ `none`.** A missing declaration and a declared absence are different facts and
   are reported with different words. GSD's own review note is the argument: telling a user their
   runtime *"declares no executor-isolation primitive"* when the **resolver** failed *"is false"*
   (VERIFIED, `references/dispatch-isolation-gate.md`).
3. **Degrade closed, and say which of the two happened.** §7.3's `weakened[]` array carries both.
4. **A parse that yields nothing is `unknown`, never a value.** A `progress` command returning a 200
   the mapper cannot read does **not** become `0%`. `JUDGE-survival` F5 records the live instance of
   the opposite: a rename rendered `0 % used`, *"which reads as plenty of room."*

### 5.5 The exit contract, and the rule about exit codes

> **Never branch on an engine CLI's exit code except through a contract the descriptor pins.**

**VERIFIED on this machine today**, and this is why the rule exists — the same failing invocation:

```
gsd-tools progress --project-dir /tmp                       → exit 1
gsd-tools progress --project-dir /tmp --exit-contract=v2     → exit 64
```

GSD versions its own exit codes, and an unpinned dependency inside the one place the orchestrator
trusts completely is how a GSD upgrade silently changes what a probe means.
**DEFAULT-PROPOSED:** `engine.gsd.exit_contract: "v1"` — the current default on this machine, pinned
so an upgrade is a visible change rather than a silent one. When `exit_contract` is `null` the
orchestrator **may not** use exit codes for anything but "the process ran"; it must read `format`
output instead. The descriptor's `exit_contract` is the value; the config key
`engine.<id>.exit_contract` overrides it, and the override is recorded in `plan/engine.json` so the
journal says which contract was in force. The key is named per engine id, because an exit contract
belongs to one engine and not to the orchestrator.

`ok_when` accepts exactly three forms and nothing else: `"exit==0"`, `"exit in [0,N,…]"`,
`"json.<field>==<literal>"`. Anything else → exit 64.

### 5.6 The ten points, with their required sub-fields

| Point | Legal `kind` | Required sub-fields | Result the orchestrator derives |
|---|---|---|---|
| `identity` | command | argv | `engine.version` (string or `undocumented`) |
| `start` | invoke, command | value/argv | the prompt or command that begins one unit |
| `step` | hook, event | see §6.3 | a `step.finished` signal, or nothing |
| `progress` | command, file | argv/path + map | `{percent?, position?}`; never guessed |
| `escalation` | command, file | argv/path + map | `needs_human: bool` + `reason` |
| `completion` | command, file | argv/path + `done_when` | `done | not_done | indeterminate` |
| `records` | file (array) | path + anchor | the resumability reference block (§9) |
| `branching` | command (array) | argv per probe | `owns_worktrees`, `base_ref`, `branch_name` |
| `verification` | command, file | argv/path + map | the engine's verdict, read and carried, never judged |
| `delivery` | invoke, command | value/argv | `engine_delivers: bool` + how |

A point whose required sub-field is missing is exit 64 at load. A point that is absent entirely is
`undocumented` and the orchestrator falls back per §7.1.

### 5.7 Template variables

Substituted into `argv`, `cwd`, `value` and `path`. The set is **closed**; an unknown `{{…}}` is exit
64 at load, because a template that silently renders empty is how a lane gets dispatched at the wrong
ticket (FIELD-NOTES §11.8 records a spawn script that `cd`'d into the phase-4 worktree while every
label said phase 5).

| Variable | Type | Source |
|---|---|---|
| `{{ticket.id}}` | string | the work item's id |
| `{{ticket.ref}}` | string | the engine-meaningful reference (a GSD phase number, a file path) |
| `{{ticket.title}}` | string | first line of the work item |
| `{{ticket.body_path}}` | path | a read-only copy of the body in the lane dir |
| `{{worktree}}` | path | the lane's working directory |
| `{{project_root}}` | path | the project root, which may equal `{{worktree}}` |
| `{{base_ref}}` | string | the branch the lane was cut from |
| `{{base_sha}}` | string | the SHA recorded before dispatch (§11 A3) |
| `{{branch}}` | string | the lane's branch name, or `""` when there is no repo |
| `{{lane_id}}` | string | the lane id |
| `{{run_id}}` | string | the run id |

`{{branch}}`, `{{base_ref}}` and `{{base_sha}}` render as `""` on a project with no git repository.
That is legal and expected — N2 [344]. A descriptor that *requires* them declares
`"needs": ["git"]`, and §7.1 step 6 refuses the run rather than rendering empty.

### 5.8 `map` — JSONPath-lite, deliberately tiny

The only supported syntax: `$.a`, `$.a.b`, `$.a[0]`, `$.a[-1]`, and `$.a[?(@.k=='v')]` returning the
first match. No expressions, no functions, no wildcards beyond those. Rationale: this runs in `bash`
with `jq`, and every expression language added here is a place a 03:00 failure hides. An unsupported
expression is exit 64 at load, not a runtime surprise.

---

## 6. The six operations, and the commands behind them

### 6.1 Operation 1 — DISCOVER

Defined as the algorithm in §4.4. Output: `<run>/plan/engine.json` (§7.2), one `engine.resolved`
journal line, exit 0/64/66.

### 6.2 Operation 2 — START a unit of work

```
orch-engine start <lane-dir>
```

1. Read `<run>/plan/engine.json` (frozen; never re-resolve mid-run).
2. Render `points.start`. If `run.mode = autonomous` and `start.autonomous` is declared, use it;
   otherwise use `start.value`. (R1-14's two modes are a sibling spec's; this is the only place the
   engine seam reads the mode.)
3. If `prompt_fragment` is declared, read `<engine-dir>/engine.md`, cap at 8 KiB, and prepend it to
   the rendered prompt under a fenced heading `## Process`. Over the cap → truncate at a line
   boundary and journal `engine.fragment_truncated`. Never fail the lane for this.
4. Prepend the red-line file's contents (R1-15, one text file, mandatory reading for every agent
   [357]). Its path and size cap are the sibling spec's; this seam only guarantees it goes first.
5. Write `<lane>/start.json` **before the platform is launched**, carrying `engine.id`,
   `engine.version`, `exit_contract`, the rendered prompt's sha256, `ticket`, `base_sha`, `branch`,
   `worktree`. (`ARCH-minimal` §4's ordering, kept whole: a crash then leaves a detectable orphan
   rather than a false claim of completion.)
6. Hand the prompt to the platform adapter. **The engine seam never launches a process itself.**

`start` is the only mandatory point precisely because it is the only one with no honest fallback: an
orchestrator that does not know how to begin a unit of work cannot run the engine at all.

### 6.3 Operation 3 — OBSERVE progress

```
orch-engine observe <lane-dir>        # zero model tokens; runs on the tick
```

Numbered, and the order matters because each step is allowed to short-circuit the next:

1. **Tier 0 — did anything change?** If `records` is declared, `stat` every declared path and compare
   `(mtime, size, sha256)` against `<lane>/engine.records.json`. Nothing changed **and** no platform
   event arrived since the last observation → write nothing, spend nothing, return the cached
   `<lane>/engine.state.json` with `stale: true`. (Tiering taken from `ARCH-operability` §6.4 via
   `JUDGE-cost` G2, whose measured spread is ~$14 → ~$0.01 per 8-hour night. Here it applies to
   engine records rather than to ticket bodies, and the model is never in this path at all.)
2. **Run the declared probes**, at most `engine.probe_calls_per_tick` of them
   (**DEFAULT-PROPOSED: 3** — `progress`, `escalation`, `completion`; rationale: three subprocess
   calls per lane per tick is ~30 ms and was measured sufficient for GSD, while `identity` and
   `branching base-check` belong at preflight and dispatch, not on a tick — `JUDGE-cost` G3).
   Each probe: `timeout_s` from §5.3, stdin `/dev/null`, stdout captured, stderr to
   `<lane>/engine.probe.log` (rotated at **DEFAULT-PROPOSED** `engine.probe_log_max_kb: 256`).
3. **Interpret by the pinned contract only** (§5.5). A timeout, a non-`ok_when` exit, or an
   unparseable body → that field is `unknown`. Never zero, never `false`, never `done`.
4. **Derive** `progress.percent` / `progress.position`, `escalation.needs_human` + `reason`. When
   `progress` is `undocumented`, report `progress: unavailable` and **never guess a percentage**.
5. **Write** `<lane>/engine.state.json` atomically (write to `.tmp`, `fsync`, `rename`):

```json
{ "schema": 1, "lane": "L03", "engine": "gsd", "engine_version": "1.14.0",
  "observed_at": "2026-09-19T21:40:11Z", "mono": 918233.114,
  "progress": { "percent": 75, "position": "Phase 7 of 7 · executing", "source": "declared" },
  "escalation": { "needs_human": false, "reason": null, "source": "declared" },
  "completion": { "verdict": "not_done", "source": "declared", "evidence": ["gsd:smart-entry"] },
  "records": [ { "path": ".planning/STATE.md", "anchor": "state_head",
                 "value": "5154f24…", "read_at": "…", "sha256": "…" } ],
  "unknown_fields": [], "probe_errors": [] }
```

6. **Emit at most one journal line** per changed field (§9.4). Unchanged fields emit nothing — that
   is Д8's «нічого назад не поверне» [466] achieved structurally rather than behaviourally.

**What observation is never allowed to do:** write into the engine's files, call a model, fetch the
network beyond a probe the descriptor declares, or convert `unknown` into a value.

**Step boundaries (`points.step`).** Two legal kinds, and both are *the engine's own* extension
mechanism — installing one is not owning the engine:

- `{"kind":"hook","point":"execute:post","emits":"step.finished","install":["gsd_run","loop","render-hooks","execute:post"]}`
  — **VERIFIED**: GSD publishes twelve named loop-hook points on this machine
  (`discuss:pre`, `discuss:post`, `plan:pre`, `plan:post`, `execute:pre`, `execute:wave:pre`,
  `execute:wave:post`, `execute:post`, `verify:pre`, `verify:post`, `ship:pre`, `ship:post`, read
  from `~/.claude/gsd-core/references/loop-hook-dispatch.md` today), and
  `gsd_run loop render-hooks <point> --raw` is its documented consumer surface. A `contribution`
  hook gets the orchestrator a step signal **without patching GSD**.
- `{"kind":"event","emits":"step.finished","when":"turn_completed"}` — the fallback, and the default
  when `step` is `undocumented`: **a step is a turn**. §7.1 records the consequence, which is that
  the sibling spec's `stop-soft` and context-`soft` boundaries become turn-granular.

### 6.4 Operation 4 — DETECT COMPLETION

Specified in full in §8, because it is the hardest thing in this document and the one place two of
the owner's decisions leave a hole (C9-A1).

### 6.5 Operation 5 — READ THE ENGINE'S OWN RECORDS (resumability)

Specified in §9.

### 6.6 Operation 6 — DELEGATE BRANCHING

Specified in §10.

---

## 7. The frozen plan, and what happens when a point is missing

### 7.1 The fallback table — what the orchestrator does with an `undocumented` point

This table **is** the degradation contract. Each row also names which owner item gets weaker, which
is what §7.3 records per run.

| Missing point | The orchestrator… | Owner item weakened |
|---|---|---|
| `identity` | records `engine_version: "undocumented"` in every journal line | R1-06.3 (records name no version) |
| `start` | **cannot run this engine** — exit 64 at preflight | R1-03 |
| `step` | treats a turn as a step | R1-08 soft mode, Д12 `stop-soft` → turn granularity |
| `progress` | reports `progress: unavailable`; never guesses | R1-09 (less to judge on) |
| `escalation` | relies on the platform's `waiting_on_human` event only | R1-09, Д6 |
| `completion` | falls back to §8.3's ladder, ending at `indeterminate` | R1-13's silent half |
| `records` | keeps its own record instead of a reference — R1-06.3's **third** case, which he named: «якщо в процесу немає — вести свої» | R1-06.3 |
| `branching` | assumes the engine owns nothing and takes ownership itself (§10.2) | Д4 |
| `verification` | records `verification: "engine-none"` and **imposes nothing** | R1-13 (honoured, not weakened) |
| `delivery` | takes delivery itself, subject to §11 and the sibling trunk spec | R1-12 |

Step 6 of §4.4 also enforces `needs[]`: a descriptor declaring `"needs": ["git"]` or
`"needs": ["subagents"]` against a lane whose platform capability map cannot supply it is a
**preflight refusal**, not a 03:00 degradation. (`ADAPTER-CONTRACT` §6.6's finding that a
subagent-heavy engine simply will not run on some platforms, applied.)

### 7.2 `<run>/plan/engine.json` — frozen, immutable, readable with no model

```json
{ "schema": 1, "run_id": "20260919-214000", "frozen_at": "2026-09-19T21:40:00Z",
  "process": { "kind": "engine" },
  "engine": { "id": "gsd", "version": "1.14.0", "runtime": "@opengsd/gsd-core",
              "descriptor_path": "…/engines/gsd/engine.json", "descriptor_sha256": "…",
              "exit_contract": "v1", "protocol_version": 1 },
  "points": { "identity": "declared", "start": "declared", "step": "declared",
              "progress": "declared", "escalation": "declared", "completion": "declared",
              "records": "declared", "branching": "declared",
              "verification": "declared", "delivery": "declared" },
  "branching": { "owner": "orchestrator", "base_ref": "main", "engine_setting_applied": "use_worktrees=false" },
  "weakened": [], "denied": [],
  "assertions_enabled": ["A1","A2","A3","A4","A5","A6","A7"] }
```

Written once, `chmod 0444`, never rewritten. A run that needs a different plan is a different run.

### 7.3 `weakened[]` and `denied[]` — naming which of his decisions stopped holding tonight

Taken from `ARCH-adapters` §5.3 via `JUDGE-fidelity` G5 and `JUDGE-survival` G9. Each row:

```json
{ "owner_item": "R1-08.soft-boundary", "point": "step", "reason": "undocumented",
  "from": "engine step boundary", "to": "turn boundary",
  "consequence": "stop-soft may wait up to one whole turn" }
```

`denied[]` carries the same shape for a point whose absence **refuses** the run instead of weakening
it. Both arrays are printed at start and carried into `status.json`, so the answer to *"is the thing
he asked for still holding on this run"* is a file read at any hour with no model in the path.

---

## 8. Detecting completion — the hole two of his decisions leave, and how it is closed

### 8.1 The hole, stated exactly

R1-13 [344] gives **verification** to the process. R1-03 [118] makes *"no verification at all"* a
legal process — «коли перевірка, **чи буде перевірка**». Neither decision says how the orchestrator
learns that a unit of work **finished**, as distinct from **the session ended**. "Done" and
"verified" are two different objects, and the second has an owner while the first does not
(C9-A1, blocker).

The failure is concrete and was demonstrated with a shipped engine: a worker running `feature-dev`
reaches Phase 5, whose text reads literally **"DO NOT START WITHOUT USER APPROVAL"** (VERIFIED in the
file on this machine today), ends its turn and exits 0. A design that treats exit 0 as done marks the
ticket complete and, with the autonomous trunk setting on, opens and merges a PR containing a design
discussion and no implementation.

### 8.2 The resolution: the oracle is the engine's, and it has three values

```
oracle(lane) → done | not_done | indeterminate
```

The orchestrator supplies **no completion criterion of its own**. Where the engine declares one, it
is read. Where the engine declares none, the answer is `indeterminate` — never `done`.

**DEFAULT-PROPOSED:** `process.on_indeterminate: "needs_review"` (values: `needs_review | done | ask`)
— rationale: the two errors are not symmetric. Advancing an empty ticket moves work in a system the
orchestrator does not own, removes it from the queue it does own, and puts it in front of a person;
withholding leaves it where it was, in a queue that is still being watched, with the withholding
recorded. One error costs a morning; the other costs a tick.

### 8.3 The ladder, in order, first answer wins

```
orch-engine oracle <lane-dir>       # called at lane terminal, and only there
```

1. **`points.completion` declared** → run it under the pinned contract. `done_when` is matched
   against the mapped value; a match is `done`, a clean non-match is `not_done`, a timeout or
   unparseable body is **`unknown` → continue to 2** (never `not_done`).
2. **`points.verification` declared** → read the engine's verdict. A verdict that says done is
   subject to §8.4 before it is believed.
3. **`points.records` declared** → if a record's declared `done_marker` predicate holds
   (e.g. a `status:` frontmatter field equal to a declared value), that is `done`.
4. **`points.escalation` says a human is needed** → `not_done`, with `needs_human: true`. This
   outranks a clean exit: an engine asking for a person has not finished.
5. **Platform terminal event and exit code disagree** → `not_done` with `reason: "contradictory"`.
   (`ARCH-minimal`'s rule, kept: silence is never success.)
6. **Nothing above answered** → `indeterminate`.

**HARVEST.** Step 6 is not the end of the lane; it is a lane state. `harvest_evidence`
(**DEFAULT-PROPOSED: `observed`**, values `observed | strict | off`, never a boolean because absence
of evidence is not evidence of absence) controls what the orchestrator does with `indeterminate`:
`observed` withholds `done` only on positively observed emptiness and otherwise routes to
`process.on_indeterminate`; `strict` treats every `indeterminate` as `needs_review`; `off` accepts
the platform's exit code, which is the pre-2026 behaviour and is offered only so the owner can have
it back in one line.

### 8.4 The self-attribution clause — and the tension it carries

> A verdict read at step 2 is **not believed** when the verdict's own record attributes the
> verification to the party that did the work.

Declared in data, never in code, so it stays engine-agnostic:

```json
"completion": {
  "kind": "command", "argv": ["gsd-tools","smart-entry"], "format": "line",
  "done_when": "/100% · complete/",
  "reject_if": [ { "file_glob": ".planning/phases/*/[0-9][0-9]-VERIFICATION.md",
                   "field": "verified_by", "matches": "(?i)the lane that built" } ]
}
```

**Why it is here.** FIELD-NOTES §11.4 (VERIFIED): *"GSD's verify stage was silently skipped for
phases 14 to 18, each `NN-VERIFICATION.md` self-attributing with `verified_by: the lane that built
the phase`… No automated check caught it; manual review did."* One string comparison closes it, and
`JUDGE-survival` G7 calls it the cheapest high-value line in its whole graft list.

**⚠ TENSION with R1-13.** This reads the engine's own record and declines to believe one field of
it. It does not check the work — it checks the **provenance of the verdict** — but the owner was
never asked whether that distinction is his. **DEFAULT-PROPOSED:**
`completion.trust_self_attributed_verdict: false` (i.e. the clause is on). Setting it `true` restores
the literal reading of R1-13 in one line. §20 Q4 puts it to him.

### 8.5 Failure counting (Д5)

"Identical failure" is `(ticket_id, step_id, reason_code)` where `reason_code` comes from the ladder
above, not from a message string. The count is **durable** — it lives in `journal.ndjson`, not in
process memory, so it survives the orchestrator's own death, which is the only case where looping
forever actually happens.

**DEFAULT-PROPOSED:** `failures.identical_threshold: 3` — his number, [442] «Три рази».
**DEFAULT-PROPOSED:** `failures.on_exhausted: "notify_and_stop"` — one of exactly the two actions he
offered («дати знати про це, зупинитись, або просто зупинитись»), and no third. `JUDGE-fidelity` §5.2
names a third option shipped elsewhere as the clearest instance in the set of a decision being
improved on while being described as honoured; this document does not repeat that.
**Recorded as his, not decided here:** *when* the rule fires — «В який момент не знаю» [442] — so the
threshold is counted at lane terminal only, and §20 Q5 asks him.

---

## 9. Reading the engine's own records — resumability and accounting

### 9.1 The rule, in his words

R1-06.3 [187–191], ratified in its narrow form at [189] «Так, правильно»: reference the chosen
process's own records, supplement only what is missing, keep own records **only** when the process
has none — «нічого не треба окремо записувати, а лише записувати оце референс».

### 9.2 What a reference is: a pointer plus a witness

A reference that is only a path is worthless after a crash, because the file has changed since. So
every record reference carries a **witness anchor**:

```json
{ "path": ".planning/STATE.md", "anchor_kind": "git-sha", "anchor": "state_head",
  "value": "5154f24c…", "sha256": "…", "size": 8123, "mtime": "…", "read_at": "…" }
```

The four legal `anchor_kind` values and what each proves:

| `anchor_kind` | Proves | Cost |
|---|---|---|
| `git-sha` | the record names a commit; the graph can be re-checked independently | free |
| `digest` | the file's bytes at read time; detects any later edit | one `sha256` |
| `timestamp` | only that the engine wrote at a moment | nearly nothing |
| `none` | nothing; the reference is a path | nothing |

**DEFAULT-PROPOSED:** `records.min_anchor: "digest"` — a reference with no witness cannot support a
resume decision, and `digest` costs one hash per declared file per tick. `none` is legal and is
reported in `weakened[]`.

**⚠ TENSION, recorded rather than resolved.** A reference points at a **claim**, not at a witness:
the engine's own record of what it did is written by the same agent that did it. The owner's decision
stands — reference, do not duplicate — and this document adds exactly one thing, which is the
smallest hedge against the risk he himself flagged at [189] («Я можу помилятись»): **the
orchestrator's own journal independently records the orchestrator's own operations**, so recovery
reads two records with different authors and can name a disagreement (§9.5). It adds no second
record of the *work*.

### 9.3 Resume — the algorithm

Called on orchestrator restart (R1-10 [300]: "start over" means restart the orchestrator, not redo
the work), once per orphaned lane. Zero model tokens in the common cases; a model is reached only at
step 7.

1. Read `<lane>/start.json`. Absent → this is not a lane; ignore the directory.
2. Read `<lane>/result.json`. Present → the lane finished; nothing to resume.
3. Read `<run>/plan/engine.json`. If `engine.id` or `descriptor_sha256` differs from
   `start.json` → **do not resume**; mark `needs_review` with `reason: "engine_changed"`. A run
   resumed under a different engine is R1-03 violated by accident.
4. Re-run `identity`. Version differs from `start.json` → journal `engine.version_drift` and
   continue; a version change is a fact to record, not a reason to abandon work.
5. For each record in `points.records`: re-read and compare against the stored anchor.
   - anchor unchanged → the engine did nothing since the crash;
   - anchor advanced (a newer git SHA, a changed digest) → the engine **did** work the orchestrator
     never recorded. Journal `engine.record_advanced` with both anchors. This is the one signal that
     distinguishes "the lane died doing nothing" from "the lane died having half-finished".
6. Run `oracle` (§8.3). `done` → close the lane from the engine's record, not from a re-run.
   `not_done` with `needs_human` → route to the questions channel. `not_done` otherwise → the lane is
   resumable.
7. Only what steps 1–6 could not resolve goes to a model, with the fact sheet
   (`JUDGE-cost` G9's rule: *a probe of the world beats a model's reading of a fact sheet about the
   world*). **DEFAULT-PROPOSED:** `recovery.probe_before_judge: true`.

**Resume sources, per R1-07/R1-10 [293], [307], [310].** The orchestrator's own state files are the
default; the engine's records are the second source; platform transcripts and previous sessions are
the third and are the platform adapter's business, configured per platform. This seam owns only the
second. **DEFAULT-PROPOSED:** `records.resume_from: ["orchestrator_state","engine_records"]` —
his stated default plus the reference he ratified; adding `"transcripts"` is one config line and is
the sibling spec's mechanism.

### 9.4 The journal lines this seam owns

Appended to `<run>/journal.ndjson`. One line per fact, never a prose sentence, and **never containing
a string the orchestrator's own detectors match** (`JUDGE-survival` G11: a governor that prints
`/compact` or `rate-limit` into a file its own detectors read gets matched by itself).

```
{"ts":"…","mono":918233.1,"event":"engine.resolved","engine":"gsd","version":"1.14.0","descriptor_sha256":"…","points_declared":10}
{"ts":"…","event":"engine.start","lane":"L03","ticket":"T-17","prompt_sha256":"…","base_sha":"…"}
{"ts":"…","event":"engine.progress","lane":"L03","percent":75,"position":"Phase 7 of 7 · executing"}
{"ts":"…","event":"engine.step","lane":"L03","step":"execute:post","source":"hook"}
{"ts":"…","event":"engine.escalation","lane":"L03","needs_human":true,"reason":"insufficient_spec"}
{"ts":"…","event":"engine.record","lane":"L03","ref":".planning/STATE.md","anchor_kind":"git-sha","anchor":"state_head","value":"5154f24…","read_at":"…"}
{"ts":"…","event":"engine.record_advanced","lane":"L03","ref":".planning/STATE.md","from":"5154f24…","to":"9ab13c0…"}
{"ts":"…","event":"engine.oracle","lane":"L03","verdict":"indeterminate","source":"ladder:6","harvest":"observed"}
{"ts":"…","event":"engine.assertion","lane":"L03","id":"A6","result":"pass","evidence":{"ref":"refs/heads/main","before":"…","after":"…"}}
{"ts":"…","event":"engine.weakened","owner_item":"R1-08.soft-boundary","point":"step","to":"turn boundary"}
```

`mono` is `CLOCK_MONOTONIC` seconds beside the wall clock, so a duration computed across a machine
sleep is not a lie (`JUDGE-survival` G3; sleep is literally how the previous run ended).

### 9.5 Disagreement between the two records

When the engine's record says a unit is done and the orchestrator's journal has no `engine.start`
for it in this run, or vice versa, the observation is journalled as `engine.record_disagreement` and
the lane goes to `needs_review`. The orchestrator **states** the disagreement; it never resolves it
by preferring its own record. That is the line R1-13 draws, kept.

---

## 10. Where the engine owns branching and worktrees — and the orchestrator must not

### 10.1 The collision, verified today rather than remembered

Д4 [433]: «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі … щоби це ворк трі
був з головної гілки», and in the same breath «якщо людина виборне гіт шдан, то там є воркспейс,
**і з цим треба поєднювати**». That last clause is **a task he assigned, not a decision he made**.

**VERIFIED by execution on this machine today**, in a real GSD project
(`/Users/sasha-marchuk/Work/sashko-vps`):

```
gsd-tools dispatch-isolation    → harness-worktree
gsd-tools git base-branch       → main
gsd-tools worktree base-check   → { "shouldDegrade": true, "reason": "head-diverged-from-fork",
                                    "headSha": "c62374ce…", "forkRef": "origin/HEAD",
                                    "forkSha": "72e0b343…",
                                    "message": "… (worktree.baseRef:\"head\" applies only where GSD
                                     itself creates the worktree — the runtime harness does not read
                                     it; #48, #3659.)" }
```

Read GSD's own parenthesis. Under Claude Code the **host** creates and binds the worktree per agent
and *"GSD runs no git"* (VERIFIED, `references/dispatch-isolation-gate.md`); GSD's executor worktrees
fork from `origin/HEAD`; and GSD's own escape hatch `worktree.baseRef: "head"` **is not read by the
host** — GSD says so itself. So an orchestrator that honours Д4, cuts `worktree/T-17` off `main`, and
then invokes `/gsd:execute-phase` inside it gets one of two silent outcomes:

1. GSD sees HEAD ≠ `origin/HEAD`, degrades to sequential, and a six-plan phase that should have run
   four-wide runs one-wide — a throughput loss the owner never chose, at 03:00, with nothing printed;
2. or GSD's sub-worktrees fork from `origin/HEAD` and build on a base that is not the orchestrator's.
   FIELD-NOTES §4.3 is this, observed: GSD computed
   `gsd/phase-23-tooling-the-harness-and-the-pre-commit-checkers` from a roadmap slug, one word off
   the lane branch, and *"left alone `execute-phase` would cut that name fresh from `origin/master`
   and lose the merged master tip."*

And a **third** owner now exists that did not when those notes were written: `claude --worktree`
(**VERIFIED** in `claude --help` today — *"Create a new git worktree for this session"*, with
`--tmux` requiring it, and `claude rm <id>` deleting *"its worktree when that is safe"*).

**Stated plainly, because the brief demands it: the part of Д4 that is impossible as stated is
«з цим треба поєднювати».** There is no configuration today that gives both his uniform
one-worktree-per-task default **and** GSD's intra-phase parallelism. Keeping both would cost a change
inside GSD (making the host's base readable to `worktree.baseRef`), which is not ours to make and
would violate R1-03's ownership boundary. The choice between them is his; this document ships his
stated default and refuses loudly on a mismatch.

### 10.2 One owner, declared once, asserted before every dispatch

`branching.owner` has exactly three legal values.

| `branching.owner` | Who creates the worktree | Engine setting required | Consequence |
|---|---|---|---|
| `orchestrator` **(DEFAULT-PROPOSED)** | `git worktree add -b <branch> <path> <base>` | GSD `workflow.use_worktrees: false` | Д4's stated default holds; the orchestrator has one `base_sha` it can assert; **costs GSD's intra-phase parallelism** |
| `engine` | the engine, through its host | leave GSD's setting alone | keeps the parallelism; the orchestrator creates nothing and **must not assume any base**, so assertion A3 (§11) is disabled and appears in `weakened[]` |
| `none` | nobody; the lane runs in the project root | n/a | the correct value for a non-code project (N2) and for any process with no repository |

**Rationale for the default:** it is his own stated default at [433], and it is the only value under
which the ledger-driven teardown can destroy exactly what this run created (Д3 [430], «щоби не
залишати хвостів»). `JUDGE-fidelity` §5.2 explicitly names the opposite default, shipped elsewhere,
as not defensible as his.

**DEFAULT-PROPOSED:** `branching.base_ref: "auto"` — resolved as: the engine's declared base branch
when `points.branching` publishes one (GSD: `gsd-tools git base-branch` → `main`, VERIFIED), else the
repository's default branch, else refuse. Rationale: `auto` reads a fact rather than hard-coding
`main`, and the repository this plugin lives in uses `main` while the project the field notes came
from used `master`.

### 10.3 The preflight negotiation — numbered, zero tokens, refuses rather than degrades

Run once per run, before any lane starts.

1. If `branching.owner = none` → assert there is no `points.branching` that claims ownership;
   a claim plus `none` is exit 64. Otherwise done.
2. Resolve `base_ref` per §10.2. No repository present → `branching.owner` must be `none`, else
   exit 64 with the sentence `branching.owner=<v> requires a git repository; this project has none`.
3. If `points.branching` is declared, run its probes (for GSD, all three, **VERIFIED** working):
   `dispatch-isolation`, `git base-branch`, `worktree base-check`.
4. **Ownership conflict test.** `branching.owner = orchestrator` **and** the engine reports that it
   creates worktrees → **refuse to start**, exit 65, with this message and no paraphrase:
   `engine "<id>" creates its own worktrees and branching.owner=orchestrator. Set
   branching.owner=engine, or disable the engine's worktrees (<the engine's own setting, quoted from
   the descriptor>). There is no configuration that gives both.`
5. **Base drift test.** `worktree base-check` (or the equivalent declared probe) reports degradation
   → record it in `weakened[]` with `owner_item: "Д4.base-from-main"` and the engine's own message
   verbatim. Whether this refuses or merely records is one key:
   **DEFAULT-PROPOSED** `branching.on_base_drift: "record"` (values `record | refuse`) — rationale:
   drift is normal and recoverable (it resolves as soon as HEAD is pushed), so refusing the run would
   make ordinary work impossible; but it must be visible, because outcome 1 of §10.1 is silent.
6. Apply the engine setting the chosen owner requires, **only through the engine's own documented
   configuration surface**, and record in `plan/engine.json.branching.engine_setting_applied`. If the
   engine publishes no such surface, do not edit its files — record `denied[]` and refuse.
7. Capture nothing yet. `base_sha` is captured per lane at dispatch, not per run (§11 A3).

### 10.4 Per-lane worktree health — «постійно переконуватись» [433]

Four `git` calls plus the declared probes, per lane per tick, no model. This is the second half of Д4
that the first analysis dropped: **«постійно переконуватись»** (continuously, not once at spawn) and
**«запущений стек»** (a running stack, not only environment variables).

1. `git worktree list --porcelain` → the lane's path, HEAD and branch still exist.
2. `git rev-parse HEAD` compared against the recorded `base_sha` lineage (`git merge-base
   --is-ancestor <base_sha> HEAD`) → the lane is still descended from the base it was given.
3. `git status --porcelain=v2 --branch` → `# branch.ab +N -M` and dirtiness.
4. The engine's declared `branching` base probe, at **dispatch only**, not per tick
   (`JUDGE-cost` G3: `worktree base-check` and `runtime-identity` are preflight/dispatch calls).
5. `env`: compare the variables actually exported into the lane's launcher against
   `branching.required_env[]` (**DEFAULT-PROPOSED: `[]`** — an empty list, because inventing required
   variables for a project this plugin has never seen is exactly the overreach N2 forbids).
6. `stack`: run `branching.stack_probe` when declared — an argv the user supplies (an HTTP check, or
   `docker compose ps --format json` scoped to the lane's own project name). **DEFAULT-PROPOSED:**
   `branching.stack_probe: null`. **DEFAULT-PROPOSED:** `branching.on_stack_down: "hold"` (values
   `hold | notify | ignore`) — rationale: holding is reversible and a lane whose stack is down
   produces nothing anyway; killing or restarting someone else's stack is precisely what Д3 and
   R1-16 forbid. FIELD-NOTES §5.1 is the case: the owner's own container was OOM-killed mid-run and
   *"there was no live alert."* §20 Q6 asks him which of the three he wants.

Any teardown command built from any of this obeys the rule that belongs to the boundaries spec and is
repeated here because it is the recorded incident: **every identifier in a teardown command comes
from the ledger line written when the resource was created, never from the environment.** FIELD-NOTES
§11.5: `docker compose down -v` with no `COMPOSE_PROJECT_NAME` exported landed on the **default**
project — the owner's.

---

## 11. What the orchestrator is allowed to assert anyway

### 11.1 The three tests

R1-13 is given and is not reopened. This section sits **next to** it. An assertion is legal only if
it passes all three tests; anything that fails one is forbidden, and adding to the list is the
owner's decision, not an implementer's.

1. **Self-scope.** It is about an action the orchestrator itself performed, or a fact about the
   workspace the orchestrator itself created. The process cannot attest to an action it did not take.
2. **Zero model tokens.** It is a subprocess and a comparison.
3. **N2-safe.** It is equally true on a project with no tests, no build and no repository — either
   because it is a git fact on a run that has git, or because it is skipped entirely when the
   primitive is absent.

### 11.2 The closed list — seven assertions

| id | Assertion | Command | When | Failure |
|---|---|---|---|---|
| **A1** | The unit of work was actually dispatched | `start.json` exists and `prompt_sha256` matches what was sent | at dispatch | lane `failed: "dispatch_unproven"` |
| **A2** | The lane is in the worktree it was given | `git rev-parse --show-toplevel` == `{{worktree}}` | at dispatch | lane `failed: "wrong_worktree"`, no retry |
| **A3** | The lane's base is the base it was told | `git merge-base --is-ancestor <base_sha> HEAD` | at dispatch and on the tick | hold the lane, notify |
| **A4** | The engine's computed branch equals the lane's branch | render `branching.branch_name_from` (a template, not a literal — for GSD `phase_branch_template`, VERIFIED `gsd/phase-{phase}-{slug}`) and compare against `{{branch}}` | at dispatch | hold the lane; **this is FIELD-NOTES §4.3** |
| **A5** | The step the orchestrator was told to dispatch actually started | a `engine.start` line exists for that step id before its result | at each step boundary | `not_done`, `reason: "step_not_started"` |
| **A6** | A merge the orchestrator performed moved the ref | §11.3 | at delivery | lane `failed: "merge_unproven"`, **never a retry** |
| **A7** | A resource the orchestrator created is gone at teardown | the ledger's own identifier is absent | at teardown | `degraded`, notify |

**A6 is the one that matters most**, and it is the direct fix for the largest recorded failure class.
FIELD-NOTES §4.1 (VERIFIED): `git checkout master` aborts when a tracked file is modified, and one
always is — GSD rewrites `.planning/milestone.lock` every phase and leaves it dirty — so the merge
*"ran on the phase branch against itself and printed `Already up to date` and `Everything
up-to-date`. Both read like success."* It was caught only because a human checked what `master`
actually pointed at.

### 11.3 A6, verbatim, already verified working

```bash
BASE=$(gh pr view "$PR" --json baseRefName --jq .baseRefName)
HEAD=$(gh pr view "$PR" --json headRefOid  --jq .headRefOid)
git fetch origin "$BASE"
git merge-base --is-ancestor "$HEAD" "origin/$BASE" \
  || fail "PR $PR reports merged; $HEAD is NOT an ancestor of origin/$BASE"
[ "$(gh pr view "$PR" --json state --jq .state)" = MERGED ] || fail "PR $PR is not MERGED"
```

CLAIMED working against this repository's own PR #26 (`C9` §5.3); the `gh pr view` shape and
`git merge-base --is-ancestor` exit 0 were re-VERIFIED there. Two independent oracles — the forge's
state and the git graph — and §4.1's failure mode (a branch merged into itself) fails the second one
instantly. Siblings in the same class: capture `EXPECTED_BASE=$(git rev-parse HEAD)` before dispatch
(A3); prefer `gh pr merge --match-head-commit "$HEAD"` so anything moving underneath aborts the merge
(**VERIFIED** present in `gh 2.92.0 --help`).

**DEFAULT-PROPOSED:** `assertions.enabled: ["A1","A2","A3","A4","A5","A6","A7"]` — all seven on;
each can be removed by name. Rationale: every one of them is a comparison the orchestrator can make
about itself, and six of the seven name a failure that actually happened.

### 11.4 What is explicitly forbidden, and linted

Not assertions. Not configurable into existence. A `grep`-for-absence in the test harness fails the
build if any of these appears in plugin source (a grep asserting a string is **absent** is one of the
very few checks that cannot pass vacuously — which matters in this repository, whose own memory rule
records that its harness greps prose):

- parsing a test summary, a coverage number or a lint count for a verdict;
- reading a diff to form an opinion about the work;
- re-running the engine's verification to "check" it;
- any judgement whose input is the content of the work product rather than the shape of an action.

The one string this rule *reads* is the self-attribution field of §8.4, which is metadata about the
verdict and not the work — and that exception is flagged three times in this document and is in §20.

---

## 12. The custom process — `process.yaml`

### 12.1 What it must express, from his sentence

[118], VERIFIED: «людина може визначити, абсолютно свій процес … **які дії будуть, за якими, коли
перевірка, чи буде перевірка**, і так далі, і він може що завгодно вписати.» Four things: the steps,
their order, where a check goes, **and whether there is a check at all**. A process with no check
must be legal, and nothing in the file may imply otherwise.

### 12.2 Location and format

```
./.claude/orchestrator/processes/<name>/process.yaml      # or process.json
```

**Both YAML and JSON are accepted, and neither is claimed as his choice** — [118] names YAML and
hedges it in the same breath. The loader is Node (already a dependency: `gsd-tools` is Node, and
`<baseline-marketplace>` OWNER-DECISIONS 5.1 fixes the resolver as Node), and it runs **once**, at
preflight, producing `<run>/plan/process.compiled.json`. **The tick loop only ever reads the compiled
JSON.** Rationale: `bash` cannot parse YAML, and a YAML reader in the hot path is the hidden
dependency `JUDGE-cost` flagged; compiling once removes it entirely.

### 12.3 The schema — nine keys per step, seven optional

```yaml
schema: 1
name: weekly-client-report
roles: [ready, active, needs-input, done]     # the work-source roles this process needs
steps:
  - id: gather                # REQUIRED — unique, stable, ^[a-z0-9][a-z0-9_-]{0,31}$
    run: "…"                  # REQUIRED — exactly one of `run` | `uses`
    uses: "my-skill"          #            `run` = shell argv or string; `uses` = skill/agent/command
    name: "Gather sources"    # optional — human label
    needs: [previous_step]    # optional — ordering edge; absent = after the previous step
    if: "file_exists:notes/"  # optional — a declared predicate, §12.5
    success: "exit 0"         # optional — DECLARED, never guessed; default `exit 0`
    timeout: 30m              # optional — default from §17
    retry: { max: 2, backoff: 60s, never: [auth_expired] }   # optional
    artifacts: ["out/report.md"]   # optional — existence test, §12.6
    on_fail: stop             # optional — stop | continue | ask ; default stop
    on_fail_message: "…"      # optional — the sentence handed back to the agent
completion:
  all_steps_passed: true      # optional; default true. `false` = the process declares no completion
                              # criterion, and the oracle returns `indeterminate` (§8).
```

Two deliberate departures from GitHub Actions, whose step keys are the reference minimum
(VERIFIED from the workflow-syntax docs: `id`, `if`, `name`, `uses`, `run`, `shell`, `with`, `env`,
`continue-on-error`, `timeout-minutes`, `working-directory`, and **no step-level retry**):

- an explicit `success` signal, because a coding agent exiting 0 means far less than a CI step
  exiting 0;
- a `retry` block with a `never[]` list, because Д5 needs a count and because some failures must
  never be retried — a permission refusal retried three times is three refusals.

**The minimum viable step is two keys**, `id` and `run`. A process with one step and no `artifacts`,
no `success` and no `completion` block is legal, and that is the point.

### 12.4 Compilation — the algorithm

1. Read the file; YAML or JSON by extension. A parse error is exit 64 naming line and column.
2. `schema` must be `1`. Unknown top-level keys that do not start with `x-` → exit 64.
3. Validate every step: `id` unique and matching the pattern; exactly one of `run`/`uses`; `needs`
   ids all exist; the graph is acyclic; `on_fail` in the closed set; `retry.never[]` entries are
   known reason codes.
4. Linearise: a total order consistent with `needs`, ties broken by file order.
   **DEFAULT-PROPOSED:** `process.parallel_steps: false` — steps run one at a time.
   Rationale: he described «які дії будуть, за якими» — a sequence. A DAG that fans out is a
   scheduler he did not ask for, and the sibling spec already owns run-level concurrency (R1-05,
   where he retracted machine-resource awareness outright at [163]).
5. Render each step into a frozen record with its resolved timeout, retry policy and templates
   (§5.7's closed variable set applies here too).
6. Write `<run>/plan/process.compiled.json`, `chmod 0444`.
7. Synthesise the ten points of §5.2 so the rest of this document applies unchanged:
   `start` = step 1, `step` = the step boundary, `progress` = steps completed over total,
   `completion` = `completion.all_steps_passed`, `records` = the compiled plan plus
   `<lane>/steps.ndjson`, `verification` = `engine-none` unless a step declares `artifacts`,
   `branching` = `undocumented` (so §10.2's default applies), `delivery` = `undocumented`.

### 12.5 The `if` predicate vocabulary — closed, four entries

`file_exists:<path>` · `file_absent:<path>` · `step_failed:<id>` · `step_skipped:<id>`.
Nothing else. No expression language, no shell interpolation into a condition. An unknown predicate
is exit 64 at compile time. Rationale: an expression language is the single most common place a
02:00 failure hides, and this is a sequence of steps, not a build system.

### 12.6 `artifacts` — the one check that does not cross the R1-13 line

A step declares it will produce a path; after the step, the path is there or it is not. **That is an
existence test, not a quality judgement.** It works identically on a repository with no tests and on
a folder of Markdown. A missing declared artifact sets the step's `success` to false and takes
`on_fail`; it never inspects the file's content.

**DEFAULT-PROPOSED:** `process.artifacts_required: true` when a step declares `artifacts`, i.e. a
declared artifact is enforced. Rationale: the user wrote the declaration; ignoring it would make the
key decorative. A user who wants the declaration to be advisory sets `on_fail: continue`.

### 12.7 `on_fail_message` — backpressure, not a second agent

The sentence in `on_fail_message` is handed back to the same session on the retry, which makes
"independent verification" a config file rather than a second agent (the `backpressure.gates` shape
from Ralph Orchestrator, VERIFIED in `LANDSCAPE` §4). **DEFAULT-PROPOSED:**
`process.on_fail_message_default: null` — no invented sentence; an empty message means the step
simply reports failure.

---

## 13. Worked example A — a code project on GSD

The shipped descriptor. **Every command in it was executed on this machine today** against
`/Users/sasha-marchuk/Work/sashko-vps`, a real GSD project, and the outputs are in the appendix.

`<plugin-root>/engines/gsd/engine.json`:

```json
{
  "id": "gsd",
  "name": "Get Shit Done",
  "protocol_version": 1,
  "runtime": "@opengsd/gsd-core",
  "exit_contract": "v1",
  "prompt_fragment": "engine.md",
  "needs": ["git", "subagents"],
  "timeouts": { "identity": 10, "progress": 15, "completion": 15, "escalation": 15, "records": 10, "branching": 20 },
  "points": {
    "identity":   { "kind": "command", "argv": ["gsd-tools","runtime-identity"], "format": "json",
                    "map": { "version": "$.version", "package": "$.packageName" }, "ok_when": "exit==0" },

    "start":      { "kind": "invoke",
                    "value": "/gsd:execute-phase {{ticket.ref}}",
                    "autonomous": "/gsd:autonomous",
                    "expect": ["turn_completed"] },

    "step":       { "kind": "hook", "point": "execute:post", "emits": "step.finished",
                    "install": ["gsd_run","loop","render-hooks","execute:post","--raw"] },

    "progress":   { "kind": "command", "argv": ["gsd-tools","progress"], "format": "json",
                    "map": { "percent": "$.percent", "position": "$.phases[-1].name" },
                    "ok_when": "exit==0" },

    "escalation": { "kind": "command", "argv": ["gsd-tools","windows","status"], "format": "json",
                    "map": { "open": "$.ledger.open_count",
                             "first": "$.ledger.entries[?(@.status=='human_needed')]" },
                    "needs_human_when": "open>0", "ok_when": "exit==0" },

    "completion": { "kind": "command", "argv": ["gsd-tools","smart-entry"], "format": "line",
                    "done_when": "/·\\s*100%\\s*·\\s*complete/",
                    "reject_if": [ { "file_glob": ".planning/phases/*/[0-9][0-9]-VERIFICATION.md",
                                     "field": "verified_by", "matches": "(?i)the lane that built" } ] },

    "records":    [ { "kind": "file", "path": ".planning/STATE.md", "format": "frontmatter",
                      "anchor": "state_head", "anchor_kind": "git-sha",
                      "fields": ["status","stopped_at","milestone","progress.percent"] },
                    { "kind": "file", "path": ".planning/ROADMAP.md", "format": "text",
                      "anchor_kind": "digest" },
                    { "kind": "file", "path": ".planning/milestone.lock", "format": "text",
                      "anchor_kind": "digest", "expect_dirty": true } ],

    "branching":  { "kind": "command",
                    "probes": {
                      "isolation":  { "argv": ["gsd-tools","dispatch-isolation"], "format": "line" },
                      "base_branch":{ "argv": ["gsd-tools","git","base-branch"], "format": "line" },
                      "base_check": { "argv": ["gsd-tools","worktree","base-check"], "format": "json",
                                      "map": { "degrade": "$.shouldDegrade", "reason": "$.reason",
                                               "head": "$.headSha", "fork": "$.forkSha" } } },
                    "owns_worktrees_when": "isolation != 'harness-worktree'",
                    "disable_setting": "workflow.use_worktrees=false in .planning/config.json",
                    "branch_name_from": "$.config.phase_branch_template" },

    "verification":{ "kind": "command", "argv": ["gsd-tools","verification"], "format": "json",
                     "map": { "verdict": "$.status" } },

    "delivery":   { "kind": "invoke", "value": "/gsd:ship" }
  }
}
```

**Three things in that file make it an adapter rather than a fork.**

1. **`step` uses GSD's own published extension point.** VERIFIED: twelve named loop-hook points exist
   on this machine (`discuss:pre` … `ship:post`), and `gsd_run loop render-hooks <point> --raw` is
   their documented consumer. A `contribution` hook gets a step-boundary signal **without patching
   GSD**. Nothing in `~/.claude/gsd-core/` is modified by the orchestrator, ever.
2. **`records` implements R1-06.3 literally.** [189]: «нічого не треба окремо записувати, а лише
   записувати оце референс». `STATE.md` frontmatter already publishes `state_head` as a git SHA
   (VERIFIED — today's file also carries `status: executing`, `stopped_at: Completed 06-02-PLAN.md`,
   `progress.percent: 75`). **One caution the owner should hear:** a process's own record can be
   hand-maintained, and a reference to it is then a reference to a claim. His three-way rule at [171]
   already covers the case; what is open is how the orchestrator decides a record is insufficient
   (§20 Q7).
3. **`branching` is a set of probes, not a belief.** `owns_worktrees_when` is evaluated from GSD's
   own answer, so the §10.3 negotiation is data-driven and the collision is detected at preflight
   rather than at 03:00.

### 13.1 One night, step by step

Configuration in slot 2 (`./.claude/shared/plugins/orchestrator.json`):

```json
{ "process": { "kind": "engine", "engine": { "id": "gsd" }, "on_indeterminate": "needs_review" },
  "branching": { "owner": "orchestrator", "base_ref": "auto" } }
```

1. **Preflight.** §4.4 resolves `engines/gsd/engine.json` from the shipped path; `identity` returns
   `{"packageName":"@opengsd/gsd-core","version":"1.14.0"}` (VERIFIED today). All ten points are
   `declared`. `plan/engine.json` is frozen.
2. **Branching negotiation (§10.3).** `dispatch-isolation` → `harness-worktree`, so
   `owns_worktrees_when` evaluates false: GSD does **not** own worktrees under this host, and
   `branching.owner: orchestrator` is compatible. `git base-branch` → `main`, so `base_ref` resolves
   to `main`. `worktree base-check` → `shouldDegrade: true, reason: head-diverged-from-fork`, which
   under the default `on_base_drift: record` writes one `weakened[]` row
   (`owner_item: "Д4.base-from-main"`, `consequence: "GSD runs phases sequentially in this worktree"`)
   and does **not** refuse.
3. **Dispatch.** The lane's worktree is cut off `main`; `base_sha` is captured; A2 and A3 assert
   inside the worktree; A4 compares GSD's `phase_branch_template`-derived name against the lane
   branch and **holds the lane on a mismatch** — that is FIELD-NOTES §4.3, closed by one comparison.
   `start` renders `/gsd:execute-phase 07`, preceded by the red-line file and `engine.md`.
4. **Each tick.** Three subprocess calls, zero tokens: `progress` → `75 / "executing"`;
   `escalation` → `open_count: 0`; `completion` → `Phase 7 of 7 · 75% · executing`, which does not
   match `done_when`, so `not_done`. `records` tier-0 `stat` shows `.planning/STATE.md` unchanged →
   nothing is journalled at all.
5. **A step boundary.** The `execute:post` hook emits `step.finished`; the sibling spec's `stop-soft`
   and context-`soft` boundaries now have a real place to land instead of waiting for the turn.
6. **Terminal.** The oracle ladder runs. `completion` matches → `done`, **unless** §8.4's `reject_if`
   finds `verified_by: the lane that built the phase` in the phase's `NN-VERIFICATION.md`, in which
   case the verdict is `not_done` with `reason: "verdict_self_attributed"` and the ticket goes to
   `needs_review`. That is phases 14–18 of the recorded run, caught automatically for the first time.
7. **Delivery.** `points.delivery` is declared, so the engine ships. The orchestrator asserts A6
   afterwards and nothing else: it does not read the diff, does not run the tests, does not judge the
   phase. A6 failing is `merge_unproven` and never a retry.
8. **Teardown (Д3).** The worktree, the branch and every resource in the lane's ledger are removed by
   the identifiers the ledger recorded. `.planning/` is not touched: it is the engine's.

---

## 14. Worked example B — a non-code task list, no repo, no tests, no build

N2 [344] is the reason this example exists: «може використовуватись зовсім навіть не для написання
коду … може таке бути, що десь не буде тестів, і це також окей.» Nothing below involves git.

`./.claude/orchestrator/processes/weekly-report/process.yaml`:

```yaml
schema: 1
name: weekly-report
roles: [ready, active, needs-input, done]
steps:
  - id: gather
    name: "Collect the week's sources"
    uses: "research-notes"
    artifacts: ["work/{{ticket.id}}/sources.md"]
    timeout: 20m
    on_fail: stop
    on_fail_message: "No sources were collected. Say what you could not reach, and stop."

  - id: draft
    name: "Write the draft"
    needs: [gather]
    uses: "report-writer"
    artifacts: ["work/{{ticket.id}}/draft.md"]
    timeout: 40m

  - id: factcheck
    name: "Check every claim against the sources"
    needs: [draft]
    uses: "fact-checker"
    artifacts: ["work/{{ticket.id}}/factcheck.md"]
    retry: { max: 2, backoff: 120s, never: [auth_expired] }
    on_fail: ask
    on_fail_message: "Two fact-check passes disagreed with the draft. Do not rewrite; report which claims."

  - id: package
    name: "Produce the deliverable"
    needs: [factcheck]
    run: ["pandoc", "work/{{ticket.id}}/draft.md", "-o", "out/{{ticket.id}}.docx"]
    artifacts: ["out/{{ticket.id}}.docx"]
    success: "exit 0"
completion:
  all_steps_passed: true
```

Configuration:

```json
{ "process": { "kind": "steps", "steps_ref": "weekly-report" },
  "branching": { "owner": "none" },
  "assertions": { "enabled": ["A1","A5","A7"] } }
```

**What changes, and why every change is forced by a rule already stated.**

- `branching.owner: none` — §10.2's third value. §10.3 step 2 sees no repository and accepts it;
  A2, A3, A4 and A6 are **skipped, not failed**, because they are git assertions on a project with no
  git (test 3 of §11.1). `plan/engine.json.assertions_enabled` records the three that remain.
- The oracle never reaches step 1 or 2 of §8.3 — there is no `points.completion` command — it lands
  on the synthesised `completion.all_steps_passed`, which is true exactly when every step's declared
  `success` held and every declared artifact exists. **No test was run, nothing was verified, and
  the ticket is still provably finished.** That is `artifacts` doing the work that tests do in
  example A.
- `factcheck.on_fail: ask` routes to the Д6 questions channel and the lane waits; a waiting lane
  charges nothing against the Д5 failure budget, because "needs a person" is not a failure.
- Teardown removes `work/<ticket>/` only if the ledger recorded creating it. `out/` is the
  deliverable and is never removed.
- **What the orchestrator asserts here:** A1 (the step was dispatched), A5 (each step it was told to
  dispatch actually started), A7 (what it created is gone). Nothing about the report's content. If
  the report is wrong, the process is what was supposed to catch that, and the user wrote the
  process. R1-13, on a project with no code at all.

### 14.1 The same shape, on a board instead of a folder

`roles:` in the process file is the list of work-source roles this process needs. The work-source
spec maps those roles to whatever the board calls them (R1-04 [153]: status names are the user's and
adapt to the chosen process). This seam declares the requirement and reads the mapping; it never
learns a status **name**. A process declaring a role the configured board cannot supply is a
preflight refusal naming both, exit 65.

---

## 15. The three descriptors that ship, and the one that does not

| id | Points declared | Status |
|---|---|---|
| `gsd` | all ten | **VERIFIED** — every command executed today (§13, appendix) |
| `feature-dev` | `start` only | **VERIFIED** — 125 lines of prose, no state file, no status command, no git, no resumability, read on this machine today |
| `none` | `start` only, the platform's own session | the default when nothing is configured |
| `superpowers` | — | **NOT SHIPPED.** VERIFIED absence: no `superpowers` plugin is installed on this machine (searched `~/.claude/plugins` and the profile switcher's directory today). He named it at [118] and it must be configurable; shipping a descriptor written from a README nobody ran would be exactly the lying manifest this contract exists to prevent. It is a user-written `engine.json` at path 1, 2 or 3 of §4.1 until someone runs it. §20 Q8. |

`feature-dev` is in the box as the **calibration**, not as a recommendation: if the contract cannot
express it, the contract is GSD-shaped wearing a generic name. Under it, every point but `start` is
`undocumented`, `weakened[]` has nine rows, the oracle returns `indeterminate` on every lane, and
with the default `on_indeterminate: needs_review` **every ticket lands in front of a human.** That is
the correct behaviour for an engine that publishes nothing, and it is loud rather than silent.

---

## 16. Refusals, exit codes, and the verify verb

### 16.1 Exit codes

| Code | Meaning | Where |
|---|---|---|
| 0 | ok | — |
| 64 | descriptor or process file invalid; EN-1 violated; unknown key/template/predicate | load, compile |
| 65 | contract violation: an ownership conflict, a role the board cannot supply, a `needs[]` the lane cannot meet | preflight |
| 66 | the configured engine is not installed | discover |
| 70 | environment: the engine's runtime is missing or unrunnable | preflight |

### 16.2 What refuses at 22:00 rather than degrading at 03:00

Only these: EN-1 (both process kinds set), a missing `start`, a `needs[]` the lane cannot meet, the
§10.3 step-4 ownership conflict, a `roles:` entry the board cannot supply, and an invalid descriptor
or process file. **Everything else degrades and is named in `weakened[]`.** The line is deliberate:
a refusal costs him a night, so only a condition under which the run would produce a *wrong* result
earns one; a condition under which it produces a *smaller* result is recorded and runs.

### 16.3 `orchestrator:engine verify <id>`

A shell script. Exit 0 pass / 64 descriptor invalid / 65 contract violation (named) / 70 environment.
Three checks carry it, and all three are the mechanical form of a rule that is otherwise only prose:

1. **Every declared `command` point runs** against `fixtures/` and, when `--live` is passed, against
   the configured project, within its timeout.
2. **`progress` returning an unparseable body yields `unknown`, never `0`** — asserted by feeding it
   a fixture with a renamed field. This is the mechanical catch for the class where a rename rendered
   `0 % used` and read as plenty of room.
3. **`completion` never returns `done` from a `reject_if` fixture** — a recorded
   `NN-VERIFICATION.md` carrying `verified_by: the lane that built the phase` must produce
   `not_done`.

**DEFAULT-PROPOSED:** `engine.verify_max_age_hours: 0` — **not** gated. Rationale: `ARCH-adapters`
gates dispatch on a conformance pass within 24 hours, and `JUDGE-cost` prices that as *the only
standing daily cost in the set* — one launched session per adapter per day, forever. For **one**
engine the owner runs every night, a gate that can block a run is worse than the drift it prevents.
`verify` runs on demand and in CI. Setting the key above zero turns the gate on. §20 Q9.

### 16.4 Build-time lints

Added to `tests/run-all.sh` (**VERIFIED**: the harness exists in this repository, 79 lines, with a
`PLUGINS=(…)` array a new plugin must be added to, per the repository's own memory rule).

1. Every key in §17 appears in the defaults file, and **no configuration default appears anywhere
   else in plugin source.** (Scope: configuration keys only. Values inside a shipped `engine.json`
   are descriptor content, not defaults, and are exempt — but each one that shadows a §17 key must
   name that key, which lint 5 checks.) A default in two places is a default that drifts.
2. None of the forbidden verbs of §11.4 appears in plugin source.
3. No teardown command in plugin source builds an identifier from an environment variable.
4. `pkill`, `killall` and an unscoped `docker compose down` appear nowhere.
5. Every `DEFAULT-PROPOSED` in this document has a row in §17, and every row in §17 has a key in the
   defaults file. Checked by a script, not by reading.

**And the rule this repository's own memory insists on:** each lint is verified by **mutation** —
break the contract on purpose and confirm the suite goes red — because a harness that greps prose can
pass vacuously. A lint nobody has broken on purpose is a claim, not a property.

---

## 17. The defaults register — this table is the contract

Nothing outside it may invent a default at runtime. `scope`: which of his three scopes may set it
(u = user, p = project, r = this run). `apply`: `live` = picked up on the next tick, `boundary` =
at the next step/lane boundary, `frozen` = fixed for the run at preflight.

| Key | DEFAULT-PROPOSED | Scope | Apply | One-line rationale |
|---|---|---|---|---|
| `process.kind` | `engine` | u p r | frozen | The common case is an existing process; `steps` is opt-in. |
| `process.engine.id` | `none` | u p r | frozen | No engine configured must mean "the platform's own session", not a crash. |
| `process.per_ticket_override` | `false` | u p | frozen | A per-ticket engine reopens EN-1 through the back door (§3.3). |
| `process.steps_ref` | `null` | u p r | frozen | Names the custom process directory under `.claude/orchestrator/processes/`; required when `kind: steps`, refused otherwise (EN-1). |
| `process.on_indeterminate` | `needs_review` | u p r | boundary | Advancing an empty ticket costs a morning; withholding costs a tick (§8.2). |
| `process.parallel_steps` | `false` | u p | frozen | He described a sequence; a fan-out is a scheduler he did not ask for. |
| `process.artifacts_required` | `true` | u p | frozen | The user wrote the declaration; ignoring it makes the key decorative. |
| `process.on_fail_message_default` | `null` | u p | boundary | No invented sentence is handed to an agent. |
| `engines.resolution` | `whole_file` | u p | frozen | A deep-merged descriptor is a contract nobody wrote or tested (§4.2). |
| `engine.probe_calls_per_tick` | `3` | u p r | live | Three subprocess calls per lane per tick is ~30 ms and zero tokens. |
| `engine.probe_log_max_kb` | `256` | u p | live | Bounded so a chatty engine cannot fill the disk overnight. |
| `engine.gsd.exit_contract` | `"v1"` | u p | frozen | VERIFIED: the same failure exits 1 under v1 and 64 under v2; pin it. |
| `engine.verify_max_age_hours` | `0` | u p | frozen | A daily live conformance smoke is a standing cost the owner did not ask for (§16.3). |
| `harvest_evidence` | `observed` | u p r | boundary | Withhold `done` only on positively observed emptiness; three values, never a boolean. |
| `completion.trust_self_attributed_verdict` | `false` | u p r | boundary | Five phases shipped with the builder as its own verifier; one string comparison closes it (§8.4). |
| `records.min_anchor` | `digest` | u p | frozen | A reference with no witness cannot support a resume decision. |
| `records.resume_from` | `["orchestrator_state","engine_records"]` | u p r | frozen | His stated default plus the reference he ratified at [189]. |
| `recovery.probe_before_judge` | `true` | u p | frozen | A probe of the world beats a model's reading of a fact sheet about the world. |
| `branching.owner` | `orchestrator` | u p r | frozen | Д4 [433] is his stated default; the parallelism cost is named, not hidden. |
| `branching.base_ref` | `"auto"` | u p r | frozen | Reads the engine's or the repo's own default branch rather than hard-coding `main`. |
| `branching.on_base_drift` | `record` | u p r | live | Drift is normal and self-healing; refusing would make ordinary work impossible, but it must be visible. |
| `branching.required_env` | `[]` | u p r | live | Inventing required variables for an unseen project is exactly the overreach N2 forbids. |
| `branching.stack_probe` | `null` | u p r | live | The orchestrator does not guess what stack a project needs. |
| `branching.on_stack_down` | `hold` | u p r | live | Holding is reversible; restarting or killing someone else's stack is what Д3 and R1-16 forbid. |
| `assertions.enabled` | all seven | u p r | frozen | Six of the seven name a failure that actually happened (§11.2). |
| `failures.identical_threshold` | `3` | u p r | live | His number, [442] «Три рази». |
| `failures.on_exhausted` | `notify_and_stop` | u p r | live | One of exactly the two actions he offered; no third is invented. |
| `timeouts.identity` / `.progress` / `.completion` / `.escalation` / `.records` / `.branching` | `10 / 15 / 15 / 15 / 10 / 20` s | u p | live | Long enough for a cold Node start on this machine, short enough that a tick is never blocked. |
| `steps.default_timeout` | `60m` | u p r | boundary | Measured: a worker session per phase ran 58 min – 3 h 20 (FIELD-NOTES §6); 60 min is a floor a user will raise deliberately. |
| `steps.default_retry` | `{max: 0}` | u p r | boundary | No silent retry. Д5 counts identical failures; a hidden retry hides the first two. |

---

## 18. What an implementer builds, in order

1. `orch-engine` (bash + jq): `discover`, `start`, `observe`, `oracle`, `resume`, `assert`. ~350 lines.
2. `engines/gsd/engine.json` + `engine.md`, and `engines/feature-dev/engine.json`. Data only.
3. `orch-process-compile.mjs` (Node): §12.4, YAML/JSON → `process.compiled.json`. ~200 lines.
4. `orchestrator:engine verify` (§16.3) plus fixtures. ~150 lines.
5. The five lints of §16.4, each broken on purpose once before it is believed.

**INFERRED cost:** ~700 lines plus two data files, inside `JUDGE-cost`'s ~1,000–1,400-line shared
baseline for the whole plugin rather than on top of it, because the observation path replaces work the
tick loop would otherwise do. No new runtime dependency: `git`, `jq`, `node` and `gh` are all present
on this machine (VERIFIED: `git 2.33.0`, `jq 1.8.1`, `node v22.18.0`, `gh 2.92.0`).

---

## 19. Tensions with his decisions — designed for, not replaced

1. **R1-13 vs the seven assertions (§11).** He decided verification belongs to the process with the
   field evidence in front of him [342], and that decision is not reopened. This document adds checks
   the orchestrator performs **on itself**. The distinction was never put to him. Every assertion is
   listed, every one is switchable off by name, and §20 Q3 asks him in his own vocabulary.
2. **R1-13 vs the self-attribution clause (§8.4).** Narrower and sharper than 1: this reads a field
   of the engine's own verdict and declines to believe it. It is on by default because five phases
   shipped that way; it is one key to turn off; §20 Q4 asks him.
3. **Д4's «з цим треба поєднювати» is impossible as stated (§10.1).** Named exactly: there is no
   configuration today that gives both his uniform worktree default and GSD's intra-phase
   parallelism. Keeping both costs a change inside GSD, which R1-03 forbids us from making. His
   stated default ships; the cost is printed; the choice is returned to him at §20 Q10.
4. **R1-06.3's reference points at a claim (§9.2).** His rule is kept whole. The only addition is
   that the orchestrator's own journal independently records the orchestrator's own operations, so a
   disagreement between two records with different authors can be *named*. It adds no second record
   of the work.
5. **Д5's moment is undecided (§8.5).** «В який момент не знаю» [442]. Counting at lane terminal is
   this document's choice and is the most conservative reading; §20 Q5.
6. **The four descriptor paths of §4.1 are this document's invention.** Д1 [416] points at his
   marketplace, whose rules cover values and not artefact directories. The ranking is copied; the
   paths are not his. §20 Q2.
7. **`engine.md` is prose injected into a prompt.** It is bounded at 8 KiB and truncated at a line
   boundary rather than failing, on the principle that a lane that starts with a slightly shorter
   process description is better than a lane that does not start. Nothing in this seam ever silently
   drops a *configuration* value — only prose, and it journals when it does.

---

## 20. Needs the owner — round 2, in plain Ukrainian

Ten questions. Each one names something this document had to invent because he never decided it.
One question per item, the concrete case included, options named and then silence.

**Q1 — один рушій на весь ран, чи на кожен тікет?**
> Ти сказав: або готовий процес, або свій, без змішування. Я зробив так, що процес обирається один
> раз на весь ран. Але може бути, що в одному ран одні тікети йдуть через гет шіт дан, а інші — через
> твій власний список кроків. Це змішування, чи ні?
> A) один процес на весь ран; B) можна вказати інший процес у самому тікеті.

**Q2 — де лежать описи рушіїв?**
> Налаштування ми беремо з твого маркетплейсу — шість файлів, особисте перемагає командне. Але сам
> опис рушія (як запускати гет шіт дан, які в нього команди) — це не налаштування, це файл-артефакт.
> Я поклав його в чотири місця з тим самим порядком: особисте в проєкті → твоє на машині → командне в
> проєкті → те, що йде з плагіном. Це правильне місце, чи описи рушіїв мають лежати десь інде?

**Q3 — чи має оркестратор перевіряти власні дії?**
> Ти вирішив, що перевірку роботи робить процес, і я цього не чіпаю. Але є окремий випадок: злиття,
> яке зробив сам оркестратор, надрукувало «Already up to date» і не перенесло нічого — гілку злили
> саму з собою. Жоден процес цього не перевіряв, бо дію зробив оркестратор. Чи має оркестратор
> перевіряти власні дії — що злиття справді зрушило гілку, що крок, який він мав запустити,
> запустився — чи це теж належить процесу?

**Q4 — чи можна не вірити вердикту, який підписав сам виконавець?**
> У тому рані п'ять фаз пройшли з файлом перевірки, де написано «перевірив той, хто це й робив».
> Ніхто цього не спіймав, крім людини очима. Я зробив так, що оркестратор читає вердикт процесу, але
> не приймає його, якщо в записі стоїть, що перевіряв той самий виконавець. Це нормально, чи це вже
> втручання в перевірку, яку ти віддав процесу?

**Q5 — коли рахувати три однакові невдачі?**
> Ти сказав: три рази одне й те саме — діяти за конфігом, а в який момент — не знаєш. Я рахую в
> момент, коли завдання завершилось невдало, а не всередині виконання. Тобто крок може всередині
> впасти десять разів, і це не рахується. Так правильно, чи рахувати кожне падіння кроку?

**Q6 — що робити, коли стек, від якого залежить завдання, впав посеред роботи?**
> Ти сказав постійно переконуватись, що енвайрмент верібли й запущений стек на місці. Уяви: о 3-й
> ночі контейнер, від якого залежить завдання, помер. Три варіанти: A) тримати завдання й чекати;
> B) написати тобі й тримати; C) не звертати уваги й виконувати далі. Я поставив A.

**Q7 — коли запис процесу вважати недостатнім?**
> Ти сказав: посилатися на записи процесу, свої вести лише якщо в процесу їх немає. Але буває третє:
> записи є, але вони неповні або їх пише руками сам процес. Як оркестратор має зрозуміти, що запису
> процесу недостатньо, і почати вести свій — чи це взагалі не має бути автоматично, а лише як я
> налаштую?

**Q8 — суперпауерс: хто пише опис?**
> Ти назвав суперпауерс як один із готових процесів. На машині його немає, я його не запускав, і
> писати опис із чужого README я не став — це саме той випадок, коли опис бреше о 3-й ночі. Чи мені
> поставити його і зробити перевірений опис, чи цей рушій лишається тим, що користувач описує сам?

**Q9 — чи має ран відмовлятися стартувати, якщо опис рушія давно не перевірявся?**
> Є варіант, коли оркестратор раз на добу реально запускає рушій і перевіряє, що опис не бреше, і
> без цієї перевірки не стартує. Це коштує одну зайву сесію щодня, назавжди. Я це вимкнув:
> перевірка є, але вона не блокує старт. Лишити вимкненим?

**Q10 — ворк трі: що віддаємо?**
> Твоя дефолтна пропозиція — кожне завдання в своєму ворк трі від головної гілки. Гет шіт дан
> усередині сам нарізає собі ворк трі від віддаленої головної гілки, і коли твоя база з нею не
> збігається, він тихо перемикається на послідовне виконання — я перевірив це сьогодні на твоєму ж
> проєкті. Сьогодні обидва варіанти разом не працюють. Що віддаємо:
> A) оркестратор створює ворк трі, а гет шіт дан усередині працює послідовно (зараз стоїть це);
> B) гет шіт дан створює сам, оркестратор ворк трі не чіпає й перестає перевіряти базу.

---

## Appendix — commands executed on this machine today (2026-09-19), for re-checking

```
node ~/.claude/gsd-core/bin/gsd-tools.cjs --help
  (in /Users/sasha-marchuk/Work/sashko-vps:)
  gsd-tools runtime-identity        → {"packageName":"@opengsd/gsd-core","version":"1.14.0"}
  gsd-tools smart-entry             → Phase 7 of 7 · 75% · executing / Recommended: progress-next
  gsd-tools progress                → JSON: milestone_version, phases[]{number,name,plans,summaries,status}
  gsd-tools state                   → JSON: config{branching_strategy, phase_branch_template, mode,
                                       auto_advance, _auto_chain_active, pr_strict, context_window, …},
                                       state_raw, state_exists, roadmap_exists, config_exists
  gsd-tools worktree base-check     → {"shouldDegrade":true,"reason":"head-diverged-from-fork",
                                       "headSha":"c62374ce…","forkRef":"origin/HEAD","forkSha":"72e0b343…"}
  gsd-tools dispatch-isolation      → harness-worktree
  gsd-tools git base-branch         → main
  gsd-tools windows status          → {"ok":true,"ledger":{"schema_version":1,"open_count":0,…}}
  gsd-tools state --pick config.branching_strategy         → none            (exit 0)
  gsd-tools state --pick config.nonexistent --json-errors  → {"ok":false,"reason":"pick_field_absent",…} (exit 1)
  gsd-tools progress --project-dir /tmp                     → exit 1
  gsd-tools progress --project-dir /tmp --exit-contract=v2  → exit 64
  gsd-tools bogus-command                                   → exit 1, "Unknown command"
head -20 /Users/sasha-marchuk/Work/sashko-vps/.planning/STATE.md
  → frontmatter: gsd_state_version, milestone, status: executing,
    stopped_at: "Completed 06-02-PLAN.md", last_updated, progress{percent: 75}
grep -oE '…' ~/.claude/gsd-core/references/loop-hook-dispatch.md
  → twelve points: discuss:pre|post, plan:pre|post, execute:pre, execute:wave:pre|post,
    execute:post, verify:pre|post, ship:pre|post
grep -n 'human_needed|insufficient_spec' ~/.claude/gsd-core/references/honest-verifier.md
  → abstain → insufficient_spec → human_needed, "never passed"
wc -l ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev/commands/feature-dev.md → 125
find ~/.claude/plugins ~/.<switcher> -iname '*superpower*'   → (no output — VERIFIED absence)
claude --help | grep -E 'worktree|--bg|--session-id|--output-format'
  → -w, --worktree [name]; --tmux (requires --worktree); --bg; --session-id <uuid>; --output-format
claude agents --help                                     → "Manage background agents", --json, --all, --cwd
git --version → 2.33.0 · jq 1.8.1 · node v22.18.0 · gh 2.92.0
```

**Files read in full or in the relevant part:** `round-1/ANALYSIS-01.md`, `round-1/TRANSCRIPT-01.md`
(rows 118–125, 344–349, 433–438), `research/extract/corrections.md` §§A–C,
`research/clusters/C9-process-delivery-{research,challenge,questions}.md`,
`research/platforms/ADAPTER-CONTRACT.md` §0–§1, `research/LANDSCAPE.md` §1, §5,
`research/architecture/{ARCH-minimal,ARCH-operability,ARCH-reliability,ARCH-adapters}.md` (engine and
claim sections), all three `JUDGE-*.md` in full,
`plugins/harness/docs/FIELD-NOTES.md` §4, §5, §6, §11.4, §11.5, §11.8, §12.7,
`~/.claude/gsd-core/references/{loop-hook-dispatch,honest-verifier,dispatch-isolation-gate}.md`,
`<baseline-marketplace>/requirements/OWNER-DECISIONS.md`
§§2–5 and `docs/config-levels.md` Parts One–Two.
