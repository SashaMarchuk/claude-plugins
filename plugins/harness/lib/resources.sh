# shellcheck shell=bash
# Out-of-memory cap lowering and usage history (H-106, H-108; design D26b, D37-LIMITS-1,
# D37-LIMITS-2, D37-LIMITS-4, D37-LIMITS-5, D37-LIMITS-6, D37-FLOW-8, S8-21).
#
# Out-of-memory stop (D37-LIMITS-1): a session reports a stopped container by its exact ID; the
# engine runs the check command for that one container and confirms the stop only when the
# container runtime's own record says out of memory. The command is data: the shipped default
# in limits/oom-check.json, or an entry of the user config (limits.oom_check.list.<label>:
# {argv, jq}); a project config may only select the label (limits.oom_check.label). A project
# config that holds a command there is refused before anything runs (D37-FLOW-8). "{container}"
# in argv becomes the container ID; jq is a filter on the command's output that must give true.
# A failed, slow (20 s), unclear or missing answer is unconfirmed, and the cap does not change.
# Each check writes one run ledger line.
#
# Lowering (H-106, D37-LIMITS-2, D37-LIMITS-6): one confirmed stop lowers the run's worker cap
# by one, once per container ID, never below 1, never raised again. It lives in
# <run>/limits.json (run state; the configured value stays as it is, and the next run starts
# from it). At cap 1 the cap stays 1. In every case the stopped task restarts through the
# normal recovery path (lib/recover.sh, D37-LIMITS-4) and waits for a slot under the new cap.
#
# Usage history (H-108, D26b, D37-LIMITS-5): "resources <run> sample" appends one reading of
# CPU load, memory use and process count (and the run's worker count) to
# <project>/.harness/usage/history.jsonl. "resources recommend" shows recommended values only
# when that history exists, and never writes any config.
#
# Exit codes: 64 usage, 65 refused, 78 config.

HO_RES_ID_RE='[A-Za-z0-9][A-Za-z0-9_.-]{0,127}'

# ho_res_project_cmd_check: refuse a project config that holds an out-of-memory check command.
ho_res_project_cmd_check() {
  local pf
  pf=$(ho_project_root 2>/dev/null) || return 0
  pf="$pf/.harness/config.json"
  if jq -e '(.limits.oom_check // {}) | type == "object" and (
        ((.argv // []) | length > 0) or ((.command // "") | length > 0) or ((.jq // "") | length > 0)
        or ((.list // {}) | length > 0))' "$pf" >/dev/null 2>&1; then
    printf 'harness: the project config %s holds an out-of-memory check command (limits.oom_check). No command from it runs. Move the command to the user config %s under limits.oom_check.list.<label> and keep only limits.oom_check.label in the project config.\n' \
      "$pf" "$(ho_user_config)" >&2
    return 78
  fi
}

# ho_res_check_def: the check {argv, jq} for the selected label.
ho_res_check_def() {
  local label def
  label=$(ho_cfg '.limits.oom_check.label' 'default') || return 78
  case $label in -* | *[!a-z0-9-]* | '') printf 'harness: limits.oom_check.label %s must use a-z 0-9 -\n' "$label" >&2; return 78 ;; esac
  def=$(ho_cfg_user ".limits.oom_check.list[\"$label\"] // null") || return 78
  if [ "$def" = null ]; then
    def=$(jq -c --arg l "$label" '.checks[$l] // null' "$HO_ROOT/limits/oom-check.json" 2>/dev/null) || def=null
  fi
  [ "$def" != null ] || { printf 'harness: no out-of-memory check named %s in the user config or the shipped list\n' "$label" >&2; return 78; }
  printf '%s' "$def" | jq -e '(.argv | type) == "array" and (.argv | length) > 0 and all(.argv[]; type == "string") and (.jq | type) == "string"' >/dev/null 2>&1 || {
    printf 'harness: the out-of-memory check %s needs argv (a list of strings) and jq\n' "$label" >&2; return 78; }
  printf '%s\n' "$def"
}

# ho_res_run_check <def> <container>: print yes, no or unclear.
ho_res_run_check() {
  local def=$1 c=$2 out pid i=0 rc=0
  local -a argv=()
  while IFS= read -r el; do argv+=("$el"); done <<EOF_ARGV
$(printf '%s' "$def" | jq -r --arg c "$c" '.argv[] | gsub("\\{container\\}"; $c)')
EOF_ARGV
  out=$(mktemp "${TMPDIR:-/tmp}/ho-oom.XXXXXX")
  ( exec "${argv[@]}" > "$out" 2>/dev/null ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$out"; echo unclear; return 0; fi
  wait "$pid" || rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$out"; echo unclear; return 0; fi
  case $(jq -r "$(printf '%s' "$def" | jq -r .jq)" "$out" 2>/dev/null | head -n 1) in
    true) echo yes ;;
    false) echo no ;;
    *) echo unclear ;;
  esac
  rm -f "$out"
}

# resources <run> oom <container-id> [--ticket T]: check one reported stop; lower the cap once.
ho_res_oom() {
  local c=${1-} t="" def verdict w new
  shift || true
  printf '%s' "$c" | grep -Eqx "$HO_RES_ID_RE" || { echo "harness: oom needs the exact container ID" >&2; return 64; }
  while [ $# -gt 0 ]; do
    case $1 in
      --ticket) [ $# -ge 2 ] || { ho_res_usage; return 64; }; t=$(ho_stop_ticket_arg "$2") || return 64; shift 2 ;;
      *) ho_res_usage; return 64 ;;
    esac
  done
  ho_res_project_cmd_check || return 78
  def=$(ho_res_check_def) || return 78
  verdict=$(ho_res_run_check "$def" "$c")
  if [ "$verdict" != yes ]; then
    ho_ledger_append oom-check container "$c" ticket "$t" result unconfirmed answer "$verdict"
    echo "oom: container $c: not confirmed as out of memory ($verdict); the worker cap does not change"
    return 0
  fi
  mkdir -p "$HO_RUN_DIR/slots" && ho_slot_lock_take || return 1
  # One stop lowers the cap once (D37-LIMITS-1): keyed on the container ID.
  if ho_ledger_events | jq -e --arg c "$c" 'select(.kind == "oom-check" and .container == $c and .result == "confirmed")' >/dev/null 2>&1; then
    rm -rf "$HO_RUN_DIR/slots/.lock"
    ho_ledger_append oom-check container "$c" ticket "$t" result repeat
    echo "oom: container $c was already counted; the worker cap stays $(ho_slot_limit worker)"
    return 0
  fi
  w=$(ho_slot_limit worker)
  new=$w
  [ "$w" -le 1 ] || new=$((w - 1))
  if [ "$new" -ne "$w" ]; then
    jq --argjson n "$new" '.workers_configured = (.workers_configured // .workers) | .workers = $n' "$HO_RUN_DIR/limits.json" \
      | ho_atomic_write "$HO_RUN_DIR/limits.json" || { rm -rf "$HO_RUN_DIR/slots/.lock"; return 1; }
  fi
  rm -rf "$HO_RUN_DIR/slots/.lock"
  ho_ledger_append oom-check container "$c" ticket "$t" result confirmed cap_from "$w" cap_to "$new"
  [ "$new" -eq "$w" ] || ho_ledger_append cap-lowered from "$w" to "$new" reason "confirmed out-of-memory stop of container $c"
  echo "oom: container $c confirmed out of memory; worker cap $w -> $new; the stopped task restarts through recovery when a slot is free"
}

# ho_res_history_file: the project's usage history.
ho_res_history_file() {
  local p
  p=$(ho_project_root 2>/dev/null) || return 1
  printf '%s/.harness/usage/history.jsonl\n' "$p"
}

# ho_res_mem_pct: memory in use, percent (no free-memory gate uses it: S8-21).
ho_res_mem_pct() {
  if [ -r /proc/meminfo ]; then
    awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if (t > 0) printf "%.1f\n", (t - a) * 100 / t}' /proc/meminfo
  elif command -v vm_stat >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1; then
    local total ps
    total=$(sysctl -n hw.memsize 2>/dev/null)
    vm_stat 2>/dev/null | awk -v total="$total" '
      /page size of/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) ps = $i}
      /^Pages (active|wired down|occupied by compressor)/ {gsub(/\./, "", $NF); used += $NF}
      END {if (total > 0 && ps > 0) printf "%.1f\n", used * ps * 100 / total}'
  fi
}

# resources <run> sample: one reading into the history (H-108).
ho_res_sample() {
  local f load mem procs workers
  f=$(ho_res_history_file) || { echo "harness: no project for the usage history" >&2; return 66; }
  load=$(uptime 2>/dev/null | sed -E 's/.*load averages?: *//; s/,/ /g' | awk '{print $1}')
  mem=$(ho_res_mem_pct)
  procs=$(ps -A -o pid= 2>/dev/null | wc -l | tr -d ' ')
  workers=$(ho_slot_count "$HO_RUN_DIR/slots/worker")
  mkdir -p "$(dirname "$f")"
  jq -cn --arg ts "$(ho_now)" --arg run "$HO_RUN_ID" --arg load "$load" --arg mem "$mem" --arg procs "$procs" --arg w "$workers" \
    '{ts: $ts, run: $run, cpu_load: ($load | tonumber? // null), mem_pct: ($mem | tonumber? // null),
      procs: ($procs | tonumber? // null), workers: ($w | tonumber? // 0)}' >> "$f"
  tail -n 1 "$f"
}

# resources recommend: only with history (D26b). Total: how many workers fit in 80% memory at the
# highest memory share one worker used; stages and heavy: 1. Never written to any config.
ho_res_recommend() {
  local f
  f=$(ho_res_history_file) || { echo "harness: no project here" >&2; return 66; }
  if [ ! -s "$f" ] || ! jq -se 'any(.[]; (.workers // 0) > 0 and (.mem_pct | type) == "number")' "$f" >/dev/null 2>&1; then
    echo "no recommendation: no usage history yet; the defaults apply (total 1, stage and heavy limits 1)"
    return 0
  fi
  jq -sr '[.[] | select((.workers // 0) > 0 and (.mem_pct | type) == "number") | .mem_pct / .workers] | max as $per
    | ([(80 / $per | floor), 1] | max) as $total
    | "recommended (from \(length) readings; your configured values stay as you set them): total \($total), stages 1, heavy 1"' "$f"
}

ho_res_usage() {
  cat >&2 <<'USAGE'
usage: harness resources <run-dir> oom <container-id> [--ticket T]
                                       check a reported container stop; a confirmed
                                       out-of-memory stop lowers this run's worker cap by one
       harness resources <run-dir> sample
                                       append one CPU, memory and process reading to the history
       harness resources recommend     recommended concurrency, only when history exists
USAGE
}

ho_res_main() {
  [ "${1-}" = recommend ] && { ho_res_recommend; return $?; }
  [ $# -ge 2 ] || { ho_res_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2
  shift 2
  case $verb in
    oom) ho_res_oom "$@" ;;
    sample) ho_res_sample ;;
    *) ho_res_usage; exit 64 ;;
  esac
}
