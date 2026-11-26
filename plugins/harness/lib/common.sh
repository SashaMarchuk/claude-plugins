# shellcheck shell=bash
# Shared helpers for the Harness Orchestrator engine. Sourced by bin/harness.
# Requires HO_ROOT (the plugin root) to be set.

ho_die() {
  printf 'harness: %s\n' "$*" >&2
  exit 1
}

# Print the version from the plugin manifest.
ho_version() {
  local manifest="$HO_ROOT/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || ho_die "manifest not found: $manifest"
  jq -er '.version' "$manifest" || ho_die "manifest has no version"
}

# ho_group_start <cmd...>: start cmd in the background as the leader of its own process group,
# so it and every child it starts can be stopped together. Sets HO_GROUP_PID. Stdin, stdout and
# stderr are the caller's to redirect around the call.
ho_group_start() {
  local had_m=0
  case $- in *m*) had_m=1 ;; esac
  set -m
  "$@" &
  HO_GROUP_PID=$!
  [ "$had_m" -eq 1 ] || set +m
}

# ho_group_stop <pid>: stop what ho_group_start started. TERM, then KILL after 2 s. The signal
# goes to the process group only when its ID is exactly <pid> and is not our own group;
# otherwise only to <pid>. Never by name (H-103). Reaps the process.
ho_group_stop() {
  local pid=$1 target=$1 pg own i=0
  pg=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
  own=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')
  if [ -n "$pg" ] && [ "$pg" = "$pid" ] && [ "$pg" != "$own" ]; then target="-$pid"; fi
  kill -TERM -- "$target" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  # The leader may be gone while a child of its group lives on; KILL the group in any case.
  kill -KILL -- "$target" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
