#!/usr/bin/env bash
# limits.sh — subscription rate-limit awareness. Pause, don't stop (DESIGN.md §6).
# Usage:
#   limits.sh snapshot          # raw usage API JSON (or "UNREADABLE")
#   limits.sh verdict           # one line: VERDICT=OK|PAUSE|UNKNOWN SESSION=<pct> WEEKLY=<pct> UNTIL=<iso>
#   limits.sh wait              # block until the pause clears (API resets_at + margin); STOP-aware
# Token source: macOS Keychain first (the credentials file goes stale after refresh — L6),
# then ~/.claude/.credentials.json. 401/null = UNKNOWN, never OK-by-default (policy decides).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh"

token() {
  # Meter the ACTIVE account, not just the machine default (review MEDIUM). If an account
  # switcher is configured, apply its env first so CLAUDE_CONFIG_DIR points at that account's
  # credentials; then prefer the config-dir file, then the Keychain (fresh after a switch),
  # then the default file. Any provided CLAUDE_CODE_OAUTH_TOKEN wins outright.
  local ec blob t cfgdir="${CLAUDE_CONFIG_DIR:-}"
  # meter the role's actual account when a per-role override is active (HARNESS_ROLE is set by the
  # spawn rate-gate), else the shared account (review MEDIUM — M3 metering).
  ec=""
  [ -n "${HARNESS_ROLE:-}" ] && ec=$(cfg ".accounts.$HARNESS_ROLE.env_command" '')
  [ -n "$ec" ] || ec=$(cfg '.accounts.env_command' '')
  if [ -n "$ec" ]; then
    local envout; envout=$($ec 2>/dev/null || true)
    case "$envout" in
      *CLAUDE_CODE_OAUTH_TOKEN=*) t=$(printf '%s\n' "$envout" | sed -n 's/.*CLAUDE_CODE_OAUTH_TOKEN=["'\'']\{0,1\}\([^"'\'' ]*\).*/\1/p' | head -1); [ -n "$t" ] && { printf '%s\n' "$t"; return 0; } ;;
    esac
    case "$envout" in *CLAUDE_CONFIG_DIR=*) cfgdir=$(printf '%s\n' "$envout" | sed -n 's/.*CLAUDE_CONFIG_DIR=["'\'']\{0,1\}\([^"'\'' ]*\).*/\1/p' | head -1) ;; esac
  fi
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && { printf '%s\n' "$CLAUDE_CODE_OAUTH_TOKEN"; return 0; }
  if [ -n "$cfgdir" ] && [ -f "$cfgdir/.credentials.json" ]; then
    t=$(jq -r '.claudeAiOauth.accessToken // empty' "$cfgdir/.credentials.json" 2>/dev/null)
    [ -n "$t" ] && { printf '%s\n' "$t"; return 0; }
  fi
  blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
  t=$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  [ -n "$t" ] && { printf '%s\n' "$t"; return 0; }
  t=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
  [ -n "$t" ] && { printf '%s\n' "$t"; return 0; }
  return 1
}

snapshot() {
  local t j
  t=$(token) || { echo "UNREADABLE"; return 1; }
  j=$(curl -sS --max-time 20 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $t" -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null) || { echo "UNREADABLE"; return 1; }
  # an auth error body is JSON too — require the limits[] array to call it readable
  if printf '%s' "$j" | jq -e '.limits | type == "array"' >/dev/null 2>&1; then
    printf '%s\n' "$j"
  else
    echo "UNREADABLE"; return 1
  fi
}

verdict() {
  local j sess weekly sess_reset weekly_reset p_sess p_week v until reason
  j=$(snapshot) || { echo "VERDICT=UNKNOWN SESSION=? WEEKLY=? UNTIL="; return 0; }
  sess=$(printf '%s' "$j"        | jq -r '[.limits[] | select(.group=="session") | .percent] | max // 0')
  weekly=$(printf '%s' "$j"      | jq -r '[.limits[] | select(.group=="weekly")  | .percent] | max // 0')
  sess_reset=$(printf '%s' "$j"  | jq -r '[.limits[] | select(.group=="session")] | sort_by(.percent) | reverse | .[0].resets_at // empty')
  weekly_reset=$(printf '%s' "$j"| jq -r '[.limits[] | select(.group=="weekly")]  | sort_by(.percent) | reverse | .[0].resets_at // empty')
  p_sess=$(cfg '.limits.pause_next_spawn_at' '90')
  p_week=$(cfg '.limits.weekly_pause_at' '99')
  # percent is a JSON number and may be fractional (e.g. 91.7); integer `[ -ge ]` would error and,
  # with 2>/dev/null, silently take the no-pause branch (review MEDIUM). Compare numerically.
  ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0>=b+0)}'; }
  v=OK; until=""; reason=""
  if [ "$p_sess" != "null" ] && ge "$sess" "$p_sess"; then v=PAUSE; reason=session; until="$sess_reset"; fi
  if [ "$p_week" != "null" ] && ge "$weekly" "$p_week"; then
    # weekly pause wins only if it is the tighter constraint (session pause already implies waiting)
    if [ "$v" = "OK" ]; then v=PAUSE; reason=weekly; until="$weekly_reset"; fi
  fi
  echo "VERDICT=$v SESSION=$sess WEEKLY=$weekly REASON=$reason UNTIL=$until"
}

wait_clear() {
  local margin line v until epoch now left
  margin=$(cfg '.limits.resume_margin_seconds' '90')
  while :; do
    stop_requested && { hlog "limits.wait: STOP requested — aborting wait"; return 75; }
    line=$(verdict)
    v=$(printf '%s' "$line" | sed -n 's/.*VERDICT=\([A-Z]*\).*/\1/p')
    case "$v" in
      OK) hlog "limits.wait: clear ($line)"; return 0 ;;
      UNKNOWN)
        if [ "$(cfg '.limits.on_unreadable' 'proceed')" = "proceed" ]; then
          hlog "limits.wait: usage API unreadable — proceeding per config"; return 0
        fi
        hlog "limits.wait: usage API unreadable — holding 300s per config"; sleep 300; continue ;;
      PAUSE)
        until=$(printf '%s' "$line" | sed -n 's/.*UNTIL=\([^ ]*\).*/\1/p')
        epoch=$(iso_to_epoch "$until"); now=$(now_epoch)
        if [ -z "$epoch" ]; then hlog "limits.wait: unparsable reset '$until' — sleeping 600s"; sleep 600; continue; fi
        left=$(( epoch + margin - now ))
        [ "$left" -le 0 ] && left=30
        hlog "limits.wait: PAUSED ($line) — sleeping ${left}s until reset+${margin}s"
        # sleep in ≤300s slices so STOP stays responsive
        while [ "$left" -gt 0 ]; do
          stop_requested && { hlog "limits.wait: STOP during pause"; return 75; }
          if [ "$left" -gt 300 ]; then sleep 300; left=$((left-300)); else sleep "$left"; left=0; fi
        done ;;
    esac
  done
}

case "${1:?usage: limits.sh snapshot|verdict|wait}" in
  snapshot) snapshot ;;
  verdict)  verdict ;;
  wait)     wait_clear ;;
  *) echo "usage: limits.sh snapshot|verdict|wait" >&2; exit 64 ;;
esac
