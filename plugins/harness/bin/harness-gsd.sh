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
  # gsd MCP is configured if a server named gsd exists in the user or project mcp config
  jq -e '.mcpServers.gsd // empty' "$HOME/.claude.json" >/dev/null 2>&1 && return 0
  local pj; pj=$(hproject_root 2>/dev/null) || return 1
  jq -e '.mcpServers.gsd // empty' "$pj/.mcp.json" >/dev/null 2>&1
}

gsd_cli() { # locate the real gsd-tools CLI (the live capability registry lives here)
  local c
  for c in "$HOME/.claude/gsd-core/bin/gsd-tools.cjs" "$(command -v gsd-tools 2>/dev/null)"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

case "${1:?usage: harness-gsd.sh discover|present}" in
  discover)
    echo "# GSD surface discovered at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "# Preference order for a harness: (1) mcp__gsd__* tools — a separately-versioned API"
    echo "#   contract, the MOST drift-resistant; (2) 'gsd-tools capability list' — the live"
    echo "#   registry; (3) the skill names below. NOTE: /gsd-help is a hand-maintained static"
    echo "#   catalog, not live introspection — don't rely on it to know what's installed."
    if mcp_present; then echo "mcp: gsd MCP configured — prefer mcp__gsd__* (gsd_progress, gsd_status, gsd_roadmap, gsd_execute, gsd_doctor, gsd_*_plan/_complete)"; else echo "mcp: not detected in config, but check your own tool list for mcp__gsd__* and prefer them if present"; fi
    if cli=$(gsd_cli); then
      echo "live-registry: $cli capability list   (JSON: id/role/version/status/title per capability)"
    else
      echo "live-registry: gsd-tools CLI not found — fall back to the skill list below"
    fi
    skills=$(gsd_skills)
    if [ -n "$skills" ]; then echo "skills:"; printf '  /%s\n' $skills; else echo "skills: none found — GSD may not be installed."; fi
    ;;
  present)
    [ -n "$(gsd_skills)" ] || mcp_present
    ;;
  *) echo "usage: harness-gsd.sh discover|present" >&2; exit 64 ;;
esac
