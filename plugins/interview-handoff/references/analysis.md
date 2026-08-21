# Analysing what came back

## What an answer is matched to

By default no written question exists: the plugin wrote **open items** and the interviewer worded the questions live. So an answer is matched to its **item**, not to a sentence.

Two anchors, in this order. The interviewer names the item id aloud in each confirmation and reads the list back at the end, so **match on the stated id first**. Fall back to matching on meaning only where an id is missing, and say in the analysis which items were matched that way, because those are the ones most likely to be wrong.

An item nobody named and nobody discussed is `untouched`. That is what makes the open set countable and the next round buildable.

## Classify every question

Five labels, as a recommendation rather than a closed set. Add one of your own when there is a real reason, and say why you added it.

| Label | When |
|---|---|
| settled | A clear answer you can build from. |
| partial | Answered, but something load-bearing is missing: a number, a condition, an exception, what happens on failure. Name exactly what is missing. |
| untouched | Not asked, or asked and not answered. |
| premise rejected | They denied the question's premise rather than answering inside it. |
| deferred | They put it off on purpose, and said so. |

Two labels carry more than they look like.

**Premise rejected is not a missing answer.** It means the question was broken, and usually the requirement underneath it is broken the same way. In real use these produced the largest decisions in the whole corpus. Never file one as untouched.

**Partial is not a soft settled.** "Yes, that sounds right" said to a recommendation is settled. "Something like that", with no detail, is partial. Be strict about the difference.

## Ratification: did they actually say yes

An interviewer restating something is not the person deciding it. In one real session, four of eight closures were the interviewer saying "so I am recording it as..." followed by "great, recorded" with no word from the person in between.

So every recorded answer carries how it was confirmed:

- **confirmed**: they said yes to the restatement.
- **not ratified**: the interviewer formulated it and moved on without a yes, or they asked for a repeat and never got one.

A `not ratified` item is never treated as settled. It goes into the next package as a short ratification block at the very front: the sentence as recorded, and a yes-or-a-correction. That block is quick, and it comes before the new questions.

## Later beats earlier, inside one resource too

People reverse themselves mid-session, deliberately, out loud. Look for the marks: "ignore what I just said", "do not write that down yet", "actually, no", "that is my final word".

- Record both versions. Mark which is final and which is withdrawn.
- The later one is the requirement. The withdrawn one is kept as a struck line so the change is visible as a change.
- When it is genuinely unclear which came last, that is `partial`, not a guess.

## Decisions that arrive outside any question

The largest decisions often are not answers to anything asked. Somebody starts talking and rewrites a whole model.

Sweep for these separately from the question matching. Anything that reads as a decision, a constraint, a rejection or a rule goes into the analysis as its own item, with the verbatim words, whether or not it maps to a question.

## Closures that cascade

One answer often settles other questions that were never asked. Check the whole open set against each new answer, not only the question it was aimed at. Say which question closed which, and on whose words.

The reverse also happens: an answer can break a question's premise, so a question still on the list is now invalid. Mark it rather than asking it again.

## Contradictions

Check each new answer against everything already recorded, including earlier answers in the same resource. A contradiction is not resolved here, ever. Present it as a choice: what collides, which side is newer, the concrete case where both cannot hold, and the question to put to them.

Where the source material carries speaker labels, treat an unattributable segment as a flag, not a guess. Attributing the interviewer's words to the person fabricates a decision at the highest level of authority the record has.

## Resource trust

Ask once per resource: can everything here be taken as source of truth, or does it need further confirmation? Record the answer with the analysis, permanently.

A resource marked as needing confirmation can narrow a question but cannot settle one. Its answers cap at `partial`.

## Writing it out

- One analysis file per round. **Never rewritten.** The context document points at it.
- Verbatim quotes in the language they were said, always.
- Say plainly what each new answer cancels, and what that cancelled thing used to say.
- Where something is unknown, write that it was not said. Do not fill it in.

A long session produces a large analysis. Work it in parts rather than trying to hold all of it at once, and keep the parts in the resource's own order.

## Why there is no answers file by default

An interviewer told to write its answers into a file wrote nothing, twice, across two full sessions, with explicit instructions both times. The session record was the only thing that survived on both occasions.

So the answers file is off unless the user turns it on. When they do turn it on, it stops being a convenience and becomes the resource: that is the file `collect` reads, and nothing else needs looking for.
