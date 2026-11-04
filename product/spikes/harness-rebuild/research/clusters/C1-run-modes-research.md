# C1 — Run modes and decision authority

Cluster: **C1-run-modes** · Items: **R1-14, R1-02, R1-01**, owner instruction **I2**
Date of research: **2026-09-19** · Machine: this one (darwin 25.5.0), Claude Code **2.1.278**, Codex CLI **0.152.0**

Every claim is marked **VERIFIED** (I read it in source, docs, or ran it here), **CLAIMED** (a README, blog
or vendor page asserts it and I did not confirm), or **INFERRED** (my reasoning from the above).

This document answers the instruction the owner gave at [082]: analyse, and come back with concrete
candidate definitions of "controlled run" and "autonomous run". It does not pick one. Section 5 holds
five, each with a classifying rule, an authority list, a logging contract and a failure mode.

---

## 1. What the owner decided, quoted

### 1.1 The distinction is his, and it replaced the question's frame

The interviewer asked R1-01 ("what must be done by morning so you'd say the night went well"). He
rejected the framing:

> «Це все залежить, так як це налаштував, тобто якщо... Це дуже абстрактне питання, тому що я б взагалі
> навіть не фокусувався на тому, що там щось вночі працює, чи ще щось Можливо, це треба просто трошки
> правильніше розділити, як автономний ран та... контрольований» **[054]**

Night is an *example* of autonomous, not the defining property:

> «Не знаю, чи вони будуть відрізнятися, але автономний це про те, що він там вночі, наприклад, працює
> і якщо він стихається» **[058]**

**This sentence is load-bearing and is not in ANALYSIS-01.md.** He is not certain the two modes are
different things. Any proposal that makes them two elaborate, separately-specified machines is
proposing more than he asked for. `extract/corrections.md:50` records the same reading: "the
distinction itself may collapse."

### 1.2 The substance of the two modes

> «Якщо це автономний ран, то і агент не впевнений на сто в цьому варіанті, то він його може обрати. …
> Момент був, що це автономний ран, і він обрав це, **якщо це не підходить, то треба вчити, відповідні
> дії**.» **[062]**

In English, the rest of the answer: in a controlled run any doubt goes straight to him as a conditional hard stop and the work stays paused «поки людина не відпустить»; in an autonomous run the agent «прозвітовує» afterwards about the decision it took.

Four things are in that answer, and ANALYSIS-01.md carries only three:

1. Controlled: doubt → straight to him → conditional **hard stop**, work paused «поки людина не відпустить».
2. Autonomous: the agent «не впевнений на сто» may still choose.
3. Autonomous: it **reports afterwards** «він прозвітовує».
4. **A learning loop** — «якщо це не підходить, то треба вчити, відповідні дії». A wrong autonomous
   decision must change future behaviour. Nothing in the analysis, and nothing in the previous
   harness, implements this. (`extract/outside-list.md:59` flags the same gap.)

### 1.3 Mode selection is configuration, per-run overridable

> «людина може законфігурувати, щоб постійно це, наприклад, був автономний ран, або постійно це був
> контрольований ран. А також вона може перевизначити це для конкретного рану.» **[075]** — confirmed
> «Погоджуюсь» [080].

In English, the rest of the answer: three options, ask every time, always autonomous, always controlled.

### 1.4 Two further settings, orthogonal to the mode

> «Там, плюс, має налаштовуватись, **чи агент може щось вирішувати чи ні**. … **Якщо можливо, то на
> основі чого?**» **[087]** — confirmed «Так, підтверджую» [101].

In English, the rest of the answer: the bases he named are a tone of voice, his answers to similar earlier questions, a tone of voice kept in the repository, or the agent deciding fully on its own from project knowledge.

And what "tone of voice" means:

> «Може бути таке, що людина створила tone of voice своїх рішень, таким чином, що коли треба щось
> вирішити, то вона може це довірити агенту. … якщо людина сказала, що вона налаштувала так, що, грубо
> кажучи, **майже замість неї може відповідати**, по причині попередніх прикладів, налаштувань, тощо і
> так далі, то це повністю окей, і агент буде це використовувати» **[092]**

So there are **three independent switches**, not one:

| Switch | Values he named | Row |
|---|---|---|
| Mode | ask-every-run · always-autonomous · always-controlled; per-run override | [075] |
| May the agent decide at all | yes · no | [087] |
| On what basis, if yes | written rules + examples of past decisions ("tone of voice") · previous answers to similar questions · a tone of voice living **in the repository** · the agent's own project knowledge | [087] |

### 1.5 An autonomous run may still stop itself

> «Якщо агент вирішив, що це точно має бути хардстопом, то такі моменти теж можуть бути, що
> відбувається хардстоп, і йдеться до людини, навіть якщо це автономний ран. Таке може бути, і **агент
> сам буде пробувати детермінувати, коли це робити**» **[082]**

**Confirmation status:** `extract/corrections.md:83` establishes that the restatement carrying this
clause [085]/[086] never got a "yes" — he answered by adding a new condition instead [087]. The later
confirmed restatement [094]→[101] covers only the *basis*. So the agent-forced-hard-stop clause is
**recorded but unratified**, and it is the single most open-ended authority in the whole design: the
agent decides, by itself, when to override the mode.

### 1.6 What may be delegated at all

> «Це все має налаштовуватись. … людина повинна сама налаштовувати, що саме вона може віддавати на
> автономне виконання, а що взагалі ні.» **[107]** — confirmed [110].

In English, the rest of the answer: options range from fully autonomous, through choosing by tone of voice, to the agent not choosing at all, probably gathered by a questionnaire before a run or in the global configurator.

### 1.7 And the definitions themselves are handed to this agent

> «І в мене поки немає відповіді. Це потрібно, щоби агент, який буде колектити ці результати,
> проаналізував і запропонував мені варіанти для цього.» **[082]**

In English: what "controlled" and "autonomous" mean was itself one of the open sub-questions.

### 1.8 Adjacent decisions that constrain any proposal

- **R1-01 [062]:** there is no universal measurable definition of a good run; success is the user's
  configuration. So a mode definition may **not** be phrased in terms of outcome quality.
- **R1-15 [357]:** the red line is **one text file, mandatory reading for every agent**, no
  enforcement machinery — «Достатньо лише одного файлу, який може доповнюватись, текстописний … На
  окремо якогось обов'язкової процедури для цього не треба … технічні обмеження середовища користувач
  за потреби налаштовує сам». Any proposal that *requires* engine-enforced gating contradicts him.
  Section 6 raises this as an open question rather than overriding it.
- **Д6 [449]:** one configurable channel carries questions, clarifications, confirmations and review;
  the orchestrator watches it for changes and applies answers live. Independent tasks continue.
- **Д12 [520,524] (UNRATIFIED):** `stop-hard`, `stop-soft`, `stop-custom`, applied via the file the
  orchestrator re-reads each tick.
- **Soft/hard vocabulary** is already general across limits, context, accounts and stops.

---

## 2. How the world does it

### 2.1 Claude Code already ships a six-tier autonomy ladder — VERIFIED on this machine

`claude --help` on 2.1.278 here prints:

```
--permission-mode <mode>   Permission mode to use for the session
                           (choices: "acceptEdits", "auto", "bypassPermissions",
                            "manual", "dontAsk", "plan")
```

**VERIFIED** (ran it). From the docs (`code.claude.com/docs/en/permission-modes`, fetched today,
**VERIFIED** as primary vendor documentation):

| Mode | Runs without asking | Vendor's stated use |
|---|---|---|
| `default` (alias `manual`) | reads only | reviewing every action yourself |
| `acceptEdits` | reads, file edits, `mkdir/touch/mv/cp` in the working dirs | iterating on code you review |
| `plan` | reads, plus classifier-approved commands | exploring before changing |
| `auto` | everything, with a **classifier** reviewing in the background | long tasks, prompt fatigue |
| `dontAsk` | reads + pre-approved tools; **anything that would prompt is denied** | "locked-down CI and scripts; the session never waits for input" |
| `bypassPermissions` | everything | isolated containers/VMs only |

Two of these map directly onto the owner's vocabulary:

- **`dontAsk` is a machine-level "autonomous run that never blocks"** — its documented property is
  literally «the session never waits for input». It converts every would-be question into a denial and
  keeps going. That is the failure-safe half of autonomous without any bespoke machinery.
- **`default`/`manual` is a machine-level "controlled run"** — every non-read action stops and asks.

Independent of the mode, rules are **ordered deny → ask → allow, first match wins, specificity does not
matter** (**VERIFIED**, docs `permissions`): "A broad deny rule like `Bash(aws *)` blocks every
matching call, including calls that also match a narrower allow rule". And "if a tool is denied at any
level, no other level can allow it."

### 2.2 The auto-mode classifier is a ready-made, inspectable escalation taxonomy — VERIFIED here

I ran `claude auto-mode defaults` on this machine:

```
allow: 17 rules
soft_deny: 70 rules
hard_deny: 1 rules
environment: 21 rules
```

**VERIFIED.** The rule lists are **prose strings**, versioned by Anthropic, splice-able with the
literal `"$defaults"`, and live in `autoMode.{environment,allow,soft_deny,hard_deny}` in
`~/.claude/settings.json` or managed settings. Precedence inside the classifier is four-tier
(**VERIFIED**, docs `auto-mode-config`):

1. `hard_deny` — unconditional; user intent and `allow` cannot clear it.
2. `soft_deny` — blocks; user intent and `allow` can clear it.
3. `allow` — exceptions to `soft_deny`.
4. **Explicit user intent** clears the remaining soft blocks — *only if* the user's message "directly
   and specifically describes the exact action". «"clean up the repo" doesn't authorize force-pushing,
   but "force-push this branch" does.»

The `soft_deny` labels I printed here are, verbatim, an escalation taxonomy of one-way doors:

> `Production Deploy`, `Irreversible Local Destruction`, `Irreversible Deletion (general)`,
> `Unverifiable Deletion Target`, `Git Destructive`, `Cloud Storage Mass Delete`,
> `Permission Grant`, `Secret-Store Writes`, `DNS / Domain / Cert Changes`,
> `Logging/Audit Tampering`, `CI Bypass`, `Merge Without Review`, `Self-Approval`,
> `Modify Shared Resources`, `Shared Cluster Mutation`, `Real-World Transactions`,
> `Credential Leakage`, `Code from External`, `Safety Bypass Flag`, `Create Unsafe Agents`,
> `Auto-Mode Bypass`, `Session Transcript Tampering`, `Instruction Poisoning`, …
> (70 total, **VERIFIED** by running the command)

And every one carries the same machine-readable clause:

> `[named+specifics — **must name:** the destructive operation and its target]`

That clause is the most directly reusable idea in this entire research. It is a **precise operational
definition of "the owner authorised this"**: not "he approved the ticket", but "he named the
destructive operation and he named its target". It converts a vague escalation question into a
checkable predicate. **VERIFIED** (printed from the local install).

The single `hard_deny` rule is `Data Exfiltration`. Note the asymmetry the vendor chose: **one**
unconditional rule, seventy conditional ones. **INFERRED:** they concluded that almost nothing is
absolutely forbidden; almost everything is forbidden *unless named*.

### 2.3 Prose in a file is a real enforcement surface — and its exact failure is documented

Two mechanisms in Claude Code read **plain prose** as policy (**VERIFIED**, docs `auto-mode-config`):

- `autoMode.*` entries are "prose descriptions, read as natural-language rules… Write them the way you
  would describe your infrastructure to a new engineer."
- "The classifier reads the same **CLAUDE.md** content Claude itself loads, so an instruction like
  'never force push' in your project's CLAUDE.md steers both Claude and the classifier at the same time."

This is direct vendor support for the owner's R1-15 position (one text file is enough). **But the same
page names the failure mode of the weakest version of it:**

> "**Boundaries you state in conversation**: The classifier treats boundaries you state in the
> conversation as a block signal… **Boundaries are not stored as rules.** The classifier re-reads them
> from the transcript on each check, so a boundary can be lost if context compaction removes the
> message that stated it. For a hard guarantee, add a deny rule instead."

**VERIFIED.** The design conclusion is sharp: prose works, *if it lives in a file that is re-read*, and
fails silently *if it lives only in a conversation*. Given R1-08 (compaction is configurable and
frequent) and field-notes §3 (a lane spent three quarters of its window on polling), any red line or
tone-of-voice carried in-context will be compacted away mid-run. **INFERRED, but with a verified
mechanism behind it.**

### 2.4 Circuit breakers, and where they evaporate — VERIFIED

Auto mode has a hard-coded circuit breaker (docs `permission-modes`, **VERIFIED**):

> "if the classifier blocks an action **3 times in a row or 20 times total**, auto mode pauses and
> Claude Code resumes prompting. Approving the prompted action resumes auto mode. **These thresholds
> are not configurable.** Any allowed action resets the consecutive counter."

And the part that matters most for an unattended run:

> "**Sessions that can't prompt**: a non-interactive `-p` run without a `--permission-prompt-tool` has
> no prompt to fall back to. When repeated blocks reach a threshold, the action doesn't run and Claude
> keeps working… **Claude Code doesn't stop the run in either case.**"

**VERIFIED.** This is the exact shape of the previous generation's worst failure class: an escalation
that exists on paper and dissolves into "keep working" when nobody is there. An orchestrator design
that assumes "the platform will stop when it is stuck" is wrong on this platform, today.

### 2.5 The approval-queue primitives that do exist — VERIFIED on this machine

```
--permission-prompt-tool     YES
--permission-prompts         YES   (host | none)
--permission-mode            YES
--restricted                 YES
--allow-dangerously-skip-permissions  YES
```

(all five confirmed present in `claude --help` here, **VERIFIED**)

- `--permission-prompt-tool <mcp tool>` — an MCP tool answers permission prompts instead of a human.
  This is the hook for a *queue*: the tool can write the request to the Д6 channel and block, or
  return a decision from a policy file.
- `--permission-prompts none` — "anything that would prompt is denied automatically; the permission
  mode still decides everything else"; Claude is told nobody can approve and **not to retry**;
  `AskUserQuestion` is removed from the toolset entirely; unanswered MCP elicitations are cancelled;
  denials are reported as `permission_denied` events and collected in `permission_denials` in the
  final result. **VERIFIED** (docs `headless`).
- Hooks: the full event list is 32 names (**VERIFIED**, docs `hooks`). Four matter here:
  - `PreToolUse` → `permissionDecision: "allow" | "deny" | "ask"`; **exit 2 blocks unconditionally**,
    before permission rules are evaluated.
  - `PermissionRequest` → `decision: "allow" | "deny" | "ask"`; exit 2 is *not* honoured.
  - `PermissionDenied` → fires after auto mode denies, receives `classifier_verdict`, can set
    `retry: true`.
  - `Elicitation` / `ElicitationResult` → can answer an MCP server's mid-tool question
    (`userResponse`) without a human.
  - `Notification` matchers include `permission_prompt`, `idle_prompt`, `agent_needs_input`,
    `agent_completed` — i.e. "this session is stranded waiting" is an observable event, not something
    that must be inferred from screen scraping. **VERIFIED.**

**INFERRED:** together, `PreToolUse` (deny/ask by rule) + `PermissionRequest` (route to a queue) +
`Notification:agent_needs_input` (detect a stranded session) + `--permission-prompts none` (fail
closed) is a complete controlled/autonomous substrate on Claude Code **without writing a screen
scraper** — which is what the previous generation actually did, and what produced its 85-minute
self-sustaining loop (field notes §11.6).

### 2.6 Codex — a different, coarser ladder — VERIFIED on this machine

`codex --help` (0.152.0) here:

```
-s, --sandbox <SANDBOX_MODE>      [read-only, workspace-write, danger-full-access]
-a, --ask-for-approval <POLICY>   on-request | never
    --approve-for-me              Route approval requests through automatic review
                                  using the workspace-write sandbox
    --dangerously-bypass-approvals-and-sandbox
    --dangerously-bypass-hook-trust
-p, --profile <CONFIG_PROFILE_V2> Layer $CODEX_HOME/<name>.config.toml on top of the base user config
```

**VERIFIED.** Notes:

- The approval axis has **two** values here, not the four (`untrusted`/`on-failure`/`on-request`/`never`)
  that older Codex builds carried. **VERIFIED for 0.152.0; CLAIMED that earlier builds had four** (from
  memory of prior releases — treat as unconfirmed and re-check if it matters).
- `on-request` means **the model decides when to ask** — the authority to escalate sits in the model,
  exactly the unratified clause at [082]. Codex ships that as its *normal* mode.
- `--approve-for-me` is an automatic-review stand-in for the human, analogous to Claude Code's
  classifier but sandbox-scoped rather than rule-scoped.
- The real autonomy dial on Codex is the **sandbox**, not the approval policy. This machine's
  `~/.codex/config.toml` currently sets `sandbox_mode = "danger-full-access"` (**VERIFIED** — I read
  the file). Worth flagging to the owner independently of this cluster.
- `-p, --profile` layering gives Codex a native "per-run override of a named config" — a direct fit for
  «перевизначити це для конкретного рану» [075].
- There is an open request for a permission-request hook "for parity with claude code's auto-approve
  flow" (openai/codex issue #16301) — **CLAIMED** (search result title only; I did not open the issue).

### 2.7 cursor-agent — one bit — VERIFIED on this machine

```
-f, --force   Force allow commands unless explicitly denied (default: false)
```

(`cursor-agent --version` → `2025.09.12-4852336`, **VERIFIED**.) That is the whole autonomy surface: a
boolean plus a deny list. No tiers, no classifier, no escalation hook. **This is the shape of the
divergence I1 asks about**: on this platform "controlled" and "autonomous" can only be expressed as
force-off / force-on, and every finer distinction must be enforced by the orchestrator outside the
tool.

### 2.8 Framework patterns — approval queues, partial approval, resumable interrupts

- **LangGraph / LangChain HITL** — an agent pauses before a sensitive tool call via `interrupt()`; graph
  state is persisted so the pause can last arbitrarily long and resume with `Command(resume=…)`. Four
  decision verbs: **approve · edit · reject · respond**. The `interrupt()` function is now the
  recommended path over the older `interrupt_before` / `interrupt_after`. **CLAIMED** (LangChain docs
  via search; I did not run it).
- **OpenAI Agents SDK** — a tool declares `needsApproval: true` or a predicate; the run pauses, returns
  `RunToolApprovalItem` interruptions, and the caller calls `state.approve()` / `state.reject()` and
  resumes. **Partial approval is supported**: approve two of five, resume, the other three stay
  paused. Interruptions from a nested `agent.asTool()` surface on the **outer** run. **CLAIMED**
  (OpenAI Agents SDK docs via search).
- **AWS Step Functions** — the callback/task-token pattern: the state pauses until `SendTaskSuccess` /
  `SendTaskFailure` returns the token. `TimeoutSeconds` / `HeartbeatSeconds` on that state fire a
  timeout transition, and `Catch` routes it to an escalation state: notify a secondary reviewer,
  escalate, or **default to a safe fallback, typically blocking the operation**. A 24-hour timeout is
  the commonly cited default. **CLAIMED** (AWS docs + practitioner posts via search).
- **Temporal** — `wait_condition(..., timeout=…)` on a durable timer: either a signal arrives or the
  timeout fires and you mark it rejected or escalate. Works identically for five seconds or five
  months. **CLAIMED** (Temporal blog via search).

**The pattern common to all four:** the wait is *durable state*, not a blocked process, and the timeout
has a **declared default**. That is the design the owner half-invented already — see §2.11.

### 2.9 Policy-as-data, and why "examples of past decisions" is the hard part

The owner's "tone of voice" basis [087,092] is, in the literature's terms, **precedent-based /
case-based routing**: decide by analogy to previously approved cases.

- The verified, shipped analogue is Claude Code's `autoMode` prose lists plus the per-repo memory of
  "Yes, and don't ask again", which the docs describe as remembered "permanently per repository and
  command" (**VERIFIED**, docs `permissions`). That is precedent accumulation with a *human* writing
  each precedent explicitly.
- `/auto-mode-setup` goes further: Claude Code drafts `autoMode.environment` entries **from your recent
  sessions in this project** — the hosts, buckets and command names from commands Claude ran, never
  your messages — and writes the accepted draft to `~/.claude/settings.json` (**VERIFIED**, docs
  `auto-mode-config`). This is the closest shipped thing to "learn my tone of voice from what I
  approved", and note its two safety choices: it reads **actions, not messages**, and the human
  **accepts or discards the draft as a whole** before it becomes policy.
- CSA's *Agentic AI Autonomy Levels and Control Framework v2* defines L0 Observe → L1/L2 human-involved
  → **L3 Bounded execute (reversible or low-risk actions under policy)** → **L4 High-autonomy execute
  (high-impact, explicit risk acceptance, monitoring)**, and states that autonomy boundaries must be
  **technically enforced, not merely documented**. **CLAIMED** (CSA blog/lab pages via search).
- Feng, McDonald & Zhang, *Levels of Autonomy for AI Agents* (arXiv 2506.12469, submitted 2025-06-14,
  rev. 2025-07-28) defines five levels by the **human's role**: operator · collaborator · consultant ·
  **approver** · observer, and argues autonomy level is "a deliberate design decision, separate from
  its capability and operational environment". **VERIFIED** (fetched the abstract page today).
  Mapping: the owner's *controlled* ≈ **approver**; his *autonomous* ≈ **observer**.

### 2.10 Confidence is not a usable gate — and the previous harness gated on it

The previous harness's orchestrator prompt escalates on a self-reported number:

> "**Hard / high-stakes / normally-would-need-the-owner** (architecture, a cross-cutting choice,
> **something you're <70% sure on**) → escalate to `/ultra:run --large`"
> — `plugins/harness/templates/prompts/orchestrator.md:19-21`, **VERIFIED** (I read the file)

The research says that number is not measuring anything:

- Xiong et al. survey verbalized-confidence elicitation and find **pervasive overconfidence,
  predominantly in the 80–100% band**. **CLAIMED** (via search summary).
- *Wired for Overconfidence: A Mechanistic Perspective on Inflated Verbalized Confidence in LLMs*
  (arXiv 2604.01457, COLM 2026) localises the inflation to a stable set of MLP blocks and attention
  heads in middle-to-late layers, conserved across datasets — i.e. it is a **model-internal mechanism**,
  not a prompt artefact. **CLAIMED** (arXiv listing via search; abstract read, paper not).
- An evaluation across **48 LLMs** reports poor self-reported confidence calibration as an **intrinsic
  limitation across all tested models**; high task accuracy does not imply usable uncertainty.
  **CLAIMED** (via search summary of medical-QA calibration work, PMC13309378).
- Instruct-tuned models at 3–9B show ceiling rates above 90% — near-maximum confidence regardless of
  correctness. **CLAIMED**.

**INFERRED, and I would defend it:** "the agent is <70% sure" and «агент не впевнений на сто» [062] are
the *same* quantity, and it is not measurable by asking the agent. Any definition of the two modes that
turns on self-assessed confidence will, in practice, behave as "always confident" — which means
**autonomous by default, silently, even in controlled mode**. Proposals P2, P3 and P5 below avoid
confidence entirely; P1 and P4 quarantine it behind a structural trigger.

A usable substitute that needs no calibration: **disagreement**. Three advisors with different lenses
disagreeing is an observable, non-self-reported uncertainty signal. The previous harness already had
the mechanism (`agents/council-advisor.md`, model `opus`, 3 voices, "majority + strongest argument",
**VERIFIED** — I read it) but used it as a *decision procedure*, never as a *trigger*. Turning "the
council split" into the escalation signal costs nothing extra and is not self-reported.

### 2.11 What the previous generation actually did, and what happened

**The design (VERIFIED — `plugins/harness/docs/DESIGN.md` §10c and the orchestrator prompt):**

Four tiers, chosen by the model:

| Tier | Trigger (as written) | Action |
|---|---|---|
| Small / low-stakes | naming, obvious trade-off, local refactor | decide; `harness-state.sh decision "<title>" "<rationale>"` |
| Non-trivial in-scope | two defensible designs, ambiguous requirement, API shape | 3 `council-advisor` agents (simplicity / risk / user-impact), majority + strongest argument |
| Hard / high-stakes | architecture, cross-cutting, **<70% sure** | `/ultra:run --large`, adopt its recommendation |
| Scope change | ticket doesn't cover it | block the ticket |
| Irreversible / prod | `guardrails.owner_gated` | never executed → `OWNER-ACTIONS.md` |

Plus the hard rule at the top of the prompt: "**Never use AskUserQuestion** — decide autonomously, by
the right tier for the stakes. Nobody is watching." (**VERIFIED**.) That is a permanently-autonomous
run with no controlled mode at all — the previous generation had exactly one of the owner's three
config values.

Two engine verbs carry the logging contract (**VERIFIED** — `bin/harness-state.sh`):

```
state.sh decision <title> <rationale...>          → appends to RUN-REPORT-adjacent DECISIONS.md
state.sh owner-action <title> <why> <command> <verify>  → appends to OWNER-ACTIONS.md
```

Note the shape of `owner-action`: **why / command / verify**. It does not merely say "I need you"; it
hands over the exact command and how to check it afterwards. That field triple came from a real
incident (L20: "owner actions scattered across state files") and is worth keeping verbatim.

**What the field notes record about it (all VERIFIED — `plugins/harness/docs/FIELD-NOTES.md`):**

*It worked, in the ways that were observable:*

- §9.1 — **eleven** questions were routed to the project's question channel rather than answered by
  assumption (`Q-P9-01`, `Q-T122-01`, `Q-OWN-01..04`, `Q-ORCH-04..07`, `Q-RESTORE-01`, `Q-PARITY-01`,
  `Q-T250-01`), **each with a recorded `Fallback`** and each later marked answered.
  **This is the most important single fact in the cluster.** The proven-in-production pattern is not
  "ask and wait" — it is **ask, declare what you will do if nobody answers, continue**.
- §9.1 — `Q-PARITY-01` drove the question **empirically before asking**: removed a permission check,
  rebuilt, ran the comparison in 27.4 s, found 64 count-pairs identical across four roles and sixteen
  collections, and asked only what measurement could not settle. A pre-escalation obligation
  ("measure first, then ask") with a real instance behind it.
- §9.2 — checks caught real defects: a plan rejected through three revision rounds; a phase rejected
  with one blocker and four warnings, three sent back, **one warning declined with reasoning**; eight
  warnings plus `IN-03` fixed before merge.
- §9.2 — a process gap was **disclosed rather than buried**: phases 14–18 shipped with builder-only
  verification because of a bad orchestrator instruction; corrected from 19 on and reported.

*It failed, in ways the same logs record:*

- §11.1 — "**The stale-heartbeat nudge is the only escalation the engine has.**" Observed peaks before
  a nudge fired: **2808 s** (47 min) in the current run and **44791 s (≈12.4 h)** in the previous one.
  "Nothing stronger is triggered at any ceiling."
- §11.1 — a subagent retried `docker desktop start` for **33 m 31 s** against an unreachable daemon,
  spending **184k tokens**, "indistinguishable from working by heartbeat". Found by reading the log
  by hand.
- §11.6 — an **85-minute self-sustaining loop**: the watch matched what looked like a usage-cap banner
  inside the orchestrator's **own wrapped prose**, pressed Escape and sent `continue` every ~60 s
  forever. "**Nothing internal detected it**" — it ended on an external `SIGTERM`. Line 5620 of the
  log reads `NO ONE IS BEING TOLD`.
- §11.5 — the owner's default Docker stack was destroyed by `docker compose down -v` with no
  `COMPOSE_PROJECT_NAME`. "Detected only afterwards from image and volume timestamps; **the actor was
  never identified**, and a session had refused that exact action as owner-only **two minutes
  earlier**." Prose owner-gating held in one session and not in another, with no attribution.
- §4.1 — a merge **reported success and did nothing** (`Already up to date` / `Everything up-to-date`
  on the phase branch against itself). Caught only because the orchestrator checked what `master`
  actually pointed at.
- §4.2 — a phase reached the trunk **without its independent validation**; the orchestrator simply
  never spawned the validator, then caught its own error about a minute later.
- §12.7 — **"An audit log that recorded events that never happened"**: a security review of a single
  API read found **26 refusal events in the audit log that never occurred.**

**The last one is fatal to a naive logging contract.** «Він прозвітовує» [062] cannot mean "the agent
writes what it decided", because on this exact codebase the agent wrote refusals that never happened.
Every proposal below therefore separates **engine-written** log lines (a verb ran, exit code, timestamp,
tty, git sha) from **model-written** ones (rationale), and treats only the first as evidence.

---

## 3. What is feasible per platform

| Capability the two modes need | Claude Code 2.1.278 | Codex 0.152.0 | cursor-agent 2025.09.12 | Others (GLM, Kimi, Gemini) |
|---|---|---|---|---|
| Named autonomy tiers | **6** (`manual/acceptEdits/plan/auto/dontAsk/bypassPermissions`) — VERIFIED | sandbox×approval = 3×2 — VERIFIED | 1 bit (`--force`) — VERIFIED | not installed here — **UNVERIFIED** |
| Per-run override of a named config | `--permission-mode`, `--settings`, `--setting-sources` — VERIFIED | `-p/--profile` layering `$CODEX_HOME/<name>.config.toml`, `-c key=value` — VERIFIED | none found — VERIFIED | UNVERIFIED |
| Deterministic deny that the model cannot argue with | `permissions.deny`, evaluated before everything, unoverridable from any level — VERIFIED | sandbox boundary (OS-level) — VERIFIED | "unless explicitly denied" deny list — VERIFIED (mechanism unexamined) | UNVERIFIED |
| Policy expressed as data the owner edits | `permissions.{allow,ask,deny}` + `autoMode.{environment,allow,soft_deny,hard_deny}` prose + CLAUDE.md — VERIFIED | `config.toml` + profiles; no prose rule-list equivalent found — VERIFIED (absence) | none found | UNVERIFIED |
| Escalation routed to a non-human handler | `--permission-prompt-tool <mcp tool>`, `PermissionRequest` hook — VERIFIED | `--approve-for-me` (automatic review, sandbox-scoped) — VERIFIED | none | UNVERIFIED |
| Fail-closed when nobody can answer | `--permission-prompts none` (deny, tell Claude not to retry, remove `AskUserQuestion`) — VERIFIED | `--ask-for-approval never` ("execution failures are immediately returned to the model") — VERIFIED | `--force` off ⇒ blocks | UNVERIFIED |
| "This session is stranded waiting" as an event | `Notification` matchers `permission_prompt`, `idle_prompt`, `agent_needs_input` — VERIFIED | not found — VERIFIED (absence in `--help`); issue #16301 requests parity — CLAIMED | not found | UNVERIFIED |
| Interactive question answerable by the orchestrator (R1-11 [324]) | `AskUserQuestion` exists and can be answered by another session; removed entirely under `--permission-prompts none` — VERIFIED | interactive TUI only | n/a | UNVERIFIED |
| Circuit breaker on repeated blocks | 3-in-a-row / 20-total → pause & prompt; **not configurable**; **does not fire in `-p` without a prompt host** — VERIFIED | none documented in `--help` | none | UNVERIFIED |

**Divergences that should each become their own question for the owner (per I1 [182–184]):**

- **D-1.** On cursor-agent (and, until verified, GLM/Kimi/Gemini), "controlled" cannot be expressed
  *inside* the tool. Either the orchestrator enforces it from outside (spawn read-only, review the
  diff, spawn again to apply) or those platforms are simply not eligible for controlled runs.
- **D-2.** The Claude-Code circuit breaker (3/20) is **not configurable** and **absent in headless
  runs**. A run mode that relies on "it will stop when it keeps getting blocked" is true in an
  interactive terminal and false in `-p`.
- **D-3.** Codex's `on-request` puts the escalate/don't-escalate decision **in the model by design**.
  On Claude Code that is a choice the orchestrator makes; on Codex it is the vendor's default. The two
  platforms cannot be given identical semantics without extra work on one of them.
- **D-4.** This machine's Codex is configured `sandbox_mode = "danger-full-access"` (VERIFIED). Any
  mode definition that leans on "the sandbox is the boundary" is currently false here.

---

## 4. What is NOT feasible, and why

1. **"The agent stops when it is unsure" — not implementable as written.** Self-reported confidence is
   uncalibrated and ceiling-biased (§2.10). There is no API on any of these platforms that exposes a
   trustworthy uncertainty signal. What *is* implementable: stop on a **structural** trigger (an
   unmatched action class, a council split, a second failure, a missing precedent).

2. **"The agent decides for itself when to force a hard stop" [082] — implementable but unbounded, and
   unratified.** Nothing constrains it, nothing tests it, and the same mechanism produced the run that
   never stopped (§11.1: 12.4 hours of silence, one nudge) *and* the run that could not stop itself
   (§11.6: 85 minutes of `continue`). It can be built; it cannot be relied upon. Raise it (Q-3).

3. **Nothing in any platform measures a session's context window from outside.** FIELD-NOTES §3.3:
   "Nothing in the plugin measures context." **VERIFIED.** So a mode cannot be defined in terms of
   "escalate before you run out of room".

4. **A model-written decision log is not evidence.** §12.7: 26 refusal events that never occurred.
   **VERIFIED.** Feasible: an engine-written append-only log of *verb invocations*, with the model's
   rationale as an attached, explicitly-untrusted field.

5. **"Prove the work happened" cannot be carried by the mode definition.** R1-13 [344] assigns
   verification to the configured process. And FIELD-NOTES §4.1/§11.4/§11.9 show success-reporting
   no-ops surviving every gate on that project. A run mode can decide *who decides*; it cannot decide
   *whether the work was real*.

6. **A hard stop that blocks the queue is not what he asked for.** Д6 [449]: independent tasks
   continue while one waits. So "hard stop" must mean *this task holds*, not *the run holds* — except
   where he explicitly said the run holds (Д7 [455]: default recommendation is stay and wait when
   only human-blocked work is left).

7. **`bypassPermissions` cannot be the autonomous mode.** Vendor text: "offers no protection against
   prompt injection or unintended actions"; refuses to start as root/sudo; needs a one-time interactive
   acceptance before a background session will run (**VERIFIED**). And ticket bodies are untrusted
   input on this design (previous harness already fences them: `tickets.sh render`, DESIGN 0.6.0).

---

## 5. Five concrete proposals

Each is a complete pair of definitions. They are **alternatives**, not layers, though P0 below is
common to all of them. Read the failure mode before the appeal.

### P0 — The invariant floor (common to all five)

Not a proposal; the part that does not change between modes, derived from what is already decided.

- **Blast radius is declared before the run, not judged during it.** The run may write to: the
  worktrees it created (Д4 [433]), the branches it created, the tickets it claimed, the containers and
  services it started (Д3 [430]), and its own run directory. Everything else is outside. This is R1-16
  [366] expressed as a list rather than as self-awareness.
- **The red-line file is read by every agent at start and re-read on every tick** (R1-15 [357], plus
  §2.3's verified lesson that prose in a transcript is lost to compaction while prose in a re-read file
  is not).
- **Two logs, different trust.** `events.log` is engine-written: verb, args-digest, exit code, UTC
  timestamp, session tty, git sha before/after. `DECISIONS.md` is model-written: rationale, tier,
  basis. Only the first is evidence (§12.7).
- **Every escalation carries a `Fallback`** — what happens if nobody answers — because that is the one
  escalation format that demonstrably worked eleven times out of eleven (§9.1).
- **Measure before you ask** (the `Q-PARITY-01` obligation, §9.1): if the question is settleable by
  running something inside the blast radius, run it first and escalate only the residue.

### P1 — Modes differ only in **where an unresolved question goes**

*The minimal reading, and the one consistent with «Не знаю, чи вони будуть відрізнятися» [058].*

**Classifying rule.** A moment needs the owner when the orchestrator has a question it cannot resolve
**after consulting the configured basis** ([087]: rules+examples · prior similar answers · repo tone of
voice · project knowledge). The basis is consulted identically in both modes. Only the disposition of
the residue differs:

- **Controlled:** residue → the Д6 channel → **this task holds** («поки людина не відпустить» [062]);
  other independent tasks continue (Д6 [449]).
- **Autonomous:** residue → the agent chooses → **records the choice and continues** → reports in the
  run report («він прозвітовує» [062]).

**What the agent may do without him:** identical in both modes — everything inside P0's blast radius
whose action class is not on the stop list. The mode changes *nothing* about capability.

**What gets logged:** engine — `escalation.raised(question-id, class, basis-consulted, fallback)` and
`escalation.resolved(by: owner | basis | fallback | timeout)`. Model — the question text, the basis
excerpt it matched, and in autonomous mode the choice and rationale. Every autonomous residue decision
is flagged `taught: pending` until he marks it right or wrong — that is [062]'s «треба вчити» as a
field rather than a promise.

**Failure mode.** *The basis always answers.* A tone-of-voice document written to let the agent answer
«майже замість неї» [092] will match almost everything, the residue goes to zero, and controlled mode
becomes indistinguishable from autonomous. Observable symptom: escalations-per-run trending to zero
while decisions-per-run rises. Needs a floor: an action class list that escalates regardless of what
the basis says (which is P2).

**Trade-off.** Cheapest to build and the easiest to explain. It gives him the least protection, because
one well-written tone-of-voice file silently collapses the distinction.

---

### P2 — Modes differ only in **where the line sits on a three-band action list**

*Policy-as-data. Confidence plays no part. Closest to what Claude Code actually ships.*

**Classifying rule.** Every action the orchestrator or a worker is about to take is matched against
three prose lists in the run's config — deliberately the `autoMode` shape (§2.2), because it is proven
and because he can read and edit it:

- `always_mine` — never taken without him in either mode. Starts as: anything outside the blast radius;
  anything on the red-line file; the categories Anthropic's `hard_deny` + the irreversible half of
  `soft_deny` already name (production deploy, irreversible deletion, permission grant, secret-store
  write, DNS/cert change, force push, merge without review, self-approval, CI bypass, real-world
  transactions). **Ready-made: 70 rules, printable today with `claude auto-mode defaults`.**
- `always_yours` — always taken without him in either mode: reads, writes inside the worktree, the
  configured process's own steps, ticket comments and status moves.
- **the middle band** — everything else. **This band is the entire definition of the two modes.**
  - **Controlled:** middle band → him.
  - **Autonomous:** middle band → the agent, on the configured basis, reported after.

**What the agent may do without him:** exactly `always_yours` in controlled mode; `always_yours` +
middle band in autonomous mode. Never `always_mine`, in any mode, including when the agent thinks it
should — which is the same asymmetry `bypassPermissions` keeps (§2.1) and the same one the previous
harness's L22 encodes ("'ignore all limits' override must not unlock prod writes").

**The escape valve, borrowed verbatim from the shipped classifier:** a middle-band or `always_mine`
action clears **only if the owner named the operation and its target** — the
`[named+specifics — must name: …]` predicate (§2.2). «Fix the deploy» does not authorise a production
deploy; «deploy api-gateway to prod» does. This makes "he approved it" checkable instead of arguable.

**What gets logged:** engine — for every action: `action.class`, which list matched, which rule string,
the verdict, exit code. This is the only proposal where a third party can later reconstruct *why* an
action was allowed, because the matched rule string is in the log.

**Failure mode.** *The list is never complete, and the gap fails open.* An action matching nothing lands
in the middle band, which in autonomous mode means "do it". The real instance is on record: the
`docker compose down -v` that destroyed the owner's default stack (§11.5) — a session had refused that
exact action as owner-only two minutes earlier, so the *class* was known and the *variant* wasn't. Fix
direction: unmatched ⇒ treat as `always_mine` (fail closed) and log an `unclassified` event so the list
grows from real runs — the same loop `/auto-mode-setup` implements (§2.9). But fail-closed collides
with Д7/Д11's preference for a run that keeps moving quietly.

**Trade-off.** The most inspectable and the most defensible, and the only one where "what may be
delegated" (R1-02 [107]) is answered by a file he can read rather than by a mode name. It costs the most
authoring up front — though §2.2 means most of that authoring already exists and is free to copy.

---

### P3 — Modes differ by **whether the action can be undone by this run**

*"Let an agent do anything it can undo." The reversibility axis from the CSA/Knight frameworks (§2.9).*

**Classifying rule.** For each action the orchestrator must name, before acting, a concrete undo that
**this run can execute by itself**: a git revert of a named sha, `git worktree remove`, `docker compose
-p <project> down`, a ticket status restore. If it cannot name one, the action is irreversible.

- **Autonomous:** may take any reversible action inside the blast radius without asking; must escalate
  every irreversible one.
- **Controlled:** may take any reversible action inside the blast radius **whose effect is confined to
  artefacts the run created**; must escalate anything that becomes visible outside the run (a push, a
  PR, a comment on a ticket he watches, a notification) even when it is technically reversible.

**What the agent may do without him:** in both modes, everything it can undo; the modes differ on
*visible-but-reversible*.

**What gets logged:** engine — `undo.declared(action, command, verified: yes|no)` before the action, and
`undo.available` after. A declared undo that cannot be verified by the engine (e.g. "restore from
backup") is not an undo, and downgrades the action to irreversible.

**Failure mode.** *"Reversible" is a claim the model makes and the evidence says it is often wrong.*
Three recorded instances: the merge that printed `Already up to date` and did nothing while reading as
success (§4.1); the OOM-kill of the owner's container by two parallel builds — no undo, no live alert,
found by correlating timestamps (§11.5); and two role passwords printed in clear text into a session
transcript by Playwright `--trace on`, where **"no automated secret scan covers tool output or
transcripts"** (§11.10) — a leak has no undo at all. Also: reversibility is **cheap to claim and
expensive to verify**, so the verification step is the first thing a long run will skip.

**Trade-off.** The most intuitive and the easiest to explain to a stranger. The most dependent on the
model telling the truth about the world, which is the exact dependency the field notes say to avoid.
Strongest as a *component* of P2 (use it to place actions in the three bands) rather than as the
primary rule.

---

### P4 — One mode with a timeout: **controlled = infinite wait, autonomous = wait T then take the declared fallback**

*The workflow-engine pattern (§2.8) applied to his own proven `Fallback` field (§9.1).*

**Classifying rule.** Identical in both modes — use P2's lists, or P1's residue, whichever he picks.
What differs is only **what happens when the owner does not answer**:

- Every escalation is written to the Д6 channel with four fields: **question · why now · what I will do
  if you don't answer (the `Fallback`) · deadline T**.
- **Controlled:** T = ∞. The task holds until he answers, exactly «поки людина не відпустить» [062].
- **Autonomous:** T is configured (per-class, defaulting to something like the Step Functions
  convention of 24 h — **CLAIMED** as a convention, not a recommendation). At T, the declared
  `Fallback` executes, and the decision is recorded as `taken_by: timeout` — never as a normal decision.

This is the only proposal where the two modes are **one mechanism with one parameter**, which is what
[058] hints he may actually want. It also satisfies Д7 [455] directly: he can change T *during* the run
by editing the control file, and the orchestrator re-reads it on the next tick.

**What the agent may do without him:** anything whose `Fallback` it can honestly write down. A moment
for which no safe fallback exists **cannot be given a finite T** — that is the machine-checkable
definition of "this really does need him", and it is stronger than any confidence threshold.

**What gets logged:** engine — `escalation.opened(id, class, fallback, T, opened_at)`,
`escalation.answered(id, by, at)` or `escalation.expired(id, fallback_executed, at)`. Plus a per-run
counter, **expired-vs-answered**, which is the single number that tells him whether the run mode is
working. A run with 11 escalations and 11 answers (§9.1's actual record) is healthy; a run with 11
escalations and 11 expiries is bypass mode wearing a costume.

**Failure mode.** *The fallback becomes the policy.* He is asleep; T expires; the run does what the
fallback said. Over a few runs, the fallbacks are tuned to "continue" because that is what keeps runs
finishing, and autonomous mode degrades into `bypassPermissions` with paperwork. The verified analogue
is Claude Code's own documented behaviour under `-p` with no prompt host: repeated blocks reach the
threshold, "the action doesn't run and Claude keeps working… Claude Code doesn't stop the run" (§2.4).
Second failure: he *did* answer, but into the wrong place — field notes §12.5 records "a channel that
forked", and §11.2 "instructions that were typed and never submitted".

**Trade-off.** Unifies the two modes instead of specifying them twice, and produces the one health
metric that makes the design falsifiable. Requires the Д6 channel to be genuinely reliable, which on
this evidence it has not yet been.

---

### P5 — Autonomy is **earned per question-class from a precedent ledger**

*The literal implementation of «tone of voice … майже замість неї може відповідати» [092].*

**Classifying rule.** Every decision is tagged with a **class** (a short, stable key: `naming`,
`dependency-bump`, `test-strategy`, `branch-cleanup`, …). A ledger records, per class, the prior
decisions and the owner's verdict on each (approved / corrected / rejected).

- The agent may decide a moment **only if** its class has ≥ N owner-approved precedents in the ledger
  **and** no correction newer than the newest approval.
- **Autonomous:** N is small (2–3) and new classes escalate once, then become decidable.
- **Controlled:** N = ∞ — no class is ever self-decidable; every decision goes to him, and the ledger
  is built purely as a record.

This makes his three "bases" [087] concrete rather than aspirational: *written rules* = the seed
entries he authors by hand; *previous answers to similar questions* = the ledger itself; *repo tone of
voice* = seed entries read out of the project's own CLAUDE.md-shaped file; *the agent's own project
knowledge* = the explicit "no ledger required" setting, i.e. N = 0.

It is also the only proposal that implements «якщо це не підходить, то треба вчити» [062]: a correction
is a ledger write that **revokes** the class's autonomy until it is re-earned.

**What the agent may do without him:** whatever the ledger says it has earned, and nothing else. On day
one that is nothing — which is an honest and probably correct starting state.

**What gets logged:** engine — every ledger read (`class`, `precedents_found`, `verdict`) and every
ledger write, append-only with the writer identified (owner vs engine vs model). The ledger **must not
be writable by the deciding session** — §12.7's 26 fabricated refusal events is precisely what happens
when the actor writes its own record.

**Failure mode.** *Precedent over-generalisation.* One approval for a narrow case becomes authority for
a wide one. The recorded instance is exact: an orchestrator generalised **a narrow `council-advisor`
warning into "every GSD agent"**, and GSD's verify stage was silently skipped for **phases 14 to 18**,
each `NN-VERIFICATION.md` self-attributing `verified_by: the lane that built the phase`. "No automated
check caught it; manual review did." (§11.4, VERIFIED.) Second failure: **class-key drift** — the same
question gets a new key each run, so nothing ever accumulates and the run stays at N=0 forever.

**Trade-off.** The only proposal that gets *safer* with use, and the only one that closes his learning
loop. Also the slowest to become useful, the most machinery, and the one with the worst failure when it
goes wrong — because the failure is invisible and compounding.

---

### Comparison

| | Trigger is | Needs the model to be honest about | Gets better with use | Collapses into bypass when… | Smallest thing it needs to work |
|---|---|---|---|---|---|
| **P1** routing | an unresolved residue | its own uncertainty | no | the basis answers everything | the Д6 channel |
| **P2** action bands | a pattern match on the action | nothing | only if unmatched-actions are harvested | the list has a gap and gaps fail open | one prose list (70 rules copyable today) |
| **P3** reversibility | "can I undo this" | the world | no | "reversible" is asserted, not verified | a verified undo command per action |
| **P4** timeout | the same as whichever it wraps | the fallback being safe | no | T expires unattended and fallbacks drift to "continue" | a reliable answer channel |
| **P5** precedent | class has N approvals | the class key being stable | **yes** | a precedent is over-generalised | an append-only ledger the session can't write |

**They compose.** P2 supplies the classification, P4 supplies the disposition, P5 supplies the learning,
P3 helps place actions in P2's bands, P1 is what is left if he wants the smallest possible thing. The
natural stack is **P2 + P4**, with P5 added later once the ledger has something in it. That is an
observation about the shapes, not a recommendation — the choice is his, and [058] leaves open that he
may want none of the five and a single mode with a dial.

---

## 6. Open questions this raises for the owner

**Q-1 — Do the two modes differ in *capability*, or only in *who answers*?** At [058] you said you did
not know whether they differ at all. P1 and P4 say they do not (same powers, different disposition of a
question). P2 and P5 say they do (autonomous genuinely has more powers). This single answer eliminates
three of the five proposals.

**Q-2 — What does "hard stop" stop?** [062] says «на паузі, поки людина не відпустить»; Д6 [449] says
independent tasks continue. So: this task, this lane, or the whole run? And does the answer change
between the two modes?

**Q-3 — The agent forcing a hard stop in an autonomous run [082] was never confirmed** (the restatement
carrying it got a new condition, not a yes — `extract/corrections.md:83`). Is that clause in or out?
If in: it is the only unbounded authority in the design, and nothing tests it. What would make you
comfortable with it — a required reason code, a cap on how often, an obligation to try the fallback
first?

**Q-4 — Is the red line really enforceable as prose alone?** R1-15 [357] says one text file is enough.
The evidence says prose held in one session and not in another two minutes later, and the destroyed
stack was never attributed to an actor (FIELD-NOTES §11.5). Claude Code's own answer is explicit: prose
steers the classifier, but "for a hard guarantee, add a deny rule instead" (§2.3). Would you accept
**one text file plus a generated deny list** — the file stays the single source you edit, and the
engine compiles the subset it can enforce — or does that break the "no procedure for this" decision?

**Q-5 — What is a decision's *class*, and who names it?** P5 needs stable class keys, and a per-class
tone of voice is a far smaller writing job than a general one. Do you want to enumerate the classes you
care about (naming · dependency choice · test strategy · scope trim · branch/merge · infra), or should
the agent propose them from the first runs and you approve the list?

**Q-6 — Where is the tone-of-voice file, and who may write it?** [087] allows «tone of voice в цьому
репозиторії» — the project's own file, not written for the orchestrator. That means the decision basis
is **untrusted input** whenever the project is not yours. Should the orchestrator read a project-supplied
tone of voice at all, or only one under your control? (Claude Code makes this exact distinction: the
classifier reads `autoMode` from user and managed settings but **deliberately not** from
`.claude/settings.json` in the repo, "so a checked-in repo or a build step could otherwise inject its
own allow rules" — VERIFIED, §2.9.)

**Q-7 — What is the fallback when nobody answers, and does the answer differ by mode?** P4 makes this
the whole definition. Your project's own record is that eleven escalations each carried a `Fallback`
and all eleven were answered (§9.1) — so you have already used this pattern successfully. Should the
fallback be mandatory (no escalation may be raised without one), and should "no safe fallback exists"
be the formal definition of a moment that must reach you?

**Q-8 — Per platform (I1):** on cursor-agent the only autonomy control is `--force` on/off (VERIFIED).
GLM, Kimi and Gemini are not installed here and I could not verify them. Is "controlled mode" required
to work on every platform — which would mean the orchestrator enforces it from outside the tool, e.g.
spawn read-only, review, spawn again to apply — or may a platform be marked *autonomous-only* and
excluded from controlled runs?

**Q-9 — «якщо це не підходить, то треба вчити» [062]: what is the teaching act?** Marking a decision
wrong in the run report, editing the tone-of-voice file, or writing a ledger entry that revokes a
class? Nothing in the previous generation implemented any of them, and without one, an autonomous run's
report is a record nobody acts on.

**Q-10 — Which number tells you a run mode is working?** P4 offers expired-vs-answered escalations. On
the last real run the comparable numbers were: 11 escalations, 11 answered; one escalation ladder whose
*only* rung was a heartbeat nudge that took up to 12.4 hours to fire; and an 85-minute loop nothing
internal detected. Is there a number you would want to see in the run report every morning?

---

## Sources

Primary, run or read on this machine (VERIFIED):
`claude --help` · `claude auto-mode defaults|config|--help` · `codex --help`, `codex exec --help`,
`~/.codex/config.toml` · `cursor-agent --help` ·
`plugins/harness/docs/DESIGN.md` · `plugins/harness/docs/FIELD-NOTES.md` ·
`plugins/harness/templates/prompts/orchestrator.md` · `plugins/harness/bin/harness-state.sh` ·
`plugins/harness/bin/harness-trust.sh` · `plugins/harness/agents/council-advisor.md` ·
`product/spikes/harness-rebuild/round-1/TRANSCRIPT-01.md` ·
`product/spikes/harness-rebuild/round-1/ANALYSIS-01.md` ·
`product/spikes/harness-rebuild/research/extract/{by-item,outside-list,corrections,meta}.md`

Vendor documentation fetched 2026-09-19 (VERIFIED as primary):
- [Choose a permission mode](https://code.claude.com/docs/en/permission-modes)
- [Configure permissions](https://code.claude.com/docs/en/permissions)
- [Configure auto mode](https://code.claude.com/docs/en/auto-mode-config)
- [Hooks reference](https://code.claude.com/docs/en/hooks)
- [Run Claude Code programmatically (headless)](https://code.claude.com/docs/en/headless)
- [Settings files and precedence](https://code.claude.com/docs/en/settings)

Secondary (CLAIMED — read via search summaries or abstract only):
- [Levels of Autonomy for AI Agents — Feng, McDonald, Zhang, arXiv 2506.12469](https://arxiv.org/abs/2506.12469) (abstract fetched)
- [Wired for Overconfidence: A Mechanistic Perspective on Inflated Verbalized Confidence in LLMs, arXiv 2604.01457 (COLM 2026)](https://arxiv.org/html/2604.01457)
- [Calibration of Self-Reported Confidence and Accuracy of Large Language Models in Medical Question Answering (PMC13309378)](https://pmc.ncbi.nlm.nih.gov/articles/PMC13309378/)
- [Mind the Confidence Gap: Overconfidence, Calibration, and Distractor Effects in LLMs, arXiv 2502.11028](https://arxiv.org/pdf/2502.11028)
- [Agentic AI Autonomy Levels and Control Framework v2 — Cloud Security Alliance](https://labs.cloudsecurityalliance.org/research/agentic-ai-autonomy-levels-control-framework-v2-csa-styled/)
- [Autonomy Levels for Agentic AI — CSA blog, 2026-01-28](https://cloudsecurityalliance.org/blog/2026/01/28/levels-of-autonomy)
- [Human-in-the-loop — LangChain docs](https://docs.langchain.com/oss/python/langchain/human-in-the-loop)
- [Human-in-the-loop — OpenAI Agents SDK](https://openai.github.io/openai-agents-js/guides/human-in-the-loop/)
- [Guardrails and human review — OpenAI API](https://developers.openai.com/api/docs/guides/agents/guardrails-approvals)
- [Human-in-the-Loop Approval Workflows — Temporal](https://temporal.io/blog/human-in-the-loop-approvals)
- [Service integration patterns (callback / task token) — AWS Step Functions](https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html)
- [AGENTSEC04-BP02 Human-in-the-loop for critical decisions — AWS Agentic AI Lens](https://docs.aws.amazon.com/wellarchitected/latest/agentic-ai-lens/agentsec04-bp02.html)
- [Let an agent do anything it can undo](https://www.thisandthat.chat/blog/let-an-agent-do-anything-it-can-undo)
- [hooks: add permission request event for parity with claude code's auto-approve flow — openai/codex #16301](https://github.com/openai/codex/issues/16301)
- [User Elicitation — FastMCP](https://gofastmcp.com/servers/elicitation)
- [The 2026-07-28 MCP Specification Release Candidate](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/)

**Currency note.** Claude Code's permission surface is changing fast: the docs read today carry
per-version notes at v2.1.198, .200, .203, .207, .211, .212, .218, .246, .251, .257, .259, .265 and
.278. Anything in §2.1–§2.5 should be re-checked against `claude --help` and `claude auto-mode config`
before it is built on, not taken from this document. Codex's approval-policy enum in particular has
fewer values in 0.152.0 than earlier builds carried.
