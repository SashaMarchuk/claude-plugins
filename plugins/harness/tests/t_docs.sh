# Install guide and newcomer documentation (tasks.md 20.3): H-126 (a short install guide),
# H-130 (the README lists the tested flow systems and says others are untested), H-131
# (how to set up or bypass the harness in a project that already uses it); design D19
# (newcomer explanation: plugin README section and a README in the config folder) and D27
# (a short multi-worker recipe).
root=$HO_PLUGIN_ROOT
guide="$root/docs/INSTALL.md"
readme="$root/README.md"
folder="$root/templates/harness-folder-README.md"
docs="$guide $readme $folder"

assert_eq "H-126: the install guide ships" yes "$([ -f "$guide" ] && echo yes || echo no)"
n=$(wc -l < "$guide" 2>/dev/null | tr -d ' ' || echo 999)
assert_eq "H-126: the install guide is short (at most 80 lines)" yes "$([ "${n:-999}" -le 80 ] && echo yes || echo no)"
assert_contains "H-126: the guide installs from the marketplace" "$(cat "$guide")" "/plugin install harness@"
mkt=$(jq -r .name "$root/../../.claude-plugin/marketplace.json")
assert_contains "H-126: the guide names this repository's marketplace" "$(cat "$guide")" "harness@$mkt"
assert_eq "H-126: the marketplace lists the harness plugin" harness "$(jq -r '.plugins[] | select(.name == "harness") | .name' "$root/../../.claude-plugin/marketplace.json")"

# Every slash command the docs name exists.
missing=""
for c in $(cat $docs | grep -oE '/harness:[a-z-]+' | sort -u); do
  [ -f "$root/commands/${c#/harness:}.md" ] || missing="$missing $c"
done
assert_eq "H-126: every /harness command in the docs exists" "" "$missing"
# Every engine verb the guide names is a verb of bin/harness.
verbs=$("$root/bin/harness" help | sed -n 's/^  \([a-z]*\) .*/\1/p' | tr '\n' ' ')
missing=""
for v in $(grep -oE 'bin/harness [a-z]+' "$guide" | awk '{print $2}' | sort -u); do
  case " $verbs " in *" $v "*) ;; *) missing="$missing $v" ;; esac
done
assert_eq "H-126: every bin/harness verb in the guide exists" "" "$missing"
assert_eq "H-126: bin/harness version runs" 0 "$(rc=0; "$root/bin/harness" version >/dev/null 2>&1 || rc=$?; echo "$rc")"
assert_eq "H-126: the guide's worker option parses (bad value refused as usage)" 64 "$(rc=0; "$root/bin/harness" run new --workers x >/dev/null 2>&1 || rc=$?; echo "$rc")"
# Every relative link resolves, and its anchor names a heading.
bad=""
for f in $docs; do
  d=$(dirname "$f")
  for l in $(grep -oE '\]\([^)#][^)]*\)' "$f" | sed 's/^](//; s/)$//' | grep -v '^https\?:'); do
    p=${l%%#*}; a=""
    case $l in *'#'*) a=${l#*#} ;; esac
    [ -e "$d/$p" ] || { bad="$bad $f:$l"; continue; }
    if [ -n "$a" ]; then
      grep -E '^#+ ' "$d/$p" | sed 's/^#* //' | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9 -]//g; s/ /-/g' | grep -qx -- "$a" || bad="$bad $f:$l"
    fi
  done
done
assert_eq "H-126: every relative link in the docs resolves" "" "$bad"

# D27: the multi-worker recipe; D19 / H-131: the newcomer section and the folder README.
assert_contains "D27: the guide has a short multi-worker recipe" "$(cat "$guide")" "## Several workers at once"
assert_contains "D27: the recipe sets the worker cap" "$(cat "$guide")" "--workers"
assert_contains "D19 H-131: the plugin README has the newcomer section" "$(cat "$readme")" "## Joining a project that already uses the harness"
j=$(sed -n '/^## Joining a project that already uses the harness/,/^## /p' "$readme")
assert_contains "H-131: the section explains how to bypass the harness" "$j" "ignore the folder"
assert_contains "H-131: the section says work is not blocked without the harness" "$j" "not blocked"
assert_contains "H-131: the section explains how to set the harness up" "$j" "/harness:config"
assert_contains "D19: the config-folder README says the harness is optional" "$(cat "$folder")" "do not need the harness"
assert_contains "D19: the config-folder README says how to set it up" "$(cat "$folder")" "/harness:config"

# H-130: the tested flow systems, and that others are possible but untested.
t=$(sed -n '/^## Tested with/,/^## /p' "$readme")
assert_contains "H-130: the README names the tested basic flow" "$t" "basic"
assert_contains "H-130: the README names the tested gsd flow" "$t" "gsd"
assert_contains "H-130: the README says other flow systems are untested" "$t" "not tested"

# No local paths, e-mail addresses or account names, except the public marketplace source.
owner=$(jq -r '.author.url' "$root/.claude-plugin/plugin.json" | sed 's#.*/##')
assert_eq "T43: the docs hold no local path" "" "$(grep -nE '/(Users|home)/[A-Za-z]|~/[A-Za-z]+/[A-Za-z]' $guide $folder || true)"
assert_eq "T43: the docs hold no e-mail address" "" "$(grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' $docs || true)"
assert_eq "T43: the account name appears only in the marketplace source line" "" \
  "$(grep -n -- "$owner" $guide $folder | grep -v '/plugin marketplace add' || true)"
