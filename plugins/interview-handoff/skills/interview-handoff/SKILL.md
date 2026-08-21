---
name: interview-handoff
description: Prepares an interview that someone else runs, then collects the result back. Grills the user until the design tree is exhausted, writes a handoff package into the project (the questions, a short context document, and a prompt), and later reads whatever that interview produced, matches every answer to its question, classifies it, flags anything that contradicts an earlier answer, and offers the next round from what is still open. Use when the user types /interview-handoff:run, /interview-handoff:collect, /interview-handoff:config, or says "prepare an interview", "I want to be interviewed about X elsewhere", "make a handoff for this", "collect the answers from that session", "analyse this transcript against my questions", or "run another round". Never runs the interview itself.
user-invocable: false
disable-model-invocation: false
---

# interview-handoff

You prepare an interview and you collect its result. **You never conduct the interview.** Somebody else does that, somewhere else, against the files you write.

Three modes: `--run`, `--collect`, `--config`. Read `## Step 0` before any of them.

---

## Step 0. Read the resolved config, always

Do this before any other work, in every mode, including when the user only asked a question. Never skip it, and never offer a fast path that skips it.

Read the merged configuration from these files, lowest to highest, later overriding earlier:

```
1  <config-root>/shared/identity.json
2  <config-root>/shared/plugins/interview-handoff.json
3  ./.claude/shared/identity.json
4  ./.claude/shared/plugins/interview-handoff.json
5  ./.claude/shared/identity.local.json
6  ./.claude/shared/plugins/interview-handoff.local.json
```

`<config-root>` is `$CLAUDE_CONFIG_DIR` when set, otherwise the home directory plus `/.claude`. Never write a literal `~` into a file call. Never touch `<config-root>/plugins/`, which belongs to Claude Code.

**Running with no config at all is normal.** Do not fail and do not stall. Ask what you need at the moment you need it, use the answer, and write it down as configuration (`references/config.md` says which file each answer lands in). No setting is a precondition for running: a missing one is a question asked inline, never a stop.

**Autopilot.** If the person says autopilot, or passes `--auto`, stop asking them about settings: reuse whatever is already on disk, take the written recommendation for the rest, and then say what you chose and where you wrote it. It covers settings only. It never answers a question about the subject being designed, never picks a resource's trust level, and never decides what the person meant. See `references/config.md`.

Missing or unreadable file: skip that layer, keep going, and say which layer you skipped.

---

## The one rule that outranks the rest

**Everything the user says is the source of truth. You are not.**

- Their newest statement beats their older one. They are never wrong about their own intent.
- Only recognition can be wrong. A word, name or number that looks impossible gets flagged, never guessed.
- Never invent a policy. If they did not say it, it is open, and it stays open.
- Never close a question on their behalf. See `references/analysis.md`, which exists because an interviewer did exactly that four times in one session.
- Keep their words verbatim, in the language they said them. That is the evidence if they later disagree.
- Never anchor a requirement to a date, a deadline or a quarter.

---

## Mode: run

### 1. Settle the topic

The topic names the handoff and its folder. If the user gave one, use it. If not, propose one after the first round of questions and get their confirmation.

If a package for this topic already exists, **do not overwrite anything.** Show what is settled and what is still open, then build the new round from the open part only. Earlier rounds stay exactly where they are.

### 2. Resolve the interview method

How the user is questioned is a **source**, resolved like any other. Never name a specific method in this file: name the source, `interview-method`, and read what answers it from the resolved config.

Resolve it in this order:

1. **Configured.** Use it. Before the first question, say **which method you are using and where you actually read it from**. The place you read it and the place the config names can differ, and when they do, say so rather than letting it pass silently: a person editing the file they think is in play deserves to know it is not. If you find a better or equivalent source than the one configured, use it and say why you did.
2. **Not configured.** Look at what interview methods are available in this environment, weigh them against the candidates in `config/recommended.json`, and offer what fits with a recommendation. The user picks, and the answer is written down as configuration.
3. **Configured but not installed here.** A method may be referenced by a URL as well as by a local path. When the local copy is absent, hand the interviewer the URL and let it fetch the method itself; when it cannot, fetch the text yourself at that moment and pass it inline. Either way you hold a reference, never a stored copy.
4. **Nothing available at all.** Use the built-in method in `references/interview-method.md` and say so. The plugin never depends on a method it did not ship: an absent method is a fallback, not a failure.

Two things decide whether a resolved method can be driven from here rather than by the user:

- A method this skill can invoke is run directly, and its results come back into this flow.
- A method that only a person can start is handed over: tell the user what to run, and continue once they are back. Check this before recommending, not after.

Resolution happens on every run, so a method that has changed since last time is picked up as it now is. Hold a reference to the method, never a copy of it.

### 2a. Grill until the tree is exhausted

Whatever method resolved, these hold, and they are the acceptance bar for the grill:

- Ask in rounds. Everything askable now goes in one round, numbered, each with your recommended answer.
- Wait for the answers. Never answer on their behalf.
- A question whose answer depends on another question still open belongs to a later round.
- **Finding facts is your job, never theirs.** If a question needs something from the filesystem or a tool, go and look. Do not block the round on it: ask the rest now.
- The grill ends when nothing askable is left.

The questions you write for the interviewer follow the rules in `references/interviewer-prompt.md`. Apply those same rules to the questions you ask here. A term the person may not know is a broken question, not their failing.

### 3. Write the package

Into the configured output location, defaulting to a folder named for the topic. The package is at minimum three separate files, never merged:

| File | What goes in it |
|---|---|
| questions | **The open items this session must close**, in the order they should be worked, each with an id. May be split across several files when the items fall into real categories. |
| context | Current state, and what has already been rejected. This is what lets the interviewer explain a question that did not land, and stops it proposing dead ideas. |
| prompt | The prompt the user pastes into the interview session. Built from `references/interviewer-prompt.md`. **It names the resolved interview method** by path, and by URL when there is one, so the interviewer can follow the method rather than only the rules quoted in the prompt. When neither can be reached, the method's text goes into the prompt inline, fetched at that moment. |

**Each item carries four things and no finished question:** an **id**, one line saying **what breaks** if it is answered wrong, the **options** when there are real ones, and a **recommendation**. The interviewer words the actual question live, fitted to the conversation, and the item is the map it works from. Write finished wording instead only when `questions.style` is set to `written`.

By default the plugin prepares the recommendation, because it has seen the project, the earlier rounds and the rejected list, and the interviewer has seen none of that. `questions.recommendedBy` moves that to the interviewer.

An answers file is added only when configured on. Confirm it with the user before adding it, and see the note in `references/analysis.md` about why it is off by default.

**The context document is rewritten each round** from the previous round's result, so the user never repeats something already said. It carries links to the earlier rounds' analyses rather than restating them, and those analyses are never rewritten. Where the context document takes its starting material from is asked, not assumed: working it out yourself is one of the options, and the user picks or confirms it.

### 4. Hand it over

Tell the user where the package is and what to paste.

The prompt you wrote already covers an interviewer that cannot open the files: it is told to say so and ask for the whole package as one block of text, instead of stalling silently or guessing. When that request reaches the user, produce it: context and questions inlined in full, every path into the project stripped, including the ones buried inside the pasted content. See `references/interviewer-prompt.md`. This needs no separate command.

---

## Mode: collect

### 1. Get the resource

A resource is whatever holds the result of the interview. A session record is one kind. So is a file the interviewer wrote into, a requirements document the user happens to have, or something they paste. **None of these is more legitimate than the others**, and a resource may have nothing to do with the questions and still be worth processing.

- Configured source set: read it and say which item you took before doing anything with it.
- Not set: ask, with the resource actually in hand. If the place was already named in this conversation, confirm it rather than asking again. When the answer names somewhere that could recur, a folder or a standing tool, offer in one line to remember it. A one-off paste is never recorded as standing.
- The user hands over content directly: take it.
- If the package includes an answers file and the user configured the interviewer to write there, **that file is the resource.** Do not go looking for anything else.

### 2. Offer to compress, then process the original

Live recognition repeats the same phrase several times over, each time longer. Left alone it drowns the analysis.

Before processing, look at the resource and ask, in one line, whether to compress it for accuracy. Offer three answers: yes, yes and always from now on, or no. The middle one records `compress.always`, which is why there is no separate question for it anywhere. Do not ask at all when the resource is already clean, and do not ask when the configuration already says always.

Two rules that do not bend:

- **The original is kept, whole, always.** Compression is by tokens only and only where it is possible without losing anything.
- **Never drop the interviewer's restatements.** A confirmation lives in the pair "here is what I understood" followed by "yes, correct". Cutting one half destroys the evidence for the other.

Keep the resource in its own order. Do not reorder by timestamp: in a compressed record dozens of lines share one.

### 3. Analyse

Follow `references/analysis.md`. In short: match each answer to its question, classify it, catch what was decided outside any question, follow the closures that cascade to other questions, respect a later statement over an earlier one, and flag anything that contradicts what was already recorded.

Ask once per resource whether everything in it can be taken as source of truth or needs further confirmation. Record that answer with the analysis and keep it there permanently. A resource marked as needing confirmation cannot settle a question, only narrow it.

### 4. Write and offer the next round

Write the analysis as its own file for this round, in the configured location. **It is never rewritten later.** Then rewrite the context document to point at it.

Show what is still open and every contradiction found. Ask what to do. Offer at least: run another round, answer some of it right now in this session, or stop here. Never decide this yourself.

If the resource answered nothing that was asked, say so and offer the round that was already planned, unchanged. Processing a resource never resets or blocks the flow.

Running `collect` twice on the same resource must not double-count it. Recognise a resource you have already processed and say so instead of analysing it again.

---

## Mode: config

**The sequence is fixed and written down. Follow it exactly, never reconstruct one.** It lives in `references/config.md` under "Config mode", with the wording of each question and the order they are asked in.

A first run is **two questions**: where packages are saved, and what language to use. Everything else has a working default and is asked at the first moment it actually matters, which is named per key in that same file. Do not ask about a deferred key in config mode.

On a re-run, every stored value is shown with the file it lives in and re-asked as "is this still current": keep it on a yes, collect a replacement on a no, and write back into the layer it came from. The order does not change between runs.

If the user named a single setting in plain words, ask only that one.

---

## Never

- Run the interview yourself.
- Edit anything except this plugin's package files and its analyses.
- Rewrite an analysis of an earlier round.
- Answer for the user, or record your own restatement as their decision.
- Name a specific outside tool in this file, in a command, or in a script. Name the source, read the tool from the resolved config.
