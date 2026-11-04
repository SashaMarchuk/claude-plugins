# Errata to ANALYSIS-01.md

`ANALYSIS-01.md` is never rewritten — it is the record of the first pass. This file carries the
corrections four independent re-readings and nine research clusters produced. Full detail with row
anchors: `../research/GAP-MAP.md` §2, and `../research/extract/{by-item,outside-list,corrections,meta}.md`.

## 1. The confidence grade was wrong on 22 items

`ANALYSIS-01.md` defines SETTLED as "owner confirmed a restatement" and then applies it to
restatements he never confirmed. Counted mechanically over every «Підтверджуєш?» and the next `ME:`
row: **22 of 48 restatements got no «так»**, and in six of them the interviewer announced its own
confirmation («Підтвердив, зафіксував» [218], «Зафіксував» [318], «Р1-18 підтверджено» [406] …).
**Eleven of the eighteen R1 items and six of the twelve Д items carry at least one unratified
sub-part.** No decision changes; the confidence grade does, and the four load-bearing ones are the
red-line file (R1-15), the stop vocabulary (R1-06), notifications (R1-17) and the health check
(R1-10). They open round 2 as block А.

## 2. Outright mis-statements

| Where | ANALYSIS-01 says | The transcript says |
|---|---|---|
| R1-10 | Fallback providers "must exist", SETTLED | He disowned that reading: «Це не як правило, це лише просто пояснення» [258]; the interviewer withdrew at [268] and never re-put it. **UNRATIFIED and partly disowned.** |
| R1-07 | "mtime named as the mechanism" | A hedge: «**Можливо**, там, **наприклад**, по даті» [195]. Measured since: second-resolution mtime misses two writes in the same second, and an identical rewrite still moves it. The mechanism is open. |
| Д1 | "(That is `<baseline-marketplace>`: six slots, three levels…)" under a SETTLED label | He named no repository and no rules [416]. The identification is correct but **INFERRED**, and it omits the `never` veto key — the closest existing analogue to his prohibitions file. |
| Headline | "The name changed: harness → orchestrator [118]" | He said «оркестратор» in his first sentence [007]; [118] only ratified existing usage. |
| R1-11 | "within configured authority [325]" | That condition is the **interviewer's** phrasing. His own answer attaches none: «це повністю і повністю окей» [324]. |
| Mechanics | "repeated … called out three times" | **15** duplications, **8** call-outs, two with profanity; plus a separate interruption complaint [266]. |
| Mechanics | "twice mislabelled an item" | Once [188], plus its self-correction [190]. Separately, [188] **invented an item that was not on the list** and he answered it — that answer belongs to no approved question. |
| R1-09, R1-15 | "see challenges" | There is no challenges section in the file. Both tensions were flagged and never delivered. |

## 3. Never asked, or asked by halves

- **R1-06's second half** — may the run spend the limit to zero, or must it leave him a reserve —
  **was never put to him.** There is no answer anywhere in the transcript. Round 2: Ж-01.
- **R1-14's third clause** — what happens to the task while it waits — never asked; Д6 answered it
  for the queue, not the task. And R1-14 was never asked as a question at all: every record is a
  restatement of material he volunteered while answering R1-01.
- **R1-01's "where"** and **R1-17's substance** (what is worth waking him for) — unanswered.
- **The night frame was silently dropped** from R1-02, R1-12 and R1-17 when they were spoken.

## 4. Present in the transcript, absent from the analysis

- **The learning loop** — «якщо це не підходить, то треба вчити» [062]: the only place where feedback
  changes future behaviour, and the missing half of "it reports its decision". Round 2: В-04.
- **The three-role model** — orchestrator / context watcher / executor [036, 195, 204], stated as
  three concrete terminal windows with per-window thresholds. The old plugin shipped four roles.
- **The simplicity constraint, stated four times** [171, 189, 300, 370] — recorded only once, and only
  as a local remark about boundaries.
- **His concrete numbers** — 60% weekly and 5% five-hour as "safe to start", 80% weekly as the example
  threshold [171].
- **«Але, так, це максимум»** [357] — dropped, and it is currently the binding constraint on the whole
  safety design. Round 2: Б-05.
- **«обмеження різного типу»** [357] — flattened to "one text file"; typed restrictions are a design
  hook. Round 2: Д-06.
- **Д3's teardown list starts with his own orchestrators** [430]; **Д4's «постійно»** and the running
  stack [433] were compressed away.
- **Д6's provenance** — «в мене так було, коли я робив, працював з гарнесом» [449]: the only
  field-proven design in the session, which should outweigh untested ideas. Round 2: Д-05, П-10.
- **«це має бути оркестратор для всього»** [182] — the scope at its widest.
- **His permission to be contradicted** — «я ну все вірю, але воно може не сходитися з дійсністю» [182]
  — recorded as instruction I1 without the permission framing, which is its most load-bearing clause.
- **I4's corrected intent** [409]: he does not want answers from this process; he wants to tell, have
  it recorded, and have it shape the build. [409] supersedes [408] by his own last-said-wins rule.
- **The opening monologue is paused, not finished** [031] — he never resumed it. Round 2 opens there.

## 5. Transcription that must not be guessed

«[profile switcher]» [199] = **a profile switcher** (verified on this machine). «медпоколка» [118] ≈ marketplace,
said with «наприклад». **«нетворк 3» [366] is unresolved** — plausibly Docker networks, plausibly
worktrees. «стокінгів» [512] — the interviewer read it as «токенів» [515] and he never confirmed that
reading.
