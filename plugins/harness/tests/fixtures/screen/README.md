# Saved screen fixtures

One file is one screen capture, as `harness screen ... classify` reads it. `t_screen.sh`
compares only the class word a file produces, so no test prints a file.

- `limit-notice-*.txt`, `trust-dialog*.txt`, `password-prompt*.txt` must be recognised.
- `n-*.txt` must not be recognised. They are the field-note cases: a session's own prose
  that quotes a notice, a notice wrapped into a paragraph, a boxed dialog pasted into a
  report, a prompt named inside a sentence, an ordinary working screen, a one-line summary
  and a bare phrase that have the shape of a notice but not its words, a two-line summary
  whose last line reads like a notice, a notice without its reset line, a notice pasted inside the first paragraph of a report, and a short last line that a
  pattern with a wrongly read bracket would match.

Two limit fixtures hold the contracted wording, one with the ASCII apostrophe and one with
the typographic one, because a notice may carry either.

**Provenance.** These are reconstructions, not captures of a real run. Their recognisable
lines are built from the patterns the 0.6.0 watch used, which is the only part of that watch
the rebuild keeps; the layout around them is written by hand. A real capture is not used,
because a transcript or a screen can carry secrets (field note I4). So these files prove the
recognition rules and the negative cases, not that the released tool still renders a notice
this way. The product check against a real limit is the deferred task of H-113 and issue #82.

Adding a file: write it with a script, keep the recognisable line inside the file, and add
one assertion in `t_screen.sh` that compares the class word.
