# H-125: plugin id stays harness; display name is Harness Orchestrator;
# version is a pre-release string other than 0.6.0.
m="$HO_PLUGIN_ROOT/.claude-plugin/plugin.json"

assert_eq "H-125 manifest id is harness" "harness" "$(jq -r '.name' "$m")"
assert_eq "H-125 display name is Harness Orchestrator" "Harness Orchestrator" "$(jq -r '.displayName' "$m")"

v=$(jq -r '.version' "$m")
if [ "$v" != "0.6.0" ]; then
  ok "H-125 version is not 0.6.0"
else
  bad "H-125 version is not 0.6.0" "version is $v"
fi
if printf '%s\n' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z.-]+$'; then
  ok "H-125 version is a pre-release string"
else
  bad "H-125 version is a pre-release string" "version is $v"
fi

assert_eq "H-125 bin/harness version prints the manifest version" "harness $v" "$("$HO_PLUGIN_ROOT/bin/harness" version)"
