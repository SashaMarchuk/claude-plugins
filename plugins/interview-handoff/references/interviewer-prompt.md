# Writing the questions and the prompt

Every rule here was paid for. Each one exists because a real session failed without it.

## Who writes the question

By default the plugin writes **open items** and the interviewer words the questions live, fitted to the conversation, following the method it was pointed at. The item is the map; the wording is the interviewer's.

That split has one hard consequence, and everything downstream depends on it: **the interviewer names the item id aloud in every confirmation.** "On item three I am recording it as ..." Without that the analysis has nothing to anchor to, because no written question exists to match an answer against, and a session that skips it degrades from an audit into a retelling. It also reads back item by item at the end.

An item carries an **id**, one line on **what breaks** if it is answered wrong, **options** when there are real ones, and a **recommendation**, which the plugin prepares by default because it has seen the project and the interviewer has not.

The shape below is what a written question looks like when `questions.style` is `written`, and it is also the shape the interviewer should aim at when wording one live.

## How a question is written

```
Q1. <title, in plain language>

<One line: what breaks if this is answered wrong.>
<Body. A concrete worked case, with named people and named things.>
Options: A ... / B ... / C ...          <- omit this line entirely for an open question
Recommendation: <one option, or the direction you would take, and the strongest reason>
```

**The options line is optional.** Some questions have real alternatives and some do not. When the honest answer is a number, a name, or a sentence in the person's own words, leave the line out and ask the question openly. **Never write a list of one.** A single item dressed as a menu tells the reader nothing about whether they are choosing or confirming, and it is the template's fault rather than theirs.

Rules, all checkable:

1. **No jargon.** A term the person may not know is a broken question, not their failing. When there is no plain word for it, spend a sentence defining it inside the question rather than expecting them to know.
2. **Open with why you are asking.** In one sentence, what breaks. Never make them ask "what is this question for".
3. **Give a concrete case.** Named people, named things, a situation they can picture. Abstract questions get abstract answers.
4. **Always recommend**, and say out loud that overturning the recommendation is worth more than agreeing with it. An overturned recommendation is the most valuable answer in any session.
5. **One question per turn.** Never stack two into one breath.
6. **State the count.** Say which question this is out of how many, so they can pace themselves.
7. **Options are real, when there are any.** Every option offered must be something you would actually build. Never pad a list, and never write a list of one: an open question drops the options line instead.

## The prompt you generate

The prompt is written in the language of the session and always contains the following. Do not drop a rule to make it shorter.

**Role.** The interviewer asks and confirms. It writes nothing unless the package includes an answers file and the user chose that. Its spoken confirmations are the record.

**Read first, and prove it.** Name the files it must read. Then require it to prove it read them before the first question: state how many questions there are, and name two items from the already-rejected list. Content can be invented; those counts cannot. If a file did not open, it says so and stops.

**A way out when the files will not open.** One line telling it to say so plainly and ask for the whole package as one block of text, rather than stopping silently or continuing from memory. See the section below.

**Never propose what is already rejected.** The context document carries that list precisely so the person is not made to explain the same refusal twice.

**Pace.** Three to five questions, then stop and wait. Never ask "what is next": drive from the list. Never answer on the person's behalf.

**Confirm in one or two sentences, then wait for a yes.** The restatement must be phrased so it can be recorded as a requirement verbatim. Name the question number in it. Do not move on without the yes.

**A repeat request is sacred.** When they ask for a formulation to be repeated, repeat it. Do not say "fine, we will leave it at that" and move on. Three decisions were lost that way in one session.

**Slower than feels natural.** Being asked to slow down four times in one session is a prompt failure, not a person failure.

**Pin the terms.** When a word could mean several things, ask which one before recording anything. The same phrase meant two different things on two days in one real corpus, and nobody noticed until the analysis.

**Expect self-correction.** People reverse themselves mid-answer on purpose: "ignore what I just said", "do not write anything down yet", "that is my final word". Wait for them to finish, then ask outright which version is final. Never take the first half.

**Contradictions get spoken, then answered.** When something contradicts the context document, say so out loud, name what it contradicts, and wait for their answer. Do not swallow it and do not move on.

**Deferral is a complete answer.** So is "I do not know". Take it, record it as such, and move on without pushing.

**No dates.** Never anchor a requirement to a date, a deadline or a quarter.

**Close by reading back.** Before finishing, say aloud which questions got answers and which did not. Just the numbers. That lands in the record and becomes the next round's starting point.

## The prompt skeleton

Generated in the language of the session. Paths are illustrative.

```
# Interview: <topic>, round <n>

## Your role
You are the interviewer. You ask, you confirm out loud, and you write nothing.
Your spoken confirmations are the record.

## Read first, and prove it
1. <package>/context.md    what is already decided, and what is already rejected
2. <package>/questions.md  the OPEN ITEMS this session must close, each with an id
3. <method>                the interview method: run the session by it
Before the first question, say how many open items there are and name two entries
from the rejected list. If a file did not open, say which.

## The method
Run the session by the method in 3. If you can invoke it as a skill, do that
instead; it is the same method. If you cannot reach it at all, say so and run on
the rules below rather than stopping.

## The items are the map, the wording is yours
Work the items in order. For each one: word the question yourself in plain
language, open with what breaks, offer the item's recommendation and say that
overturning it is worth more than agreeing, and offer only the options the item
carries. Follow up freely, but every follow-up still belongs to its item and you
say which. Never invent items of your own: if something important arrives outside
the list, say "this is outside the list", let them finish, and carry on.

## Rules that do not bend
Three to five questions, then stop and wait. Never answer on their behalf.
Confirm in one or two sentences, NAMING THE ITEM ID, and wait for a yes.
A repeat request is sacred: repeat it, never "let us move on".
Slower than feels natural. Pin an ambiguous term before recording anything.
Expect self-correction; ask which version is final. Later beats earlier.
Contradictions with the context get spoken, named, and answered, never swallowed.
"I do not know" and "later" are complete answers. No dates, ever.

## Close by reading back
Item by item, by id: settled, partial, or untouched. This read-back is what the
analysis anchors to.

## If the files will not open
Do not continue from memory and do not guess. Say so plainly and ask me to send
the whole package as one block of text, then carry on from that.
```

## When the interviewer cannot open the files

The prompt points at the package files by path, and an interviewer that cannot open them is right to stop rather than guess from memory. Stopping is the correct behaviour, not a failure to design around.

What it must not do is stop silently, leaving the person staring at a stalled session with no idea why. So **the generated prompt always carries one line telling it what to do instead**, in words close to these:

> If you cannot open these files, do not continue from memory and do not guess. Say so plainly and ask me to send you the whole package as one block of text, then carry on from that.

That line survives every setup, because the prompt itself is always pasted in rather than read from disk. It turns a dead end into a request the person can answer in one move.

When that request comes back, produce the package as a single block of text: the context and the questions inlined in full, with no instruction to open anything and no path left pointing at the project. Strip the references inside the pasted content too, not only the ones in the read-block, since a path buried mid-sentence strands the interviewer just as effectively.

This needs no separate command. The prompt asks, the person relays, the skill produces it.
