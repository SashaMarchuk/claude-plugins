# JUDGE-fidelity — how faithfully each design implements what the owner actually said

**Date:** 2026-09-19. **Axis:** fidelity to the owner's stated decisions, including the inconvenient
ones. **Verdict shape:** score 1–10, ranking, and — the part that matters more — the specific
mechanisms worth grafting from the losers into the winner.

**Sources of truth, in this order.** `round-1/TRANSCRIPT-01.md` (the owner's own words, read at the
row anchors), `round-1/ANALYSIS-01.md` (the requirements), `research/extract/corrections.md` (the
confidence grading on those requirements). Where the analysis and the transcript disagree, the
transcript wins; where a design cites a source, I opened it.

**Evidence tags.** **VERIFIED** — I read the row in `TRANSCRIPT-01.md` or the line in the design on
this machine today. **CLAIMED** — a design asserts it and I did not re-derive it. **INFERRED** — my
reasoning from the above.

**Two rules I judged against, taken from the brief.**

1. A decision of his that a design implements while recording the discomfort scores well. A decision
   of his that a design replaces with something better, quietly, scores badly. A decision replaced
   *loudly* sits in between, and where it sits depends on whether the loudness is in a tension
   register the owner will actually read or buried in a paragraph.
2. Everything he made configurable stays configurable, and every configurable thing needs a stated
   default. I checked each design's default register against its own body, not just against itself.

---

## 0. The scoreboard

| Rank | Design | Fidelity | One-line reason |
|---|---|---|---|
| 1 | `ARCH-minimal` | **8 / 10** | Recovers owner intent the analysis dropped; every deviation is in a register he can read in five minutes. Its one big deletion of stated configurability is the largest in the set and it says so. |
| 2 | `ARCH-reliability` | **7 / 10** | The only design that carries `corrections.md`'s unratified grading into its own open list. Three defaults outrank his words; each is flagged, one is mischaracterised as within his shape. |
| 3 | `ARCH-adapters` | **6 / 10** | Best preservation of "everything stays configurable". Loses points for one checkable miscitation used to justify a stricter-than-stated default, one unflagged brake, and a missed assignment. |
| 4 | `ARCH-operability` | **5 / 10** | The most literal reading of [204] in the set, and the only design that silently drops a value from an enumeration he stated out loud. Thinnest grounding in his words; least complete default register. |

---

## 1. ARCH-minimal — 8 / 10

### What it gets right, with his words

**It recovered a constraint the analysis lost.** Four separate times, in four different items, he
asked for the least machinery that works — «тут нічого надприроднього не потрібно вигадувати» [171],
«це має бути дуже простий процес» [189], «це має бути надійна річ, дуже проста» [300], «я не хочу
якихось детерміністського варіанту … він буде дуже складний оверінжиринг, але дуже якісь простий та
надійний варіант» [370] (all four VERIFIED in the transcript). `ANALYSIS-01.md` carries only the
last. No other design treats the other three as binding. This is the single strongest fidelity act
in the set: it is the only place where a design went back to what he said and found something the
requirements document had dropped, rather than elaborating on what the requirements document kept.

**It discharges an assignment he actually gave.** [146]: «має бути конкретна структура, якимись або
тегами, або що, які потрібно фоловити … це треба буде, щоби придумав якусь структуру, і її
притримувався». Minimal §4 delivers one at grep size and defaults it to
`tickets.ready_requires: ["Outcome","Acceptance","Scope"]`, measured over 327 real tickets. Two of
the other three never deliver it (§3, §4 below).

**R1-15 is implemented literally, which is the uncomfortable reading.** [357]: «На окремо якогось
обов'язкової процедури для цього не треба … технічні обмеження середовища користувач за потреби
налаштовує сам». Minimal's `session.permissions: inherit` is the plugin abstaining entirely — no
hook, no deny list, no sandbox, no permission wrapper — and it is a direct correction of the shipped
`--dangerously-skip-permissions` default. §14.5 then states plainly what that costs: a flat prose
file has no field separating an absolute from a preference, and nothing writable in it would have
stopped Playwright's `--trace on` printing two passwords into a transcript. Design for the decision;
price it; do not add the machinery. That is the pattern the brief asks for.

**Д5's default is one of the two he offered.** [442]: «якщо налаштоване канал комунікації, то дати
знати про це, зупинитись, або просто зупинитись». `failures.action: notify_and_stop`. No third
option invented.

**Д4's default is his.** [433] «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк
трі» → `worktree.enabled: true`, `base_ref` = the default branch. And §14.10 refuses to pretend the
GSD collision is solved: «з цим треба поєднювати» is recorded as *an assignment he gave, not a
decision he made*, which is exactly what row [433] is.

**His stop verbs survive as he named them.** [524] «stop-hard, stop-soft, stop-custom». §2.2 splits
the file's representation into `verb`/`scope`/`apply` because his own «хард»/«софт» carries three
granularities and two opposite post-conditions across [171], [195] and [204] — and then keeps the CLI
names unchanged so the vocabulary he speaks is untouched. The tension is §14.2, not a footnote.

**Quote hygiene.** It quotes Д11 as «мінімальну кількість аутпуту і стокінгів» [512] — including the
voice-garbled word — rather than tidying it. VERIFIED against row [512]. Two of the four tidy or
truncate this row.

### Where it costs him something he said

**The largest single deletion of stated configurability in the set.** [204] gives him a choice about
the orchestrator itself: «оркестратор можна як компактити, так і запускати повністю новий
оркестратор, що також може бути окей, і людина може це налаштовувати». And [204] again: «якщо в мене
є Клод Код, і допустимо, три вікна, перше, це контекст вочер, друге, це оркестратор, третє, це
екзек'ютор, то я для кожного з них можу вказати, який буде поріг компакту, і як саме компакт повинен
відбуватися». Minimal deletes the orchestrator as a session, so both options and two of the three
per-role compaction settings have nothing to attach to. §14.1 states this openly and buys something
real with it (R1-08's hardest case stops existing). But a configurable he named twice, in the same
answer, is gone rather than defaulted — and the brief's second rule is that configurables stay
configurable. This is graft #2 below.

**R1-11 is demoted, by its own admission.** [324] asks for per-platform choice between interactive,
headless, hybrid and mostly-interactive. Minimal is headless-first with `attach: true` as an
exception and takeover as a paid handoff, and §15.1 calls it "the largest single deviation from a
decision he confirmed ([328])". Honest, and still a deviation on a ratified item — [328] «Так,
підтверджую» is in `corrections.md`'s ratified column (VERIFIED).

**The board stops being his «помічник».** [149]: «це має бути якась дошка, яка буде помічником для
цього оркестратора, щоби ставити статуси таскам, залишати якісь коментарі». Minimal makes the board
a best-effort mirror and, on the local registry, never writes into a ticket at all. §14.6 records it.
The hazard it is avoiding (C3-A1, the tool's own write firing its own detector) is real — but minimal
already ships the fix for that hazard in §2.4 (self-write suppression by content hash), so the
demotion is paid for twice. Graft #7.

**No engagement with the confidence grading.** Zero occurrences of "unratified" in 1,139 lines
(VERIFIED by grep). §2.2 rebuilds the entire control vocabulary on R1-06's hard/soft rule, which
`corrections.md` §C records as never ratified — the restatement at [176]/[177] was answered with
«Повтори, будь ласка» and the interviewer moved on. Graft #1.

**Smaller.** [118] names YAML («може налаштовуватись з допомогою якогось ямл файлу», hedged); minimal
uses JSON throughout and says "no YAML schema beyond an array". 19 `DEFAULT-PROPOSED` markers, and
its §13 register omits keys its own body uses (`custom.timeout_s` from §9.1, `judge.model` resolved by
reference rather than by value).

### Justification for 8

Minimal is the only design that treated the transcript as more authoritative than the analysis and
came back with something the analysis had lost. Every deviation it makes is in a numbered register
(§14, eleven items; §15, three sections) written for the owner to overturn, and several of its
defaults are literally his numbers. It loses two points for deleting a configurable he named twice in
one breath, and for taking every requirement's confidence grade on faith.

---

## 2. ARCH-reliability — 7 / 10

### What it gets right

**It is the only design that knows which of his decisions are actually confirmed.** §17.5 item 8:
"The 22 unratified restatements in `corrections.md` §C, several of which this design leans on hard —
the soft/hard stop vocabulary (R1-06), the per-platform account-switch verification (R1-07), the
every-task-in-a-worktree default (Д4), and Д12 itself." Fourteen citations of `corrections.md`
(VERIFIED by grep; minimal has 3, adapters 2, operability 1). On a fidelity axis this is worth more
than any mechanism, because it is the only thing in the set that distinguishes *what he said* from
*what the interviewer said and he did not deny*.

**It reconciles two of his statements that collide, without dropping either.** [204] wants the
orchestrator replaceable («запускати повністю новий оркестратор»); [300]/[301] forbids two
orchestrators absolutely («якщо раптом одночасно два якісь оркестратори працюють, то це не окей … Це
треба відслідковувати і не дозволяти»). I2 makes the singular thing the conductor — which has no
context to compact — and the `handover` run state keeps dispatching while the judging agent is
replaced. Both of his sentences survive intact. Best structural fidelity move in the set.

**`run.mode: ask` matches his enumeration.** [075] names three values and describes the mechanics of
the first: «Перше, це кожного разу запитуватись … перед кожним раном треба … задати питання юзеру».
Reliability defaults to `ask` and adds `run.mode_on_takeover: controlled` for the case [075] cannot
cover (C1-A5: nobody to ask at 04:00), listing it in §17.5 for his ruling.

**It refuses to harden a hedge.** [118] on YAML is hedged in the same breath («Можливо, не так, тут
треба буде подумати, як саме»). §7.3 accepts YAML or JSON and states that neither is claimed as his
choice. §3.2 rule 4 does the same for [195]'s mtime («Можливо, там, наприклад, по даті»), citing
`corrections.md` for the fact that the analysis hardened it.

**§17 is the best "impossible as stated" section in the set** — four items, each naming the exact
clause that fails and pricing what keeping it costs, in his own quoted words.

**41 `DEFAULT-PROPOSED` rows in one reviewable table** with an apply-class per key. The most complete
register of the four.

### Where it quietly outranks him

**Д5's default is an option he did not offer, presented as one he did.** [442] gives exactly two
actions and closes the set: «дати знати про це, зупинитись, або просто зупинитись» — and the owner's
boundary, per `ANALYSIS-01` Д5, is that deciding anything beyond that needs his permission.
Reliability defaults `failure.on_exhausted: park` — tombstone the ticket, *keep the run going* —
which is neither of his two, and its own tension note calls it "within the shape he allowed". It is
not within that shape; it is a third behaviour. The tension is flagged, the characterisation is
wrong, and the default ships as the non-his one. **This is the clearest instance in the set of a
decision being improved on while being described as honoured.**

**Д4's default flips to its opposite in his primary case.** [433]: «Дефолтна пропозиція, щоби
абсолютно все виконувати в різних ворк трі». `worktree.policy` defaults to `engine` "when the engine
claims ownership" — and GSD claims ownership, and GSD is the engine he names most often. So in the
case he will actually run, the shipped default is not his stated default. Flagged at §7.2 with the
C9-A2 evidence, but the flag does not change which value ships.

**`orphan_reclaim: same_tool_confirm` is a self-declared widening shipped as the default.** §12.4:
"it is a widening and he did not authorise one." The `off` value exists and is described as "strictly
his rule". A widening he did not authorise belongs behind a flag, not in front of one.

**`limits.max_concurrent_builds: 1` reintroduces a sliver of what he retracted.** [160] → [163]:
«ресурси машини, поки це заберемо, це добавимо в майбутнє … це от останнє про сто завдань, це
забери». §5.3 argues it is "a declared-cost queue, not resource awareness" and offers `0` to disable.
Defensible, disclosed, and still a scheduler constraint on the axis he removed.

**R1-04's assignment is pushed away rather than discharged.** §7.1: `readiness` is "the engine
decides what 'ready' means (R1-04 [145]); the orchestrator never invents it." But [146] asks the
orchestrator to have a structure and follow it — «це треба буде, щоби придумав якусь структуру, і її
притримувався» — and under `engine.kind: custom` this design leaves the owner to invent it himself.
The assignment is inverted, not delegated.

### Justification for 7

It is the most honest design in the set about *what grade of evidence each requirement carries*, and
its two hardest reconciliations (I2, §17) keep his words whole where other designs pick a side. It
loses three points because three of its shipped defaults are not his values on items where he stated
one, and because one of those three is described as being within his shape when the transcript row
says it is not.

---

## 3. ARCH-adapters — 6 / 10

### What it gets right

**The best implementation of "everything he made configurable stays configurable."** This is the
design's real fidelity achievement and it is structural, not rhetorical:

- **§4.4 `probes.json` — liveness, identity and capacity probes as data.** [310]: «для кожної
  платформи можна налаштовувати, як саме буде робитись відновлення … Можливо, там використання
  якогось скіла». [312]: «людина це може налаштовувати, може написати свої власні [с]кіли». A probe
  is a JSON object with `cmd`, `env_from`, `match`, `alive_when`, so an owner-written skill is a legal
  probe and a platform nobody has installed costs one config entry rather than a code change. No other
  design turns these two rows into a mechanism.
- **§4.1 adapter discovery on a four-level path that mirrors his own config ranking** (personal ›
  project-committed › shipped), resolving `<config-root>` exactly as OWNER-DECISIONS 3.3 requires.
- **§5.1 `requirements.json`, where every row carries `owner_item`.** Each capability requirement is
  traceable to R1-06, R1-08, R1-11, Д12, R1-15 by name, and `negotiate.on_unknown: impossible` means a
  new requirement cannot silently pass on an old adapter.
- **§5.3 `plan.json` with `weakened[]` and `denied[]`** — a file naming which of his items got weaker,
  on which lane, from what to what, with the consequence, readable at any hour with no model.

**§9.3 EN-1 makes [118]'s «комбінувати ні, тут або або» mechanical** and then pre-empts the obvious
lawyer's objection out loud: the orchestrator's own steps are not a second process, "if they were an
engine, R1-03 would forbid the plugin from existing."

**Д4's default is his, with the price named and the choice returned to him.** §9.6:
`worktree.owner: orchestrator` (his [433] default), GSD `use_worktrees: false`, "costs GSD's
intra-phase parallelism … There is no configuration that gives both his uniform default and GSD's
parallelism today, and the choice is his." That is the correct handling of a collision between one of
his decisions and a fact.

**§9.4 keeps R1-11's answering requirement alive against a field that is closing the door**, by
injecting an `ask_supervisor` MCP tool rather than accepting the platform's refusal. [324] «оркестратор
може відповідати на ці питання, і це повністю і повністю окей» is preserved as a capability instead of
being recorded as impossible.

**§19 ends tensions with an instruction to ask him** — "Ask him." — rather than with a resolution.

**§17 is the strictest defaults contract in the set:** ~40 rows with `scope`, `apply` and
protects-against, headed by "This table is the contract; **nothing outside it may invent a default at
runtime.**"

### Where it replaces him

**One miscitation, used to justify going stricter than his words. This is the sharpest fidelity
defect I found in any of the four.** §9.4 states:

> "The owner said *"повністю і повністю окей"* with no condition at [324]; the *"в межах налаштованих
> повноважень"* qualifier at [325] was **the interviewer's phrase, not his** (VERIFIED,
> `extract/corrections.md`)."

Checked against both sources. [325] is indeed the interviewer's restatement — but at [328] the owner
answered «Так, підтверджую, переходимо до наступного питання», and `corrections.md` lists [328] by row
number in its "Ratified for contrast (owner's own yes, verbatim)" line (both VERIFIED). R1-11 does not
appear anywhere in `corrections.md`'s unratified table. So the qualifier is ratified, the cited source
does not say what it is claimed to say, and the false claim is used in exactly one direction: to
justify `questions.authority: refuse-and-escalate`, a default stricter than [324].

The irony is that the default is fine — the ratified qualifier *authorises* bounded authority, so the
design could have grounded it in his own confirmed words. The problem is the mechanism: a "VERIFIED"
tag on a claim the source does not support is precisely how an owner decision gets replaced without
anyone noticing, and a fidelity judge that lets it pass is not doing its job.

**A second quote is normalised and presented as verbatim.** Line 126 quotes Д11 as «мінімальна
кількість токенів» [512]. Row [512] reads «мінімальну кількість аутпуту і стокінгів» (VERIFIED). The
reading is almost certainly right — "стокінгів" is voice noise — but the design does not say it is a
reconstruction, and `ARCH-minimal` quotes the same row correctly.

**A brake he did not ask for, shipped as a default and flagged nowhere.** §17: `intake: capped` at 10
started per run. His Д2 answer at [422] is unconditional — «якщо під час запуску я добавляю якесь
завдання, яке тегується … AI бере це завдання, і виконує» — and he never mentioned volume. The
"protects against" column cites the 236 → 327 queue growth, which is a real incident, but the cap is
not in §19's tension list and it is not described as a widening. (Compare `ARCH-minimal`, which uses a
*notification* at queue growth 50 and leaves `max_claims_per_run: 0` unbounded, explicitly "his
behaviour": the same evidence, without changing what he said.)

**R1-04's assignment is never discharged.** "Readiness floor" appears once, in the release rule (§8.2),
as something that "still passes". The structure he asked for at [146] is never defined.

**R1-15 gets teeth it is told it does not need, twice.** `redlines.enforce: false` is offered and
correctly labelled as "precisely the *окрема обов'язкова процедура* he said was unnecessary" — that is
fine, it is off. But §11 also makes a *mandatory* worktree plus "a static deny list for destructive
commands" on sandboxless lanes (Kimi, pi). A mandatory deny list is enforcement machinery in a subset
case; it is raised as a question, but it ships.

**§19.2 admits the design will refuse to start for reasons he never asked about**, which trades an
unattended night against an honest refusal — a defensible trade, disclosed, and still friction on a
man whose stated ideal is a thing that outputs nothing and asks him nothing.

### Justification for 6

On the second half of the brief — configurables stay configurable, each with a stated default — this
is the best design in the set, and `probes.json`, `plan.json.weakened[]` and the §17 contract are the
mechanisms most worth taking. It scores 6 rather than 8 because a fidelity axis has to weight a false
evidential claim heavily when that claim is the sole stated justification for overriding a confirmed
decision, and because one unflagged default brake plus one undelivered assignment mean the "nothing
outside the table invents a default" discipline is not applied to the requirements themselves.

---

## 4. ARCH-operability — 5 / 10

### What it gets right

**The most literal reading of [204] anywhere in the set.** §2.2: `brain_mode: resident | ephemeral`,
"the owner already named both at [204] («як компактити, так і запускати повністю новий
оркестратор»)". Where minimal deletes the choice and reliability and adapters each pick one shape,
operability turns his own two options into a config key and prices both. On the axis of "everything he
made configurable stays configurable", this single row is the best example in the four documents.

**It discharges R1-04's assignment and then makes it operational.** §6.2 defines the readiness floor
concretely and re-checks it "on **every** transition including release, not once at creation — that is
what «її притримувався» [146] means operationally." That last clause is a correct and non-obvious
reading of his verb.

**§16.4 is the only place any design confronts the Д11 / R1-17 collision head on.** Proving a
notification channel works (R1-17 [395] «повинен лише переконатися, що це працює») requires sending a
real message, which is output he did not ask for (Д11 [508]). The resolution stays inside his words —
terminal silence is absolute, a channel he chose is not a terminal — and
`notifications.probe_message: false` lets him turn off even that, with the downgrade recorded.

**§16.6 surfaces a distinction that was never put to him and refuses to hide the assumption.** R1-13
gives verification to the process; nobody asked whether that covers the orchestrator's *own* merge.
The design assumes yes, says it assumes yes, and routes it to round 2.

**Д4's default is his** (`worktree_owner: orchestrator`, "because Д4 is his stated default").

**§17.3 is the most self-critical weakest-point section of the four** — it names the exact shape of
its own quiet failure and asks for an adversarial pass on the predicate list before a line is written.

### Where it replaces him

**It silently drops a value from an enumeration he stated out loud. This is the only instance in the
set of a settled configurable losing a value with no note anywhere.** [075] is explicit:
«там будуть три варіанти. Перше, це кожного разу запитуватись. Друге, це постійно автономний. Третє,
це постійно контрольований. І якщо постійно запитувати, то перед кожним раном треба … задати питання
юзеру» (VERIFIED). `control.yaml` §3.3 ships `mode: autonomous # autonomous | controlled`. I grepped
the whole document for `ask` as a run-mode value, for `run.mode`, and for "ask before every run": no
occurrences (VERIFIED). The value is not deferred, not flagged in §16, and not in §15. `ANALYSIS-01`
records it as SETTLED.

**The defaults register is the least complete relative to its own body**, which is the brief's second
requirement. Keys that appear in `control.yaml` §3.3 with a value and never appear in §15 with a
justification: `mode` (the run mode itself — and the sample ships the more permissive `autonomous`),
`behaviour.when_only_human_blocked`, `behaviour.on_contradicting_change` (Д9's whole four-way choice),
and the `custom_stops` shape. Compare adapters, whose §17 opens by forbidding exactly this.

**Thinnest grounding in his words.** 651 Ukrainian characters against ~1,300 in minimal and
reliability (VERIFIED by grep), and one citation of `corrections.md`. Several owner items are argued
from FIELD-NOTES and the cluster research rather than from what he said — which is good engineering
and is not what this axis measures.

**It adds a product surface he never requested.** `NEXT-RUN.md`, `tuning.patch.yaml`,
`/orchestrator:report`, `/orchestrator:ask`, the detector scorecard. §0 is honest that the morning
artifact is "one the brief adds" rather than his. But `config --apply-tuning` edges into the one
place where he *did* ask for a learning loop — [062] «якщо це не підходить, то треба вчити» — and
tunes thresholds rather than the decision basis, without connecting the two. Adding the wrong half of
a thing he asked for, under a heading that does not mention he asked for it, is a fidelity cost even
when the thing is good.

**`lanes.max: 1`** is below his own observed practice and below every other design's default; the
justification (his container OOM-killed by two parallel builds) is real, and the value is still the
most conservative reading of «людина сама може визначати, яка кількість завдань може одночасно
робитися» [163].

### Justification for 5

It contains the single most faithful mechanism in the set (`brain_mode`) and the only honest
resolution of the Д11/R1-17 collision, and it is the only design to silently lose a value from an
enumeration he spelled out in three ordered sentences. Those two facts are the whole score. It is a
strong design being judged on a narrow axis: its lens is the operator's experience, and it optimised
that experience using research rather than using his transcript.

---

## 5. Cross-cutting checks the brief asked for

### 5.1 Does every configurable thing have a stated default?

| Design | Register | Complete against its own body? | Contractual? |
|---|---|---|---|
| `ARCH-minimal` | §13, 28 rows, protects-against | **Nearly** — misses `custom.timeout_s` (§9.1), resolves `judge.model` by reference | No |
| `ARCH-reliability` | §15, 38 rows, + apply-class | **Nearly** — `behaviour.when_only_human_blocked` is defaulted in §7.5 and absent from §15 | No |
| `ARCH-adapters` | §17, ~40 rows, + scope + apply | **Yes** | **Yes** — "nothing outside it may invent a default at runtime" |
| `ARCH-operability` | §15, ~26 rows | **No** — `mode`, `when_only_human_blocked`, `on_contradicting_change`, `custom_stops` missing | No |

### 5.2 Are the defaults defensible?

Mostly yes, and every one of the four states what its defaults protect against. Four are not
defensible as his:

1. `ARCH-reliability` `failure.on_exhausted: park` — a third option on an item where [442] closed the
   set at two and reserved the rest to him.
2. `ARCH-reliability` `worktree.policy: engine` — the opposite of [433]'s stated default in his
   primary engine's case.
3. `ARCH-reliability` `orphan_reclaim: same_tool_confirm` — a self-declared widening shipped in front
   of the flag rather than behind it.
4. `ARCH-adapters` `intake: capped` at 10 — a brake on Д2's unconditional pickup, in no tension list.

Two defaults are better than his and correctly labelled as proposals rather than as his decisions,
which is the right handling: `capacity.on_unknown: hold_dispatch` (all four; reverses the shipped
`proceed` that made the limiter provably inert) and `context` thresholds restated on the raw scale
(all four; C5-A2's ~13-point gap).

### 5.3 One configurable that all four lose

[204], VERIFIED: «Людина це налаштовує, і обирає, чи відправляється якийсь промпт одразу після
компакту, чи ні». None of the four exposes this as a key. `ARCH-reliability`, `ARCH-adapters` and
`ARCH-operability` each hard-wire a post-compaction red-line re-injection — which is a post-compact
prompt, fixed, and a good idea — and `ARCH-minimal` has nothing at all, because it has no resident
session to compact. The build needs `context.post_compact_prompt` (DEFAULT-PROPOSED: the red-line
re-injection, which is the behaviour the evidence supports; `null` to disable), and the owner needs to
be told this is his key, not the plugin's behaviour.

### 5.4 One assignment two designs never discharge

[146]: the readiness structure. Delivered concretely by `ARCH-minimal` (§4) and `ARCH-operability`
(§6.2). Pushed to the engine with "the orchestrator never invents it" by `ARCH-reliability` (§7.1),
which inverts the sentence. Never defined by `ARCH-adapters`.

---

## 6. Grafts — what to take from the losers into `ARCH-minimal`

Each names the file, the mechanism and the reason it beats the winner's version. Ordered by fidelity
value, not by effort.

### G1. A confidence-grade register keyed to `corrections.md` §C
**From:** `ARCH-reliability` §17.5 item 8.
**Into:** a new `ARCH-minimal` §16, next to §14's tension register.
**Mechanism:** one row per requirement the design depends on, carrying its ratification status —
ratified with the owner's verbatim yes and its row, or unratified with the restatement that was never
answered. Gate the build order on it: nothing whose vocabulary is unratified gets built before round 2
re-confirms it.
**Why it beats minimal's version:** minimal has no version. Zero occurrences of "unratified" in 1,139
lines, while §2.2 — the control-file protocol that carries stops, account changes and behaviour
overrides — is built entirely on R1-06's hard/soft rule, whose restatement at [176]/[177] was answered
with «Повтори, будь ласка» and never re-put. Reliability names four of its own load-bearing pieces as
resting on nothing. Minimal's tension register asks "is this decision comfortable?"; this asks "is
this a decision?"

### G2. `brain_mode: resident | ephemeral`, as `judge.mode`
**From:** `ARCH-operability` §2.2 (the mode), with the arithmetic in §14.1.
**Into:** `ARCH-minimal` §5.4 and §13.
**Mechanism:** `judge.mode: oneshot | resident` (DEFAULT-PROPOSED `oneshot`, minimal's current
stateless `-p` call). `resident` keeps one long-lived judge session that the supervisor wakes over the
adapter's `send` channel, subject to the same `roles.orchestrator` context threshold and the same
`decisions.ndjson` recording; on threshold it takes minimal's existing close-and-reseed path.
**Why it beats minimal's version:** [204] gives the owner a choice — compact the orchestrator, or
launch a completely new one — and minimal's architecture removes the object the choice applies to.
This restores it as a switch rather than as a rebuild, keeps `oneshot` as the default so minimal's
central bet is unchanged, and closes the gap minimal itself names in §15.1 ("the judge has no memory …
cross-ticket pattern recognition exists only where the renderer includes it"). Operability's version
is the one to copy because it already prices both shapes and defines the wake channel.

### G3. `trips/<sha>.json`, written `O_EXCL` before the wake
**From:** `ARCH-operability` §2.2 ("Idempotency"), generalised from C5's watermark rule.
**Into:** `ARCH-minimal` §3.3 tick steps 5 and 6.
**Mechanism:** every predicate firing produces `trip_key = (predicate, subject, epoch, armed_at)`,
created exclusively on disk *before* the action. A trip already present does not re-fire.
**Why it beats minimal's version:** minimal caps the judge at `max_calls_per_hour: 30`, which bounds
spend but permits thirty identical re-fires of the same detector on its own effect — which is the
mechanism of the 85-minute loop, not its volume. A ceiling answers "how much"; a watermark answers
"again?". Minimal already has self-write suppression for *files* (§2.4); this is the same rule for
*detectors*, and it is four lines.

### G4. `probes.json` — liveness, identity and capacity probes as data
**From:** `ARCH-adapters` §4.4.
**Into:** `ARCH-minimal` §7.1, as a seventh file beside the six shell scripts.
**Mechanism:** a JSON object per probe carrying `cmd`, `env_from`, `match`, `alive_when`,
`status_field`, `timeout_s`. The supervisor executes it; it never contains platform knowledge itself.
An owner-written skill is a legal probe: `{"cmd":["claude","-p","/my-recovery-skill"], …}`.
**Why it beats minimal's version:** [310] and [312] are two rows the owner spent on exactly this —
per-platform recovery configured separately, and «може написати свої власні [с]кіли». Minimal's
liveness is hard-coded in `orch-run.sh` as pid + start-time + event-file growth, which is a good
default and is the one place his per-platform configurability cannot reach. Data-shaped probes make a
new platform one config entry instead of a code change, and they compose with minimal's fact sheet
without touching the tick loop.

### G5. `plan.json` with `weakened[]` and `denied[]`, each row carrying `owner_item`
**From:** `ARCH-adapters` §5.3, with `requirements.json` §5.1 behind it.
**Into:** `ARCH-minimal` §11.1's preflight output and §2.3's `status.json`.
**Mechanism:** preflight writes an immutable record naming, per lane, which owner item got weaker,
on which capability axis, from what to what, and with what consequence — then prints it at start and
carries it in `status.json`.
**Why it beats minimal's version:** minimal's §7.2 is binary — a missing capability is a loud refusal.
But almost every one of his decisions is "configure it per platform", which makes *partial*
degradation the normal case, not the exception. A binary gate forces either a refusal he did not ask
for or a silent acceptance, and minimal's §15.1 already concedes several places where it degrades
quietly (attach-as-exception, board staleness). Naming the degradation against the owner's item number
is the cheapest possible honesty and costs one JSON file.

### G6. The defaults table as a contract, with `scope` and `apply` columns
**From:** `ARCH-adapters` §17, including its opening sentence.
**Into:** `ARCH-minimal` §13.
**Mechanism:** add `scope` (user / project / run) and `apply` (live / boundary / frozen) columns —
minimal already computes the apply class in §8.2 but does not put it in the register — and adopt the
rule verbatim: *nothing outside this table may invent a default at runtime*, enforced by a test.
**Why it beats minimal's version:** the brief's second requirement is that every configurable has a
stated default, and adapters is the only design that makes the register a contract rather than a
summary. It also closes minimal's own leaks (`custom.timeout_s`, `judge.model`), and the `scope`
column is where Д1's [416] deferral to his marketplace becomes checkable per key rather than per
document.

### G7. Board write-back restored, with `board_readback` as the only admissible evidence
**From:** `ARCH-reliability` §4.3 (`self_write_digest` + readback evidence) and §7.1's five-role
mapping with a preflight refusal on an unmapped required role.
**Into:** `ARCH-minimal` §4, replacing the "the orchestrator never writes into a work item's own body"
rule and `board.writeback: false` for the local registry.
**Mechanism:** every board or ticket write is an operation whose only admissible evidence is the item
re-fetched and the field compared; the post-write digest is recorded and the change detector ignores a
change whose digest it produced.
**Why it beats minimal's version:** [149] is ratified — «це має бути якась дошка, яка буде помічником
для цього оркестратора, щоби ставити статуси таскам, залишати якісь коментарі» — and minimal gives it
up to avoid C3-A1, the self-write loop. But minimal already ships the fix for C3-A1 in §2.4
(self-write suppression by content hash). The decision is therefore paid for twice: once in §2.4 and
again in §14.6. Reliability's readback rule adds the second half — that a 200 is not evidence a
transition applied — which is the part minimal's mirror model was implicitly relying on the board to
provide. Restoring write-back costs four lines of existing mechanism and returns a confirmed decision.

### G8. The three-tier change detector, with the scout on the diff only
**From:** `ARCH-operability` §6.4 and §2.4.
**Into:** `ARCH-minimal` §3.3 tick step 4, with a `roles.scout` pin distinct from `roles.watcher`.
**Mechanism:** tier 0, did anything change (`If-None-Match` → 304, zero quota; `stat` + sha for a
local file); tier 1, was it the body or just a comment (`lastEditedAt` / body sha against the
watermark taken at claim); tier 2 only then, and only the textual diff, on the cheapest configured
model.
**Why it beats minimal's version:** Д8 [466] is unusually specific for this interview — «немає сенсу
перевіряти фейбл моделю … чи змінився якийсь тікет … можливо, є сенс запускати слабшу модель,
сабагента … і в нормальному рані, якщо нічого не змінилось, то цей агент просто, типу, нічого назад
не поверне». Minimal does the `stat` and then hands the result to the same judge on the same model
pin; it has no separate cheap watcher role and no diff-only input. Operability's tiering makes the
silence structural (no model is invoked at all) rather than behavioural, which is the stronger reading
of «нічого назад не поверне», and its measured spread (~$14 → ~$0.01 a night) is the cost-awareness
he asked for at Д11.

### G9. `control.ack.json` — the supervisor's reply to a command
**From:** `ARCH-operability` §3.3, with `ARCH-reliability` §10.2's polling exit code as the weaker
alternative.
**Into:** `ARCH-minimal` §9, alongside `control.applied.ndjson`.
**Mechanism:** the supervisor writes `{read_at, doc_sha256, epoch, applied[], deferred[{key,until}],
rejected[{key,reason}], parse}` after each control read; `orchestrator:stop` and
`orchestrator:set` read it to report whether the change landed, was deferred to a boundary, or was
refused as frozen.
**Why it beats minimal's version:** minimal's stop command prints "written to control.json (c-0012);
applied within 60s" — a promise, not an observation. FIELD-NOTES §11.2 records two real operator
instructions recorded as delivered and never executed. Д12's whole mechanism is his: the command
writes the file, the tick reads it — and the missing half is the acknowledgement that closes the loop
back to him. Operability's file is the better of the two because it also carries `deferred` and
`rejected` per key, which is where minimal's §8.2 Frozen class currently reports into nothing.

### G10. `context.basis` as a required key, set against a number he can see
**From:** `ARCH-reliability` §6.2.
**Into:** `ARCH-minimal` §5.2 and its `orchestrator:config` verb.
**Mechanism:** `context.basis ∈ raw_window | usable_after_reserve | statusline`, required rather than
inferred, and the config verb prints both numbers for a live session at the moment he sets the
threshold.
**Why it beats minimal's version:** [204] gives him the percentage — «Людина може налаштувати, при
скількох відсотках відбувається компакт». Minimal handles C5-A2's ~13-point gap by *naming* the key
`context.raw_pct_threshold` and printing both numbers in `status.json`, which is a good convention and
still asks him to pick a number on a scale he has never read — his status line has shown him the other
one all year. Reliability makes the scale an explicit choice and shows him both at the moment of
choosing, which is the difference between a naming convention and an informed setting.

### G11. `context.post_compact_prompt`
**From:** nowhere — this is the gap in §5.3 above, closed with the mechanism that
`ARCH-reliability` §13.4 and `ARCH-adapters` §10.2 both describe (OpenClaw's fenced-heading extraction,
byte-bounded, every failure path returning null).
**Into:** `ARCH-minimal` §5.3 and §13.
**Mechanism:** a config key whose DEFAULT-PROPOSED value is the red-line re-injection and whose `null`
value disables it.
**Why it belongs:** [204] names it as his setting — «чи відправляється якийсь промпт одразу після
компакту, чи ні» — and all four designs turned it into plugin behaviour or dropped it. Shipping the
re-injection as the default is right on the evidence; shipping it as behaviour rather than as his key
is the thing to fix.

---

## 7. What no graft fixes

Three things are outside all four documents and outside this axis, and the build should carry them
rather than assume they are handled.

1. **R1-16 case 2** — his parallel work in the same checkout. He routed it to a separate agent [378],
   [381], and all four designs correctly decline to invent it. `ARCH-adapters` §18 and
   `ARCH-operability` §16.7 both state the field solves it nowhere. Nothing to graft; something to owe.
2. **The learning loop.** [062]: «якщо це не підходить, то треба вчити» — the only place in the whole
   session where feedback changes future behaviour, and `extract/outside-list.md` records it is absent
   from `ANALYSIS-01` entirely. `ARCH-minimal` §14.11 is the only design that names it as a live gap,
   and its answer is a hand-maintained file. `ARCH-operability`'s `tuning.patch.yaml` tunes thresholds,
   which is the other half. Neither is the thing he described.
3. **R1-14's definitions.** He instructed the collector to bring him options [082]. `ARCH-minimal`
   §14.9 and `ARCH-reliability` §14 each offer one, both correctly labelled as proposals;
   `ARCH-adapters` and `ARCH-operability` offer none. Round 2 needs a page with both proposals side by
   side, not a design that has already picked.
