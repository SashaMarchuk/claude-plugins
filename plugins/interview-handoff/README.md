# interview-handoff

Prepares an interview that somebody else runs, then collects the result back.

You do not want to be interviewed inside a coding session. You want to be interviewed by voice, elsewhere, and then have the answers collected and merged. That is the split this plugin makes.

```
you ──grill──> plugin ──package──> a separate interviewer ──session──> you
                  ^                                                     │
                  └──────────────── the result ─────────────────────────┘
```

The plugin never conducts the interview. It prepares and it analyses.

## Commands

| Command | What it does |
|---|---|
| `/interview-handoff:run [topic]` | Grills you until the design tree is exhausted, then writes the package: the questions, a short context document, and a prompt. |
| `/interview-handoff:collect [path]` | Reads what the interview produced, matches answers to questions, classifies them, flags contradictions, offers the next round. |
| `/interview-handoff:config` | Sets where results come from, where output lands, and which language each artifact uses. |

## What it writes

Three files, always separate. The questions drive the session. The context document lets the interviewer explain a question that did not land, and stops it proposing things you already rejected. The prompt is what you paste.

A fourth file for answers is added only if you turn it on. It is off because interviewers told to write into one have, in practice, written nothing.

## Rounds

Run it again on the same topic and nothing is overwritten. It shows what is settled and what is open, and builds the next package from the open part only. Each round's analysis is written once and never rewritten; the context document points at them rather than absorbing them, so the words you actually said stay recoverable.

## The resource

Whatever holds the result of an interview. A session record, a file the interviewer wrote into, a requirements document you happen to have, or something you paste. None is more legitimate than the others, and a resource that has nothing to do with the questions can still be worth processing: whatever it already answers is dropped from the open set, and the round you were going to run is offered without it.

Noisy voice records are compressed before analysis, with your say-so, losslessly, and the original is always kept whole.

## Configuration

Nothing is required. With no configuration at all it asks what it needs and writes the answers down. Three settings are shared with your other plugins, because they are useful beyond this one: the language to talk to you in, where your session records live, and how you like to be questioned. Everything else stays in this plugin's own file. See `references/config.md`.

## Where the rules live

- `references/interviewer-prompt.md` — how questions are written, and every rule the generated prompt must carry.
- `references/analysis.md` — classification, ratification, contradictions, and reversals.
- `references/config.md` — every key, and which file it is written to.
- `REQUIREMENTS.md` — the decisions this plugin was built from, and who made each one.
