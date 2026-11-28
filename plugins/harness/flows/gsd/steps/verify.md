Verify ticket @TICKET_ID@ with GSD's verifier.

1. Start the `gsd-verifier` agent on the phase that the classification step named. Do not use
   `/gsd-verify-work`: it is a conversation and waits for answers.
2. Read the verification file it writes. Every acceptance check of the ticket must be shown
   as met, with evidence.
3. A `gaps_found` or `human_needed` item is not a pass. Report it.

Result: `pass` when the verifier finds no gap. This step does not replace the independent
validator, which runs after it.
