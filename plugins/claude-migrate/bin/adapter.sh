#!/usr/bin/env bash
# adapter.sh - dispatch SOURCE operations to the universal source skill.
#
# Usage:
#   adapter.sh <run-path> <operation> [args...]
#
# Operations (SPEC §5.1, the 7-op SOURCE contract):
#   enumerate | extract_unit | extract_projects | unit_project_ref
#   | account_check | citation_anchor | forbidden_fields
#
# The universal source skill reads <run-path>/source-connector.md to determine
# HOW to execute the requested operation. The source type is NOT hardcoded here
# - it is a property of each run's source-connector.md. This keeps the plugin
# source-agnostic: a future provider is an additive templates/sources/*.md plus
# a config interview, with no change to this script.

set -euo pipefail

run_path="${1:?run-path required}"
op="${2:?operation required (enumerate|extract_unit|extract_projects|unit_project_ref|account_check|citation_anchor|forbidden_fields)}"
shift 2

connector_spec="$run_path/source-connector.md"
[[ -f "$connector_spec" ]] || {
  echo "ERROR: no source-connector.md at $connector_spec" >&2
  echo "       Run: /claude-migrate:init <run-name>  (copies a source template)" >&2
  echo "       Or copy a template: cp \$(dirname \$(dirname \$0))/templates/sources/<mode>.md $connector_spec" >&2
  exit 2
}

bindir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$bindir")

# Route every operation through the universal source skill. The skill reads
# <run-path>/source-connector.md and follows its instructions for <op>.
exec claude --plugin-dir "$plugin_dir" --print "/claude-migrate:source $run_path $op $*"
