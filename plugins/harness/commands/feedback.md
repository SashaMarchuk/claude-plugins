---
description: "Report a problem with the harness: shows the full issue text first and files it in the plugin's repository only after your yes."
argument-hint: "[what went wrong, in your own words]"
---

File a problem with the harness as one issue in the plugin's own repository (H-140). Follow these steps exactly.

1. **Get the description.** Use the text in `$ARGUMENTS` as the person's description. If it is empty, ask the person to describe the problem in their own words and wait for the answer. Do not add, guess or rewrite anything; keep their words.

2. **Write it to a file.** Use the Write tool to save the description, as it is, to a new file in your scratchpad or temp folder (for example `feedback-description.md`). Never put the description on a shell command line.

3. **Build the preview.** Run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/harness" feedback preview "<description file>"
   ```

   It sends nothing. It prints the full issue text, then a `DRAFT <folder>` line and a `CODE <code>` line. If it exits non-zero, show its error to the person and stop.

4. **Show the full text.** Show the person everything the command printed above the `DRAFT` line, word for word, in a code block. Do not shorten or edit it. It says which repository gets the issue and that the issue is filed under their own GitHub login.

5. **Ask for a yes.** Ask one question: "Send this issue?" with the answers "Yes, send it" and "No, don't send". Anything other than a clear yes means no: say that nothing was sent, and stop. If the person wants changes, go back to step 2 with their new words.

6. **Send only after a yes.** Run, with the folder and code from step 3:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/harness" feedback send --draft "<folder>" --code "<code>" --yes
   ```

   Pass `--yes` only after the person said yes in step 5. On success it prints `OK filed <issue link>`; give the person that link. On an error, show it; the draft stays in place.
