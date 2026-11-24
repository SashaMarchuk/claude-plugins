Check the user interface if ticket @TICKET_ID@ changes it.

1. Decide from the diff of @BRANCH@ against @BASE@ whether the change touches anything a
   user sees. If it does not, write `no UI change` with the reason, and pass.
2. If it does, run `/gsd-ui-review` with the phase number that the classification step named,
   then open each changed screen in a browser and use it as a user would.
3. Save what you saw and name each file in the result.

Result: `pass` when every changed screen works. `fail: <reason>` when one does not, or when
the check cannot run.
