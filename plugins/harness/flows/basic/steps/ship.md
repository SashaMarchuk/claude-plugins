Prepare ticket @TICKET_ID@ for shipping. Every earlier step has passed.

1. Make sure the tree is clean and every commit is on @BRANCH@.
2. Write a pull request title and body: what changed, why, how it was tested, and which
   ticket it closes. Put them in the step result.
3. Review the pull request as a reader would: the full diff against @BASE@, the title and the
   body. Fix anything that is wrong or unclear, then commit.
4. Do not push and do not open the pull request yourself. The engine opens it when the
   autonomy profile allows it.

Result: `pass` when the pull request text is written and the review found nothing open.
