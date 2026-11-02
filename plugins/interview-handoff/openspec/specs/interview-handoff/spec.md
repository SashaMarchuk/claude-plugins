# interview-handoff

## Purpose

The plugin turns "I need to be interviewed about X" into a self contained handoff package: it grills
the user until the design tree has no unvisited branch, then writes a question set, a short context
document and a ready to paste prompt into the project. A separate interviewer runs the actual session
against those files, and the plugin takes no part in it. Afterwards the plugin reads the resource that
session produced, matches every answer to its question, classifies it, checks it against everything
answered before, and writes the result. If what comes back is contradictory or thin, it shows the list
and asks what to do about it.

The plugin is never the interviewer. It prepares and it analyses.

## Requirements

### Requirement: D1 · The grill runs the full tree

(round 1) The plugin interviews the user round by round until
the frontier is empty, in the manner of the `grilling` skill: work the design tree, ask the whole
frontier in one round with a recommendation on each question, wait, recompute. A first package is
never produced from a partial tree.

#### Scenario: Acceptance

Given a topic whose design tree still has unvisited branches, When `run` grills the user, Then no first package is written until the frontier is empty.

*Trace: REQUIREMENTS.md@fd6125e · D1*

### Requirement: D2 · The package is at least three files, and they are separate

(round 2) Questions, context and
prompt are three files, never merged. A fourth file for answers may be added. Which files a package
contains is configuration.

#### Scenario: Acceptance

Given a package is written, When its files are listed, Then questions, context and prompt are three separate files, an answers file appears only when configured, and the file set follows configuration.

*Trace: REQUIREMENTS.md@fd6125e · D2*

### Requirement: D3 · The plugin follows the S&F marketplace architecture

(round 2) A thin command plus a hidden
skill, config read on every run, `config/recommended.json` for outside tools, no connector named in
shipped code. Sources: `requirements/OWNER-DECISIONS.md`, `plugin-anatomy.feature`,
`plugin-commands.feature`, `plugin-agnosticism.feature`, `config-read.feature`, and
`.arch-work/drafts/config-levels-DRAFT.md` in the snf-automation-workspace checkout.

#### Scenario: Acceptance

Given the plugin's source, When it is checked against the S&F marketplace architecture, Then it has a thin command plus a hidden skill, reads config on every run, keeps outside tools in `config/recommended.json`, and names no connector in shipped code.

*Trace: REQUIREMENTS.md@fd6125e · D3*

### Requirement: D4 · The resource is configurable, and the plugin asks when it is not set

(round 1) The user may
configure a fixed place to read from, in which case the plugin reads it without asking. Otherwise the
plugin asks. If the place was already named in the conversation, the plugin confirms it rather than
asking again. The user may also simply hand over the content.

#### Scenario: Acceptance

Given no configured resource and none named in the conversation, When `collect` starts, Then the plugin asks for it; with a configured place it reads it without asking, and with a place already named it confirms instead of asking.

*Trace: REQUIREMENTS.md@fd6125e · D4*

### Requirement: D5 · Contradictions are shown, never resolved

(round 1) When the analysis finds contradictions or
too much that is unclear, the plugin shows the list and asks what to do with it. Two of the offers are
a further round and asking right now, in the current session.

#### Scenario: Acceptance

Given the analysis finds contradictions or too much that is unclear, When it finishes, Then the plugin shows the list and asks what to do, offering at least a further round and asking now, and resolves nothing itself.

*Trace: REQUIREMENTS.md@fd6125e · D5*

### Requirement: D6 · Name: `interview-handoff`

(round 2) Kebab case, no `snf-` or `claude-` prefix.

#### Scenario: Acceptance

Given the marketplace manifest, When the plugin is listed, Then its name is `interview-handoff`, in kebab case, with no `snf-` or `claude-` prefix.

*Trace: REQUIREMENTS.md@fd6125e · D6*

### Requirement: D7 · Three commands: `run`, `collect`, `config`

(round 2) `collect` is outside the closed verb set
of `docs/NAMING.md`, and `plugin-commands.feature` accepts a verb outside the baseline explicitly, so
the feature file governs.

#### Scenario: Acceptance

Given the plugin is installed, When its commands are listed, Then they are `run`, `collect` and `config`.

*Trace: REQUIREMENTS.md@fd6125e · D7*

### Requirement: D8 · Target repository: `SashaMarchuk/claude-plugins`

(round 2) The working checkout is
`/Users/sasha-marchuk/Work/claude-plugins`, on `main`. The S&F architecture is followed inside a
plugin that lives in the personal marketplace.

#### Scenario: Acceptance

Given the plugin's source, When its home is checked, Then it lives in `SashaMarchuk/claude-plugins` and follows the S&F architecture there.

*Trace: REQUIREMENTS.md@fd6125e · D8*

### Requirement: D9 · Memory between rounds is the context document itself

(round 2) `CONTEXT.md` is rewritten each
round on the basis of the previous interview, so the user never repeats something already said. The
file the interviewer reads and the plugin's own memory are the same artifact.

*Amended by D22.*

#### Scenario: Acceptance

Given a later round on a topic, When the package is rebuilt, Then the context document is rewritten from the previous interview and is both what the interviewer reads and the plugin's memory, so nothing already said is asked again.

*Trace: REQUIREMENTS.md@fd6125e · D9*

### Requirement: D10 · Where the short context comes from is asked, not assumed

(round 2) The plugin asks where to
take the context from. Working it out by itself is one of the options, and that option is confirmed or
chosen by the user rather than taken silently. The user may describe where to look and what to take.
This is asked even when the project is empty.

#### Scenario: Acceptance

Given a `run` in any project, even an empty one, When the short context is needed, Then the plugin asks where to take it from, and working it out itself is an option the user confirms or chooses, never taken silently.

*Trace: REQUIREMENTS.md@fd6125e · D10*

### Requirement: D11 · Output location is recommended, never forced

(round 3) The recommendation is
`./docs/handoff/{topic}/`. The user sets it at first run or through `config`, and the recommendation is
presented at the moment of asking.

#### Scenario: Acceptance

Given no output location is set, When the first package is about to be written, Then the plugin asks, presents `./docs/handoff/{topic}/` as the recommendation, and writes wherever the user chose.

*Trace: REQUIREMENTS.md@fd6125e · D11*

### Requirement: D12 · Five classification labels, as a recommendation

(round 3) Settled, partial, untouched,
premise rejected, deferred. The set is overridable, and the model may add a label of its own when
there is a reason. It is a recommendation, not a restriction. A separate flag marks an answer that
contradicts an earlier one.

#### Scenario: Acceptance

Given an analysed answer, When it is classified, Then it gets settled, partial, untouched, premise rejected or deferred (or an overriding label, or a label the model adds with a reason), and an answer that contradicts an earlier one carries a separate flag.

*Trace: REQUIREMENTS.md@fd6125e · D12*

### Requirement: D13 · The answers file is off by default

(round 3) It is enabled through configuration, and
confirmed with the user.

*Amended by AMD-1.*

#### Scenario: Acceptance

Given no configuration, When a package is written, Then it has no answers file; one appears only when configured and confirmed with the user.

*Trace: REQUIREMENTS.md@fd6125e · D13*

### Requirement: D14 · Language is auto detected by default and configurable per artifact

(round 4, amending
round 3) There is no rule and no recommendation in favour of English. By default the language is
detected from the live conversation with the model at that moment. Configuration sets it separately
for the things it applies to: the questions, the package documents, the analysis output. Verbatim
quotes are always kept exactly as said, in the language they were said.

#### Scenario: Acceptance

Given no language is configured, When an artifact is written, Then its language is detected from the live conversation; configuration may set it separately for the questions, the package documents and the analysis output; verbatim quotes keep the language they were said in.

*Trace: REQUIREMENTS.md@fd6125e · D14*

### Requirement: D15 · The topic is given at `run` and is the folder name

(round 4) When no topic is given, the
plugin proposes one from the first grilling round and the user confirms. `collect` with no topic takes
the most recent active handoff.

#### Scenario: Acceptance

Given `run` without a topic, When the first grilling round ends, Then the plugin proposes a topic, the user confirms it, and it becomes the folder name; `collect` without a topic takes the most recent active handoff.

*Trace: REQUIREMENTS.md@fd6125e · D15*

### Requirement: D16 · A second `run` on an existing topic never overwrites

(round 4) It shows what is closed and
what is open, and builds a package from the open part only. Earlier rounds stay where they are.

#### Scenario: Acceptance

Given a topic that already has a package, When `run` is used on it again, Then nothing is overwritten, closed and open items are shown, and the new package covers only the open part.

*Trace: REQUIREMENTS.md@fd6125e · D16*

### Requirement: D17 · Two trust levels on a processed resource

(round 4) Source of truth, or needs further
confirmation. One question per resource, asked once. The label stays in the analysis permanently.

#### Scenario: Acceptance

Given a resource processed for the first time, When it is read, Then the plugin asks once whether it is source of truth or needs further confirmation, and that label stays in the analysis permanently.

*Trace: REQUIREMENTS.md@fd6125e · D17*

### Requirement: D18 · Normalisation ships, optional through configuration, and is lossless

(round 4) Before
reading a resource the plugin may offer to optimise it first, or to send it through a cheaper sub
agent. Optimisation is by tokens only and only where it is possible, for example compacting JSON that
arrives as a JSON resource. No originality of the data is ever lost. The original is always kept.

*Amended by D19, which supersedes its config-only framing.*

#### Scenario: Acceptance

Given a resource that can be optimised, When normalisation is offered and accepted, Then only tokens are reduced, nothing original is lost, and the original is kept.

*Trace: REQUIREMENTS.md@fd6125e · D18*

### Requirement: D19 · Compression is offered, not silently applied

The original resource is always processed and always
kept whole. Before processing, the plugin asks in one line whether to compress a noisy resource for accuracy,
and does not ask when the resource is already clean. Configuration may set always-compress, and only
losslessly. This supersedes D18's config-only framing and rejects the reviewer's always-compress proposal.

#### Scenario: Acceptance

Given a noisy resource and no always-compress setting, When processing starts, Then the plugin asks in one line whether to compress; for a clean resource it does not ask; in every case the original is processed and kept whole.

*Trace: REQUIREMENTS.md@fd6125e · D19*

### Requirement: D20 · Two settings are shared, the rest are not

The language to speak to the person in, and where session
records live, go to the general config: both are useful to any plugin. Output location, package composition,
per artifact language, labels, compression and context source stay in the plugin's own file.

#### Scenario: Acceptance

Given the plugin stores a setting, When it chooses the file, Then the speaking language and where session records live go to the general config, and output location, package composition, per artifact language, labels, compression and context source go to the plugin's own file.

*Trace: REQUIREMENTS.md@fd6125e · D20*

### Requirement: D21 · The source is named `session-logs`, not `transcripts`

Another plugin in this marketplace already
uses `transcripts` to mean a notetaker service. Here the source is a place where a session record lives. Two
meanings, two names.

#### Scenario: Acceptance

Given the plugin's config and source, When the session-record source is named, Then it is `session-logs`, never `transcripts`.

*Trace: REQUIREMENTS.md@fd6125e · D21*

### Requirement: D22 · The context document may point instead of contain

It is rewritten each round, as D9 said, and that
is fine because it carries links to the earlier rounds' analyses rather than restating them. Those analyses
are written once and never rewritten. This closes the reviewer's objection to D9 without adding ceremony:
the conclusion is rewritten, the evidence is not.

#### Scenario: Acceptance

Given a later round, When the context document is rewritten, Then it links to the earlier rounds' analyses instead of restating them, and those analyses are never rewritten.

*Trace: REQUIREMENTS.md@fd6125e · D22*

### Requirement: D23 · The interview method is a resolved source, not a copy

(round five, after the owner caught the
original build inlining a paraphrase of a third-party skill) The skill names the source `interview-method`
and reads what answers it from the resolved config. Concrete candidates appear only in
`config/recommended.json`. Resolution happens on every run, so an updated or newly available method is used
as it now is. The plugin ships its own compact method in `references/interview-method.md` and falls back to
it when nothing else is available, so it never depends on a method it did not ship. Whether a resolved
method can be driven by the skill or must be handed to the user is checked before it is recommended.

#### Scenario: Acceptance

Given any run, When the interview method is needed, Then it is resolved from config on that run, concrete candidates appear only in `config/recommended.json`, and the shipped `references/interview-method.md` is used only when nothing else is available.

*Trace: REQUIREMENTS.md@fd6125e · D23*

### Requirement: D24 · The config wizard is two questions, and the sequence is written down

(round six, after a test run
found that "start at the first question" pointed at a key reference with no questions in it, so two runs
produced two different wizards) A first run asks only `output.path`, which has no default and blocks the first
write, and `language`, which is person-dependent and answerable cold. The other six keys each keep a working
default and are asked at a named in-context trigger instead, several of which the run and collect flows
already perform. Full sequence, wording and triggers in `references/config.md`.

#### Scenario: Acceptance

Given a first run, When the config wizard runs, Then it asks only `output.path` and `language`, and every other key keeps a working default and is asked at its named in-context trigger.

*Trace: REQUIREMENTS.md@fd6125e · D24*

### Requirement: D25 · An interviewer that cannot open the files stops, and says why

(round six) Stopping is correct
behaviour and is kept. What changes is that the generated prompt now always carries one line telling it to say
so plainly and ask for the whole package as one block of text. No separate command: the prompt asks, the
person relays, the skill produces it with every project path stripped, including those inside the pasted
content.

#### Scenario: Acceptance

Given an interviewer that cannot open the package files, When the session starts, Then it says so plainly and asks for the whole package as one block of text, and the skill produces that block with every project path stripped.

*Trace: REQUIREMENTS.md@fd6125e · D25*

### Requirement: D26 · The options line in a question is optional

(round six) The template previously made it mandatory, so
an open question was forced to invent a menu of one. An open question now omits the line. A list of one is
forbidden. Question wording beyond this is the interview method's business, not the plugin's.

#### Scenario: Acceptance

Given an open question with no real options, When it is written, Then it has no options line, and no question ever carries a list of one.

*Trace: REQUIREMENTS.md@fd6125e · D26*

### Requirement: D27 · No setting is a precondition for running

(round six) A missing value is asked inline at the moment
it is needed and written down, never a reason to stop. The wizard settles things in one sitting as a
convenience; it is not a gate in front of the plugin.

#### Scenario: Acceptance

Given a setting is missing, When it is needed, Then it is asked inline and written down, and the run continues instead of stopping.

*Trace: REQUIREMENTS.md@fd6125e · D27*

### Requirement: D28 · Autopilot

(round six) Saying autopilot, or passing `--auto`, stops the questions about settings:
values already on disk are reused, the written recommendation is taken for everything still unset, and the
plugin then states what it chose and where it wrote it. **It covers settings only.** It never answers a
question about the subject being designed, never picks a resource's trust level, and never decides what the
person meant, because the plugin closing one of those on the person's behalf is the failure it exists to
avoid.

#### Scenario: Acceptance

Given autopilot (`autopilot` or `--auto`), When settings would be asked, Then values already on disk are reused, the written recommendation is taken for every unset one, and the plugin states what it chose and where it wrote it; it never answers a question about the subject, picks a trust level or decides what the person meant.

*Trace: REQUIREMENTS.md@fd6125e · D28*

### Requirement: D29 · The package carries open items, and the interviewer words the questions live

(round seven) Each
item has an id, one line on what breaks if it is answered wrong, options where there are real ones, and a
recommendation. This is the default. `questions.style: written` restores finished wording for an interviewer
that cannot follow a method. Live wording rests only on the interviewer reading files, which is proven;
invoking a skill is a bonus, not a foundation.

#### Scenario: Acceptance

Given default settings, When a package is written, Then each item carries an id, one line on what breaks if it is answered wrong, options where there are real ones, and a recommendation, and the interviewer words the questions live; `questions.style: written` restores finished wording.

*Trace: REQUIREMENTS.md@fd6125e · D29*

### Requirement: D30 · The interviewer names the item id aloud in every confirmation

(round seven) With no written question
on disk, the id is what the analysis matches an answer to. Meaning-matching is the fallback and is reported as
such. The interviewer also reads the list back item by item at the end.

#### Scenario: Acceptance

Given an interview run from a package, When the interviewer confirms an answer, Then it names the item id aloud, and it reads the list back item by item at the end; the analysis matches by id and reports meaning-matching as a fallback.

*Trace: REQUIREMENTS.md@fd6125e · D30*

### Requirement: D31 · A method is referenced, never copied, and the reference may be remote

(round seven) Local path
first; when the method is not installed, the URL is handed over, or fetched at that moment and passed inline.
Nothing is ever stored as a frozen copy. This is how a person with none of the known methods installed still
gets one.

*Amended by D37.*

#### Scenario: Acceptance

Given a method that is not installed locally, When it is needed, Then its URL is handed over, or fetched at that moment and passed inline, and no frozen copy is ever stored.

*Trace: REQUIREMENTS.md@fd6125e · D31*

### Requirement: D32 · The plugin prepares each item's recommendation by default

(round seven) It has seen the project, the
earlier rounds and the rejected list; the interviewer has seen none of that, so a recommendation formed live
would be guesswork. `questions.recommendedBy: interviewer` moves it.

#### Scenario: Acceptance

Given default settings, When a package is written, Then the plugin has prepared each item's recommendation; `questions.recommendedBy: interviewer` moves it to the interviewer.

*Trace: REQUIREMENTS.md@fd6125e · D32*

### Requirement: D33 · The package points the interviewer at the method

(round seven, found by test) A live run resolved
`grilling` and followed it correctly on the plugin side, but nothing in the package named it, so the external
interviewer reached only the rules quoted in the prompt and reported the method as "the prompt itself". The
generated prompt now names the resolved method by path, and by URL where one exists, with the text inlined
only when neither can be reached.

#### Scenario: Acceptance

Given a resolved method, When the prompt is generated, Then it names the method by path, and by URL where one exists, and inlines the text only when neither can be reached.

*Trace: REQUIREMENTS.md@fd6125e · D33*

### Requirement: D34 · Every setting is enumerable and re-askable

(round eight, found by test) `questions.style` and
`questions.recommendedBy` were settable by name but appeared in no list and in no trigger table, so nothing
ever showed them back and a re-run never re-asked them. Both are now enumerated in the wizard's closing line
and carry a trigger, like every other deferred key.

#### Scenario: Acceptance

Given any setting, When the wizard closes or a run reaches that setting's trigger, Then it is listed and can be asked again; no setting is settable by name only.

*Trace: REQUIREMENTS.md@fd6125e · D34*

### Requirement: D35 · The plugin says which method it is using and where it actually read it from

(round eight, found by
test) A run recorded one path in config and loaded the method from another. This is transparency, not a
restriction: the two may legitimately differ, and a better or equivalent source may be used, but the person is
told which one is really in play so they are not editing a file that has no effect.

#### Scenario: Acceptance

Given a run, When the method is loaded, Then the plugin tells the person which method it is using and where it actually read it from, even when that differs from the configured path.

*Trace: REQUIREMENTS.md@fd6125e · D35*

### Requirement: D36 · A contradiction is its own item, and is resolved only by the person

(round eight) It carries both
statements and when each was said. If the person marked one final in the session, that is the decision and it
is recorded with the words that settled it. If nothing marks either as final, it goes back to them as a
question showing both sides and their timing; recency alone is not finality. A contradiction touching the
rejected list is called out, because a rejected entry that is now live policy must be corrected or the next
interviewer will refuse to discuss it.

#### Scenario: Acceptance

Given two statements that contradict each other, When the analysis records them, Then they form their own item with both statements and when each was said, settled only by the person's own final mark or answer and never by recency, and a contradiction touching the rejected list is called out.

*Trace: REQUIREMENTS.md@fd6125e · D36*

### Requirement: D37 · A method is resolved by name first, and the stored value carries its URL

(0.4.1, found by a user
report) D31 bound a method by local path, so a path that stopped resolving — another machine, another
profile, an uninstalled marketplace — sent the plugin past a perfectly good installed copy and out to the
network, or to the built-in method. It is now resolved by exact name first, then the stored path, then the
stored URL, then the built-in method. The stored value carries `name`, `path` and `url` together: the name
resolves it, the path records which copy was actually read, and the URL is copied in at write time so the
run-time branch never reads `config/recommended.json` and an interviewer running elsewhere is never handed
a path it cannot open. Names are matched exactly, never loosely: two methods can have similar names, and
choosing the wrong one silently is worse than asking. This amends D31 and does not weaken it — nothing is
copied, everything is still a reference.

#### Scenario: Acceptance

Given a stored method value, When the method is resolved, Then the exact name is tried first, then the stored path, then the stored URL, then the built-in method; the stored value carries `name`, `path` and `url`, and names are never matched loosely.

*Trace: REQUIREMENTS.md@fd6125e · D37*

### Requirement: D38 · On a clean first run, one obvious method is taken, not put to a vote

(0.4.1, found by the same
report) Step 2 said offer-and-pick for every case, so a person with exactly one method installed was asked
a question with one real answer before the grill could start. Now: exactly one method in exactly one copy is
taken, named out loud along with the copy that was read, and the person is **offered the chance to settle
it** — an offer that never blocks the first round. More than one method, the same method in more than one
copy, or none at all still goes to the person to pick, showing what is installed here alongside the
candidates. Autopilot still writes without asking, per D28. What must never happen is the shape that
prompted this: a difference between `config/recommended.json` and what is installed, reported as though the
person's configuration had been contradicted, on a run where nothing was configured at all.

#### Scenario: Acceptance

Given a clean first run with exactly one method in exactly one copy, When the grill is about to start, Then that method is taken and named together with the copy read, and the person is offered to settle it without blocking the first round; any other case goes to the person to pick, except under autopilot, which still writes without asking (D28).

*Trace: REQUIREMENTS.md@fd6125e · D38*

### Requirement: RES-1 · The resource

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

*Amended by D19.*

#### Scenario: Acceptance

Given a resource of any kind (a file, a path, pasted content, anything handed over), When `collect` processes it, Then it carries a trust level, whatever it answers leaves the open set, and the next round is offered from what remains, or unchanged when it answers nothing, without breaking the flow.

*Trace: REQUIREMENTS.md@fd6125e · § The resource*

### Requirement: PKG-1 · The package

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

*Refined by D26 and D29.*

#### Scenario: Acceptance

Given a package, When it is written, Then it holds the files in the table, and every question opens with why it is asked, uses no jargon, and states its recommendation aloud together with the fact that overturning it is worth more than agreeing with it.

*Trace: REQUIREMENTS.md@fd6125e · § The package*

### Requirement: ANL-1 · The analysis

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

*Amended by D19.*

#### Scenario: Acceptance

Given `collect` on a resource, When the analysis runs, Then it follows the seven steps in order, keeps the person's words verbatim in the language they were said, and flags, never guesses, a word, name or number that looks impossible.

*Trace: REQUIREMENTS.md@fd6125e · § The analysis*

### Requirement: CFG-1 · Configuration

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

*Amended by D19 and D21. Refined by D20, D24 and D27.*

#### Scenario: Acceptance

Given no configuration at any level, When the plugin runs, Then it asks what it needs and writes the answer down as configuration, and on every invocation it reads the resolved config before any other work.

*Trace: REQUIREMENTS.md@fd6125e · § Configuration*

### Requirement: AGN-1 · Agnosticism

No file under `commands/`, `skills/` or `scripts/` names a connector, and none names a method. The skill
names the sources it needs and reads what answers them from the resolved config. Concrete tool and method
names appear only in `config/recommended.json`. The plugin declares no fixed connector, so the hardcoding
exception does not apply to it.

`config/recommended.json` declares two sources, both with strength `weak`:

- `session-logs`, because the tool that holds a session recording differs from person to person, and
  several are plausible.
- `interview-method`, because the method that suits a person is theirs to pick, and any method installed
  in their environment can answer it.

That file is advisory. It is read only while a source is being **chosen**; it is never a config layer and
never contributes to a resolved value. See `references/config.md`.

#### Scenario: Acceptance

Given the files under `commands/`, `skills/` and `scripts/`, When they are searched for a connector or method name, Then none is found; concrete names appear only in `config/recommended.json`, which declares `session-logs` and `interview-method`, both `weak`, and is never a config layer.

*Trace: REQUIREMENTS.md@fd6125e · § Agnosticism*

### Requirement: AMD-1 · D13 stands, and gains a second role

**D13 stands, and gains a second role.** The answers file stays off by default. The reviewer proposed
cutting it entirely; the owner kept it, because when it is switched on it is the file the interviewer
writes into, and therefore the resource `collect` reads. The link between the two must not be lost.

#### Scenario: Acceptance

Given the answers file is switched on, When the interview runs, Then the interviewer writes into it and `collect` reads it as the resource.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 1*

### Requirement: AMD-2 · Ratification

**Ratification.** A recorded answer carries how it was confirmed. An answer the interviewer formulated
without a yes is `not ratified`, is never treated as settled, and opens the next package as a short
ratification block.

#### Scenario: Acceptance

Given an answer the interviewer formulated without a yes, When it is recorded, Then it is `not ratified`, is never treated as settled, and opens the next package as a short ratification block.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 2*

### Requirement: AMD-3 · Interviewer rules

**Interviewer rules.** The generated prompt carries a fixed set of behavioural rules, each derived from an
observed failure. In `references/interviewer-prompt.md`.

#### Scenario: Acceptance

Given a generated prompt, When it is written, Then it carries the fixed behavioural rules from `references/interviewer-prompt.md`.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 3*

### Requirement: AMD-4 · Later beats earlier inside one resource

**Later beats earlier inside one resource**, with explicit self-cancellation marks recognised and both
versions kept.

#### Scenario: Acceptance

Given a resource in which a later statement or an explicit self-cancellation changes an earlier one, When it is analysed, Then the later one wins and both versions are kept.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 4*

### Requirement: AMD-5 · Decisions dictated outside any question

**Decisions dictated outside any question** are swept for separately from question matching.

#### Scenario: Acceptance

Given a resource with decisions dictated outside any question, When it is analysed, Then they are found by a separate sweep, not only by question matching.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 5*

### Requirement: AMD-6 · Closures that cascade

**Closures that cascade** to questions that were never asked are checked against the whole open set.

#### Scenario: Acceptance

Given an answer that closes questions that were never asked, When it is analysed, Then the closure is checked against the whole open set.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 6*

### Requirement: AMD-7 · Idempotent collect

**Idempotent collect.** A resource already processed is recognised and not counted twice.

#### Scenario: Acceptance

Given a resource that was already processed, When `collect` runs on it again, Then it is recognised and not counted twice.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 7*

### Requirement: AMD-8 · Inline package variant

**Inline package variant** for an interviewer that cannot read project files.

#### Scenario: Acceptance

Given an interviewer that cannot read project files, When a package is needed, Then an inline package variant is available.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 8*

### Requirement: AMD-9 · Unattributable segments are flagged, never guessed

**Unattributable segments are flagged, never guessed**, because misattributing the interviewer's words to
the person fabricates a decision at the highest authority the record has.

#### Scenario: Acceptance

Given a segment that cannot be attributed to a speaker, When it is analysed, Then it is flagged, never guessed.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 9*

### Requirement: AMD-10 · Compression never drops the interviewer's restatements

**Compression never drops the interviewer's restatements**, since a confirmation lives in the pair of
restatement and yes.

#### Scenario: Acceptance

Given a resource is compressed, When compression is applied, Then the interviewer's restatements are kept.

*Trace: REQUIREMENTS.md@fd6125e · § Amendments carried without a new decision, item 10*
