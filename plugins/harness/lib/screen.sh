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
#   boundary, so a boxed notice or dialog needs no blank line above it.
#   The runtime's own tail (issue #104): when the capture ends with a closed, empty input box
#   (a frame line, the input line, a frame line) and under it only lines of the profile's
#   status-area shapes (the runtime's status lines and agent list) and blank lines, that tail
#   is set aside first, and the rules above read the lines above the box. The tail counts
#   only in this order: status lines with no box, or between a block and the box, are text.
#   The status area (ho_screen_status_area): the line right under the box may have the
#   status_first_line shape (the runtime's or the user's own status line); every other line
#   must have one of the status_lines shapes. A data file without them reads as before. Only
#   when that tail is found, one line glued to the top rule of the box is set aside too, if it
#   is the runtime's notification line (ho_screen_notification): the notification_line shape,
#   and right-aligned, so it ends within 3 columns of the rule's right end. Without a closed
#   box nothing is set aside (PR #105 review round 2). Known limit: a faithful paste of the notice as the last
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

# ho_screen_profile_data [<profile>]: the pattern data the runtime profile names, or exit 78.
# Without <profile>, the profile of runtime.main; delivery passes the profile of the session's
# own runtime (PR #95 review).
# The patterns live in their own file, because that file holds the words a session shows on
# its screen: nothing else needs to be opened to read the profile (field note I2).
ho_screen_profile_data() {
  local f=${1-} name data
  [ -n "$f" ] || f=$(ho_runtime_profile) || return 78
  name=$(jq -r '.screen_file // "" | strings' "$f" 2>/dev/null || true)
  case $name in
    '' | */* | *[!a-z0-9.-]* | .*) ;;
    *)
      data="$(dirname "$f")/$name"
      if [ -f "$data" ] && data=$(jq -e -c 'select(type == "object")
            | select((.shapes | type == "array") and (.shapes | length > 0))' "$data" 2>/dev/null); then
        ho_screen_learned_merge "$f" "$data"
        return 0
      fi
      ;;
  esac
  printf 'harness: the runtime profile %s names no readable screen pattern file; screen text reads as unknown\n' "$f" >&2
  return 78
}

# ---- the user's own status line (issue #108) ---------------------------------------------------
# A runtime may let each user set a custom status line, which the shipped status shapes do not
# know; delivery then types nothing for that user. `harness screen <run> learn <session>` reads
# that session's idle screen once (read-only, every other check of the delivery screen gate
# still applies), learns a shape for each line under the input box that no shipped shape reads,
# shows it, and stores it only after the person's yes (--yes --code). The learned file lives in
# the user folder only: $HO_USER_DIR/screen/<runtime>.learned.json.
#
# The shape (agent decision under D37): the line's fixed marks in order and nothing else. A mark
# is any non-ASCII character (a symbol, a box or separator character, an emoji) or one of the
# ASCII characters [ ] ( ) { } < > | $; a run of the same mark counts as one. Between two marks
# only other ASCII characters may stand, so the words and numbers may change (branch, model,
# cost) but a line with another set of marks, a dialog or a notice say, does not read as the
# status line. A line with fewer than two marks is not learned: it cannot be told from text.
#
# The learned shapes are used only while the runtime binary (its real path, size and change
# time) and the user's status line command are the ones they were learned with; after a runtime
# update or a change of the status line setting they are set aside (delivery types nothing) until
# they are learned again.

# ho_screen_learned_file <profile>: where the learned shapes of that runtime are kept.
ho_screen_learned_file() { printf '%s/screen/%s.learned.json\n' "${HO_USER_DIR:-$HOME/.claude/harness}" "$(basename "$1" .json)"; }

# ho_screen_sha <text>: the first 16 hex digits of its SHA-256.
ho_screen_sha() {
  local s
  if command -v shasum >/dev/null 2>&1; then s=$(printf '%s' "$1" | shasum -a 256)
  else s=$(printf '%s' "$1" | sha256sum); fi
  printf '%s\n' "${s:0:16}"
}

# ho_screen_learn_keys <profile>: {runtime_id, status_sha}: what a learned shape depends on.
# runtime_id is the runtime binary's real path, size and change time (a cheap stand-in for its
# version: an update replaces the file); status_sha is the hash of the user's status line
# command (the runtime's own settings file, status_line.user_settings and .user_command).
ho_screen_learn_keys() {
  local f=$1 cmd p t n=0 st="" sf key cdir uc=""
  cmd=$(jq -r '.command // ""' "$f" 2>/dev/null) || cmd=""
  p=$(PATH=$(ho_session_clean_path) command -v "$cmd" 2>/dev/null) || p=""
  case $p in /*)
    while [ -L "$p" ] && [ "$n" -lt 20 ]; do
      t=$(readlink "$p") || break
      case $t in /*) p=$t ;; *) p="$(dirname "$p")/$t" ;; esac
      n=$((n + 1))
    done
    p="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")"
    st=$(stat -f '%z %m' "$p" 2>/dev/null || stat -c '%s %Y' "$p" 2>/dev/null) || st=""
    ;;
  *) p="" ;; esac
  sf=$(jq -r '.status_line.user_settings // ""' "$f" 2>/dev/null) || sf=""
  key=$(jq -r '.status_line.user_command // ""' "$f" 2>/dev/null) || key=""
  if [ -n "$sf" ] && [ -n "$key" ]; then
    cdir=$(ho_rt_config_dir "$f" "" 2>/dev/null) || cdir=""
    sf=${sf//\{config_dir\}/$cdir}
    [ -f "$sf" ] && uc=$(jq -r "$key | strings" "$sf" 2>/dev/null) || uc=""
  fi
  jq -cn --arg r "$p $st" --arg s "$(ho_screen_sha "$uc")" '{runtime_id: $r, status_sha: $s}'
}

# ho_screen_learned_merge <profile> <data-json>: print the data with the learned status shapes
# added when they are valid and current; else the data as it is.
ho_screen_learned_merge() {
  local f=$1 data=$2 lf learned keys
  [ "${HO_SCREEN_SHIPPED_ONLY:-}" != 1 ] || { printf '%s\n' "$data"; return 0; }
  lf=$(ho_screen_learned_file "$f")
  if [ ! -f "$lf" ] || [ -L "$lf" ]; then printf '%s\n' "$data"; return 0; fi
  learned=$(jq -c 'select(type == "object" and .schemaVersion == 1
      and (.first_line | type == "string") and (.lines | type == "array" and all(type == "string"))
      and (.runtime_id | type == "string") and (.status_sha | type == "string"))' "$lf" 2>/dev/null) || learned=""
  keys=$(ho_screen_learn_keys "$f")
  if [ -z "$learned" ] || ! jq -en --argjson a "$learned" --argjson k "$keys" \
    '$a.runtime_id == $k.runtime_id and $a.status_sha == $k.status_sha and ($k.runtime_id | test("^/"))' >/dev/null 2>&1; then
    printf 'harness: the learned status line in %s is from another runtime version or status line setting; it is not used until it is learned again (harness screen <run> learn <session>)\n' "$lf" >&2
    printf '%s\n' "$data"
    return 0
  fi
  jq -cn --argjson d "$data" --argjson a "$learned" '$d
    | .status_first_line = ([(.status_first_line // "" | strings | select(length > 0)), ($a.first_line | select(length > 0))]
        | map("(" + . + ")") | join("|"))
    | .status_lines = ((.status_lines // []) + $a.lines)'
}

# ho_screen_learn_shape <line>: print the shape of one status line, or fail when it has fewer
# than two marks (see above). Bytes are read in the C locale; a UTF-8 character is one mark.
ho_screen_learn_shape() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    function esc(c) { return (c ~ /^[][(){}|$]$/) ? "\\" c : c }
    {
      sub(/\r$/, ""); sub(/[ \t]+$/, "")
      n = length($0); i = 1; k = 0; gap = 0
      while (i <= n) {
        c = substr($0, i, 1)
        if (c >= "\200") {
          m = c; i++
          while (i <= n && substr($0, i, 1) >= "\200" && substr($0, i, 1) < "\300") { m = m substr($0, i, 1); i++ }
        } else if (c ~ /^[][(){}<>|$]$/) { m = c; i++ }
        else { i++; gap = 1; continue }
        if (k > 0 && g[k] == m && !gap) { r[k] = 1; continue }
        k++; g[k] = m; r[k] = 0; gap = 0
      }
      if (k < 2) exit 1
      N = "[ -#%-\047*-;=?-Z\\\\^-z~\t]*"
      out = "^" N
      for (j = 1; j <= k; j++) out = out (r[j] ? "(" esc(g[j]) ")+" : esc(g[j])) N
      print out "$"
    }' 2>/dev/null
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
  HO_SC_STATUS_FIRST=$(printf '%s' "$frames" | jq -r '.status_first_line // "" | strings')
  HO_SC_STATUS_LINES=$(printf '%s' "$frames" | jq -r '[.status_lines // [] | .[] | strings | "(" + . + ")"] | join("|")')
  HO_SC_NOTIFICATION_LINE=$(printf '%s' "$frames" | jq -r '.notification_line // "" | strings')
  HO_SC_CONT=$(printf '[\200-\277]')
  HO_SC_PROSE=$HO_SCREEN_PROSE
  export HO_SC_ANCHOR HO_SC_COMPANION HO_SC_BLOCK_ABOVE HO_SC_LAST_ONLY \
    HO_SC_FRAME_START HO_SC_FRAME_END HO_SC_FRAME_ONLY HO_SC_INPUT_BOX HO_SC_STATUS_FIRST HO_SC_STATUS_LINES HO_SC_NOTIFICATION_LINE HO_SC_CONT HO_SC_PROSE
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
      status_first = ENVIRON["HO_SC_STATUS_FIRST"]
      status_lines = ENVIRON["HO_SC_STATUS_LINES"]
      notification_line = ENVIRON["HO_SC_NOTIFICATION_LINE"]
      cont = ENVIRON["HO_SC_CONT"]
      prose = ENVIRON["HO_SC_PROSE"]
    }
    function trim(s) { sub(/\r$/, "", s); sub(/[ \t]+$/, "", s); return s }
    function blank(s) { return trim(s) == "" }
    function framed(s) { return s ~ frame_start }
    # width: the characters of a line (UTF-8 continuation bytes are not counted).
    function width(s,  t) { t = s; gsub(cont, "", t); return length(t) }
    # notice_line: the runtime notification line, right-aligned to the frame line under it.
    function notice_line(s, fr,  w, fw) {
      if (notification_line == "" || s !~ notification_line) return 0
      w = width(s); fw = width(fr)
      return w <= fw && w >= fw - 3
    }
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
      # The runtime tail: the last input line with a frame line right above it, a frame line
      # as the next non-blank line below it (an empty box), and below that only status lines
      # and blank lines. The lines from the opening frame down are set aside.
      boxed = 0
      if (status_first != "" || status_lines != "") {
        for (p = n; p >= 2; p--) {
          if (blank(raw[p]) || trim(raw[p]) !~ input_box) continue
          if (blank(raw[p - 1]) || trim(raw[p - 1]) !~ frame_only) break
          q = p + 1
          while (q <= n && blank(raw[q])) q++
          if (q > n || trim(raw[q]) !~ frame_only) break
          tail_ok = 1
          for (j = q + 1; j <= n; j++) {
            if (blank(raw[j])) continue
            t = trim(raw[j])
            if (j == q + 1 && status_first != "" && t ~ status_first) continue
            if (status_lines != "" && t ~ status_lines) continue
            tail_ok = 0
            break
          }
          if (tail_ok) { n = p - 2; boxed = 1 }
          break
        }
      }
      if (boxed && n >= 1 && !blank(raw[n]) && notice_line(trim(raw[n]), trim(raw[n + 1]))) n--
      if (n < NR) {
        last = 0
        for (i = 1; i <= n; i++) if (!blank(raw[i])) last = i
        if (last == 0) exit 1
      }
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
    HO_SC_FRAME_START HO_SC_FRAME_END HO_SC_FRAME_ONLY HO_SC_INPUT_BOX HO_SC_STATUS_FIRST HO_SC_STATUS_LINES HO_SC_NOTIFICATION_LINE HO_SC_CONT HO_SC_PROSE
  case $rc in 0 | 1 | 3) return "$rc" ;; esac
  return 70
}

# ho_screen_status_area <data-json>: read the lines under the closing frame of the input box
# on stdin, the first of them right under the frame. 0 when every non-blank line is the
# runtime's status area (the shapes above), 1 when one is not, 78 when the data holds no
# status shapes. Delivery uses it: any other line under the box gets nothing typed.
ho_screen_status_area() {
  local rc=0
  HO_SC_STATUS_FIRST=$(printf '%s' "$1" | jq -r '.status_first_line // "" | strings')
  HO_SC_STATUS_LINES=$(printf '%s' "$1" | jq -r '[.status_lines // [] | .[] | strings | "(" + . + ")"] | join("|")')
  export HO_SC_STATUS_FIRST HO_SC_STATUS_LINES
  if [ -z "$HO_SC_STATUS_FIRST$HO_SC_STATUS_LINES" ]; then
    unset HO_SC_STATUS_FIRST HO_SC_STATUS_LINES
    return 78
  fi
  LC_ALL=C awk '
    BEGIN { first = ENVIRON["HO_SC_STATUS_FIRST"]; lines = ENVIRON["HO_SC_STATUS_LINES"] }
    { t = $0; sub(/\r$/, "", t); sub(/[ \t]+$/, "", t) }
    t == "" { next }
    NR == 1 && first != "" && t ~ first { next }
    lines != "" && t ~ lines { next }
    { bad = 1; exit }
    END { exit bad ? 1 : 0 }' 2>/dev/null || rc=$?
  unset HO_SC_STATUS_FIRST HO_SC_STATUS_LINES
  case $rc in 0 | 1) return "$rc" ;; esac
  return 70
}

# ho_screen_notification <data-json> <line> <frame-line>: 0 when <line>, glued right above
# <frame-line> (the top rule of a closed input box), is the runtime's notification line: the
# notification_line shape, ending within 3 columns of the rule's right end. 1 otherwise.
# Delivery uses it for the lines above the box; the classifier applies the same rule inline.
ho_screen_notification() {
  local pat rc=0
  pat=$(printf '%s' "$1" | jq -r '.notification_line // "" | strings')
  [ -n "$pat" ] || return 1
  HO_SC_NOTIFICATION_LINE=$pat HO_SC_CONT=$(printf '[\200-\277]') LC_ALL=C awk -v want=2 '
    BEGIN { pat = ENVIRON["HO_SC_NOTIFICATION_LINE"]; cont = ENVIRON["HO_SC_CONT"] }
    function width(s,  t) { t = s; gsub(cont, "", t); return length(t) }
    { sub(/\r$/, ""); sub(/[ \t]+$/, ""); l[NR] = $0 }
    END {
      if (NR != want || l[1] == "" || l[1] !~ pat) exit 1
      w = width(l[1]); fw = width(l[2])
      exit (w <= fw && w >= fw - 3) ? 0 : 1
    }' 2>/dev/null <<EOF_NOTE || rc=$?
$2
$3
EOF_NOTE
  return "$rc"
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

# ho_screen_named_rule <line> <rule-char> <name>: a session launched with a name shows that name
# at the right end of its input box's top rule: at least three rule characters, one space, the
# name, one space, then rule characters only. For exactly that line, print the plain rule of
# the same width (the name and its two spaces become rule characters) and return 0; return 1
# for any other line. The name comes from the session's record, so another session's name
# never opens a box. The own name is on the screen and can be typed; that is safe because a
# typed copy inside the box is box text (a draft), and a printed fake box above the real one
# gives a second input line (a draft); delivery types nothing in either case.
ho_screen_named_rule() {
  local l=$1 c=$2 nm=$3 head rest mid tail fill i
  [ -n "$c" ] && [ -n "$nm" ] || return 1
  head=${l%% *}
  rest=${l#* }
  [ "$rest" != "$l" ] || return 1
  mid=${rest%% *}
  tail=${rest#* }
  [ "$tail" != "$rest" ] && [ "$mid" = "$nm" ] || return 1
  case $head in *"$c$c$c"*) ;; *) return 1 ;; esac
  case $tail in *"$c"*) ;; *) return 1 ;; esac
  [ -z "${head//"$c"/}" ] && [ -z "${tail//"$c"/}" ] || return 1
  fill=$c$c
  i=0
  while [ "$i" -lt "${#nm}" ]; do fill=$fill$c; i=$((i + 1)); done
  printf '%s\n' "$head$fill$tail"
}

# ho_screen_box_name <record>: the name a session was launched with (ho-<role>-<name>), from its
# record; nothing when the record does not give both parts.
ho_screen_box_name() {
  local r n
  r=$(jq -r '.role // "" | strings' "$1" 2>/dev/null) || r=""
  n=$(jq -r '.name // "" | strings' "$1" 2>/dev/null) || n=""
  case $r$n in *[!A-Za-z0-9_-]*) return 0 ;; esac
  [ -z "$r" ] || [ -z "$n" ] || printf 'ho-%s-%s\n' "$r" "$n"
}

# ho_screen_classify <capture-file> [<runtime-profile>] [<box-name>]: print one word and nothing else.
#   limit | trust | password  a shape was recognised (the first in profile order)
#   none                      the screen holds text and no shape
#   unknown                   the capture cannot be read, holds no text, or there is no data
# Exit 0 when the result is decided (including "none"), 66 for an unreadable or empty
# capture, 78 when the profile holds no screen patterns, 70 when the match could not run.
# With <box-name> (the session's launch name), a top rule that carries exactly that name
# (ho_screen_named_rule) is read as the plain rule it stands for, so the runtime's own tail
# is still set aside and a dialog above a named box is still seen.
ho_screen_classify() {
  local file=${1-} profile=${2-} box=${3-} data n i shape rc
  if [ -z "$file" ] || [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo unknown
    printf 'harness: cannot read the screen capture %s\n' "${file:-(no file)}" >&2
    return 66
  fi
  data=$(ho_screen_profile_data "$profile") || { echo unknown; return 78; }
  ho_screen_selftest "$data" || { echo unknown; return 70; }
  if [ -n "$box" ]; then
    local rprof rch line plainl norm
    rprof=$profile
    [ -n "$rprof" ] || rprof=$(ho_runtime_profile 2>/dev/null) || rprof=""
    rch=$(jq -r '.screen.rule_char // "" | strings' "$rprof" 2>/dev/null) || rch=""
    norm=$(umask 077 && mktemp "$(dirname "$file")/.named.XXXXXX" 2>/dev/null) || { echo unknown; return 70; }
    # The copy holds screen text: it is removed if this step is stopped (callers run this in
    # a command substitution, so the trap is this subshell's own).
    HO_SCREEN_NORM=$norm
    trap 'rm -f "$HO_SCREEN_NORM"' EXIT HUP INT TERM
    while IFS= read -r line || [ -n "$line" ]; do
      if plainl=$(ho_screen_named_rule "$line" "$rch" "$box"); then printf '%s\n' "$plainl"; else printf '%s\n' "$line"; fi
    done < "$file" > "$norm"
    rc=0
    ho_screen_classify "$norm" "$profile" || rc=$?
    rm -f "$norm"
    trap - EXIT HUP INT TERM
    return "$rc"
  fi
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

# ho_screen_learn <session> [--yes --code <code>]: learn the session's own status line (#108).
# Without --yes it prints what it learned and a code, and stores nothing. With --yes and the
# code of that preview it reads the screen again and stores the shapes only when they are the
# same. Exit 0 learned or nothing to learn, 64 usage, 65 refused (a line that cannot be
# learned, a wrong code, an unsafe place), 75 the screen is not an idle screen of the runtime.
ho_screen_learn() {
  local name="" yes=0 code="" rec profile out first width lines j=0 line shape src first_shape="" rest="[]"
  local data lf learned keys want ver cmd
  while [ $# -gt 0 ]; do
    case $1 in
      --yes) yes=1; shift ;;
      --code) [ $# -ge 2 ] || { ho_screen_usage >&2; return 64; }; code=$2; shift 2 ;;
      -*) printf 'harness screen learn: unknown argument %s\n' "$1" >&2; return 64 ;;
      *) [ -z "$name" ] || { ho_screen_usage >&2; return 64; }; name=$1; shift ;;
    esac
  done
  [ -n "$name" ] || { ho_screen_usage >&2; return 64; }
  [ "$yes" -eq 0 ] || [ -n "$code" ] || { echo "harness: --yes needs the --code of the preview" >&2; return 64; }
  rec=$(ho_deliver_record "$name") || return $?
  profile=$(ho_deliver_profile "$rec") || return $?
  out=$(ho_deliver_screen "$rec" "$profile" learn)
  first=$(printf '%s\n' "$out" | head -n 1)
  case $first in
    learned) echo "nothing to learn: every line under the input box already reads as the runtime's status area"; return 0 ;;
    'learn '[0-9]*) width=${first#learn } ;;
    *) printf 'harness: the screen of session %s is not an idle screen of the runtime (%s); nothing was learned\n' "$name" "$first" >&2; return 75 ;;
  esac
  lines=$(printf '%s\n' "$out" | sed 1d)
  data=$(HO_SCREEN_SHIPPED_ONLY=1 ho_screen_profile_data "$profile" 2>/dev/null) || data='{"shapes":[{}]}'
  local -a show=()
  while IFS= read -r line || [ -n "$line" ]; do
    j=$((j + 1))
    line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
    [ -n "$line" ] || continue
    # A line a shipped shape reads stays the runtime's; only the others are learned.
    src=0
    if [ "$j" -eq 1 ]; then printf '%s\n' "$line" | ho_screen_status_area "$data" || src=$?
    else printf '\n%s\n' "$line" | ho_screen_status_area "$data" || src=$?; fi
    [ "$src" -eq 0 ] && continue
    shape=$(ho_screen_learn_shape "$line") || {
      printf 'harness: line %s under the input box has fewer than two fixed symbols, so it cannot be told from other text; it is not learned and delivery types nothing while it shows\n' "$j" >&2
      return 65
    }
    printf '%s\n' "$line" | HO_SC_SHAPE=$shape LC_ALL=C awk 'BEGIN { r = ENVIRON["HO_SC_SHAPE"] } { exit ($0 ~ r) ? 0 : 1 }' || {
      printf 'harness: the shape learned for line %s does not read that line; nothing was learned\n' "$j" >&2; return 65; }
    if [ "$j" -eq 1 ]; then first_shape=$shape; else rest=$(jq -cn --argjson a "$rest" --arg s "$shape" '$a + [$s]'); fi
    show+=("$j" "$line" "$shape")
  done <<EOF_LEARN
$lines
EOF_LEARN
  [ "${#show[@]}" -gt 0 ] || { echo "nothing to learn: every line under the input box already reads as the runtime's status area"; return 0; }
  want=$(ho_screen_sha "$(jq -cn --arg f "$first_shape" --argjson l "$rest" '{first_line: $f, lines: $l}')")
  if [ "$yes" -eq 0 ]; then
    cmd=$(jq -r '.runtime_path // ""' "$rec"); ver=""
    case $cmd in /*) [ -x "$cmd" ] && ho_session_runtime_path_ok "$cmd" 2>/dev/null && ver=$(ho_deliver_version_of "$cmd") ;; esac
    printf 'Learned from the idle screen of session %s (runtime %s, version %s, frame width %s):\n' \
      "$name" "$(basename "$profile" .json)" "${ver:-unknown}" "$width"
    j=0
    while [ "$j" -lt "${#show[@]}" ]; do
      printf '  line %s under the input box: %s\n    shape: %s\n' "${show[j]}" "${show[j + 1]}" "${show[j + 2]}"
      j=$((j + 3))
    done
    printf 'The words and numbers between the symbols may change; another set of symbols does not read as your status line.\n'
    printf 'Nothing is stored until you confirm: harness screen <run> learn %s --yes --code %s\n' "$name" "$want"
    printf 'CODE %s\n' "$want"
    return 0
  fi
  [ "$code" = "$want" ] || { echo "harness: nothing stored: the status line's symbols changed since the preview (code mismatch); preview again" >&2; return 65; }
  lf=$(ho_screen_learned_file "$profile")
  if [ -L "$(dirname "$lf")" ] || [ -L "$lf" ]; then printf 'harness: nothing stored: %s is a link\n' "$lf" >&2; return 65; fi
  (umask 077 && mkdir -p "$(dirname "$lf")") || return 1
  keys=$(ho_screen_learn_keys "$profile")
  learned=$(jq -n --argjson k "$keys" --arg rt "$(basename "$profile" .json)" --arg f "$first_shape" --argjson l "$rest" \
    --argjson w "$width" --arg ts "$(ho_now)" \
    '{schemaVersion: 1, runtime: $rt, runtime_id: $k.runtime_id, status_sha: $k.status_sha, frame_width: $w,
      first_line: $f, lines: $l, learned: $ts}') || return 1
  printf '%s\n' "$learned" | (umask 077 && ho_atomic_write "$lf") || return 1
  printf 'OK learned the status line of runtime %s; stored in %s (learn again after a runtime update or a status line change)\n' \
    "$(basename "$profile" .json)" "$lf"
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
  class=$(ho_screen_classify "$dir/$name.txt" "" "$(ho_screen_box_name "$HO_RUN_DIR/sessions/$name.json")") || rc=$?
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
    permission)
      # H-052, D37-AUTONOMY-1: lib/permission.sh answers only under the analyse setting.
      ho_perm_handle "$name" "$dir/$name.txt" >/dev/null || return $?
      printf 'permission\n'
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
  permission <session>                 a permission prompt on that screen: owner action, or one
                                       accept under session.permission_prompts analyse
  pretrust <dir>                       trust a folder inside the project before a launch
  learn <session> [--yes --code C]     learn your own status line from that idle session; shows
                                       it first and stores it only with --yes and the shown code
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
    permission) ho_perm_main "$@" ;;
    wait)     ho_screen_wait "${1-}" ;;
    learn)    ho_screen_learn "$@" ;;
    *) printf 'harness screen: unknown verb %s\n' "$verb" >&2; ho_screen_usage >&2; return 64 ;;
  esac
}
