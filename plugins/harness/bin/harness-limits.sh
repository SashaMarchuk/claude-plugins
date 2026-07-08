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
  local blob t
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
  p_week=$(cfg '.limits.weekly_pause_at' 'null')
  v=OK; until=""; reason=""
  if [ "$p_sess" != "null" ] && [ "$sess" -ge "$p_sess" ] 2>/dev/null; then v=PAUSE; reason=session; until="$sess_reset"; fi
  if [ "$p_week" != "null" ] && [ "$weekly" -ge "$p_week" ] 2>/dev/null; then
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
