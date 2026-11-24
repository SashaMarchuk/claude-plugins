The classification step found open questions on ticket @TICKET_ID@. Settle them with GSD.

1. Run `/gsd-discuss-phase <phase> --auto` on the phase that the classification step named.
   Never use an interactive entry point: nobody answers questions in this session.
2. Answer each open question from the repository and the ticket thread, with its source.
3. A question that changes what the user gets, and that the sources do not settle, goes to
   a person.

Result: `pass` when every question is answered. `blocked: <questions>` when one needs a person.
