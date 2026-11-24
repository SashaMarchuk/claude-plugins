Build ticket @TICKET_ID@ by following the plan from the planning step.

1. Work one task at a time, in plan order.
2. For new behaviour, write the test first and see it fail, then make it pass.
3. Run the repository's own gates (tests, type checks, lint) after each task. Use the exact
   commands the repository documents.
4. Commit each task on @BRANCH@ with a message that says what changed and why.
5. If the plan turns out wrong, stop and report it. Do not change the scope by yourself.

Result: `pass` when every task is done and every gate is green. `fail: <reason>` with the
failing command and its output otherwise.
