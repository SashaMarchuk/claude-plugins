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
