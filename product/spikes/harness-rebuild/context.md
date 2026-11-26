# Harness rebuild — context for the interviewer (round 1)

Read this before the session. **Do not read it aloud.** Use it only when the owner asks what a
question means, why it is being asked, or what a word means — and then answer in one or two
sentences and return to the item.

## What is being designed

An unattended orchestration tool. The owner starts it and leaves; it takes a queue of work items
and drives them to a finished, reviewable state across several agent sessions running at the same
time on his own machine, overnight, without him watching. A version of this tool exists and has
been used on a real project. It is being rebuilt from zero rather than patched.

## What round 1 is for

His own picture of the tool, in his words, at the level of needs — not a review of any design.
Round 1 has two halves:

1. **His account.** He describes what the tool is for and how he sees it working. Let him talk.
   Ask follow-ups. Do not steer him through the item list while he is doing this.
2. **The items.** The open items in `questions.md`, which exist because they are the decisions
   everything else will rest on. If his account already answered an item, say so, confirm what you
   recorded for that item, and move on rather than asking it again.

## Deliberately withheld

**The existing tool's design is not in this package, on purpose.** The point of the rebuild is to
hear what he needs, not to have him ratify what he already built. So:

- Do not ask him to approve, keep or drop any existing mechanism.
- **Do not open anything else in this repository during round 1** — in particular not
  `plugins/harness/`. You have access to the folder tree; this one round is not the time to use it.
- If he brings the old tool up himself, follow him. His account of it is evidence.

## Already rejected — never propose these

1. **Patching the existing tool incrementally.** He has ruled this out; the tool is being rebuilt
   from zero, with what exists treated as evidence rather than as a starting point.
2. **Tying the tool to one workflow engine.** It must work with whatever engine a project uses, or
   none. Do not design around any single one.
3. **Naming a specific vendor or tool inside the tool's own code.** What it talks to is
   configuration, resolved at run time — never hardcoded.
4. **Designing the requirements store in this round.** How answers become requirements is a
   separate track and out of scope here.

## What actually happened in real use

These are facts from a 34-hour unattended run of the existing tool on a real project, plus its
predecessor. They are here so you can answer "why are you asking that" with something concrete.
**They are problems, not solutions — never present any of them as the design to keep.**

**Talking to a running session**
- An instruction typed into a session failed to arrive at least 19 times; it sat on the input line
  unsent. Short single words to an empty input line did land.
- One session sat at 149 minutes of silence while an instruction meant for it was never submitted.

**Sessions that nobody ended or revived**
- A session that had finished its work sat idle for 28 hours 40 minutes; an attempt to close it
  left it open, and a person closed it by hand.
- When the leading session died, nothing revived it: its death was recorded for 301 consecutive
  checks — about 10 hours — with seven ready items untouched.

**Context**
- Nothing in the tool measured how full a session's context was.
- One worker spent 4,416 of its 4,657 tool calls checking whether it was idle, which filled 76% of
  its context with the checking itself and took it to 96% full.
- The rescue was another session typing a compact command in from outside.

**Liveness judged wrongly**
- 33 automatic nudges went to sessions that were healthy and working.
- A shell command that could never finish read as work forever.

**Subscription limits**
- The limit check could not find the credential for the owner's profile, so for whole runs it read
  "unknown" and the pause rule could never fire.
- The weekly reading took the worst of several counters, one of which was stuck at 100%.
- Supervision itself cost quota: the watching session re-read its whole context every cycle.

**Work that looked finished and was not**
- A merge printed "already up to date" and moved nothing; it was caught by checking the branch by hand.
- A killed test run reported 346 passed and read as a clean pass.
- For nine consecutive pieces of work, the session that built the work also signed off on it,
  because an independent check had been skipped; a person found that afterwards.
- One piece of work was merged before its independent check ran.

**The owner's own machine**
- His Docker stack was destroyed by a command run without a project name, two minutes after a
  session had refused the same action.
- His own container was killed for memory while two builds ran at once.
- A broad process kill aimed at test processes killed an unrelated session.
- Two role passwords were printed into a session transcript by a debug trace.

**Throughput and cost**
- Only two pieces of work could ever run at the same time across nineteen, because of dependencies
  between them — not because of any limit the tool set.
- The whole 34-hour run consumed roughly a quarter of a weekly allowance.

**What had to be built outside the tool**
- An LLM session to watch context and revive dead sessions, a supervisor to pause and resume the
  run around the weekly limit, a script to unstick a wedged session, and an email watchdog.

## Other tools that exist

Fourteen comparable open-source tools were surveyed. None covers this whole job; they differ in
whether they cap how much runs at once, react to subscription limits, detect a stalled session by
time, verify work deterministically, or merge on their own. **Do not pitch any of them in this
session** — the owner will get that comparison separately, after this round. If he asks whether
something already exists, say that a comparison is waiting for him and return to the item.

## Words used in the questions

- **Run** — one unattended stretch of work, typically overnight.
- **Queue / work item** — the list of pieces of work waiting to be picked up, and one entry in it.
- **Session** — one running agent, in its own window or process.
- **Leading session** — the one that hands work out and decides what happens next.
- **Context** — how much a session can hold before it must forget or be compacted.
- **Compaction** — squeezing a session's history so it can keep going.
- **Subscription limit** — the 5-hour and weekly caps on how much can be spent.
- **Trunk / main branch** — the branch the finished work ends up on.
- **Independent check** — verification by something other than whatever produced the work.
