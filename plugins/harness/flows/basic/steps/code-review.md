Review the full change for ticket @TICKET_ID@: the diff of @BRANCH@ against @BASE@.

1. Read every changed line. Look for bugs, missing error handling, silent failures,
   security problems (injection, secrets, access) and work the ticket did not ask for.
2. Check that the tests prove the behaviour and do not only repeat the code.
3. Check the change against the repository's own rules and conventions.
4. Fix each real problem you find, run the gates again and commit the fix.
5. Write each finding to the step result, with what you did about it and why.

Result: `pass` when no open problem is left. `fail: <reason>` when one stays open.
