#!/usr/bin/env bash
# adapter.sh — dispatch source operations to the universal connector skill.
#
# Usage:
#   adapter.sh <run-path> <operation> [args...]
#
# The universal connector reads <run-path>/connector.md to determine how to
# execute the requested operation. Source type is NOT hardcoded here — it's
# a property of each run's connector.md.

set -euo pipefail

run_path="${1:?run-path required}"
op="${2:?operation required (enumerate|sample_schema|execute_query|resolve_refs|citation_anchor|forbidden_fields)}"
shift 2

connector_spec="$run_path/connector.md"
[[ -f "$connector_spec" ]] || {
  echo "ERROR: no connector.md at $connector_spec" >&2
  echo "       Run: /ultra-analyzer:connector-init $run_path" >&2
  echo "       Or copy a template: cp \$(dirname \$(dirname \$0))/templates/connectors/<type>.md $connector_spec" >&2
  exit 2
}

bindir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$bindir")

# Route every operation through the universal connector skill.
# The connector reads <run-path>/connector.md and follows its instructions for <op>.
exec claude --plugin-dir "$plugin_dir" --print "/ultra-analyzer:connector $run_path $op $*"
