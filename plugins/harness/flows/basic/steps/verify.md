Prove that ticket @TICKET_ID@ does what it asks, on the code as it is now committed.

1. Take each acceptance check of the ticket, one by one.
2. Run the command or test that proves it. Do not rely on an earlier step's output.
3. Run the repository's full gates once more on a clean tree.
4. For each check, write the command, its result and whether it passes.
5. A check you cannot run is not passed. Name it and say why it cannot run.

Result: `pass` when every acceptance check passes with evidence. `fail: <reason>` otherwise.
This step does not replace the independent validator, which runs after it.
