#!/usr/bin/env bash
# state.sh — the coordination triad: markers (existence-gates) + heartbeats (liveness) +
# decision/owner logs (audit). Three channels, never one overloaded file (DESIGN.md §1, L18).
# Usage:
#   state.sh marker set <name>            # e.g. "auth-lane.pr-ready"
#   state.sh marker check <name>          # exit 0 if present
#   state.sh marker wait <name> [timeout_s]
#   state.sh heartbeat <session-name> <step...>
#   state.sh heartbeat-age <session-name> # seconds since last beat (or "never")
#   state.sh decision <title> <rationale...>
#   state.sh owner-action <title> <why> <command> <verify>
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh"

RUN=$(hcurrent_run)
MARKERS="$RUN/markers"; HB="$RUN/heartbeats"
mkdir -p "$MARKERS" "$HB"

marker_name_ok() { case "${1:?}" in *[!a-z0-9.-]*|"") echo "ERROR: marker must be a-z0-9.- : $1" >&2; return 65 ;; *) return 0 ;; esac; }

case "${1:?usage: state.sh marker|heartbeat|heartbeat-age|decision|owner-action}" in
  marker)
    sub="${2:?set|check|wait}"; name="${3:?marker name}"; marker_name_ok "$name"
    case "$sub" in
      set)   date -u '+%Y-%m-%dT%H:%M:%SZ' > "$MARKERS/$name.done"; hlog "marker set: $name" ;;
      check) [ -f "$MARKERS/$name.done" ] ;;
      wait)
        timeout="${4:-0}"; waited=0
        while [ ! -f "$MARKERS/$name.done" ]; do
          stop_requested && exit 75
          [ "$timeout" -gt 0 ] && [ "$waited" -ge "$timeout" ] && { echo "TIMEOUT waiting for $name" >&2; exit 73; }
          sleep 30; waited=$((waited+30))
        done ;;
      *) exit 64 ;;
    esac ;;
  heartbeat)
    name="${2:?session name}"; shift 2
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$HB/$name"
    printf '%s\n' "$(date +%s)" > "$HB/$name.epoch" ;;
  heartbeat-age)
    name="${2:?session name}"
    if [ -f "$HB/$name.epoch" ]; then echo $(( $(date +%s) - $(cat "$HB/$name.epoch") )); else echo never; fi ;;
  decision)
    title="${2:?title}"; shift 2
    { printf '\n## %s — %s\n%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$title" "$*"; } >> "$RUN/DECISIONS.md"
    hlog "decision logged: $title" ;;
  owner-action)
    title="${2:?}"; why="${3:?}"; command="${4:?}"; verify="${5:?}"
    { printf '\n### %s\n- **Why:** %s\n- **Command:** `%s`\n- **Verify:** %s\n' "$title" "$why" "$command" "$verify"; } >> "$RUN/OWNER-ACTIONS.md"
    hlog "owner action logged: $title" ;;
  *) echo "usage: state.sh marker|heartbeat|heartbeat-age|decision|owner-action" >&2; exit 64 ;;
esac
