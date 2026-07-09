#!/usr/bin/env bash
# harness-guide.sh — advisory: list the project's OWN guidance files so a session reads and follows
# them (push/merge gates, real lint/format/test/build commands, deploy/release process, branch/PR/
# commit conventions, CODEOWNERS / do-not-touch). ADVISORY ONLY — it lists paths, never interprets
# contents (one cheap exception: package.json script NAMES). The LLM reads what this points at.
# Usage:
#   harness-guide.sh discover [repo-path]   # default $PWD (a worker's worktree); orchestrator passes each repo
#   harness-guide.sh present  [repo-path]   # exit 0 if any guidance file exists
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh" 2>/dev/null || true

# default candidates, relative to a repo root
CANDIDATES='
README* CONTRIBUTING* AGENTS.md .cursorrules
Makefile Justfile Taskfile.yml Taskfile.yaml
package.json
.eslintrc .eslintrc.js .eslintrc.json .eslintrc.cjs .prettierrc .prettierrc.json biome.json
ruff.toml pyproject.toml .flake8 setup.cfg .rubocop.yml .golangci.yml
tsconfig.json .editorconfig .pre-commit-config.yaml
.gitlab-ci.yml .circleci/config.yml azure-pipelines.yml
DEPLOY* RELEASE* RUNBOOK*
.nvmrc .tool-versions .python-version .env.example
'

list_found() { # <repo>
  local repo="$1" pat m found=0
  for pat in $CANDIDATES; do
    for m in "$repo"/$pat; do
      [ -e "$m" ] || continue
      printf '  %s\n' "${m#"$repo"/}"; found=1
    done
  done
  # .github gate/convention files (shallow)
  local g
  for g in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md .github/CODEOWNERS; do
    [ -e "$repo/$g" ] && { printf '  %s\n' "$g"; found=1; }
  done
  if [ -d "$repo/.github/workflows" ]; then
    local w n=0
    for w in "$repo"/.github/workflows/*.y*ml; do
      [ -e "$w" ] || continue; printf '  .github/workflows/%s\n' "$(basename "$w")"; found=1; n=$((n+1)); [ "$n" -ge 10 ] && { printf '  .github/workflows/ (…more)\n'; break; }
    done
  fi
  # docs/ — top-level markdown only, capped
  if [ -d "$repo/docs" ]; then
    local d n=0 names=""
    for d in "$repo"/docs/*.md; do
      [ -e "$d" ] || continue; n=$((n+1)); [ "$n" -le 15 ] && names="$names $(basename "$d")"
    done
    [ "$n" -gt 0 ] && { printf '  docs/  (%s files; top:%s)\n' "$n" "$names"; found=1; }
  fi
  # package.json script NAMES (the real task commands) — the one content peek, jq-guarded
  if [ -f "$repo/package.json" ]; then
    local scripts; scripts=$(jq -r '.scripts // {} | keys | join(", ")' "$repo/package.json" 2>/dev/null || true)
    [ -n "$scripts" ] && printf '  package.json  (scripts: %s)\n' "$scripts"
  fi
  return $((1-found))
}

do_discover() {
  local repo="${1:-$PWD}"
  repo=$(cd "$repo" 2>/dev/null && pwd -P) || { echo "ERROR: no such repo path: ${1:-$PWD}" >&2; return 65; }
  echo "# Project guidance discovered at $(date -u '+%Y-%m-%dT%H:%M:%SZ') in $repo"
  echo "# ADVISORY: read these BEFORE working. Extract the push/merge gates, the EXACT lint/format/"
  echo "# test/build commands, how deploy/release works, branch+PR+commit conventions, and"
  echo "# do-not-touch/CODEOWNERS boundaries — then FOLLOW them (they override your defaults)."
  echo "# CLAUDE.md is auto-loaded by Claude Code (already in context) — skip re-reading it."
  local out; out=$(list_found "$repo")
  if [ -n "$out" ]; then echo "found:"; printf '%s\n' "$out"; else echo "found: none — no standard guidance files in this repo."; fi
  # config-listed extras (globs relative to the repo)
  local extra; extra=$(cfg '.guidance.files' '' 2>/dev/null)
  if [ -n "$extra" ] && [ "$extra" != "null" ]; then
    local globs; globs=$(printf '%s' "$extra" | jq -r '.[]?' 2>/dev/null || true)
    if [ -n "$globs" ]; then
      echo "config-listed:"; local gl m
      while IFS= read -r gl; do [ -n "$gl" ] || continue; for m in "$repo"/$gl; do [ -e "$m" ] && printf '  %s\n' "${m#"$repo"/}"; done; done <<< "$globs"
    fi
  fi
  local notes; notes=$(cfg '.guidance.notes' '' 2>/dev/null)
  [ -n "$notes" ] && [ "$notes" != "null" ] && echo "notes: $notes"
  [ -e "$repo/CLAUDE.md" ] && echo "already-loaded (skip): CLAUDE.md"
}

case "${1:?usage: harness-guide.sh discover|present [repo-path]}" in
  discover) shift; do_discover "$@" ;;
  present)  shift; repo="${1:-$PWD}"; list_found "$(cd "$repo" && pwd -P)" >/dev/null 2>&1 ;;
  *) echo "usage: harness-guide.sh discover|present [repo-path]" >&2; exit 64 ;;
esac
