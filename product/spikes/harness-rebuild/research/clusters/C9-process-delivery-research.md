# C9 — Workflow-engine adapter, verification, delivery and observability

Cluster items: **R1-03, R1-12, R1-13, Д4, Д11, R1-17**
Written 2026-09-19. Evidence labels: **VERIFIED** = read in source/docs/code or executed on this
machine; **CLAIMED** = a README, doc site or article asserts it and I did not run it;
**INFERRED** = my reading, flagged as mine.

Machine state at time of writing (VERIFIED by execution): macOS Darwin 25.5.0 · `git 2.33.0` ·
`gh 2.92.0` · `jq 1.8.1` · `@opengsd/gsd-core 1.14.0` installed at `~/.claude/gsd-core`.

---

## 1. What the owner decided, quoted

### R1-03 — the orchestrator runs one configured process, and does not own it

> "І людина може налаштувати, чи це буде відповідно до правил ГЕТШЕД Тобто, які там порядок,
> послідовність, тощо далі. Або там може бути, наприклад, суперпауерс, або будь-що інше." [118]

In English, the rest of the answer: the harness is being renamed to the orchestrator, and it acts according to its config.

> "людина може визначити, абсолютно свій процес, який буде відпрацьовувати оркестратор, тобто,
> які дії будуть, за якими, коли перевірка, чи буде перевірка, і так далі, і він може що завгодно
> вписати. Це може налаштовуватись з допомогою якогось ямл файлу, де будуть приписуватись ці кроки
> та чітко їх закриватись. Можливо, не так, тут треба буде подумати, як саме" [118]

> "або комбінувати але, ні, комбінувати ні, тут або або, або свій, або вже готовий, якщо готовий,
> то який саме" [118]

Binding: one process, chosen by config — an existing one (GSD, superpowers, another marketplace's
tooling) **or** a fully user-defined one. **No mixing.** YAML is his own guess, hedged in the same
breath ("Можливо, не так") — so the format is open, not chosen.

Also his, unprompted, in the opening monologue six days earlier:

> "це все в основі - того, аби використовувати якийсь конкретний workflow, наприклад, get shit done,
> super powers або інші, який допомагає робити екзек'ютинг надійним" [007]

### R1-12 — reaching the trunk

> "Це все налаштовується, і людина може як налаштувати, що це має автономно робитися, що агент може
> це сам зробити, або ж, що це обов'язково передається на людину. Ну і, звісно, що не порушується
> правило, якщо, наприклад, в репозиторії якісь інші правила, або, наприклад, обмеження, що там
> можна зробити тільки пул реквесту, тощо, так далі, і це дуже важливо розуміти та приймати. Також
> оркестратор має за можливості гіта, а саме те, що там можна піари стакати, і він це теж може
> використовувати" [331]

> "ці конфігурації повинні працювати приблизно по такому самому флоу, як це працює зараз в Git
> Shodan" [331]  ("Git Shodan" = Get Shit Done — INFERRED from [007]/[118].)

> "людина це налаштовує, і не має конкретного обмеження, як це саме повинно працювати" [334]

Binding: autonomous-vs-handoff is a setting; repository rules bind and he calls that "дуже важливо";
stacked PRs are a capability to exploit; **no universal gate**; the settings flow copies GSD's.

**A recorded loss** (corrections.md:136): [334] opens "Також дуже [важливо…]" and the interviewer's
restatement at [335] runs over it. A point he flagged as very important at R1-12 was never made.

### R1-13 — proving the work happened

> "Якщо в нього щось власне, то ці всі перевірки відбуваються виключно так, як юзер налаштував. … Тобто
> не роби обмеження те, що вся робота потім буде мати тести, і що є якісь готовий воркфлоу, по якому
> саме воно проходить" [344]

In English: verification follows whatever setup the user configured (GSD verifies by its own rules); the plugin may run non-coding work with no tests at all, and the workflow is the user's.

He was given the field evidence first, in the question itself [342]: a truncated suite read as 346
passing, and a merge command that reported success and moved nothing. **It did not move him.** This
is a decision taken under the evidence, not an uninformed one.

### Д4 — worktrees

> "Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі. І постійно переконуватись, що
> всі ті енвайрмент верібли, які потрібні, вони запущені відповідно, тощо, так далі" [433]

In English, the rest of the answer: worktree behaviour is configurable and aligned with the chosen tool (GSD's workspaces), each worktree comes off the main branch with its env vars "або що є якісь запущений стек", and the orchestrator must handle worktrees properly for the user.

Two words the first analysis dropped and that change the requirement: **"постійно переконуватись"**
(continuously, not once at spawn) and **"запущений стек"** (a running stack, not only env vars).

### Д11 — status output

First position [508]:

> "Ні, оркестратор не повинен нічого виводити для мене. … Тобто, якщо я хочу отримати статус виконання,
> то я можу запустити окремий термінал, прописати orchestrator двокрапка статус і таким чином я
> отримую статус теперішнього..."

Then his own correction [512], [514]:

> "Дефолтний варіант, що оркестратор використовує мінімальну кількість аутпуту і стокінгів для цього"
> … "Але людина може це переналаштовувати"

Last-said-wins is his own rule [003]: **"Пізніше сказане перемагає раніше сказане."** So the binding
version is *minimum output and minimum tokens by default, user-reconfigurable*, with status pulled
on demand from a separate terminal. The unsoftened first version still tells you the strength of
feeling about token spend on chatter. Note also: **Д11's corrected version was never confirmed** —
the interviewer asked "Це остаточний варіант, підтверджуєш?" at [515]/[516] and the next line is Д12
(corrections.md:104).

### R1-17 — notifications

> "Та повинен лише переконатися, що це працює. … Людина сама налаштовує, які саме канал зв'язку для
> цього буде, і чи треба взагалі канал якогось зв'язку" [395]

In English, the rest of the answer: the channel can be anything (Telegram, Slack, Gmail, even an agent's phone call) or just the terminal, and the user also configures which event types arrive (critical only, or all).

Binding: any channel, or none; event types configured; **the orchestrator's only duty is to verify
the channel works**. "Чи треба взагалі канал" means *no notifications at all* is a supported config.

Two things the record must carry with it, both from the extraction notes:

- **The substantive half of R1-17 was never answered.** The question asked "що варте того, щоб тебе
  розбудити … що може почекати до ранку"; he redirected the whole thing to configuration
  (by-item.md, R1-17 last row). The interviewer also asked about quiet hours at [394]; [395] does
  not touch them (outside-list.md §13.4).
- **He rejected the night frame of the whole questionnaire** at [054]: "я б взагалі навіть не
  фокусувався на тому, що там щось вночі працює … Можливо, це треба просто трошки правильніше
  розділити, як автономний ран та... контрольований". R1-12 and R1-17 are both worded "вночі" /
  "розбудити". That frame is void; the axis is autonomous vs controlled.

---

## 2. How the world does it

### 2.1 OpenAI Symphony — the closest published analogue to what he described

VERIFIED by fetching `https://raw.githubusercontent.com/openai/symphony/main/SPEC.md` (2026-09-19).
The spec's own shape, quoted from the fetch:

- **The process lives in the repo as one file.** "`WORKFLOW.md` is a Markdown file with OPTIONAL
  YAML front matter" (§5.2). Front matter sections (§5.3): `tracker`, `polling`, `workspace`,
  `hooks`, `agent`, `codex`. The Markdown body below the front matter is the per-issue prompt
  template. Parsing rule: "If file starts with `---`, parse lines until the next `---` as YAML front
  matter. Remaining lines become the prompt body."
- **The tracker is the state machine and the orchestrator only reads it.** "Symphony is a
  scheduler/runner and tracker reader" (§1). `active_states` and `terminal_states` are configurable.
  "Ticket writes (state transitions, comments, PR links) are typically performed by the coding agent
  through provider-native tools" (§1).
- **One persistent workspace per issue.** "Workspace path: `<workspace.root>/<workspace_key>`"
  (§9.1); workspaces survive successful runs (§9.2).
- **Delivery to the trunk is not the orchestrator's business.** The spec defines no PR or merge
  mechanism; that lives in the workflow prompt and the agent's tools.
- **Verification is not the orchestrator's business either** — it runs *preflight* (workflow file
  readable, tracker kind supported, `codex.command` present, §6.3) and *timeouts* (turn, stall,
  read, §10.6), and nothing about the work.
- **Lifecycle hooks are the extension seam**: `after_create`, `before_run`, `after_run`,
  `before_remove`. Failure semantics are asymmetric and explicit: `after_create` failure aborts
  workspace creation, `before_run` failure aborts the attempt, `after_run` and `before_remove`
  failures are logged and ignored (§9.4).
- **Status is an OPTIONAL read API, not stdout**: `GET /api/v1/state` (running sessions, retry
  queue, token totals, rate limits) and `GET /api/v1/<issue_identifier>` (§13.7.2). "Restart recovery
  is tracker-driven and filesystem-driven (without a durable orchestrator DB)" (§6.2, §14.3).
- **Notifications are explicitly not prescribed.** "Each implementation MUST document its chosen
  approval, sandbox, and operator-confirmation posture" (§10.5).

Almost every boundary Symphony draws is a boundary the owner drew independently. INFERRED: that is
convergent evidence his boundaries are the right ones, not a reason to adopt Symphony (R1-18 stands:
"превентивно я буду обирати свій варіант" [403]).

### 2.2 Bernstein — the YAML-DAG end of the spectrum

CLAIMED (README fetched 2026-09-19, not run): declarative YAML DAGs of `agent`, `command` and `loop`
nodes; `loop` nodes take a bash predicate that re-fires until exit 0; `fresh_context: true` mints a
new agent session per iteration; per-step CLI/model routing; stock workflows `idea-to-pr`,
`refactor-with-tests`, `security-review`, `doc-update`, `dependency-bump`, `hot-fix`. "Manifests are
plain YAML, validated up-front."

Its verification layer, the **janitor**, gates merges on concrete signals: test pass rate, lint
status, type correctness, file existence ("owned files produced"), optional coverage delta, optional
mutation score, and arbitrary custom commands. Two tiers: "Required evidence producers gate
completion; advisory producers attach failure records without blocking."

State on disk (CLAIMED): a hash-chained JSONL ledger at `.sdd/runtime/ledger/<run-id>/` recording
`run.open`, `task.scheduled/started/completed/failed`, `run.resumed`; a lineage spine at
`.sdd/lineage/<run_id>/spine.jsonl`; a replay journal at `.sdd/runs/<run_id>/journal.jsonl`. Status
surfaces: `bernstein status`, `bernstein replay list`, `bernstein live`. Chat control via
`bernstein chat serve --platform=telegram|discord|slack` with `/run`, `/status`, `/approve`,
`/reject`.

The README's core claim is the interesting one for this design: **"No model in the coordination
loop, so parallel runs in per-task git worktrees replay byte-identically."** INFERRED: that is the
same instinct as Д11 — the coordinator should be cheap, deterministic and silent, and the model
should only be in the executors.

### 2.3 GitHub Actions — the reference minimum for a step definition

VERIFIED against `docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax`
(fetched 2026-09-19). The per-step keys are: `id`, `if`, `name`, `uses`, `run`, `shell`, `with`,
`env`, `continue-on-error`, `timeout-minutes`, `working-directory`. **There is no retry key at step
level** — retry in Actions is either a whole-job re-run or a third-party action.

### 2.4 Temporal — the reference retry vocabulary

CLAIMED (docs.temporal.io, searched 2026-09-19): `RetryPolicy` = `initialInterval`,
`backoffCoefficient`, `maximumInterval`, `maximumAttempts` (0 = unlimited),
`nonRetryableErrorTypes`. The last field is the one worth stealing: **some failures must never be
retried**, and that is a declaration, not a heuristic. Д5 ("три рази одне і те саме") is a
`maximumAttempts: 3` on *identical* failures; a `nonRetryableErrorTypes` list is what stops the
orchestrator retrying a permission refusal three times.

### 2.5 Stacked PRs — the actual 2026 state

- **Native git**: `git rebase --update-refs` / `rebase.updateRefs` is the primitive that makes a
  stack maintainable without tooling (available from Git 2.38). **VERIFIED NOT AVAILABLE HERE**:
  `git --version` → `2.33.0`, and `git rebase -h | grep update-ref` returns nothing on this machine.
- **`gh` has a native merge-base per branch.** VERIFIED from `gh pr create --help` on this machine
  (gh 2.92.0): "The base branch for the created PR can be specified using the `--base` flag. If not
  provided, the value of `gh-merge-base` git branch config will be used… Run
  `git config branch.{current}.gh-merge-base {base}` to configure the current branch to use the
  specified merge base." That is enough to build a stack with no third-party tool: each branch
  records its parent, and `gh pr create` targets it automatically.
- **Third-party**: Graphite (`gt`), ghstack (Meta, commit-oriented), git-spr / stack-pr (Modular),
  Aviator, git-branchless. CLAIMED, from a 2026 survey and Graphite's own docs. **None is installed
  on this machine** — VERIFIED: `which gt spr ghstack git-spr` → none found.
- **GitHub's own `gh-stack` extension** entered private preview April 2026 (CLAIMED, InfoQ
  2026-04). Too early to depend on.

### 2.6 Notification verification — what a channel can and cannot prove

Three distinct levels, and they are routinely conflated:

| Level | Telegram | Slack | What it actually proves |
|---|---|---|---|
| Credential valid | `getMe` | `auth.test` | The token works. Nothing about reachability of the human. |
| Service accepted | `sendMessage` → `ok:true` + `message_id` | `chat.postMessage` → `ok:true` + `ts` | The message is in the chat. Not that anyone saw it. |
| Human acknowledged | inline keyboard → `callback_query` | interactive block action, or a reaction | The only real proof. |

VERIFIED against `core.telegram.org/bots/api` (fetched 2026-09-19): `getMe` returns a `User` object
with the bot's capability fields — "This proves the bot's capabilities and configuration, not
operational status." **The Bot API documents no read receipts for bot-sent messages.** `callback_query`
exists on the `Update` object and `answerCallbackQuery` exists as a method. `getWebhookInfo` returns
a `WebhookInfo` carrying `pending_update_count`, `last_error_date`, `last_error_message`,
`last_synchronization_error_date` — a real channel-health surface.

CLAIMED (Slack docs, searched 2026-09-19): `auth.test` "checks authentication and tells you who you
are… you can also use this method to test whether Slack API authentication is functional";
`chat.postMessage` returns `ok` plus `ts` and `channel`. **Slack has no per-recipient read receipts
in any channel type** — so "delivered" is the ceiling there too.

The dead-man's-switch pattern (healthchecks.io and equivalents) inverts the problem: instead of
proving each message arrived, the orchestrator pings a external endpoint on a schedule and *the
absence of a ping* raises the alarm on the far side. CLAIMED. INFERRED: this is the only pattern that
survives the orchestrator itself dying, which is precisely the case the field notes record.

### 2.7 Status on demand for a headless daemon — the established shape

Versioned, machine-readable, pull-only status contracts that cost nothing to produce, all VERIFIED by
running them on this machine or by their own documented contract:

- `git status --porcelain=v2 --branch` — a **version number in the flag itself**, so consumers pin
  the format. Executed here; output begins `# branch.oid …`, `# branch.head main`, `# branch.ab +0 -0`.
- `docker compose ps --format json`, `terraform show -json` (carries `format_version`),
  `systemctl show --output=json`. The shared pattern: the daemon writes state to a known place, and a
  separate short-lived command renders it. The daemon itself prints nothing.

---

## 3. What is feasible per platform

### 3.1 GSD — VERIFIED by execution on this machine

GSD is not merely scriptable; it has a **published, versioned host-integration protocol** that is
already the shape of an adapter contract, only pointed at the host rather than at an orchestrator.

**VERIFIED**, `~/.claude/gsd-core/bin/lib/host-integration.cjs`:

```
const PROTOCOL_VERSION = 1;
const INTERFACE_POINTS = Object.freeze(['command', 'dispatch', 'model', 'hooks', 'state', 'artifact']);
const HOST_INTEGRATION_AXES = { embeddingMode, commandSurface, modelMode, hookBus, stateIO,
                                transport, runtime, subagentToolkit, effortSurface, isolation }
const UNDOCUMENTED = 'undocumented';   // "VALIDATES … but NEVER propagates into effective axes"
const SAFE_DEFAULTS = { … }            // "the most restrictive known value per axis … degrade-closed,
                                       //  never assume capability"
function degradationFor(point, axes)   // "NEVER throws. Returns { level:'absent', … unknown:true }"
```

Three design rules in that file are worth taking wholesale (INFERRED as applicable, VERIFIED as
present):

1. **A closed vocabulary per axis.** An out-of-vocabulary value is not a capability verdict.
2. **`undocumented` ≠ `none`.** A missing declaration and a declared absence are different facts and
   must be reported differently. `dispatch-isolation-gate.md` spells out why: telling a Claude Code
   user their runtime "declares no executor-isolation primitive" when the *resolver* failed "is
   false (#2652 review)".
3. **Degrade closed, and say which of the two happened.**

**Machine-readable surfaces that cost zero model tokens** (all executed here against
`/Users/sasha-marchuk/Work/sashko-vps`, a real GSD project):

| Command | Output |
|---|---|
| `gsd-tools progress` | JSON: `milestone_version`, `phases[] {number,name,plans,summaries,status}`, `total_plans`, `total_summaries`, `percent`, `phase_scope` |
| `gsd-tools smart-entry` | one line: `Phase 7 of 7 · 75% · executing` + `Recommended: progress-next → /gsd:progress --next` |
| `gsd-tools state` / `state.load` | the entire resolved config as JSON, including `branching_strategy`, `auto_advance`, `_auto_chain_active`, `mode`, `use_worktrees`, `test_command` |
| `gsd-tools worktree base-check` | JSON: `shouldDegrade`, `reason`, `message`, `headSha`, `forkRef`, `forkSha` |
| `gsd-tools dispatch-isolation` | `harness-worktree` |
| `gsd-tools dispatch-should-flatten` | `true` |
| `gsd-tools git base-branch` | `main` |
| `gsd-tools windows status` | JSON ledger: `open_count`, `waived_count`, `fixed_count`, `entries[]` |
| `gsd-tools workstream list` | JSON: `mode: "flat"`, `workstreams: []` |
| `gsd-tools capability list` | JSON array of `{id, role, version, tier, source, scope, status, surfaced, title}` |
| `gsd-tools runtime-identity` | `{"packageName":"@opengsd/gsd-core","version":"1.14.0"}` |

Global flags that matter to an adapter: `--raw`, `--pick <field>`, `--project-dir <path>`,
`--ws <name>`, `--json-errors`, and **`--exit-contract=v1|v2`** — GSD versions its own exit codes.

**An MCP surface exists too.** VERIFIED from `~/.claude/gsd-core/bin/lib/mcp-server.cjs`: "A minimal
stdio JSON-RPC 2.0 server exposing two of the six interface points" — `gsd_invoke_command`
("interface point 1"), `gsd_read_state` and `gsd_write_state` ("interface point 5"). Both are live in
this session's tool list.

**Twelve named extension points.** VERIFIED, `references/loop-hook-dispatch.md`: `discuss:pre`,
`discuss:post`, `plan:pre`, `plan:post`, `execute:pre`, `execute:wave:pre`, `execute:wave:post`,
`execute:post`, `verify:pre`, `verify:post`, `ship:pre`, `ship:post`. `gsd_run loop render-hooks
<point> --raw` returns `{point, activeHooks[], rendered}` where each hook is one of three kinds:

- `contribution` — inject `fragment.inline` verbatim into a named role's context;
- `step` — dispatch `ref.skill` / `ref.agent` / `ref.command`;
- `gate` — `{check:{query}, blocking:true, onError:"skip"}`.

The `ship` workflow declares its own hook header: `points: ship:pre, ship:post`,
`agent-roles: orchestrator`, `consumes: UAT.md`.

**Resumability, already recorded by GSD**: `.planning/STATE.md`, `ROADMAP.md`, per-phase
`NN-PLAN.md` / `NN-SUMMARY.md` / `NN-VERIFICATION.md`, `.planning/milestone.lock`, per-workstream
directories under `.planning/workstreams/<name>/`, and a session-scoped active-workstream pointer.
VERIFIED, `references/workstream-flag.md`: resolution order is `--ws` → `GSD_WORKSTREAM` →
session-scoped pointer keyed on `GSD_SESSION_KEY` / `CODEX_THREAD_ID` / `CLAUDE_CODE_SESSION_ID` /
`TMUX_PANE` / TTY → `.planning/active-workstream` → flat mode. The doc states the reason plainly:
"The shared `.planning/active-workstream` file is fundamentally unsafe when multiple Claude/Codex
instances are active on the same repo at the same time."

**Autonomy flags GSD already has**: `mode: "interactive" | "yolo"` ("`yolo` runs autonomously without
prompts"), `workflow.auto_advance`, and the internal `workflow._auto_chain_active`. The
`/gsd:autonomous` workflow runs discuss→plan→execute per phase and "Pauses only for explicit user
decisions (grey area acceptance, blockers, validation requests)". VERIFIED from
`references/planning-config.md` and `workflows/autonomous.md`.

**GSD's own escalation signal.** VERIFIED, `references/honest-verifier.md`: a non-inferable check with
no explicit evidence "abstains → ⚠️ `insufficient_spec`, flagged, → `human_needed` — **never
`passed`**", and it distinguishes interactive from autonomous: "*Autonomous (AFK):* it produces a
prominent `unverified — held-out test recommended` flag and the completion line reads 'complete with
N unverified non-inferable checks'; the run neither silently passes the blind spot nor hard-halts."
That is a ready-made "the engine wants a human" event for R1-17 routing.

### 3.2 A second marketplace process — `feature-dev` (Anthropic, official marketplace)

VERIFIED by reading
`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev/commands/feature-dev.md`
(125 lines, one file, plus three agent definitions).

It is **pure prose**. Seven phases (Discovery, Codebase Exploration, Clarifying Questions,
Architecture Design, Implementation, Quality Review, Summary). It writes **no state file**, exposes
**no status command**, touches **no git**, and has **no notion of resumability**. Its only progress
surface is `TodoWrite`, which lives inside the session. And it is human-gated by design — Phase 5
reads "**DO NOT START WITHOUT USER APPROVAL**" and Phase 6 step 3 reads "**Present findings to user
and ask what they want to do**".

This is the single most important calibration in this research. **GSD is the outlier, not the norm.**
An adapter contract designed around GSD's surfaces would fit exactly one engine.

A third shape, for completeness — `ralph-loop` (official marketplace), VERIFIED from
`hooks/stop-hook.sh`: state is one file, `.claude/ralph-loop.local.md`, with YAML front matter
carrying `iteration`, `max_iterations`, `completion_promise`, `session_id`. The `Stop` hook refuses
to let the session exit until the promise is met or the iteration cap is hit, and it self-isolates by
comparing the state file's `session_id` against the hook payload's. Corrupt state is deleted, not
guessed at. So: a loop engine, with a file-based state contract and a hook-based control surface, and
nothing else.

### 3.3 Claude Code itself — new primitives that did not exist for the previous generation

VERIFIED by running the CLI on this machine (2026-09-19):

- **`claude agents --json`** — "Print active sessions (interactive and background) as a JSON array and
  exit (for scripting; **does not require a TTY**)". Executed here; returns per-session `id` or `pid`,
  `cwd`, `kind` (`background` | `interactive`), `startedAt`, `sessionId`, `name`, and
  `state` (`blocked`) for background sessions / `status` (`busy`) for interactive ones. `--all` adds
  completed background sessions; `--cwd <path>` filters by directory.
- **`claude --bg`** — "Start the session in the background and return immediately. Prints the id that
  `claude attach`, `logs`, `stop` and `rm` take". Plus subcommands `attach`, `logs <id>`,
  `stop|kill <id>`, `rm <id>`, `respawn [--all]`.
- **`claude -w, --worktree [name]`** — "Create a new git worktree for this session (optionally specify
  a name)", and `--tmux` (requires `--worktree`).
- **`claude rm <id>`** — "Delete a background session, **and its worktree when that is safe**."
- `--output-format json|stream-json`, `--permission-mode`, `--session-id`, `--settings`,
  `--add-dir`, `--bare`.

The previous generation built all of this by hand: `harness-term.sh` drives iTerm2/Terminal.app via
`osascript` and tmux, and the field notes record that **Terminal.app "supports only spawn, capture and
close — `send` and `key` are explicitly refused as undrivable" (`harness-term.sh:163-181`)**, which
made it unusable for anything that types into a session. Most of that machinery is now replaceable by
first-party CLI verbs. INFERRED, and worth checking against the owner's R1-11 answer (visible
terminals) before acting on it — that is another cluster's decision, not mine.

### 3.4 PR delivery — what is available and what is true of his repos

VERIFIED by execution against `SashaMarchuk/claude-plugins`:

- `gh repo view --json defaultBranchRef` → `main`; `isPrivate: false`.
- `gh api repos/:owner/:repo/rulesets` → `[]`.
- `gh api repos/:owner/:repo/branches/main/protection` → `404 Branch not protected`.
- `gh pr view 26 --json state,mergedAt,mergeCommit,headRefOid,baseRefName,mergedBy` →
  `{"state":"MERGED","mergedAt":"2026-08-26T13:10:12Z","mergeCommit":{"oid":"fd6125e…"},
  "headRefOid":"198eb7c…","baseRefName":"main","mergedBy":{"login":"SashaMarchuk"}}`.
- `git merge-base --is-ancestor fd6125e origin/main` → exit 0.

**The finding that matters for R1-12:** this repo's CLAUDE.md says work must be "shipped via PR (no
direct pushes to `main`)" — and **GitHub enforces nothing**. No ruleset, no branch protection. The
rule the owner calls "дуже важливо розуміти та приймати" [331] is, in his own flagship repo,
discoverable only by reading prose. An orchestrator that learns repo rules from the GitHub API would
push straight to `main` here and be technically correct.

Useful `gh` flags for delivery, VERIFIED from `--help` on gh 2.92.0: `gh pr merge --auto` ("Automatically
merge only after necessary requirements are met"; with a merge queue, "If required checks have not yet
passed, auto-merge will be enabled… If required checks have passed, the pull request will be added to
the merge queue"), `--admin` to bypass a queue, `-d/--delete-branch`, and
**`--match-head-commit SHA`** ("Commit SHA that the pull request head must match to allow merge") —
an optimistic-concurrency guard that refuses the merge if anything moved underneath.

`gh pr view --json` exposes, among others: `state`, `mergedAt`, `mergeCommit`, `mergeStateStatus`,
`mergeable`, `baseRefOid`, `headRefOid`, `statusCheckRollup`, `reviewDecision`, `autoMergeRequest`.

### 3.5 Worktrees — three owners, and they already collide

The field notes record the collision (§4.3): GSD computed
`gsd/phase-23-tooling-the-harness-and-the-pre-commit-checkers` from the roadmap slug, one word off the
lane's actual branch, "and that left alone `execute-phase` would cut that name fresh from
`origin/master` and lose the merged master tip."

**VERIFIED on this machine that this is still live, and confirmed by GSD's own words.** Running
`gsd-tools worktree base-check` in `/Users/sasha-marchuk/Work/sashko-vps` right now returns:

```json
{ "shouldDegrade": true, "reason": "head-diverged-from-fork",
  "message": "⚠ Worktree base mismatch: HEAD (c62374ce) differs from origin/HEAD (72e0b343).
   Running this phase sequentially on the main working tree. Parallel worktrees return once
   HEAD is merged/pushed so origin/HEAD matches it. (worktree.baseRef:\"head\" applies only
   where GSD itself creates the worktree — the runtime harness does not read it; #48, #3659.)",
  "headSha": "c62374ce…", "forkRef": "origin/HEAD", "forkSha": "72e0b343…" }
```

Read the parenthesis. Under Claude Code, `dispatch-isolation` is `harness-worktree` (VERIFIED,
returns that string), which per `dispatch-isolation-gate.md` means "The host's own harness creates and
binds a worktree per agent… **GSD runs no git**". So:

- The executor worktree is forked from **`origin/HEAD`**, by Claude Code, not by GSD.
- GSD's own escape hatch, `worktree.baseRef:"head"` in `.claude/settings.local.json`, **is not read by
  the host** — GSD says so itself in that message.
- When HEAD differs from `origin/HEAD`, GSD degrades to sequential. `dispatch-should-flatten` returns
  `true` here, today.

So an orchestrator that puts a task on its own worktree off the trunk, and then invokes GSD
`execute-phase` inside it, gets one of two bad outcomes: parallelism silently collapses to sequential,
or sub-worktrees fork from `origin/HEAD` and never see the orchestrator's base.

And a **third** owner now exists: `claude --worktree` (§3.3). Three parties can create a worktree for
the same task.

GSD's sub-agent guard is worth quoting, because it names the ownership rule explicitly. VERIFIED,
`references/worktree-branch-check.md`:

> "The orchestrator owns this worktree's lifecycle; a sub-agent MUST NOT hold state-correction
> primitives (hard-reset, update-ref, force-move, index-discard) on a worktree it did not create
> (#48, #2924). If ANY assertion below fails, HALT immediately — print the FATAL line, `exit 42`, and
> let the orchestrator (the lifecycle owner) decide recovery."

It asserts three things before any commit: HEAD is not detached and not on `main|master|develop|trunk|
release/*`; the branch is in the `agent-*` / `worktree-agent-*` / `worktree-wf_*` namespace; and
`git rev-parse HEAD` equals an `EXPECTED_BASE` SHA the dispatcher captured and substituted into the
prompt. **That base-SHA assertion is the exact mechanism the new orchestrator needs**, and it is
already written down.

### 3.6 Continuous worktree health ("постійно переконуватись … запущений стек")

Feasible, cheaply, with no model in the loop — VERIFIED that the primitives exist here:

- `git worktree list --porcelain` → per worktree: path, `HEAD <sha>`, `branch refs/heads/<name>`.
  Executed here; correctly reports this repo plus `claude-plugins-ig-skill` on
  `feature/ig-dm-export-analyzer-plugin`.
- `git rev-parse HEAD` vs a recorded expected base → base drift.
- `git status --porcelain=v2 --branch` → `# branch.ab +N -M` for ahead/behind, plus dirtiness.
- Env: compare the process environment actually exported into the session's launcher against a
  declared required list.
- Stack: an HTTP/TCP health probe or `docker compose ps --format json` per lane, on the lane's own
  `COMPOSE_PROJECT_NAME`.

The field notes name exactly why the last two matter (§5.1, §11.5): "The owner's default stack was
destroyed by a `docker compose down -v` run with **no `COMPOSE_PROJECT_NAME` exported**, which landed
it on the default project instead of a lane project… the actor was never identified"; and §12.4 is
titled "Environment that detached processes do not inherit".

---

## 4. What is NOT feasible, and why

**4.1 A uniform engine adapter that can read progress from any process.** `feature-dev` has no state
at all (§3.2). Any adapter contract that *requires* a progress query is a contract only GSD can
satisfy. The contract must make every engine capability **optional and declared**, with a degraded
mode, exactly as GSD does for hosts. VERIFIED by the source of both engines.

**4.2 Trusting the engine's own success report.** This is the one place where the owner's R1-13
decision and the field evidence do not meet, and it should be put to him rather than decided around.
He said verification belongs to the configured process [344]. The field notes record three failures
where **the configured process is what produced the false result**:

- §4.1 — "`git checkout master` aborts when a tracked file is modified, and one always is: GSD
  rewrites `.planning/milestone.lock` during every phase and leaves it dirty. The merge command that
  followed then ran **on the phase branch against itself** and printed `Already up to date` and
  `Everything up-to-date`. Both read like success." It was caught "only because the orchestrator
  checked what `master` actually pointed at after the push rather than trusting the exit status."
- §11.5 — "346 passed, 0 failed — caught only by arithmetic: 346 plus 35 never-reached does not equal
  the declared 382."
- §11.4 — "**GSD's verify stage was silently skipped for phases 14 to 18**, each `NN-VERIFICATION.md`
  self-attributing with `verified_by: the lane that built the phase`. … No automated check caught it;
  manual review did." And "**Phase 21 merged before its validator ran.**"

INFERRED, and offered as a distinction rather than an override: **there are two different objects
here.** Verifying *the work* (are the tests real, is the feature right) is the process's job and his
decision settles it. Verifying *the orchestrator's own actions* (did the merge move the ref, did the
notification send, is this worktree on the base I told it to use, did the stage I was told to run
actually run) is nobody's job but the orchestrator's — the process cannot attest to an action it did
not take. §4.1 is the proof: the thing that caught it was an orchestrator checking its own merge.
This is a proposal, not a correction; see §5.3 and Q3.

**4.3 Proving a human received a notification.** Neither Telegram nor Slack exposes read receipts for
bot-sent messages (§2.6, VERIFIED for Telegram from the API docs, CLAIMED for Slack). "Verified to
work" can therefore mean at most *credential valid* + *service accepted*. Anything stronger requires
an explicit acknowledgement the human performs.

**4.4 A channel verified once stays verified.** Field notes §11.6: an 85-minute self-sustaining loop
in which "the human-notification watchdog had already exited ('run finished') and was never
restarted", with `context-watch.log:5620` reading literally **`NO ONE IS BEING TOLD`**. A preflight
send at 22:00 proves nothing at 04:00. This is not a contradiction of [395] — he said "повинен лише
переконатися, що це працює", and the open question is *when*, which he was not asked.

**4.5 Stacked PRs with native git on this machine.** `git 2.33.0` has no `--update-refs` (VERIFIED,
§2.5). Either the orchestrator upgrades git as a preflight requirement, or it maintains the stack by
hand with `gh-merge-base` branch config plus explicit rebases, or it takes a dependency on a tool none
of which is installed here.

**4.6 An orchestrator that both owns the worktree and lets GSD parallelise inside it.** §3.5,
VERIFIED from GSD's own `base-check` message. Under `harness-worktree` the two are mutually exclusive
as configured today; `workflow.use_worktrees: false` makes GSD sequential inside the orchestrator's
worktree, which is a real, coherent choice — and it is a choice, with a throughput cost, that only the
owner can make.

**4.7 Discovering "PR-only" from the forge.** §3.4, VERIFIED on his own repo: no ruleset, no branch
protection, rule in prose only.

**4.8 A zero-token status command, if status is a skill.** VERIFIED:
`plugins/harness/commands/status.md` reads in full — "Invoke the `harness:harness` skill via the Skill
tool, passing `--status $ARGUMENTS` through verbatim." So today, asking for status **spends a model
turn**. That is in direct tension with "мінімальну кількість аутпуту і стокінгів" [512]. The shell
path underneath it already costs nothing — `harness-run.sh do_status --json` is pure bash + jq, and its
own comment reads "machine-readable health for a cron/notifier babysitter: exit 0 healthy, exit 1 when
the run needs a human. No terminal/network required beyond the limits verdict". The zero-token
path exists; the command in front of it does not use it.

---

## 5. Concrete proposals, with trade-offs

### 5.1 Engine adapter contract — a capability descriptor, negotiated and degraded closed

Copy GSD's own protocol shape (§3.1), inverted: the **engine** declares, the **orchestrator**
negotiates and degrades.

Six interface points, each independently optional:

| Point | What the engine declares | If absent, the orchestrator… |
|---|---|---|
| `start` | how to begin one unit of work (command / skill / prose prompt) | cannot run this engine — the only mandatory point |
| `progress` | a command returning machine-readable progress | reports `progress: unavailable`, never guesses a percentage |
| `completion` | how the engine signals done / failed / needs-human | falls back to session exit + a declared marker file |
| `branching` | who creates branches and worktrees, and from which base | assumes the engine owns nothing and takes ownership itself |
| `verification` | whether the engine verifies, and how to read its verdict | records `verification: engine-none`; imposes nothing (R1-13) |
| `delivery` | whether the engine opens PRs / merges | takes delivery itself, subject to §5.3 |

Rules, taken from `host-integration.cjs`:

- Closed vocabulary per field; an out-of-vocabulary value is not a verdict.
- `undocumented` ≠ `none`, and the two are reported with different words. GSD's own review note is the
  argument: reporting a resolver failure as a declared absence "is false".
- `SAFE_DEFAULTS` are the most restrictive value per field.
- A `protocol_version` integer, and a `--exit-contract`-style pin so a descriptor written for v1 keeps
  working.

Two descriptors ship in the box and prove the range: `gsd` (every point populated, via `gsd-tools`)
and `feature-dev` (only `start`, everything else absent). If the contract cannot express
`feature-dev`, it is a GSD-shaped contract wearing a generic name.

**Trade-off.** Six points is more than a first version needs, and every point is a thing to keep in
sync with an engine that ships on its own cadence. The mitigation is that `start` alone is mandatory;
a descriptor with one field is legal and useful.

**Not decided here:** the descriptor's file format. He guessed YAML and hedged in the same sentence
[118]. Symphony's answer — YAML front matter for the machine, Markdown body for the prompt, in one
in-repo file (§2.1) — is worth putting to him as an option, not adopted silently.

### 5.2 Custom processes — a step schema, and the smallest honest version of it

For the "повністю свій" branch of R1-03, a step needs at minimum:

```
id              required, unique, stable         (GitHub Actions `id`)
run | uses      required, exactly one            (`run` = shell; `uses` = skill/agent/command)
name            optional, human label
needs           optional, list of step ids       (the DAG edge; Actions uses job-level `needs`)
if              optional, condition to run
success         optional; default = exit 0       (a declared signal, not a guess)
timeout         optional minutes                 (Actions `timeout-minutes`)
retry           optional {max, backoff, never[]}  (Temporal RetryPolicy, incl. nonRetryableErrorTypes)
artifacts       optional list of paths the step must produce
on_fail         optional: stop | continue | ask   (Actions `continue-on-error`, widened)
```

Nine keys, seven of them optional. Two deliberate departures from Actions: an explicit `success`
signal, because a coding agent exiting 0 means far less than a CI step exiting 0; and a `retry` block,
because Actions has none at step level (§2.3) and Д5 needs one.

`artifacts` is what makes "чи буде перевірка" [118] answerable without imposing a check: *the step
declared it would produce this file; the file is there or it is not.* That is an existence test, not a
quality judgement, so it does not cross the R1-13 line. Bernstein's janitor calls the same signal
"owned files produced" (§2.2).

**Trade-off.** Every optional key is a thing a user can get wrong at 02:00 with nobody watching. The
counter-pressure is that the minimum viable step is two keys, `id` and `run`.

### 5.3 Delivery — the orchestrator verifies its own actions, never the work

Offered explicitly as a **proposal that sits next to R1-13, not over it** (see §4.2 and Q3). Every
check below is about an action the orchestrator itself performed, costs no model tokens, and works
identically whether or not the project has tests:

**The merge-landed assertion** — the one that would have caught field notes §4.1:

```bash
BASE=$(gh pr view "$PR" --json baseRefName --jq .baseRefName)
HEAD=$(gh pr view "$PR" --json headRefOid  --jq .headRefOid)
git fetch origin "$BASE"
git merge-base --is-ancestor "$HEAD" "origin/$BASE" \
  || fail "PR $PR reports merged; $HEAD is NOT an ancestor of origin/$BASE"
[ "$(gh pr view "$PR" --json state --jq .state)" = MERGED ] || fail "PR $PR is not MERGED"
```

VERIFIED working here against PR #26 (§3.4). Two independent oracles — the forge's own state and the
git graph — and the failure mode in §4.1 (a branch merged into itself) fails the second one instantly.

**Other self-checks in the same class:**

- Before dispatch, capture `EXPECTED_BASE=$(git rev-parse HEAD)` and assert it inside the worktree —
  GSD's `worktree_branch_check` block, verbatim, `exit 42` on mismatch (§3.5).
- On merge, prefer `gh pr merge --match-head-commit "$HEAD"` so anything moving underneath aborts it.
- Assert the process stage actually ran before accepting its verdict — field notes §11.4 records five
  phases whose `NN-VERIFICATION.md` self-attributed `verified_by: the lane that built the phase`. The
  orchestrator dispatched (or failed to dispatch) that stage; checking that it did is checking its own
  work.
- Never parse a test summary. If the engine declares a `verification` point, read its verdict; if not,
  record `verification: engine-none` and carry it into the PR body and the status file so the owner
  sees what was and was not checked. The 346/382 arithmetic (§4.2) is the reason to record rather than
  interpret.

**Respecting repo rules, given §4.7.** A three-source ladder, most-authoritative first, all cheap:

1. `gh api repos/:owner/:repo/rulesets` and `…/branches/<base>/protection` — machine truth when present.
2. `.planning/config.json` `git.protected_branches` — GSD's own list, which "extends the resolved base
   branch; it never replaces the base". VERIFIED from `planning-config.md`, which also warns:
   "Matching is by exact branch name — there is no glob or prefix support".
3. The project's own prose (`CLAUDE.md`, `CONTRIBUTING.md`) as a **declared, config-pinned** file path.

And a fail-closed default: **PR-only unless the config says otherwise**. On this repo all three
machine sources say "nothing is protected" while the prose says "no direct pushes to `main`". A
default of "direct push allowed unless forbidden" gets that wrong, silently, on his own flagship
repo.

**Stacked PRs** (`gt`/`ghstack`/`spr` absent, git 2.33 has no `--update-refs`, §2.5): the
zero-dependency version is one branch per ticket, each branched off its parent, each recording
`git config branch.<name>.gh-merge-base <parent>`, so `gh pr create` targets the parent automatically
(VERIFIED from `gh pr create --help`). Merge bottom-up; after each merge, retarget the children.
**Trade-off:** without `--update-refs`, every rebase of the bottom of the stack requires rebasing each
child by hand. Recommend stacking only for genuinely dependent tickets, and defaulting independent
tickets to independent PRs off the trunk — which is also what Д4's "все в різних ворк трі" implies.

### 5.4 Worktrees — declare the owner, once, and assert it

One config value with three legal settings, matching the three parties in §3.5:

| `worktree.owner` | Who creates it | GSD setting required | Consequence |
|---|---|---|---|
| `orchestrator` | the orchestrator, `git worktree add -b <branch> <path> <base>` | `workflow.use_worktrees: false` | one worktree per task off the trunk (his default), GSD runs sequentially inside it |
| `engine` | GSD via the host harness | leave `use_worktrees: true` | GSD parallelises; the orchestrator does **not** create a worktree and does not assume the base |
| `host` | `claude --worktree` | `use_worktrees: false` | cheapest to build; least control over the base |

Preflight, at run start, refuse to start on a mismatch: read `gsd-tools state.load` for
`use_worktrees` and `branching_strategy`, read `gsd-tools dispatch-isolation`, run
`gsd-tools worktree base-check`, and compare against `worktree.owner`. If `worktree.owner:
orchestrator` and `use_worktrees: true`, that is the §3.5 collision — say so, in those words, and stop.

Per-lane health, on a tick, no model (§3.6): `git worktree list --porcelain` → path/HEAD/branch;
`git rev-parse HEAD` vs the recorded `EXPECTED_BASE`; `git status --porcelain=v2 --branch` for `+N -M`
and dirtiness; the declared env list; a declared stack probe. That is "постійно переконуватись" [433]
at roughly the cost of four `git` invocations per lane per tick.

**Trade-off:** `worktree.owner: orchestrator` costs GSD's intra-phase parallelism. `engine` keeps it
and costs the orchestrator its uniform "every task in its own worktree off main" default. There is no
configuration that gives both today, and the choice is his.

### 5.5 Status — a state directory, a versioned JSON contract, and a script that is not a skill

Three parts:

1. **The run state directory**, the single place anything is written. Keep the previous generation's
   layout, which the field notes describe and which worked: `state/registry/<name>.json` per session,
   `heartbeats/<name>` + `.epoch`, `markers/<name>.done`, `state/attention`, and the control file that
   Д12 writes stop commands into. Add: `state/status.json`, rewritten atomically each tick.
2. **A versioned contract.** `{"schema": 1, …}` and never a breaking change without the integer moving
   — `git status --porcelain=v2` (§2.7) and GSD's `--exit-contract=v1|v2` are both precedents on this
   machine. Fields: run id, project, started_at, per-lane `{ticket, stage, worktree, branch,
   base_sha, heartbeat_age_s, state}`, queue counts, limits verdict, attention items, last error.
3. **`orchestrator:status` is a shell script, not a skill.** It reads `status.json` and prints. Human
   text by default, `--json` for machines, exit 0 healthy / exit 1 needs-a-human. **Zero model
   tokens.** The previous generation already wrote this exact contract in bash+jq
   (`harness-run.sh do_status --json`, §4.8) — the regression was routing the *command* through a
   skill. INFERRED: fixing that is a one-file change and it is the most direct possible answer to
   [512].

**Where the daemon does spend tokens:** nowhere, by default. The tick loop is bash. A model is invoked
only to do work or to make a judgement the config says it may make.

**Trade-off.** A JSON file goes stale the moment the writer dies, and shows the last good state as
though it were current. Mitigation: `status.json` carries its own `written_at`, and the status script
prints the staleness prominently. Field notes §1.5 warns the opposite way too — "Heartbeat staleness
is not a stall" — so staleness is a fact to display, never a verdict to act on.

### 5.6 Notifications — a two-tier verify, at start and on a schedule

**Tier 1, preflight, mandatory.** Credential check per channel: Telegram `getMe`, Slack `auth.test`,
SMTP `EHLO`+auth, or a declared `test_command` for anything custom (the phone call at [395] is a
`test_command`). Fail → refuse to start the run if any notification type is configured as required,
because a run that cannot reach him is a run he will not know has stopped.

**Tier 2, delivery, once at start.** Send one real message through each configured channel and record
the service's receipt — Telegram's `message_id`, Slack's `ts`. This is the ceiling of what is
provable (§4.3), and it should be labelled as *delivered*, never *seen*.

**Tier 3, liveness, on a schedule — the answer to §4.4.** Two options, neither of which he was asked
about:

- *Self-check*: re-run Tier 1 every N ticks and raise an attention item when it starts failing. Cheap;
  fails if the orchestrator itself is dead, which is the case that matters most.
- *Dead-man's switch*: the orchestrator pings an external endpoint on a schedule, and the **absence**
  of a ping alerts on the far side (§2.6). Survives the orchestrator dying. Costs an external
  dependency and, on a hosted service, sends run metadata off the machine.

INFERRED recommendation: default to self-check, offer the dead-man's switch as opt-in, and let
`notifications.required: true|false` decide whether Tier 1 failure is fatal.

**A channel that is a two-way surface.** Telegram inline keyboards produce a `callback_query`
(VERIFIED, §2.6), so "Approved / Rejected" buttons give both an acknowledgement *and* the answer.
That connects R1-17 to Д6's questions channel. Out of my cluster to decide; noted because the two
decisions share one mechanism.

**Rate limits.** Not stated in the Bot API page I fetched. Treat as unknown, cap outbound
notifications per run, and coalesce — field notes §11.6 records "1085 times" for one unresolved
condition over about five days. Whatever the real Telegram limit is, 1085 identical alerts is a
product failure before it is an API failure.

---

## 6. Open questions this raises for the owner

**Q1 (R1-12, from his own lost sentence).** At [334] he began "Також дуже [важливо…]" and the
interviewer's restatement ran over it. A point he flagged as very important about reaching the trunk
was never made. It should be asked again, plainly: *що ще важливе ти хотів сказати про потрапляння в
основну гілку?*

**Q2 (R1-17, never answered).** The substantive half of the question — what is worth interrupting him
for, and what waits — was redirected to configuration and never answered; the quiet-hours clause
[394] was asked and skipped. Configuration still needs a shipped default, and only he can supply it.
Suggested re-ask, in his own preferred shape (a case, per outside-list.md §14): *три ситуації о 3-й
ночі — оркестратор зупинився на питанні; впав сам оркестратор; злиття пройшло, але нічого не
перенесло. Яка з них будить тебе зараз, а яка чекає до ранку?*

**Q3 (R1-13, the distinction, not a reversal).** He decided verification belongs to the process, with
the field evidence in front of him [342]/[344], and that decision stands. The question is narrower and
was never put to him: **does the same rule cover the orchestrator's own actions?** When the
orchestrator runs a merge and git reports `Already up to date` because it merged a branch into itself
(field notes §4.1), no process verified anything — the orchestrator did the thing. Ask: *чи має
оркестратор перевіряти власні дії — що злиття справді зрушило гілку, що етап, який він мав запустити,
запустився — чи це теж належить процесу?*

**Q4 (Д4, the collision).** Under Claude Code, GSD's executor worktrees fork from `origin/HEAD` and
GSD's own `worktree.baseRef` setting is not read by the host (VERIFIED, §3.5). His default is "все в
різних ворк трі" off the main branch. The two cannot both hold. Which does he give up: GSD's
intra-phase parallelism (`use_worktrees: false`, orchestrator owns the worktree), or the uniform
one-worktree-per-task default (engine owns it, base is `origin/HEAD`)?

**Q5 (Д4, "постійно").** He said the orchestrator must "постійно переконуватись" that env vars and a
running stack are in place. How often is "постійно" — every tick, before each step, or only at spawn?
And what should happen when a stack a lane depends on goes down mid-task: hold the lane, restart the
stack, or escalate? (Field notes §5.1: an OOM killed the owner's own container mid-run and "there was
no live alert".)

**Q6 (R1-12/R1-15, prose rules).** His own repo says "no direct pushes to `main`" in CLAUDE.md and
GitHub enforces nothing (VERIFIED, §3.4). Where should the orchestrator read repo rules from, and
should the default be fail-closed (PR-only unless configured otherwise)? This touches R1-15's single
prohibitions file — same mechanism, different cluster.

**Q7 (R1-03, format).** He guessed YAML and hedged it in the same sentence [118]. Symphony's answer is
one in-repo file with YAML front matter for the machine and Markdown below it for the prompt (§2.1).
Is that the shape he wants for a custom process, or does the process definition belong in the plugin's
config rather than in the project repo?

**Q8 (Д11, unconfirmed).** The corrected Д11 — minimum output by default, reconfigurable — was never
ratified; the interviewer asked "Це остаточний варіант, підтверджуєш?" and moved on (corrections.md
:104). Worth one line of confirmation. And a concrete sub-question: **should `orchestrator:status` be
a plain script that spends no model tokens?** Today's equivalent routes through a skill and costs a
model turn (VERIFIED, §4.8), which reads as the opposite of what he asked for.

**Q9 (R1-12, stacked PRs).** `git 2.33.0` on this machine has no `--update-refs`, and no stacking tool
is installed (VERIFIED, §2.5). Is upgrading git an acceptable preflight requirement, or should stacked
PRs be an opt-in extra that the orchestrator refuses to attempt when the primitive is missing?

---

## Appendix — commands run on this machine, for re-checking

```
git --version                                              # 2.33.0
git rebase -h | grep update-ref                            # (no output)
gh --version                                               # 2.92.0
which gt spr ghstack git-spr                               # none found
gh repo view --json nameWithOwner,defaultBranchRef,isPrivate
gh api repos/:owner/:repo/rulesets                         # []
gh api repos/:owner/:repo/branches/main/protection         # 404 Branch not protected
gh pr view 26 --json state,mergedAt,mergeCommit,headRefOid,baseRefName,mergedBy
git merge-base --is-ancestor fd6125e origin/main           # exit 0
git worktree list --porcelain
git status --porcelain=v2 --branch
claude agents --json
claude --help ; claude agents --help
node ~/.claude/gsd-core/bin/gsd-tools.cjs --help
  (in /Users/sasha-marchuk/Work/sashko-vps:)
  gsd-tools progress | state | state.load | smart-entry
  gsd-tools worktree base-check | dispatch-isolation | dispatch-should-flatten
  gsd-tools git base-branch | windows status | workstream list
  gsd-tools capability list | runtime-identity | teams-status
```

Files read in full or in relevant part:
`~/.claude/gsd-core/bin/lib/host-integration.cjs`, `~/.claude/gsd-core/bin/lib/mcp-server.cjs`,
`~/.claude/gsd-core/references/{planning-config,git-integration,worktree-branch-check,workstream-flag,
dispatch-isolation-gate,loop-hook-dispatch,honest-verifier,verifier-evidence-gate}.md`,
`~/.claude/gsd-core/workflows/{autonomous,ship}.md`, `~/.gsd/defaults.json`,
`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev/commands/feature-dev.md`,
`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/ralph-loop/hooks/stop-hook.sh`,
`plugins/harness/bin/{harness-run.sh,harness-gsd.sh}`, `plugins/harness/commands/status.md`,
`plugins/harness/docs/FIELD-NOTES.md`,
`<baseline-marketplace>/docs/config-levels.md`.

Not available on this machine, noted as a gap: `docs/open/supervisor/ORCHESTRATION.md` and
`docs/open/supervisor/WATCHER-PROMPT.md` in the `<work-project>` repository — the field notes reference
both by path and I could not locate that checkout. The prior-research directory named in the task
(`.../scratchpad/context/`) was **empty**, so nothing was reused from it and §2 was derived fresh.

Sources cited in §2 (fetched or searched 2026-09-19):
[openai/symphony SPEC.md](https://github.com/openai/symphony/blob/main/SPEC.md) ·
[Bernstein README](https://github.com/AmirF194/bernstein) ·
[GitHub Actions workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) ·
[Temporal failure detection](https://docs.temporal.io/develop/go/failure-detection) ·
[Telegram Bot API](https://core.telegram.org/bots/api) ·
[Slack auth.test](https://docs.slack.dev/reference/methods/auth.test/) ·
[Slack chat.postMessage](https://api.slack.com/methods/chat.postMessage) ·
[GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) ·
[GitHub merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue) ·
[Graphite: evaluating tools for stacking](https://graphite.com/docs/evaluating-tools) ·
[InfoQ: GitHub native stacked PRs](https://www.infoq.com/news/2026/04/github-stacked-prs/)
