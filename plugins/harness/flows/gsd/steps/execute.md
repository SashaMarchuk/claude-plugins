Build ticket @TICKET_ID@ with GSD.

1. Run `/gsd-execute-phase <phase>` on the phase that the classification step named.
2. Work stays on @BRANCH@. If GSD names another branch, keep @BRANCH@ and record the difference.
3. Run the repository's own gates (tests, type checks, lint) when GSD is done. Use the exact
   commands the repository documents.

Result: `pass` when every plan is executed and every gate is green. `fail: <reason>` with the
failing command and its output otherwise.
