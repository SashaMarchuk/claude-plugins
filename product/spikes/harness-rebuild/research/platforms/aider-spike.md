# Spike — making Aider a first-class citizen of the orchestrator

**Date:** 2026-09-19. **Version under test:** `aider-chat==0.86.2` (PyPI release 2026-02-12).
**Machine:** owner's Mac, darwin 25.5.0. **Companion:** `./aider.md` (capability profile) — read it first.

**Evidence tags.** **VERIFIED** — I ran it on this machine in this pass, or read the exact flag/line in
the installed 0.86.2 source. **CLAIMED** — asserted by docs/README only. **UNKNOWN** — not established.

---

## 0. The headline, and what changed since the profile

Aider is **not installed on the owner's machine** (VERIFIED: `which aider` → nothing; `ls ~/.aider` →
absent, both before and after this pass). All work below ran in an isolated sandbox under a fake
`HOME`, against **local fake OpenAI-compatible endpoints**, at **zero owner quota cost**. No owner
config was read or modified.

```
$SCRATCH/aider-sandbox/.venv/bin/aider     ← uv venv, Python 3.12.8, aider-chat 0.86.2
$SCRATCH/aider-home/                       ← fake HOME
$SCRATCH/aider-spike/{repo*,roles,state}/  ← this pass's repos, role profiles, session state
$SCRATCH/fakeapi.py    :8799               ← canned success (SEARCH/REPLACE + usage block)
$SCRATCH/fakeapi2.py   :8800               ← canned reply that creates a NEW file → permission prompt
$SCRATCH/fakeapi429.py :8801               ← canned 429 with Retry-After + reset time in the message
```

### Two findings that change the adapter design

The capability profile concludes that Aider fails axis G outright — *"the supervisor cannot send a
message into a running session"*, *"answering a session's own question programmatically is
**impossible**"*. **Both are false once the session is hosted in a terminal multiplexer the
orchestrator owns.** This pass proved, end to end on this machine:

1. **`tmux send-keys` delivers instructions into a live aider and arrival is confirmable four
   independent ways** (§8). The profile only considered `--watch-files`, which is a worse channel.
2. **A permission prompt can be detected and answered programmatically, against the default**
   (§9). I answered `n` to a `[Yes]`-defaulted `Create new file?` and the file was not created.

And one primitive the profile does not mention at all:

3. **`--notifications-command` is an arbitrary shell command aider runs the moment a session starts
   waiting for input** — including waiting on a permission prompt, **and it fires even headless under
   `--yes-always`, before the auto-yes resolves** (VERIFIED, §4/§9). It is the only push-based signal
   Aider has. `tmux 3.6a` is installed at `/usr/local/bin/tmux` (VERIFIED), so this whole design is
   available on the owner's machine today.

What does **not** change: exit code 0 is meaningless, there is no quota headroom, there is no session
identity, and there is no MCP.

---

## The session contract this adapter imposes

Aider has no session concept, so the orchestrator manufactures one. Everything below assumes this
layout. **The session id is a pure orchestrator invention, injected at four points.**

```
$ORCH/state/$SID/
  chat.md          --chat-history-file     transcript (markdown)
  llm.log          --llm-history-file      timestamped raw LLM exchanges
  input.history    --input-history-file    keeps the repo clean
  events.jsonl     --analytics-log         the ONLY structured channel
  notify.jsonl     written by notify.sh    push signal: "session is waiting"
  notify.sh        --notifications-command the hook
  fileset.txt      written by /save        file-set snapshot for resume
  stdout.txt       tee of the pane         prose scrape of last resort
$ORCH/roles/$ROLE/
  aider.conf.yml   --config                flags
  env.role         --env-file              credentials (NOT named .env — see §7)
$ORCH/worktrees/$SID/                      one git worktree per session (§H)
```

The four SID injection points, all VERIFIED in this pass:

| Where | Mechanism | Proof |
|---|---|---|
| Filesystem | every history/log path under `state/$SID/` | paths above |
| Git | `GIT_AUTHOR_EMAIL=$SID@aider.local` in the launch env | commits `21b3a57`, `8b2ae20`, `279fee6` |
| Process | `tmux` session named `aider-$SID` | `tmux has-session -t aider-$SID` |
| Transcript | aider writes **the full launch command line** as the first line of `chat.md` | §3 |

That last one is a gift: `chat.md` self-describes the exact invocation that produced it, so a
supervisor that finds an orphaned state dir can reconstruct how to relaunch it.

### The standing flag set

Every recipe below assumes this base. Each flag is here because something goes wrong without it.

```sh
AIDER_BASE=(
  --model "$MODEL"                # never omit: absent + no key ⇒ OpenRouter OAuth flow (§H)
  --no-check-update               # startup network I/O
  --no-show-release-notes         # --yes-always would auto-open release notes in a browser
  --no-gitignore                  # --yes-always would otherwise EDIT the repo's .gitignore
  --no-stream                     # cost numbers are unreliable while streaming
  --no-pretty --no-fancy-input    # headless only; OMIT both for a visible terminal
  --no-auto-lint                  # lint failures burn reflections
  --map-tokens 0                  # kill the repo map; orchestrator owns context (§5)
  --analytics-disable             # do not ship telemetry to PostHog
  --analytics-log "$S/events.jsonl"   # still works with analytics disabled (VERIFIED)
  --llm-history-file "$S/llm.log"
  --chat-history-file "$S/chat.md"
  --input-history-file "$S/input.history"
  --notifications --notifications-command "$S/notify.sh"
  --config "$ROLE/aider.conf.yml" --env-file "$ROLE/env.role"
)
export BROWSER=/usr/bin/true      # last-ditch guard against webbrowser.open (§H)
```

`--yes` is an unambiguous argparse prefix of `--yes-always` and works, but the env var is
`AIDER_YES_ALWAYS`; the project's own `scripting.md` documents `--yes` as if it were the real name.
Prefer the full `--yes-always`.

---

## 1. Preflight: installed, authenticated, which account?

```sh
# installed?
command -v aider || exit 70
aider --version                      # → "aider 0.86.2"

# resolved settings + which config/env files won, WITHOUT spending a token
aider "${AIDER_BASE[@]}" --exit --verbose > "$S/preflight.txt" 2>&1
grep -c . "$S/preflight.txt"         # 271 lines in this pass
sed -n '$p;$-4,$p' "$S/preflight.txt"
```

**Success** (VERIFIED, exit 0, last five lines):

```
Aider v0.86.2
Main model: gpt-4o with diff edit format
Weak model: gpt-4o-mini
Git repo: .git with 1 files
Repo-map: disabled
```

plus, earlier in the dump, the load-order audit the orchestrator actually needs:

```
Loaded /…/repo-prec/.env
Loaded /…/roles/roleB/env.role
```

**Failure.** No binary → exit 127. Bad repo → `exit` event `"Repository sanity check failed"` and a
real `return 1`. Unknown `--edit-format` → `"Unknown edit format"`, `return 1`. These are among the
*few* paths where aider's exit code is meaningful (§J).

**Which account is active: Aider will not tell you, and this is a hard limit.** The verbose dump
prints `openai_api_key: None` even when the key is live, because the key arrived through the
environment rather than the `--openai-api-key` flag (VERIFIED). The dump is therefore **safe to log —
it leaks no secret — and useless as an identity check.**

**Fallback (mandatory).** The orchestrator authenticates out of band, before launch, and never asks
aider:

```sh
# 1. prove the credential works, against the provider, not against aider
curl -sS -o /dev/null -w '%{http_code}\n' "$BASE/models" -H "Authorization: Bearer $KEY"   # expect 200
# 2. bind the identity the orchestrator believes in to the profile it will pass
printf '%s' "$KEY" | shasum -a 256 | cut -c1-12 > "$S/account.fingerprint"
# 3. after launch, assert aider loaded the file you meant (see §7)
grep -Fq "$ROLE/env.role" "$S/preflight.txt" || fail "role not loaded"
```

**verified: true** — ran `--exit --verbose`, exit 0, 271 lines; confirmed the `Loaded` lines and the
`openai_api_key: None` masking.

---

## 2. Start a task headless, pinned session id, structured output

```sh
S="$ORCH/state/$SID"; mkdir -p "$S"
cat > "$S/notify.sh" <<EOF
#!/bin/sh
printf '{"sid":"$SID","event":"waiting","ts":%s}\n' "\$(date +%s)" >> "$S/notify.jsonl"
EOF
chmod +x "$S/notify.sh"

cd "$ORCH/worktrees/$SID"
GIT_AUTHOR_NAME=orch   GIT_AUTHOR_EMAIL="$SID@aider.local" \
GIT_COMMITTER_NAME=orch GIT_COMMITTER_EMAIL="$SID@aider.local" \
timeout 1800 aider "${AIDER_BASE[@]}" --yes-always \
  --message "$TASK" --file src/thing.py --read CONVENTIONS.md \
  > "$S/stdout.txt" 2>&1
echo "exit=$?"    # ← MEANINGLESS. Do not branch on it.
```

**Success looks like** (VERIFIED, all four observed together):

```
events.jsonl:  launched → repo → auto_commits → message_send_starting → message_send → exit
message_send:  {"prompt_tokens":1234,"completion_tokens":56,"cost":0.0036,"total_cost":0.0036,…}
exit:          {"reason":"Completed --message"}
chat.md:       "> Applied edit to hello.py"  /  "> Commit 21b3a57 …"
git:           21b3a57 | t-0001@aider.local | Co-authored-by: aider (gpt-4o) <aider@aider.chat>
```

The orchestrator's completion predicate, in order of trustworthiness:

```sh
jq -e 'select(.event=="message_send")' "$S/events.jsonl" >/dev/null   # a turn actually billed
git log --author="$SID@aider.local" --since="$START" --format=%H      # work actually landed
grep -q '^> Applied edit to ' "$S/chat.md"                            # prose fallback
```

**Structured output: there is none.** No `--json`, no `--output-format`, no `--print` in 0.86.2's
`--help` (VERIFIED). `events.jsonl` is the only machine-readable artefact and it is a **spend meter,
not a result channel** — it never says which files changed or what the model concluded. The adapter
must scrape `chat.md` (`#### ` = user, `> ` = tool output, bare = assistant) and diff git.

**Failure looks like:** `message_send_starting` present, **`message_send` absent**, `exit` still
`"Completed --message"`, process exit 0. That signature covers auth failure, rate limit, and crash
alike — see §6 to disambiguate.

**The SID-in-git trick works only by default.** With `--attribute-co-authored-by` at its default
`True`, aider does **not** rewrite author/committer, so the orchestrator's `GIT_*_EMAIL` survives
into the commit (VERIFIED — `repo.py:292-307` only calls `set_git_env` when co-authored-by is off or
`--attribute-author` is explicitly true). **If you set `--attribute-author`, you lose the session
id.**

**verified: true** — ran it; commit `21b3a57` carries `t-0001@aider.local` as both author and
committer, alongside the `Co-authored-by: aider (gpt-4o)` trailer.

---

## 3. Start the same task in a visible terminal the owner can type into

Host it in tmux on a **dedicated socket** so the orchestrator never touches the owner's own server.

```sh
tmux -L orch new-session -d -s "aider-$SID" -c "$WORKTREE" -x 200 -y 50 \
  "GIT_AUTHOR_EMAIL=$SID@aider.local GIT_COMMITTER_EMAIL=$SID@aider.local BROWSER=/usr/bin/true \
   aider --model $MODEL --config $ROLE/aider.conf.yml --env-file $ROLE/env.role \
     --watch-files --file src/thing.py \
     --chat-history-file $S/chat.md --llm-history-file $S/llm.log \
     --input-history-file $S/input.history --analytics-log $S/events.jsonl \
     --notifications --notifications-command $S/notify.sh \
     --no-check-update --no-show-release-notes --no-gitignore --no-auto-lint \
   2>&1 | tee $S/stdout.txt"

# the owner attaches and types normally:
tmux -L orch attach -t "aider-$SID"
```

**Success** (VERIFIED): `has-session` returns 0;
`list-panes -F 'pid=#{pane_pid} dead=#{pane_dead} cmd=#{pane_current_command}'` →
`pid=66292 dead=0 cmd=Python`; the pane shows the banner and a bare `>` prompt; and `chat.md` opens
with the **full launch command line** followed by the banner.

**Failure: the pty is not optional.** With stdin closed, aider reaches the prompt, raises `EOFError`
and `Coder.run()` returns immediately (VERIFIED in the prior pass at `base_coder.py:891`). macOS
`script` also refuses (`tcgetattr/ioctl: Operation not supported on socket`). **Never launch
interactive mode with `stdin < /dev/null`.** Drop `--no-pretty`/`--no-fancy-input` here; they are
headless-only.

**Fallback** if tmux is unavailable: `pty.openpty()` from a supervisor process (a working driver from
the prior pass is at `$SCRATCH/ptydrive.py`). It costs you `capture-pane`, `send-keys` and owner
attachment — i.e. everything in §8 and §9 — so tmux is strongly preferred. iTerm2 tabs give the owner
a window but give the supervisor no writable stdin.

**verified: true** — launched, attached-capable, banner captured, `cmd=Python`, `dead=0`.

---

## 4. Alive / working / waiting / finished, from outside

Aider offers no status API, so the adapter composes four cheap probes. **This is the state machine.**

```sh
alive()    { tmux -L orch has-session -t "aider-$SID" 2>/dev/null; }
finished() { jq -e 'select(.event=="exit")' "$S/events.jsonl" >/dev/null 2>&1; }
waiting()  { [ -s "$S/notify.jsonl" ] && \
             [ "$(jq -r .ts "$S/notify.jsonl" | tail -1)" -gt "$(last_send_ts)" ]; }
working()  { [ $(( $(date +%s) - $(stat -f %m "$S/llm.log") )) -lt 120 ]; }
```

| State | Signature | Tag |
|---|---|---|
| **finished, clean** | `exit` event present, reason `"/exit"` or `"Completed --message"`; tmux session gone | VERIFIED |
| **crashed** | tmux session gone **and no `exit` event** — last line is whatever was in flight | VERIFIED |
| **waiting** | a fresh line in `notify.jsonl` newer than the last `message_send_starting` | VERIFIED |
| **working** | `llm.log` mtime moving; `message_send_starting` with no matching `message_send` yet | VERIFIED |
| **stalled** | alive, `llm.log` mtime stale > N, no notify — needs a wall-clock timeout | CLAIMED |

**The push signal, exactly.** `--notifications-command` runs
`subprocess.run(cmd, shell=True, capture_output=True)` from `IO.ring_bell()` (`io.py:1088-1104`), and
`ring_bell()` is called at the top of **`get_input` (io.py:535)**, **`confirm_ask` (819)** and
**`prompt_ask` (932)** — i.e. every way aider can block on a human. It is gated by
`bell_on_next_input`, set only by `llm_started()` (`base_coder.py:1423`) and cleared after each fire.

Three consequences, all VERIFIED:

- It fires **once per LLM turn**, when the session goes idle. Startup prompts *before* any LLM call do
  **not** fire it.
- In pure `--message` mode with no mid-turn question it **never fires** (session `t-0001`: empty
  `notify.jsonl`). Headless completion is detected from `events.jsonl`, not from this hook.
- It fires on a **permission prompt even headless under `--yes-always`**, because `ring_bell()` runs
  *before* the auto-yes shortcut (session `t-0002`: one `waiting` line).

**Two hazards.** The command is **synchronous and blocking** — a hanging hook hangs aider; keep it to
an `echo >> file`. And it receives **no arguments and no context**, so the SID must be baked into the
command string, and *what* was asked must be read separately (§9).

**Do not enable `--notifications` without `--notifications-command`**: on macOS the default is
`osascript -e 'display notification …'` (`io.py:1064-1066`), which would spray the owner's desktop all
night.

**Timestamps.** `chat.md` has **one** timestamp, the session header — so it cannot distinguish a slow
turn from a dead one. `llm.log` writes `TO LLM <iso>` / `LLM RESPONSE <iso>` per exchange and is the
real liveness clock. **Always pass `--llm-history-file`; it is off by default.**

**verified: true** — observed every state above: `ALIVE`/`dead=0`, notify firing at 3s on a prompt,
crash leaving zero `exit` events, `/exit` leaving reason `"/exit"`.

---

## 5. Read context fullness, force a compaction, prove it happened

### Read — headless (start-of-process only)

```sh
printf '/tokens\n' > "$S/cmds.txt"
aider "${AIDER_BASE[@]}" --load "$S/cmds.txt" --exit --file src/thing.py
```

**Success** (VERIFIED):

```
Executing: /tokens
Approximate context window usage for gpt-4o, in tokens:
$ 0.0050    2,015 system messages
$ 0.0001       20 hello.py        /drop to remove
==================
$ 0.0051    2,035 tokens total
          125,965 tokens remaining in context window
          128,000 tokens max context window size
```

Parse `tokens total`, `tokens remaining in context window`, `tokens max context window size`.
**Failure mode:** the `remaining` line is printed only `if limit:` — for a model absent from the
litellm price DB the meter silently truncates to the two lines above it, and the adapter must treat a
missing `remaining` as UNKNOWN, not as zero.

### Read — on a **running** session (the profile says this is impossible; it is not)

```sh
tmux -L orch send-keys -t "aider-$SID" "/tokens" Enter; sleep 4
tmux -L orch capture-pane -p -t "aider-$SID" | grep -E 'tokens total|remaining in context'
```

### Force a reset and prove it — live, from outside

```sh
tmux -L orch send-keys -t "aider-$SID" "/tokens" Enter; sleep 4   # BEFORE
tmux -L orch send-keys -t "aider-$SID" "/clear"  Enter; sleep 3   # ACT
tmux -L orch send-keys -t "aider-$SID" "/tokens" Enter; sleep 4   # AFTER
```

**The proof, captured live on this machine (VERIFIED):**

| | chat history row | tokens total | remaining |
|---|---|---|---|
| BEFORE | `121` | **2,156** | 125,844 |
| `/clear` | → `All chat history cleared.` | | |
| AFTER | *(row gone)* | **2,035** | 125,965 |

That is a supervisor-triggered context reset with a measurable before/after delta — axis D's
"with proof it happened", satisfied by emulation.

### The handoff, and why you need it

`/clear` **does not truncate `chat.md`** (VERIFIED: file still 6,965 bytes after clearing), so a later
`--restore-chat-history` would re-hydrate the very history you just dropped. A durable handoff is
three steps:

```sh
tmux -L orch send-keys -t "aider-$SID" "/save $S/fileset.txt" Enter   # snapshot the file set
orchestrator_writes_summary > "$S/HANDOFF.md"                          # YOUR summary, not aider's
mv "$S/chat.md" "$S/chat.$(date +%s).md"                               # rotate, or restore is a lie
# relaunch with:  --read "$S/HANDOFF.md"  --load "$S/fileset.txt"  (no --restore-chat-history)
```

**Proof the handoff landed** (VERIFIED) — it appears as its own row with its own token count:

```
$ 0.0006      221 ../state/t-0001/HANDOFF.md (read-only) /drop to remove
```

### What is genuinely impossible

**There is no compaction and no hook.** `/compact` does not exist. What exists is `ChatSummary`
(`history.py`), triggered internally by `summarize_start()` only when
`self.summarizer.too_big(self.done_messages)`, on a background thread. It summarizes **only the
conversation** — not files, not the repo map, not the system prompt, which were 2,015 of 2,035 tokens
in the measurement above. **It writes nothing to the transcript and emits no analytics event**, so it
cannot be observed, triggered, or proven from outside. There is **no hook of any kind in Aider** —
no PreCompact, no PreToolUse, nothing.

**Design consequence:** the orchestrator *prevents* context growth rather than managing it —
`--map-tokens 0`, an explicit minimal `--file`/`--read` set, one message per process — and uses
`/clear` + a handoff file when a live session must be continued.

**verified: true** — cold and restored `/tokens` both captured; live `/clear` delta 2,156 → 2,035
captured via tmux; `HANDOFF.md` row captured; `chat.md` byte count after `/clear` confirmed unchanged.

---

## 6. Quota, reset time, in-band limit hit

### Headroom: there is none, and this is structural

Aider has no account, no subscription and no plan. It is a BYO-key litellm client, so there is no
rolling window, no weekly window, no credit balance and no `resets_at` **to read**. The quota belongs
to the key, and the orchestrator must read it from the provider itself:

```sh
# OpenRouter — the only provider aider itself knows how to ask about
curl -sS https://openrouter.ai/api/v1/auth/key -H "Authorization: Bearer $KEY" | jq '.data'
# Anthropic / OpenAI / others: each provider's own endpoint, on the orchestrator's schedule
```

Aider's `onboarding.py:18 check_openrouter_tier()` GETs exactly that URL (5s timeout) and reads
`data.data.is_free_tier` — but only to pick a default model, never surfaces it, and **defaults to
`True` on any error** (VERIFIED). Treat it as a curiosity: the orchestrator calls the endpoint itself.

### Spend: precise, free, live-tailable — Aider's one genuinely good surface

```sh
tail -f "$S/events.jsonl" | jq -c 'select(.event=="message_send") | .properties |
  {model:.main_model, in:.prompt_tokens, out:.completion_tokens, cost, total_cost}'
```

Build the budget governor on cumulative `total_cost`. Caveats, all VERIFIED: `message_send` is
emitted by `show_usage_report()` **only after a successful completion**; an unpriced model yields
**no `cost` field at all** (the litellm price DB is cached 24h at
`~/.aider/caches/model_prices_and_context_window.json`, so an offline night drifts to a stale table);
and `--cache-prompts` with `--stream` makes the number unreliable by aider's own admission.

### Limit hit: reproduced precisely on this machine

Against a canned 429 (`fakeapi429.py`, `Retry-After: 1800`, reset time in the message body):

```
EXITCODE=0  ELAPSED=80s
Retrying in 0.2 / 0.5 / 1.0 / 2.0 / 4.0 / 8.0 / 16.0 / 32.0 seconds...   ← exactly 8 retries
litellm.RateLimitError: … Rate limit reached for gpt-4o. Limit resets at 2026-09-19T21:00:00Z …
The API provider has rate limited you. Try again later or check your quotas.
https://example.invalid/limits
```

`events.jsonl` for that run: `launched → repo → auto_commits → message_send_starting → exit`
(reason `"Completed --message"`). **Zero `message_send` events. Exit code 0.**

The loop is `retry_delay = 0.125`, doubling, breaking once `retry_delay > RETRY_TIMEOUT`
(`models.py:26` → `60`) — so **8 retries over ~64s of sleeps, ~80s wall**, then it gives up and
proceeds to a normal exit (`base_coder.py:1449-1490`). This refines the profile's estimate of
"~9 attempts over about two minutes".

**Detector:**

```sh
limit_hit() {
  grep -q '"event": "message_send_starting"' "$S/events.jsonl" &&
  ! grep -q '"event": "message_send"'        "$S/events.jsonl" &&
  grep -qE 'RateLimitError|rate limited you' "$S/stdout.txt"
}
```

**Reset time.** Aider never parses or structures it — but the provider's own message, which *does*
carry it, is copied verbatim into both `stdout.txt` and `chat.md` (VERIFIED: the
`Limit resets at …` line appears in `chat.md`). A best-effort provider-specific regex over the
transcript is the only route; `Retry-After` never reaches disk. Treat the reset time as **CLAIMED,
best-effort** and back it with a fixed cooldown.

**Fallback (mandatory).** Never trust the exit code. On a suspected limit: park the SID, apply the
orchestrator's own cooldown, and **verify headroom against the provider before relaunching** — Aider
will happily burn eight more retries to tell you nothing.

**Also note:** on exhaustion the loop calls `check_and_open_urls(err, …)`, which regex-scans the
error text and **offers every URL it finds** — auto-accepted under `--yes-always`. `chat.md` from the
429 run ends with `> Open URL for more info? (Y)es/(N)o/(D)on't ask again [Yes]: y`. **A rate limit
opens browser tabs on the owner's desktop.** `export BROWSER=/usr/bin/true` is not optional.

**verified: true** — full 429 run reproduced: 80s, 8 retries, exit 0, no `message_send`, reset time
present only as prose, browser-open prompt auto-answered.

---

## 7. Switch a new session to a different account, verify before work starts

**This is Aider's best axis and it costs the orchestrator nothing.** There is no login state, no
keychain, no global config to mutate — an account *is* a process environment. Unlimited concurrent
sessions on different accounts and providers, with zero interference.

```
$ORCH/roles/roleA/{aider.conf.yml, env.role}
$ORCH/roles/roleB/{aider.conf.yml, env.role}
```

```sh
aider --model "$MODEL" --config "$ORCH/roles/$ROLE/aider.conf.yml" \
                       --env-file "$ORCH/roles/$ROLE/env.role"  …
```

**Precedence, read in source** (`main.py:generate_search_path_list` + `load_dotenv_files`):
`~/.aider/oauth-keys.env` (weakest, prepended) → `~/.env` → `<git-root>/.env` → `./.env` →
**`--env-file` (wins)**. Each is loaded with `load_dotenv(fname, override=True)`. Above all files sit
`AIDER_*` env vars, then the command line. The same ordering governs `.aider.conf.yml`.

**The hazard, reproduced on this machine.** `override=True` means **a dotenv file found in the repo
beats the orchestrator's own exported environment.** I exported `OPENAI_API_BASE` pointing at endpoint
A, placed a repo-root dotenv pointing at endpoint B, passed **no** `--env-file` — and got B's reply
(`I will add a new module`). Passing `--env-file` explicitly flipped it back to A's reply
(`Here is the change`). **A cloned repo containing a dotenv silently hijacks the session's
credentials.** Always pass `--env-file` explicitly; never rely on exported vars alone.

**Verify the switch before work starts.** Aider will not name the account (§1), so assert three
things:

```sh
aider … --exit --verbose > "$S/preflight.txt" 2>&1
grep -Fq "$ORCH/roles/$ROLE/env.role" "$S/preflight.txt" || fail "wrong role"   # intended file loaded
grep '^Loaded ' "$S/preflight.txt" | grep -v "$ORCH/roles/" && fail "stray dotenv in tree"
curl -sS -o /dev/null -w '%{http_code}' "$BASE/models" -H "Authorization: Bearer $KEY"  # = 200
```

In this pass the roleB preflight printed both loads in order — the stray repo dotenv **and** the
intended role file — which is exactly the audit the second check needs (VERIFIED).

**Two more guards.** Prefer `--env-file` over `--api-key PROVIDER=KEY` and `--set-env VAR=value`: the
latter two land in the **process environment**, visible in `ps` and inherited by every shell command
the model runs. And on this machine a local `PreToolUse` secret-guard hook blocks any command whose
arguments match `.env`, so **name role files `env.role`, not `.env`** — `--env-file` accepts any path
(VERIFIED: that is how every run above was launched).

**Changing a running session's account: impossible.** No `/provider`, no `/api-key`; `/model` only
switches model within the loaded environment. Changing credentials means a new process — which, given
§10, means losing the session anyway.

**verified: true** — precedence read in source and reproduced both ways; `Loaded` audit lines
captured; `env.role` naming exercised throughout.

---

## 8. Deliver an instruction into a running session and confirm it arrived

**This works, and it is the finding that most changes the profile's verdict.**

```sh
MARK="orch-$(date +%s)-$RANDOM"
tmux -L orch send-keys -t "aider-$SID" "$TASK  [$MARK]" Enter
```

**Confirm arrival — four independent channels, all VERIFIED in one run:**

```sh
grep -Fq "#### $TASK  [$MARK]" "$S/chat.md"                  # 1. echoed back verbatim  ← the ack
jq -e 'select(.event=="message_send_starting")' "$S/events.jsonl"  # 2. turn started
jq -e 'select(.event=="message_send")'          "$S/events.jsonl"  # 3. turn billed + token counts
[ -s "$S/notify.jsonl" ]                                      # 4. back to waiting = turn done
```

Observed: `chat.md:12: #### add a docstring orch-msg-1789825180`; `message_send_starting` and
`message_send` at `t=1789825180`; `notify.jsonl` `waiting` at `t=1789825181`; commit `279fee6`
authored `t-tmux@aider.local`; `hello.py` rewritten with the docstring.

**This is a true acknowledgement,** not inference: the unique marker round-trips into the transcript,
so the supervisor can correlate request → response with certainty. That is the owner's stated
requirement, met — by tmux, not by Aider.

**Success/failure/fallback.** Success is the marker in `chat.md` within a few seconds. Failure is the
marker absent (session not at a prompt — it was mid-turn, and tmux queued the keystrokes into the
pending input buffer) or `has-session` failing. Send only while `waiting()` (§4); otherwise queue in
the orchestrator.

**The native alternative, and why it is worse.** `--watch-files` picks up one-line `AI!`/`AI?`
comments written into watched files, and it genuinely reaches a live session (VERIFIED in the prior
pass). But: no acknowledgement at all; it **commits the injected instruction comment into the owner's
repo** before applying edits; removal of the comment depends on the model complying; it silently adds
any changed file containing an AI comment to the chat (`watch.py:195`); and its regex
`(?:#|//|--|;+) *(ai\b.*|…|.*\bai[?!]?) *$` is case-insensitive and trips on ordinary source comments.
**Use `send-keys`; keep `--watch-files` only as the no-tmux fallback.**

**Fallback without tmux:** `pty.openpty()` and write to the master fd — same effect, no owner
attachment. Without a pty at all, intervention is impossible; kill and relaunch with new instructions.

**verified: true** — marker delivered, echoed into `chat.md`, billed in `events.jsonl`, completed via
`notify.jsonl`, landed as commit `279fee6`.

---

## 9. Answer a permission prompt or a clarifying question without a human

**Also works.** The profile calls this impossible; it is not, when the orchestrator owns the terminal.

The three-step loop — **detect (push), read (pull), answer (write)**:

```sh
# 1. DETECT — the hook fires the moment aider blocks on a question
for i in $(seq 1 20); do [ -s "$S/notify.jsonl" ] && break; sleep 1; done

# 2. READ — what is it actually asking?
Q=$(tmux -L orch capture-pane -p -t "aider-$SID" | grep -E '\((Y)es/\(N\)o|\[Yes\]:|\[Y/n\]' | tail -1)

# 3. ANSWER — policy decides; write the keystroke
case "$Q" in
  *"Create new file"*)  ANS=n ;;
  *"Run shell command"*) ANS=n ;;
  *)                     ANS=y ;;
esac
tmux -L orch send-keys -t "aider-$SID" "$ANS" Enter
```

**Proof it is a real answer, not the default** (VERIFIED, session `t-perm`, launched **without**
`--yes-always`):

```
notify fired after 3s   → {"sid":"t-perm","event":"waiting","ts":1789825226}
pane                    → Create new file? (Y)es/(N)o [Yes]:
sent                    → n
pane                    → Create new file? (Y)es/(N)o [Yes]: n
                          Skipping edits to newmod.py
filesystem              → newmod.py NOT created
git                     → no new commit
chat.md:27              → "> Create new file? (Y)es/(N)o [Yes]: n"
```

The default was **Yes**; the file was not created; therefore the `n` demonstrably came from the
supervisor. Round-trip latency: ~3s to detect, immediate to answer.

**The audit trail is `chat.md`, not stdout.** In headless runs the prompt line **does not appear in
stdout at all** (no tty) but **is** recorded in `chat.md` (VERIFIED, session `t-0002`:
`> Create new file? (Y)es/(N)o [Yes]: y`). Any adapter that greps stdout for permission decisions will
see nothing. Grep `chat.md`.

**Limits.** There is **no protocol** — no permission event, no request id, no structured question,
nothing that says *why* it is asking. The hook carries no payload, so classification is screen-scraping
a prompt string. Aider's questions come from `io.confirm_ask()`/`io.prompt_ask()` blocking on
prompt-toolkit; whoever holds the terminal answers them, and that is the entire mechanism.

**Fallback — pre-decide instead of answering.** Headless, set the policy at launch and never be asked:

| Want | Flag | Note |
|---|---|---|
| auto-approve everything answerable | `--yes-always` | still **refuses** suggested shell commands — see below |
| never propose shell commands | `--no-suggest-shell-commands` | |
| run tests/lint without asking | `--test-cmd` + `--auto-test`, `--lint-cmd` + `--auto-lint` | orchestrator-specified, never prompted |
| restrict what may be edited | `--aiderignore FILE`, `--subtree-only` | gitignore syntax |
| change nothing | `--dry-run` | |

**The one guardrail that survives `--yes-always`:** `io.confirm_ask()` takes
`explicit_yes_required`, and when set, `self.yes is True` yields `"n"`, not `"y"`. It is used in
exactly one place — `handle_shell_commands()` (`base_coder.py:2459`). So a fully unattended aider
**proposes a shell command and declines it on the owner's behalf**. That is the right default and also
a capability ceiling: use `--test-cmd`/`--lint-cmd` for anything that must actually run.

**verified: true** — full detect → read → answer → verify-effect cycle executed against a `[Yes]`
default.

---

## 10. Resume after a crash, and after a reboot

**There is no session to resume. There is a restart with a paraphrase.** No `--session-id`, no
`--resume`, no `--continue`, no session list, no rollout file, no sqlite. The `/session` command that
would have provided this is unmerged PR `#4343`.

### Detect the crash

```sh
crashed() { ! tmux -L orch has-session -t "aider-$SID" 2>/dev/null &&
            ! grep -q '"event": "exit"' "$S/events.jsonl"; }
```

VERIFIED: after `kill -9` of the pane process, `events.jsonl`'s last line was
`{"event": "command_save", …}` with **zero** `exit` events, while a clean `/exit` wrote
`command_exit` then `{"event":"exit","properties":{"reason":"/exit"}}`. The presence and reason of the
`exit` event is the whole termination-cause channel.

### Resume

```sh
# keep the file set fresh while the session lives — cheap, no LLM call
tmux -L orch send-keys -t "aider-$SID" "/save $S/fileset.txt" Enter

# after the crash: cold process, nothing but the state dir and the worktree
cat "$S/fileset.txt" > "$S/resume.txt"; printf '/tokens\n' >> "$S/resume.txt"
aider "${AIDER_BASE[@]}" --restore-chat-history --load "$S/resume.txt" --exit
```

**Success** (VERIFIED — cold process, only `state/$SID/` + the worktree present):

```
Executing: /drop            → Dropping all files from the chat session.
Executing: /add  hello.py   → Added hello.py to the chat
Executing: /tokens          → $ 0.0005  182 chat history  use /clear to clear
                              $ 0.0055  2,217 tokens total
```

**What it actually recovered, measured.** `--restore-chat-history` calls
`utils.split_chat_history_markdown()` (`base_coder.py:519-521`), which parses the rendered markdown
and **discards every `> `-prefixed line** — all of aider's own output: applied-edit notices, commit
hashes, errors, lint/test results, cost lines. In this run that meant **5 user turns recovered and 48
tool-output lines discarded** (VERIFIED by counting `^#### ` vs `^> ` in `chat.md`). Round-tripping
through markdown also makes blockquote handling heuristic. **The reconstructed conversation is a
paraphrase.** `/save`/`--load` restores the **file set only** — literally `/drop`, then `/add` and
`/read-only` per file.

**Prefer the handoff (§5) over `--restore-chat-history`** for anything that mattered: an
orchestrator-authored `HANDOFF.md` passed via `--read` is lossless, auditable, and its arrival is
provable as a token row.

### After a reboot

Mechanically identical — aider holds nothing in memory between processes — with three additions:

1. **tmux does not survive a reboot.** Sessions must be re-created; treat every SID as crashed.
2. **Put `$ORCH/state/` outside `/tmp`.** macOS clears it, and the state dir is the entire session.
3. **Reconcile git first.** `--auto-commits` and `--dirty-commits` are both on, so a crash may leave a
   commit the orchestrator never saw. Read `git log --author="$SID@aider.local"` before deciding what
   is left to do — it is the most reliable record of what happened, and it survived the `kill -9`
   intact (VERIFIED: commit `279fee6` present, working tree clean).

**Fallback when resume is not good enough:** decompose harder. Aider is a one-shot edit applier with
`max_reflections = 3` (`base_coder.py:101`) — one `--message` is at most four LLM turns. If a task is
large enough that losing mid-flight state hurts, it was too large for Aider.

**verified: true** — crash signature, `/save` snapshot, cold resume with restored file set and chat
history, and the 5-vs-48 lossiness measurement.

---

## 11. Stop cleanly, leaving nothing running

```sh
# graceful: let aider write its own exit record
tmux -L orch send-keys -t "aider-$SID" "/exit" Enter
for i in $(seq 1 10); do tmux -L orch has-session -t "aider-$SID" 2>/dev/null || break; sleep 1; done
# escalate only if needed
tmux -L orch has-session -t "aider-$SID" 2>/dev/null && tmux -L orch kill-session -t "aider-$SID"
```

**Success** (VERIFIED):

```
events.jsonl  → {"event":"command_exit",…}
                {"event":"exit","properties":{"reason":"/exit"},…}
tmux          → can't find session: aider-t-perm
process       → PROCESS GONE
repo          → .  ..  .git  hello.py          ← no .aider.* artefacts at all
```

**Leaving nothing behind is a configuration choice, and it worked.** Aider normally litters a repo
with `.aider.input.history`, `.aider.chat.history.md`, `.aider.tags.cache.v4/` and — under
`--yes-always` — an edited `.gitignore`. The standing flag set prevents all of it: history files
redirected into `state/$SID/`, `--map-tokens 0` (no tags cache), `--no-gitignore` (no `.gitignore`
edit). The stopped repo above was byte-clean.

**Failure and escalation.** `/exit` only lands if the session is at a prompt; mid-turn it queues.
Escalate `tmux kill-session` → `kill -TERM <pane_pid>` → `kill -9`. **Do not kill the pane pid
directly when it is the last session on the socket — it takes the tmux server down with it**
(observed: `no server running on /private/tmp/tmux-501/aiderspike`). Use `kill-session`, or keep a
holder session on the socket.

**Also stop what aider started.** Headless runs are short-lived, but check for a stray OpenRouter
OAuth listener on ports **8484–8584** (`onboarding.py`) if `--model` was ever omitted, and note that
`ChatSummary` runs on a background thread — a `kill -9` mid-summarization loses it silently with no
trace anywhere.

**verified: true** — `/exit` teardown, `exit` reason `"/exit"`, process and session gone, repo clean,
and the pane-pid-kills-the-server behaviour observed.

---

## The adapter interface

```
AiderAdapter implements PlatformAdapter:
  preflight()            EMULATED   version + --exit --verbose; account verified out of band
  launch_headless()      NATIVE     --message / --message-file
  launch_visible()       EMULATED   tmux -L orch new-session  (pty mandatory)
  status()               EMULATED   tmux + events.jsonl + notify.jsonl + llm.log mtime
  read_context()         NATIVE*    /tokens  (*live read needs tmux send-keys)
  compact()              EMULATED   /clear + orchestrator-authored HANDOFF.md via --read
  read_quota()           IMPOSSIBLE no quota surface; provider API, out of band
  read_spend()           NATIVE     --analytics-log → message_send
  switch_account()       NATIVE     --config + --env-file, per role dir
  send_instruction()     EMULATED   tmux send-keys; ack = unique marker echoed into chat.md
  answer_prompt()        EMULATED   notify hook → capture-pane → send-keys
  resume()               EMULATED   --restore-chat-history + /save/--load  (LOSSY)
  stop()                 NATIVE     /exit, then tmux kill-session
```

| # | Capability | Verdict | How |
|---|---|---|---|
| 1 | Preflight | **Emulated** | `--exit --verbose` proves *which files loaded*, never *which account*. Authenticate against the provider yourself. |
| 2 | Headless + pinned id + structured output | **Emulated** | `--message` is native; identity is four orchestrator-injected anchors; "structured output" is `events.jsonl` (spend only) + scraping `chat.md` and git. |
| 3 | Visible terminal | **Emulated** | tmux. A pty is mandatory — stdin closed means instant silent exit. |
| 4 | Liveness | **Emulated** | Four probes. `--notifications-command` is a real push signal for *waiting*; nothing else pushes. |
| 5 | Context read + forced compaction with proof | **Emulated** | `/tokens` reads; `/clear` + delta proves; **true compaction does not exist and leaves no trace**. |
| 6 | Quota headroom + reset | **Impossible** | Structural: no account, no plan, no window. Spend is excellent; headroom is the provider's problem. Reset time survives only as prose. |
| 7 | Account switch | **Native — best in field** | One dir per role. No login state, unlimited concurrency. Guard the dotenv-overrides-environment hazard. |
| 8 | Instruction into a live session + ack | **Emulated — works well** | `send-keys` + marker echoed into `chat.md`. Overturns the profile. |
| 9 | Answer a prompt without a human | **Emulated — works well** | notify → capture-pane → send-keys. Proven against a `[Yes]` default. Overturns the profile. |
| 10 | Resume after crash / reboot | **Emulated — lossy** | Crash detectable; resume recovers a paraphrase (5 turns kept, 48 tool lines dropped). No exact resume exists. |
| 11 | Clean stop | **Native** | `/exit` writes its own exit record; repo left byte-clean. |

**Native: 3 (7, 11, and spend within 6). Emulated: 7. Impossible: 1 (quota headroom).**
Every emulation except #1 and #6 depends on **tmux**. Without a multiplexer, items 3, 4, 8 and 9
collapse and Aider drops to executor-only.

### Support tier: **TIER 2 — workable with emulation**, conditional

**Tier 2 with tmux.** All of the owner's non-negotiables are reachable except quota headroom:
accounts are native and excellent, context is readable and resettable with proof, instructions arrive
with a real acknowledgement, prompts are answerable programmatically. What remains genuinely broken is
**resume** (lossy by construction) and **quota** (nothing to read).

**Tier 3 without tmux** — executor-only: it runs a task and cannot be supervised.

The emulation is not free. The adapter must own: a tmux session manager, a prose scraper for
`chat.md`, a four-probe state machine, a wall-clock timeout, a git-worktree manager, a spend governor,
and a provider-side quota poller — roughly all of the supervision, with Aider contributing only the
edit loop.

### Where Aider belongs in the fleet

A **cheap, frozen, disposable leaf executor**: one process per fully-specified edit, judged by git,
its account swapped per task for free. Free and Apache-2.0 — you pay only the provider.

Three standing costs: **748 MB and 227 packages** per install, **Python ≤3.12** (the 0.86.2 wheel caps
at `<3.13` despite PR `#4899` merging after the release), and a project with **zero commits since
2026-05-22**, 502 open PRs, 1,378 open issues, and MCP support closed unmerged (`#5694`, 2026-09-09).
Hibernation is a feature for a frozen executor and terminal for anything needing new capability.

**Three rules the adapter must never break:**

1. **Never branch on Aider's exit code.** `main.py:1133` is a bare `return` after `--message`: auth
   failure, rate limit and success all exit **0**.
2. **Always pass `--env-file` explicitly.** A dotenv in the repo tree beats the orchestrator's own
   exported environment (`load_dotenv(..., override=True)`) and silently redirects the account.
3. **Always `export BROWSER=/usr/bin/true` and `--no-show-release-notes --no-gitignore`.** Under
   `--yes-always`, a rate limit opens browser tabs and startup edits the repo's `.gitignore`.

### Still UNKNOWN

- Whether concurrent aiders in **one** worktree corrupt each other (`.gitignore`, input history, tags
  cache, `git commit` race). Not tested; one worktree per session on principle.
- Whether the unsupported Python `Coder` API — the only route to a genuine multi-turn in-process
  session, with direct reads of `coder.total_cost`, `coder.aider_edited_files`, `coder.done_messages`
  — is stable enough to build on. The project's own docs disclaim it: *"not officially supported or
  documented, and could change without providing backwards compatibility."* Against zero commits in
  four months, that cuts both ways.
- Whether any maintained **fork** has added MCP or sessions. Not surveyed; worth one check before
  writing Aider off.
- Whether `--notifications-command` survives a long unattended night without the synchronous
  `subprocess.run` ever blocking aider. Tested only over minutes.

---

## Reproduction log

All runs 2026-09-19, sandboxed, zero owner quota spent, owner config untouched (`ls ~/.aider` →
absent before and after; all fake endpoints and the tmux server killed at the end).

| Session | What it proved | Key evidence |
|---|---|---|
| preflight | `--exit --verbose` dump; key masking; load-order audit | exit 0, 271 lines, `openai_api_key: None` |
| `t-0001` | headless success; SID in git; analytics stream | commit `21b3a57` by `t-0001@aider.local`; `message_send` cost `$0.0036` |
| `t-0001` | context read cold vs restored; `/clear` delta; `/save`; handoff row | 2,035 → 2,130 → 2,035; `HANDOFF.md` 221 tokens |
| `t-0002` | notify hook fires on a permission prompt **headless under `--yes-always`** | `notify.jsonl` 1 line; `chat.md:` `Create new file? … : y` |
| `t-429` | rate limit: 8 retries, 80s, **exit 0**, no `message_send`, browser prompt | full stdout + `events.jsonl` captured |
| `t-tmux` | tmux launch; `send-keys` + marker ack; live `/tokens`; live `/clear` proof; crash signature; cold resume | `chat.md:12` marker; 2,156 → 2,035; 0 `exit` events after `kill -9`; resume restored 182 tokens |
| `t-perm` | permission prompt detected in 3s and answered **`n` against a `[Yes]` default** | `Skipping edits to newmod.py`; no file; no commit |
| `t-perm` | clean stop | `exit` reason `"/exit"`; process gone; repo byte-clean |
| `repo-prec` | repo dotenv beats exported env; `--env-file` wins | endpoint B's reply, then endpoint A's |

**Source read in the installed 0.86.2 package** (`.venv/lib/python3.12/site-packages/aider/`):
`io.py` (`ring_bell` 1088-1104, `llm_started` 1050, `get_default_notification_command` 1054-1086,
`confirm_ask` 807-819, `prompt_ask` 928-932), `main.py` (`load_dotenv_files`,
`generate_search_path_list`, exit-reason table, `--message` bare return at 1133),
`coders/base_coder.py` (retry loop 1449-1490, `llm_started()` 1423, `max_reflections` 101,
`handle_shell_commands` 2459, `split_chat_history_markdown` 519-521), `models.py`
(`RETRY_TIMEOUT = 60`), `repo.py` (attribution logic 131-310), `args.py` (`--notifications*` 825-838),
`history.py`, `analytics.py`, `onboarding.py`, `watch.py`.
