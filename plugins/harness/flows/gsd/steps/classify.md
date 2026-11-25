Decide whether ticket @TICKET_ID@ is described well enough to build without guessing, and
find its GSD phase.

1. Find the phase for this ticket in `.planning/ROADMAP.md`. If none exists, add one with
   `/gsd-phase` and name the ticket in it. Write the phase number in the step result; later
   steps use it.
2. Read the ticket, then the code and docs it touches.
3. List every point the ticket leaves open. A point that the code or the docs answer is not
   open: write down the answer and its source.

Result: `pass` when nothing is open. `questions` when points stay open; list each one with the
readings you see. Change no product code in this step.
