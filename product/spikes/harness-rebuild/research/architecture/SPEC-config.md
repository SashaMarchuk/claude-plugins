# SPEC-config — Configuration and the control plane

**Plugin:** `orchestrator` (replaces `harness`). **Date:** 2026-09-19. **Status:** implementable
specification. An implementer should be able to build every file, path, algorithm and default below
without asking a question; where a question is unavoidable it is in §14, phrased in Ukrainian for
round 2.

**Evidence tags.** **VERIFIED** — read or executed on this machine today, or read at the cited row in
`round-1/TRANSCRIPT-01.md`. **CLAIMED** — asserted by a document I read and not re-derived here.
**INFERRED** — my reasoning from the above. Every default is marked **DEFAULT-PROPOSED** with a
one-line rationale, because the owner stated almost none of them.

**Authority, in order.** `round-1/TRANSCRIPT-01.md` (his words) › `round-1/ANALYSIS-01.md` (the
requirements) › `research/extract/corrections.md` (which of those requirements he actually ratified)
› `<baseline-marketplace>/requirements/OWNER-DECISIONS.md` + `docs/config-levels.md` (his own
marketplace rules, which Д1 [416] hands this plugin wholesale) › the four designs and the three
judgments. Where the analysis and the transcript disagree, the transcript wins.

---

## 0. Which design this builds on, and where the judges disagreed

The three judgments do not agree on a winner:

| Judgment | 1st | 2nd | 3rd | 4th |
|---|---|---|---|---|
| `JUDGE-fidelity` | **ARCH-minimal** (8) | reliability (7) | adapters (6) | operability (5) |
| `JUDGE-cost` | **ARCH-minimal** (9) | operability (7) | reliability (5) | adapters (4) |
| `JUDGE-survival` | **ARCH-operability** (8) | adapters (7) | reliability (6) | minimal (5) |

**I follow `ARCH-minimal` as the base** — two of three firsts, and the two that agree are the two
axes a configuration spec sits on: fidelity (his decisions stay his) and cost (a control plane that
costs nothing to run is one that runs all night). **I take the control-plane mechanisms from the
survival winner**, because survival's specific complaint about minimal is precisely in this
document's scope: minimal's stop command *promises* ("applied within 60s") where operability's
`control.ack.json` *observes*, and minimal bounds the judge's bill but not the loop.

Concretely, and named so an implementer knows which document to open next:

| Taken from | What | Why over minimal's version |
|---|---|---|
| `ARCH-minimal` §2.2 | the one watched file; entries applied **exactly once by id**; self-write suppression by content hash; `verb`/`scope`/`apply` instead of a bare `hard` | it is the only design that refuses to guess which of his three meanings of «хард» a field carries |
| `ARCH-minimal` §2.1 | run state outside the work tree | Д4 [433] makes worktrees the default, and FIELD-NOTES §12.5 records a question channel forking into a worktree copy for an hour (VERIFIED) |
| `ARCH-operability` §3.3 | **`control.ack.json`** — the supervisor's reply, `applied` / `deferred` / `rejected` per key | FIELD-NOTES §11.2: two of the owner's own instructions recorded as delivered and never executed (VERIFIED). A promise is not an observation |
| `ARCH-operability` §10.3 | the hot / warm / cold apply classes, renamed to his own words | his «софт»/«хард» [195] generalised, plus the honest third case he never named |
| `ARCH-operability` §3.4 | the single-writer table, enforced by a lint rule | FIELD-NOTES §2.1: the previous generation's watch loop truncated `state/attention` every cycle and destroyed a night of another process's writing (VERIFIED) |
| `ARCH-adapters` §17 | the defaults table **as a contract** — *nothing outside it may invent a default at runtime*, plus `scope` and `apply` columns | the brief's second rule made checkable by a test rather than stated as a summary |
| `ARCH-adapters` §3.4 | content hash as the decision, mtime only as the cheap gate | `corrections.md` §B [195]: mtime was «Можливо, там, наприклад, по даті» — a hedge the analysis hardened |
| `ARCH-reliability` §3.2 r5 + §10.2 | *boot fails loud, reload keeps last good*; the stop command polls the applied record and returns **exit 8** for written-but-unacknowledged | a hand-edit mistake at 02:00 must not take the run down, and a stop's exit code should mean something |
| `ARCH-reliability` §3.5 | holder identity as `(pid, pid_start_ticks, argv_sha256, boot_id)` | PID reuse; and it is the only lock identity that survives a reboot honestly |
| `JUDGE-fidelity` G11 | `context.post_compact_prompt` as **his** key, not the plugin's behaviour | [204] names it and all four designs turned it into behaviour or dropped it |
| `JUDGE-cost` G1 / `JUDGE-survival` G3 | `trips/<sha>.json` created `O_EXCL` **before** acting | a ceiling answers "how much"; a watermark answers "again?" — the 85-minute loop was a re-fire, not a volume problem |

**Where I went against a judge, and why.** Four places.

1. **`failure.action` default.** `ARCH-reliability` ships `park` (tombstone the ticket, keep the run
   going). `JUDGE-fidelity` §5.2 calls this the clearest instance in the set of a decision being
   improved on while being described as honoured, and it is right: [442] closes the set at two —
   «дати знати про це, зупинитись, або просто зупинитись» — and reserves everything beyond that to
   him. I ship `notify_and_stop`, one of his two. `park` exists as a value, off.
2. **`tickets.intake` default.** `ARCH-adapters` ships `capped` at 10. Д2 [422] is unconditional. I
   ship `open` and keep the 236 → 327 queue-growth evidence as a *notification*
   (`tickets.notify_on_queue_growth: 50`, minimal's handling) rather than a brake.
3. **`lanes.max` default.** `ARCH-operability` ships 1 per account, which `JUDGE-fidelity` correctly
   reads as below his own observed practice. I ship 2 (FIELD-NOTES §9.3: two lanes ran cleanly,
   VERIFIED) and answer the OOM half with `lanes.max_heavy: 1` — a declared-cost queue, flagged in
   §12 as adjacent to the axis he retracted at [163].
4. **`context.basis`.** `JUDGE-fidelity` G10 wants it *required*, with no default. Requiring a key he
   has never thought about, on an unattended tool, buys an exit 3 at 22:00. I give it a default and
   move the honesty into the wizard: whenever he sets any context threshold, the wizard prints both
   numbers for a live session at that moment. The information arrives; the refusal does not.

---

## 1. Three planes, and why they are not one thing

The single most common mistake available here is to call all of this "config". It is three planes
with three lifetimes, three writers and three protocols.

| Plane | Lifetime | Written by | Read by | Governed by |
|---|---|---|---|---|
| **Configuration** | forever, across runs | the person, the wizard; **never** the running orchestrator | the resolver, at preflight and on change | his marketplace rules (Д1 [416]) |
| **Run input** | one run, immutable | `/orchestrator:run --set …` at launch | the supervisor, once | this document §8 |
| **Control** | one run, mutable *during* it | the person's editor, `/orchestrator:*` commands | the supervisor, every `control.poll_seconds` | Д12 [520]/[524], R1-07 [195], Д7 [458] |

The owner's cross-cutting requirement 1 in `ANALYSIS-01` — *everything is configurable at three
scopes, and a change made during a run must be picked up* — is the seam between plane 1 and plane 3.
The whole of §5 exists to make that seam cheap and auditable.

**The orchestrator never writes a configuration file.** OWNER-DECISIONS 5.1 (the resolver reads and
never writes) and 3.9 (an answer is written to the person's own file, after asking) are both binding.
An unattended run that learns something writes it to the control plane or to the run report, never to
a slot. `/orchestrator:config --promote` (§6.6) is the only path from plane 3 back into plane 1, and
it is interactive.

---

## 2. Configuration — the six slots, mapped onto this plugin

### 2.1 The paths

Plugin name: `orchestrator`. The six binding slots are OWNER-DECISIONS 3.3 and `config-levels.md` §2
verbatim, lowest authority first:

```
slot 1   ./.claude/shared/identity.json                      project, general, committed
slot 2   ./.claude/shared/plugins/orchestrator.json          project, this plugin, committed
slot 3   <config-root>/shared/identity.json                  user, general
slot 4   <config-root>/shared/plugins/orchestrator.json      user, this plugin
slot 5   ./.claude/shared/identity.local.json                project, general, personal, gitignored
slot 6   ./.claude/shared/plugins/orchestrator.local.json    project, this plugin, personal, gitignored

advisory plugins/orchestrator/config/recommended.json        never a value (OWNER-DECISIONS 3.8)
```

`<config-root>` resolves as `config-levels.md` §2 requires: `CLAUDE_CONFIG_DIR` verbatim when set;
otherwise `os.homedir() + "/.claude"` on macOS/Linux, `%USERPROFILE%\.claude` on Windows. Always
absolute, never a literal `~` in a file call. **`<config-root>/plugins/` belongs to Claude Code**; the
per-plugin files live under `<config-root>/shared/plugins/`.

Two facts an implementer will otherwise get wrong:

- **All four project-level files resolve for one invocation** (slots 1, 2, 5, 6). Each is read
  whichever others exist. A missing file is an empty slot, not an error.
- **The project root is the main checkout, always.** Resolve it with
  `git rev-parse --git-common-dir` and take its parent (CLAIMED from `ARCH-minimal` §2.1, which
  reports it VERIFIED on git 2.33.0; git 2.33.0 confirmed on this machine today, VERIFIED). A lane
  running inside a worktree must not read slot 1/2/5/6 from the worktree's own copy — that is exactly
  the fork FIELD-NOTES §12.5 records (VERIFIED).

**A file that looks like config but sits anywhere else is not config.** It supplies no value and the
run emits one warning naming it (`config-levels.md` §2). This is load-bearing here: the previous
generation's `~/.claude/harness/config.json` and `<project>/.harness/config.json` are **not slots** and
must not be read as such. §10 specifies the migration.

### 2.2 Which file a key belongs in

OWNER-DECISIONS 3.4's test is **reusability**, and its default answer is the general config. A value
reaches `plugins/orchestrator.json` only when nothing but this plugin could act on it; a value whose
reach is unclear counts as reusable.

| Goes into `identity.json` (general) | Goes into `plugins/orchestrator.json` |
|---|---|
| `connectors.*` — the board, the notification channel, the questions channel | `engine.*`, `tickets.*`, `lanes.*`, `roles.*` |
| `never`, `fallback` | `run.*`, `authority.*`, `capacity.*`, `context.*` |
| `accounts.*` and `providers.*` — the account/provider inventory | `liveness.*`, `doctor.*`, `warden.*`, `recovery.*` |
| `redlines.path` — R1-15's file is *"обов'язкового порядку всіма"* [357], so it is plainly reusable | `stops.*`, `failure.*`, `behaviour.*`, `delivery.*` |
| `notify.channel` | `questions.*` (the behaviour), `notify.events`, `status.*` |
| | `tick.*`, `control.*`, `judge.*`, `runs.*`, `adapters.*`, `runtime.*`, `worktree.*` |

INFERRED, applying 3.4's test key by key. The line that will be argued is `worktree.*`: I put it in
the plugin file because a worktree layout chosen *for this orchestrator's lanes* is not a fact another
plugin can act on. `accounts.*` goes in the general config because the account roster is the most
reusable thing on the machine.

### 2.3 `recommended.json` — advice, never a value

`plugins/orchestrator/config/recommended.json`, read by the configurator and the plugin builder,
**never by the resolver** (OWNER-DECISIONS 3.8). Deleting it changes no resolved value.

```json
{
  "connectors": {
    "tasks": {
      "strength": "weak",
      "candidates": ["github-issues", "clickup", "linear", "jira", "local"],
      "note": "Where ready work comes from. GitHub Issues fits a single-repo project; a local registry under .orchestrator/tickets needs nothing at all."
    },
    "notify": {
      "strength": "weak",
      "candidates": ["terminal", "telegram", "slack", "gmail", "call"],
      "note": "Where the orchestrator tells you something happened. Terminal-only is a complete answer."
    },
    "questions": {
      "strength": "weak",
      "candidates": ["file", "github-issues", "clickup"],
      "note": "The one place you answer its questions, confirm decisions and review finished work. It may be somewhere other than the task board."
    }
  }
}
```

`strength` is `weak | strong`, and those two are the whole domain (OWNER-DECISIONS 4.12). A `strong`
source lists exactly one candidate. All three of this plugin's sources are `weak`: R1-04 [129] and
Д6 [449] and R1-17 [395] each end in *"це може бути що завгодно"*. The candidate lists are
his own examples, in his own order — GitHub Issues first because [129] says so, hedged with «напевно»
(`corrections.md` §B, VERIFIED), which is exactly what `weak` means.

Note what is **not** here: the platform adapters. `claude-code` is the only lane that can run tonight
(CLAIMED, `ADAPTER-CONTRACT` §5), which would make it a `strong` recommendation — but a platform is
not a *connector source* in the marketplace's vocabulary, so it is declared in the adapter registry
(§4.13), not here.

### 2.4 Resolution — the algorithm

Run once at preflight, and again on any slot-file change (§5.9). Deterministic: two runs over
identical file contents produce an identical result, byte for byte.

1. Resolve `<config-root>` and the project root as §2.1 specifies.
2. Read the six files. A missing file is `{}`. A file that is present and unparseable is a **hard
   failure at preflight** (exit 78, naming the file and the parse error) and, mid-run, is treated as
   *unchanged* — the last good content of that slot stays in force and a `config.slot_invalid` journal
   line is written. Rationale: at preflight a broken config must fail loud; mid-run it must not take a
   night down. (`ARCH-reliability` §3.2 rule 5.)
3. Start from the shipped defaults of §4 (layer 0).
4. Merge slots 1 → 6 in order. Objects deep-merge key by key. `use` is replaced as one whole value
   and carries the keys of the file it came from. `never` accumulates: the sorted, deduplicated union
   of every entry in force. Arrays other than `never` are replaced whole (INFERRED — `config-levels.md`
   §6's "anything else" row). `x-` keys pass through and combine like any other key.
5. Merge run input (`run.json`, layer 7) — §8.
6. Merge the control overlay (`control.yaml`, layer 8) — §5. This step, and only this step, re-runs
   on a control change without re-reading the slots.
7. Apply the veto (§3.3).
8. Validate (§4.14). Unknown keys inside `connectors.<source>` are a warning, the key is dropped, and
   nothing else in the file is affected (OWNER-DECISIONS 4.9: *one unknown key never costs more than
   itself*). Unknown keys elsewhere in a plugin file are a warning and are preserved in the resolved
   config unread, so a newer plugin version finds them.
9. Write `runs/<run-id>/config.resolved.json` with **per-key provenance**:

```json
{
  "schema": 1,
  "resolved_at": "2026-09-19T22:41:00Z",
  "values": { "lanes": { "max": 2 }, "run": { "mode": "controlled" } },
  "provenance": {
    "lanes.max":  { "layer": 6, "source": "./.claude/shared/plugins/orchestrator.local.json" },
    "run.mode":   { "layer": 0, "source": "shipped-default" }
  },
  "sources": [
    { "slot": 1, "path": "…/identity.json", "present": true,  "sha256": "…", "mtime": "…", "size": 412 },
    { "slot": 2, "path": "…/orchestrator.json", "present": false }
  ],
  "warnings": [ { "code": "unknown-key", "key": "connectors.tasks.labelz", "file": "…" } ]
}
```

Provenance is not decoration. It is the only way `/orchestrator:config --show` can answer *"why is
this value 2"* without a model, and it is what makes every worked example in §3.4 checkable.

### 2.5 The resolver, and what happens when it did not run

One deterministic Node program (OWNER-DECISIONS 5.1). Node v22.18.0 is present on this machine
(VERIFIED). Interface:

```
node <plugin>/scripts/resolve-config.mjs --plugin orchestrator --project <abs> [--json]
  → stdout: the config.resolved.json document above
  → exit 0 ok · 78 a slot file is unparseable · 64 usage
```

**The read is mandatory on every invocation** (OWNER-DECISIONS 4.10), and when the resolver did not
run the agent performs the merge itself by these rules and acts on that (4.10, `config-levels.md`
§10).

**⚠ A deviation from the letter of 4.10, stated rather than hidden.** The supervisor's tick loop is
not an invocation of the plugin; it is one process that was invoked once. Running the Node resolver 60
times an hour for a whole night is a cost the owner would not accept and Д11 [512] says so. So: the
resolver runs at preflight, and again only when the cheap change gate (§5.9) says a slot file's hash
moved. Between those points the supervisor holds `config.resolved.json` in memory. Every *command*
(`config`, `status`, `stop`, `run`) is a real invocation and resolves normally. This is recorded in
§12 as a tension and in §14 as a question.

---

## 3. Precedence — the exact table

### 3.1 The nine layers

Highest authority first. This table is the contract; nothing else establishes a value.

| Layer | What | Path | Lifetime | Mid-run change |
|---:|---|---|---|---|
| **8** | **Control overlay** | `runs/<run-id>/control.yaml` | dies with the run | yes, per apply class (§5.7) |
| **7** | **Run input** | `runs/<run-id>/run.json` | dies with the run | no — immutable once written |
| **6** | slot 6 — project, this plugin, personal | `./.claude/shared/plugins/orchestrator.local.json` | forever | yes, re-resolved (§5.9) |
| **5** | slot 5 — project, general, personal | `./.claude/shared/identity.local.json` | forever | yes |
| **4** | slot 4 — user, this plugin | `<config-root>/shared/plugins/orchestrator.json` | forever | yes |
| **3** | slot 3 — user, general | `<config-root>/shared/identity.json` | forever | yes |
| **2** | slot 2 — project, this plugin, committed | `./.claude/shared/plugins/orchestrator.json` | forever | yes |
| **1** | slot 1 — project, general, committed | `./.claude/shared/identity.json` | forever | yes |
| **0** | shipped defaults | §4 of this document | forever | never |
| — | `recommended.json` | `plugins/orchestrator/config/recommended.json` | — | **contributes no value, ever** |

Layers 1–6 are OWNER-DECISIONS 4.15 verbatim: *a person's own files beat the project's committed
files; among a person's own, this project beats the home folder; inside either, the plugin's own file
beats the general one.* Layers 7 and 8 are this plugin's run scope and are **not config slots** —
§3.2.

### 3.2 Why 7 and 8 are not a fourth level

R1-12 [331], R1-14 [075] and Д7 [458] all require a **run** scope. OWNER-DECISIONS 3.6 says three
levels are the whole set and *"do not build it, do not reserve a path for it"* about the fourth. Both
are his. The reconciliation, which changes nothing in his marketplace:

> **The run scope is not configuration. It is run state.** `run.json` is the invocation's arguments;
> `control.yaml` is the run's control surface. Neither is read by the resolver, neither lives at a
> config path, neither persists past the run, and neither can be created by the wizard. What the
> marketplace forbids is a fourth *config level*; what he asked for is a way to change this run.

`LANDSCAPE.md` §5 records that nobody in the field has three scopes, so there is no prior art to copy
and the reconciliation is ours (VERIFIED as a field fact, CLAIMED as to its completeness). §12 records
it as a tension, because layer 8 does outrank a person's own file for the duration of a night, and he
never ruled on that.

### 3.3 The veto, and the one thing layer 8 cannot do

`never` is not a value; it is a filter (OWNER-DECISIONS 4.4, 4.15).

1. A person's own `never` entries — from slots 3, 4, 5, 6 — accumulate and hold against **every**
   candidate for that source, including that person's own `use`.
2. A committed project `never` (slots 1, 2) holds against every candidate **except** a tool one of the
   person's own files names in `use`.
3. **Layers 7 and 8 cannot defeat a `never`.** A `--set` or a control `overrides:` entry that selects
   a tool struck by an in-force `never` is refused: the run records `control.veto` / `run.veto`
   naming the entry and the file that holds it, `control.ack.json` reports it under `rejected`, and
   the previously resolved value stays. This is the one asymmetry in the ladder and it follows
   directly from 4.15's "hold against everything, their own pick included".
4. Matching is on whole segments of a tool identity string `<kind>:<identity>`: `mcp` matches
   `mcp:clickup`; `mcp:gcal` does not match `mcp:gcal-2`.
5. A `never` entry that strikes nothing anywhere in the resolution produces one warning naming the
   entry and its file, and is **never corrected automatically** (OWNER-DECISIONS 4.6).

The veto applies only where a tool is being selected — the `connectors.<source>.use` keys. It has no
meaning for `lanes.max`, and an implementer must not generalise it.

### 3.4 Worked examples of conflicts

Each example gives the files, the resolution, and the one sentence that decides it.

---

**E1 — the team standard versus his own preference.** OWNER-DECISIONS 4.15's headline case.

```jsonc
// slot 1  ./.claude/shared/identity.json           (committed)
{ "connectors": { "tasks": { "use": { "kind": "mcp", "server": "clickup" } } } }
// slot 3  <config-root>/shared/identity.json       (his own)
{ "connectors": { "tasks": { "use": { "kind": "cli", "command": "clkup" } } } }
```

Resolved `connectors.tasks.use` = `{ "kind": "cli", "command": "clkup" }`, and it carries **no**
`server` key — `use` is replaced whole, not deep-merged. *A person's own file beats the project's
committed file, and he marks nothing to make that happen.*

---

**E2 — all nine layers on one key.** `lanes.max` over one night.

| Layer | Value | Event |
|---:|---|---|
| 0 | `2` | shipped default |
| 2 | `4` | the repo's committed `orchestrator.json` says this project can take four |
| 6 | `2` | his own `.local` file says not on his laptop |
| 7 | `3` | `orchestrator:run --set lanes.max=3` at 22:41 |
| 8 | `1` | at 02:10 he edits `overrides: {lanes.max: 1}` because a build is thrashing |
| 8 | *(removed)* | at 07:00 he deletes the line |

Effective value at each point: `2 → 2 → 2 → 3 → 1 → 3`. Two consequences an implementer must get
right. First, **deleting a key from `overrides:` restores the next layer down, not the shipped
default** — the resolution is recomputed, it is not a stack of patches. Second, `lanes.max` is class
`soft` **upward** and `hard` **downward** (§5.7): the drop to 1 takes effect on the next poll and no
new lane is dispatched; the return to 3 takes effect at the next lane boundary. That asymmetry is
deliberate — lowering a ceiling is a brake and must not wait; raising one is an opportunity and can.

---

**E3 — an override struck by his own veto.**

```jsonc
// slot 3 (his own)
{ "connectors": { "tasks": { "use": { "kind": "cli", "command": "clkup" } } },
  "never": ["mcp:clickup"] }
```
```yaml
# control.yaml, hand-edited at 01:50
overrides:
  connectors.tasks.use: { kind: mcp, server: clickup }
```

Refused. `control.ack.json` gains
`{"key":"connectors.tasks.use","reason":"vetoed by never:mcp:clickup in <config-root>/shared/identity.json"}`
under `rejected`, a `control.veto` journal line is written, `connectors.tasks.use` stays
`cli:clkup`, and the run continues. *His `never` holds against his own pick, so it certainly holds
against a run-scope override.* The fix is his: remove the `never` entry, which is a config edit, not a
control edit.

---

**E4 — a `next-run` key edited in the control file.**

```yaml
overrides:
  engine.kind: custom
```

Refused twice over. If it was written by a command, `/orchestrator:config --set` refuses at write time
with exit 65 and prints: *`engine.kind` takes effect only on a new run — write it to
`./.claude/shared/plugins/orchestrator.local.json` and start a new run.* If it was hand-edited, the
reader refuses it, records `control.refused` with
`reason: "next-run class key in overrides"`, lists it in `control.ack.json.rejected`, and shows it in
`status.json.control_refused` with the words *takes effect on the next run*. It is never silently
ignored and never silently applied. (`ARCH-adapters` §3.4; `ARCH-operability` §10.3.)

---

**E5 — an account change, soft and hard.** R1-07 [195]: *«чи це софт, що це треба буде наступні
завдання перенести, чи це хард, чи це треба прямо вже зробити і зупинити»* (VERIFIED).

```yaml
roles:
  executor: { account: <profile-B>, apply: soft }   # → applies to the next dispatch
```
```yaml
roles:
  executor: { account: <profile-B>, apply: hard }   # → stop the lane now, relaunch, re-seed
```

`soft` is class `soft`: running lanes keep the account they booted with, the next claim uses the new
one. `hard` is class `hard`, and here the honest cost has to be printed, because **changing a running
session's account is impossible on every one of the fifteen platforms examined** (CLAIMED,
`ADAPTER-CONTRACT` §3 F, stated as VERIFIED there; corroborated by FIELD-NOTES §8's measurement that a
booted session keeps its account). So `apply: hard` means *stop the lane, relaunch on the new account,
re-seed its context* — he pays for that context a second time. The command prints the estimated
re-seed cost before writing, and the journal records `cost.reseed_tokens`. §13 lists it as impossible
as stated.

---

**E6 — a broken hand-edit at 02:14.**

He opens `control.yaml` in vim, mis-indents `behaviour:`, saves. Sequence, exact:

| t | What happens |
|---|---|
| 02:14:03 | `rename()` lands (vim's default `backupcopy=auto` writes and renames) |
| 02:14:08 | poll: mtime changed, mtime age 5 s ≥ `debounce_ms`, read, hash differs from applied |
| 02:14:08 | parse fails at line 14 col 9 |
| 02:14:08 | **last good document stays in force**; `control.applied.json` is untouched |
| 02:14:08 | `control.ack.json` ← `{"parse":"error","error":{...,"line":14,"col":9},"applied":[],"deferred":[],"rejected":[]}` |
| 02:14:08 | one `control.invalid` journal line; one notification (coalesced by error hash — a file left broken does not notify 360 times an hour) |
| 02:14:08 | `status.json.control_error` set; **the run does not stop and nothing is rolled back** |
| 02:20:41 | he fixes it; next poll applies it; `control_error` clears |

*Boot fails loud, reload keeps last good* (`ARCH-reliability` §3.2 rule 5, from `dsh`'s settings-file
protocol, CLAIMED via `ADOPTION-VERDICT` §4 item 9). The alternative — refusing to run on a bad
control file — converts a typo into a lost night.

---

**E7 — two writers in the same second.** `/orchestrator:stop-soft` from a second terminal while he is
saving an edit in vim.

The command takes the lock, re-reads, merges its one leaf, bumps `revision` 12 → 13, renames.
Vim does not take the lock; its rename lands at revision 12 with different content. The reader's rule
(§5.9 step 7) is on `(revision, sha256)`:

| revision vs applied | sha vs applied | Decision |
|---|---|---|
| — | equal | no-op (self-write or a save with no change) |
| `>` | differs | apply; `author` from the document |
| `==` | differs | **hand edit** — apply, record `author: "hand"`, set `applied_revision = applied + 1` |
| `<` | differs | **stale** — refuse, `reason: stale-revision`, notify. This is the `git checkout`-restores-old-content case, which defeats mtime entirely |

So the outcome depends on landing order and nothing is lost silently: if vim lands last, the stop is
gone from the file and the command's `control.ack.json` poll returns **exit 8, written but not
acknowledged**, which tells him to look. That is the whole reason the stop command polls rather than
promises.

---

**E8 — `CLAUDE_CONFIG_DIR` moves.** With it set to `/Users/x/.<switcher>/profiles/<profile>`, slots 3 and
4 become `/Users/x/.<switcher>/profiles/<profile>/shared/identity.json` and
`.../shared/plugins/orchestrator.json`. Slots 1, 2, 5 and 6 do not move — they are relative to the
project. This is not hypothetical on this machine: the account switcher works by moving exactly this
variable (VERIFIED — the running session's own `CLAUDE_CONFIG_DIR` is a profile switcher's profile directory).
An implementer must therefore resolve `<config-root>` **per invocation**, never cache it across a
role switch, and record it in the run's `config.sources.json`, because two roles on two accounts
legitimately resolve two different slot 3s.

---

## 4. The key catalogue

**This table is the contract. Nothing outside it may invent a default at runtime**
(`ARCH-adapters` §17's rule, adopted verbatim). A test walks the plugin source for every literal
fallback and fails the build on one that is not a row here.

Columns: **File** is `G` general (`identity.json`) or `P` plugin (`plugins/orchestrator.json`), by
§2.2. **Apply** is the mid-run class (§5.7): `hard` next poll · `soft` next boundary · `next-run`.
**Asked** is what obtains the value when it is missing: `—` the default stands · `W§n` the wizard
stage · `PF` preflight refuses in an unattended run.

**Every value in the DEFAULT-PROPOSED column carries that tag literally**: he stated almost none of
them, and each row's Rationale is the one line that justifies it. Where the rationale cites a
transcript row, the *value* is his and only the choice to make it the default is mine; those are
marked in the rationale in bold.

**Scope.** There is no per-key scope restriction, and inventing one would break "everything he made
configurable stays configurable". **Every key below may be set at any of layers 1–8** (§3.1), with
one mechanical exception: a key whose Apply class is `next-run` is refused in layer 8, because the
control overlay dies with the run and setting a next-run key there could never take effect (V6, E4).
The **File** column says which of the two files inside a band a key belongs in, by the reusability
test of §2.2; it does not restrict the band.

### 4.1 Connectors and channels

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `connectors.tasks.use` | object | G | next-run | *unset* → `tickets.source: local` | W§3 | R1-04 [129]: local registry **or** a board; a local registry needs nothing, so zero config still runs (OWNER-DECISIONS 6.1) |
| `connectors.tasks.fallback` | `ask\|auto\|skip` | G | next-run | `ask` | — | OWNER-DECISIONS 4.14's own default |
| `connectors.notify.use` | object | G | soft | `{kind:"terminal"}` | W§9 | R1-17 [395] names terminal as one of his own options and it is the only channel that cannot fail to be configured |
| `connectors.questions.use` | object | G | next-run | `{kind:"file", path:"<project>/.orchestrator/QUESTIONS.md"}` | W§9 | Д6 [449]: a single local file is his own lived example — *«я зробив якийсь єдиний файлик»* |
| `never` | string[] | G,P | next-run | `[]` | — | OWNER-DECISIONS 4.4 |
| `fallback` | `ask\|auto\|skip` | G | next-run | `ask` | — | OWNER-DECISIONS 4.14 |

### 4.2 Accounts, providers, roles (R1-07)

`Provider` and `Platform` are different objects and a lane is their product — four of the fifteen
names on his list are providers behind an existing CLI, not platforms (CLAIMED, `ADAPTER-CONTRACT`
§0: `Lane = Platform × Provider × Account × Role`).

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `accounts.<id>.platform` | string (adapter id) | G | next-run | *required per account* | W§4 | — |
| `accounts.<id>.provider` | string | G | next-run | the platform's native provider | W§4 | `ADAPTER-CONTRACT` §0 |
| `accounts.<id>.switch` | object `{kind: env\|profile\|apikey\|home, command?, vars?, home?}` | G | next-run | *required per account* | W§4 | R1-07 [199]: *«для кожної платформи це окремо треба пояснювати… в моєму випадку це перемикач профілів, який використовує різні профілі»* |
| `accounts.<id>.roles` | string[] | G | soft | `["*"]` | — | [270]: *«може використовувати тільки для оркестратора… тільки для екзек'ютора»* — the restriction is his, the permissive default is mine because he called it a restriction, not a requirement |
| `accounts.<id>.verify` | probe object (§4.13) | G | next-run | the adapter's own identity probe | — | R1-07 [199] *«перед запуском потрібно переконатися, що це працює»* |
| `providers.<id>.base_url` / `.model` / `.small_model` / `.context_window` | string / int | G | next-run | from the adapter manifest | — | — |
| `providers.<id>.capacity_model` | `window\|credit\|unknown` | G | next-run | from the adapter manifest | — | `ADAPTER-CONTRACT` §3 E: the axis that splits the field |
| `providers.<id>.concurrency_ceiling` | int | G | soft | `0` (none) | — | some providers ban concurrency contractually |
| `roles.<role>.account` | string | P | hard/soft per §5.3 | `orchestrator`, `executor`, `watcher`, `doctor` all → the first account whose `roles` admits them | W§4 | R1-07 [195]/[270]. Roles named from his own words: контекст вочер, оркестратор, екзек'ютор [204], and *«агента раз в N годин на якійсь іншій підписці»* [246] |
| `roles.<role>.model` | string | P | soft | `orchestrator`/`executor`: the platform default · `watcher`: **the cheapest model the adapter reports** · `doctor`: the cheapest | — | Д8 [466]: *«немає сенсу перевіряти фейбл моделю… чи змінився якийсь тікет»* |

### 4.3 Engine — the process the orchestrator drives (R1-03)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `engine.kind` | `gsd\|custom\|<adapter id>` | P | next-run | **none — the one key with no default** | W§2 / **PF exit 3** | R1-03 [118]: the orchestrator drives a process he chose; inventing one would be the plugin owning the process, which he forbade |
| `engine.definition` | path | P | next-run | *unset*; required when `kind: custom` | W§2 | [118]: *«може налаштовуватись з допомогою якогось ямл файлу, де будуть приписуватись ці кроки»*, hedged with «Можливо, не так» |
| `engine.step_boundary` | string (predicate id) or `turn.completed` | P | soft | the engine descriptor's own step point; `turn.completed` when it has none | — | R1-08 [209]: *«Лише поточного кроку, але це можна налаштовувати, людина може сама налаштувати, що це означає»* |
| `engine.accounting` | `reference\|supplement\|own` | P | soft | `reference` | W§2 | R1-06.3 [189]: *«лише записувати оце референс на те, що веде get shit done»* |
| `engine.mixing` | — | — | — | **not a key** | — | [118] *«комбінувати ні, тут або або»*. Declaring both `kind: gsd` and a non-empty `engine.definition` is a **load-time error**, not a merge (`ARCH-adapters` §9.3) |

### 4.4 Work source and readiness (R1-04, Д2)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `tickets.source` | `local\|connector` | P | next-run | `connector` when `connectors.tasks.use` is set, else `local` | — | [129] names both and prefers neither in the abstract |
| `tickets.local_dir` | path | P | next-run | `<project>/.orchestrator/tickets` | — | — |
| `tickets.ready_selector` | object `{kind: label\|status\|tag\|section, value}` | P | soft | `{kind:"label", value:"ai-ready"}` | W§3 | [145]: *«наприклад, AI ready, чи ще щось, я не знаю»* — his example, marked as an example |
| `tickets.ready_requires` | string[] (section headings) | P | soft | `["Outcome","Acceptance","Scope"]` | W§3 | [146]'s assignment — *«придумав якусь структуру, і її притримував»*. Value from `ARCH-minimal` §4, measured clean over 327 real tickets (CLAIMED) |
| `tickets.statuses` | map | P | next-run | `{ready:"ready", in_progress:"in progress", done:"done"}` | W§3 | [153]: names overridable, adapting to the chosen process |
| `tickets.writeback` | bool | P | soft | `true` | — | [149] is ratified (*«Так…»*, `corrections.md`): the board is *«помічник для цього оркестратора, щоби ставити статуси таскам, залишати якісь коментарі»* |
| `tickets.writeback_evidence` | `readback\|none` | P | soft | `readback` | — | a 200 is not evidence a transition applied (`ARCH-reliability` I4); and the readback digest is what keeps the tool's own write from firing its own change detector |
| `tickets.intake` | `open\|capped\|frozen` | P | hard | `open` | — | Д2 [422] is unconditional — *«AI бере це завдання, і виконує»*. I follow `JUDGE-fidelity` against `ARCH-adapters`' cap |
| `tickets.intake_cap` | int | P | hard | `0` (unbounded) | — | the brake exists; it is off |
| `tickets.notify_on_queue_growth` | int | P | hard | `50` | — | the 236 → 327 overnight growth that needed a human to brake it (CLAIMED, FIELD-NOTES §10.1) — as a notification, not a brake |
| `tickets.description_sufficiency` | `off\|mark_needs_review` | P | soft | `off` | — | Д2 [422] is *«точно не знаю»* twice (`corrections.md` §B). Shipping it on would be inventing a process he explicitly had not designed |
| `tickets.change_watch` | `off\|on` | P | soft | `on` | — | Д8 [466]: the orchestrator watches the active ticket's source |
| `tickets.change_watch_tiers` | bool | P | soft | `true` | — | Д8 [466]: *«в нормальному рані, якщо нічого не змінилось, то цей агент просто нічого назад не поверне»* — tier 0 `stat`/ETag, tier 1 body hash, tier 2 the cheap model on the diff only (`JUDGE-fidelity` G8) |

### 4.5 Concurrency and worktrees (R1-05, Д4)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `lanes.max` | int | P | `hard` down / `soft` up | `2` | — | [163] *«Людина сама може визначати»*; two lanes ran cleanly (CLAIMED, FIELD-NOTES §9.3) |
| `lanes.max_per_account` | int | P | `hard` down / `soft` up | `0` (unbounded) | — | some providers ban concurrency; `0` keeps the ceiling in `providers.*` |
| `lanes.max_heavy` | int | P | soft | `1` | — | two concurrent image builds OOM-killed his own container (CLAIMED, FIELD-NOTES §5.1). **Flagged §12.10** — adjacent to the machine-resource axis he retracted at [163] |
| `lanes.respect_dependencies` | bool | P | soft | `true` | — | [160]: a task blocked by an unfinished predecessor is not taken |
| `worktree.enabled` | bool | P | next-run | `true` | — | Д4 [433]: *«Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі»* |
| `worktree.owner` | `orchestrator\|engine` | P | next-run | `orchestrator` | W§6 | Д4 [433] is his default. GSD claims workspace ownership, and *«з цим треба поєднювати»* is an assignment he gave, not a decision he made — §13 |
| `worktree.base_ref` | string | P | next-run | the repo's default branch | — | [433] *«щоби це ворк трі був з головної гілки»* |
| `worktree.env_proof` | string[] (commands) | P | next-run | `[]`, and **preflight warns when empty and `worktree.enabled`** | W§6 | [433] *«постійно переконуватись, що всі ті енвайрмент верібли, які потрібні, вони запущені»* |
| `worktree.remove_on_done` | bool | P | soft | `false` | — | removing a tree with uncommitted work; preflight lists leftovers instead |

### 4.6 Run mode and authority (R1-14, R1-02)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `run.mode` | `ask\|autonomous\|controlled` | P | next-run | `controlled` | — | [075] names exactly these three and no default. `ask` cannot be the default because a 04:00 restart has nobody to ask |
| `run.mode_when_no_tty` | `autonomous\|controlled` | P | next-run | `controlled` | — | what `ask` degrades to; the cautious half |
| `authority.may_decide` | bool | P | hard | `false` | W§5 | [082]: *«має налаштовуватись, чи агент може щось вирішувати чи ні»* — a permission he described as a setting starts off |
| `authority.basis` | subset of `rules\|tone_of_voice\|past_answers\|project_knowledge` | P | hard | `[]` | W§5 | [087]/[094], ratified at [101] |
| `authority.tone_of_voice_path` | path | P | soft | *unset* | W§5 | [094]: *«людина створила tone of voice своїх рішень»* |
| `authority.may_force_stop` | bool | P | hard | `true` | — | [082]: the agent may force a hard stop even in an autonomous run. **Unratified** (`corrections.md` §C [085]→[087]) |
| `authority.autonomous_ops` | string[] | P | hard | `["*"]` | W§5 | R1-02 [107]: *«людина повинна сама налаштовувати, що саме вона може віддавати на автономне виконання»* |
| `authority.owner_gated` | string[] | P | hard | `["production_deploy","destructive_write","secret_required"]` | W§5 | **his own prior words**: this list is copied from the `guardrails.owner_gated` he wrote by hand in `plugins/harness/templates/project-config.example.json` (VERIFIED) |

### 4.7 Capacity and limits (R1-06)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `capacity.mode` | `soft\|hard` | P | hard | `soft` | — | [171]'s pair; soft is the one that does not interrupt a step |
| `capacity.soft_pct` | int | P | hard | `80` | — | **his own number** [171] |
| `capacity.hard_pct` | int | P | hard | `95` | — | above his 80, because he used 80 for both |
| `capacity.on_soft` | `stop_new\|save_and_close` | P | hard | `stop_new` | — | `save_and_close` is the intermediate mode he floated and left OPEN at [171] with «не знаю». Shipped, off |
| `capacity.on_unknown` | `hold_dispatch\|proceed` | P | hard | `hold_dispatch` | — | inverts the shipped `proceed` that made the previous limiter provably inert for days (CLAIMED, FIELD-NOTES §11.7) |
| `capacity.unknown_grace_minutes` | int | P | hard | `30` | — | `hold_dispatch` silently idling a whole night on one 429 |
| `capacity.poll_min_seconds` / `.burst` | int | P | soft | `3600` / `2` | — | a measured one-call `rate_limit_error` on the usage endpoint with four standing pollers on this machine (CLAIMED, C4-A3) |
| `capacity.resume_margin_seconds` | int | P | soft | `120` | — | resuming one second before the window actually rolls |
| `capacity.buckets` | — | — | — | **not a key: enumerate, never name** | — | take every bucket carrying a utilization and act on the **worst**. Z.ai's `TOKENS_LIMIT` → `CREDIT_LIMIT` rename rendered 0 % used, which reads as plenty of room (CLAIMED, `ARCH-adapters` §4.5) |
| `capacity.threshold_bucket` | string | P | hard | *unset* | — | when set and the provider stops reporting that bucket, it is a **configuration error** surfaced at preflight and again on the first tick that cannot find it — never a silent no-op (`ARCH-minimal` §5.1) |
| `capacity.reserve_pct` | int | P | soft | `0`, **flagged** | — | a reserve on an account he also works in was never put to him (CLAIMED, `extract/meta.md` G3). §14 Q11 |
| `capacity.spend_ceiling_usd` | number\|null | P | soft | `null`, **and preflight refuses to start when any lane's `capacity_model` is `credit`** | W§7 | a credit lane has no reset to wait for; the model is money, not time |

### 4.8 Context (R1-08)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `context.basis` | `raw_window\|usable_after_reserve\|statusline` | P | next-run | `raw_window` | W§7 (prints both numbers) | two percentages ~13 points apart on his machine (CLAIMED, C5-A2). Diverges from `JUDGE-fidelity` G10, which wanted it required — §0 |
| `context.threshold_pct.<role>` | int | P | soft | `executor: 75`, `watcher: 85`, `orchestrator: 66` | W§7 | [204]: *«Людина може налаштувати, при скількох відсотках відбувається компакт»*, per session and per provider |
| `context.threshold_pct.<platform>.<role>` | int | P | soft | falls back to the role value | — | [204] *«для всіх сесій, або для окремого провайдера по-іншому»* |
| `context.mode` | `soft\|hard` | P | soft | `soft` | — | [204]'s pair; hard mode has no external trigger at all on four platforms (CLAIMED, `ADAPTER-CONTRACT` §3 D) |
| `context.mode_fallback` | `reseed\|none` | P | soft | `reseed` | — | keeps the *outcome* guarantee [204] demands where the *action* is impossible |
| `context.command.<platform>` | string\|null | P | soft | the adapter manifest's own compaction op; `null` = close-and-reseed | W§7 | [204]: *«якою командою, чи це офіційна… чи це кастомний скіл»* — **his key** |
| `context.post_compact_prompt` | string\|null | P | soft | the red-line re-injection (the contents of `redlines.path`, truncated to `redlines.max_bytes`) | — | [204]: *«чи відправляється якийсь промпт одразу після компакту, чи ні»* — **his key**, and all four designs turned it into behaviour or dropped it (`JUDGE-fidelity` §5.3) |
| `context.orchestrator_on_threshold` | `compact\|fresh_session` | P | soft | `compact` | — | [204]: *«як компактити, так і запускати повністю новий оркестратор… людина може це налаштовувати»* — the configurable `JUDGE-fidelity` says all four lost |
| `context.verify_timeout_s` | int | P | soft | `600` | — | believing a compaction that did not happen; ~7 minutes measured for 67 % → 0 % (CLAIMED, `ARCH-operability` §15) |
| `context.refill_rate_alarm_pct_per_hour` | int\|null | P | soft | `15` | — | the 445k-token `echo idle` lane — 3,466 of 3,626 Bash calls, 77 % of all context growth in that window (CLAIMED, FIELD-NOTES §3.1). A **defect** predicate, not a compaction predicate |
| `context.on_terminal_state` | `fresh_session\|hold` | P | soft | `fresh_session` | — | three verified dead-ends where `/compact` can never work again (CLAIMED, `ARCH-adapters` §17) |

### 4.9 Liveness, health, recovery (R1-09, R1-10)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `liveness.silence_minutes` | int | P | hard | `20` | — | the previous generation's `stall_minutes`; long enough not to fire on a 14-minute suite |
| `doctor.enabled` | bool | P | next-run | `true` **when `doctor.account` resolves to an account different from `roles.orchestrator.account`; otherwise `false` with a preflight warning naming the cost** | W§4 | [246]: *«запускати якогось агента раз в N годин на якійсь іншій підписці»*. `ARCH-minimal` ships it off, which `JUDGE-survival` calls a restatement of the failure; the conditional makes the safe path the default wherever it is possible |
| `doctor.account` | string | P | next-run | the first account whose `roles` admits `doctor` and which is not the orchestrator's | W§4 | [246] |
| `doctor.interval_hours` | number | P | soft | `2` | — | a 4-hour window swallows an 85-minute loop whole (CLAIMED, C6-A10) |
| `warden.enabled` | bool | P | next-run | `true` | — | a dead orchestrator flagged itself 1,085 times over about five days, unresolved (CLAIMED, FIELD-NOTES §11.1) |
| `warden.interval_seconds` | int | P | next-run | `120` | — | observed peaks before an escalation fired: 2,808 s and ≈12.4 h (CLAIMED, FIELD-NOTES §10.1) |
| `warden.env` | map | P | next-run | `{PATH, CLAUDE_CONFIG_DIR, GH_CONFIG_DIR}` captured at install | — | three detached scripts had to export their own `gh` account because launchd and `nohup` start with no environment (CLAIMED, FIELD-NOTES §12.4) |
| `warden.on_unknown` | `notify_and_hold\|takeover` | P | soft | `notify_and_hold` | — | a live process that did not hold the lock is a contradiction; holding and telling him beats picking a story |
| `recovery.sources` | ordered subset of `state_files\|engine_state_ref\|resume_by_id\|transcript\|re_dispatch` | P | soft | all five, in that order | W§8 | [293]/[307]: state files are the default, the user configures which options are allowed, the orchestrator picks |
| `recovery.probe.<platform>` | probe object (§4.13) | P | soft | the adapter's own | W§8 | [310]/[312]: *«для кожної платформи можна налаштовувати, як саме буде робитись відновлення… може написати свої власні скіли»* |
| `crashloop.n` / `.window_minutes` | int | P | soft | `3` / `15` | — | N claims in T minutes with no result between is a restart loop, findable by `grep` — his own *«нескінченний цикл оркестраторів»* [300] made detectable |
| `claim.stale_minutes` | int | P | soft | `45` | — | releasing a claim from a healthy lane mid-long-turn |

### 4.10 Stops, failures, behaviour (Д12, Д5, Д7, Д9, Д10)

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `stops.custom.<name>` | object `{kind: rules\|commands, text?, steps?}` | P | soft | `{}` | W§12 | Д12 [524]: *«прочитати що це означає і відповідно зробити… Там можуть бути текстописні правила чи команди»* — both shapes, under one name |
| `stops.custom_timeout_s` | int | P | soft | `120`, then falls back to `stop-soft` | — | a custom stop that silently does nothing is worse than a blunt one |
| `stops.hard_deadline_s` | int | P | soft | `30`, then SIGKILL the recorded process group | — | a lane that will not die must not hold the night |
| `stops.ack_timeout_s` | int | P | soft | `20` (two polls) | — | §5.5 step 9's exit-8 boundary |
| `failure.identical_limit` | int | P | hard | `3` | — | **his number** [442] |
| `failure.action` | `notify_and_stop\|stop\|park` | P | hard | `notify_and_stop` | — | [442] offers exactly two and reserves the rest to him. `park` exists and is off — §0 |
| `failure.durable_across_restarts` | bool | P | soft | `true` | — | a retry budget that resets on every crash is not a budget |
| `behaviour.when_only_human_blocked` | `wait\|finish\|ask` | P | hard | `wait` | — | Д7 [455]: *«по дефолту я б рекомендував, що він залишається та чекає на мої відповіді»* — **his own recommendation** |
| `behaviour.wait_max_minutes` | int | P | hard | `0` (forever) | — | his recommendation carries no deadline |
| `behaviour.on_change_after_done` | `new_ticket\|adapt\|restart\|orchestrator` | P | hard | `new_ticket` | — | Д9 [482]: *«оркестратор задати перевагу тому, щоб зробити новий тікет»* |
| `behaviour.on_change_mid_execution` | `adapt\|restart\|finish_then_new_ticket\|orchestrator\|ask` | P | hard | `orchestrator` | — | Д9 [482] gives the orchestrator the mid-execution call first, then lists the overrides |
| `behaviour.on_restart_with_live_executors` | `orchestrator\|stop\|wait` | P | hard | `orchestrator` | — | Д10 [497]: the orchestrator analyses and decides within its permissions |

### 4.11 Delivery, questions, runtime, notifications, red lines

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `delivery.mode` | `pr_only\|direct\|human` | P | soft | `pr_only` | W§8 | R1-12 [331]: *«можна зробити тільки пул реквести»* as the repository rule he must not break. On his own repos no machine source states the rule — `gh api …/rulesets` → `[]`, `…/branches/main/protection` → 404 — while `CLAUDE.md` says PR-only (CLAIMED, C9-A3) |
| `delivery.stacked_prs` | bool | P | soft | `false` | — | [331] allows stacking; `--update-refs` needs git ≥ 2.38 and this machine has **2.33.0** (VERIFIED today) |
| `delivery.evidence` | `observed\|reported` | P | soft | `observed` | — | a merge that printed `Already up to date` on the phase branch against itself and read as success (CLAIMED, FIELD-NOTES §4.1). `observed` = `git merge-base --is-ancestor` plus the host's own merged state, two independent oracles |
| `delivery.respect_repo_rules` | bool | P | soft | `true` | — | [331] — *«це дуже важливо розуміти та приймати»* |
| `questions.poll_seconds` | int | P | soft | `30` | — | Д6 [449]: *«це скоро потрапить в оркестратор»* is a feeling about latency, not a guarantee |
| `questions.answer` | `never\|when_native\|always` | P | soft | `when_native` | — | R1-11 [324]: the orchestrator may answer a session's own question, *«в межах налаштованих повноважень»* [325], ratified at [328]. `when_native` = only where the platform has a typed answer channel; a keystroke with no receipt is not an answer |
| `questions.authority` | `refuse_and_escalate\|bounded\|full` | P | hard | `refuse_and_escalate` for irreversible external effects | W§5 | the ratified qualifier at [325]/[328] authorises bounded authority. (`ARCH-adapters` grounded the same default in a miscitation — `JUDGE-fidelity` §3; the default is right, the ground is [328]) |
| `runtime.<platform>.visibility` | `interactive\|headless\|hybrid\|mostly_interactive` | P | next-run | `mostly_interactive` | W§6 | R1-11 [324] lists exactly these and warns *«з цим треба бути дуже обережним»* about headless. `mostly_interactive` = interactive wherever the adapter reports an attachable pane or native intervention, headless only where it does not. Diverges from `ARCH-minimal`'s headless-first, which `JUDGE-fidelity` calls its largest deviation |
| `runtime.pty.backend` / `.host` | string | P | next-run | `tmux` / `iterm2-if-present` | — | every recorded AppleScript delivery failure (CLAIMED, FIELD-NOTES §1.3) |
| `notify.events` | string[] | P | soft | `["run.ended","run.holding","capacity.exhausted","control.invalid","failure.exhausted","teardown.orphan","question.raised"]` | W§9 | R1-17 [395]: *«Людина налаштовує, які типи можуть приходити»*. The list is printed at the end of the wizard for him to cut |
| `notify.probe_message` | bool | P | soft | `true` | — | R1-17 [395]: *«повинен лише переконатися, що це працює»* — which requires sending one real message, which is output Д11 [508] did not ask for. `false` keeps Д11 absolute and downgrades the proof to `unprovable` |
| `notify.max_per_run` / `.coalesce_minutes` | int | P | soft | `40` / `30` | — | 1,085 identical flags over five days (CLAIMED, FIELD-NOTES §11.1) |
| `status.during_run` | `silent\|line_per_tick` | P | hard | `silent` | — | Д11 [508]: *«оркестратор не повинен нічого виводити для мене»*, made configurable at [512]/[514] |
| `status.output` | `minimal\|normal\|verbose` | P | hard | `minimal` | — | Д11 [512]: *«Дефолтний варіант, що оркестратор використовує мінімальну кількість аутпуту і стокінгів»* (quoted with the voice garble intact, as `ARCH-minimal` does) |
| `redlines.path` | path | G | hard | `<project>/.orchestrator/RULES.md`, resolved from the **main checkout** | W§10 | R1-15 [357]: *«Достатньо лише одного файлу… Має бути якісь визначене місце»*. Main-checkout resolution because a worktree copy hid an owner-facing question for an hour (CLAIMED, FIELD-NOTES §12.5) |
| `redlines.apply` | `next_launch\|now` | P | hard | `next_launch` | — | applying *now* to a live session requires a re-seed; quiet by default |
| `redlines.max_bytes` | int | P | soft | `8192` | — | a prohibitions file too large to re-inject after every compaction |
| `redlines.enforce` | bool | P | next-run | **`false`** | — | R1-15 [357]: *«На окремо якогось обов'язкової процедури для цього не треба»*. Implemented literally. §12.8 prices it |
| `session.permissions` | `inherit\|bypass\|acceptEdits\|dontAsk` | P | next-run | `inherit` | — | R1-15 [357]: *«технічні обмеження середовища користувач за потреби налаштовує сам»*. Corrects the shipped `bypass` (VERIFIED in `templates/user-config.example.json`) |

### 4.12 The control plane's own knobs

| Key | Type | File | Apply | DEFAULT-PROPOSED | Asked | Rationale |
|---|---|---|---|---|---|---|
| `tick.interval_seconds` | int | P | hard | `60` | — | a tick loop cheap enough to run all night with no model in it |
| `control.poll_seconds` | int | P | hard | `10` | — | worst-case stop latency; one `stat` per poll is free (`ARCH-adapters` §3.4) |
| `control.debounce_ms` | int | P | hard | `750` | — | a half-written hand-edit read mid-save |
| `control.max_bytes` | int | P | hard | `65536` | — | one `read(2)` and one hash; a control file larger than this is a mistake |
| `control.lock_timeout_s` | int | P | hard | `10` | — | a stale writer must not block a stop |
| `control.on_invalid` | `keep_last_good\|hold_dispatch` | P | hard | `keep_last_good` | — | E6. `hold_dispatch` exists for someone who would rather idle than run on a stale document |
| `control.stale_revision` | `refuse\|apply` | P | hard | `refuse` | — | E7's fourth row: `git checkout` restores old content with a new mtime |
| `judge.max_calls_per_tick` / `_per_hour` | int | P | hard | `1` / `30` | — | Д11's token concern made mechanical |
| `judge.max_wakes_per_hour` | int | P | hard | `12` | — | bounds the **loop**, which a bill does not: the 85-minute Escape-and-`continue` loop fed by the orchestrator's own wrapped prose (CLAIMED, FIELD-NOTES §11.6) |
| `judge.on_unparseable` | `defer\|escalate` | P | hard | `defer` | — | waiting is the fail-safe everywhere |
| `journal.line_bytes` | int | P | soft | `4096` | — | one enormous line making the journal unreadable by `jq` |
| `runs.retain` | int | P | soft | `20`, pruned at run **start** | — | never clean up the post-mortem of the night that just failed |
| `adapters.verify_max_age_hours` | int | P | soft | `24` | — | one platform shipped five releases in fifteen hours (CLAIMED, `ARCH-adapters` §17) |

### 4.13 Two object shapes used above

**A probe** is data, never code — R1-10 [310]/[312] made mechanical (`JUDGE-fidelity` G4, from
`ARCH-adapters` §4.4). The supervisor executes it and holds no platform knowledge itself.

```json
{
  "cmd": ["claude", "agents", "--json"],
  "env_from": "accounts.<profile-B>",
  "timeout_s": 20,
  "match": { "sessionId": "${session_id}" },
  "alive_when": "row present",
  "status_field": "status"
}
```

An owner-written skill is a legal probe: `{"cmd":["claude","-p","/my-recovery-skill"], …}`. That is
[312] — *«може написати свої власні скіли»* — as a config entry rather than a code change.

**An adapter registry entry** lives in the plugin file, not in `recommended.json`:

```json
{ "adapters": { "claude-code": { "path": "builtin", "verified_at": "2026-09-19T21:00:00Z" },
                "my-thing":    { "path": "<project>/.orchestrator/adapters/my-thing" } } }
```

Discovery order mirrors the config bands: `<project>/.orchestrator/adapters/` › `<config-root>/orchestrator/adapters/` › shipped.

### 4.14 Validation rules

Applied at resolution (§2.4 step 8) and again by `/orchestrator:config --check`.

1. **Type and enum.** A value of the wrong type or outside its enum is a warning, the key falls back
   to the next layer down, and the fallback is recorded in `provenance` with `"invalid_at_layer": n`.
   A config never fails over one key (OWNER-DECISIONS 4.9's principle, generalised).
2. **`use` is an object.** A string, including the bare string `"auto"`, is a validation error
   (OWNER-DECISIONS 4.8, 4.13). `{ "kind": "auto" }` and an absent `use` both mean detection.
3. **Values inside `use` are open.** A `kind` nobody has heard of takes the ordinary path; typos are
   not handled (OWNER-DECISIONS 4.6). Do not validate against a list of known vendors.
4. **Unknown keys inside `connectors.<source>`** other than `use`, `never`, `fallback`, `x-*` are an
   error: warn, naming the key and the file, and keep the value out of the resolved config.
5. **`x-*` keys** are accepted anywhere and combine like any other key.
6. **The no-mixing rule** (§4.3) and **the ambiguous-`hard` rule** (§5.6) are load-time errors, not
   warnings. They are the only two.
7. **Referential checks**: every `roles.<role>.account` names a declared account; every declared
   account names a declared platform; `doctor.account` differs from `roles.orchestrator.account`.
   A failure here is a preflight refusal (§7), not a resolution error — the resolved config is still
   produced so `--show` can explain it.

---

## 5. The control file

### 5.1 Path, and why the state lives outside the work tree

```
$ORCHESTRATOR_STATE_DIR                      default: $HOME/.orchestrator      (VERIFIED: expanded, never a literal ~)
  locks/<sha1(project-root)>.lock.d/         the project lock (§5.4)
  runs/index.tsv                             run-id \t project \t run-dir \t created_at \t state
  runs/<run-id>/
    control.yaml                             ← THE watched file
    control.yaml.lock.d/                     the writer lock
    control.applied.json                     the reader's own state: last good document + revision
    control.ack.json                         the reader's reply to the last read
    config.resolved.json                     §2.4, with per-key provenance
    config.sources.json                      the six paths + (sha256, mtime, size) at last read
    run.json                                 layer 7, immutable
    journal.ndjson                           append-only; carries the control audit (§5.10)
    status.json                              atomic rewrite each tick
    preflight.json  plan.json                the proof table and the negotiated plan (§7)
    trips/<sha>.json                         detector watermarks, created O_EXCL
    lanes/… capacity/… owned.ndjson          (outside this document's scope)

<project>/.orchestrator/                     created by /orchestrator:init
  RULES.md                                   R1-15 red lines — COMMITTED
  processes/*.yaml                           custom engine definitions — COMMITTED
  tickets/*.md                               local registry — COMMITTED
  QUESTIONS.md                               Д6 default channel — COMMITTED
  .gitignore                                 ignores current, control.yaml, adapters/
  current        → $STATE/runs/<run-id>      symlink, for him
  control.yaml   → $STATE/runs/<run-id>/control.yaml   symlink, for him
```

**Run state is under `$HOME`, not in the repository.** Д4 [433] makes a worktree per task the default;
a worktree is a separate checkout, so anything kept in the repository forks per lane and the copies
diverge. This is measured, not theoretical: a questions file and a journal forked into a worktree's own
copy with a real owner-facing question invisible for an hour, and one dirty tracked file is exactly
what made a merge print success and move nothing (CLAIMED, FIELD-NOTES §12.5, §4.1).

**The two symlinks exist because he hand-edits this file at 02:00** and
`$HOME/.orchestrator/runs/<work-project>-20260919-224100Z/control.yaml` is not a path anyone types. Rules
for them:

1. Created by the supervisor at run start; removed at run end.
2. Every writer calls `realpath` first and writes to the **real** path. The atomic rename must never
   land on a symlink.
3. The lock directory sits beside the real file, never beside the symlink.
4. `<project>/.orchestrator/.gitignore` lists `current`, `control.yaml`, `adapters/` so the symlinks
   never reach a checkout. `RULES.md`, `processes/`, `tickets/` and `QUESTIONS.md` are tracked — they
   are project content, not run state.

### 5.2 One file, three jobs — and the one he keeps separate

He named a watched file three times, in three items, and never said they were the same file:
account assignments (R1-07 [195]), stop commands (Д12 [520]), behaviour overrides (Д7 [458]).
`ANALYSIS-01`'s cross-cutting finding 2 says exactly that.

**Decision: one file.** A second watched file is a second place for a stop to get stranded, and the
recorded failure mode is precisely a channel forking and going unread. Recorded as a tension in §12.5.

**Д6's questions channel is not this file and must not be folded into it.** [449] is explicit that it
may be a GitHub issue with a tag, a task in the tracker, or a local file, and that *«місце
визначається користувачем»*. It is a connector (§4.1), watched on its own cadence
(`questions.poll_seconds`), mirrored into `runs/<run-id>/questions/` so a channel outage does not lose
a question.

**`redlines.path` is a third watched surface**, also not this file: it is committed project content
that outlives the run.

### 5.3 The document

Format: **YAML, restricted to a strict subset** (§5.8). One document. Annotated, because he reads it
at 02:00 and a header comment is the difference between an informed edit and a guess.

```yaml
# .orchestrator/control.yaml — read every 10 s. Hand-edit freely.
# Changes apply by class: hard = next poll · soft = next safe boundary · next-run = refused, told to you.
# Deleting a key here restores the value your config files resolve to. Nothing here survives the run.
schema: 1
revision: 7                      # commands bump this; a hand edit may leave it alone

stop:                            # Д12 [520],[524]
  verb: null                     # null | hard | soft | custom
  custom: null                   # names a key under stops.custom.<name>; ignored unless verb: custom
  scope: run                     # run | lane:<lane-id> | ticket:<ticket-id>
  reason: ""
  author: ""                     # "cli:orchestrator:stop-soft" | "hand"
  at: null

pause:                           # not a stop: dispatch holds, lanes keep working, resume is symmetric
  active: false
  reason: ""

roles:                           # R1-07 [195]: role → account, re-read live
  orchestrator: { account: <profile-B>, apply: soft }
  executor:     { account: <profile-A>, apply: soft }
  watcher:      { account: glm-main,   apply: soft }
  doctor:       { account: codex-main, apply: soft }

behaviour:                       # Д7 [455],[458]: changeable DURING the run
  when_only_human_blocked: wait  # wait | finish | ask
  on_change_after_done: new_ticket
  on_change_mid_execution: orchestrator

intake: open                     # Д2 [422]: open | capped | frozen

overrides:                       # any ordinary config key from §4, by dotted path
  lanes.max: 1
  context.threshold_pct.executor: 70

x-note: "anything prefixed x- is preserved and ignored"
```

**The `overrides:` map is flat and dotted, not nested.** Two reasons, both practical: a dotted key is
unambiguous to diff leaf by leaf, and it makes `deleting a key restores the layer below` a one-line
operation rather than a structural merge. A nested form is rejected at validation with the dotted form
printed.

**Disjointness rule.** A key that has a dedicated section above — `stop`, `pause`, `roles`,
`behaviour`, `intake` — **may not also appear in `overrides:`**. The writer refuses (exit 65, naming
the section); the reader prefers the section, refuses the duplicate, and reports it under `rejected`.
Without this rule there are two authorities for one value inside one file and no rule that decides.

### 5.4 The lock — and a VERIFIED problem with every design's answer

All four designs say *take `flock`*. **There is no `flock(1)` on this machine** (VERIFIED today:
`which flock` → not found; macOS ships no such utility). `shlock(1)` exists at `/usr/bin/shlock`
(VERIFIED) and Python 3.9.6 is present (VERIFIED), but the dependency this plugin already has is
Node v22.18.0 (VERIFIED), required by OWNER-DECISIONS 5.1.

**So the lock is a directory, not a flock.** `mkdir(2)` is atomic on every POSIX filesystem
(INFERRED from POSIX; standard practice).

```
control.yaml.lock.d/            created by mkdir — creation IS acquisition
control.yaml.lock.d/holder.json {"pid":41233,"pid_start_ticks":"5081993","argv_sha256":"c1de…",
                                 "boot_id":"F1A0…","cmd":"orchestrator:stop-soft","at":"…"}
```

Acquire:

1. `mkdir` the lock directory. Success → write `holder.json`, proceed.
2. Failure → read `holder.json`. If it is absent or unparseable, wait 100 ms and retry (the holder is
   mid-write).
3. If the holder's `boot_id` differs from the current boot, or the `pid` is dead, or the pid is alive
   but its start time or argv digest do not match, the lock is **stale**: remove the directory and
   retry once. The identity triple is `ARCH-reliability` §3.5 and it is what makes PID reuse safe.
4. If all three match and the pid is alive, wait 100 ms and retry until `control.lock_timeout_s`.
5. On timeout: exit **75**, printing the holder's `cmd`, `pid` and `at`. Never break a live lock.

Release is `rm -r` of the directory, in a shell trap and in a Node `finally`, so a killed writer's
lock is stale rather than permanent.

**The same mechanism is the project lock** (`locks/<sha1(project-root)>.lock.d/`), which is how the
single-orchestrator invariant [300] — *«якщо раптом одночасно два якісь оркестратори працюють, то це
не окей. Це треба відслідковувати і не дозволяти»* — is enforced: the health check is *try to take the
lock*, with no TTL and no heuristic.

**The lock is a recommendation; the destination is not** (OWNER-DECISIONS 4.11's own rule, applied
here). On a filesystem where the directory cannot be created at all, the write still goes to the same
path, says so in one visible line, and only the lock is skipped.

### 5.5 Write protocol

Every writer — `/orchestrator:stop*`, `/orchestrator:set`, `/orchestrator:pause`,
`/orchestrator:resume` — follows this. The owner's editor follows none of it, which §5.9 step 7
handles.

1. Resolve the real path (`realpath`), refusing if the result is outside `$ORCHESTRATOR_STATE_DIR`.
2. Acquire `control.yaml.lock.d` (§5.4).
3. Re-read the file **under the lock**. Parse. If it does not parse, refuse with exit 65 and print the
   parse error — a command must not overwrite a document it cannot read, because the unreadable part
   may be his.
4. Apply a **leaf merge**, preserving comments, blank lines, key order and every key the writer does
   not recognise, at every depth.
5. Refuse, before writing, anything §5.6 forbids: an unknown enum value, a `next-run`-class key in
   `overrides:`, a key that duplicates a dedicated section, an ambiguous bare `hard`.
6. `revision = revision + 1`.
7. Write `control.yaml.tmp.<pid>.<rand>` in the same directory, mode `0600`, then `fsync` the file
   **and its directory**.
8. `rename()` over the destination. `rename(2)` is atomic within a directory, so a reader never sees
   half a file and a writer killed before the rename leaves the previous file intact
   (OWNER-DECISIONS 4.11's own protocol, applied to run state).
9. Release the lock.
10. **Poll `control.ack.json`** until `applied_revision ≥ N` or `stops.ack_timeout_s` elapses. Exit
    **0** when the change was applied; **8** when it was written but not acknowledged, printing
    *"written to control.yaml (revision 13); the supervisor has not acknowledged it — run
    `/orchestrator:doctor`"*. This is the half the previous generation never had: two of his own
    instructions were recorded as delivered and never executed (CLAIMED, FIELD-NOTES §11.2).

### 5.6 Validation of a control document

Checked by the writer before writing and by the reader after parsing. Same rules, two chances.

| # | Rule | On violation |
|---|---|---|
| V1 | `schema` is an integer this build understands | reader: refuse the whole document, keep last good, notify. Writer: exit 65 |
| V2 | `revision` is a non-negative integer when present | treat as absent |
| V3 | **No bare top-level `hard` key.** `stop.verb: hard` stops; `roles.<r>.apply: hard` switches | writer refuses; reader refuses the key. His words collide at [171] and [195] and the file must not guess |
| V4 | Every enum value is in its domain | reject that key, keep the previous value, list under `rejected` |
| V5 | Every `overrides:` key exists in the §4 catalogue | reject that key with `reason: unknown-key`. Unlike a config file, an unknown control key is a **typo at 02:00**, not a forward-compatible extension |
| V6 | No `overrides:` key is `next-run` class | reject with the file to edit named (E4) |
| V7 | No `overrides:` key duplicates a dedicated section | reject the `overrides:` copy (§5.3) |
| V8 | No `overrides:` value selects a tool an in-force `never` strikes | reject with the vetoing entry and its file named (E3) |
| V9 | `stop.verb: custom` names an existing `stops.custom.<name>` | reject; **fall back to `stop-soft`**, loudly — refusing to stop at all is the worse failure |
| V10 | Document ≤ `control.max_bytes` | refuse the read, keep last good, notify |
| V11 | `x-*` keys anywhere | accepted, preserved, ignored |

### 5.7 Apply classes

Three classes, using his own two words plus the honest third. Every key in §4 carries exactly one, in
the **Apply** column; the catalogue is the only source of a key's class and a key not in the catalogue
has no class and cannot be set (V5).

| Class | Meaning | Applied | Examples |
|---|---|---|---|
| **`hard`** | act now, interrupting running work if it must | the next poll (≤ `control.poll_seconds`) | `stop`, `pause`, `roles.*` with `apply: hard`, `behaviour.*`, `intake`, `lanes.max` **downward**, capacity and context thresholds, `judge.*`, `redlines.*` |
| **`soft`** | at the next safe boundary — the next dispatch for run-scoped keys, `engine.step_boundary` for lane-scoped ones | the next boundary | `roles.*` with `apply: soft` (the default), `lanes.max` **upward**, `roles.*.model`, `context.command.*`, `worktree.remove_on_done`, `notify.*` |
| **`next-run`** | cannot change while this run exists | never; recorded and reported | `engine.*`, `tickets.source`, `connectors.*.use` for tasks and questions, `worktree.enabled/owner/base_ref`, `runtime.*`, `run.mode`, `context.basis`, `warden.*`, `doctor.enabled` |

This is R1-07's soft/hard vocabulary [195] generalised, which `ANALYSIS-01`'s cross-cutting finding 3
asks for. `next-run` is the case he never named, and it is not a design preference: changing a
*running* session's account is impossible on every platform examined (CLAIMED, `ADAPTER-CONTRACT` §3
F); `context.basis` mid-run would make every threshold in the journal incomparable; `engine.kind`
mid-run would leave half a ticket planned by one process and half by another.

**Sortie is the precedent and the reason to publish this table**: the best config reload in the field
is good precisely because it documents the keys that deliberately do *not* rebuild (CLAIMED,
`LANDSCAPE.md` §5).

**`lanes.max`'s split class** is the one asymmetry: a reduction is a brake and is `hard`; an increase
is an opportunity and is `soft`. Stated here rather than inferred, because an implementer reading one
row would get it wrong.

### 5.8 The YAML subset, and the parser

He named YAML once, at [118], and for the **custom process definition**, not for this file, and
hedged it — *«Можливо, не так, тут треба буде подумати, як саме»* (VERIFIED). So YAML here is my
choice, for one reason: he hand-edits this file and comments are what make an edit informed. It is
§14 Q1.

The cost is a parser. Node has no built-in YAML, and a dependency is exactly what `JUDGE-cost` ranked
`ARCH-minimal` first for avoiding. The answer is a **strict subset**, parsed by a vendored reader of
roughly 150 lines with no npm dependency, and emitted by the writer so a command-written file is always
in the subset:

- block mappings and block sequences, two-space indentation, `#` comments to end of line;
- scalars: plain, single-quoted, double-quoted, `|` and `>` block scalars;
- `null`, `true`, `false`, integers, floats, ISO-8601 timestamps as strings;
- empty flow forms `[]` and `{}` only.

**Rejected outright**, each with a message naming the line: anchors and aliases (`&`, `*`), merge keys
(`<<`), multi-document (`---`), tags (`!!`), non-empty flow collections, tabs for indentation. A
rejected construct is a parse failure and takes the E6 path — last good stays.

`/orchestrator:config --check` runs the same parser against the current file, so he can validate
before saving somewhere that matters.

### 5.9 Read protocol — one poll, in order

Runs every `control.poll_seconds` in the supervisor. Steps 1–3 cost one `stat` and nothing else; the
loop is free when nothing changed.

1. `stat` `control.yaml`. Record `(mtime_ns, size, inode)`.
2. Unchanged from the last poll → **return**. (This is [195]'s mtime, used as the gate he suggested.)
3. Changed → if `now − mtime < control.debounce_ms`, **return** and re-check next poll. A hand-edit
   half-written is the common case and a parse failure that resolves itself in 750 ms should never
   reach a notification.
4. Read at most `control.max_bytes`. Compute `sha256`.
5. `sha256 == control.applied.json.doc_sha256` → record `control.touched`, update the stat cache,
   **return**. This closes two cases at once: the supervisor's own write, and an editor that rewrote
   the file without changing a byte of content. *mtime is the gate; the hash is the decision* —
   which honours [195]'s hedge («Можливо, там, наприклад, по даті») without hardening it into the
   mechanism, and survives the cases mtime alone does not (`git checkout`, write-and-rename,
   a partially written file).
6. Parse (§5.8). Failure → keep last good, write `control.ack.json` with `parse: "error"` and the line
   and column, append one `control.invalid` journal line, notify once per distinct error hash, set
   `status.json.control_error`, **return**. The run never stops on this path.
7. Decide on `(revision, sha256)` against `control.applied.json`, per E7's table: newer revision →
   apply; equal revision with different content → apply as a **hand edit**; older revision → refuse
   with `reason: stale-revision` when `control.stale_revision: refuse`.
8. Validate (§5.6). Rejected keys are collected, not fatal.
9. **Leaf-diff** the accepted document against `control.applied.json.document`. For each changed leaf,
   look up its class in the §4 catalogue.
10. **Directives** (`stop`, `pause`) are keyed by `(verb, scope, revision)`. Before acting, create
    `trips/<sha256(key)>.json` with `O_EXCL`. **A trip that already exists does not re-fire.** A
    ceiling answers "how much"; a watermark answers "again?" — and the recorded 85-minute loop was a
    re-fire of one detector on its own effect, not a volume problem (CLAIMED, FIELD-NOTES §11.6).
11. Apply `hard` leaves now. Queue `soft` leaves with their boundary predicate. Record `next-run`
    leaves as refused.
12. Write `control.applied.json` (atomic rename): `{schema, applied_revision, doc_sha256, applied_at,
    applied_seq, document}`.
13. Write `control.ack.json` (atomic rename) — §5.10.
14. Append one journal line per leaf — §5.10.
15. Update `status.json.control_*`.

**The config slots are gated on the same tick, not on this poll.** Once per `tick.interval_seconds`,
`stat` the six slot files plus `run.json`. On any `(mtime, size)` change, hash; on a hash change,
re-run the resolver, diff `config.resolved.json` key by key, and route each changed key through steps
9–15. Seven `stat` calls a minute, no model, no Node process unless something actually moved. That is
Д7 [458] and R1-07 [195] implemented for configuration as well as for control.

### 5.10 The audit record

Three artifacts, each answering a different question.

**`control.ack.json`** — *"did my command land?"* Rewritten after every read, atomically. Read by the
stop/set commands and by `/orchestrator:status`.

```json
{ "schema": 1,
  "read_at": "2026-09-20T02:14:08Z",
  "doc_sha256": "7f3c…",
  "revision": 13,
  "applied_revision": 13,
  "author": "cli:orchestrator:stop-soft",
  "parse": "ok",
  "applied":  [ { "key": "stop.verb", "from": null, "to": "soft", "class": "hard" } ],
  "deferred": [ { "key": "lanes.max", "from": 1, "to": 3, "class": "soft", "until": "next lane boundary" } ],
  "rejected": [ { "key": "engine.kind", "class": "next-run",
                  "reason": "takes effect on the next run — edit ./.claude/shared/plugins/orchestrator.local.json" } ] }
```

**`control.applied.json`** — *"what is actually in force?"* The reader's own state: the last good
document, its revision and its hash. **Written by the supervisor only.** The supervisor never writes
`control.yaml`, so there is no self-trigger loop — the previous generation's attention file had one
process as both writer and watcher and it destroyed a night of another process's writing (CLAIMED,
FIELD-NOTES §2.1).

**`journal.ndjson`** — *"what happened, and when?"* Append-only, `O_APPEND`, one fact per line, never
truncated, never globbed away, no lock. Six control record kinds:

```jsonc
{"seq":412,"at":"2026-09-20T02:14:08Z","kind":"control.read","revision":13,"doc_sha256":"7f3c…","author":"cli:orchestrator:stop-soft","changed":3}
{"seq":413,"at":"…","kind":"control.apply","revision":13,"key":"stop.verb","from":null,"to":"soft","class":"hard","result":"applied"}
{"seq":414,"at":"…","kind":"control.defer","revision":13,"key":"lanes.max","from":1,"to":3,"class":"soft","until":"lane-boundary"}
{"seq":415,"at":"…","kind":"control.refused","revision":13,"key":"engine.kind","class":"next-run","reason":"next-run key in overrides"}
{"seq":416,"at":"…","kind":"control.veto","key":"connectors.tasks.use","to":{"kind":"mcp","server":"clickup"},"vetoed_by":"never:mcp:clickup","source":"<config-root>/shared/identity.json"}
{"seq":417,"at":"…","kind":"control.invalid","parse":{"error":"mapping values are not allowed here","line":14,"col":9},"doc_sha256":"a91f…","result":"kept_last_good","last_good_revision":12}
```

Plus two for configuration: `config.reresolve` (which slot's hash moved, and how many keys changed)
and `config.slot_invalid`.

Every line carries `from` and `to`. That is the property that makes the record an audit rather than a
log: at 09:00 he can answer *"what did I change at 02:14, and did it take"* with
`jq 'select(.kind|startswith("control."))'` and no model. `/orchestrator:config --audit` renders the
same thing as a table.

**Retention.** The journal is never rotated inside a run. Runs are pruned by `runs.retain` (20) at the
**start** of a run, never at the end — never clean up the post-mortem of the night that just failed.

### 5.11 The single-writer table

Multiple writers to one file is the mechanism behind the recorded loss of a night's corrections
(CLAIMED, FIELD-NOTES §2.1). Every file has exactly one writer, named here, and a lint rule in the
test harness fails the build when a second component writes one.

| File | Writer | Readers | Mechanism |
|---|---|---|---|
| `control.yaml` | the owner's editor + `/orchestrator:*` commands | the supervisor | lock + atomic rename |
| `control.applied.json` | the supervisor | commands, `status` | atomic rename |
| `control.ack.json` | the supervisor | commands, `status` | atomic rename |
| `config.resolved.json`, `config.sources.json` | the supervisor | commands | atomic rename |
| `run.json` | `/orchestrator:run`, once | everyone | write once, then read-only |
| `journal.ndjson` | **any component**, append-only | everyone | `O_APPEND`, no lock, never truncated |
| `status.json` | the supervisor | `status` | atomic rename |
| `trips/*.json` | whoever fires the predicate | the supervisor | `O_EXCL` create |
| slots 1–6 | the person and the wizard | the resolver | lock + atomic rename (OWNER-DECISIONS 4.11) |

---

## 6. The config verb

A thin command plus a hidden skill (OWNER-DECISIONS 6.6). A `config` command is a strong
recommendation for any plugin holding user configuration (6.5); this one holds a great deal of it.

### 6.1 The surface

| Command | What it does | Model |
|---|---|---|
| `/orchestrator:config` | the wizard (§6.2) | yes, for explanation only |
| `/orchestrator:config --show [key]` | the effective value with provenance, layer by layer | **no** |
| `/orchestrator:config --explain <key>` | what it does, its type, its class, its default, which layer supplies it, what would change it | no |
| `/orchestrator:config --set <key>=<value> [--where <slot>]` | write one key to a config file (§6.4) | no |
| `/orchestrator:config --unset <key>` | remove one key from the file that supplies it | no |
| `/orchestrator:config --check [--file <path>]` | validate every slot and the control file; exit 0 or 65 | no |
| `/orchestrator:config --audit [--since <t>]` | render the control audit (§5.10) | no |
| `/orchestrator:config --promote <key>` | copy a value that proved itself in `control.yaml` into his own file | no |
| `/orchestrator:config --doctor` | re-prove what preflight proves, without starting a run | no |
| `/orchestrator:config --import-harness` | §10 | no |

`--show` with no key prints every key that is not at its default, then a count of the ones that are.
That is Д11's minimal-output rule applied to the config surface as well as to the run.

### 6.2 The wizard

Two rules from him govern it. [133] (ratified, *«Так, підтверджую»*): on a run, read global and
project settings, use what is there, **ask for what is missing** — *«це вже існуюча архітектура для
Клод Маркетплейсу»*. [189]: when it asks, it must **explain why it is asking** — *«він має чітко
пояснити, чому він це запитує»*. So every question carries a `why` string drawn from the key's
Rationale column in §4, and every stage can be skipped.

Algorithm:

1. Resolve the config (§2.4). Nothing is written yet.
2. Build the question set: every key marked `W§n` in §4 that is **missing**, plus — when invoked as
   `/orchestrator:config` rather than from a run — every key marked `W§n` that is **already set**.
   Re-asking whether what is set is still current is OWNER-DECISIONS 6.2, in his words: *«якщо щось
   вже визначено, то перепитати, чи це актуально»*.
3. Walk the stages in order. Each question shows: the key, what it is for, **why it is being asked**,
   the current value and which file it came from, the proposed default, and the consequence of
   leaving it unset.
4. Collect answers. **Write nothing until the end**, so an abandoned wizard changes nothing.
5. For each answer, resolve the destination file (§6.4), announce any shadowing, write under the lock.
6. Run `--doctor` (§6.5) and print the proof table.

The stages, and which of his items each discharges:

| Stage | Asks | Owner items |
|---|---|---|
| **W§1** | config root, project root, whether the six slots are where they should be | Д1 [416] |
| **W§2** | the engine: GSD, another marketplace's process, or a custom definition — **one, never a mix** | R1-03 [118] |
| **W§3** | where work comes from; the readiness selector; the readiness structure; the board's statuses | R1-04 [129],[145],[153] |
| **W§4** | providers, accounts, the switch mechanism per platform, role restrictions, and **proving the switch works** | R1-07 [199],[270]; R1-10 [246] |
| **W§5** | run mode; whether the agent may decide at all; on what basis; what is always owner-gated | R1-14 [075],[082]; R1-02 [107] |
| **W§6** | concurrency; worktrees and their base ref; the environment proof; session visibility per platform | R1-05 [163]; Д4 [433]; R1-11 [324] |
| **W§7** | capacity thresholds; context thresholds per role — **printing both percentage scales for a live session** | R1-06 [171]; R1-08 [204] |
| **W§8** | how work reaches the trunk; which recovery sources are allowed | R1-12 [331]; R1-10 [293],[307] |
| **W§9** | the questions channel; the notification channel and which events | Д6 [449]; R1-17 [395] |
| **W§10** | the red-line file: where it is, and that nothing enforces it | R1-15 [357] |
| **W§11** | status output during the run | Д11 [508],[512] |
| **W§12** | custom stops, if he wants any | Д12 [524] |

W§4 and W§9 are the two stages that **prove** rather than ask. R1-07 [199] requires the account switch
be shown working before a run; R1-17 [395] requires the same of the channel. The wizard performs both
there, so the proof is fresh at the moment of the decision rather than at 22:41.

### 6.3 What the wizard does when it cannot ask

An unattended run has no listener. OWNER-DECISIONS 4.5 already rules on the analogous case — *"A run
that cannot ask does not substitute; it skips the source with one visible line"*. So:

- **Interactive session**: ask, in one batch, with reasons.
- **No TTY**: do not ask, do not substitute. Preflight collects every missing **required** key and
  refuses with **exit 3**, naming each one and the command that would set it. In practice this is one
  key, `engine.kind` (§4.3).
- Missing **optional** keys never refuse; their defaults stand and `status.json.defaults_in_use` lists
  them.

### 6.4 Where an answer is written

`config-levels.md` §7's list, unchanged. Take the first line that matches and stop.

| | Case | Destination |
|---|---|---|
| 1 | one of his own files (slots 3, 4, 5, 6) already sets this key | that same file |
| 2 | the setting is usable by more than this plugin, or its reach is unclear | `<config-root>/shared/identity.json` (slot 3) |
| 3 | anything else | `<config-root>/shared/plugins/orchestrator.json` (slot 4) |

Four rules that come with it:

1. **The agent writes no committed project file.** Slots 1 and 2 change through the project's ordinary
   review. Where one of them holds the key, line 1 does not match and the answer lands in his own file
   — which is what overriding a committed value means.
2. **A write into a layer a higher layer would shadow is announced first**: the winning file is named
   and the choice is to write into that file instead, to write here anyway, or to cancel. Nothing is
   written until he chooses.
3. **The write protocol** is OWNER-DECISIONS 4.11: take `<destination>.lock` (here a lock directory,
   §5.4), re-read under the lock, merge into that read, preserve every unrecognised key at every depth
   including `x-`, create the directory and file where neither exists, replace atomically by a
   temporary file in the same directory renamed over the destination. Creating a `.local` file adds
   its `.gitignore` entry in the same write.
4. **The answer is always written, and always to the file the list resolves to.** A run never
   redirects an answer to an easier file and never drops it.

### 6.5 `--doctor` — "is my config still true?"

Zero model, no run started. Re-proves the things that decay: every account's switch mechanism actually
switches (from the platform's own report, never from the command's exit code); the board is reachable
and carries the configured statuses; the questions channel is writable; the notification channel
delivers when `notify.probe_message`; `redlines.path` exists and is readable from the main checkout;
`worktree.base_ref` resolves; each account's capacity endpoint returns something parseable; the
adapter verifications are within `adapters.verify_max_age_hours`.

Output is the same proof table preflight writes (§7.3), with `unprovable` where it is honestly
unprovable — an idle account cannot be polled at all, and recording `unprovable` beats recording
`ok`.

### 6.6 `--promote`

`/orchestrator:config --promote lanes.max` reads the value in force in `control.yaml`, resolves the
destination by §6.4, shows the diff, and writes on confirmation. This is the only path from the
control plane back into configuration, and it is the ordinary application of OWNER-DECISIONS 3.9 and
6.1: a value that proved itself should stop being re-typed.

---

## 7. Preflight

Runs inside `/orchestrator:run` before anything is created. Zero model. It refuses loudly rather than
degrading quietly at 03:00 — and it says, each time, exactly what it refused and what would fix it.

### 7.1 The gates, in order

| # | Gate | Refuses when | Exit |
|---:|---|---|---|
| 1 | **Resolution** | a slot file is present and unparseable | 78 |
| 2 | **Required keys** | `engine.kind` unset and no TTY | 3 |
| 3 | **No mixing** | `engine.kind` names a ready process *and* `engine.definition` is set | 65 |
| 4 | **Referential** | a role names an undeclared account; an account names an undeclared platform | 65 |
| 5 | **Single orchestrator** | the project lock is held by a live process | 71 |
| 6 | **Crash loop** | `crashloop.n` claims in `crashloop.window_minutes` with no result between | 71 (notify, hold) |
| 7 | **Account distinctness** | `doctor.account` equals `roles.orchestrator.account` | warn, `doctor.enabled → false` |
| 8 | **Account switch proven** | a configured switch does not produce the expected identity from the platform's own report | 69 |
| 9 | **Capacity readable** | an account's capacity is `unknown` and `capacity.on_unknown: hold_dispatch` | warn; dispatch holds |
| 10 | **Threshold bucket exists** | `capacity.threshold_bucket` names a bucket the provider no longer reports | 65 — **a configuration error, never a silent no-op** |
| 11 | **Board** | unreachable, or missing a configured status | 69 |
| 12 | **Readiness structure** | `tickets.ready_requires` is empty and `tickets.source: connector` | warn |
| 13 | **Questions channel** | not writable | 69 |
| 14 | **Notification channel** | `notify.probe_message` and the probe fails | 69 |
| 15 | **Red lines** | `redlines.path` missing or unreadable from the main checkout | warn (R1-15 makes the file optional; it is his decision) |
| 16 | **Worktree** | `worktree.base_ref` does not resolve; `worktree.env_proof` empty | 69 / warn |
| 17 | **Adapter verification** | an adapter's verification is older than `adapters.verify_max_age_hours` | 69 |
| 18 | **Residue** | a previous run left resources in `owned.ndjson` | list them with one exact command each; **never reclaim automatically** |
| 19 | **Credit ceiling** | any lane's `capacity_model` is `credit` and `capacity.spend_ceiling_usd` is null | 65 |

Exit-code table, used by every command in this plugin: `0` ok · `3` missing required config ·
`5` split brain · `8` written but unacknowledged · `64` usage · `65` validation · `69` a proof failed ·
`70` preflight refused · `71` another orchestrator · `75` lock timeout · `78` config unparseable.

### 7.2 What preflight writes

**`preflight.json`** — the proof table, frozen at start. One row per gate: `gate`, `result`
(`ok | warn | fail | unprovable`), `evidence` (the command run and the bytes that came back),
`at`. It is what `/orchestrator:status` prints when he asks why a run refused, and it is what
`--doctor` re-runs.

**`plan.json`** — the negotiated result, with `weakened[]` and `denied[]`, and **every row carrying
`owner_item`** (`JUDGE-fidelity` G5, from `ARCH-adapters` §5.3):

```json
{ "weakened": [
    { "owner_item": "Д12", "lane": "L2", "axis": "intervention",
      "from": "stop-hard as an instruction", "to": "kill the process",
      "why": "this platform cannot deliver a mid-turn message" } ],
  "denied": [
    { "owner_item": "R1-07", "lane": "L3", "axis": "accounts",
      "why": "this platform supports one account per machine" } ] }
```

Almost every one of his decisions is *"configure it per platform"*, which makes **partial**
degradation the normal case, not the exception. A binary gate forces either a refusal he did not ask
for or a silent acceptance. Naming the degradation against his own item number is the cheapest
possible honesty and costs one JSON file.

---

## 8. The per-run override

### 8.1 Grammar

```
/orchestrator:run [--mode ask|autonomous|controlled]
                  [--set <key>=<value>]...
                  [--unset <key>]...
                  [--dry-run]
```

- `<key>` is a dotted path that must exist in the §4 catalogue; an unknown key is exit 64.
- `<value>` is parsed as JSON when it parses (`2`, `true`, `null`, `[1,2]`, `{"a":1}`), otherwise as a
  string. `--set notify.events='["run.ended"]'` sets an array; `--set run.mode=controlled` sets a
  string.
- `--unset <key>` forces the key to its **layer-0 default** for this run, which is not the same as
  omitting it (omitting it takes the resolved value).
- `--mode X` is sugar for `--set run.mode=X`, because [075] singles out the run mode as the thing he
  overrides per run.
- Repeating a key is exit 64. Order never matters.

### 8.2 `run.json`

Written once, before preflight, then read-only for the life of the run:

```json
{ "schema": 1, "run_id": "<work-project>-20260919-224100Z", "at": "…",
  "argv_sha256": "…",
  "set":   { "lanes.max": 3, "run.mode": "controlled" },
  "unset": ["capacity.reserve_pct"] }
```

Layer 7. It cannot be edited mid-run — that is what layer 8 is for, and having one mutable run-scope
surface instead of two is the whole point of §5.2.

**What `--set` may not do**, and these are refusals at parse time:

1. It cannot remove or weaken a `never` entry (§3.3 rule 3). A veto that a command-line flag can lift
   is not a veto.
2. It cannot set a key that does not exist in the catalogue.
3. It cannot set `engine.kind` to a value whose adapter is not installed — that is gate 4, but the
   command says so immediately rather than at gate time.

`--dry-run` resolves everything, runs preflight, prints `config.resolved.json`'s provenance and
`plan.json`, and creates nothing.

### 8.3 The relationship between layers 7 and 8

A `--set` at launch is **not** written into `control.yaml`. They are different layers with different
lifetimes: `run.json` is what he asked for at 22:41, `control.yaml` is what he changed at 02:10, and
the record has to be able to show both. `/orchestrator:config --show lanes.max` prints:

```
lanes.max = 1
  layer 8  control.yaml overrides           1     ← in force
  layer 7  run.json --set                   3
  layer 6  ./.claude/…/orchestrator.local.json  2
  layer 2  ./.claude/…/orchestrator.json     4
  layer 0  shipped default                   2
```

That render, with no model, is the answer to "why is it 1", and it is why provenance is a required
part of §2.4's output rather than a nicety.

---

## 9. Zero-config behaviour

OWNER-DECISIONS 6.1 is binding: *"every plugin must be designed so that it can be run without a config
too, it will simply ask all the questions"*.

With no config file anywhere and a TTY: `/orchestrator:run` resolves an entirely default
configuration, finds `engine.kind` missing, runs the wizard from W§2, writes the answers to his own
files by §6.4, and proceeds. `tickets.source` falls to `local`, `connectors.notify.use` falls to
`terminal`, `connectors.questions.use` falls to `<project>/.orchestrator/QUESTIONS.md` — three
channels that need nothing installed. A first run on a fresh machine therefore needs exactly one
decision from him: which process the orchestrator is driving. That is R1-03, and it is the one thing
the plugin must not invent.

With no config and no TTY: exit 3, naming `engine.kind`.

---

## 10. Migration from `harness`

The previous generation's config files are **not slots** and must never be read as such:
`~/.claude/harness/config.json` and `<project>/.harness/config.json` (both VERIFIED, and both outside
every path in §2.1). `/orchestrator:config --import-harness` reads them, prints the mapping, and
writes nothing until he confirms.

| Old key | New key | Note |
|---|---|---|
| `tickets.source: github` | `tickets.source: connector` + `connectors.tasks.use: {kind:"cli",command:"gh"}` | |
| `tickets.repo`, `tickets.label_prefix` | `connectors.tasks.x-repo`, `tickets.ready_selector.value` | |
| `limits.pause_next_spawn_at` | `capacity.soft_pct` | |
| `limits.weekly_pause_at` | `capacity.hard_pct` | |
| `limits.on_unreadable: proceed` | `capacity.on_unknown` | **the value is not carried over.** `proceed` made the limiter provably inert for days (CLAIMED, FIELD-NOTES §11.7); the import prints the change and the reason |
| `limits.resume_margin_seconds` | `capacity.resume_margin_seconds` | |
| `limits.stop_at` | `capacity.threshold_bucket` + `capacity.hard_pct` | the old form parsed a bucket out of the literal string `SESSION=?`, so the hard stop could never fire (CLAIMED, FIELD-NOTES §11.7) |
| `session.permissions: bypass` | `session.permissions` | **not carried over**; defaults to `inherit` per R1-15 [357], and the import says so |
| `models.<role>` | `roles.<role>.model` | the `a\|b\|c` OR-chain becomes an array |
| `accounts.env_command` | `accounts.<id>.switch: {kind:"env", command:"…"}` | |
| `parallel.max_workers` | `lanes.max` | |
| `guardrails.never_push` | `delivery.mode: pr_only\|human` | |
| `guardrails.owner_gated` | `authority.owner_gated` | carried verbatim — it is his own list |
| `run.watch_interval_seconds` | `tick.interval_seconds` | |
| `run.stall_minutes` | `liveness.silence_minutes` | |
| `terminal.*`, `guardrails.sonnet_*`, `run.caffeinate` | — | no new home; listed as dropped, with one line each saying why |

Three keys deliberately do not survive the import with their old values. Each prints its reason. An
import that silently carried `on_unreadable: proceed` forward would reproduce the single largest
recorded failure of the previous generation on the first night of the new one.

---

## 11. What a test must enforce

Seven checks, because a contract nobody checks is prose.

1. **The defaults table is the only source of defaults.** Walk the plugin source for literal
   fallbacks; fail on one whose key is not a row in §4.
2. **Every catalogue row has a class**, and every class is one of `hard`, `soft`, `next-run`.
3. **Every `W§n` key appears in the wizard stage it claims**, and every wizard question carries a
   non-empty `why`.
4. **Single-writer**: no component writes a file §5.11 assigns to another.
5. **No pattern matching against processes**: `pkill`, `killall` and an unscoped `docker compose down`
   do not appear anywhere in plugin source. (`ARCH-adapters` BD-1, adopted; a lane's own prompt
   containing the literal string `playwright test` is what killed an unrelated lane, CLAIMED,
   FIELD-NOTES §11.8.)
6. **Never log a trigger phrase**: the plugin's own output never prints `/compact`, `rate-limit`, or a
   stop verb in a form its own detectors match. A governor that prints its own trigger on its own
   screen gets matched by its own detector (`ARCH-adapters` non-negotiable 4).
7. **Round-trip**: writing every key in §4 through `--set`, then resolving, yields the value written,
   and an unknown key written by hand into a slot file survives a wizard write untouched.

---

## 12. Tensions — his decisions, implemented, with the discomfort recorded

Each is a decision of his that this spec implements while something about it stays uncomfortable.
None is quietly replaced.

1. **Д1 itself is unratified.** [417]/[419]: the interviewer restated *"precedence follows your own
   the owner's company marketplace"* and moved to Д2 with no answer (VERIFIED, `corrections.md` §C).
   This entire document rests on it. If he meant something narrower — *"look at what I did there"*
   rather than *"inherit it whole"* — §2, §3 and §6.4 change shape.
2. **The run scope is a fourth authority in practice.** OWNER-DECISIONS 3.6 says *"remove the fourth
   level entirely"*. §3.2's reconciliation keeps the letter — no new config path, no new slot, the
   resolver untouched — and the effective value for a night still differs from the resolved config.
3. **Layer 8 outranks his own personal file.** 4.15's headline property is that a person's own file
   wins. A file in the run directory now wins over it for the duration of the run. That is what Д7
   [458] asks for — *«навіть якщо на початку я обрав інший варіант… або якщо в мене в дефолтній
   налаштуванні інше»* — and he never ruled on the interaction.
4. **YAML is my choice, not his.** [118]'s YAML was for the custom process definition and was hedged
   in the same breath. §5.8 pays for it with a vendored subset parser.
5. **One file for three jobs.** He named a watched file three times and never said they were one. §5.2
   makes them one; the cost is that an account reassignment and a stop share a parse failure.
6. **mtime was a hedge.** [195] says *«Можливо, там, наприклад, по даті»*. §5.9 uses it as the cheap
   gate and the content hash as the decision — which is more than he said and less than the analysis
   claimed he said.
7. **`control.poll_seconds: 10` is a promise about latency he never asked for.** Д12's mechanism is
   his — the command writes, the tick reads — and the number is mine.
8. **R1-15 as stated leaves nothing underneath the file.** `redlines.enforce: false` and
   `session.permissions: inherit` are [357] implemented literally. A flat prose file has no field
   separating an absolute from a preference, and nothing writable in this configuration would have
   stopped a browser trace printing two passwords into a transcript (CLAIMED, FIELD-NOTES). That is
   his decision and this is its price.
9. **`doctor.enabled` defaults true conditionally.** He never said the health check should be on. The
   conditional makes it on only where a separate account is configured, and off — loudly — where it does not.
10. **`lanes.max_heavy: 1` touches an axis he retracted.** [163]: *«це от останнє про сто завдань, це
    забери»* and [160] defers machine-resource awareness to the future. `max_heavy` is a declared-cost
    queue over steps a lane *declares* heavy, not resource sensing, and it is the smallest thing that
    prevents the one incident that actually happened. It is still a scheduler constraint on the axis
    he removed. `0` disables it.
11. **The resolver does not run on every tick.** OWNER-DECISIONS 4.10 says the read is mandatory on
    every invocation. §2.5 runs it at preflight and on a hash change. Defensible, disclosed, and a
    deviation from the letter.
12. **Every unratified item this document leans on**, listed once so the build order can be gated on
    round 2 (`JUDGE-fidelity` G1, all VERIFIED in `corrections.md` §C): Д1 config precedence
    [417]→[419] · Д12 stop verbs [523]/[525] · Д7 the mid-run override rule [460]→[463] · Д6 the single
    questions channel [451]→[453] · Д11's corrected output rule [515]→[517] · Д4's every-task-in-a-worktree
    default [435]→[437] · R1-06's entire hard/soft vocabulary [176]/[177]→[178] · R1-08's «guaranteed
    mechanism» clause [220]→[225] · R1-07's per-platform switch verification [200]→[202] · R1-15's
    one-file-no-enforcement rule [358]→[360] · R1-04's config lifecycle restatement [134]→[138] and
    board readiness check [154]→[156] · R1-17 [396]→[398].
    **Nothing whose vocabulary is unratified should be built before round 2 re-confirms it**, and the
    soft/hard vocabulary in §5.7 is the largest such thing in this document.

---

## 13. What is impossible as stated, and what keeping it costs

| Owner item | The part that is impossible | What keeping it costs |
|---|---|---|
| **R1-07 [195]** — a *hard* account change, "applies now, stops current work" | Changing a **running** session's account is impossible on every platform examined (CLAIMED, `ADAPTER-CONTRACT` §3 F, corroborated by FIELD-NOTES §8) | Stop the lane, relaunch on the new account, re-seed the context. He pays for that context a second time and one ticket becomes a lineage of sessions rather than one. The alternative is to redefine *hard* as *soft*, which changes his word |
| **R1-08 [204]** — *«повинен бути механізм, який гарантовано робить цю дію»* in hard mode | Four platforms have **no external compaction trigger at all** (CLAIMED, `ADAPTER-CONTRACT` §3 D) | The *outcome* guarantee survives via close-and-reseed (`context.mode_fallback: reseed`). The *action* guarantee cannot be kept on those four. The clause itself sits on an unratified restatement ([220]→[225]) |
| **Д12 [524]** — `stop-hard` as an instruction into a live session | On some platforms a mid-run message cannot be delivered, and in one protocol it aborts the turn (CLAIMED, `ADAPTER-CONTRACT` §3 G) | `stop-hard` degrades to killing the recorded process group after `stops.hard_deadline_s`. Recorded in `plan.json.weakened[]` **before** the run starts, not discovered at 03:00 |
| **Д4 [433]** — every task in its own worktree, *and* align with GSD's workspaces | GSD claims workspace ownership; there is no configuration that gives both his uniform default and GSD's intra-phase parallelism (CLAIMED, `ARCH-adapters` §9.6) | `worktree.owner: orchestrator` keeps his default and costs GSD's parallelism. *«з цим треба поєднювати»* is an assignment he gave, not a decision he made, and it is still open |
| **OWNER-DECISIONS 4.10** — the config read is mandatory on every invocation | A 60-second bash tick loop cannot spawn Node 1,440 times a night within Д11's token and cost posture | §2.5's hash gate. The cost of keeping 4.10 literally is a Node process a minute all night |
| **R1-16 case 2** — his own parallel work in the same folder | Nobody in the field solves it (CLAIMED, `LANDSCAPE.md` §5); a sandbox confines the agent to the workspace root, which is exactly where his parallel work lives | Nothing in configuration fixes this. He routed it to a separate agent at [378]/[381] and this document does not invent an answer |

---

## 14. Needs the owner — round 2

Everything below is something I had to invent because he never decided it. Each is phrased as a plain
question in Ukrainian, ready to be asked.

1. **Формат керуючого файлу.** Я зробив `control.yaml` — YAML з коментарями, бо ти редагуєш його
   руками о другій ночі. Ти згадував YAML [118], але про файл із кроками кастомного процесу, не про
   цей. YAML тут чи JSON? YAML коштує власний парсер; JSON не має коментарів.
2. **Ран-скоуп — це четвертий рівень?** У твоїх правилах маркетплейсу написано «три рівні і все,
   четвертий прибрати». Я зробив так, що `run.json` і `control.yaml` — це не конфіг, а стан рану:
   вони не в жодному слоті, не читаються резолвером і зникають разом із раном. Але фактично вони
   перебивають усі шість слотів. Це те, що ти мав на увазі?
3. **Керуючий файл перебиває твій особистий конфіг.** Головне правило 4.15 — «твій файл виграє
   завжди». Зараз рядок в `overrides:` у ран-директорії виграє навіть у твого `.local`. Для Д7 це
   потрібно, але це нове правило. Приймаєш?
4. **Дефолт `run.mode`.** Ти назвав три варіанти — питати щоразу, завжди автономний, завжди
   контрольований — але не сказав, який дефолт. Я поставив `controlled`, бо о четвертій ранку
   питати нема в кого. Правильно?
5. **Дефолт `lanes.max`.** Поставив 2. Твоє?
6. **Три невдачі підряд — і далі що?** Ти дав рівно два варіанти: повідомити і зупинитись, або просто
   зупинитись [442]. Я взяв перший. Чи потрібен третій — «позначити цей тікет як зламаний і
   продовжити ран далі»? Я його не додав, бо ти сказав, що все поза цими двома — з твого дозволу.
7. **Проміжний стоп із [171].** Ти згадав щось між софтом і хардом — «записати теперішній стан,
   можливо зберегти сесію, і зупинити її повністю» — і сказав «не знаю». Ключ є
   (`capacity.on_soft: save_and_close`), він вимкнений. Потрібен він узагалі?
8. **На якій шкалі відсотки контексту?** На твоїй машині два різні числа розходяться приблизно на 13
   пунктів: «скільки вікна зайнято» і те, що показує статус-лінія. Коли ти кажеш «компакт на 75%» —
   яке з двох? Я поставив «сире вікно» і зробив так, що візард показує обидва числа в момент вибору.
9. **`context.post_compact_prompt` — це твоя настройка.** Ти сам сказав: «чи відправляється якийсь
   промпт одразу після компакту, чи ні» [204]. Дефолт я зробив — перевставити файл із заборонами.
   Так, чи порожньо?
10. **Doctor на іншому акаунті.** Ти казав «запускати якогось агента раз в N годин на якійсь іншій
    підписці» [246]. Який саме акаунт для цього? Якщо другого акаунта немає — я вимикаю перевірку
    і кажу про це вголос. Це прийнятно, чи краще перевіряти з того самого акаунта?
11. **Резерв ліміту для тебе.** Чи треба тримати запас відсотків на акаунті, щоб оркестратор не з'їв
    весь ліміт, поки ти сам працюєш? Зараз `capacity.reserve_pct: 0` — тобто не тримає.
12. **Структура готовності тікета.** Ти дав це як завдання: «придумай якусь структуру, і її
    притримуйся» [146]. Я пропоную три секції: Outcome, Acceptance, Scope. Тег `ai-ready` —
    окремо. Годиться, чи інші назви?
13. **Видимість сесій.** Ти назвав чотири варіанти [324] і попередив, що з headless «треба бути дуже
    обережним». Я поставив дефолт «переважно інтерактивні, headless лише там, де платформа інакше не
    вміє». Чи хочеш повністю headless заради ресурсів машини?
14. **`session.permissions: inherit`.** Ти сказав, що окремої обов'язкової процедури для обмежень не
    треба і що середовище ти налаштовуєш сам [357]. Тобто плагін не ставить жодних прав узагалі —
    ані дозволів, ані заборон. Підтверджуєш, що це саме те, чого ти хочеш?
15. **Гальмо на нові завдання під час рану.** Д2 [422] — ти сказав просто «бере і виконує», без умов.
    Я не став ставити ліміт, лише сповіщення, коли черга зросла на 50. Чи потрібен ліміт?
16. **Чи може `stop-custom` сам писати в керуючий файл?** Тобто чи дозволено твоєму текстовому
    правилу породжувати нові команди (наприклад, «зупини тільки збірки, решту дай дописати»)? Зараз
    дозволено для варіанта `kind: commands` і заборонено для `kind: rules`.
17. **Що робити з `harness`-конфігами.** Я написав імпорт, який переносить старі ключі, але **не
    переносить** три значення: `on_unreadable: proceed`, `session.permissions: bypass` і `stop_at`.
    Усі три в реальному рані виявились зламаними. Погоджуєшся, що імпорт має їх мовчки не брати, а
    натомість сказати чому?
18. **Що вважати «кроком» за замовчуванням?** [209] — «лише поточного кроку, але це можна
    налаштовувати». Для GSD це його власна межа кроку. Для процесу без кроків я поставив «кінець
    ходу». Ок?
