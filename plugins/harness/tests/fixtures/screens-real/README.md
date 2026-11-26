# Real screen layout fixtures (issue #104)

These files hold the layout of a real Claude Code screen, as `tmux capture-pane -p -e` shows it.
They are styled: the colour codes are kept, because the delivery reader reads a styled capture.
`t_screen.sh` removes the colour codes before it classifies a file. `t_deliver.sh` shows a file
as it is. No test prints a file.

## Where they come from

Each shape was read from captures of one real Claude Code session, read only. No key was sent
to that session, and its pane was never resized. The pane was 64 columns wide.

Kept from the real captures, byte for byte:

- the rule line above and below the input box (the colour code and 64 rule characters);
- the prompt line of an idle session: the prompt mark, then a no-break space (U+00A0), not a
  plain space;
- the prompt line of a busy session: the same, in a dim colour. Every busy capture had this
  colour and every idle capture had the default one, so the colour shows a busy session at
  any width;
- the right-aligned notification line glued to the top rule (`idle-notification.txt`);
- the second status line, idle (it ends with the agents hint) and busy (it ends with the busy
  hint, cut short with "…" at this width);
- the colour layout of the first status line and of the agent list.

Replaced, so that no conversation or account detail is in a public file:

- every line above the box is neutral filler;
- the first status line keeps its shape (model, effort, bar, percentage, tokens, branch,
  folder), but the folder name, the percentage and the token count are neutral, at the same
  widths;
- the task count in the second status line is neutral, at the same width;
- agent names, task text and timers in the agent list are neutral, with the same columns.

## Built, not captured

These states never showed on the real pane, so they were built by editing a real capture's
lines:

- `draft-one-line.txt`, `draft-multi-line.txt`, `draft-separator-only.txt`, `busy-draft.txt`:
  the text in the box is written in. Whether the runtime keeps the no-break space before typed
  text is not known; these files keep it.
- `busy-cut-before-hint.txt`: the second status line cut before the busy hint, as a pane a
  little narrower than 64 columns, or a longer line, would show it. Only the dim prompt shows
  that the session is busy.
- `idle-notification.txt`: the real notification line is kept, but in the real capture a
  tip card of the runtime sat above it; that card is left out (see "Not covered").
- `wide-idle-full.txt`, `wide-busy-full.txt`: the rule lines are widened to 120 columns, and the
  busy hint is written in full. Only a 64-column pane was observed.
- The T14 cases (a limit notice, a trust dialog or a password prompt above the real box) are
  not saved here. The tests splice the fixtures of `../screen` into these files by script.
  The real limit notice is still the deferred check of issue #82.

## What the readers need from these shapes (PR #105 review round 1)

- Delivery types only when idle is proven: the prompt shows the idle colour. A missing busy
  mark proves nothing, because a narrow pane can cut the busy hint off.
- So a capture without colour codes never gets typed text. **On iTerm2 delivery never types**:
  the iTerm2 backend returns plain text, so idle cannot be proven there. Sessions run in tmux by
  default (D42b); on iTerm2 the message route is the only route.
- Under the box only status-area lines may sit: the line right under the box (the runtime's
  or the user's own status line), the permission-mode line, the shortcuts hint and the agent
  list. Any other line there gets nothing typed.

## Not covered

- A tip card of the runtime (a few lines with numbered answers) can sit right above the
  box. A notice above that card is not recognised. The card goes away once it is answered.
- Dim suggested text in the box, other widths than 64 columns, and a real limit notice were
  not seen on the real pane.

## Files

| File | State |
|---|---|
| `idle-box-only.txt` | idle, empty box, nothing under it |
| `idle-status.txt` | idle, empty box, the two status lines |
| `idle-full.txt` | idle, empty box, status lines and agent list |
| `busy-status.txt` | busy, status lines |
| `busy-full.txt` | busy, status lines and agent list |
| `draft-one-line.txt` | a one-line draft (built) |
| `draft-multi-line.txt` | a two-line draft (built) |
| `draft-separator-only.txt` | an empty prompt line, then a short rule line typed in the box (built) |
| `busy-draft.txt` | busy, with a draft (built) |
| `busy-cut-before-hint.txt` | busy, status line cut before the busy hint (built) |
| `idle-notification.txt` | idle, with the runtime's notification line above the box |
| `wide-idle-full.txt` | idle at 120 columns (built) |
| `wide-busy-full.txt` | busy at 120 columns (built) |
