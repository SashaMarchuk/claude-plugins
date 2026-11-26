# shellcheck shell=bash
# Screen text: recognition only (design "Rebuild" reuse list; H-113, H-099).
#
# What the engine may do with a session's screen:
#   - recognise the subscription-limit notice, the folder-trust dialog and a password or
#     sudo prompt, against saved screen fixtures (tests/fixtures/screen);
#   - on the limit notice: record one line and run the STOP-aware wait for the reset time
#     the limits reader gives (H-114, D28c). The reset time never comes from the screen
#     (field note I1: a parser that reads a value from the screen read the wrong one);
#   - on the trust dialog: report it as an owner action. A folder is trusted only before
#     launch, and only inside the project (ho_screen_pretrust);
#   - on a password or sudo prompt: record an owner action. It is never answered, and no
#     input is sent to it (reuse list: a password or sudo prompt becomes an owner action).
#
# What the engine never does: it types nothing, and it sends no key, for any of the three.
# The typed reaction to a limit notice is on the design drop list, and field note F1 is why:
# a match inside a session's own prose started an 85-minute loop of Escape and a typed word.
#
# All pattern text lives in a data file that the runtime profile names, never here
# (D37-RUNTIME-1), and the profile comes only from the shipped defaults or the user config
# (D37-FLOW-8).
#
# Recognition rules, in engine code because they are about shape, not about words:
#   Anchor and companion patterns are matched against the lower-cased line, so the patterns
#   in the profile are written in lower case.
#   A line is a candidate only when it is the tool's own line: it starts at column 0, with
#   the profile's frame character or with no space, and the whole line (frame and padding
#   removed) matches the shape's anchor. An embedded or wrapped sentence therefore misses.
#   The candidate's block is the run of non-blank lines around it. Depending on the shape:
#   the line above the block is blank (so wrapped prose above misses), the block holds the
#   shape's companion line, the candidate is the last non-blank line, and after the block
#   come only blank lines, frame lines and the input line (so a block pasted into a report
#   that goes on afterwards misses). Where the line above the block must be blank, the
#   candidate must also open its block, with only frame lines above it inside the block, so
#   a notice wrapped into a paragraph of the session's own prose misses. A box draws its own
#   boundary, so a boxed notice or dialog needs no blank line above it. Known limit: a faithful paste of the notice as the last
#   block of the screen cannot be told from the notice itself by text. That is bounded, not
#   closed: nothing is typed, and the wait it leads to is recorded once and ends on STOP.
#
# Unknown is never "nothing found" (field notes I1, I3): a capture that cannot be read, an
# empty capture and missing pattern data all read as "unknown".
#
# Requires lib/files.sh, lib/config.sh, lib/run.sh, lib/term.sh and lib/sessions.sh.

# Marks of a session's own writing: the quote characters a quoted notice carries, and the
# markers of a list or a quoted block. An apostrophe is not one of them: a notice of the tool
# may hold one too (for example a contraction), so it would reject the real line.
HO_SCREEN_PROSE='(["`]|^[>*#+-][ 	]|^[0-9]+[.)][ 	])'

# ho_screen_profile_data: the pattern data the runtime profile names, or exit 78.
# The patterns live in their own file, because that file holds the words a session shows on
# its screen: nothing else needs to be opened to read the profile (field note I2).
ho_screen_profile_data() {
  local f name data
  f=$(ho_runtime_profile) || return 78
  name=$(jq -r '.screen_file // "" | strings' "$f" 2>/dev/null || true)
  case $name in
    '' | */* | *[!a-z0-9.-]* | .*) ;;
    *)
      data="$(dirname "$f")/$name"
      if [ -f "$data" ]; then
        jq -e -c 'select(type == "object")
            | select((.shapes | type == "array") and (.shapes | length > 0))' "$data" 2>/dev/null && return 0
      fi
      ;;
  esac
  printf 'harness: the runtime profile %s names no readable screen pattern file; screen text reads as unknown\n' "$f" >&2
  return 78
}

# ho_screen_trust_data: the runtime profile's trust object, or exit 78.
ho_screen_trust_data() {
  local f
  f=$(ho_runtime_profile) || return 78
  jq -e -c '.trust | select(type == "object")
      | select((.config_file | type == "string") and (.projects_key | type == "string")
        and (.fields | type == "object"))' "$f" 2>/dev/null && return 0
  printf 'harness: the runtime profile %s holds no trust data; a folder cannot be trusted before launch\n' "$f" >&2
  return 78
}

# ho_screen_shape_match <file> <shape-json> <frames-json>: 0 the shape is on the screen,
# 1 it is not, 3 the capture holds no text, 70 the match could not run.
ho_screen_shape_match() {
  local file=$1 shape=$2 frames=$3 rc=0
  # awk writes nothing of its own: an error message about a pattern would carry the pattern
  # text out of this file (field note I2).
  # The patterns travel in the environment, not in awk -v: an awk assignment reads escape
  # sequences, so a pattern such as a bracket written with a backslash would arrive as a
  # character class instead of the two characters it stands for.
  HO_SC_ANCHOR=$(printf '%s' "$shape" | jq -r '.anchor')
  HO_SC_COMPANION=$(printf '%s' "$shape" | jq -r '.companion // ""')
  HO_SC_BLOCK_ABOVE=$(printf '%s' "$shape" | jq -r 'if .block_above then 1 else 0 end')
  HO_SC_LAST_ONLY=$(printf '%s' "$shape" | jq -r 'if .last_nonblank then 1 else 0 end')
  HO_SC_FRAME_START=$(printf '%s' "$frames" | jq -r '.frame_start')
  HO_SC_FRAME_END=$(printf '%s' "$frames" | jq -r '.frame_end')
  HO_SC_FRAME_ONLY=$(printf '%s' "$frames" | jq -r '.frame_only')
  HO_SC_INPUT_BOX=$(printf '%s' "$frames" | jq -r '.input_box')
  HO_SC_PROSE=$HO_SCREEN_PROSE
  export HO_SC_ANCHOR HO_SC_COMPANION HO_SC_BLOCK_ABOVE HO_SC_LAST_ONLY \
    HO_SC_FRAME_START HO_SC_FRAME_END HO_SC_FRAME_ONLY HO_SC_INPUT_BOX HO_SC_PROSE
  LC_ALL=C awk '
    BEGIN {
      anchor = ENVIRON["HO_SC_ANCHOR"]
      companion = ENVIRON["HO_SC_COMPANION"]
      block_above = ENVIRON["HO_SC_BLOCK_ABOVE"]
      last_only = ENVIRON["HO_SC_LAST_ONLY"]
      frame_start = ENVIRON["HO_SC_FRAME_START"]
      frame_end = ENVIRON["HO_SC_FRAME_END"]
      frame_only = ENVIRON["HO_SC_FRAME_ONLY"]
      input_box = ENVIRON["HO_SC_INPUT_BOX"]
      prose = ENVIRON["HO_SC_PROSE"]
    }
    function trim(s) { sub(/\r$/, "", s); sub(/[ \t]+$/, "", s); return s }
    function blank(s) { return trim(s) == "" }
    function framed(s) { return s ~ frame_start }
    function core(s,  t) {
      t = trim(s)
      if (framed(t)) {
        sub(frame_start, "", t)
        sub(frame_end, "", t)
        sub(/^[ \t]+/, "", t)
        sub(/[ \t]+$/, "", t)
        return t
      }
      return t
    }
    { raw[NR] = $0 }
    END {
      n = NR
      last = 0
      for (i = 1; i <= n; i++) if (!blank(raw[i])) last = i
      if (last == 0) exit 3
      for (i = 1; i <= n; i++) {
        line = trim(raw[i])
        if (blank(line)) continue
        if (!framed(line) && line ~ /^[ \t]/) continue
        c = core(line)
        if (c ~ prose) continue
        if (tolower(c) !~ "^(" anchor ")$") continue
        if (last_only == 1 && i != last) continue
        # The block is the run of lines of the same kind around the candidate: a box is its
        # own block, so output that sits right above it is not part of it.
        boxline = framed(line)
        top = i
        while (top > 1 && !blank(raw[top - 1]) && framed(trim(raw[top - 1])) == boxline) top--
        bottom = i
        while (bottom < n && !blank(raw[bottom + 1]) && framed(trim(raw[bottom + 1])) == boxline) bottom++
        if (block_above == 1) {
          skip = 0
          for (j = top; j < i; j++) if (trim(raw[j]) !~ frame_only) { skip = 1; break }
          if (skip) continue
          boxed = (top < i && trim(raw[top]) ~ frame_only)
          if (!boxed && top > 1 && !blank(raw[top - 1])) continue
        }
        if (companion != "") {
          found = 0
          for (j = top; j <= bottom; j++) {
            if (tolower(core(raw[j])) ~ "^(" companion ")$") { found = 1; break }
          }
          if (!found) continue
        }
        ok = 1
        for (j = bottom + 1; j <= n; j++) {
          if (blank(raw[j])) continue
          if (trim(raw[j]) ~ frame_only) continue
          if (trim(raw[j]) ~ input_box) continue
          ok = 0
          break
        }
        if (!ok) continue
        exit 0
      }
      exit 1
    }' "$file" 2>/dev/null || rc=$?
  unset HO_SC_ANCHOR HO_SC_COMPANION HO_SC_BLOCK_ABOVE HO_SC_LAST_ONLY \
    HO_SC_FRAME_START HO_SC_FRAME_END HO_SC_FRAME_ONLY HO_SC_INPUT_BOX HO_SC_PROSE
  case $rc in 0 | 1 | 3) return "$rc" ;; esac
  return 70
}

# ho_screen_selftest <frames-json>: before the first match, check that this awk runs the
# patterns as written: a bounded repeat must match, and a backslash-escaped dot must stay a
# dot. An awk that cannot would read every screen as "none"; this makes it "unknown" with
# exit 70 and a message instead (PR #97 review). Runs once per process.
ho_screen_selftest() {
  local rc=0
  [ "${HO_SCREEN_SELFTEST:-}" = ok ] && return 0
  printf 'p.robe\n' | ho_screen_shape_match - '{"anchor":"p\\.ro{1,2}be","companion":""}' "$1" || rc=$?
  if [ "$rc" -eq 0 ]; then
    rc=0
    printf 'pxrobe\n' | ho_screen_shape_match - '{"anchor":"p\\.ro{1,2}be","companion":""}' "$1" || rc=$?
    if [ "$rc" -eq 1 ]; then
      HO_SCREEN_SELFTEST=ok
      return 0
    fi
  fi
  printf 'harness: the awk on this machine does not run the screen patterns as written (bounded repeats or escapes); screen text reads as unknown\n' >&2
  return 70
}

# ho_screen_classify <capture-file>: print one word and nothing else.
#   limit | trust | password  a shape was recognised (the first in profile order)
#   none                      the screen holds text and no shape
#   unknown                   the capture cannot be read, holds no text, or there is no data
# Exit 0 when the result is decided (including "none"), 66 for an unreadable or empty
# capture, 78 when the profile holds no screen patterns, 70 when the match could not run.
ho_screen_classify() {
  local file=${1-} data n i shape rc
  if [ -z "$file" ] || [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo unknown
    printf 'harness: cannot read the screen capture %s\n' "${file:-(no file)}" >&2
    return 66
  fi
  data=$(ho_screen_profile_data) || { echo unknown; return 78; }
  ho_screen_selftest "$data" || { echo unknown; return 70; }
  n=$(printf '%s' "$data" | jq '.shapes | length')
  i=0
  while [ "$i" -lt "$n" ]; do
    shape=$(printf '%s' "$data" | jq -c --argjson i "$i" '.shapes[$i]')
    rc=0
    ho_screen_shape_match "$file" "$shape" "$data" || rc=$?
    case $rc in
      0) printf '%s\n' "$(printf '%s' "$shape" | jq -r '.id')"; return 0 ;;
      3) echo unknown; printf 'harness: the screen capture %s holds no text\n' "$file" >&2; return 66 ;;
      70) echo unknown; printf 'harness: the screen match could not run over %s\n' "$file" >&2; return 70 ;;
    esac
    i=$((i + 1))
  done
  echo none
}

# ho_screen_git <args>: git with every variable that can point it at another repository
# cleared, so the engine's own environment cannot steer a trust check (PR #97 review).
ho_screen_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_CEILING_DIRECTORIES \
    -u GIT_DISCOVERY_ACROSS_FILESYSTEM git "$@"
}

# ho_screen_git_dir <dir> <rev-parse-flag>: the physical path that rev-parse gives for <dir>.
ho_screen_git_dir() {
  local d=$1 out
  out=$(ho_screen_git -C "$d" rev-parse "$2" 2>/dev/null) || return 1
  [ -n "$out" ] || return 1
  case $out in /*) ;; *) out="$d/$out" ;; esac
  (cd "$out" 2>/dev/null && pwd -P)
}

# ho_screen_trust_scope <dir> <project>: print root, inside or worktree, or fail.
#   root      <dir> is the project folder itself
#   inside    <dir> is a folder inside the project folder
#   worktree  <dir> is in a linked worktree of the project's own repository: its common git
#             folder is the project's own, and its top folder is one that
#             `git worktree list` of the project names. A hand-made .git file, a worktree of
#             another repository (also one nested inside the project) and a git variable in
#             the engine's environment do not pass.
ho_screen_trust_scope() {
  local d proj common dcommon top line
  ho_assert_abs "${1-}" "folder" 2>/dev/null || return 1
  [ -d "$1" ] || return 1
  d=$(cd "$1" && pwd -P) || return 1
  proj=$(cd "$2" 2>/dev/null && pwd -P) || return 1
  [ "$d" = "$proj" ] && { echo root; return 0; }
  case "$d/" in "$proj"/*) echo inside; return 0 ;; esac
  common=$(ho_screen_git_dir "$proj" --git-common-dir) || return 1
  [ "$common" = "$proj/.git" ] || return 1
  dcommon=$(ho_screen_git_dir "$d" --git-common-dir) || return 1
  [ "$dcommon" = "$common" ] || return 1
  top=$(ho_screen_git -C "$d" rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(cd "$top" 2>/dev/null && pwd -P) || return 1
  [ "$top" != "$proj" ] || return 1
  while IFS= read -r line; do
    case $line in
      'worktree '*)
        line=$(cd "${line#worktree }" 2>/dev/null && pwd -P) || continue
        [ "$line" = "$top" ] && { echo worktree; return 0; }
        ;;
    esac
  done <<EOF_WT
$(ho_screen_git -C "$proj" worktree list --porcelain 2>/dev/null)
EOF_WT
  return 1
}

# ho_screen_trust_file <trust-data>: the runtime's own state file, as this engine sees it.
ho_screen_trust_file() {
  local data=$1 env_name env_value file
  env_name=$(printf '%s' "$data" | jq -r '.config_dir_env // ""')
  file=$(printf '%s' "$data" | jq -r '.config_file')
  case $file in /*) ;; *)
    env_value=""
    [ -n "$env_name" ] && env_value=$(printenv "$env_name" 2>/dev/null || true)
    if [ -n "$env_value" ]; then file="$env_value/$file"; else file="$HOME/$file"; fi
    ;;
  esac
  printf '%s\n' "$file"
}

# ho_screen_trusted <file> <trust-data> <folder>: 0 when every trust field is already set for
# that folder; 2 when the file cannot be read as an object.
ho_screen_trusted() {
  printf '%s' "$2" | jq -e --arg p "$3" --slurpfile cur "$1" \
    '.projects_key as $k | .fields as $f
     | ($cur[0] | select(type == "object")) as $c
     | ($c[$k][$p] // {}) as $e
     | [$f | to_entries[] | $e[.key] == .value] | all' >/dev/null 2>&1
}

# ho_screen_trust_lock <file> / ho_screen_trust_unlock: one writer at a time for the runtime's
# state file, across every run of this engine (the lock lives in the harness user folder).
# A lock whose holder is gone is taken over; no lock after 30 s is a failure.
ho_screen_trust_lock() {
  local dir n=0 pid
  dir="${HO_USER_DIR:-$HOME/.claude/harness}/locks"
  mkdir -p "$dir" || return 1
  HO_SCREEN_TRUST_LOCK="$dir/trust-$(printf '%s' "$1" | cksum | awk '{ print $1 }').lock"
  until mkdir "$HO_SCREEN_TRUST_LOCK" 2>/dev/null; do
    pid=$(cat "$HO_SCREEN_TRUST_LOCK/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      [ "$(cat "$HO_SCREEN_TRUST_LOCK/pid" 2>/dev/null || true)" = "$pid" ] && rm -rf "$HO_SCREEN_TRUST_LOCK"
      continue
    fi
    if [ -z "$pid" ] && [ -n "$(find "$HO_SCREEN_TRUST_LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rm -rf "$HO_SCREEN_TRUST_LOCK"
      continue
    fi
    n=$((n + 1))
    [ "$n" -lt 600 ] || { printf 'harness: the trust lock %s is held; nothing was written\n' "$HO_SCREEN_TRUST_LOCK" >&2; return 1; }
    sleep 0.05
  done
  printf '%s\n' "$$" > "$HO_SCREEN_TRUST_LOCK/pid"
}
ho_screen_trust_unlock() { rm -rf "$HO_SCREEN_TRUST_LOCK"; }

# ho_screen_pretrust <dir>: trust <dir> for the runtime before a session starts there.
# Consent first (PR #97 review, a security finding): the person must already have
# trusted the project folder in the runtime, in the state file the session will use. That is
# the one interactive consent this needs; the repository itself is the untrusted side, so
# "inside the project" alone is not consent. With it, a folder inside the project, or in a
# linked worktree of the project's own repository, gets the same trust (reuse list: pre-trust
# inside the project only). The project folder itself is never written.
#   0  trusted now, already trusted, or the project folder itself (nothing written)
#   77 the project folder is not trusted in the runtime: nothing written, the caller stops
#   65 refused (outside the project and not one of its worktrees)
#   78 no trust data in the runtime profile
#   1  the runtime's state file could not be written (a link, unreadable, or locked)
ho_screen_pretrust() {
  local dir=${1-} proj data file scope resolved tmp rc=0
  [ -n "$dir" ] || { echo "harness: screen pretrust <dir>" >&2; return 64; }
  proj=$(cd "${HO_PROJECT_DIR:-$(ho_project_root)}" 2>/dev/null && pwd -P) || return 65
  scope=$(ho_screen_trust_scope "$dir" "$proj") || {
    printf 'harness: refusing to trust %s: it is not inside the project or one of its worktrees\n' "$dir" >&2
    return 65
  }
  resolved=$(cd "$dir" && pwd -P) || return 65
  data=$(ho_screen_trust_data) || return 78
  file=$(ho_screen_trust_file "$data")
  if [ ! -f "$file" ] || ! printf '%s' "$data" | jq -e --arg p "$proj" --slurpfile cur "$file" \
      '.projects_key as $k | (.consent_field // "") as $c
       | $c != "" and (($cur[0] | select(type == "object"))[$k][$p][$c] == true)' >/dev/null 2>&1; then
    printf 'harness: the project %s is not trusted in the runtime yet; nothing was written\n' "$proj" >&2
    return 77
  fi
  [ "$scope" = root ] && return 0
  ho_screen_trusted "$file" "$data" "$resolved" && return 0
  if [ -L "$file" ]; then
    printf 'harness: %s is a link; %s was not trusted before launch\n' "$file" "$resolved" >&2
    return 1
  fi
  ho_screen_trust_lock "$file" || return 1
  # Read again under the lock: another launch may have written it meanwhile.
  if ho_screen_trusted "$file" "$data" "$resolved"; then
    ho_screen_trust_unlock
    return 0
  fi
  tmp=$(mktemp "$(dirname "$file")/.ho-trust.XXXXXX") || { ho_screen_trust_unlock; return 1; }
  if printf '%s' "$data" | jq -e --arg p "$resolved" --slurpfile cur "$file" \
      '.projects_key as $k | .fields as $f
       | ($cur[0] | select(type == "object"))
       | .[$k] = ((.[$k] // {}) | (.[$p] = ((.[$p] // {}) + $f)))' > "$tmp" 2>/dev/null \
      && [ -s "$tmp" ] && mv "$tmp" "$file"; then
    ho_screen_trusted "$file" "$data" "$resolved" || rc=1
  else
    rm -f "$tmp"
    rc=1
  fi
  ho_screen_trust_unlock
  [ "$rc" -eq 0 ] || printf 'harness: could not write the trust record into %s; %s was not trusted before launch\n' "$file" "$resolved" >&2
  return "$rc"
}

# ho_screen_reset_ok <value>: a reset is "unknown" or a plain epoch in seconds: no leading
# zero, not 0, and inside the 64-bit range of shell arithmetic. Anything else is refused
# (exit 64), so a reader that falls back to 0, or a number that wraps, never reads as
# "reset reached" (PR #97 review).
ho_screen_reset_ok() {
  case ${1-} in
    unknown) return 0 ;;
    [1-9] | [1-9]*[0-9])
      case $1 in *[!0-9]*) ;; *)
        if [ "${#1}" -lt 19 ] || { [ "${#1}" -eq 19 ] && [ ! "$1" \> 9223372036854775807 ]; }; then
          return 0
        fi
        ;;
      esac
      ;;
  esac
  printf 'harness: a reset must be unknown or an epoch in seconds (1 to 9223372036854775807, no leading zero): %s\n' "${1-}" >&2
  return 1
}

# ho_screen_wait <epoch|unknown>: the reused STOP-aware wait (D28c). Sleeps in slices so a
# STOP lands quickly. An unknown reset never means "continue now" (field note F4.1): it
# holds for one bounded period and then reports unknown, so the caller asks the reader again.
#   0 the reset time has passed, 75 a STOP ended the wait, 2 the reset is unknown.
ho_screen_wait() {
  local until=${1-} name=${2:--} digest=${3:--} slice margin hold now left rc=0 state
  slice=$(ho_cfg_int '.limits.wait_slice_seconds' 300)
  margin=$(ho_cfg_int '.limits.resume_margin_seconds' 90)
  hold=$(ho_cfg_int '.limits.unknown_hold_seconds' 300)
  ho_screen_reset_ok "$until" || return 64
  case $until in
    unknown) left=$hold; rc=2 ;;
    *)
      now=$(date -u '+%s')
      left=$((until + margin - now))
      [ "$left" -lt 0 ] && left=0
      ;;
  esac
  while :; do
    state=0
    ho_stopped || state=$?
    if [ "$state" -ne 1 ]; then
      ho_screen_wait_logged stopped "$name" "$digest" \
        || ho_ledger_append limit-wait session "$name" digest "$digest" result stopped
      return "$HO_EXIT_STOPPED"
    fi
    [ "$left" -gt 0 ] || break
    if [ "$slice" -gt 0 ] && [ "$left" -gt "$slice" ]; then
      sleep "$slice"
      left=$((left - slice))
    else
      sleep "$left"
      left=0
    fi
  done
  if [ "$rc" -eq 2 ]; then
    ho_screen_wait_logged unknown "$name" "$digest" \
      || ho_ledger_append limit-wait session "$name" digest "$digest" result unknown
  else
    ho_ledger_append limit-wait session "$name" digest "$digest" result reset
  fi
  return "$rc"
}

# ho_screen_digest <file>: a number that stands for the screen, so an unchanged screen is
# recorded once (field note F1: one event per watch cycle was the loop). Never the text.
ho_screen_digest() {
  cksum < "$1" | awk '{ print $1 "-" $2 }'
}

# ho_screen_logged <shape> <session> <digest>: 0 when this screen was already recorded.
ho_screen_logged() {
  ho_ledger_events | jq -e --arg s "$1" --arg n "$2" --arg d "$3" \
    'select(.kind == "screen" and .shape == $s and .session == $n and .digest == $d)' >/dev/null 2>&1
}

# ho_screen_wait_logged <result> <session> <digest>: 0 when the wait for that screen already
# ended with that result.
ho_screen_wait_logged() {
  [ "$2" != - ] || return 1
  ho_ledger_events | jq -e --arg r "$1" --arg n "$2" --arg d "$3" \
    'select(.kind == "limit-wait" and .result == $r and .session == $n and .digest == $d)' >/dev/null 2>&1
}

# ho_screen_owner_action <session> <shape> <why> <command>
ho_screen_owner_action() {
  ho_ledger_append owner-action title "$2 in session $1" why "$3" command "$4" \
    verify "the session goes on by itself once you have answered it"
}

# ho_screen_watch <session-name> [--reset <epoch|unknown>]: read that session's screen
# through the terminal adapter, recognise it, record it once and act. Prints the class word.
# Types nothing and sends no key, whatever is on the screen.
ho_screen_watch() {
  local name=${1-} reset=unknown dir class digest rc=0 cwd
  [ -n "$name" ] || { echo "harness: screen watch <session> [--reset <epoch|unknown>]" >&2; return 64; }
  shift
  while [ $# -gt 0 ]; do
    case $1 in
      --reset)
        [ $# -ge 2 ] || { echo "harness: screen watch <session> [--reset <epoch|unknown>]" >&2; return 64; }
        reset=$2
        shift 2
        ;;
      *) printf 'harness: screen watch: unknown option %s\n' "$1" >&2; return 64 ;;
    esac
  done
  ho_screen_reset_ok "$reset" || return 64
  dir="$HO_RUN_DIR/screen"
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  ho_session_capture "$name" "$dir/$name.txt" || return $?
  class=$(ho_screen_classify "$dir/$name.txt") || rc=$?
  case $class in
    none) printf 'none\n'; return 0 ;;
    unknown)
      digest=$(ho_screen_digest "$dir/$name.txt" 2>/dev/null || echo none)
      ho_screen_logged unknown "$name" "$digest" \
        || ho_ledger_append screen session "$name" shape unknown action none digest "$digest"
      printf 'unknown\n'
      return "$rc"
      ;;
  esac
  digest=$(ho_screen_digest "$dir/$name.txt")
  case $class in
    limit)
      printf 'limit\n'
      # One notice is one recorded notice and one recorded result per kind, not one line per
      # look (PR-5, field note F1). The notice stays on the screen after the reset, because
      # nothing is typed, so the wait for that screen ends only once its reset was reached;
      # a look after an unknown reset or after a STOP waits again, as PR-8 asks, and adds no
      # line.
      if ho_screen_wait_logged reset "$name" "$digest"; then
        return 0
      fi
      ho_screen_logged limit "$name" "$digest" \
        || ho_ledger_append screen session "$name" shape limit action wait digest "$digest" reset "$reset"
      ho_screen_wait "$reset" "$name" "$digest"
      return $?
      ;;
    trust)
      cwd=$(jq -r 'if type == "object" then (.cwd // "") else "" end' "$HO_RUN_DIR/sessions/$name.json" 2>/dev/null || true)
      if ! ho_screen_logged trust "$name" "$digest"; then
        ho_ledger_append screen session "$name" shape trust action owner-action digest "$digest"
        ho_screen_owner_action "$name" "folder trust dialog" \
          "the folder was not trusted before launch, and the harness never answers the dialog" \
          "attach to the session and answer the dialog for ${cwd:-its folder} yourself"
      fi
      printf 'trust\n'
      return 0
      ;;
    password)
      if ! ho_screen_logged password "$name" "$digest"; then
        ho_ledger_append screen session "$name" shape password action owner-action digest "$digest"
        ho_screen_owner_action "$name" "password or sudo prompt" \
          "the harness never answers a password or sudo prompt and types nothing into it" \
          "attach to the session and enter it yourself, or set up access that does not ask"
      fi
      printf 'password\n'
      return 0
      ;;
  esac
  printf 'unknown\n'
  return 70
}

ho_screen_usage() {
  cat <<'USAGE'
usage: harness screen <run-dir> <verb> [args]

verbs:
  classify <capture-file>              print limit | trust | password | none | unknown
  watch <session> [--reset <epoch|unknown>]
                                       read that session's screen, record it once and act
  pretrust <dir>                       trust a folder inside the project before a launch
  wait <epoch|unknown>                 the STOP-aware wait for a limit reset
USAGE
}

ho_screen_main() {
  local dir=${1-} verb=${2-}
  case $verb in '' | help | -h | --help) ho_screen_usage; [ -n "$verb" ] || return 64; return 0 ;; esac
  [ -n "$dir" ] || { ho_screen_usage >&2; return 64; }
  shift 2
  ho_run_open "$dir"
  ho_session_bind_project || return $?
  case $verb in
    classify) ho_screen_classify "${1-}" ;;
    watch)    ho_screen_watch "$@" ;;
    pretrust) ho_screen_pretrust "${1-}" ;;
    wait)     ho_screen_wait "${1-}" ;;
    *) printf 'harness screen: unknown verb %s\n' "$verb" >&2; ho_screen_usage >&2; return 64 ;;
  esac
}
