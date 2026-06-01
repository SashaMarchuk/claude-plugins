#!/usr/bin/env bash
# sink-adapter.sh - dispatch SINK operations to the universal sink skill.
#
# Usage:
#   sink-adapter.sh <run-path> <operation> [args...]
#
# Operations (SPEC §5.2, the 7-op SINK contract):
#   prepare | dedupe_probe | create_project | seed_unit
#   | finalize_unit | finalize_run | rate_limit_check
#
# The universal sink skill reads <run-path>/sink-connector.md to determine HOW
# to execute the requested operation. The sink type is NOT hardcoded here - it
# is a property of each run's sink-connector.md. This keeps the plugin
# sink-agnostic: the copy-page floor and the optional browser accelerator are
# both just sink-connector.md contracts, with no change to this script.

set -euo pipefail

run_path="${1:?run-path required}"
op="${2:?operation required (prepare|dedupe_probe|create_project|seed_unit|finalize_unit|finalize_run|rate_limit_check)}"
shift 2

connector_spec="$run_path/sink-connector.md"
[[ -f "$connector_spec" ]] || {
  echo "ERROR: no sink-connector.md at $connector_spec" >&2
  echo "       Run: /claude-migrate:init <run-name>  (copies a sink template)" >&2
  echo "       Or copy a template: cp \$(dirname \$(dirname \$0))/templates/sinks/<mode>.md $connector_spec" >&2
  exit 2
}

bindir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$bindir")

# Route every operation through the universal sink skill. The skill reads
# <run-path>/sink-connector.md and follows its instructions for <op>.
exec claude --plugin-dir "$plugin_dir" --print "/claude-migrate:sink $run_path $op $*"
