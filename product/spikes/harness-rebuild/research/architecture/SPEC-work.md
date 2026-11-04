# SPEC-work — work source, readiness and the questions channel

**Component spec for the `orchestrator` plugin.** Date **2026-09-19**. Implementable without asking
questions; every hole the owner never closed is filled here with a **DEFAULT-PROPOSED** and repeated
at the end as a Ukrainian question for round 2.

**Authority.** `../../round-1/ANALYSIS-01.md` and `TRANSCRIPT-01.md` are the source of truth. This
spec covers **R1-04**, **Д2**, **Д6**, **Д7**, **Д8**, **Д9**, and the parts of **R1-05** (dependency
blocking) and **Д5** (repeat failure) that touch a work item's state. Nothing below replaces a
decision of his. Where a decision costs something, the price is named and the decision is kept
(§14). Where a decision is impossible as stated, the impossible clause is isolated and priced (§13).

**Evidence tags used on every non-trivial claim.**
**VERIFIED** — read in a primary source on this machine, or measured here on 2026-09-19.
**CLAIMED** — a vendor doc or third-party document asserts it and I did not execute it.
**INFERRED** — my reasoning from the above. An estimate, not a fact, and stated so it can be rejected.

---

## 0. Which design this builds on, and where the judges disagreed

**I followed the two-of-three consensus: `ARCH-minimal` is the spine.**

| Judge | Winner | Score spread |
|---|---|---|
| `JUDGE-cost` | **ARCH-minimal 9** | operability 7 · reliability 5 · adapters 4 |
| `JUDGE-fidelity` | **ARCH-minimal 8** | reliability 7 · adapters 6 · operability 5 |
| `JUDGE-survival` | ARCH-operability 8 | adapters 7 · reliability 6 · **minimal 5** |

Cost and fidelity both name `ARCH-minimal` and both graft *into* it. Survival ranks it **last** and
grafts into `ARCH-operability`. I followed cost and fidelity, for three reasons stated so they can be
argued with:

1. Survival's own tiebreak paragraph says the corpus is *"a corpus of nights"* and that what ended
   nights were **loops, silence, and capabilities that reported `native` and were not**. In *this*
   spec's scope, all three of those are closed by mechanisms both camps agree on — self-write
   suppression (§6.4), the evidence gate (§5.5), and the capability floor at connect (§3). Survival's
   real complaint about `ARCH-minimal` is about the *fleet* (a watchdog, a pacer, a warden), which is
   outside this component.
2. Fidelity is the axis the owner's brief makes non-negotiable, and `ARCH-minimal` is the only design
   that scores top on it while also scoring top on cost.
3. `ARCH-minimal` and `ARCH-operability` agree on **almost everything in this component** — the same
   five role states, the same readiness floor, the same three-tier detector, the same claim
   primitives. Their disagreements are two: `intake` default (§7.2) and whether the orchestrator
   writes into the item body (§5.1). Both are recorded as tensions and both are in §15.

**Grafts taken from the losing designs**, each named where it lands:

| Graft | From | Lands in |
|---|---|---|
| `ops.json` + evidence-gated `ok` on every mutating operation | `ARCH-reliability` §1 I4, §3.6 (via `JUDGE-survival` G1) | §5.5 |
| The claim ordering as a build-failing invariant, not a convention | `ARCH-reliability` §5.1 (via `JUDGE-survival` G13) | §4.3 |
| Three-tier change detection with the scout on the diff only | `ARCH-operability` §6.4 (via `JUDGE-cost` G2, `JUDGE-fidelity` G8) | §8 |
| Role mapping **confirmed by the owner**, never derived silently | `ARCH-operability` §6.1 | §3.4 |
| `HARVEST` — a third answer between exit code and done | `ARCH-operability` §5 (via `JUDGE-cost` G8) | §4.6 |
| Three capability values (`native`/`emulated`/`impossible`), never a boolean | `ARCH-adapters` §5 (via `JUDGE-cost` G11) | §3.3 |
| `${ORCHESTRATOR_STATE_DIR:-…}` over a hardcoded `~/.orchestrator` | `ARCH-reliability` §3.1 | §1.2 |
| `intake` as a named three-value setting | `ARCH-operability` §6.6 | §7.2 (value default follows `ARCH-minimal`) |

**Where I departed from the winner, and said so:** `ARCH-minimal` keeps the claim inside the run
directory. This spec moves it to a **project-scoped** directory that outlives the run (§4.2), because
C3-A11's dead-run case — three tickets left `active` by a run that died at 03:40, invisible to the
morning run — is unreachable from a claim that dies with the run. INFERRED; flagged in §14.7.

---

## 1. Vocabulary, paths and the one-page model

### 1.1 Words this spec uses in exactly one sense

| Word | Meaning here |
|---|---|
| **work item** | One unit of work. Never "ticket" or "task" in normative text, because the local registry, GitHub and ClickUp each call it something different. |
| **backend** | Where work items live: `local`, `github`, `clickup`, or a user-supplied adapter. |
| **board** | A backend other than `local`. His «підключена дошка» [129]. |
| **registry** | The `local` backend. His «локально, в самому проєкті … сканбан-дошка» [129]. |
| **role** | One of the five meanings a work item's state can have (§2.1). The orchestrator knows roles; it never knows a status *name*. |
| **spec region** | The bytes of a work item that constitute its description. Defined exactly in §2.4, because nothing in R1-04 defines it and C3-A10 shows two implementers will split on it. |
| **lane** | One running executor working one claimed item. |
| **channel** | The Д6 questions channel [449]. One configured location, never the board by default. |
| **sweep** | One poll of a backend that covers every watched item at once. The unit of polling cost. |

### 1.2 Paths

```
# ── machine state ──  ${ORCHESTRATOR_STATE_DIR:-$HOME/.local/state/orchestrator}/
  projects/<pkey>/                     pkey = sha1(realpath of the project root), 40 hex
    claims/<item-id>.d/                THE CLAIM. Created by mkdir(2). Outlives the run (§4.2)
      claim.json                       {holder, run_id, epoch, item_id, taken_at, heartbeat_at, …}
    items/<item-id>.json               per-item orchestrator state: digests, watermarks, generation
    questions/<qid>.json               the orchestrator's mirror of a channel entry (§9.6)
    board.cache.json                   last sweep: per-item (etag|watermark|digest), sweep_at
  runs/index.tsv                       run-id \t project-root \t run-dir \t created_at \t state
  runs/<run-id>/
    journal.ndjson                     append-only; every record type in §11
    status.json                        rewritten each tick; the pull surface (Д11)
    ops.json                           the operation catalogue and its evidence rules (§5.5)
    lanes/<lane-id>/ …                 outside this spec's scope

# ── in the project, and read from the MAIN checkout only ──
<project>/.orchestrator/items/*.md     the local registry, when tasks.backend = local
<project>/.orchestrator/QUESTIONS.md   DEFAULT-PROPOSED location of the Д6 channel (§9.2)
```

**Everything the run writes lives outside the work tree.** `ARCH-minimal` §2.1's reason is verified
and load-bearing here: Д4 [433] makes *every task its own git worktree*, a worktree is a separate
checkout, and anything the run keeps in the repository forks per lane. FIELD-NOTES §12.5 records
`QUESTIONS.md` and `JOURNAL.md` **forking into a worktree's own copy with a real owner-facing question
invisible for an hour** (VERIFIED). C3-A2 measured 327 registry files tracked in git, every status
write dirtying one, and FIELD-NOTES §4.1 records that one dirty tracked file is what made a merge
print success and move nothing (VERIFIED).

**The two project-side files are read from the main checkout, never from a worktree copy.** Resolve it
with `git rev-parse --git-common-dir` and take its parent (VERIFIED on git 2.33.0 on this machine: run
from inside a worktree it returns the main repo's `.git`). If the project is not a git repository — N2
[344] explicitly allows that — the project root is the directory holding `.orchestrator/`.

### 1.3 The model in one paragraph

A work item lives in one backend. Its **role** is what the orchestrator reads; its **status name** is
the backend's business. An item becomes claimable when a deterministic **floor** passes (§2.5). A
claim is one `mkdir` that cannot produce two winners (§4). While claimed, one **sweep** per tick asks
the backend "did anything change" for free or nearly free, and a model is woken only when a *spec
region* actually moved (§8). A change that touches a ticked acceptance criterion is the Д9
contradiction case and takes the configured branch (§10). Anything the run cannot decide goes into
**one channel** the owner placed, in one format, with a stated fallback; an answer appearing there is
detected deterministically and delivered to the lane that is waiting, or to the item if no lane is
(§9).

---

## 2. The readiness contract

This is the structure the owner handed forward: «це треба буде, щоби придумав якусь структуру, і її
притримувався» [145]/[146]. Two obligations, not one — design it, **and adhere to it at runtime**
(`extract/outside-list.md:82`). §2.5 is the adherence half, and it is checked on **every** transition,
not once at creation.

### 2.1 Five roles, and they are roles rather than names

R1-04 [153] says status names are user-overridable and adapt to the chosen process. So the
orchestrator never learns a name.

| role | meaning | who may write it |
|---|---|---|
| `backlog` | exists; not offered to the orchestrator | human |
| `ready` | may be claimed **now** | human. The orchestrator **only** with `tickets.model_may_promote: true` (§7.3) |
| `active` | claimed and being worked | **orchestrator only** |
| `needs-input` | stopped, waiting on a human; carries `reason` | orchestrator, or human |
| `done` | finished | orchestrator, or human |

Five, not six. Д2's «needs review» for a thin description [422] and R1-14's hard stop are the **same**
role with a different `reason`. A sixth state would have to be mapped onto every backend and confirmed
by the owner for nothing.

**`blocked` is not a role.** R1-05 [160] blocking — «якщо якісь завдання не може виконуватися, тому що
не виконалось одне з попередніх, то його ми не можемо взяти» — is **derived** from `depends_on` at
dispatch time, every tick, and is never written to the backend. Writing it would produce the defect
FIELD-NOTES §12.6 records twice: `done` leaving a previously blocked issue holding **two** state labels
because `blocked` is never removed (VERIFIED).

### 2.2 Fields

Every field has **exactly one writer**. `where` says whether it lives on the backend or in the run's
own state; that distinction is not cosmetic (§2.3).

| field | type | required | writer | where | purpose |
|---|---|---|---|---|---|
| `id` | string, `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` | yes | backend | backend | stable cross-reference. **Never reused, even after `dropped`** |
| `title` | string, 1–200 chars | yes | human | backend | — |
| `role` | enum, §2.1 | yes | per §2.1 | backend | the state machine |
| `spec` | string | yes | human | backend | the description. Its byte range is §2.4 |
| `depends_on` | array of `id` | no, default `[]` | human | backend | R1-05 [160] |
| `labels` | array of string | no | either | backend | free; the orchestrator reads only what config names |
| `origin` | object, §10.3 | no | orchestrator | backend | `{supersedes, generation, run_id}` for a Д9 item |
| `claim` | object, §4.2 | no | **orchestrator only** | **run state** | `{holder, run_id, epoch, taken_at, heartbeat_at}` |
| `spec_digest` | 64 hex | no | **orchestrator only** | **run state** | sha256 of the normalised spec region at claim time (Д8) |
| `source_watermark` | object, §8.3 | no | **orchestrator only** | **run state** | the backend's own change token at claim time |
| `ac_state` | array, §2.4 | no | **orchestrator only** | **run state** | `[{anchor, text_digest, ticked_at}]` — what Д9 compares against |
| `generation` | integer ≥ 0 | no, default 0 | orchestrator | backend | how many Д9 hops from a human-authored item (§10.4) |

**`id` is read back, never composed.** The previous generation's allocator composed ids and produced
**two files under one id in five rounds out of five**, and a twenty-way add produced **20 files under 3
ids, with zero non-zero exits — both callers told `OK created ticket 273`** (VERIFIED,
`<work>/<work-project>/docs/open/HARNESS-TICKET-ID-ALLOCATION.md`). The rule that
document arrived at is adopted verbatim as a contract: **nobody writes an id they have not read back
from the tool's own output.** There is no reservation verb, on purpose. On `local` the id is allocated
by §4.1's `mkdir` primitive and read back from the created directory name.

### 2.3 Why four fields live off the backend

`claim`, `spec_digest`, `source_watermark` and `ac_state` are never written to the item. On GitHub,
writing them into the body **edits the body**, which moves `lastEditedAt`, which is the exact signal
Tier 1 reads — the detector would trigger itself on every claim (VERIFIED: `lastEditedAt` is the field
that isolates body edits, and it moves only on a body edit). On `local` it is worse: writing into the
file is a real textual change to the spec region.

INFERRED but firm: this is the same topology as FIELD-NOTES §11.6's **85-minute loop nothing internal
could break** — a detector reading a surface its own actor writes to, which ended only on an external
`SIGTERM` (VERIFIED). One rule removes the whole class.

### 2.4 The spec region — defined exactly, because nothing in R1-04 defines it

C3-A10's finding is the reason this subsection exists: the previous generation's readiness floor was
three greps over the **whole file**, and the tool appended its own log to that same file, so the floor's
input included the tool's own echo (VERIFIED, `harness-tickets.sh:27-37`, `:143`, `:50`).

**Definition.** The spec region is:

- **local** — the bytes after the closing `---` of YAML frontmatter, to **end of file**, with two
  exclusions: any line inside an `<!-- ORCH:LOG -->` … `<!-- /ORCH:LOG -->` fence, and any trailing
  run of blank lines.
- **github** — `issue.body`, entire. Comments are not part of it.
- **clickup** — `task.description` (the markdown field), entire. Comments are not part of it.

**The `ORCH:LOG` fence exists and the orchestrator still does not write into it.** It is defined so a
*human* or an *engine* that appends a log to the local file does not corrupt the digest, and so a
migration from the previous generation's ticket files has a place to put the old appended logs. The
orchestrator's own writing goes elsewhere (§5.1).

**Normalisation before hashing** — apply in this order, so two implementers get the same digest:

1. Decode as UTF-8; replace an invalid byte with `U+FFFD`.
2. `CRLF` → `LF`; `CR` → `LF`.
3. Strip the `ORCH:LOG` fences and their contents (local only).
4. Strip trailing whitespace from every line.
5. Collapse three or more consecutive blank lines to two.
6. Strip leading and trailing blank lines.
7. `spec_digest = sha256(bytes)`, lowercase hex.

**Required sections.** Three headings, matched case-insensitively at any heading level:

| Section | Regex on a heading line | What it is |
|---|---|---|
| Outcome | `^#{1,6}[ \t]*(outcome\|goal\|objective)\b` | what is true when this is finished. Prose. No format imposed |
| Scope | `^#{1,6}[ \t]*(scope\|in scope)\b` | what this item may touch and what it must not |
| Acceptance criteria | `^#{1,6}[ \t]*(acceptance( criteria)?\|accept\|definition of done\|dod)\b` | the checklist below |

These three are the previous generation's, kept **verbatim** for two measured reasons: they held
across the live 327-item queue — 288 `done`, **15 of 15 `ready` items passing the floor, zero
violations** (VERIFIED, audited 2026-09-19) — and they are already in the owner's muscle memory.

**The acceptance-criteria fence and its anchors.** Inside the acceptance section:

```markdown
## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 The sign-in screen shows the company logo at the top.
- [x] #2 A wrong password shows a message naming the field.
<!-- /AC:END -->
```

- Anchor syntax: `^- \[( |x|X)\] #(\d+) (.+)$`. `#N` is stable for the item's life and is **never
  renumbered**; a deleted criterion leaves its number retired.
- Anchors are what Д9 decides on (§10.2). Without them a contradiction can only be judged on prose,
  which is what makes «оркестратор вирішує» [482] unimplementable.
- `ac_state[i].text_digest = sha256(normalised criterion text, excluding the checkbox and the anchor)`.
- If the fence is absent, every `- [ ]` line inside the acceptance section counts, anchors are
  assigned by ordinal position, and `status.json` carries `ac_anchors: "positional"` — a weaker mode
  that is honest about being weaker. DEFAULT-PROPOSED `tickets.require_ac_fence: false` — *rationale:
  it would refuse every one of his 327 existing items on day one.*

**`[NEEDS CLARIFICATION: …]` anywhere in the spec region blocks `ready`.** Borrowed from
`github/spec-kit` (VERIFIED: read `templates/spec-template.md` through the GitHub API), and it is the
same idea the owner reached for independently — «він пише, що, типу, needs review» [422].

**Deliberately not required:** tests, a repository, a branch, a build, EARS, Gherkin, a test command.
N2 [344] forbids assuming any of them: «може таке бути, що десь не буде тестів, і це також окей».

### 2.5 The floor — deterministic, zero model, run on every transition

```
FLOOR(item) -> PASS | FAIL(reasons[])
 1. role must be present and map to one of the five roles          else FAIL "role-unmapped"
 2. spec region is non-empty after normalisation                   else FAIL "spec-empty"
 3. spec region matches the Outcome heading regex                  else FAIL "missing-outcome"
 4. spec region matches the Scope heading regex                    else FAIL "missing-scope"
 5. spec region matches the Acceptance heading regex               else FAIL "missing-acceptance"
 6. at least one line matching ^- \[( |x|X)\] inside that section  else FAIL "no-criteria"
 7. no "[NEEDS CLARIFICATION" substring in the spec region         else FAIL "needs-clarification"
 8. every id in depends_on resolves to an item in this backend     else FAIL "dangling-dependency:<id>"
 9. no cycle among depends_on edges reachable from this item       else FAIL "dependency-cycle"
10. PASS
```

Cost: a `stat`, a read and nine regexes. Milliseconds, zero tokens.

**Where the floor runs.** On six transitions, and it is the same function every time:

| transition | on FAIL |
|---|---|
| `backlog → ready` (a human moves it) | refuse to claim; record `floor_fail`; leave the item where it is |
| `ready → active` (the claim) | do not claim; log; try the next item |
| `active → done` | do **not** write `done`; go to `needs-input` with `reason: floor_fail` |
| stale-claim release (§4.5) | do not release to `ready`; print `STUCK — needs a human` and leave the claim |
| a Д8 Tier-2 change lands (§8.5) | the item is a Д9 case; §10 decides |
| `needs-input → ready` (a human fixed it) | stays `needs-input` |

**Dependency blocking is checked separately at dispatch and is not a floor failure.** An item whose
`depends_on` all *resolve* passes step 8 even when they are not yet `done`; it simply is not
dispatchable. `status.json.queue.blocked_by_deps` counts them, so an item stuck behind a dependency is
visible rather than silently absent.

### 2.6 A complete worked item, local backend

`<project>/.orchestrator/items/0412-sign-in-logo.md`

```markdown
---
id: "0412"
title: Show the company logo on the sign-in screen
role: ready
depends_on: ["0388"]
labels: [ui, mvp]
generation: 0
---

## Outcome
A visitor who opens the sign-in screen sees the company logo above the form, on a phone and on a
desktop, and the page keeps working when the image fails to load.

## Scope
Only the sign-in screen and its stylesheet. Not the header used by the rest of the site. No change
to the authentication flow.

## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 The logo appears above the form on the sign-in screen.
- [ ] #2 On a 375px-wide viewport the logo does not overlap the form.
- [ ] #3 With the image blocked, the screen still shows the form and a text alternative.
<!-- /AC:END -->
```

FLOOR: passes if `0388` resolves. Dispatchable once `0388` is `done`.

---

## 3. Connecting a backend, and what "verify access" means

R1-04 [153]: «треба перевіряти, чи дошка готова до цього … мають бути якісь певні мінімальний набір
статусів … Ці статуси можна конфігурувати також власноруч». And [129]: «треба просто переконатися, що
є доступ до цього ресурсу».

**Recorded honestly: this decision was never ratified.** The restatement at [154]/[155] was never
answered — the interviewer moved to R1-05 at [156] (VERIFIED, `extract/corrections.md:85`).
ANALYSIS-01 files it SETTLED. This spec implements it as his stated intent and puts the ratification
in §15.

### 3.1 «Переконатися, що є доступ» is five probes, not one

C3-A9's failure is the reason: a connect step that verifies access **with a read** — the natural
reading, and the only check that cannot damage anything — passes at 23:00 and the run discovers at
03:00 that the token is read-scoped. Three lanes' real work is then invisible on the board, and a
morning run re-claims work that is already done.

`orchestrator:connect` runs all five, in order, and prints a row per probe:

| # | probe | local | github | clickup |
|---|---|---|---|---|
| P1 | **read** one item | read a file under `items/` | `gh issue view <n> --json number` | `clickup-cli task get <id>` |
| P2 | **list** with the readiness filter | glob + parse frontmatter | `gh issue list --label <ready> --json number` (**core**, never `--search`) | `clickup-cli task list --list <id>` |
| P3 | **comment** | write + delete a temp file under the run state, not the project | `gh issue comment` on the probe item, then delete the comment | `clickup-cli comment create` then delete |
| P4 | **role write** | rewrite a temp file's frontmatter | `gh issue edit --add-label <probe-label>` then remove | `clickup-cli task update --status <x>` then restore |
| P5 | **create** (only if `intake.machine_may_create: true`, §10.4) | `mkdir` a temp item dir, remove | `gh issue create --title "orchestrator connect probe"` then close | `clickup-cli task create` then delete |

P3–P5 run against a **probe item the owner names or the connect step creates**, never against a real
one. `connect.probe_item` is a config key with no default; if unset, connect creates one titled
`orchestrator connect probe` and closes it.

**P2 must not be phrased as a search.** VERIFIED by measurement on 2026-09-19: `gh issue list --repo …`
consumed **1 core request** of 5,000/hour; the same query phrased `gh issue list --search "state:open"`
consumed **0 core** and hit the **search** resource, whose live headers report `limit: 30` **per
minute**. A poller that types the wrong flag gets a 160× smaller budget. The adapter never issues a
search-resource call.

**Failure verb.** C3-A7 is right that this is the sharper hole, so it is decided here:

DEFAULT-PROPOSED `connect.on_probe_fail: refuse` — *rationale: proceeding with a partial mapping
silently loses whichever role has no home, and creating what is missing edits someone else's board;
refusing is the only one of the three that is reversible.* The other two values exist:
`degrade` (record the failing probe as a capability of `impossible`, continue, and refuse at run time
every operation that needs it) and `create` (P4/P5 create the missing statuses or labels).

**`create` is never the default, and it is refused outright on a shared surface.** The previous
generation shipped `create`: `gh_labels_bootstrap` runs `gh label create … --force` for five labels
(VERIFIED, `harness-tickets.sh:73-85`). On a shared repository or a shared ClickUp list that is an
externally visible schema change to other people's board made at 04:00 with nobody awake, and on
ClickUp a status set is a **list-level** property, so changing it changes it for every task in the
list. It also collides with the owner's own boundary principle [370]: «він би не мав зупиняти якісь
там тести, які не він запускав». If `connect.on_probe_fail: create` is set and the backend reports
more than one collaborator, connect refuses and says why.

### 3.2 The gh account hazard, named because it is this machine's

CLAIMED, from the owner's own global instructions: `~/.zshenv` sets `GH_CONFIG_DIR` **by working
directory** — a work identity and a personal identity, routed by folder. A git worktree cut outside the routed tree therefore flips the
GitHub account the adapter authenticates as, silently, mid-run.

**Rule.** The `github` adapter records `gh api user --jq .login` at connect time as
`board.identity.login`, and re-reads it **before every mutating board call**. A mismatch is a hard
refusal of that call with `reason: identity-drift`, never a retry. Cost: one cached call; the login is
re-read at most once per `board.identity_recheck_seconds` (DEFAULT-PROPOSED **300** — *rationale: long
enough to be free, short enough that a drift cannot survive a lane's lifetime*).

### 3.3 Capability declaration — three values, never a boolean

Each backend adapter declares, before anything runs:

```json
{ "backend": "clickup",
  "capabilities": {
    "read": "native", "list": "native", "comment": "native", "role_write": "native",
    "create": "native",
    "free_unchanged_poll": "impossible",
    "spec_change_signal":  "emulated",
    "prior_spec_text":     "impossible",
    "atomic_claim":        "impossible",
    "watermark_listing":   "native" },
  "poll": { "unit": "request", "budget": 100, "window_seconds": 60 } }
```

`native | emulated | impossible`, never a boolean — `JUDGE-cost` G11 and `ARCH-adapters` §5 are both
right that a two-valued map forces `emulated` to be spelled `true`, and an adapter that reports
`native` and degrades at 03:00 is the single worst failure this contract exists to prevent
(ADAPTER-CONTRACT §2.0).

**The orchestrator asks the owner a question for every `impossible` a configured requirement depends
on**, at connect time, not at 03:00. On ClickUp that is exactly one question, and it is in §15.

The three backends, measured (VERIFIED on 2026-09-19 unless marked):

| capability | local | github | clickup |
|---|---|---|---|
| `free_unchanged_poll` | `native` — `stat` + sha256 | `native` — `If-None-Match` → **304, zero quota consumed** (measured: five 304s moved the counter zero; five 200s moved it five) | **`impossible`** — `cache-control: no-cache, no-store`, no `etag`, no `last-modified` |
| `spec_change_signal` | `native` — digest of the spec region | `native` — `lastEditedAt`, distinct from `updatedAt` (observed **ten days apart** on `cli/cli#14188`) | `emulated` — fetch the task, hash `description`. No `date_description_updated` exists in the payload |
| `prior_spec_text` | `emulated` — only what the run stored | `native` — `userContentEdits[].diff` carries the **full body at that revision** | `impossible` |
| `atomic_claim` | `native` — `mkdir` | `native` — `POST /git/refs` → **422 `Reference already exists`** | **`impossible`** — none found |
| `watermark_listing` | `native` — mtime + digest | `native` — `since=`, GraphQL `orderBy` | `native` — `date_updated_gt=<unix_ms>` |
| full-board sweep cost | free | **2 GraphQL points** of 5,000/hour for 50 items with everything the detector needs | **1 request** of 100/minute; 19,580 bytes for 4 tasks |

**Two GitHub traps, both measured, both of which silently cost full price if ignored:**
1. The ETag is bound to the exact representation. Dropping `Accept: application/vnd.github+json`
   turned the same conditional request back into a `200`. **Cache the `Accept` header alongside the
   ETag**, and treat a `200` where a `304` was expected as a cache miss to be investigated, not as
   normal.
2. `GET /rate_limit` returned **stale zeros** repeatedly while the endpoint's own `x-ratelimit-used`
   header was accurate. **Read the budget from the response headers of the call you actually made.**

### 3.4 The role mapping is proposed and confirmed, never derived

The connect step reads the backend's statuses, proposes a mapping to the five roles, and **asks the
owner to confirm it**. It never binds a derived mapping silently.

The reason is measured. On the owner's own live ClickUp list `[AUT] Developmental Tasks` (VERIFIED):

```
backlog     type=open        to do        type=unstarted
ongoing     type=custom      in progress  type=custom
on hold     type=custom      blocked      type=custom
review      type=done        Closed       type=closed
```

`review` is typed **`done`**. A mapping derived from `type` binds `review → done`, and then C3-A7's
03:00 failure runs: a lane finishes, the process says "move to review for a human", the orchestrator
reads type `done`, marks the work complete, Д9 never fires because nothing was contradicted, and the
run reports thirteen items done, one of which nobody ever reviewed.

So `type` is the *proposal's* input and the owner's confirmation is the *binding*. That keeps «ці
статуси можна конфігурувати також власноруч … людина може перевизначити» [153] as the authority.

**The mapping, once confirmed, is written to the owner's own config file** — per
`snf/OWNER-DECISIONS` 3.9, a configuration answer is written to the person's own file, and the
recommendation is always his own file.

```json
{ "connectors": { "tasks": {
    "use": { "kind": "cli", "command": "gh" },
    "x-orchestrator": { "backend": "github", "repo": "owner/<work-project>",
      "roles": { "backlog": {"label": "orch:backlog"},  "ready": {"label": "orch:ready"},
                 "active":  {"label": "orch:active"},   "needs-input": {"label": "orch:needs-input"},
                 "done":    {"closed": true} } } } } }
```

Per `snf/OWNER-DECISIONS` 4.9 an unknown key inside a source is an error **except** one prefixed
`x-`, and per `docs/config-levels.md` §6 an `x-` key behaves like any other key in the merge. The
backend binding therefore rides in `connectors.tasks.x-orchestrator` without inventing a key the
marketplace schema does not allow.

### 3.5 The minimum set of statuses

[153] names no minimum. Decided here:

**The minimum is the set of roles the configured process needs**, and the configured process declares
it. `ARCH-minimal` §6.1 and R1-03 [118] both make the process the authority, so the orchestrator asks
the engine descriptor which roles it uses and requires a mapping only for those.

DEFAULT-PROPOSED `process.roles_required: ["ready", "active", "done"]` — *rationale: his own plain
case, spoken verbatim: «Або там може бути дуже звичайні процес, це ready, in progress, done» [153].*
`needs-input` is added automatically whenever `questions.channel` is configured, because Д6's whole
purpose is to park an item on a human. `backlog` is optional: an unmapped `backlog` means "anything
not `ready` is not offered", which is the same behaviour with one fewer status.

---

## 4. Claiming and releasing

### 4.1 The primitive, per backend, measured

VERIFIED on this machine's APFS volume on 2026-09-19, 2/10/50 concurrent workers racing one claim:

| primitive | 2 workers | 10 workers | 50 workers |
|---|---|---|---|
| `mkdir` | **1 winner** | **1 winner** | **1 winner** |
| `ln` (hard link) | **1 winner** | **1 winner** | **1 winner** |
| `set -o noclobber; : > f` | **1 winner** | **1 winner** | **1 winner** |
| `test -e` then write — **the shape the previous generation ships** | 2 winners | 10 winners | **27 winners** |

`flock(1)` is **absent** on this machine — not on `PATH`, not in `/usr/bin`, not in
`/opt/homebrew/bin` (VERIFIED). That independently forces the `mkdir` choice.

| backend | claim primitive | evidence |
|---|---|---|
| **any** (always) | `mkdir ${STATE}/projects/<pkey>/claims/<item-id>.d` | measured above |
| **github** (belt) | `POST /repos/<owner>/<repo>/git/refs {"ref":"refs/heads/orch-claim/<item-id>","sha":<default-branch-head>}` → `201` you hold it, `422 Reference already exists` someone else does | VERIFIED live: creating an existing ref returns `422 {"message":"Reference already exists"}` |
| **clickup** (belt) | **none exists.** Assignee + re-read, and the connect output must **say the guarantee is absent** rather than imply one | VERIFIED: no CAS found |
| **local** (belt) | the `mkdir` above is already the local CAS | — |

**The single-claimer rule stands, and is now enforced rather than assumed.** Only the orchestrator
moves an item to `active`; executors never claim. That is what the previous generation relies on
today — VERIFIED, `templates/prompts/orchestrator.md:91`, only the orchestrator calls
`harness-tickets.sh claim` — and it follows from the owner's single-orchestrator invariant [300–302]:
«якщо раптом одночасно два якісь оркестратори працюють, то це не окей. Це треба відслідковувати і не
дозволяти.» The rule is load-bearing and, today, undefended. §4.3 defends it.

DEFAULT-PROPOSED `claim.board_cas: true` where the capability is `native` — *rationale: it costs one
API call per claim and it is the only thing standing between a crashed-and-restarted orchestrator
(Д10 [497]) and a double claim; it adds a `refs/heads/orch-claim/*` namespace to the repo, which is
the cost and is in §15.*

### 4.2 `claim.json`

`${STATE}/projects/<pkey>/claims/<item-id>.d/claim.json`, written temp-then-`rename()`:

```json
{ "schema": 1,
  "item_id": "0412",
  "backend": "github",
  "holder": {"host": "sasha-mbp", "pid": 40311, "boot_id": "…", "user": "sasha-marchuk"},
  "run_id": "<work-project>-20260919-224100Z",
  "epoch": 7,
  "lane_id": "t-0412",
  "taken_at":     "2026-09-19T23:41:02Z",
  "heartbeat_at": "2026-09-20T02:14:03Z",
  "board_cas": {"kind": "git_ref", "ref": "refs/heads/orch-claim/0412", "created_at": "…"},
  "worktree": "/Users/…/<work-project>-wt/0412",
  "base_sha": "fd6125e…" }
```

**The claim is project-scoped and outlives the run.** `ARCH-minimal` puts it in the run directory;
this spec does not, because C3-A11's case is unreachable from a run-scoped claim: the Mac sleeps at
03:40, items 88, 91 and 104 sit `active` with the orchestrator's own comments claiming progress, and
at 09:00 run N+1 does not touch them (not `ready`), nothing releases them (the shipped staleness
default is **7 days** — VERIFIED, `stale_report() { local days="${1:-7}" …}`), and a human reading the
board believes the comments. A project-scoped claim makes run N+1 see run N's abandoned claims on its
first tick and reconcile them by §4.5. INFERRED; recorded in §14.7.

**`epoch`.** Monotonic, incremented each time this project's lock is acquired; stored beside the lock.
It is what distinguishes *this* run's claim from a dead predecessor's when PIDs have been reused.

### 4.3 The claim algorithm — an invariant, not a convention

`JUDGE-survival` G13 asks for the ordering to be a **named, build-failing invariant**. It is
`INV-CLAIM-ORDER`, and a unit test asserts each step's precondition; a reordering fails the build.

```
CLAIM(item):
 1. assert the process holds the project lock.                    else ABORT "not-the-orchestrator"
 2. FLOOR(item) must PASS.                                        else SKIP, journal floor_fail
 3. every id in item.depends_on has role == done.                 else SKIP, count as blocked_by_deps
 4. item.generation <= tickets.max_generation.                    else SKIP, journal generation_capped
 5. mkdir claims/<id>.d              — ATOMIC. EEXIST -> SKIP (someone holds it; §4.5 may reclaim).
 6. write claim.json (temp + rename). Failure -> rmdir claims/<id>.d, SKIP.
 7. if claim.board_cas and capability is native:
      create the CAS object. 422/exists -> rmdir claims/<id>.d, SKIP "lost-board-race".
 8. read the item AGAIN from the backend; recompute spec_digest.
      digest differs from step 2 -> release (reverse of 6,7,5) and SKIP "raced-edit".
 9. write items/<id>.json: {spec_digest, source_watermark, ac_state, claimed_at}.
10. board write: role -> active.  ADVISORY (§5.4). Failure degrades board_sync; DOES NOT abort.
11. mkdir lanes/<lane-id>; write start.json; launch.
```

Step 8 is not paranoia: it closes the window between the floor check and the claim in which the owner
edits the item. It costs one read, and on GitHub that read is a 304 most of the time.

**The reverse order on release is mandatory** and is the same invariant: `result.json` is written
**last**, then the lane directory is moved to `lanes.done/`, then the board write, then the CAS object
is deleted, then `rmdir claims/<id>.d`. A crash therefore leaves a **detectable orphan** — a claim with
no live holder, or a lane directory with `start.json` and no `result.json` — rather than a false claim
of completion.

### 4.4 Heartbeat

The tick refreshes `heartbeat_at` for every claim this run holds, by `rename()` of a rewritten
`claim.json`. One `write` + one `rename` per claim per tick.

**Idleness is derived from `heartbeat_at` in the claim, and from nothing else.** Never from the
backend's `updatedAt`, which the orchestrator's own comments bump — VERIFIED on `cli/cli`:
`issue.updated_at` was **exactly equal** to the last comment's `created_at` on three open issues, and
the previous generation's `gh_comment` uses `--edit-last --create-if-none`, so **a session that only
comments looks alive forever** (VERIFIED, `harness-tickets.sh`).

### 4.5 Reclaiming a stale claim

Every tick, for each claim directory in this project:

```
RECLAIM(claim):
 1. claim.run_id is this run  -> refresh heartbeat; done.
 2. claim.run_id is listed live in runs/index.tsv AND that pid+boot_id is alive
       -> NOT OURS. Leave it. Journal foreign_claim. This is the single-orchestrator
          invariant [300] holding, and it is never overridden automatically.
 3. now - heartbeat_at < claim.stale_minutes  -> leave it.
 4. FLOOR(item) must still PASS               -> else print "STUCK — needs a human",
          set role needs-input with reason stale_claim_floor_fail, notify, LEAVE THE CLAIM.
 5. release: delete the board CAS object, set role back to ready, rmdir claims/<id>.d,
    journal claim_reclaimed with the dead run_id and the last heartbeat.
```

DEFAULT-PROPOSED `claim.stale_minutes: 45` — *rationale: the shipped default is 7 days, which hides a
dead run's abandoned work for a week (VERIFIED); 45 minutes is longer than the longest legitimate
silent stretch the field notes record for a working lane and far shorter than a night.*

DEFAULT-PROPOSED `claim.reclaim_foreign: false` — *rationale: reclaiming a claim held by a live
foreign orchestrator is exactly the thing [300] forbids; the honest response is to refuse and say so.*

### 4.6 `HARVEST` — the third answer between the exit code and `done`

Grafted from `ARCH-operability` §5 via `JUDGE-cost` G8. When a lane exits, the item does **not** go to
`done` on the strength of the exit code. It enters `HARVEST`, and the completion oracle is asked
(that oracle is the configured process's, per R1-13 [344]: «Якщо в нього get shit done, то [він] сам
робить verification»). Three answers, not two: **done**, **not done**, **undeterminable**.

DEFAULT-PROPOSED `harvest_evidence: observed` — *rationale: withhold `done` only on positively
**observed** emptiness; the two errors are not symmetric. Advancing an empty item moves work in a
system we do not own and puts it in front of a person; withholding leaves it in a queue we keep
watching, with the withholding recorded.* Values: `observed` · `strict` (also withholds an
undeterminable verdict) · `off` (exit-code behaviour).

This exists because FIELD-NOTES §4.1 records a merge that reported success and moved nothing — `git
merge` printing `Already up to date` and exiting **0** (VERIFIED) — and because R1-13's evidence
(«merge that did nothing, a truncated suite read as a pass») was put to the owner at [342] and did
**not** change his answer: verification belongs to the process. `HARVEST` does not add a check of the
work. It only refuses to convert an exit code into a claim about the work.

---

## 5. Write-back: statuses, comments, and the evidence gate

### 5.1 Where the orchestrator writes, and the tension this creates

[149]: «це має бути якась дошка, яка буде помічником для цього оркестратора, щоби ставити статуси
таскам, залишати якісь коментарі». Confirmed cleanly at [152] «Ну так, правильно».

**Rule: the orchestrator writes the item's role, and it writes comments, and it never writes into the
item's spec region.** Concretely:

| backend | role write | comment write | spec region |
|---|---|---|---|
| local | rewrite the frontmatter `role:` key only, temp + `rename()` | **not into the item file.** Appended to `${STATE}/projects/<pkey>/items/<id>.log.md`, and surfaced by `orchestrator:show <id>` | never touched |
| github | add/remove the mapped label, or close/reopen | `gh issue comment` — a **new** comment each time, never `--edit-last` | never touched |
| clickup | `clickup-cli task update --status` | `clickup-cli comment create` | never touched |

**This is a real departure from his framing and it is recorded, not hidden.** He described the local
registry as a working surface too. On the local backend this spec makes the item file **read-only to
the orchestrator apart from one frontmatter key**, and puts the trail in the run state. The cost: the
local item file is no longer a self-contained record a person can read end to end. The benefit is that
three verified failure classes go away at once — C3-A1 (the tool's own log inside the description
firing its own change detector), C3-A10 (the readiness grep matching the tool's own echo, releasing an
item that has had its `## Scope` removed), and C3-A2's 327 dirty tracked files inside worktrees, one of
which is what made a merge print success and move nothing. Recorded in §14.1; the question is in §15.

**`--edit-last` is dropped.** VERIFIED, `harness-tickets.sh`: `gh_comment` uses
`--edit-last --create-if-none`, so the board holds exactly **one** comment per item — the latest
status, not a trail. C3-A12's 09:00 case is the cost: the owner opens item 91 to understand why a lane
stopped at 02:00, and the comment says what the orchestrator thought at 03:55. A trail is the whole
value of «помічник».

DEFAULT-PROPOSED `board.comment_mode: append` — *rationale: the decision's value to him is a readable
trail at 09:00, and `edit_last` cannot produce one.* Value `edit_last` remains available for a board
where comment volume is a real cost.

DEFAULT-PROPOSED `board.comment_events: ["claimed", "needs_input", "done", "failed", "superseded"]` —
*rationale: five events is a trail; a comment per tick is noise and, on GitHub, moves `updatedAt`
every 60 seconds for nothing.*

### 5.2 The comment format

One shape, on every backend, so a person reading a board recognises it and a machine can find its own:

```
<!-- orch:v1 run=<work-project>-20260919-224100Z item=0412 event=needs_input action=a7f3c1 -->
**orchestrator** · needs input · 2026-09-20T02:41:09Z

Question `Q-0412-01` is open in the questions channel. This item is parked and nothing else is
blocked by it.

Fallback if unanswered: take the first acceptance criterion literally and record the reading.
```

The HTML comment is the machine-readable header. `action` is a random 6-hex id written into the side
effect **before** the call, so a retry after an ambiguous failure can tell "my write landed" from "my
write did not" by searching for its own `action` (`ARCH-operability` §8.1's `action_id`, adopted).

### 5.3 Self-write suppression

**Every surface this spec watches is checked by `(mtime, size)` first and only then by content
digest, and the orchestrator records the digest of everything it writes.** A change whose digest the
orchestrator produced is ignored, not reported, not counted, not escalated.

On a board, a second and cheaper rule applies and is preferred where it exists: **a comment authored
by the orchestrator's own identity is never a change.** The `github` adapter filters on
`comment.author.login == board.identity.login`; the `clickup` adapter on the comment's `user.id`. This
needs no digest bookkeeping and cannot drift.

This is the one-line fix for C3-A1. Without it, the 02:14 shape runs: the orchestrator comments, the
watcher wakes at 02:15, spends a model call, reports «змінилось» with a diff consisting of its own log
line, Д9 decides whether that contradicts finished work, and writes the decision back at 02:16 —
which is another change. Same topology as FIELD-NOTES §11.6's 85-minute loop, which **nothing internal
detected** and which ended only on an external `SIGTERM` (VERIFIED).

### 5.4 Board writes are advisory; the local claim is authoritative

A board write that fails sets `status.json.board_sync: "degraded"`, notifies **once** per run per
failure class, appends to the journal, and **changes nothing about execution**. The run does not stop
because a label did not move.

This inverts his framing of the board as the orchestrator's working surface [149] and is recorded in
§14.2. The alternative is C3-A9's 03:00 failure with the run halted on a 403 and three lanes' work
stranded; `ARCH-minimal` §4 takes the same position for the same reason.

### 5.5 The evidence gate — `ops.json`

Grafted whole from `ARCH-reliability` §1 I4 / §3.6 via `JUDGE-survival` G1, because it closes the
"reported success and did nothing" class that this component can produce in four places.

`runs/<run-id>/ops.json` declares every mutating operation in this spec. The journal appender
**refuses** to write `outcome: "ok"` for a mutating op that carries no evidence object of a declared
admissible kind. **Adding an op without declaring its evidence is a load-time error**, not a runtime
surprise.

```json
{ "schema": 1, "ops": {
  "claim.local":        {"mutating": true, "idempotent": true,
                         "admissible": ["dir_created"],    "reconcile": "stat",        "timeout_s": 5},
  "claim.board_cas":    {"mutating": true, "idempotent": true,
                         "admissible": ["http_status:201"], "reconcile": "ref_read",   "timeout_s": 20},
  "board.role_write":   {"mutating": true, "idempotent": true,
                         "admissible": ["board_readback"],  "reconcile": "item_read",  "timeout_s": 30},
  "board.comment":      {"mutating": true, "idempotent": false,
                         "admissible": ["board_readback", "http_status:201"],
                         "reconcile": "comment_search_by_action_id",                   "timeout_s": 30},
  "item.create":        {"mutating": true, "idempotent": false,
                         "admissible": ["board_readback"],  "reconcile": "search_by_action_id", "timeout_s": 30},
  "questions.post":     {"mutating": true, "idempotent": true,
                         "admissible": ["file_digest", "board_readback"],
                         "reconcile": "qid_search",                                    "timeout_s": 30},
  "answer.deliver":     {"mutating": true, "idempotent": true,
                         "admissible": ["transcript_event", "file_digest"],
                         "reconcile": "transcript_scan",                               "timeout_s": 60}
}}
```

Evidence kinds used here: `dir_created` (the `mkdir` returned success and the directory exists),
`http_status:<n>`, `board_readback` (re-read the item and observe the new value), `file_digest`,
`transcript_event`, `ref_read`.

**`board_readback` is the only admissible evidence for a role write.** `JUDGE-fidelity` G7 says so and
the reason is measured: an API call returning 200 proves the request was accepted, not that the item's
role moved.

DEFAULT-PROPOSED `evidence.readback_sample: 1.0` for role writes, `0.0` for comments — *rationale: a
role write is what the next run reads and a wrong one causes double work; a comment is a trail and a
readback per comment doubles the API cost of the trail.*

---

## 6. The tick, and what it costs

### 6.1 One sweep, not N fetches

**The whole board is polled once per tick, by watermark, and per-item work happens only for items the
sweep flags.** This is what makes the watched set in §8.2 affordable on all three backends.

| backend | the sweep | cost | measured |
|---|---|---|---|
| local | `find items/ -newermt <last_sweep>` then digest only the hits | free | — |
| github | one GraphQL query: 50 items with `number, title, updatedAt, lastEditedAt, labels, assignees, blockedBy, subIssuesSummary, state` | **2 points** of 5,000/hour | VERIFIED live against `cli/cli`. The `number` + `lastEditedAt` shape for 100 items costs **1** |
| clickup | `GET /team/<team>/task?date_updated_gt=<unix_ms>` | **1 request** of 100/minute | VERIFIED live, returned 100 tasks with `last_page:false` |

At a 60-second tick GitHub costs **120 points/hour — 2.4% of the budget** — for a complete view of
readiness, dependencies and change state. INFERRED from the measured per-query cost.

DEFAULT-PROPOSED `board.poll_seconds: 60` — *rationale: it matches the control tick, it is the rate the
previous generation's question channel used in production (VERIFIED, its README: "re-runs that check
every 60 seconds"), and on GitHub it costs 2.4% of one budget.*

DEFAULT-PROPOSED `board.poll_seconds` **minimum 60 on `clickup`, enforced** — *rationale: 100
req/min per token is the whole budget and the owner's other tools share the token.*

DEFAULT-PROPOSED `board.max_requests_per_minute: 50` on `clickup` — *rationale: half the measured
budget, leaving headroom for his own interactive use of the same token, which is the failure the
capacity cluster measured on the Anthropic usage endpoint (a one-call `rate_limit_error` with four
standing pollers on this machine).*

### 6.2 What the sweep produces

A list of `(item_id, changed_fields[])`, where `changed_fields` ⊆ `{role, spec, labels, deps,
comments, assignee}`. The sweep is the **only** thing that decides whether Tier 1 runs (§8.4). It
never calls a model.

---

## 7. Mid-run intake (Д2)

### 7.1 The behaviour, which is not in question

> «Він може абсолютно спокійно підібрати. Тобто, якщо під час запуску я добавляю якесь завдання, яке
> тегується відповідно до того, що воно вже готове … AI бере це завдання, і виконує» [422]

**Mechanism: none needed.** The dispatch step re-reads the queue every tick from the sweep, so an item
that becomes `ready` is claimed on the next tick — at most `board.poll_seconds` after it appears.
`ARCH-minimal` §4 is right that this requires no new machinery, and adding any would be inventing
where he decided.

**Latency, stated so it can be measured:** ≤ 60 s on `local` and `github`, ≤ 60 s on `clickup`
(watermark sweep), plus the time to finish a claim. VERIFIED-by-construction from §6.1.

### 7.2 Volume — the case his answer does not reach

VERIFIED, FIELD-NOTES §10.1: the previous run's queue grew **236 → 327 items in one day**, and the
owner's response was to set a **soft pause** by hand at 11:15 (`state/SOFT-PAUSE.md`). The brake was a
human, awake.

The limits rules do not save this. They **pause**, they do not **prioritise**: «якщо … виглядає так,
що завдання впирається в те, що впереться в ліміти, то це окей» [171]. A weekly window spent on
low-value work is spent.

And it collides with Д11 [508]: nothing is pushed to him — «якщо я хочу отримати статус виконання, то
я можу запустити окремий термінал». So the growth signal that made him intervene last time is
available only if he goes looking, at a time when by design he is asleep.

**Setting, in his own vocabulary:**

| `intake` | behaviour |
|---|---|
| `open` | claim anything that becomes `ready`, no ceiling |
| `capped` | claim new arrivals until `intake.cap` items have been **started** this run; further arrivals stay `ready` and are counted |
| `frozen` | work only the set that was `ready` at run start |

DEFAULT-PROPOSED `intake: open` — *rationale: it is his behaviour, spoken twice and confirmed at
[426]; `ARCH-operability` §6.6 and `JUDGE-survival` both argue for `capped` at 20, and I did not take
it, because capping is quietly replacing a decision he made. The brake is the notification below, and
the choice between them is his (§15).*

DEFAULT-PROPOSED `intake.cap: 20` when `capped` is selected — *rationale: `ARCH-operability`'s number,
adopted unchanged so the two designs do not diverge on a value neither of us can ground.*

DEFAULT-PROPOSED `intake.notify_on_growth: 50` — *rationale: the only recorded instance is 236 → 327,
a delta of 91; 50 fires before that point and not on ordinary filing. A notification is not a brake; it
is the signal he acted on last time.* The delta since run start is also printed in
`status.json.queue.added_since_start` unconditionally, because §6.1's sweep already knows it and Д11
says the status pull is where he looks.

### 7.3 The sufficiency judge, and who wins when it disagrees with the floor

This is C3-A6, and it must be decided or two implementers build opposite products.

> «агент аналізує, і якщо достатньо опису, то він його бере і імплементує. Якщо недостатньо, то він
> пише, що, типу, needs review» [422] — with **two** «я точно не знаю» in the same answer.

> «це треба буде, щоби придумав якусь структуру, і **її притримувався**» [146]

**Decision: the floor is authoritative. The model may refuse; it may not promote.**

```
DISPATCH_GATE(item):
 1. FLOOR(item) fails  -> the model is NOT called. Item stays where it is. Zero tokens.
 2. FLOOR(item) passes AND tickets.sufficiency_judge == off  -> claim.
 3. FLOOR(item) passes AND judge is on -> call the watcher model once with the spec region and
    ask ONE question: "is this workable as written, yes or a named gap?"
      "yes"        -> claim.
      a named gap  -> role needs-input, reason = the gap verbatim, post to the questions channel.
```

DEFAULT-PROPOSED `tickets.model_may_promote: false` — *rationale: a model that can write `ready` makes
the structure advisory and cancels «її притримувався». C3-A6's 02:00 case is the cost of the other
reading: an item reading in full "Fix the footer — it looks wrong on mobile" is judged sufficient
because the intent is obvious, a lane spends four hours and a chunk of the weekly window, and at 09:00
there is nothing to compare the result against because the item never stated what "right" was — and Д9
cannot help, because no criterion was contradicted: none existed.*

DEFAULT-PROPOSED `tickets.sufficiency_judge: on` — *rationale: it is his [422] behaviour, it costs one
cheap-model call per claim (not per tick), and with `model_may_promote: false` its only power is to
refuse, which is the safe direction.*

DEFAULT-PROPOSED `tickets.sufficiency_model: <roles.watcher>` — *rationale: Д8 [466] already says the
checking model is configurable and a weaker sub-agent is the shape; the same pin serves both duties and
gives him one knob instead of two.*

Recorded honestly: this reading **is** a choice between two of his sentences, and §15 puts it to him.
The inverse risk is verified too — FIELD-NOTES §11.4 records GSD's verify stage **silently skipped for
phases 14 to 18**, each verification file self-attributing `verified_by: the lane that built the
phase`, because an orchestrator generalised a narrow warning into a broad rule; **no automated check
caught it, manual review did.** A model-judged gate is the same class of actor.

---

## 8. Watching an item change (Д8)

> «оркестратор бере це завдання і він може слідкувати за змінами в цьому завданні … має бути
> налаштування, якою моделькою перевіряти … немає сенсу перевіряти фейбл моделю … можливо, є сенс
> запускати слабшу модель, сабагента … і в нормальному рані, якщо нічого не змінилось, то цей агент
> просто, типу, нічого назад не поверне, а якщо щось змінилось, то тільки тоді він починає звітувати
> про те, що змінилось, як змінилось» [466]

**Scope of his confirmation, recorded because it is narrower than ANALYSIS-01 reads.** At [475] he
said «На те, що ти перше сказав, так, я підтверджую» — confirming **only** the first restatement
([469]). Two fragments of his own were talked over and lost: «Тобто, може бути момент» [468] and «з …
підстави чогось в моменті» [471] (VERIFIED, `extract/corrections.md:126,137`). That reads like a
qualifier on **when** a mid-flight change may be acted on, and nobody recovered it. It is an open item
and it is in §15.

**Field position, for honesty about how much of this is invented.** LANDSCAPE §5 corrects the adoption
verdict and lands here: *"Nothing found re-reads a ticket's **description** mid-run and changes what
the agent is doing."* Symphony re-fetches snapshots and Sortie re-reads issue state, but both are
about *dispatchability*, not about the operator editing the brief while the agent works on it. **Д8 is
genuinely unsolved in the field and this section is invention, not adoption.** INFERRED from
LANDSCAPE's survey.

### 8.1 Three tiers, model last

| Tier | Question | Cost | local | github | clickup |
|---|---|---|---|---|---|
| **0** | did *anything* change? | free / one sweep | `find -newermt` | folded into the 2-point sweep; or `If-None-Match` → **304, zero quota** | the 1-request `date_updated_gt` sweep |
| **1** | was it the **spec region**, or only a comment or a label? | still no model | recompute the spec digest | compare `lastEditedAt` to `source_watermark` | fetch the task, hash `description` |
| **2** | *what* changed, and does it matter? | **one cheap-model call, on the diff only** | diff against the stored prior text | `userContentEdits[].diff` gives the **full prior body** for free | diff against the stored prior text |

**Tier 0 or Tier 1 returning "no" is where «нічого назад не поверне» is achieved — deterministically,
rather than by a model deciding to stay quiet.** That is the difference between his requirement being
satisfied and being hoped for.

**Measured value of the tiering.** Ready-item bodies on the live 327-item queue: min 2,880 bytes,
median **3,932**, mean 5,129, max 20,144 (VERIFIED). At ~4 bytes/token a median body is ~1,000 input
tokens (INFERRED — no Anthropic credential on this machine, so `count_tokens` did not run). Pricing
from the bundled `claude-api` reference, cached 2026-06-24 (CLAIMED).

| watcher design | per check | 1 item, 8 h @ 60 s | 3 lanes |
|---|---|---|---|
| Fable 5.1 reads the body every tick | ~$0.010 | ~$4.72 | ~$14.16 |
| Haiku 4.5 reads the body every tick | ~$0.001 | ~$0.47 | ~$1.42 |
| **Tiers 0–1 deterministic, model only on a real change** | **$0** | **~$0.00** | **~$0.01** |

INFERRED from the measured sizes and the quoted prices. His instinct — «немає сенсу перевіряти фейбл
моделю» — is right by a factor of ten; the tiering makes it several hundred. **His decision stands: the
watcher model is configurable. Tiers 0–1 only decide when it is worth waking it.**

### 8.2 The watched set — and Д9's trigger, which C3-A3 found missing

Д8 scopes the watcher to an item the orchestrator «бере» and watches «під час цього». Д9's **preferred**
branch is the one where the item is already finished: «якщо вже завдання виконане, але воно змінене, то
оркестратор задати перевагу тому, щоб зробити новий тікет» [482]. **Nothing in his answers says who
notices that a finished item changed.** The decision that fires most often has no trigger.

VERIFIED that the obvious implementation cannot see it: the previous generation's `gh_done` runs
`gh issue close`, and every poll filters `--state open`. A finished item is closed and invisible.

**Decision.** The watched set is:

```
watched = { role == active }                                       # Д8, his words
        ∪ { role == ready and claimed by nobody }                  # so a spec edit before pickup is seen
        ∪ { role == done and done_at > now - watch.done_window_hours }   # Д9's headline case
```

DEFAULT-PROPOSED `watch.done_window_hours: 24` — *rationale: it covers the overnight case C3-A3
describes exactly (item finishes 22:10, the owner tightens its criteria at 23:40 and goes to bed, the
run reaches the end of the queue at 04:00) and it is affordable because §6.1's sweep is one call
whatever the set size. A permanent window would mean the run never stops watching anything, which
collides with Д3's clean finish.*

DEFAULT-PROPOSED `watch.scope: active_ready_done` — *rationale: as above.* Values: `active` (his
literal words, cheapest, and Д9's main branch never fires), `active_ready`, `active_ready_done`, `all`.

**The ClickUp cost of the wider set, stated rather than assumed away.** Tier 1 on ClickUp requires a
**full task fetch per flagged item** (19,580 bytes for 4 tasks, no ETag, no conditional request —
VERIFIED). The sweep is still one request, so the cost is proportional to how many items actually
changed, not to the set size. At the owner's observed rate that is near zero most ticks. The floor is
`board.max_requests_per_minute` (§6.1), and on exhaustion Tier 1 is deferred to the next tick with
`status.json.board_sync: "deferred"` rather than dropped.

### 8.3 `source_watermark`

```json
{ "local":   {"kind": "digest", "spec_digest": "…", "mtime": "…"},
  "github":  {"kind": "lastEditedAt", "value": "2026-08-18T08:41:20Z", "etag": "W/\"…\"",
              "accept": "application/vnd.github+json"},
  "clickup": {"kind": "description_digest", "spec_digest": "…", "date_updated": 1789824033000} }
```

Taken at claim time (§4.3 step 9) and **rewritten after every Tier-2 resolution**, so the same edit is
never reported twice. Never written to the backend (§2.3). The `accept` key is stored because the ETag
is bound to the representation and dropping the header silently turns a free 304 into a paid 200
(VERIFIED).

**On GitHub, `updatedAt` is never used as a change signal.** VERIFIED: for three open `cli/cli` issues
`issue.updated_at` was exactly equal to the last comment's `created_at`, and the whole-issue ETag moves
with it because the payload embeds `updated_at` and the comment count. `lastEditedAt` is `null` when
the body was never edited; treat `null` as "unchanged since creation" and compare against `created_at`.

### 8.4 The algorithm

```
WATCH(item), once per tick, for every item in `watched`:
 1. if item.id not in this tick's sweep hits -> RETURN SILENT.                # Tier 0
 2. changed_fields from the sweep. if 'spec' not possibly in it -> RETURN SILENT.
      github:  lastEditedAt == source_watermark.value       -> SILENT
      clickup: fetch task; sha256(description) == digest    -> SILENT
      local:   spec digest == stored digest                 -> SILENT
 3. if the new digest is one this run wrote (§5.3)          -> RETURN SILENT, journal self_write.
 4. prior := github ? userContentEdits[last].diff : stored prior text.
    if prior is null (redacted, or never stored)            -> prior := "" and mark diff_partial.
 5. diff := unified_diff(normalise(prior), normalise(current)), 3 lines of context.
 6. if len(diff) > watch.max_diff_bytes -> truncate, mark diff_truncated.
 7. call roles.watcher ONCE with the diff and the item's ac_state. One question, four answers:
      { "verdict": "cosmetic" | "scope" | "criteria" | "outcome",
        "anchors_touched": ["#2"], "anchors_ticked_touched": ["#2"],
        "summary": "<= 240 chars, plain language" }
 8. on unparseable output -> verdict := "criteria" (the conservative branch), journal
    watcher_unparseable, and do NOT retry in this tick.
 9. update source_watermark and the stored prior text.
10. hand (item, verdict, anchors) to §10.
```

Step 8's fail-direction matters: an unparseable verdict is treated as **the case that escalates**, not
the case that proceeds. DEFAULT-PROPOSED `watch.on_unparseable: escalate` — *rationale: waiting is the
fail-safe; acting on a malformed verdict is how a watcher becomes a hazard.*

DEFAULT-PROPOSED `watch.max_diff_bytes: 8192` — *rationale: two ticked criteria and their surrounding
prose fit comfortably; the measured max body is 20,144 bytes and sending a whole rewritten body as a
"diff" is the cost the tiering exists to avoid.*

DEFAULT-PROPOSED `watch.max_model_calls_per_hour: 20` — *rationale: bounds the loop, not just the
bill. A detector that re-reads its own effect burns a per-hour budget in minutes; on exhaustion the
watcher **stops waking, raises an attention item, notifies, and the tick keeps running**
(`JUDGE-cost` G1, grafted).*

### 8.5 The report — what «звітувати про те, що змінилось» produces

Silent when nothing changed. When something changed, exactly one journal record and one comment:

```
[ITEM 0412] spec changed at 2026-09-20T01:20:11Z by @sasha-marchuk
verdict: criteria — touches #2, which is already ticked
summary: the mobile breakpoint moved from 375px to 390px and criterion #2 now names 390px
what happens next: per change.on_contradiction = new_ticket, item 0455 opens and 0412 continues
```

---

## 9. The questions channel (Д6)

> «людина може налаштовувати собі якийсь єдиний канал для питань … якщо є якісь запитання,
> невирішення, неуточнення, або підтвердження, то вже готове рішення, але мені треба його
> підтвердити, або навіть готове рішення, яке вже імплементоване, треба його переглянути, то він це
> все додає в єдиний файлик, який я потім можу пройтись руками і дати відповіді … Тобто місце
> визначається користувачем.» [449]

In English, the rest of the answer: the orchestrator watches the file for changes so he can review it live; the place can be anything (GitHub issues with a tag, a task-manager task, a local file) and may differ from the task manager the orchestrator uses.

Four item types in one channel, and they are his: **questions**, **unresolved points**,
**clarifications**, **confirmations of a ready decision**, and **review of a decision already
implemented**. The last one is not a question at all and the format must carry it.

### 9.1 The format is his own, because it is measured

The previous run produced eleven escalations through a channel of exactly this shape — `Q-P9-01`,
`Q-T122-01`, `Q-OWN-01`…`-04`, `Q-ORCH-04`…`-07`, `Q-RESTORE-01`, `Q-PARITY-01`, `Q-T250-01` — **each
with a recorded `Fallback` and each later marked answered** (VERIFIED, FIELD-NOTES §9.1 and
`<work>/<work-project>/docs/open/QUESTIONS.md:394-603`). That is eleven out of eleven,
and it is the single strongest positive data point in the whole corpus. This spec adopts the format
rather than inventing one.

**One entry:**

```
## Q-<SCOPE>-<NN>
Kind: question | confirm | review | clarify
Origin: item 0412, lane t-0412, 2026-09-20T02:41:09Z
Status: open
Blocks: this item only — nothing else waits on it
Fallback: take criterion #2 literally at 375px and record the reading as the decision
Deadline: 2026-09-20T08:41:09Z
Question: The item says 375px and the new criterion #2 says 390px. Which width is the one that matters?
```

| Field | Rule |
|---|---|
| `## Q-<SCOPE>-<NN>` | the id, alone on its line. `SCOPE` = the item id or a short uppercase tag; `NN` = that scope's own counter from `01`. **Because the scope is in the id, two lanes never have to look at each other's numbers and can append at the same time without colliding** — VERIFIED as the rule that worked in production. An id is never reused, even after `dropped` |
| `Kind` | which of his four purposes this is. `review` is the "already implemented, look at it" case that is not a question |
| `Origin` | item, lane, timestamp. A person at 09:00 must be able to find the work without asking |
| `Status` | `open` \| `answered` \| `dropped`. **Only the writer of the entry changes it** |
| `Blocks` | what stands still. Written in plain language, because it is what tells him whether to answer now or after coffee |
| `Fallback` | **mandatory.** What happens if nobody answers. An entry with no fallback is refused at write time and the run raises `question_without_fallback` — *this is the field that made eleven out of eleven work, and a question with no fallback can deadlock the run* |
| `Deadline` | when the fallback fires. Absent means never |
| `Question` | one question, English or the project's language, bare. No recommendation, no options unless the options are genuinely the whole answer. **One question per entry**; three questions are three entries |

**Before writing an entry, the lane must have tried to settle it.** `Q-PARITY-01` is the shape worth
copying: the session drove the question empirically first — removed a permission check, rebuilt, ran
the comparison in 27.4 seconds, found 64 count-pairs identical across four roles and sixteen
collections — and asked only what measurement could not settle (VERIFIED, FIELD-NOTES §9.1). That is a
rule here: **if the question is settleable by running something inside the item's own scope, run it
first and escalate only the residue.**

### 9.2 Where the channel is, and the one-file shape

`questions.channel` has **no default value**; preflight asks once, which is exactly what he described:
«ми йому можемо задати питання, чи хоче він якийсь єдиний канал». The question is asked once, the
answer is written to **his own config file** (`snf/OWNER-DECISIONS` 3.9), and it does not come back.

```json
{ "connectors": { "questions": {
    "use": { "kind": "file", "path": ".orchestrator/QUESTIONS.md" } } } }
```

The connector lives in the **general** config (`identity.json`), not the plugin file, because
`snf/OWNER-DECISIONS` 3.4's reusability test puts almost everything in the general config and an
"ask the human" channel is plainly usable by more than one plugin.

DEFAULT-PROPOSED `questions.channel.path: <project>/.orchestrator/QUESTIONS.md` **as the suggestion
preflight offers**, not as a silent default — *rationale: it is the shape he actually built for
himself, and offering a concrete path is the difference between one keystroke and a decision at
23:50.*

**One file, two regions, single writer per region.** His words are «єдиний файлик» — one file, which
he walks through by hand and answers in. His own production setup used **two** files
(`QUESTIONS.md` written by sessions, `ANSWERS.md` written by him, with build sessions forbidden from
writing to `ANSWERS.md` — VERIFIED from that repository's README). Both are right about different
things: one file is what he said; two writers is what made answer detection unambiguous. This spec
takes both by putting two single-writer regions in one file:

```markdown
# Orchestrator questions

Append-only. Never reorder, never delete. The orchestrator writes above the fence; you write below it.

<!-- ORCH:QUESTIONS -->
## Q-0412-01
Kind: question
…
<!-- /ORCH:QUESTIONS -->

<!-- ORCH:ANSWERS -->
## Q-0412-01
Answer: 390. The old value was wrong.
<!-- /ORCH:ANSWERS -->
```

**The orchestrator never writes a byte below `<!-- ORCH:ANSWERS -->`.** That is what makes §9.4's
detection free of the self-write problem entirely, with no digest bookkeeping.

DEFAULT-PROPOSED `questions.layout: single_file` — *rationale: «єдиний файлик» is his word.* Value
`two_files` is available and takes `questions.answers_path`; a `two_files` channel is exactly the
setup he ran for 34 hours.

### 9.3 The channel on the three backends

| `use.kind` | questions go | answers come from | append primitive |
|---|---|---|---|
| `file` | the `ORCH:QUESTIONS` region, appended at the end | the `ORCH:ANSWERS` region, or an `Answer:` line inside the entry | read-modify-`rename()` under `questions.lock`, one writer at a time |
| `github_issue` | **one comment per entry** on the configured issue, or **one issue per entry** carrying `questions.label` | any comment whose author is **not** `board.identity.login` | `gh issue comment` |
| `tracker_task` | one ClickUp comment per entry on the configured task | any comment whose `user.id` is **not** the orchestrator's | `clickup-cli comment create` |

DEFAULT-PROPOSED `questions.github.shape: comments_on_one_issue` — *rationale: his words are «єдиний
канал» and «github issues, з якимось окремим тегом»; one issue with a tag is the single-thread reading
and one issue per question is the many-threads reading. One thread is closer to «єдиний файлик», and
the label is still there.* Value `issue_per_question` is available and is the right choice when he
wants each question to carry its own notification.

**The channel may be a different place from the task board, and usually is.** «І це може бути
налаштовано інше, аніж … таск менеджер, який використовує оркестратор.» The connector resolution is
independent: `connectors.tasks` and `connectors.questions` are separate sources with separate `use`
blocks, and the orchestrator never assumes one implies the other.

**The channel is read from the main checkout.** Same rule and same reason as §1.2. FIELD-NOTES §12.5
records this exact file forking into a worktree's own copy with a real owner-facing question invisible
for an hour (VERIFIED). A `file` channel whose resolved path is inside a worktree is a **preflight
refusal**, not a warning.

### 9.4 How an answer is detected

Deterministic, no model, on every tick. An entry `qid` is **answered** when **any one** of these holds:

1. a line consisting of exactly `## <qid>` exists in the `ORCH:ANSWERS` region, with at least one
   non-blank line under it before the next `## ` heading or the region's end; **or**
2. a line matching `^Answer:` exists inside `qid`'s own block in the `ORCH:QUESTIONS` region; **or**
3. on a board channel, a comment exists in `qid`'s thread whose author is not the orchestrator's own
   identity and whose body contains `<qid>` or which is the first foreign comment after the entry.

Signals 1 and 2 are the two that were in production and that the owner's own README documents:
*"A question is answered when a line consisting of exactly `## <id>` exists below. That heading is the
signal a waiting session watches for"* (VERIFIED). Signal 2 exists because an answer given in the room
and written into the entry leaves no heading for anyone to find — also VERIFIED as the practice.

**The reference implementation, for the `file` kind, in one `awk`.** This is the check the previous
generation ran every 60 seconds in production and it is kept, widened to the fenced regions:

```awk
awk -v id="$qid" '
  $0 == "<!-- ORCH:ANSWERS -->"  { reg="A"; next }
  $0 == "<!-- /ORCH:ANSWERS -->" { reg="";  next }
  $0 == "<!-- ORCH:QUESTIONS -->"  { reg="Q"; next }
  $0 == "<!-- /ORCH:QUESTIONS -->" { reg="";  next }
  reg=="A" && $0 == "## " id { a=1; next }
  reg=="A" && /^## / { a=0 }
  reg=="A" && a && NF { n++ }
  reg=="Q" && $0 == "## " id { f=1; next }
  reg=="Q" && /^## Q-/ { f=0 }
  reg=="Q" && f && /^Answer:/ { n++ }
  END { print n+0 }' "$channel"
```

`0` means keep waiting. Anything above `0` means settled.

**Corrections.** If an answer needs correcting, a second block under the same id is appended and **the
later block wins**. The orchestrator compares the digest of the answer text it acted on against the
current one every tick until the entry is `Status: answered`; a changed answer for an entry already
acted on raises a Д9-shaped event (§10) rather than silently re-running.

**A deferral is a complete answer.** «Later» or «I don't know» means: take the `Fallback`, set
`Status: answered`, record the fallback as the decision with the deferral's trigger beside it. This is
VERIFIED as the production rule and it is the difference between a channel and a deadlock.

### 9.5 How an answer reaches the blocked lane

This is where his «в лайв режимі» meets what the platforms can actually do, and the honest answer has
three tiers. ADAPTER-CONTRACT §G states the degradation plainly: where an instruction cannot be
delivered mid-turn, **Д6's «враховує відповіді наживо» becomes «at the next task boundary»**
(VERIFIED across fifteen platforms).

```
DELIVER(qid, answer_text):
 1. resolve the waiter: questions/<qid>.json carries {item_id, lane_id, waiting_kind}.
 2. write the answer to ${STATE}/projects/<pkey>/questions/<qid>.answer.md  (durable, always).
 3. if no live lane -> TIER C.
 4. adapter.capabilities.intervention:
      "native"   -> TIER A
      "emulated" -> TIER A if the lane's status() == idle, else TIER B
      "impossible" -> TIER B
```

**Tier A — delivered mid-turn.** `send(handle, text, "steer")` per ADAPTER-CONTRACT §2.3.
- `Ack` is a **state machine, not a boolean**: `accepted ≠ delivered ≠ processed`. An `accepted` ack is
  **never** recorded as delivered.
- On `accepted`, confirm downstream: scan the lane's transcript for the answer's marker within
  `answer.confirm_seconds` (DEFAULT-PROPOSED **120** — *rationale: longer than a model turn, shorter
  than a tick pair, so a failure is visible within two ticks*). No confirmation → fall to Tier B.
- **The answer text is never sent by keystroke.** VERIFIED, FIELD-NOTES §12.1: `send` **fails silently
  above roughly 200 characters**, and a 149-minute stall happened because a submit never landed. So on
  any keystroke-based transport the payload is a pointer, always under 200 characters:
  `ANSWER Q-0412-01 -> read <abs path> and continue`. The answer itself is on disk from step 2.
- Every declined or refused question is logged. Silent decline is the documented killer
  (ADAPTER-CONTRACT §2.3, Droid).

**Tier B — at the next boundary, which is the honest degradation.** The answer is attached to the
item's state and applied when the lane next reaches a boundary the engine defines (R1-08 [209]: what
counts as a step is itself configurable). If the lane is in `needs-input`, the boundary is now: the
lane is resumed or relaunched with the answer in its seed. `status.json` says
`answer_delivery: "boundary"` for that lane, so the difference between "live" and "next boundary" is
visible rather than implied.

**Tier C — no live lane.** The answer is recorded on `items/<id>.json`. If the item's role is
`needs-input` and `FLOOR` passes, it returns to `ready` and is claimed on a later tick like any other
item. If the item is `done`, the answer is a Д9 input (§10).

DEFAULT-PROPOSED `answer.delivery: auto` — *rationale: `auto` picks the highest tier the adapter can
prove; the alternatives are `boundary_only`, which never touches a running session and is the safest
posture on a platform whose intervention is `emulated`, and `off`.*

### 9.6 The mirror, and why it exists

`${STATE}/projects/<pkey>/questions/<qid>.json` holds
`{qid, kind, item_id, lane_id, posted_at, fallback, deadline, status, answer_digest, delivered_at,
delivery_tier}`.

Reason: a channel outage must not lose a question, and `orchestrator:status` must be able to print the
open questions **without a network call** (Д11's token concern). Grafted from `ARCH-operability` §3.1.
The channel remains the truth; the mirror is a cache with an explicit `stale_at`.

### 9.7 The fallback fires

At `Deadline`, if still unanswered:

```
1. apply Fallback, exactly as written. Do not improvise around it.
2. append "Decision: fallback applied at <ts> — <fallback text>" into the entry.
3. set Status: answered.
4. journal question_fallback_applied.
5. notify once through the configured channel (R1-17).
```

DEFAULT-PROPOSED `questions.default_deadline_hours: 0` (never) — *rationale: Д7's default is «стає та
чекає», and a deadline that fires by default would quietly convert his controlled run into an
autonomous one. A lane that writes an entry may set its own `Deadline`, and a run in autonomous mode
may set `questions.default_deadline_hours` to a number; the **default** does not decide for him.*

---

## 10. Contradicting changes (Д9)

> «Оркестратор вирішує, і оркестратор, скоріш за все, зробить просто нове завдання … якщо вже
> завдання виконане, але воно змінене, то оркестратор задати перевагу тому, щоб зробити новий тікет …
> Якщо це під час виконання, то оркестратор вирішує, чи прямо зараз змінити стратегію, зупинити,
> перезапустити з новими інструкціями, чи дочекатися кінця, і все-таки через новий тікет зробити …
> людина також може налаштовувати цей кейс … Чи завжди новий тікет, чи хардстоп, і переробка з нуля …
> Або ж автоматичний режим, коли оркестратор сам буде вирішувати» [482] — confirmed «Так» [486]

### 10.1 The two branches are decided by the item's role, not by a judgement

```
ON_SPEC_CHANGE(item, verdict, anchors_touched, anchors_ticked_touched):
  if item.role == done             -> BRANCH_FINISHED      (his preferred branch)
  if item.role == active           -> BRANCH_IN_FLIGHT
  if item.role in {ready, backlog} -> re-run FLOOR. Pass -> nothing happens, the new text is
                                       simply what gets claimed. Fail -> role needs-input.
  if item.role == needs-input      -> re-run FLOOR. Pass -> ready.
```

### 10.2 The contradiction test, decided on anchors rather than prose

This is what gives «оркестратор вирішує» something concrete to decide on.

| condition | classification |
|---|---|
| `anchors_ticked_touched` is non-empty | **contradiction** — a criterion already satisfied has been changed |
| `verdict == "outcome"` or `verdict == "scope"` | **contradiction** — the item's purpose or boundary moved |
| only unticked anchors touched, `verdict == "criteria"` | **in-flight adaptation** |
| `verdict == "cosmetic"` | **no action.** Update the watermark and stay silent |

A `done` item has every anchor ticked by definition, so any `criteria`-grade change to a `done` item is
a contradiction. That is why BRANCH_FINISHED is his preferred branch: it is the common case.

### 10.3 `BRANCH_FINISHED` — the new item

```
1. compose the new item's spec:
     ## Outcome      — what the change asks for, in the owner's changed words
     ## Scope        — "the part of <id> that criterion #N covers", plus what must not change
     ## Acceptance criteria — one criterion per touched anchor, restated from the new text
2. create it through the backend (op item.create, evidence board_readback, §5.5).
3. read back its id. NEVER compose one (§2.2).
4. write origin: {supersedes: "<old id>", anchors: ["#2"], generation: <old.generation + 1>,
                  run_id: "<this run>"}.
5. link natively, not in prose:
     github  -> addBlockedBy / addSubIssue mutations (VERIFIED present in the live schema)
     clickup -> the native `dependencies` field (VERIFIED present on the task object)
     local   -> depends_on + a `supersedes:` frontmatter key
6. comment on the OLD item, once: "superseded in part by <new id> for criterion #2".
7. the OLD item stays `done`. It is not reopened.
8. set the new item's role to `backlog` or `ready` per §10.4.
```

Step 5 matters because otherwise the record of *why* a second item exists survives only in comments,
and C3-A12 shows comments are the thing that gets overwritten.

### 10.4 The chain, bounded — C3-A8

A Д9 item has to be `ready` to ever run, and Д2 says anything that becomes `ready` during the run is
picked up during the run. So the orchestrator can file work for itself, claim it, and file more. That
is not a debating point: FIELD-NOTES §11.6 records an 85-minute loop nothing internal broke, and a dead
run flagging the same condition every three minutes **for about five days, 1,085 times, unresolved**
(VERIFIED).

Three bounds, each a number he can change:

DEFAULT-PROPOSED `tickets.max_generation: 1` — *rationale: one machine-authored hop from a
human-authored item is the case he described; a second hop means the orchestrator is now reacting to
its own output, which is the loop. An item at the cap is not claimed, its role is `needs-input` with
`reason: generation_capped`, and it is posted to the questions channel.*

DEFAULT-PROPOSED `tickets.machine_authored_ready: false` — *rationale: a Д9 item is created as
`backlog`, not `ready`, so it is visible at 09:00 and is **not** picked up in the run that created it.
This is a real restriction on Д2 as he stated it, it is deliberate, and it is in §15. The alternative
is C3-A8's 04:00 chain with no human awake.*

DEFAULT-PROPOSED `tickets.max_supersedes_per_item: 1` — *rationale: a second follow-up for the same
original in the same run means the first one did not settle it, and that is a question, not another
item.*

### 10.5 `BRANCH_IN_FLIGHT` — his four options, as a setting

| `change.on_contradiction` | behaviour |
|---|---|
| `adapt` | deliver the change to the running lane through §9.5's DELIVER and let it continue |
| `restart` | stop the lane (`stop`, soft), release the claim, re-claim with the new spec, new `spec_digest` |
| `finish_then_new` | let the lane finish against the **old** spec, then run BRANCH_FINISHED |
| `new_ticket` | stop nothing; open the new item now; the lane finishes against the old spec |
| `auto` | the orchestrator chooses — his «автоматичний режим» |

DEFAULT-PROPOSED `change.on_contradiction: finish_then_new` — *rationale: it is the one branch that
loses no work and needs no judgement. `adapt` requires an intervention capability that is `impossible`
on several platforms; `restart` throws away work the owner is paying for; `auto` needs a model call on
every change and is exactly where an 04:00 misjudgement becomes a night. His stated preference for
finished work — «задати перевагу тому, щоб зробити новий тікет» — is preserved, and the in-flight
choice is the cheapest route to the same end state.*

DEFAULT-PROPOSED `change.on_adaptation: adapt` for the **non**-contradiction case (only unticked
anchors touched) — *rationale: an unticked criterion has cost nothing yet; delivering it is free and
is what he would do.*

**The lost qualifier is recorded here.** [468] «Тобто, може бути момент» and [471] «з … підстави чогось
в моменті» were talked over and never recovered (VERIFIED). They read like a condition on **when** a
mid-flight change may be acted on — plausibly "only at a moment when it is safe to". If that is what he
meant, `change.on_contradiction: adapt` needs a boundary qualifier this spec does not have. §15 asks.

---

## 11. Journal records

One line per fact, NDJSON, ≤ 4,096 bytes (`ARCH-operability` §3.2: a truncated last line is one lost
fact, not a lost file). Every record carries `ts`, `run_id`, `type`, and `schema: 1`.

| `type` | payload | written when |
|---|---|---|
| `sweep` | `{backend, hits, cost, budget_left, duration_ms}` | every tick |
| `floor_check` | `{item_id, result, reasons[]}` | every floor evaluation that fails, and every claim |
| `claim` | `{item_id, lane_id, epoch, primitive, evidence}` | §4.3 step 6 |
| `claim_refused` | `{item_id, reason}` | any SKIP in §4.3 |
| `claim_reclaimed` | `{item_id, dead_run_id, last_heartbeat}` | §4.5 step 5 |
| `foreign_claim` | `{item_id, run_id, host, pid}` | §4.5 step 2 |
| `board_write` | `{item_id, op, action_id, outcome, evidence}` | every mutating board call |
| `board_degraded` | `{op, error, http_status}` | §5.4 |
| `self_write` | `{item_id, digest}` | §8.4 step 3 |
| `spec_changed` | `{item_id, verdict, anchors[], ticked[], diff_bytes, model, cost}` | §8.4 step 10 |
| `watcher_unparseable` | `{item_id, raw_head}` | §8.4 step 8 |
| `intake` | `{ready_now, added_since_start, mode, capped}` | every tick where the count moved |
| `question_posted` | `{qid, kind, item_id, fallback_present, deadline}` | §9 |
| `question_answered` | `{qid, signal, answer_digest, latency_s}` | §9.4 |
| `question_delivered` | `{qid, lane_id, tier, ack_status, confirmed}` | §9.5 |
| `question_fallback_applied` | `{qid, fallback}` | §9.7 |
| `superseded` | `{old_id, new_id, anchors[], generation}` | §10.3 |
| `harvest` | `{item_id, oracle, verdict}` | §4.6 |

---

## 12. Configuration — every key, its slot, its type, its default

Obeying `<baseline-marketplace>`: six slots, three levels, **a person's own files beat the project's
committed files** (`OWNER-DECISIONS` 4.15), the config read is **mandatory** (4.10), and
`recommended.json` is **advice, never a value** (2.2, 3.8).

### 12.1 Which file each key goes in

`OWNER-DECISIONS` 3.4's reusability test: almost everything is usable by more than one plugin and
belongs in the general config; a value reaches a per-plugin file only when nothing but that plugin can
use it.

| Goes in the **general** config (`…/shared/identity.json`) | Why |
|---|---|
| `connectors.tasks` (`use`, `never`, `fallback`, `x-orchestrator`) | the task manager is 3.4's own worked example of a general-config value |
| `connectors.questions` | an "ask the human" channel is plainly usable by more than one plugin |
| `connectors.notify` | R1-17's channel; same test |

| Goes in **`…/shared/plugins/orchestrator.json`** | Why |
|---|---|
| everything in §12.2 below | run behaviour no other plugin can act on |

Precedence, lowest to highest (`OWNER-DECISIONS` 4.15, verbatim):

```
1  ./.claude/shared/identity.json                  project, general, committed
2  ./.claude/shared/plugins/orchestrator.json      project, this plugin, committed
3  ~/.claude/shared/identity.json                  user, general
4  ~/.claude/shared/plugins/orchestrator.json      user, this plugin
5  ./.claude/shared/identity.local.json            project, general, personal
6  ./.claude/shared/plugins/orchestrator.local.json project, this plugin, personal
```

Plus the run scope, which is **not** a seventh file: `--set key=value` on the run command, and the
control file the tick re-reads. That is what makes Д7 [458] work (§12.4).

### 12.2 The table

Every row is DEFAULT-PROPOSED unless the Source column names a row of the transcript.

| Key | Type | Default | Source / rationale |
|---|---|---|---|
| `tasks.backend` | `local\|github\|clickup\|<adapter>` | — (preflight asks) | [129]. No default: he named two modes and neither is "whichever" |
| `tasks.ready_requires` | string[] | `["Outcome","Scope","Acceptance"]` | previous generation's three; measured clean over 327 items |
| `tickets.require_ac_fence` | bool | `false` | would refuse all 327 existing items on day one |
| `tickets.sufficiency_judge` | `on\|off` | `on` | his [422] behaviour, one cheap call per claim |
| `tickets.model_may_promote` | bool | `false` | keeps «її притримувався» [146] authoritative over [422] |
| `tickets.sufficiency_model` | role ref | `roles.watcher` | one knob, not two; Д8 [466] already configures this model |
| `tickets.max_generation` | int | `1` | bounds C3-A8's self-feeding chain |
| `tickets.machine_authored_ready` | bool | `false` | a Д9 item is visible at 09:00 before it runs |
| `tickets.max_supersedes_per_item` | int | `1` | a second follow-up is a question, not an item |
| `intake` | `open\|capped\|frozen` | `open` | his behaviour [422], confirmed [426] |
| `intake.cap` | int | `20` | `ARCH-operability`'s number, unchanged so the designs do not diverge |
| `intake.notify_on_growth` | int | `50` | fires before the measured 236→327 delta of 91 |
| `intake.machine_may_create` | bool | `true` | Д9 needs it; P5 probes it at connect |
| `claim.board_cas` | bool | `true` where `native` | the only defence against a restarted orchestrator (Д10 [497]) |
| `claim.stale_minutes` | int | `45` | the shipped default is 7 days, which hides a dead run for a week |
| `claim.reclaim_foreign` | bool | `false` | [300] forbids overriding a live foreign orchestrator |
| `board.poll_seconds` | int | `60` | matches the tick; 2.4% of the GitHub budget; production-proven rate |
| `board.max_requests_per_minute` | int | `50` (clickup) | half the measured 100/min, leaving him headroom on the same token |
| `board.comment_mode` | `append\|edit_last` | `append` | `--edit-last` leaves one comment and no trail (C3-A12) |
| `board.comment_events` | string[] | `["claimed","needs_input","done","failed","superseded"]` | a trail, not a per-tick log |
| `board.writeback` | bool | `true` | [149]. On `local` it means the frontmatter key only (§5.1) |
| `board.identity_recheck_seconds` | int | `300` | the `GH_CONFIG_DIR`-by-cwd hazard (§3.2) |
| `connect.on_probe_fail` | `refuse\|degrade\|create` | `refuse` | the only reversible one of the three (C3-A7) |
| `connect.probe_item` | id | unset → created | never probe a real item |
| `process.roles_required` | string[] | `["ready","active","done"]` | his plain case, verbatim [153] |
| `watch.scope` | `active\|active_ready\|active_ready_done\|all` | `active_ready_done` | Д9's headline case has no trigger otherwise (C3-A3) |
| `watch.done_window_hours` | int | `24` | covers the overnight case; a permanent window collides with Д3 |
| `watch.max_diff_bytes` | int | `8192` | measured max body is 20,144; the tiering exists to avoid sending bodies |
| `watch.max_model_calls_per_hour` | int | `20` | bounds the loop, not only the bill (`JUDGE-cost` G1) |
| `watch.on_unparseable` | `escalate\|ignore` | `escalate` | waiting is the fail-safe |
| `roles.watcher` | model+account pin | unset → preflight asks | Д8 [466]: «має бути налаштування, якою моделькою перевіряти» |
| `change.on_contradiction` | `adapt\|restart\|finish_then_new\|new_ticket\|auto` | `finish_then_new` | loses no work, needs no judgement, reaches his preferred end state |
| `change.on_adaptation` | same enum | `adapt` | an unticked criterion has cost nothing yet |
| `questions.channel` | connector ref | unset → preflight asks once | [449]: «ми йому можемо задати питання» |
| `questions.layout` | `single_file\|two_files` | `single_file` | «єдиний файлик» is his word |
| `questions.github.shape` | `comments_on_one_issue\|issue_per_question` | `comments_on_one_issue` | closest to «єдиний канал»; the label is still there |
| `questions.label` | string | `orchestrator:question` | his «з якимось окремим тегом» [449] |
| `questions.require_fallback` | bool | `true` | the field that made 11 of 11 work |
| `questions.default_deadline_hours` | int | `0` (never) | a default deadline converts a controlled run into an autonomous one |
| `questions.poll_seconds` | int | `60` | the rate that ran in production |
| `answer.delivery` | `auto\|boundary_only\|off` | `auto` | takes the highest tier the adapter can prove |
| `answer.confirm_seconds` | int | `120` | longer than a turn, shorter than two ticks |
| `when_only_blocked` | `wait\|finish\|ask` | `wait` | **his own stated recommendation** [455] |
| `when_only_blocked.max_minutes` | int | `0` (forever) | [455] says stay and wait; a timeout would decide for him |
| `when_only_blocked.hold_tick_seconds` | int | `300` | a held run polls the channel and nothing else |
| `harvest_evidence` | `observed\|strict\|off` | `observed` | the two errors are not symmetric |
| `evidence.readback_sample` | float per op class | role write `1.0`, comment `0.0` | a wrong role causes double work; a comment is a trail |

### 12.3 `recommended.json` — advice, never a value

`plugins/orchestrator/config/recommended.json` (`OWNER-DECISIONS` 3.8). Nothing here is read as a
setting; the configurator shows it and the person chooses.

```json
{ "schema": 1,
  "connectors": {
    "tasks": { "strength": "weak",
      "options": [
        {"kind": "cli", "command": "gh", "note": "GitHub Issues — the issues live with the project"},
        {"kind": "cli", "command": "clickup-cli", "note": "ClickUp — no free change poll; see the note below"},
        {"kind": "file", "note": "a local registry inside the project"}] },
    "questions": { "strength": "weak",
      "options": [
        {"kind": "file", "path": ".orchestrator/QUESTIONS.md"},
        {"kind": "github_issue"},
        {"kind": "tracker_task"}] } },
  "notes": {
    "clickup": "No conditional requests and no description-change field: watching a claimed item costs a full task fetch per change. Supported for reading, status writes and comments; mid-flight change watching is emulated." } }
```

`strength: weak` on `tasks`, not `strong`, and this is deliberate. His GitHub Issues preference is
**hedged** — «Першим ділом рекомендувати GitHub Issues, тому що для конкретно проекта і **напевно** в
цьому перевага» [129] — and `extract/corrections.md:56` records it as a hedged first recommendation,
against ANALYSIS-01 which states it flatly. `OWNER-DECISIONS` 2.3 puts the task manager in the weak
band by name. The *reason* he gave — the issues live with the project — is carried in the note, because
that reason, not the brand, is the criterion for judging any other board.

### 12.4 Mid-run change (Д7 [458], R1-07 [195])

> «якщо раптом, я хочу змінити цю поведінку під час цього запуску … оркестратор повинен це зчитувати
> та приймати … навіть якщо на початку я обрав інший варіант. Або якщо в мене в дефолтній
> налаштуванні інше» [458]

| Key class | pickup | why |
|---|---|---|
| **hot** — `when_only_blocked`, `intake`, `change.*`, `watch.*`, `questions.*`, `answer.*`, `board.comment_*` | **next tick** | [458] names `when_only_blocked` explicitly and it is the one he called «дуже важливо» |
| **warm** — `claim.*`, `board.poll_seconds`, `tickets.*` | next claim | changing them mid-claim would invalidate a lease already taken |
| **cold** — `tasks.backend`, `connectors.*.use`, `process.roles_required` | **never mid-run** | changing the backend mid-run orphans every claim |

A cold key changed mid-run is **not** applied; `status.json.config_pending` names it and the next run
picks it up. That is a refusal, and it is visible.

The mechanism is the control file the tick re-reads (`ARCH-minimal` §2.2), and the six config files
are watched by `(mtime, size)` on the same tick — which is what he described at [195], mtime named as
the mechanism.

---

## 13. What is impossible as stated, and what keeping it costs

**13.1 «Будь-яка інша тула» as an unqualified promise.** [129] sets the bar at access — «треба просто
переконатися, що є доступ … Та й все». But this component then requires four more capabilities of the
same board: set statuses [149], leave comments [149], expose a readiness marker [146], and permit a
**silent** change check [466]. Access implies none of them. **Impossible clause: "any board, with
nothing else verified."** Cost of keeping the promise: §3.3's three-valued capability map, §3.1's five
probes, and an honest `impossible` printed at connect instead of a failure at 03:00. Roughly 150 lines
per adapter. Kept.

**13.2 A silent change-watcher on ClickUp, at the fidelity GitHub gives.** VERIFIED: no conditional
requests (`cache-control: no-cache, no-store`, no `etag`), no description-change field in the payload
(`date_created`, `date_updated`, `date_closed`, `date_done` and nothing else), and the only precise
description-change signal is the webhook `history_items.field == "content"` (CLAIMED) — which a laptop
with **no public ingress** cannot receive. Adding a tunnel means a hosted relay, a stable URL, a secret
to rotate and a component that is down when the laptop sleeps, against «нічого надприроднього не
потрібно вигадувати» [171]. **Impossible clause: "free silent poll on ClickUp."** Cost of keeping the
requirement: one full task fetch per *changed* item per tick, bounded by §6.1's budget, and Tier 1
graded `emulated` rather than `native`. Kept, degraded honestly.

**13.3 «В лайв режимі» answers on every platform.** VERIFIED across fifteen platforms
(ADAPTER-CONTRACT §G): Gemini CLI headless **aborts the turn** on a mid-run prompt; `dsh` ACP is
impossible mid-prompt; Claude Code's `--bg` session cannot be answered at all. **Impossible clause:
"live on every platform."** Cost of keeping it where it is possible: §9.5's three tiers and a
`status.json` field naming which tier a lane got. Where Tier A is impossible, «наживо» becomes «at the
next task boundary», and the spec says so rather than implying otherwise.

**13.4 Config-by-asking during an unattended run.** [133] says a run that finds a missing setting asks
for it. Д11 [508] says the orchestrator outputs nothing and takes no input. **These cannot both hold
during an unattended run.** C3-A4's 23:50 case is the whole unattended use case, and the question the
orchestrator would ask — «which of your board's statuses means in-progress?» — has no answer available
at the terminal: his own live ClickUp list has `review` typed `done` and `ongoing`/`in progress` both
typed `custom`, so he would have to go and read the board. Resolution in this spec: **every question
this component can ask is asked at `connect` or `preflight`, never during a run.** A run that reaches a
missing setting does not ask; it refuses to start the affected work, posts to the questions channel
with a fallback, and continues everything else. That satisfies Д11 and defers [133] to a moment when he
is awake. It is a real narrowing of [133] and it is in §15.

---

## 14. Tensions — designed for, recorded, not replaced

1. **The local item file stops being a working surface** (§5.1). He called the board «помічник … щоби
   ставити статуси таскам, залишати якісь коментарі» [149]. This spec keeps that on a board and takes
   it away from the local file, moving the trail into run state. Buys: C3-A1, C3-A10 and C3-A2 all
   close. Costs: the local file is no longer a self-contained record.
2. **The board is a mirror, not the source of truth** (§5.4). Inverts his framing. Buys: a 403 at
   03:00 does not stop the run. Costs: the board can be stale, and a person reading it at 09:00 may see
   less than the run knows. Mitigated by `board_sync` in the status pull.
3. **`tickets.model_may_promote: false`** (§7.3) chooses [146] over one reading of [422]. It is a
   choice between two of his sentences and it is flagged as such.
4. **`tickets.machine_authored_ready: false`** (§10.4) narrows Д2 as stated: a Д9 item is not picked
   up in the run that created it. Buys: C3-A8's chain is bounded. Costs: an overnight change he
   expected to be applied by morning is waiting as `backlog` instead.
5. **`intake: open` against two judges.** `ARCH-operability` and `JUDGE-survival` both want a cap. I
   kept his behaviour and shipped the notification instead. If the 90-item bulk-file night happens, the
   notification fires and he acts; the cap would have been quieter and would also have been my
   decision rather than his.
6. **Д8's confirmation is narrower than it reads** (§8), and a qualifier of his about acting «в
   моменті» was talked over and lost. This spec's `change.on_contradiction` default may be answering a
   question he was in the middle of qualifying.
7. **The claim is project-scoped, not run-scoped** — a departure from the winning design (§4.2).
   Buys: a dead run's abandoned work is visible on the next run's first tick instead of after seven
   days. Costs: state that outlives the run and must be garbage-collected; `orchestrator:doctor` lists
   claims with no live holder.
8. **Two decisions in this cluster were never ratified aloud** — the board-status check
   ([154]/[155] → [156]) and the config lifecycle ([134]/[137] → [138]) — and ANALYSIS-01 records both
   as SETTLED (VERIFIED, `extract/corrections.md:84,85`). This spec implements both. §15 asks whether
   to re-put them.

---

## 15. Needs the owner — round-2 questions, in plain Ukrainian

Each is something I had to invent because he never decided it. The `[anchor]` is the transcript row the
question sits on. Where a question already exists in `C3-work-source-questions.md` it is marked, so
round 2 does not ask twice.

**Q-W-01 — Куди оркестратор пише свої коментарі? [149] × [466]** *(= C3 Q1)*
«Ти хочеш, щоб дошка була помічником: щоб оркестратор ставив статуси і лишав коментарі. І окремо ти
хочеш, щоб слідкувач за змінами мовчав, коли нічого не змінилось. Але коментар оркестратора — це теж
зміна тікета. Я зробив так: на дошці оркестратор коментує, а в локальний файл завдання не пише нічого,
крім одного рядка статусу — весь свій лог він тримає окремо. Так правильно, чи ти хочеш, щоб лог лишався
в самому файлі завдання?»

**Q-W-02 — Чи може агент сам поставити «готово до роботи»? [146] × [422]** *(= C3 Q5)*
«Ти сказав дві речі: що має бути структура, якої агент притримується, і що агент може подивитись на
опис і, якщо його достатньо, взяти завдання. Я вирішив так: структура головна — агент може лише
відмовитись і поставити "needs review", але не може сам написати "готове до роботи" на твоєму тікеті.
Це те, що ти мав на увазі, чи агент усе-таки може підвищувати статус сам?»

**Q-W-03 — За чим стежити після завершення? [466] × [482]** *(= C3 Q3)*
«Слідкувач стежить за завданням, поки воно в роботі. Але твоє головне правило про новий тікет — про
завдання, яке вже виконане і потім змінилось. Я поставив за замовчуванням: стежимо ще 24 години після
того, як завдання закрите. Скільки насправді має тривати це вікно — доба, тиждень, чи взагалі завжди,
поки ран живий?»

**Q-W-04 — Чи можна брати завдання, яке оркестратор сам собі створив? [482] × [422]** *(= C3 Q10)*
«Коли ти змінюєш уже виконане завдання, оркестратор створює новий тікет. А за твоїм правилом усе, що
стало готовим під час рану, береться в роботу. Виходить, він може створити роботу сам собі й одразу її
взяти. Я поставив запобіжник: такий тікет створюється як "backlog", а не "готовий", і чекає на тебе
зранку. Це правильно, чи ти хочеш, щоб він брав його одразу тієї ж ночі?»

**Q-W-05 — Чи потрібна стеля на прийом нових завдань під час рану? [422]** *(= C3 Q8, розширено)*
«Твоя черга одного разу виросла з 236 до 327 за день, і ти сам поставив паузу руками об 11:15. Я
лишив твою поведінку — беремо все, що стало готовим, без стелі — і додав лише сповіщення, коли черга
виросла на 50. Цього досить, чи ти хочеш реальну стелю на кількість завдань, узятих за один ран?»

**Q-W-06 — Що робити, коли дошці бракує потрібного статусу? [153]**
«Ти сказав, що на дошці має бути мінімальний набір статусів і що це треба перевіряти. Ти не сказав, що
робити, коли статусу бракує. Є три варіанти: відмовитись підключати дошку; створити відсутні статуси
самому; або працювати без нього. Я поставив "відмовитись", бо створення статусів змінює чужу дошку о
четвертій ранку. Який з трьох?»

**Q-W-07 — Чи достатньо одного оркестратора, чи потрібен ще атомарний клейм? [300] × [497]**
«Твоє правило, що одночасно працює лише один оркестратор, робить подвійний клейм неможливим. Але Д10
допускає, що оркестратор перезапустився, а виконавці ще живі. Я додав другий шар: локальний
`mkdir`-замок і, на GitHub, гілку `orch-claim/<id>` як атомарний клейм. Це майже нічого не коштує, але
додає у твій репозиторій службові гілки. Лишаємо, чи прибираємо?»

**Q-W-08 — ClickUp не вміє дешево відповідати «чи змінилось». [129] × [466], твоя інструкція I1**
«Ти назвав ClickUp як рівноцінний варіант. Я перевірив: у ClickUp немає безкоштовної перевірки "нічого
не змінилось" і немає окремого поля про зміну опису — щоб дізнатись, чи змінився опис, треба щоразу
тягнути завдання цілком, а бюджет там 100 запитів на хвилину. На GitHub це безкоштовно. Три варіанти:
прийняти цю ціну; опитувати ClickUp рідше, ніж GitHub; або сказати, що ClickUp підтримується для
читання, статусів і коментарів, але не для стеження за змінами на льоту. Який?»

**Q-W-09 — Що ти хотів сказати про «в моменті»? [468], [471]**
«Коли ти відповідав про зміну опису на льоту, ти двічі почав фразу — "може бути момент" і "з підстави
чогось в моменті" — і тебе перебили, це не записалось. Схоже, ти хотів поставити умову, коли саме можна
реагувати на зміну під час виконання. Що це була за умова?»

**Q-W-10 — Один файл чи два? [449]**
«Ти сказав "єдиний файлик" для питань. Але на <work-project> у тебе реально працювали два файли: в одному
сесії писали питання, в другому ти писав відповіді, і сесіям було заборонено туди писати. Я зробив один
файл, але з двома огорожами всередині: зверху пише оркестратор, знизу пишеш ти. Так зручніше, чи все ж
два окремі файли, як було?»

**Q-W-11 — Чи має питання мати дедлайн за замовчуванням? [449] × [455]**
«Кожне питання в каналі несе "Fallback" — що робити, якщо ніхто не відповів. Я НЕ ставив дедлайн за
замовчуванням: без твоєї відповіді нічого само не спрацює, ран просто чекає, як ти й просив у Д7. Але
це означає, що питання, поставлене о другій ночі, може простояти до ранку. Хочеш, щоб через N годин
fallback спрацьовував сам, і якщо так — скільки годин?»

**Q-W-12 — Чи можна питати налаштування під час рану? [133] × [508]**
«Ти сказав: якщо якогось налаштування бракує, оркестратор його питає. І окремо ти сказав, що під час
рану він нічого не виводить і нічого не питає. О 23:50, коли ти вже пішов спати, ці два правила
суперечать. Я зробив так: усі питання про налаштування ставляться на `connect` і `preflight`, а під час
рану він не питає нічого — він відмовляється від тієї частини роботи, пише питання в канал із
fallback, і решту роботи робить далі. Так правильно?»

**Q-W-13 — Чи перепитувати два пункти, які ти так і не підтвердив? [154]/[155], [134]/[137]**
«Два твої пункти з цього кластера не отримали твого "так": перевірка статусів дошки при підключенні і
порядок конфігурації при першому запуску — інтерв'юер пішов далі, не дочекавшись. В аналізі вони
записані як підтверджені. Перепитати їх у другому раунді, чи лишаємо як є?»

**Q-W-14 — Що робити зі старим алокатором id у поточному плагіні?**
«У `~/Work/claude-plugins/plugins/harness/bin/harness-tickets.sh` досі лежить зламаний алокатор id —
виправлення живе лише у встановленій копії і зникне при першому `/plugin update`. Полагодити його зараз
у старому плагіні, чи хай помирає разом з переписуванням?»

---

## Appendix A — worked examples, end to end

Five walkthroughs. Each names the section that governs each step, so an implementer can check their
build against one timeline rather than against seventeen sections. Times are wall-clock on one night.

### A.1 A normal claim, on the `local` backend

```
22:41:00  tick 1. sweep: find items/ -newermt <boot>  -> 6 hits (§6.1)
22:41:00  item 0412 role=ready. FLOOR -> PASS (§2.5). depends_on ["0388"] -> 0388 role=done. OK
22:41:00  generation 0 <= max_generation 1. OK (§4.3 step 4)
22:41:00  mkdir ${STATE}/projects/<pkey>/claims/0412.d       -> created. WE HOLD IT (§4.1)
22:41:00  write claim.json (temp + rename). epoch 7, run_id <work-project>-20260919-224100Z
22:41:00  claim.board_cas: capability for local is the mkdir itself -> nothing further
22:41:00  re-read item, recompute spec_digest -> equal to step 2's. No raced edit (§4.3 step 8)
22:41:01  write items/0412.json {spec_digest: 9c1f…, source_watermark {kind digest}, ac_state
          [{#1,…,ticked_at null},{#2,…},{#3,…}]}
22:41:01  board write: frontmatter role: ready -> active, temp + rename (§5.1)
          evidence: board_readback — re-read the file, observe role: active. ops.json satisfied (§5.5)
22:41:01  append to ${STATE}/projects/<pkey>/items/0412.log.md, event=claimed (§5.1, §5.2)
22:41:01  mkdir lanes/t-0412; write start.json; launch
22:41:01  journal: {"type":"claim","item_id":"0412","lane_id":"t-0412","epoch":7,
                    "primitive":"mkdir","evidence":{"kind":"dir_created"}}
```

**What a second orchestrator racing the same item sees at 22:41:00:** `mkdir` returns `EEXIST`, it
journals `claim_refused {reason: "held"}`, and it moves to the next item. Measured: 1 winner at 50-way
(§4.1). It does not read, check and then write, which is the shape measured at **27 winners of 50**.

### A.2 The owner edits a claimed item at 01:20 — Д8 into Д9

```
01:20:11  he changes criterion #2 from 375px to 390px and saves. Nothing else.
01:21:00  tick. sweep -> 0412 is a hit (mtime moved)                            [Tier 0, §8.1]
01:21:00  recompute spec digest -> differs from items/0412.json.spec_digest     [Tier 1, §8.1]
01:21:00  is this digest one we wrote? no self_write record matches             [§5.3]
01:21:00  prior text: stored at claim time. diff -> 3 lines, 210 bytes          [§8.4 step 5]
01:21:01  call roles.watcher ONCE with the diff and ac_state                    [Tier 2, §8.4 step 7]
          -> {"verdict":"criteria","anchors_touched":["#2"],
              "anchors_ticked_touched":[],"summary":"breakpoint 375px -> 390px"}
01:21:01  #2 is NOT ticked, verdict is "criteria"  -> in-flight ADAPTATION, not a contradiction (§10.2)
01:21:01  change.on_adaptation = adapt (§10.5)
01:21:01  DELIVER to lane t-0412 (§9.5). adapter intervention = native -> Tier A
          send(handle, "SPEC UPDATED 0412 -> read <abs path>/0412.diff.md and continue", "steer")
          Ack {status: "accepted"} -> NOT recorded as delivered (§9.5)
01:21:43  transcript event matching the marker observed within 120 s -> confirmed
01:21:43  update source_watermark and the stored prior text                     [§8.4 step 9]
01:21:43  comment on the item, event=spec_changed                               [§5.2]
01:21:43  journal spec_changed {verdict criteria, anchors ["#2"], ticked [], cost 0.0009}
```

Total model spend for this change: **one** cheap call on a 210-byte diff. Every tick before and after
it cost zero tokens.

### A.3 The same edit, but #2 was already ticked — the contradiction

```
01:21:01  watcher -> {"verdict":"criteria","anchors_touched":["#2"],
                      "anchors_ticked_touched":["#2"], …}
01:21:01  ticked anchor touched -> CONTRADICTION (§10.2)
01:21:01  item.role == active -> BRANCH_IN_FLIGHT (§10.1)
01:21:01  change.on_contradiction = finish_then_new (§10.5) -> the lane is NOT interrupted.
          A pending action is recorded on items/0412.json: {on_harvest: "supersede", anchors: ["#2"]}
02:58:20  lane exits. HARVEST: the engine's own oracle is asked, not the exit code (§4.6)
          -> done. FLOOR re-checked on active -> done. PASS (§2.5)
02:58:20  role -> done. board write, evidence board_readback.
02:58:21  pending action fires: BRANCH_FINISHED (§10.3)
          compose spec: Outcome = the 390px requirement; Scope = "the part of 0412 that #2 covers";
          AC = one criterion restated from the new text
02:58:22  item.create -> READ BACK the id: 0455. Never composed (§2.2)
02:58:22  write origin {supersedes: "0412", anchors: ["#2"], generation: 1,
                        run_id: "<work-project>-20260919-224100Z"}
02:58:22  link natively: 0455.depends_on = [] ; 0455 frontmatter supersedes: 0412 (§10.3 step 5)
02:58:22  comment ONCE on 0412: "superseded in part by 0455 for criterion #2"
02:58:22  0455.role = backlog, NOT ready  (tickets.machine_authored_ready: false, §10.4)
02:58:22  journal superseded {old_id 0412, new_id 0455, anchors ["#2"], generation 1}
09:00     he opens the status pull and sees 0455 waiting in backlog with its origin.
```

**What the bound prevents:** if 0455 were created `ready`, Д2 would claim it at 02:59, its own status
comments would move its timestamps, and C3-A8's chain — 0455 files 0456 files 0457 — has no upper
bound. Three verified precedents for that shape exist in the previous run: the 85-minute loop, the
five-day 1,085-repetition flag, and the 32-minute 180-second poll doing nothing.

### A.4 A question, asked at 02:41 and answered at 09:12

```
02:41:09  lane t-0412 cannot settle a choice inside its own scope. It first tries: runs the layout
          at both widths, measures, and finds the measurement does not decide it (§9.1, the
          Q-PARITY-01 rule). Residue only.
02:41:09  append to the ORCH:QUESTIONS region of <project>/.orchestrator/QUESTIONS.md, read from
          the MAIN checkout via `git rev-parse --git-common-dir` (§1.2, §9.3):

            ## Q-0412-01
            Kind: question
            Origin: item 0412, lane t-0412, 2026-09-20T02:41:09Z
            Status: open
            Blocks: this item only — nothing else waits on it
            Fallback: take criterion #2 literally at 375px and record the reading as the decision
            Deadline:
            Question: The item says 375px and criterion #2 now says 390px. Which width matters?

          questions.require_fallback: true -> the Fallback line is present, so the write is allowed.
          Without it the write is refused and question_without_fallback is raised (§9.1).
02:41:09  write the mirror questions/Q-0412-01.json (§9.6)
02:41:09  item 0412 role -> needs-input, reason = "Q-0412-01". board write + comment (§5.2)
02:41:09  rmdir the claim? NO. The claim is held; the item is parked, not released (§4.2).
          heartbeat_at keeps refreshing so §4.5 does not reclaim it.
02:41:10  Д6's other half: lanes t-0388 and t-0401 are untouched and keep working (§9, [449])
02:42 .. 09:11   every tick: the awk check (§9.4) returns 0. Zero tokens. Zero model calls.
09:12:40  he appends under the ORCH:ANSWERS fence:
            ## Q-0412-01
            Answer: 390. The old value was wrong.
09:13:00  tick. awk returns 1 -> ANSWERED, signal 1 (§9.4)
09:13:00  write questions/Q-0412-01.answer.md (§9.5 step 2)
09:13:00  no live lane for t-0412 (it exited at 02:41) -> TIER C (§9.5)
09:13:00  answer recorded on items/0412.json. role needs-input -> FLOOR PASS -> role ready
09:13:00  set Status: answered inside the entry. The orchestrator writes ONLY in the
          ORCH:QUESTIONS region; it never touches a byte below the ANSWERS fence (§9.2)
09:14:00  next tick: 0412 is claimed again, with the answer in its seed.
09:14:00  journal question_answered {qid, signal: 1, latency_s: 23211}
```

**If he had instead written `Answer: 390` directly inside the entry in the QUESTIONS region**, signal
2 fires and everything downstream is identical (§9.4). Both signals were in production and both are
supported, because an answer given in the room and written into the entry leaves no heading for anyone
to find.

**If he had written nothing and the entry carried `Deadline: 2026-09-20T08:41:09Z`**, at 08:41 the
fallback applies exactly as written, `Decision:` is appended, `Status` becomes `answered`, and he is
notified once (§9.7). With the shipped default (`questions.default_deadline_hours: 0`) no deadline is
set and the run waits, which is Д7's «залишається та чекає».

### A.5 Only blocked work is left, and he changes his mind at 03:30 (Д7)

```
03:12:00  the last unblocked lane finishes. queue: ready 0, active 0, needs-input 3, done 14.
03:12:00  when_only_blocked = wait, max_minutes = 0 -> the run does NOT finish (§12.2, [455])
03:12:00  tick interval drops to when_only_blocked.hold_tick_seconds = 300 (§12.2).
          The held tick does exactly two things: poll the questions channel and re-read the
          control file. Zero model calls.
03:30:11  he opens a terminal and runs:  orchestrator:set when_only_blocked=finish
          -> the command appends an entry to the control file the tick reads (§12.4)
03:35:00  next held tick. control file (mtime, size) moved -> parse -> entry applied exactly once
          by id, then moved to control.applied.ndjson (never re-fired)
03:35:00  when_only_blocked is a HOT key -> applied this tick (§12.4)
03:35:00  still nothing but blocked work -> the run finishes under Д3: stop what it started,
          release no claims that are parked on a human, write the report.
03:35:00  journal: {"type":"control_applied","key":"when_only_blocked","from":"wait","to":"finish"}
```

That is [458] working literally: «якщо я хочу, щоб прямо зараз це працювало по-іншому, аніж був
запущений оцей оркестратор, то це окей, оркестратор повинен це зчитувати та приймати … навіть якщо на
початку я обрав інший варіант. Або якщо в мене в дефолтній налаштуванні інше.»

---

## Appendix B — the operations an implementer must build, in one list

Ten functions. Nothing else in this spec is new code.

| # | Function | Section | Zero tokens? |
|---|---|---|---|
| 1 | `floor(item) -> PASS \| FAIL(reasons[])` | §2.5 | yes |
| 2 | `normalise_spec(bytes) -> bytes` and `spec_digest` | §2.4 | yes |
| 3 | `sweep(backend, since) -> [(item_id, changed_fields[])]` | §6.1 | yes |
| 4 | `claim(item) -> ok \| skip(reason)` — INV-CLAIM-ORDER | §4.3 | yes |
| 5 | `reclaim(claim) -> released \| stuck \| foreign` | §4.5 | yes |
| 6 | `watch(item) -> silent \| (verdict, anchors)` | §8.4 | one call, only on a real spec change |
| 7 | `classify(verdict, anchors, role) -> contradiction \| adaptation \| none` | §10.2 | yes |
| 8 | `supersede(item, anchors) -> new_id` | §10.3 | yes |
| 9 | `post_question(entry) -> qid` and `detect_answers() -> [qid]` | §9.1, §9.4 | yes |
| 10 | `deliver(qid, text) -> tier_A \| tier_B \| tier_C` | §9.5 | yes |

**Nine of the ten never call a model.** Function 6 calls one cheap model, once, only when a spec
region actually moved and only after three deterministic filters said it did. That is the whole of
what makes an unattended night cost cents rather than dollars, and it is the direct implementation of
his «немає сенсу перевіряти фейбл моделю … чи змінився якийсь тікет» [466].
