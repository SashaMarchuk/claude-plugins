# Configuration

## Where a value is written

Reusability decides, not convenience. A value usable by more than this plugin goes to the general config. Only a value nothing but this plugin can use goes into the plugin's own file. A value whose reach is unclear counts as reusable.

Then the level decides where that answer is true: on this machine in every project, in this project for everyone, or in this project for me only.

| Slot | Path | Kind |
|---|---|---|
| 1 | `<config-root>/shared/identity.json` | personal, every project |
| 2 | `<config-root>/shared/plugins/interview-handoff.json` | personal, every project |
| 3 | `./.claude/shared/identity.json` | committed |
| 4 | `./.claude/shared/plugins/interview-handoff.json` | committed |
| 5 | `./.claude/shared/identity.local.json` | personal, gitignored |
| 6 | `./.claude/shared/plugins/interview-handoff.local.json` | personal, gitignored |

Higher slot wins. `<config-root>` is `$CLAUDE_CONFIG_DIR` when set, otherwise the home directory plus `/.claude`. Never write a literal `~` into a file call, and never use `<config-root>/plugins/`.

On a clean first setup, with no config file anywhere, a shared answer goes to slot 1 and a plugin-only answer to slot 2. Nothing under `./.claude/` is created.

A setting some layer already holds is written back into that same layer, not created somewhere else as a side effect. Every write preserves keys it does not recognise.

## What is not a layer

`config/recommended.json` is **not a slot**. It is the plugin's own list of what a source could plausibly be answered by, and it **contributes nothing to the resolved config**: merging the six slots never reads it, and no value in it is ever treated as if a person had set it.

It is read in exactly one situation — while a source is being **chosen**: the wizard asking about a source for the first time, and the not-configured branch of a run. Once a source is settled, everything needed to use it lives in the stored value, so a run that already has one never opens that file again. Anything a settled value will need later, a URL above all, is copied into the value at the moment it is written.

This is why a run must never report a difference between `config/recommended.json` and what it found installed as though the config had been contradicted. Nothing was configured, so nothing was contradicted. What is worth saying in that situation is which copy is now in play, and that it is not yet settled.

## General config

Three keys, because each is useful to any plugin that talks to this person, not just this one.

```jsonc
{
  "language": "the language to talk to this person in",

  "connectors": {
    "session-logs": {
      "use": { "kind": "auto" }
    },
    "interview-method": {
      "use": {
        "name": "the method's own name, matched exactly against what the environment offers",
        "path": "where that method was actually read last time",
        "url":  "where the method can be fetched when no local copy resolves"
      }
    }
  }
}
```

**`language`** is what the person is spoken to in. Absent means detect it from the live conversation, which is the default and is usually right.

**`connectors.session-logs`** is where the record of a finished interview session can be found. `{ "kind": "auto" }` or an absent `use` sends it to detection, which here means asking.

**`connectors.interview-method`** is how the user is questioned while a package is being prepared. It is shared because a method that suits this person suits any plugin that questions them. Absent, or `{ "kind": "auto" }`, means nothing is settled yet: look at what is available, take or offer it, and record the answer. Resolution runs on every invocation, so a method that has changed since last time is used as it now is. `{ "name": "built-in" }` uses the method the plugin ships and stops the question returning.

The three keys are not three alternatives, they are one binding written from three angles, and **`name` is the one that resolves it**:

- **`name`** survives what a path does not — another machine, a different profile, an uninstalled marketplace. It is matched exactly against what the environment offers, never loosely.
- **`path`** is a record, not a binding: *this is the copy I actually read*. It is what lets the plugin tell a person they are editing a file that is not in play. When two copies of the same method exist, this is the one that answers "which".
- **`url`** is copied in **at the moment the value is written**, from the candidate in `config/recommended.json` when the settled method is one of them. It is carried so an interviewer running somewhere else can still reach the method, and so a broken path never sends the plugin back to `config/recommended.json` at run time.

A stored value that has no `url` simply has no URL known. It is not repaired silently and it is not rewritten behind the person's back; a value already on disk is never overridden by a recommendation.

Note on naming: another plugin in this marketplace uses a `transcripts` source, and there it means a notetaker service. Here the source is a place where a session record lives. Two different things, so two different names. Do not merge them.

## Plugin config

Everything else. None of it means anything outside this plugin.

```jsonc
{
  "output": {
    "path": "docs/handoff/{topic}"
  },

  "package": {
    "answersFile": false
  },

  "questions": {
    "style": "live",
    "recommendedBy": "plugin"
  },

  "language": {
    "questions": null,
    "documents": null,
    "analysis": null
  },

  "classification": {
    "labels": null
  },

  "compress": {
    "always": false
  },

  "context": {
    "source": null
  }
}
```

**`output.path`** is where packages and analyses land. There is no forced default. On first run the person is asked, and `docs/handoff/{topic}` is offered as the recommendation.

**`package.answersFile`** adds a file for the interviewer to write into. Off by default, and confirmed with the person before it is added. When it is on, that file becomes the resource `collect` reads.

**`questions.style`** is `live` by default: the package carries open items and the interviewer words each question during the session, following the method it was pointed at. Set it to `written` to have the plugin write finished question text instead, which is more rigid but survives an interviewer that cannot follow a method.

**`questions.recommendedBy`** is `plugin` by default, because the plugin has seen the project, the earlier rounds and the rejected list while the interviewer has seen none of that. Set it to `interviewer` to have the recommendation formed live.

**`language.*`** overrides the general `language` per artifact. Null means fall back to the general key, and an absent general key means detect. Verbatim quotes ignore all of this and stay in the language they were said.

**`classification.labels`** replaces the recommended five. Null keeps them.

**`compress.always`** compresses a noisy resource without asking, but only losslessly. Off by default, in which case the person is asked once per resource, and not asked at all when the resource is already clean. The original is kept whole either way.

**`context.source`** is where the context document takes its starting material from. Null means ask, which includes offering to work it out and having the person confirm that choice.

## Running with nothing configured

That is a normal state, not an error. Ask what is needed, use the answer, and write it down in the right file by the rules above. Never fail because a config file is missing.

## Config mode

### Why it is only two questions

One placement rule decides the whole shape: **the wizard asks up front only what can be answered well before any interview exists.** Every setting that needs a live artifact in hand, a record or a package or a method, is asked at the first moment that artifact appears, never before.

Two keys pass that bar. `output.path`, because it is the only key with no default. And `language`, because it is person-dependent and answerable cold. Everything else has a working default and a natural moment later that produces a better informed answer than a cold wizard ever could.

**Nothing here is a precondition for running.** A person who never opens config mode is not blocked: at the moment a package needs a home, that one question is asked inline, answered, and written down. The wizard is a convenience for settling things in one sitting, never a gate in front of the plugin.

**The order below is fixed and the sequence is exhaustive.** Two runs of the wizard produce the same wizard. Never reconstruct an order from the order things appear in this document.

One question per turn, the count stated, a recommendation on every question.

### First run

Open with this:

> Two questions, then you are set. Everything else already works on a default, and I will ask about each of those the first time it actually matters, never before. Each question carries a recommendation, and overturning it is worth more than agreeing with it. If you would rather not be asked at all, say autopilot and I will take the recommendations and tell you what I chose.

**Q1 of 2. Writes `output.path`.** First because it is the only key with no default, so it is the one thing that would otherwise have to be asked mid-flight the first time a package is written.

> **Q1 of 2. Where should interview packages be saved?**
>
> If this points at the wrong place, every package and analysis lands where nobody looks for it.
> When you run an interview about, say, pricing, three files are written into your project: the questions, a short context note, and the prompt you paste to your interviewer. Later the analysis of the answers lands next to them. They all need one home.
> Options: A. `docs/handoff/{topic}`, where `{topic}` is replaced with the interview name, so pricing lands in `docs/handoff/pricing` / B. a folder you name, with or without `{topic}` in it
> Recommendation: A. One predictable folder per interview keeps rounds from mixing, with no upkeep. If your project keeps documents somewhere specific, overturn this.

**Q2 of 2. Writes `language`, and on option C the three `language.*` keys too.** Second because it shapes every artifact but its default already works, including for this wizard itself.

> **Q2 of 2. What language should I use with you, and for what gets written?**
>
> If this is wrong, every question set and analysis comes out in a language you or your readers stumble over.
> Say you talk with me in one language, but the analysis is read by a teammate who works in another. Those can differ, or they can all be one.
> Options: A. follow the conversation, I use whatever language you are speaking, everywhere / B. one fixed language for everything, name it / C. split it, one language with you and another for some of the written pieces
> Recommendation: A. It follows you when you switch and there is nothing to maintain. Pick C only if someone other than you reads the output.

**Skip rule.** On A or B the wizard is done: the per-piece keys stay null and the follow-up is never asked. Only C triggers it.

> **Q2a. Which written pieces differ, and in what language?**
>
> Three can be set separately: the questions your interviewer asks, the package documents, and the analysis. Name a language for each one that should differ; the rest follow your answer above. Quoted words always stay in the language they were said. They are evidence and are never translated.

**Close** by naming every value actually written and the exact file each landed in. Name only what was written: answering Q2 with the recommendation means the language is left to detection, nothing is stored for it, and only one file is created. Do not describe a write that did not happen. Then:

> Eight more settings exist: the interview method, where finished session records are found, an answers file for your interviewer, the classification labels, automatic compression, where the context document starts from, whether the interviewer words the questions live or I write them out, and who prepares the recommendation on each item. Each keeps its default until the first moment it matters, and I will ask then. To change any one of them at any time, run the config command and name the setting in your own words.

### Autopilot

At any point, in config mode or in the middle of a question the plugin asked to get itself going, the person can say **autopilot** (or pass `--auto`). It means: stop asking me about settings, decide them.

What it does, in order:

1. **Reuse what already exists.** Read every config layer, and read the general config for values other plugins have already settled, `language` above all. A value already on disk is never overridden by a recommendation.
2. **Take the recommendation** for everything still unset. Every question in this document carries one, and that is the answer autopilot picks.
3. **Say what it did.** List each value chosen and the exact file it was written to, in one short block. Autopilot is quiet about asking, never about deciding.

**Autopilot only ever answers questions about settings.** It never answers a question about the subject being designed, never picks a trust level for a resource, and never decides what the person meant. Those belong to the person, and the plugin closing one of them on their behalf is the single failure it exists to avoid.

Any value it chose can be changed afterwards by naming that one setting.

### Deferred keys, and what makes each one get asked

Never asked by the first run. This order is also their re-run order.

| Key | Default until then | What triggers the ask |
|---|---|---|
| `connectors.interview-method` | auto | The first `run`. Step 2 of run mode already resolves it: one obvious method is taken and offered for settling, anything ambiguous is put to the person, and either way the answer is recorded. A wizard asking too would duplicate that with less in hand. |
| `connectors.session-logs` | auto, which means ask | The first `collect` with no source configured: ask where the record is, with the record actually in hand. When the answer names somewhere that could recur, offer in one line to remember it. A one-off paste is never recorded as standing. |
| `package.answersFile` | off | The person says their interviewer can write into files, or asks how answers get back. Offer it then, with the reason it is off by default. Never offered unprompted. |
| `classification.labels` | the recommended five | The person disputes a label or asks for different ones while looking at an analysis. Never proactive. |
| `compress.always` | off, which means ask per resource | The per-resource compression question in `collect` carries it as one of its answers: yes, yes and always, or no. There is no separate question. |
| `context.source` | ask per package | Run step 3 already asks at the first context build. Recorded as standing only when the person says the choice should hold for future rounds. |
| `questions.style` | `live` | Never asked proactively: the default is the recommended path. Offered when the person says the questions did not suit them, or when their interviewer turns out not to follow a method. Shown and re-asked on a config re-run, like every other stored value. |
| `questions.recommendedBy` | `plugin` | Never asked proactively. Offered when the person says the recommendations are off, or wants the interviewer to form them live. Shown and re-asked on a config re-run. |

### Re-run

- **Same order, always:** Q1, Q2, Q2a if a per-piece override is stored, then whichever deferred keys hold stored values, in the table order above, skipping the ones that do not. The order never depends on which run stored what.
- **State the count up front:** two, plus however many deferred keys are stored.
- **Re-ask form:** show the stored value and the file it lives in, ask whether it is still current. Keep it on a yes, collect a replacement on a no, and write back into the same layer it came from.
- **Jump to one setting:** name it in plain words rather than by key, for example "config language" or "config output folder". Ask only that question, write it, and close by naming what was written where. A name that matches nothing gets the list of settings, never a guess.

### Not decided, do not fill in

How a person places a **new** value at project level, slots 3 to 6, from inside the wizard is not decided. The clean-setup rule covers first writes and the write-back rule covers existing values, but nothing says when the wizard should offer a project-level home for a new value. Until that is decided the wizard writes by those two rules only and never asks a "which level" question.
