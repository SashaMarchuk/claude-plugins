#!/usr/bin/env bash
# task-launch: open ONE new iTerm2 session in <folder> and start the coding tool
# seeded with a prompt file. A tab in the current window when one exists,
# otherwise a single fresh window — never an extra empty tab.
# Usage: launch_terminal.sh <folder> <prompt_file> [tool]
#   tool: CLI to run (default: claude). A single command name, no arguments;
#         it must accept the starter prompt as its first argument.
# The starter prompt is read from a file (never passed on the command line) so
# multi-line content and quotes survive intact. Always starts a FRESH session.
set -euo pipefail

FOLDER="${1:?usage: launch_terminal.sh <folder> <prompt_file> [tool]}"
PROMPT_FILE="${2:?usage: launch_terminal.sh <folder> <prompt_file> [tool]}"
TOOL="${3:-claude}"

[ -d "$FOLDER" ]      || { echo "task-launch: folder not found: $FOLDER" >&2; exit 1; }
[ -f "$PROMPT_FILE" ] || { echo "task-launch: prompt file not found: $PROMPT_FILE" >&2; exit 1; }

# Build a tiny self-deleting runner with the paths baked in shell-quoted (%q),
# so folders containing spaces/quotes/$ survive. It reads the prompt from the
# file at runtime and execs the tool with it as the first message.
RUNNER="$(mktemp -t task-launch-runner)"
{
  printf '#!/usr/bin/env bash\n'
  printf 'rm -f -- "$0"\n'
  printf 'cd %q || exit 1\n' "$FOLDER"
  printf 'PROMPT="$(cat %q)"\n' "$PROMPT_FILE"
  printf 'exec %q "$PROMPT"\n' "$TOOL"
} > "$RUNNER"
chmod +x "$RUNNER"

# One new session: reuse the current window (new tab) if one exists, else create
# a single window whose initial session is used directly — no stray tab.
osascript <<OSA || { echo "task-launch: could not drive iTerm2 — check System Settings → Privacy & Security → Automation" >&2; exit 1; }
tell application "iTerm2"
  activate
  if (count of windows) = 0 then
    create window with default profile
  else
    tell current window to create tab with default profile
  end if
  tell current session of current window
    write text "bash '$RUNNER'"
  end tell
end tell
OSA

echo "task-launch: launched a fresh $TOOL session in $FOLDER"
