# The built-in interview method

The fallback used when no interview method is configured and none is available. It is deliberately small: the plugin ships enough to work alone, not a rival to a dedicated method.

## The shape

Model the subject as a tree of decisions. A decision branches into the decisions that hang off it.

Work in **rounds**. Each round asks everything whose prerequisites are already settled: the questions answerable now, without guessing at answers not yet heard.

1. Ask that whole set in one round. Number each question. Give your recommended answer to every one.
2. Stop and wait. Never answer on the user's behalf.
3. Their answers reshape the tree. Settled decisions unblock questions that depended on them.
4. Recompute what is now askable and run the next round.
5. Stop when nothing askable is left.

A question whose answer depends on another question still open in this round belongs to a later round, not this one.

## Facts are yours, decisions are theirs

When a question needs a fact from the environment, go and find it rather than asking. Do not stall the round on it: everything downstream of that fact waits, everything else is asked now.

Decisions are never yours. Put each one to the user and wait.

## Question quality

Every question follows `references/interviewer-prompt.md`: plain language, opens with why it is being asked, carries a concrete case, and states a recommendation the user is invited to overturn.

## Done

The grill is done when nothing askable remains. Do not write the package until the user confirms you have reached a shared understanding.
