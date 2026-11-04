# C4 — Quota, limits, providers and accounts per role · adversarial pass

Cluster: **C4-capacity** · Items: **R1-06, R1-07**, owner instruction **I1**
Date: **2026-09-19** · Read first: `research/clusters/C4-capacity-research.md`

This document attacks. It does not redesign. Every entry names a decision the owner made, the hole in
it, and a concrete situation in which that hole produces a bad outcome. Where an attack rests on
evidence, the evidence is marked **VERIFIED** (I read it in the transcript, the field notes, the
plugin source, or ran it on this machine today), **CLAIMED** (a third party asserts it) or
**INFERRED**.

**Twelve attacks survived.** Four are blockers — the decision, as stated, cannot produce the outcome
he wants until the hole is closed. Eight are majors: two competent implementers build different
things, or the thing built fails on a night nobody is awake.

Nothing below overwrites a decision. Where a challenge collides with his own words, both sides are
quoted with their `[row]` anchors.

**Six of these attacks rest on probes I ran on this machine today, and four of those contradict the
research document this challenge was told to build on.** Those are marked in place.

---

## Index

| # | Attack | Severity |
|---|---|---|
| A1 | Two profiles can be the same Anthropic account — role separation is unverifiable by anything he decided to configure | **blocker** |
| A2 | «80% тижневого» has no defined scope once roles sit on different accounts | **blocker** |
| A3 | The quota channel is itself a rate-limited shared resource, and it is exhausted on this machine right now | **blocker** |
| A4 | «можливо це буде взагалі pay-as-you-go» deletes every stop condition he defined | **blocker** |
| A5 | On the platform nominated as the reference, `primary` is sometimes the 5h window and sometimes the weekly one — verified across 7,379 records on his own disk | major |
| A6 | «Unreadable» is not a case he ruled on, and the shipped default makes the whole limiter inert | major |
| A7 | «зупинити завдання прямо вже» is not deliverable against a session you cannot talk to, and it destroys the state that justifies it | major |
| A8 | «перед запуском переконатися, що це працює» verifies at t0; the switch happens at t+9h on a token that expires | major |
| A9 | Role-restricted provider plus wait-for-reset is an undefined deadlock at 01:00 | major |
| A10 | «хард» in the watched file and «хардстоп» in the limits rule are the same word with different actions, and the file has no owner | major |
| A11 | The meter reads an account the run is not spending on — reproducible today, twice, by two different mechanisms | major |
| A12 | Headroom for his own parallel work was never asked, and [370] makes it a red line he cannot hold | major |

---

## A1 — Two profiles can be the same Anthropic account · **blocker**

**The decision.**

> «На початку, я думаю, буде достатньо, щоб мануально вказувати що яким провайдером буде
> виконуватись, що на якого провайдера перекидувати той чи інший клаптик роботи. Наприклад, на кого
> буде працювати оркестратор, на кого буде працювати скажімо, контекст фочер, на кому екзек'ютор
> буде.» **[036]**

> «з кожної з цих платформ може бути різна кількість аккаунтів» **[041]**

> «Наприклад, в моєму випадку це перемикач профілів, який використовує різні профілі.» **[199]**

> «перед запуском потрібно переконатися, що це працює, щоби це не було проблемою для користувача» **[199]**

**The hole.** The unit he configures is a **profile**. The unit that holds quota is an **account**.
Nothing he decided requires those to be checked against each other, and nothing guarantees they
coincide.

**VERIFIED** by reading `oauthAccount` out of each profile's `.claude.json`: two config dirs can share
one account and quota pool — two keychain entries, two OAuth tokens, one pool — and the plan field does
not distinguish them either, so per-dir usage reads can double-count.

**This contradicts the research.** `C4-capacity-research.md` §3.1 treats each profile as a separate
account and builds the whole per-role allowlist story (§5.2, §5.6) on top of that. It verified the
keychain derivation per profile and never checked which account each one is.

**Concrete failure.** The owner configures the orchestrator on `<profile-A>` and the three executors on
`<profile-B>`, on the stated belief that a role-restricted account [270] gives the orchestrator
protected headroom. The pre-run check [199] passes: switching works, both profiles resolve, both
report a live token. At 03:20 the executors have pushed the shared weekly window past his hard-stop
threshold. The orchestrator's «protected» account crosses the same threshold in the same second,
because it is the same account. The run hard-stops with every role dead at once — the one outcome the
role split was configured to prevent. Nothing logged says why, because every reading is labelled by
profile and the two profiles read identically.

**And the verification he asked for cannot catch it.** «переконатися, що це працює» [199] proves the
switch *applied* — a different `CLAUDE_CONFIG_DIR` is in effect, a different token is in use. It is
true, and it is not the thing that matters. The question «are these two roles on different quota
pools?» is not asked by anything in his decision set.

**Collides with:** [270] («може використовувати тільки для оркестратора … І це важливий дуже нюанс»)
— the allowlist is expressed over accounts, and the config names profiles.

---

## A2 — «80% тижневого» has no defined scope once roles sit on different accounts · **blocker**

**The decision.**

> «людина може лише налаштовувати хард ліміти, хардстопи, коли якийсь ліміт, наприклад, там , 80%
> тижневого, або що … то це означає хардстоп, що потрібно зупинити завдання прямо вже та й все» **[171]**

**The collision, in his own words:**

> «на кого буде працювати оркестратор, на кого буде працювати скажімо, контекст фочер, на кому
> екзек'ютор буде» **[036]**

**The hole.** [171] is written in the singular — one limit, one number, one run, one stop. [036] and
[041] make the run a set of N accounts across M providers, each with its own windows. The sentence
«якийсь ліміт … 80% тижневого … зупинити завдання прямо вже» does not say *whose* 80%, nor *whose*
task stops. Every reading is defensible:

- **any-account-crosses → stop the run** (the literal reading of «зупинити завдання прямо вже та й все»)
- **per-account → stop only the sessions on the crossing account** (the reading implied by [036]'s
  per-role assignment)
- **per-role → the threshold is a property of the role, not the account** (the reading implied by
  [270]'s allowlist)

**Concrete failure, implementer A (any-account).** 03:40. The orchestrator's account sits at 82% of
its weekly window — it has been running for thirty hours and it is the cheapest role in the fleet.
The executor accounts are at 8%. The hard stop fires and the entire run dies over the account with
the least work left to do. The owner opens the laptop at 09:00 to a stopped run with 92% of his
executor capacity untouched.

**Concrete failure, implementer B (per-account).** Same moment, same numbers. The orchestrator's
sessions are killed. Three executors keep working, finish their phases, and have nobody to merge
them, nobody to close them and nobody to spawn the next wave. `FIELD-NOTES.md` §10.1 records that
this is exactly how the previous run ended:
`watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)` **VERIFIED**,
with `DEAD-RUN` and `STOPPED` on disk. Implementer B ships that state as designed behaviour.

**What is undefined, separately from which reading wins.** Whether a threshold applies to the *worst*
bucket on an account or to a named one; whether an account below threshold can absorb a role whose
account crossed it; and whether the soft/hard pair are two thresholds on one number or two
independent settings (his own example gives both the same value — «хардстопи … 80% тижневого» and
«Якщо це софт стоп, наприклад, 80 відсотків» — at which point they cannot both be true).

**Collides with:** [036], [041], [270] (all his own).

---

## A3 — The quota channel is itself a rate-limited shared resource, and it is exhausted right now · **blocker**

**The decision.** Every stop mode in [171] is a comparison against a number that must be read:

> «якщо, наприклад, виглядає так, що завдання впирається в те, що впереться в ліміти, то це окей» **[171]**

**The hole.** Reading the number costs something scarce, and nothing in his decision set treats the
reader as a contended resource.

**VERIFIED, on this machine, minutes ago.** I made **one** call to
`https://api.anthropic.com/api/oauth/usage` with the canonical keychain token. The response:

```json
{"error":{"type":"rate_limit_error","message":"Rate limited. Please try again later."}}
```

One call. Not a burst — a single request, and it was refused. The lockout is **VERIFIED**; its cause
is **INFERRED** but hard to read another way: a research agent in this same workflow finished its own
probe sequence against this endpoint about one minute earlier (`C4-capacity-research.md` mtime
`2026-09-19 20:23:40` local; my call at `20:24`). That research measured the budget as roughly two
calls with a recovery still incomplete at t+167s. What I measured is the next step: a
*second reader on the same machine* finds the channel already gone, with no way to tell a lockout
from an outage.

**This is not a two-process problem; on his machine it is an N-process problem.** His own global
`CLAUDE.md` instructs **every** Claude Code session to poll this endpoint before and periodically
during any long-running task:

> «Before, and periodically during, any long-running task/workflow — check both windows and act»

So each of his three roles [204] — context watcher, orchestrator, executor — arrives with a standing
instruction to poll, before the orchestrator's own gate polls, before a watcher's cycle polls. Four
readers, a two-call budget.

**Concrete failure.** 04:00, unattended. The context watcher polls on its 120-second cycle. The
orchestrator's spawn gate polls before each spawn. An executor, following the global instruction,
polls at the start of its turn. From the third call onward every read returns `rate_limit_error`
forever, because nothing backs off and the recovery window is longer than every cycle involved. The
run is now blind. What happens next is A6's problem — and in the shipped tool, the answer is
`proceed`.

**The research's mitigation does not reach this.** §5.4 proposes «poll the active account only»,
which addresses contention *between accounts*. The contention I measured is between *readers*, and
the research itself records that whether the throttle is per-token or per-IP is **UNKNOWN** — if it is
per-IP, per-account polling buys nothing at all and rotating accounts to read quota is a no-op.

**Collides with:** the owner's own standing global instruction, which is not a transcript decision but
is a fact about the machine the orchestrator will run on.

---

## A4 — «можливо це буде взагалі pay-as-you-go» deletes every stop condition he defined · **blocker**

**The decision.**

> «тут не має бути конкретної прив'язки до Клода, Треба, мати можливість адоптовуватись до нових
> прав. Що якщо раптом буде не п'ятигодинне вікно, а десяти годинне вікно, або його взагалі не буде?
> Тобто в залежності від підписки, можливо це буде взагалі pay-as-you-go» **[007]**

**The hole.** He treats «no window» as a *shape* the system adapts to. It is not a shape — it is the
absence of the quantity all three of his stop modes are expressed in. Re-read them with no window:

| mode [171] | expressed as | on pay-as-you-go |
|---|---|---|
| hard — «зупинити завдання прямо вже» | a % of a window | no percentage exists |
| soft — «почекати, поки виконує це завдання, після цього більше не зупиняти» | a % of a window | no percentage exists |
| intermediate — «записати теперішній стан … зупинити її повністю, аби потім можна було її продовжити» | wait for a reset | **there is no reset** |

And the recovery rule has no referent either: «просто продовжити після того, як ліміти онуляться»
[171] — nothing zeroes. **VERIFIED** for DeepSeek in the research (§3.4): `user/balance` returns
`total_balance` in CNY/USD, no window, no percentage, no `resets_at`. Same for Amp's credits (§3.11).

**Concrete failure.** An executor role is configured with a BYOK key on a pay-as-you-go provider —
which is the *only* way to run Qwen at all since 2026-04-15 (CLAIMED, §3.6) and the only documented
Gemini path since 2026-06-18 (CLAIMED, §3.7), so this is the default case for two of the platforms he
named at [041], not an exotic one. The run starts at 23:00. At 01:15 that executor enters the failure
mode `FIELD-NOTES.md` §3.1 records **VERIFIED** from a real lane: `w-phase-19` issued **3,466 of its
3,626 Bash calls as the literal command `echo idle`**, mean interval 2.54 s, for three hours and
fifteen minutes, producing 274k output tokens and 1.83 billion cached-token re-reads of nothing.
There is no window to fill, no percentage to cross, no reset to wait for, and no threshold that can
fire. The run bills until he wakes up. In the real run this lane was stopped only because a human told
it to end its turn — «It stopped within one minute of being told to end its turn instead».

**What is undefined.** He never says what a threshold means in money, whether a run may have a
currency cap, or what the *default* is when a provider reports nothing. Note that the one native
money cap that exists — Claude Code's `--max-budget-usd` in `--print` mode (**VERIFIED** in the
research §3.1) — is on the platform that *does* have windows, and absent on the platforms that do not.

**Collides with:** [171] (all three stop modes, his own); [007]'s own «надійно працювало та
продовжувало відпрацьовувати» — on this path it keeps working, which is the failure.

---

## A5 — On the platform nominated as the reference, `primary` is sometimes the 5h window and sometimes the weekly one · major

**The decision.**

> «Що якщо раптом буде не п'ятигодинне вікно, а десяти годинне вікно, або його взагалі не буде?» **[007]**

He asks for adaptation when a window *changes shape*. The research answers that Codex satisfies this
«by the data format itself with no adapter change», because `window_minutes` is a number, and
nominates Codex as the reference platform (§3.2, §5.4, open question 8).

**The hole, VERIFIED on his own disk today.** I parsed every `rate_limits` record in
`~/.codex/sessions/` — **7,379 records** across ten months — and cross-tabulated the plan against the
window shape. The field names do not keep their meaning:

| `plan_type` | `primary.window_minutes` | `secondary.window_minutes` | records |
|---|---|---|---|
| `prolite` (his plan today) | **10080** (weekly) | `null` | **3030** |
| `plus` | **10080** (weekly) | `null` | 1098 |
| `plus` | **300** (5h) | 10080 | 471 |
| `plus` | `null` | `null` | 1 |
| *(absent — older builds)* | **299** | 10079 | 2726 |
| *(absent)* | **300** | 10080 | 53 |

Two real examples, both from his disk:

```
2026-08-27, plan_type "plus":
  "primary":  {"used_percent":0.0,  "window_minutes":300,   "resets_at":1787829494}
  "secondary":{"used_percent":29.0, "window_minutes":10080, "resets_at":1788271951}

2026-09-19, plan_type "prolite":
  "primary":  {"used_percent":17.0, "window_minutes":10080, "resets_at":1789809907}
  "secondary": null
```

Read the table rather than the examples, because it is worse than a plan migration:

1. **`primary` is sometimes the 5-hour window and sometimes the weekly one, within the same plan.**
   `plus` produced 471 records where `primary` is the 5h window and 1,098 where `primary` is the
   weekly window. So an adapter cannot key the meaning off `plan_type` either — there is nothing in
   the payload that says which window `primary` currently is except `window_minutes` itself.
2. **On his current plan the 5-hour window does not exist.** 3,030 of 3,030 `prolite` records report
   weekly only; `secondary` is `null` in every one. In September 2026 specifically: **2,043 of 2,043**
   records, all `window_minutes: 10080`, all `secondary: null`.
3. **The window length is not even a stable constant.** 299 vs 300, 10079 vs 10080 — the same window
   is reported with different lengths, so `window_minutes` cannot be used as a bucket identity key
   either.
4. One `plus` record reports a `rate_limits` object with **both windows null** — a well-formed payload
   carrying no capacity information at all.

**This contradicts the research**, which states «Sampling across the session history shows both window
sizes in the wild: `window_minutes` of 300 (5h), 299, and 10080 (7d) (VERIFIED)» and concludes that
the owner's [007] requirement is «satisfied *by the data format itself* with no adapter change». Both
sizes are in the history; only one is in the present, and the format does not say which window a field
holds.

**Concrete failure.** In August the owner configures, exactly as [171] describes, «хардстоп при 80%
п'ятигодинного» for the executor role on Codex, and verifies it: the reading is live, the number
moves, the threshold is sane. His plan changes to `prolite`. From then on the bucket his threshold
names is never reported. No adapter errors — the payload is well-formed JSON, parses cleanly, and
simply contains one window instead of two. The threshold matches nothing and never fires again. There
is no event, no log line and no config warning, because «a window the platform stopped reporting» is
indistinguishable from «a window at 0%» in every design that enumerates what it is given.

**A second, sharper version for an implementer.** Anyone who wrote the adapter against the 471
`primary`=300 records — the obvious mapping `short = primary, weekly = secondary` — now reads a
**weekly** number and calls it the five-hour number, and reads `null` and calls it «no weekly window».
Both numbers are wrong and both are plausible. This is the same class of silent schema drift that
killed the previous generation's Anthropic parser (A6) — on the platform proposed as the fix for it.

**Also unexercised:** `rate_limit_reached_type`, which the research names as «a genuine in-band
limit-hit signal that needs no screen scraping», is `null` in **7,379 of 7,379** records
(**VERIFIED**), as is `spend_control_reached` — **7,379 of 7,379**. Neither signal's non-null shape has
ever been observed on this machine, over ten months and two plans. Building the hard stop on either
means shipping a code path that has never once run, and whose payload shape nobody has seen.

---

## A6 — «Unreadable» is not a case he ruled on, and the shipped default makes the whole limiter inert · major

**The decision.** Every mode in [171] assumes the number is there. There is no row in the transcript
about what happens when the reading fails. `extract/corrections.md` confirms the stop rule itself is
**unratified** — he asked «Повтори, будь ласка» [178] and the interviewer moved on after repeating.

**The hole, VERIFIED in the shipped source, today.** `plugins/harness/bin/harness-limits.sh:55-58`
refuses to call a response readable unless it contains a `.limits` array:

```bash
if printf '%s' "$j" | jq -e '.limits | type == "array"' >/dev/null 2>&1; then
```

The live endpoint has no `.limits`. Its top-level keys are `five_hour`, `seven_day`, twenty-odd named
buckets and `extra_usage` (**VERIFIED** in the research; today it returns `error`, see A3). So
`snapshot` returns `UNREADABLE` on **every** call, `verdict` returns
`VERDICT=UNKNOWN SESSION=? WEEKLY=?`, and then two things follow from the defaults in
`templates/user-config.example.json` (**VERIFIED**):

- `"on_unreadable": "proceed"` — `wait_clear` logs «proceeding per config» and **returns 0
  immediately**. The pause never happens.
- `"stop_at": null` — the opt-in hard stop is off by default. And even when it is set,
  `harness-run.sh:240` extracts it with `sed -n 's/.*SESSION=\([0-9]*\).*/\1/p'` against the literal
  string `SESSION=?`, which yields **empty**, so the `[ -n "$s" ]` guard fails and the hard stop
  **can never fire** while the parser is broken.

`FIELD-NOTES.md` §11.7 records the operational consequence **VERIFIED**: `weekly_all=unreadable%`
recurring «six consecutive ticks on `2026-09-06T03:01-03:19Z`, more at 08:36 and 22:48-23:03, single
ticks on the 9th, 10th and 11th», plus «The usage endpoint returned `authentication_error` for an
extended stretch, blinding every cap read, with nobody re-authenticating.» The limit machinery
described in his decisions ran for days, on a real project, doing nothing, reporting nothing wrong.

**Concrete failure on the rebuild.** The user sets a hard stop at 80% weekly and goes to bed,
believing the machine will stop itself. The provider ships an unannounced field rename at 02:00 — the
research documents Z.ai doing exactly this, `TOKENS_LIMIT` → `CREDIT_LIMIT`, with consumers rendering
**0% used** rather than «unreadable» (CLAIMED, §3.3, three corroborating reports). The adapter reads
0%, which is below every threshold. The run proceeds to exhaustion, and the morning log says the
threshold was checked all night and never crossed.

**And the recovery path built on this confusion has its own three-step history**, from
`FIELD-NOTES.md` §11.7 **VERIFIED**: the unreadable fallback «was pinned to a fixed past epoch, so an
unreadable read resumed a paused run immediately (#65)»; the fix made a restart read `STOP` as a
manual owner stop and exit (#73); and «a failed marker write leaves an unattributed `STOP` on disk
(#82, open)». Three regressions, all downstream of a case the decision set does not name.

**What is undefined.** Whether `unreadable` is one state or several (throttled, auth-expired,
schema-unknown, network — they want opposite responses); whether the answer differs per stop class;
and what the default is when the user configures nothing. The last one has a shipped answer today and
it is `proceed`.

---

## A7 — «зупинити завдання прямо вже» is not deliverable, and it destroys the state that justifies it · major

**The decision.**

> «то це означає хардстоп, що потрібно зупинити завдання прямо вже та й все» **[171]**

**The justification he gave for allowing a task to run into the wall in the first place:**

> «в нас в реєстрі має записуватись кожен стан, його виконання, що там як, куди, для того, щоби було
> відновити процес і продовжити, навіть руками, або просто продовжити після того, як ліміти
> онуляться» **[171]**

**The hole.** There is no channel by which a supervisor can tell a running session to stop
gracefully. `FIELD-NOTES.md` §1.3 and §1.4 measure this **VERIFIED**:

- «**five separate instructions typed into sessions were never delivered**»
- «a bare Enter (`harness-term.sh key <tty> enter`) does **not** submit text already sitting on the line»
- «`send <tty> "<text>"` types its own text and submits — so it **destroys** whatever was pending»
- «when a background task re-invokes the session, whatever sits on an idle input line is **discarded**»
- the engine's own stale-heartbeat nudge «does not submit stranded text» — measured twice, both times
  the text was still on the line afterwards

So «прямо вже» has exactly one reliable implementation: kill the process. And a kill throws away the
in-flight turn — the very thing [171] says the registry exists to preserve. The decision's premise and
its mechanism point in opposite directions.

**Concrete failure.** 02:55, hard stop crosses. The orchestrator kills an executor mid-turn. That
executor was 40 minutes into `docker compose up --build`; `FIELD-NOTES.md` §5.1 records **VERIFIED**
that two concurrent builds on this machine already `OOMKilled` the owner's own application container
(`<work-project>-app-1`, exit 137, `2026-09-13T03:29:01Z`). The kill leaves a half-built image, a
container the run did not stop because it did not know it owned it, and a worktree with staged
changes and no commit. At 11:00 the weekly window resets. The resume rule — «просто продовжити після
того, як ліміти онуляться» — restarts from the registry's last recorded state, which was written
before the turn that was killed. The work between the last checkpoint and the kill is gone, silently,
and the resumed session re-enters a dirty worktree.

**Nothing in the decision set says** what a hard stop does with an uncommitted worktree, a running
container, an open merge, or a subagent tree — nor whether «завдання» means the turn, the session, the
ticket or the lane.

**A smaller, related trap that will bite this very cluster.** The previous generation's limit-banner
detector is `grep -qiE 'limit reached|hit your (session|weekly) limit|rate limit'` against the last
~25 lines of a session's screen (`harness-run.sh:308`, **VERIFIED**). Any document *about* rate limits
— this one, or `C4-capacity-research.md` — displayed in an idle session matches it. `FIELD-NOTES.md`
§11.6 records what that costs **VERIFIED**: an **85-minute loop** where the watch «matched what looked
like a usage-cap banner inside the orchestrator's **own wrapped prose**», pressed Escape and sent
`continue` every ~60 seconds, «**Nothing internal detected it** — it ended when an external `SIGTERM`
reached the orchestrator», with `NO ONE IS BEING TOLD` in the log; plus a separate **45-minute**
false-positive loop on a healthy orchestrator. If screen-scraping returns as the degradation path for
the seven platforms with no quota API, it returns with this.

---

## A8 — «перед запуском переконатися» verifies at t0; the switch happens at t+9h on a token that expires · major

**The decision.**

> «при конфігурації треба буде, коли людина налаштовує цей оркестратор, чи перший раз запускає, треба
> явно пояснити, як саме може відбуватися зміна акаунтів. І для кожної платформи це окремо треба
> пояснювати.» **[199]**

> «перед запуском потрібно переконатися, що це працює, щоби це не було проблемою для користувача» **[199]**

**The collision, in his own words:**

> «просто продовжити після того, як ліміти онуляться» **[171]**

**The hole.** The verification is bound to «перед запуском». The account switch it verifies happens
whenever the run needs it — which, by [171]'s own design, is typically *after* a multi-hour wait for a
reset. Nothing says the check repeats, and every failure mode of a stored credential is time-dependent.

**VERIFIED on this machine.** A listed profile can have a keychain entry
(`Claude Code-credentials-<hash>`) that yields **no readable access token** at all — a listed,
configured, apparently-valid account that cannot authenticate. The research verified the adjacent
case: a profile returns `authentication_error` from the usage endpoint because its stored
OAuth token is stale, and tokens refresh only when Claude Code actually runs under that profile.
`FIELD-NOTES.md` §11.7 records the unattended version **VERIFIED**: «The usage endpoint returned
`authentication_error` for an extended stretch, blinding every cap read, with nobody
re-authenticating. `2026-09-02T13:52-15:14Z`.»

**Concrete failure.** 21:50, pre-run check: the executor role will run as `<profile-A>`, switching
verified, identity echoed, green. 01:30, weekly cap crossed on that account; the run enters the
intermediate mode — «записати теперішній стан … зупинити її повністю» [171] — and waits. 11:00 the
next day, the reset lands. The resume spawns an executor under `<profile-A>`. Its OAuth token expired
during the thirteen-hour idle. There is no human awake at 11:00 either; he is in a meeting. Nothing in
his decisions says whether the resume retries, falls back to another account (forbidden if that
account is role-restricted — see A9), holds and escalates, or exits. The machine has been idle for
nine and a half hours and is now idle indefinitely.

**A second, worse variant, already flagged in the research and not covered by any decision.** macOS
may raise a **GUI Keychain dialog** the first time a given account's credential is read by a new
binary. Unattended, at 04:00, that is a modal nobody dismisses. The pre-run check would have absorbed
that prompt at 21:50 for the *starting* account — and not for the standby it was never asked to touch.

**And the check cannot verify the thing that matters.** It can prove *identity* — this role will run
as this account. It cannot prove *headroom*, because an idle Claude Code account returns
`authentication_error` rather than a quota reading (§4.3, VERIFIED). A pre-run report that says
«account B is ready» is asserting something it did not measure.

---

## A9 — Role-restricted provider plus wait-for-reset is an undefined deadlock at 01:00 · major

**The decision.**

> «коли людина налаштовує провайдери, які використовують та акаунти, вона може вказувати, для чого
> вони можуть використовуватись. Наприклад, що може використовувати тільки для оркестратора, щось
> може використовуватись тільки для екзек'ютора … І це важливий дуже нюанс» **[270]**

**The collision, in his own words:**

> «потрібно чекати, коли воно розіб'ється, для того, коли воно розблокується, щоби продовжити всю
> роботу» **[007]**

**The hole.** [270] is a constraint on *which* accounts may serve a role. [007]/[171] say an exhausted
role waits for its reset. Put together, an account restricted to one role becomes a single point of
failure whose exhaustion halts everything, and neither row says whether the restriction is a hard
constraint or a preference.

**Concrete failure.** The owner marks one account (`<profile-A>`) «orchestrator only» — precisely the
«важливий дуже нюанс» he called out, to keep that identity out of executor traffic. 01:10, that
account crosses its weekly threshold. Its reset is **Sunday 11:59:59 UTC** — verified in the research's
live read of `seven_day.resets_at` as `2026-09-20T11:59:59Z` for his active pool, so a mid-week
crossing can be a **multi-day** wait, not a five-hour one. The executor accounts sit at 8%. The
restriction forbids promoting any of them. The rule says wait. The machine idles for up to six days
with 92% of its capacity unusable, and nobody is told, because waiting is the designed behaviour and
there is no event for «waiting longer than is sensible».

**What is undefined.** Whether an exhausted restricted role blocks the run or only itself; whether the
restriction may be relaxed when the alternative is a multi-day stall; whether there is a maximum wait
after which waiting becomes escalating; and — given [300]'s «не може бути такого, що вже якісь
існуючі оркестратор і спускається наступний» — whether a waiting orchestrator counts as alive for the
purposes of the no-second-orchestrator rule. A run that is «paused waiting for a reset» and a run
whose orchestrator is dead look identical from outside, and `FIELD-NOTES.md` §11.6 records a real
five-day, 1085-repetition loop over exactly that ambiguity: «`STOPPED` present with no `run.complete`
— treating as an accidental teardown, not a finish».

**Collides with:** [007]/[171] (his own), [300] (his own).

---

## A10 — «хард» in the watched file and «хардстоп» in the limits rule are the same word with different actions, and the file has no owner · major

**The decision.**

> «це має бути налаштовано через єдиний файл, який оркестратор чи контекст вочер постійно дивиться і
> перевіряє, чи там були якісь зміни» **[195]/[196]**

> «якщо в моменті щось змінюється, то вказується, який тип цієї зміни. Тобто, чи це софт, що це треба
> буде наступні завдання перенести, чи це хард, чи це треба прямо вже зробити і зупинити» **[195]/[196]**

**The collision, in his own words:**

> «хардстоп, що потрібно зупинити завдання прямо вже та й все» **[171]**

**The hole.** Two decisions, seven rows apart in the same session, use «хард … прямо вже … зупинити»
to mean two different things: *stop the run* (limits) and *apply this account reassignment
immediately* (the watched file). The second is a **switch**, not a stop — «зупинити» there is the
means, not the end. An implementer reading a config field named `hard` cannot tell from his words
which one is meant, and a user writing `hard` in the file cannot tell what he is asking for.

**Concrete failure.** 04:10. The owner, awake briefly, edits the assignment file from his phone to
move the executors off `<profile-B>` (he needs that account for a morning demo) and writes `hard`,
meaning «do it now, don't wait for the next ticket». Implementer A reads the limits vocabulary and
**stops the run** — he wakes to a halted machine and four hours lost. Implementer B kills three
executors mid-turn and respawns them on the new account — three worktrees left dirty per A7, and the
merge that was in flight half-done. Neither is wrong by his words.

**And the threshold that fires next is computed across two different pools.** `FIELD-NOTES.md` §12.4
records **VERIFIED**: «**A weekly-usage figure can move without any usage changing.** When the
supervisor was repointed from one account to another mid-run, the weekly reading fell from 26% to 6%
**from the account switch alone**.» So immediately after any account change, the run's own limit
history is discontinuous — a soft stop that was about to fire silently un-fires, and a trend line
computed over the boundary is meaningless. Nothing in [195]/[196] or [171] says a reading must carry
the account it was taken from, or that thresholds reset on a switch.

**And nobody owns the file.** «оркестратор **чи** контекст вочер» [195]/[196] is an unresolved
either/or — `extract/by-item.md` flags it — and it collides with [300]'s single-orchestrator
invariant. A `hard` change that means «stop now» needs an actor with authority to stop; a context
watcher does not obviously have it, and if both poll, both act. `FIELD-NOTES.md` §8 records what a
real mid-run account move actually cost **VERIFIED**: it «required editing `scripts/overnight-
supervisor.sh` in the same change, because that script watches the watched account by path in
`POOL_PROFILE` and would otherwise have watched an account nothing ran on» — i.e. the single watched
file was not in fact single, and the second place had to be edited by hand or the meter would point at
an idle account.

**A last undefined:** «Можливо, там, наприклад, по даті, перевіряти, коли він був змінний» [195] was a
hedge, and `extract/corrections.md` records that ANALYSIS-01 wrongly hardened it into «mtime named as
the mechanism». An editor that writes-and-renames, a `git checkout` that restores an old file with a
new mtime, or a partially written file read mid-save all defeat mtime — and a half-read assignment
file at 04:00 assigns a role to nothing.

---

## A11 — The meter reads an account the run is not spending on — reproducible today, twice, by two mechanisms · major

**The decision.**

> «Тобто, це може бути як зміна через те, щоб використовувати інший API ключ, або зміна те, що треба
> використовувати інший акаунт підписки … Наприклад, в моєму випадку це перемикач профілів, який використовує різні
> профілі.» **[199]**

**The hole.** His vocabulary for «a provider» has two slots — API key, or subscription account/profile.
On his machine a session's actual spend is determined by a third thing he never names, and by a
default he never chose.

**Mechanism 1 — the canonical keychain entry can belong to no profile. VERIFIED.** The active
`CLAUDE_CONFIG_DIR` in this very session is `~/.<switcher>/profiles/<profile>`. The canonical
keychain entry `Claude Code-credentials` — the one his global `CLAUDE.md` rate-limit recipe reads,
the one `harness-limits.sh` falls back to at line 35, and the one I used in A3 — held a token matching
**none of the switcher's profiles**, and `~/.claude.json` / `~/.claude/.claude.json` reported an
identity different from the active profile's.
`FIELD-NOTES.md` §11.7 records the cost of this **VERIFIED**: «my limits position was measuring the
wrong account», with «the building account reading 94% weekly on that wrong pool»,
`2026-09-04T15:54:41Z`.

**Mechanism 2 — the base URL. VERIFIED today.** `~/.config/claude-mimo/env` exists on this machine and
contains `export ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com/anthropic` with its own
`ANTHROPIC_AUTH_TOKEN` and a `mimo-v2.5-pro` model option. `harness-limits.sh`'s `token()` reads the
Anthropic OAuth token from the keychain and **never consults `ANTHROPIC_BASE_URL`** (VERIFIED — I read
the function). So a session pointed at MiMo spends MiMo's quota while the gate meters
`api.anthropic.com` for an account the session never touches.

**Concrete failure.** The owner assigns the executor role to the MiMo option to save Claude quota —
exactly the multi-provider move [036] describes. The run starts at 22:00. All night the spawn gate
reads 10% weekly on an Anthropic account nothing is spending, so it never pauses and never hard-stops;
it cannot, because that number cannot rise. MiMo's own quota runs out at 03:00. The only signal is a
banner in the executor's TUI, which routes into the screen-scraping path A7 shows produced two
multi-hour false-positive loops. The morning report says the limit gate ran all night and stayed
green.

**What is undefined.** Whether a «provider» is identified by binary, by credential, or by
*(binary, base URL, credential)*; and what the meter does when the answer is «the binary you know, the
endpoint you do not». On the second, the honest answer for MiMo today is **UNKNOWN** — its quota
surface has not been established by anyone, and reading Anthropic's endpoint for it returns a
confident wrong number rather than an error.

---

## A12 — Headroom for his own parallel work was never asked, and [370] makes it a red line he cannot hold · major

**The unasked question.** `questions.md` R1-06 has two halves. The interviewer asked the first and
never put the second:

> «**Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу?**»

`extract/corrections.md` confirms it: «Half of R1-06 was dropped by the interviewer. There is **no
answer anywhere in the transcript**.» Every threshold in this cluster is therefore a threshold against
*exhaustion*, and none is a threshold against *leaving him room*.

**Why this is not a nice-to-have — his own words, on the adjacent item:**

> «перший кейс це те, що наприклад, я працюю вклад коді, але я працюю з іншим, наприклад, іншою
> папкою, іншим проектом, то цей оркестратор, він цього не має трогати. Другий кейс, якщо, наприклад,
> в тій самій папці я паралельно працюю над чимось, це не запускав оркестратор, це роблю я, він цього
> не має зупиняти.» **[370]**

He states a hard non-interference rule between the run and his own parallel work. Quota is the **one**
resource where that isolation is physically impossible when the run and his session share an account —
and A1 shows that «different profile» does not guarantee «different account», so he may believe he is
isolated when he is not.

**Concrete failure, direction 1 (the run eats his morning).** The run works all night under his hard
stop at 80% weekly and behaves perfectly: it stops at 80%. He opens the laptop at 09:00 and has **20%
of a weekly window** to last until the reset — which the research verified as
`2026-09-20T11:59:59Z` for his pool, i.e. more than a day away on a Saturday. His own interactive
work, the thing the tool exists to make room for, is the thing the tool consumed. Nothing he decided
prevents this, because 80% was chosen as «how much the run may use», not «how much must be left».

**Concrete failure, direction 2 (his morning kills the run).** Reverse it. The run is at 65% and
healthy. He spends two hours on an unrelated project in the **same account** — permitted by [370],
which says the orchestrator must not touch his parallel work — and pushes the shared weekly to 82%.
The hard stop fires on a run that was doing nothing wrong, at a threshold computed from a number his
own typing moved. The run cannot distinguish its own consumption from his, because the quota endpoint
reports an account, not a process. He then sees a stopped run with no explanation that names him.

**What is undefined.** Whether a reserve exists at all; whether it is expressed as a floor (leave 20%)
or a ceiling (spend at most 60%); whether it is per-account; and what the tool does when *his* usage,
not the run's, crosses a threshold the run is judged by. His three-mode vocabulary has no word for
«this stop was not your fault».

---

## What this pass did not attack

Recorded so the gaps are visible rather than implied.

- **The three-way accounting rule** — «посилатися на облік тієї тулзи … або він веде свій облік … з
  посиланням, плюс тої дати, якої не вистачає» [171] — is attacked only obliquely. Worth one line
  here: for *quota*, the referenced tool has no accounting to reference. GSD records phases, plans and
  state; it does not record token spend or window position. So for this cluster the three-way rule
  collapses to «веде свій облік», and own accounting can report what was spent, never what remains.
- **The intermediate stop mode** is genuinely open by his own «Не знаю» [171]; attacking an
  acknowledged gap is not useful. The research's finding that it is gated by session-resume
  capability rather than by quota stands and is the right thing to put to him.
- **Whether this machinery should exist at v1 scale at all.** `FIELD-NOTES.md` §5.3 **VERIFIED**:
  across 34 hours the watched account reached **26%** of weekly, and «The dependency graph, not the
  quota, bounded throughput: of nineteen phases only two pairs could ever run concurrently.» Against
  «нічого надприроднього не потрібно вигадувати» [171], that is a question for him, not an attack, and
  the research already files it as open question 3.
