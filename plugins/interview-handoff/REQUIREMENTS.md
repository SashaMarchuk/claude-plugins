# interview-handoff. Requirements

Status: agreed in a grilling session on 2026-08-21, five rounds, frontier empty. Built on 2026-08-22.
Nothing here was decided by the author. Every line traces to an answer given in those rounds.
Amendments after an independent validation are at the end of this file.

## What it is

The plugin turns "I need to be interviewed about X" into a self contained handoff package: it grills
the user until the design tree has no unvisited branch, then writes a question set, a short context
document and a ready to paste prompt into the project. A separate interviewer runs the actual session
against those files, and the plugin takes no part in it. Afterwards the plugin reads the resource that
session produced, matches every answer to its question, classifies it, checks it against everything
answered before, and writes the result. If what comes back is contradictory or thin, it shows the list
and asks what to do about it.

The plugin is never the interviewer. It prepares and it analyses.

## Decisions

Each decision carries the round it was settled in.

**D1. The grill runs the full tree.** (round 1) The plugin interviews the user round by round until
the frontier is empty, in the manner of the `grilling` skill: work the design tree, ask the whole
frontier in one round with a recommendation on each question, wait, recompute. A first package is
never produced from a partial tree.

**D2. The package is at least three files, and they are separate.** (round 2) Questions, context and
prompt are three files, never merged. A fourth file for answers may be added. Which files a package
contains is configuration.

**D3. The plugin follows the S&F marketplace architecture.** (round 2) A thin command plus a hidden
skill, config read on every run, `config/recommended.json` for outside tools, no connector named in
shipped code. Sources: `requirements/OWNER-DECISIONS.md`, `plugin-anatomy.feature`,
`plugin-commands.feature`, `plugin-agnosticism.feature`, `config-read.feature`, and
`.arch-work/drafts/config-levels-DRAFT.md` in the snf-automation-workspace checkout.

**D4. The resource is configurable, and the plugin asks when it is not set.** (round 1) The user may
configure a fixed place to read from, in which case the plugin reads it without asking. Otherwise the
plugin asks. If the place was already named in the conversation, the plugin confirms it rather than
asking again. The user may also simply hand over the content.

**D5. Contradictions are shown, never resolved.** (round 1) When the analysis finds contradictions or
too much that is unclear, the plugin shows the list and asks what to do with it. Two of the offers are
a further round and asking right now, in the current session.

**D6. Name: `interview-handoff`.** (round 2) Kebab case, no `snf-` or `claude-` prefix.

**D7. Three commands: `run`, `collect`, `config`.** (round 2) `collect` is outside the closed verb set
of `docs/NAMING.md`, and `plugin-commands.feature` accepts a verb outside the baseline explicitly, so
the feature file governs.

**D8. Target repository: `SashaMarchuk/claude-plugins`.** (round 2) The working checkout is
`/Users/sasha-marchuk/Work/claude-plugins`, on `main`. The S&F architecture is followed inside a
plugin that lives in the personal marketplace.

**D9. Memory between rounds is the context document itself.** (round 2) `CONTEXT.md` is rewritten each
round on the basis of the previous interview, so the user never repeats something already said. The
file the interviewer reads and the plugin's own memory are the same artifact.

**D10. Where the short context comes from is asked, not assumed.** (round 2) The plugin asks where to
take the context from. Working it out by itself is one of the options, and that option is confirmed or
chosen by the user rather than taken silently. The user may describe where to look and what to take.
This is asked even when the project is empty.

**D11. Output location is recommended, never forced.** (round 3) The recommendation is
`./docs/handoff/{topic}/`. The user sets it at first run or through `config`, and the recommendation is
presented at the moment of asking.

**D12. Five classification labels, as a recommendation.** (round 3) Settled, partial, untouched,
premise rejected, deferred. The set is overridable, and the model may add a label of its own when
there is a reason. It is a recommendation, not a restriction. A separate flag marks an answer that
contradicts an earlier one.

**D13. The answers file is off by default.** (round 3) It is enabled through configuration, and
confirmed with the user.

**D14. Language is auto detected by default and configurable per artifact.** (round 4, amending
round 3) There is no rule and no recommendation in favour of English. By default the language is
detected from the live conversation with the model at that moment. Configuration sets it separately
for the things it applies to: the questions, the package documents, the analysis output. Verbatim
quotes are always kept exactly as said, in the language they were said.

**D15. The topic is given at `run` and is the folder name.** (round 4) When no topic is given, the
plugin proposes one from the first grilling round and the user confirms. `collect` with no topic takes
the most recent active handoff.

**D16. A second `run` on an existing topic never overwrites.** (round 4) It shows what is closed and
what is open, and builds a package from the open part only. Earlier rounds stay where they are.

**D17. Two trust levels on a processed resource.** (round 4) Source of truth, or needs further
confirmation. One question per resource, asked once. The label stays in the analysis permanently.

**D18. Normalisation ships, optional through configuration, and is lossless.** (round 4) Before
reading a resource the plugin may offer to optimise it first, or to send it through a cheaper sub
agent. Optimisation is by tokens only and only where it is possible, for example compacting JSON that
arrives as a JSON resource. No originality of the data is ever lost. The original is always kept.

## The resource

`collect` takes a resource. A session transcript is one kind of resource and carries no special
status.

- A resource may be a file, a path, pasted content, or anything else the user hands over.
- A resource may have nothing to do with the questions and still be important context.
- Every processed resource carries a trust level (D17), set by asking once.
- Processing a resource never breaks the flow. Whatever the resource already answers is removed from
  the open set, and the next round is offered from what remains. When the resource answers nothing,
  the round that was already planned is offered unchanged.
- Voice resources repeat the same phrase many times over. Normalisation (D18) removes the repetition
  without removing anything else.

## The package

| File | Contents | Why it exists |
|---|---|---|
| questions | the question set, with options and a recommendation on each | what the interviewer works through in order |
| context | current state, plus what has already been rejected | so the interviewer can explain a question that did not land, and does not propose dead ideas |
| prompt | the prompt for the interviewer | what the user pastes into the session |
| answers | optional, off by default (D13) | somewhere for the interviewer to write, when it writes at all |

Question shape, taken from `grilling` and extended by two rules that a live session proved necessary:

```
Q1. <title in plain language>

<One line: what breaks if this is answered wrong.>
<Body. A concrete worked case with named people.>
Options: A ... / B ... / C ...
Recommendation: <option, and the single strongest reason>
```

Rules the question text must satisfy:

- No jargon. A term the person may not know is a broken question, not their failing.
- Every question opens with why it is being asked.
- The recommendation is stated out loud, together with the fact that overturning it is worth more than
  agreeing with it.

## The analysis

1. Find the resource (D4).
2. Normalise it, if that was offered and accepted (D18). Keep the original.
3. Match each answer to its question.
4. Classify each question (D12).
5. Compare against everything answered before, and flag every contradiction (D12).
6. Write the result to the configured location (D11).
7. Show the contradictions and what is still open, and ask what to do (D5).

Two rules govern the writing:

- Verbatim. The person's words are kept as said, in the language they were said (D14). That is the
  evidence if they later disagree.
- Recognition can be wrong, the person cannot. A word, name or number that looks impossible is flagged,
  never guessed.

## Configuration

Levels, paths and precedence are the S&F ones (D3). Which file a value lands in follows the
reusability test: anything usable by more than this plugin goes to the general config, and only a
value nothing but this plugin can use goes into the plugin's own file.

General config, `shared/identity.json`:

- `connectors.transcripts`, the source the resource is read from. The name matches the source
  `find-call` already uses in this same marketplace.
- the working language, when the user pins one instead of leaving it auto detected (D14).

Plugin config, `shared/plugins/interview-handoff.json`:

- output location (D11)
- which files the package contains, and whether the answers file is on (D2, D13)
- per artifact language overrides (D14)
- classification labels, when overridden (D12)
- whether normalisation is offered (D18)
- where the short context is taken from (D10)

Behaviour required by the architecture:

- The plugin runs with no configuration at any level. It asks what it needs and writes the answer down
  as configuration.
- The resolved config is read on every invocation, before any other work.
- `config` mode starts at the first question every time, and asks whether a stored value is still
  current.

## Agnosticism

No file under `commands/`, `skills/` or `scripts/` names a connector. The skill names the source it
needs, `transcripts`, and reads the tool for it from the resolved config. Concrete tool names appear
only in `config/recommended.json`. The plugin declares no fixed connector, so the hardcoding exception
does not apply to it.

`config/recommended.json` declares one source, `transcripts`, with strength `weak`: the tool that holds
a session recording differs from person to person, and several are plausible.

## Not in scope

- The plugin never runs the interview itself.
- It edits nothing except its own package files and the analysis output.
- It never invents an answer and never closes a question on the user's behalf.
- It pulls in no task tracker, no git workflow and no CI.

## Not decided

- Whether the plugin ships tests, and which. The repository has a regression harness at
  `tests/run-all.sh`.
- Whether `REQUIREMENTS.md` stays in the plugin folder or moves once the plugin is built.

---

# Amendments after independent validation, 2026-08-21

An independent review checked this spec against the two real sessions it generalises. Its verdict was that
the core is sound and the spec had dropped the two most valuable products of the manual process: the rules
governing interviewer behaviour, and the discipline of the analysis. The amendments below close that, plus
four owner decisions taken in a fifth round.

## Owner decisions, round five

**D19. Compression is offered, not silently applied.** The original resource is always processed and always
kept whole. Before processing, the plugin asks in one line whether to compress a noisy resource for accuracy,
and does not ask when the resource is already clean. Configuration may set always-compress, and only
losslessly. This supersedes D18's config-only framing and rejects the reviewer's always-compress proposal.

**D20. Two settings are shared, the rest are not.** The language to speak to the person in, and where session
records live, go to the general config: both are useful to any plugin. Output location, package composition,
per artifact language, labels, compression and context source stay in the plugin's own file.

**D21. The source is named `session-logs`, not `transcripts`.** Another plugin in this marketplace already
uses `transcripts` to mean a notetaker service. Here the source is a place where a session record lives. Two
meanings, two names.

**D22. The context document may point instead of contain.** It is rewritten each round, as D9 said, and that
is fine because it carries links to the earlier rounds' analyses rather than restating them. Those analyses
are written once and never rewritten. This closes the reviewer's objection to D9 without adding ceremony:
the conclusion is rewritten, the evidence is not.

## Amendments carried without a new decision

- **D13 stands, and gains a second role.** The answers file stays off by default. The reviewer proposed
  cutting it entirely; the owner kept it, because when it is switched on it is the file the interviewer
  writes into, and therefore the resource `collect` reads. The link between the two must not be lost.
- **Ratification.** A recorded answer carries how it was confirmed. An answer the interviewer formulated
  without a yes is `not ratified`, is never treated as settled, and opens the next package as a short
  ratification block.
- **Interviewer rules.** The generated prompt carries a fixed set of behavioural rules, each derived from an
  observed failure. In `references/interviewer-prompt.md`.
- **Later beats earlier inside one resource**, with explicit self-cancellation marks recognised and both
  versions kept.
- **Decisions dictated outside any question** are swept for separately from question matching.
- **Closures that cascade** to questions that were never asked are checked against the whole open set.
- **Idempotent collect.** A resource already processed is recognised and not counted twice.
- **Inline package variant** for an interviewer that cannot read project files.
- **Unattributable segments are flagged, never guessed**, because misattributing the interviewer's words to
  the person fabricates a decision at the highest authority the record has.
- **Compression never drops the interviewer's restatements**, since a confirmation lives in the pair of
  restatement and yes.

## Still not decided

- Whether the plugin ships tests, and which.
- Whether `REQUIREMENTS.md` stays in the plugin folder.

**D23. The interview method is a resolved source, not a copy.** (round five, after the owner caught the
original build inlining a paraphrase of a third-party skill) The skill names the source `interview-method`
and reads what answers it from the resolved config. Concrete candidates appear only in
`config/recommended.json`. Resolution happens on every run, so an updated or newly available method is used
as it now is. The plugin ships its own compact method in `references/interview-method.md` and falls back to
it when nothing else is available, so it never depends on a method it did not ship. Whether a resolved
method can be driven by the skill or must be handed to the user is checked before it is recommended.

**D24. The config wizard is two questions, and the sequence is written down.** (round six, after a test run
found that "start at the first question" pointed at a key reference with no questions in it, so two runs
produced two different wizards) A first run asks only `output.path`, which has no default and blocks the first
write, and `language`, which is person-dependent and answerable cold. The other six keys each keep a working
default and are asked at a named in-context trigger instead, several of which the run and collect flows
already perform. Full sequence, wording and triggers in `references/config.md`.

**D25. An interviewer that cannot open the files stops, and says why.** (round six) Stopping is correct
behaviour and is kept. What changes is that the generated prompt now always carries one line telling it to say
so plainly and ask for the whole package as one block of text. No separate command: the prompt asks, the
person relays, the skill produces it with every project path stripped, including those inside the pasted
content.

**D26. The options line in a question is optional.** (round six) The template previously made it mandatory, so
an open question was forced to invent a menu of one. An open question now omits the line. A list of one is
forbidden. Question wording beyond this is the interview method's business, not the plugin's.

## Still not decided

- Whether the plugin ships tests, and which.
- Whether `REQUIREMENTS.md` stays in the plugin folder.
- How the wizard places a **new** value at project level (slots 3 to 6). The clean-setup and write-back rules
  cover every other case; this one is not decided and is not to be invented.

**D27. No setting is a precondition for running.** (round six) A missing value is asked inline at the moment
it is needed and written down, never a reason to stop. The wizard settles things in one sitting as a
convenience; it is not a gate in front of the plugin.

**D28. Autopilot.** (round six) Saying autopilot, or passing `--auto`, stops the questions about settings:
values already on disk are reused, the written recommendation is taken for everything still unset, and the
plugin then states what it chose and where it wrote it. **It covers settings only.** It never answers a
question about the subject being designed, never picks a resource's trust level, and never decides what the
person meant, because the plugin closing one of those on the person's behalf is the failure it exists to
avoid.

**D29. The package carries open items, and the interviewer words the questions live.** (round seven) Each
item has an id, one line on what breaks if it is answered wrong, options where there are real ones, and a
recommendation. This is the default. `questions.style: written` restores finished wording for an interviewer
that cannot follow a method. Live wording rests only on the interviewer reading files, which is proven;
invoking a skill is a bonus, not a foundation.

**D30. The interviewer names the item id aloud in every confirmation.** (round seven) With no written question
on disk, the id is what the analysis matches an answer to. Meaning-matching is the fallback and is reported as
such. The interviewer also reads the list back item by item at the end.

**D31. A method is referenced, never copied, and the reference may be remote.** (round seven) Local path
first; when the method is not installed, the URL is handed over, or fetched at that moment and passed inline.
Nothing is ever stored as a frozen copy. This is how a person with none of the known methods installed still
gets one.

**D32. The plugin prepares each item's recommendation by default.** (round seven) It has seen the project, the
earlier rounds and the rejected list; the interviewer has seen none of that, so a recommendation formed live
would be guesswork. `questions.recommendedBy: interviewer` moves it.

**D33. The package points the interviewer at the method.** (round seven, found by test) A live run resolved
`grilling` and followed it correctly on the plugin side, but nothing in the package named it, so the external
interviewer reached only the rules quoted in the prompt and reported the method as "the prompt itself". The
generated prompt now names the resolved method by path, and by URL where one exists, with the text inlined
only when neither can be reached.

**D34. Every setting is enumerable and re-askable.** (round eight, found by test) `questions.style` and
`questions.recommendedBy` were settable by name but appeared in no list and in no trigger table, so nothing
ever showed them back and a re-run never re-asked them. Both are now enumerated in the wizard's closing line
and carry a trigger, like every other deferred key.

**D35. The plugin says which method it is using and where it actually read it from.** (round eight, found by
test) A run recorded one path in config and loaded the method from another. This is transparency, not a
restriction: the two may legitimately differ, and a better or equivalent source may be used, but the person is
told which one is really in play so they are not editing a file that has no effect.

**D36. A contradiction is its own item, and is resolved only by the person.** (round eight) It carries both
statements and when each was said. If the person marked one final in the session, that is the decision and it
is recorded with the words that settled it. If nothing marks either as final, it goes back to them as a
question showing both sides and their timing; recency alone is not finality. A contradiction touching the
rejected list is called out, because a rejected entry that is now live policy must be corrected or the next
interviewer will refuse to discuss it.
