Check the user interface if ticket @TICKET_ID@ changes it.

1. Decide from the diff whether the change touches anything a user sees: pages, screens,
   components, styles, or text shown in a browser or app.
2. If it does not, write `no UI change` with the reason, and pass.
3. If it does, start the app the way the repository documents, open each changed screen in
   a browser and use it as a user would. Check that it loads, looks right and does what the
   ticket asks.
4. Save what you saw, such as screenshots or a short log, and name each file in the result.

Result: `pass` when every changed screen works. `fail: <reason>` when one does not, or when
the check cannot run.
