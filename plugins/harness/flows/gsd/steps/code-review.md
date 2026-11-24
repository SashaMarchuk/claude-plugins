Review the change for ticket @TICKET_ID@ with GSD.

1. Run `/gsd-code-review <phase> --fix --auto` on the phase that the classification step named.
2. Read the review file it writes. Each finding must be fixed or declined with a reason.
3. Run the repository's gates again after the fixes, and commit on @BRANCH@.

Result: `pass` when no finding is left open. `fail: <reason>` when one stays open.
