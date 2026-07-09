#!/usr/bin/env bash
# harness-gsd.sh — discover the GSD surface AT RUNTIME so prompts never hardcode command names
# that drift (DESIGN.md §gsd). GSD ships as `/gsd-*` skills and/or `mcp__gsd__*` MCP tools.
# Usage:
#   harness-gsd.sh discover     # print the installed gsd command/skill names + whether MCP is present
#   harness-gsd.sh present       # exit 0 if any GSD surface is installed
# Output is advisory: the worker/orchestrator prompts tell the session to VERIFY names via
# `/gsd-help` before use — this just gives them the current list to start from.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh" 2>/dev/null || true

PLUGINS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"
[ -d "$PLUGINS_DIR" ] || PLUGINS_DIR="$HOME/.claude/plugins"

gsd_skills() {
  # skill dir names under any installed plugin whose name contains 'gsd', plus user/project skills
  {
    find "$PLUGINS_DIR" -type d -path '*gsd*/skills/*' -name '*' 2>/dev/null \
      | sed -E 's|.*/skills/||; s|/.*||'
    find "$HOME/.claude/skills" "$(hproject_root 2>/dev/null)/.claude/skills" -maxdepth 1 -type d 2>/dev/null \
      | sed 's|.*/||' | grep -i '^gsd'
  } 2>/dev/null | grep -iE '^gsd' | sort -u
}

mcp_present() {
  # gsd MCP is configured if any mcp config references a server named gsd
  grep -rlZ '"gsd"' "$HOME/.claude.json" "$(hproject_root 2>/dev/null)/.mcp.json" 2>/dev/null | grep -q . && return 0
  return 1
}

case "${1:?usage: harness-gsd.sh discover|present}" in
  discover)
    skills=$(gsd_skills)
    echo "# GSD surface discovered at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if mcp_present; then echo "mcp: gsd MCP server configured — prefer mcp__gsd__* tools (the drift-resistant programmatic layer)"; else echo "mcp: not detected here, but check your own tool list for mcp__gsd__* — if present, prefer those over skill names"; fi
    if [ -n "$skills" ]; then
      echo "skills:"; printf '  /%s\n' $skills
    else
      echo "skills: none found — GSD may not be installed, or uses a different name. Run /gsd-help or check /plugin."
    fi
    echo "# Always verify current names/usage with the help/index command before invoking."
    ;;
  present)
    [ -n "$(gsd_skills)" ] || mcp_present
    ;;
  *) echo "usage: harness-gsd.sh discover|present" >&2; exit 64 ;;
esac
