Plan ticket @TICKET_ID@ with GSD.

1. Run `/gsd-plan-phase --auto` with the phase number that the classification step named.
2. Check that every acceptance check of the ticket maps to a task in the plan. If one does
   not, run the plan step again with the missing check named.
3. If GSD stops on a decision it cannot take alone, report it as blocked. Do not force it.

Result: `pass` when the plan exists and covers every acceptance check.
