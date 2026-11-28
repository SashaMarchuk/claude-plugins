# Wave-2 follow-ups (#89): smaller launcher and flow guards.
h="$HO_PLUGIN_ROOT/bin/harness"

# ---- the validator role refuses --step (its prompt uses no step) ----
printf 'ticket body\n' | "$h" tickets fence 41 > ticket.txt
va=(--set RUN_ID 20261125-000000-abcdef --set TICKET_ID 41 --set BRANCH lane/t8 --set BASE trunk
  --set WORKDIR /work/lane --set VERDICT_FILE /run/verdict --set LANE t1 --set SHA 0123abc --file TICKET_TEXT ticket.txt)
rc=0; "$h" flow render basic validator --step plan "${va[@]}" >/dev/null 2>&1 || rc=$?
assert_eq "H-064 (#89): the validator role refuses --step (64)" 64 "$rc"
rc=0; "$h" flow render basic validator "${va[@]}" >/dev/null 2>&1 || rc=$?
assert_eq "H-064: the validator renders without --step" 0 "$rc"
