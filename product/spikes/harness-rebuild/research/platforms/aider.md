# Platform profile — Aider (`aider-chat`)

**Date of pass:** 2026-09-19. **Version examined:** **0.86.2** — the current PyPI release, uploaded
**2026-02-12T00:42:52Z**. **Machine:** owner's Mac (darwin 25.5.0).

**Evidence tags:** **VERIFIED** — read in shipped source, read in the project's own docs source, or
run on this machine. **CLAIMED** — asserted by a README/website only. **UNKNOWN** — could not be
established.

---

## 0. Method, and the one fact that reframes everything else

Aider was **not installed on this machine** (VERIFIED: `which aider` → not found; no `~/.aider`;
nothing Aider-shaped in `~/.claude`, `~/.codex`, `~/.gemini`, `~/.config`). Nothing of the owner's
was modified and no owner quota was spent.

So I built an isolated sandbox and ran the real thing:

```
/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/
  aider-sandbox/.venv/         ← uv venv, Python 3.12.8, aider-chat==0.86.2
  aider-home/                  ← fake HOME for every invocation
  aider-testrepo{,2,3}/        ← throwaway git repos
  aider-watch3/                ← throwaway git repo for the --watch-files test
  fakeapi.py                   ← local OpenAI-compatible endpoint on 127.0.0.1:8799
```

`fakeapi.py` is the reason this pass has success-path evidence at zero cost: it returns a canned
`chat.completion` carrying a real `usage` block and a real SEARCH/REPLACE edit, so aider applies
edits, commits them, computes cost and emits its telemetry — without touching a paid provider.
Every flag quoted below was confirmed against `./.venv/bin/aider --help` on 0.86.2, never from prose
alone.

### The fact that reframes the rest

**Aider is not an agent.** It is a one-shot edit applier with a bounded self-correction loop.
`base_coder.py:101` sets `max_reflections = 3` (VERIFIED), and a "reflection" is only triggered by
one of four things: the model asking for a file that is not in the chat, a lint failure, a test
failure, or a malformed edit block. There is no tool-calling loop, no planner, no autonomous
multi-step execution, no ability to read a file the orchestrator did not hand it. One `--message`
is at most four LLM turns and then the process is gone.

Everything in the contract below has to be read against that. Most of the orchestrator's axes are
not "weakly supported" in Aider — they are **not applicable**, because Aider has no long-lived
session to identify, resume, compact, or talk to. The unit of work is a process invocation.

### The second fact: the project has stopped moving

| Signal | Value | Tag |
|---|---|---|
| Latest PyPI release | `0.86.2`, **2026-02-12** — 7 months ago | VERIFIED (PyPI JSON) |
| Previous release | `0.86.1`, 2025-08-13 — a **6-month gap** before 0.86.2 | VERIFIED (PyPI JSON) |
| Latest GitHub *release* | `v0.86.0`, 2025-08-09 — 0.86.1/0.86.2 shipped to PyPI with no GitHub release | VERIFIED (GitHub API) |
| Last commit to `main` | **2026-05-22T14:02:20Z** — ~4 months ago | VERIFIED (GitHub API) |
| Commits since 2026-06-01 | **0** | VERIFIED (`GET /repos/Aider-AI/aider/commits?since=2026-06-01`) |
| Open issues | **1,378** | VERIFIED (GitHub search) |
| Open PRs | **502** | VERIFIED (GitHub search) |
| Stars / license | 49,053 / **Apache-2.0**, not archived | VERIFIED (GitHub API) |

The 2026 commit log is almost entirely one maintainer adding model-id metadata ("Expand
ANTHROPIC_MODELS list", "add gpt-5.5 model settings"). The last merged community PR of any substance
is `#5132` (2026-05-16). Aider is in de-facto hibernation: maintained enough to know new model names,
not maintained enough to merge features.

Three unmerged PRs matter directly to this workflow, because they are exactly the gaps found below:
- `#5694` "Native MCP client support" — **closed unmerged** 2026-09-09.
- `#4343` "Add `/session` command for chat session and file management" — open, unmerged.
- `#5638` "fix: fail unsupported slash commands in message mode" — open, unmerged. §I reproduces
  the bug it was written to fix.

Issue `#3314` "MCP SUPPORT" is still open and was last touched 2026-09-10.

---

## A. LAUNCH

**Headless: yes, and it is the only mode that works unattended. Structured output: no.**

| Flag | Meaning | Env var | Tag |
|---|---|---|---|
| `--message COMMAND` / `--msg` / `-m` | "Specify a single message to send the LLM, process reply then exit (disables chat mode)" | `AIDER_MESSAGE` | VERIFIED (`--help`) |
| `--message-file MESSAGE_FILE` / `-f` | same, read from a file | `AIDER_MESSAGE_FILE` | VERIFIED |
| `--load LOAD_FILE` | "Load and execute /commands from a file on launch" | `AIDER_LOAD` | VERIFIED |
| `--exit` | "Do all startup activities then exit before accepting user input (debug)" | `AIDER_EXIT` | VERIFIED |
| `--yes-always` | "Always say yes to every confirmation" | `AIDER_YES_ALWAYS` | VERIFIED |
| `--no-pretty`, `--no-stream`, `--no-fancy-input` | plain, unstyled, non-prompt-toolkit output | `AIDER_PRETTY` etc. | VERIFIED |
| `--file FILE`, `--read FILE` | editable / read-only files (repeatable) | `AIDER_FILE`, `AIDER_READ` | VERIFIED |
| `--dry-run` | "Perform a dry run without modifying files" | `AIDER_DRY_RUN` | VERIFIED |

A worked, verified invocation (this exact command ran on this machine):

```
aider --model gpt-4o --message "add a docstring" hello.py \
  --yes --no-check-update --no-stream --no-pretty --no-fancy-input --no-show-release-notes \
  --analytics-log run.jsonl --chat-history-file chat.md --llm-history-file llm.md --no-analytics
```

Note `--yes` works: it is an unambiguous argparse prefix of `--yes-always`, the only option starting
with `--yes` (VERIFIED — the run above used `--yes` and the confirmations were auto-answered). The
project's own `docs/scripting.md` still documents `--yes` as if it were the real flag name; it is
not, and the env var is `AIDER_YES_ALWAYS`.

**There is no JSON or stream-JSON output mode.** `--help` on 0.86.2 has no `--output-format`, no
`--json`, no `--print`. The only machine-readable artefact aider produces is the analytics JSONL
(§E), and it is telemetry, not a result channel. Everything the orchestrator would want to know —
did the edit apply, what files changed, what did the model say — must be scraped from stdout
prose, from the markdown chat log, or from git.

**Visible terminal the owner can attach to: yes, but only as an ordinary TUI.** Aider's interactive
mode is a prompt-toolkit REPL. There is no attach/detach, no server, no socket. "Attaching" means
the orchestrator launched it inside a terminal the owner can look at (iTerm tab, tmux pane) and the
owner types into that terminal by hand. The supervisor cannot share that stdin.

**A verified hazard: stdin must stay open in interactive mode.** With `stdin < /dev/null`, aider
reaches the prompt, raises `EOFError`, and `Coder.run()` returns immediately (VERIFIED —
`base_coder.py:891`, reproduced: a `--watch-files` session launched with stdin closed exited within
seconds having done nothing). Any interactive-mode launch must be given a real pty. In this pass I
had to drive it through `pty.openpty()` because macOS `script` also refused
(`script: tcgetattr/ioctl: Operation not supported on socket`).

---

## B. IDENTITY & RESUME — *the owner's non-negotiable*

**There is no session identity. There is no exact resume. This is the axis Aider fails hardest.**

- **No `--session-id`.** Nothing in `--help` assigns, prints, or accepts a session identifier
  (VERIFIED). Sessions are not entities; they are process lifetimes.
- **No `--resume`, no `--continue`, no session list.** The `/session` command that would have
  provided this is unmerged PR `#4343`.
- **No crash-recovery state.** There is no rollout file, no sqlite, no index. If the process dies
  mid-turn, the only thing that survives is whatever was already flushed to the markdown chat log
  and whatever git commits already landed.

**The closest workaround, and exactly what it recovers.** Two pieces, used together:

1. `--restore-chat-history` (`AIDER_RESTORE_CHAT_HISTORY`, default False) re-reads
   `--chat-history-file` and re-hydrates the conversation. **VERIFIED that it works** — in a
   three-run experiment, `/tokens` reported no "chat history" row on a cold run and a
   `93  chat history  use /clear to clear` row on the same cold start with
   `--restore-chat-history` added.
2. `/save FILE` writes a command file that reconstructs the **file set only** — literally `/drop`,
   then one `/add <rel>` per editable file and `/read-only <path>` per read-only file
   (VERIFIED, `commands.py:cmd_save`). `--load FILE` replays it.

**What that workaround costs.** The restore is lossy by construction. `restore_chat_history` calls
`utils.split_chat_history_markdown()` (VERIFIED, `base_coder.py:519-521`), which parses the rendered
markdown transcript and **discards every `> `-prefixed line** — that is, all of aider's own output:
applied-edit notices, commit hashes, errors, lint and test results, cost lines. Only `#### `-prefixed
user turns and un-prefixed assistant prose are rebuilt. Round-tripping through markdown also means
blockquote stripping and line handling are heuristic. The reconstructed conversation is a paraphrase
of the old one, not the old one.

The honest summary for the orchestrator: **Aider cannot be resumed; it can be restarted with a
summary of what happened before.** That is acceptable for a stateless "apply this edit" executor and
unacceptable for a long-horizon task that was halfway through a plan.

---

## C. TRANSCRIPT

**Three files, all plain text, all append-only, all live-readable. None is structured.**

| File | Default | Flag / env | Format |
|---|---|---|---|
| Chat transcript | `.aider.chat.history.md` (git root) | `--chat-history-file` / `AIDER_CHAT_HISTORY_FILE` | Markdown |
| Raw LLM log | *(off)* | `--llm-history-file` / `AIDER_LLM_HISTORY_FILE` | line-prefixed text |
| Input history | `.aider.input.history` | `--input-history-file` / `AIDER_INPUT_HISTORY_FILE` | prompt-toolkit history |
| Telemetry | *(off)* | `--analytics-log` / `AIDER_ANALYTICS_LOG` | **JSONL** — see §E |

All VERIFIED from `--help` and from the files produced by the runs above.

**The chat transcript.** Written by `io.append_chat_history()` (`io.py:1117`), opened in `"a"` mode
per write and closed again — so a supervisor `tail -f` sees it live, and a crash loses at most the
current line. Its grammar, verified from a real run:

```
# aider chat started at 2026-09-19 20:28:57      ← session header, only timestamp in the file

> You can skip this check with --no-gitignore    ← every line of aider's own output, blockquoted
> Aider v0.86.2
> Added hello.py to the chat.

#### add a docstring                             ← the user turn

Here is the change.                              ← the assistant turn, verbatim, unprefixed
hello.py
```python
<<<<<<< SEARCH
...
```

> Tokens: 1.2k sent, 56 received. Cost: $0.0036 message, $0.0036 session.
> Applied edit to hello.py
> Commit 4d6d04b Here is the change.
```

A supervisor can parse this: `#### ` = user, `> ` = tool output, bare = assistant. It can watch for
`> Applied edit to `, `> Commit <sha> `, `> Tokens: `. But there are **no per-message timestamps** —
only the one session header — so the supervisor cannot tell a stalled session from a slow one by
reading the file. Liveness has to come from process state, file mtime, or git.

**The raw LLM log** (`--llm-history-file`) is the honest record: `io.log_llm_history()`
(`io.py:755`) writes `TO LLM 2026-09-19T20:29:33` / `LLM RESPONSE <iso>` headers followed by
role-prefixed lines (`SYSTEM ...`, `USER ...`). This one **does** carry second-resolution
timestamps per exchange and contains the full system prompt. It is the best liveness signal Aider
offers, and it is off by default.

**Aider also litters the repo.** A first run in a fresh repo created `.aider.input.history`,
`.aider.tags.cache.v4/`, and — because `--yes` auto-answered "Add .aider* to .gitignore
(recommended)?" — **edited `.gitignore`** (VERIFIED, both the file and the transcript line). Suppress
with `--no-gitignore`.

---

## D. CONTEXT — *the owner's non-negotiable*

**Reading context fullness: yes, indirectly and only at process start. Triggering compaction from
outside with proof: no. There is no compaction, and no hook.**

### Reading fullness

`/tokens` is the only context meter, and it can be reached non-interactively via `--load` + `--exit`.
Verified output from this machine:

```
$ printf '/tokens\n' > cmds.txt
$ aider --model gpt-4o --load cmds.txt --exit hello.py [...]

Executing: /tokens
Approximate context window usage for gpt-4o, in tokens:

$ 0.0050    2,015 system messages
$ 0.0001       20 hello.py        /drop to remove
==================
$ 0.0051    2,035 tokens total
          125,965 tokens remaining in context window
          128,000 tokens max context window size
```

That is parseable and it is genuinely useful — `tokens total`, `tokens remaining in context window`,
`tokens max context window size`. Three caveats, all VERIFIED in `commands.py:cmd_tokens`:

1. It is an **estimate of the next request**, assembled on demand from system prompt + repo map +
   in-chat files + `done_messages`/`cur_messages`. It is not a reading of a live session's state.
2. The `remaining` line only prints if the model's `max_input_tokens` is known
   (`if not limit: return`). For a model absent from the litellm price DB the meter silently
   truncates.
3. In a `--load`/`--exit` invocation it measures *that* process. To measure a running session you
   would have to type `/tokens` into its terminal — which the supervisor cannot do (§G).

### Compaction

**Aider has no compaction and no `/compact`.** What it has is *chat-history summarization*, and the
distinction matters:

- `ChatSummary` (`history.py`) summarizes `done_messages` when they exceed
  `--max-chat-history-tokens` (default: the model's `max_chat_history_tokens`).
- The trigger is internal and automatic: `move_back_cur_messages()` → `summarize_start()`, which
  returns immediately unless `self.summarizer.too_big(self.done_messages)`
  (VERIFIED, `base_coder.py:1002-1038`). It runs on a background thread.
- It summarizes **only the conversation**. Files in the chat, the repo map and the system prompt —
  which in the measurement above were 2,015 of 2,035 tokens — are untouched. Context pressure from
  files is relieved only by `/drop`.
- **It leaves no proof.** Nothing is written to the transcript, no event is emitted to the analytics
  log, no marker lands in the chat file. A supervisor cannot tell from outside that summarization
  happened, or that it succeeded. If every model in the list fails, `summarize_all` raises
  `ValueError("summarizer unexpectedly failed for all models")` from a background thread.

There is **no hook of any kind in Aider** — no PreCompact, no PostCompact, no PreToolUse, nothing.
`grep -icE "hook|sandbox|subagent|skill|plugin|permission|allowlist|denylist"` over `args.py` returns
**1**, and that one hit is `--git-commit-verify` (git's own pre-commit hooks). VERIFIED.

**Closest workaround, and its cost.** The orchestrator manages context by *not letting it
accumulate*: one `--message` per unit of work, `--map-tokens 0` to kill the repo map, an explicit
minimal `--file`/`--read` set per call, and `--restore-chat-history` only when continuity is worth
the lossy re-hydration. That works — but it means the orchestrator, not Aider, owns context
management entirely, and it forfeits any intra-task memory.

---

## E. QUOTA — *the owner's non-negotiable*

**Remaining capacity cannot be read. Spend can be read, precisely, after the fact.**

### There is no quota surface

Aider has no subscription, no account and no plan of its own. It is a BYO-key client that speaks to
~all providers through litellm. There is no rolling-hours window, no weekly window, no credit
balance, no `resets_at` — because the product has no relationship with a provider to have a quota
*in*. Whatever quota exists belongs to the key the orchestrator hands it, and must be read from that
provider's own API, out of band.

The single exception is a curiosity rather than a capability: `onboarding.py:18` defines
`check_openrouter_tier(api_key)`, which `GET`s
`https://openrouter.ai/api/v1/auth/key` with a 5-second timeout and reads
`data.data.is_free_tier` (VERIFIED). Aider uses it only to pick a default model, never surfaces it,
and defaults to `True` on any error. If the orchestrator routes Aider through OpenRouter, that same
endpoint is the quota read — but the orchestrator calls it itself; Aider is not involved.

### Spend *is* readable, and this is Aider's one genuinely good orchestrator surface

`--analytics-log FILE` writes newline-delimited JSON:
`{"event", "properties", "user_id", "time"}` (VERIFIED, `analytics.py:Analytics.event`). It works
even with telemetry off: `disable()` clears the PostHog/Mixpanel clients but never clears
`self.logfile`, and `event()` only short-circuits when all three are absent. The run below used
`--no-analytics` and still logged.

Verified events from a complete success-path run:

```
1789824595 launched              {}
1789824595 repo                  {"num_files": 1}
1789824595 auto_commits          {"enabled": true}
1789824596 message_send_starting {}
1789824598 message_send          {"main_model":"gpt-4o","weak_model":"gpt-4o-mini",
                                  "editor_model":"gpt-4o","edit_format":"diff",
                                  "prompt_tokens":1234,"completion_tokens":56,
                                  "total_tokens":1290,"cost":0.0036450000000000002,
                                  "total_cost":0.0036450000000000002}
1789824598 exit                  {"reason": "Completed --message"}
```

That is a per-message spend meter with model attribution, in JSONL, tailable live. For an
orchestrator running a cheap executor against a metered key, this is the right primitive — it just
measures **outflow, not headroom**.

Three caveats, all verified:
- `message_send` is emitted by `show_usage_report()` **only after a successful completion**. The
  failed run in §J produced `launched / repo / auto_commits / message_send_starting / exit` and **no
  `message_send`**. A crashed or rate-limited turn is invisible to the spend meter.
- Cost is computed by `litellm.completion_cost()`, falling back to
  `compute_costs_from_tokens()` using the model's entry in the litellm price DB. If the model is
  unknown, `calculate_and_show_tokens_and_cost` returns after the token report and **cost is
  silently absent** (VERIFIED, `base_coder.py:2033-2035`). The price DB is fetched from
  `raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` and cached
  24h at `~/.aider/caches/model_prices_and_context_window.json`, so an offline overnight run drifts
  to a stale table and, on a cold cache with no network, to no costs at all.
- `--cache-prompts` with `--stream` is explicitly unreliable: aider prints *"Cost estimates may be
  inaccurate when using streaming and caching"* and the docs say caching stats "are not available
  when streaming". Use `--no-stream` if the number has to be right.

### Limit-hit signalling

In-band, and badly. `exceptions.py` classifies `RateLimitError` and `RouterRateLimitError` as
`retry=True`. The retry loop starts at `retry_delay = 0.125`, doubles each attempt, and gives up
once `retry_delay > RETRY_TIMEOUT` (`models.py:26`, **`RETRY_TIMEOUT = 60`**) — so roughly nine
attempts over about two minutes, then it **breaks out of the loop and carries on to exit**
(VERIFIED, `base_coder.py:1449-1490`). No reset time is parsed, nothing is written to the analytics
log, and — see §J — the process exits **0**.

A provider-side hard limit is therefore indistinguishable, to the orchestrator, from a task that
finished with nothing to do.

---

## F. ACCOUNTS — *the owner's non-negotiable*

**Best-in-field, and almost by accident: because Aider has no account, every account is per-process
environment. Switching a *new* session is trivial. Switching a *running* one is impossible.**

Four mechanisms, in the order they are applied (VERIFIED from `--help` and
`main.py:generate_search_path_list`):

| Mechanism | Form | Notes |
|---|---|---|
| Dedicated flags | `--openai-api-key`, `--anthropic-api-key` | Only these two providers have flags |
| Generic key flag | `--api-key PROVIDER=KEY` | *"sets `PROVIDER_API_KEY=<key>`"*; repeatable |
| Generic env setter | `--set-env ENV_VAR_NAME=value` | repeatable; the escape hatch for base URLs, org ids, anything |
| Files | `--config FILE` (`.aider.conf.yml`), `--env-file FILE` (`.env`) | one file each, fully self-contained |

**Config precedence, exactly.** `generate_search_path_list()` builds, in load order: `~/<name>`,
`<git-root>/<name>`, `./<name>`, then the `--config`/`--env-file` path. **Later files win.** This
applies identically to `.aider.conf.yml`, `.env`, `.aider.model.settings.yml` and
`.aider.model.metadata.json`. One extra: if `~/.aider/oauth-keys.env` exists it is **prepended** to
the `.env` list, i.e. loaded first and overridable by everything else (VERIFIED,
`main.py:load_dotenv_files`). Above all files sit `AIDER_*` environment variables
(`auto_env_var_prefix="AIDER_"`, `args.py:40`) and then the command line.

**The recipe for an orchestrator.** One directory per role, each holding an `.aider.conf.yml` and a
`.env`; launch with `--config <role>/.aider.conf.yml --env-file <role>/.env`. Nothing is shared,
nothing is global, nothing has to be "switched" — there is no login state to switch. Several
accounts, several providers, several models can run concurrently on one machine with no interference
whatsoever. **Aider is the only platform in this scan where axis F costs the orchestrator nothing.**

Two things to guard:
- `.env` in the **git root** and in the **cwd** are loaded automatically. A repo that happens to
  contain a `.env` will silently override the role config unless the orchestrator passes
  `--env-file` last (it wins) and controls what is in the tree.
- `--api-key` and `--set-env` land in the **process environment**, visible in `ps` and inherited by
  every shell command the model runs (§H). Prefer `--env-file`.

**Changing a running session's account: impossible.** There is no `/provider` or `/api-key`
command. `/model` switches the *model* within the already-loaded environment. Changing credentials
means a new process — which, given §B, means losing the session anyway.

---

## G. INTERVENTION — *the owner's non-negotiable*

**There is no protocol. There is exactly one out-of-band injection channel, it works, and it is
strange: `--watch-files`.**

### What does not exist

No RPC mode, no JSON-RPC, no ACP, no socket, no daemon, no `/mid-turn-message`, no permission event.
The supervisor cannot send a message into a running session and cannot answer a question the session
asks. Aider's questions are `io.confirm_ask()` / `io.prompt_ask()` calls that block on
prompt-toolkit reading the terminal. The only answer channel is keystrokes on that terminal.

### What does exist, verified end to end

`--watch-files` (`AIDER_WATCH_FILES`, default False) makes a running aider watch the repo for
one-line comments ending in `AI!` (make changes) or `AI?` (answer a question). **I drove this on
this machine and it worked**: a session was started under a pty with no further input, an external
process then wrote

```python
def hello():
    pass
# add a docstring AI!
```

into a watched file, and the running aider picked it up, called the model, applied the edit and
committed it — all without anything being typed. Git afterwards:

```
f5ec3d9 Here is the change.     ← the edit
4b9c098 Here is the change.     ← "Committing hello.py before applying edits"
9d2c82c init
```

So axis G is **not zero for Aider**. It is the only platform-native way to reach a live session.

### What it costs

Five verified costs, and together they are why this is a workaround rather than an answer:

1. **No acknowledgement.** The instruction is a file write. Nothing confirms receipt, nothing
   correlates a request to a response. The supervisor learns it arrived by polling git, the chat
   markdown, or the LLM history file. "Know it arrived" — the owner's actual requirement — is met
   only by inference.
2. **It writes into the owner's repository.** Note commit `4b9c098` above: aider commits the dirty
   file *including the injected instruction comment* before applying edits. The control channel
   leaves artefacts in the project's git history. `--no-dirty-commits` suppresses the commit but not
   the file write.
3. **Removal of the comment depends on the model complying.** The prompt asks the model to delete
   the `AI!` comment; in my run (canned response) it did not, and the comment stayed in the file. A
   surviving comment is a re-trigger hazard.
4. **It silently expands context.** `process_changes()` adds *any* changed file containing an AI
   comment to the chat (`self.coder.abs_fnames.add(fname)`, `watch.py:195`) whether or not the
   supervisor wanted it there.
5. **The matcher is loose.** `ai_comment_pattern = re.compile(r"(?:#|//|--|;+) *(ai\b.*|ai\b.*|.*\bai[?!]?) *$", re.IGNORECASE)`
   — case-insensitive, matching any `#`/`//`/`--`/`;` comment whose tail is a word "ai". Ordinary
   source comments will trip it.

And the precondition from §A applies: `--watch-files` only runs in interactive mode, which needs a
live pty. Close stdin and the session is gone before the first instruction arrives.

### The honest alternative

Because a `--message` run is short-lived and stateless, the orchestrator's realistic intervention
model is not "talk to the session" but "kill it and launch the next one with different
instructions". For a cheap executor that is a legitimate design; it just is not axis G.

---

## H. GUARDRAILS

**No permission model. No sandbox. No allow/deny lists. No hooks.** Aider's only safety boundary is
git.

| Control | What it is | Tag |
|---|---|---|
| `--yes-always` | blanket yes to every confirmation | VERIFIED |
| `--suggest-shell-commands` / `--no-suggest-shell-commands` | whether the model may propose shell commands at all (default True) | VERIFIED |
| `--aiderignore FILE` | gitignore-syntax file limiting what may be edited (default `.aiderignore` at git root) | VERIFIED |
| `--subtree-only` | restrict to the cwd subtree of the repo | VERIFIED |
| `--dry-run` | apply nothing | VERIFIED |
| `--auto-commits` / `--dirty-commits` | every edit becomes a git commit (both default True) | VERIFIED |
| `--git-commit-verify` | run git pre-commit hooks (default **False** — aider commits with `--no-verify`) | VERIFIED |

**The one guardrail that survives `--yes-always`, and it is real.** `io.confirm_ask()` has an
`explicit_yes_required` parameter; when set, `self.yes is True` yields `"n"`, not `"y"`
(VERIFIED, `io.py`). It is used in exactly one place in the codebase: `handle_shell_commands()`
(`base_coder.py:2459`). So **`--yes-always` does not auto-approve running shell commands** — a
fully unattended aider will propose a shell command and decline it on the owner's behalf. That is
the right default and it is also a capability ceiling: an unattended aider cannot run your test
suite via a suggested command. Use `--test-cmd` + `--auto-test` and `--lint-cmd` + `--auto-lint`
instead, which are orchestrator-specified and run without asking.

**Three things `--yes-always` *will* do unattended, all verified on this machine:**

1. **Edit `.gitignore`.** Transcript line: `> Add .aider* to .gitignore (recommended)? (Y)es/(N)o [Yes]: y`
   → `> Added .aider* to .gitignore`. Suppress with `--no-gitignore`.
2. **Open browser tabs.** `io.offer_url()` calls `webbrowser.open(url)` when `confirm_ask` returns
   True, and `--yes-always` makes it always return True. In my first run — a plain auth failure —
   aider auto-answered *"Would you like to see what's new in this version?"* and *"Open URL for more
   info?"* and opened two tabs on this Mac. Any provider error whose message contains a URL will do
   this, because `check_and_open_urls()` regex-scans the exception text and offers **every** URL it
   finds (`base_coder.py`). Suppress with `--no-show-release-notes` and by exporting a
   no-op `BROWSER`; there is no flag that disables `offer_url` itself.
3. **Start an OAuth flow.** If no `--model` is given and no provider key is found in the
   environment, `select_default_model()` calls `offer_openrouter_oauth()`, which on a "yes" binds a
   local HTTP server on ports **8484–8584**, opens `https://openrouter.ai/auth` in a browser, waits
   for a callback, and writes the key to `~/.aider/oauth-keys.env` (VERIFIED, `onboarding.py`).
   Always pass `--model` explicitly.

**Also unattended by default:** telemetry. `--analytics` defaults to `None`, meaning "ask 10% of
users" (`analytics.py: PERCENT = 10`), and on a yes it ships to PostHog at `us.i.posthog.com`. Pass
`--analytics-disable` (or `--no-analytics`) on every launch; note `--analytics-log` keeps working
regardless (§E).

---

## I. EXTENSIBILITY

**Effectively none, for an orchestrator's purposes.**

- **MCP: not supported.** No `--mcp` flag, nothing in the docs, nothing in the source. PR `#5694`
  ("Native MCP client support") was **closed unmerged on 2026-09-09**; issue `#3314` is open. Given
  zero commits since 2026-05-22, MCP is not arriving. (VERIFIED)
- **No subagents, no skills, no plugins, no hooks.** Nothing in the flag surface or the source.
- **Custom commands: no.** The `/`-commands are methods on `Commands`; there is no user-defined
  command mechanism.
- **Conventions files:** `--read CONVENTIONS.md` is the documented way to inject standing
  instructions, as an ordinary read-only file. There is no `AGENTS.md`/`CLAUDE.md` auto-discovery.
- **System prompt customization** is possible only by editing `aider/prompts.py` in an installed
  copy (the project's own FAQ says so and warns against it).
- **Model reach is the real extensibility story.** Through litellm, Aider will talk to essentially
  any provider, including Anthropic-compatible and OpenAI-compatible relays — exactly the pattern
  the field scan found in `~/.config/claude-mimo`. `--set-env OPENAI_API_BASE=...` plus
  `--model openai/<id>` reaches anything. In this pass that is precisely how the zero-cost
  end-to-end test was run (`OPENAI_API_BASE=http://127.0.0.1:8799/v1`). VERIFIED.

**Can a GSD-style, subagent-heavy workflow engine run inside Aider? No.** There is nowhere to put
it. Aider has no way to spawn a sub-session, no tool protocol to hang an engine off, no hook to
intercept, and a four-turn ceiling per invocation. The correct shape is the inverse: the workflow
engine lives in the orchestrator, and Aider is invoked as a leaf step that applies one well-specified
edit.

**Scripting APIs.** Two, both real:
- The CLI (`--message` / `--message-file` / `--load`), covered above.
- A **Python API**: `Coder.create(main_model=Model("..."), fnames=[...], io=InputOutput(yes=True))`
  then `coder.run("...")`, and `coder.run("/tokens")` for slash commands. This is genuinely more
  capable than the CLI — the object persists between `run()` calls, so an in-process driver gets the
  multi-turn session the CLI cannot give it, plus direct reads of `coder.total_cost`,
  `coder.total_tokens_sent`, `coder.aider_edited_files` and `coder.done_messages`. **But the
  project's own docs say: *"The python scripting API is not officially supported or documented, and
  could change in future releases without providing backwards compatibility."*** Against a project
  with zero commits in four months that warning cuts both ways — low churn risk, zero support.

**A verified bug the orchestrator must know about.** Slash commands that switch coder mode do not
work in `--message`/`--load` mode, *and they bill you anyway*:

```
Executing: /ask what is this
Here is the change. ...
Tokens: 1.2k sent, 56 received. Cost: $0.0036 message, $0.0036 session.
Command '/ask what is this' is only supported in interactive mode, skipping.
```

The message was sent, the model replied, the cost was charged, **and then** aider reported it had
skipped the command. Same for `/chat-mode ask`. `/tokens` and `/clear` work correctly. This is the
bug unmerged PR `#5638` addresses. Use `--chat-mode ask` / `--architect` at launch instead of
`/ask` via `--load`.

---

## J. OPERATIONAL REALITY

### Cost model

Free and Apache-2.0; you pay only the provider. Aider AI LLC is the company behind it. There is no
subscription, no seat, no metered platform fee — which is precisely why it is attractive as the
cheap executor in a fleet, and precisely why §E has no quota to read.

### Install footprint (VERIFIED on this machine, today)

| Fact | Value |
|---|---|
| Wheel | `aider-chat==0.86.2` |
| Declared Python | **`<3.13,>=3.10`** — the released wheel still caps at 3.12 even though PR `#4899` ("Add Python 3.13 and 3.14 support") merged 2026-03-09, after the last release |
| Interpreter used | CPython **3.12.8** |
| Installed size | **748 MB** |
| Packages pulled in | **227** |
| Wall-clock install | **~4 minutes** via `uv pip install` on a warm network, cold cache |

For comparison with the rest of the field: this is the heaviest install in the scan by a wide margin,
and it drags in litellm, tree-sitter grammars, PostHog and Mixpanel clients. Officially recommended
install is `uv tool install --force --python python3.12 --with pip aider-chat@latest` or the
`curl -LsSf https://aider.chat/install.sh | sh` one-liner. macOS is fully supported.

### Maturity

Apache-2.0, 49k stars, five years of history — and, per §0, **zero commits since 2026-06-01, 502
open PRs, 1,378 open issues, last PyPI release seven months old**. The code that exists is stable and
battle-tested; nothing new is coming. For an orchestrator that wants a frozen, predictable leaf
executor, hibernation is arguably a feature. For one that needs MCP, sessions or a control protocol,
it is terminal.

### Known unattended-run failure modes

Ordered by how much damage each does to an overnight queue. All VERIFIED on this machine unless
noted.

1. **Exit code 0 on total failure.** This is the headline. A `--message` run against a bad API key
   produced `litellm.AuthenticationError`, changed nothing, and exited **0**:

   ```
   litellm.AuthenticationError: AuthenticationError: OpenAIException - Incorrect API key provided...
   The API provider is not able to authenticate you. Check your API key.
   EXITCODE=0
   ```

   `main.py` returns a bare `return` after `--message` regardless of outcome; the only `return 1`
   paths near it are a missing or unreadable `--message-file`. **An orchestrator must never treat
   Aider's exit code as a success signal.** The only trustworthy completion evidence is a new git
   commit carrying `Co-authored-by: aider (<model>) <aider@aider.chat>` (VERIFIED — that trailer is
   on by default via `--attribute-co-authored-by`), or a `message_send` line in the analytics log,
   or `> Applied edit to <file>` in the transcript.
2. **A rate limit looks exactly like success.** Per §E: ~9 retries over ~2 minutes, then give up,
   print, exit 0, emit no `message_send`. No reset time, no in-band signal.
3. **Browser tabs open on the owner's desktop.** See §H.2 — observed twice in one failed run.
4. **An unmodelled model kills the cost meter silently.** No price-DB entry → no cost in the
   analytics event and no `remaining` line from `/tokens`. Same failure if the 24h litellm price
   cache is cold and the network is down.
5. **Interactive mode dies instantly without a pty.** §A. Any `--watch-files` supervision loop must
   allocate one.
6. **Edits land in git whether or not they are right.** `--auto-commits` and `--dirty-commits` are
   both on by default and `--git-commit-verify` is off, so aider commits with `--no-verify`,
   bypassing the project's pre-commit hooks. An overnight queue will produce a stack of commits no
   hook ever inspected. Mitigate with a worktree or branch per task and `--git-commit-verify`.
7. **Startup does network I/O.** Version check (suppress with `--no-check-update`), litellm price DB
   refresh, and potentially telemetry. Each is a place a flaky night can stall.
8. **Concurrency in one repo is unsafe.** Two aiders in the same worktree will race on `.gitignore`,
   `.aider.input.history`, the tags cache and — worse — on `git commit`. One git worktree per
   concurrent task. (Reasoned from the verified artefact list, not separately tested — CLAIMED.)

### Is it plausible to run Aider overnight unattended today?

**Yes — as a leaf executor, under a supervisor that ignores its exit code.** The recipe that works:
one process per task, explicit `--model` and `--file`/`--read`, `--yes --no-check-update
--no-stream --no-pretty --no-fancy-input --no-show-release-notes --no-gitignore --analytics-disable
--analytics-log <jsonl> --llm-history-file <log>`, a dedicated git worktree, a wall-clock timeout,
and success judged only by git + the analytics log.

**No — as a session you plan to supervise, steer and resume.** There is no session to resume, no
protocol to steer it with, and no quota to watch.

---

## What this costs the orchestrator

A per-axis ledger of what has to be built, bought or given up if Aider joins the fleet.

| Axis | Verdict | What the orchestrator must build, and what it forfeits |
|---|---|---|
| **A. Launch** | Partial | Headless is solid. **Build a stdout/markdown/git scraper** — there is no structured result channel at all. Forfeit: any machine-readable "what did it do". |
| **B. Identity & resume** | **Fails** | The orchestrator must own identity entirely: allocate its own task id, own the working directory and worktree, own the chat-history path. Resume is `--restore-chat-history` + a `/save`d file list, and it recovers a **paraphrase**. Forfeit: exact resume, crash recovery mid-turn, any notion of a session that outlives a process. |
| **C. Transcript** | Good | Free, live-tailable, parseable. **Always pass `--llm-history-file`** — it is the only timestamped record and the only real liveness signal. Cost: parsing prose; no per-message timestamps in the chat log. |
| **D. Context** | **Fails on trigger, partial on read** | Read via `--load '/tokens' --exit`, but only at process start. There is no compaction, no `/compact`, no hook, and summarization leaves **no proof**. The orchestrator must prevent context growth rather than manage it: `--map-tokens 0`, minimal file sets, one message per process. Forfeit: any long-running session's context management. |
| **E. Quota** | **Fails on headroom, excellent on spend** | Headroom must be read from the provider directly, out of band (for OpenRouter, `GET /api/v1/auth/key`). Spend comes free and precise from the `message_send` JSONL event. **Build a budget governor** on cumulative `total_cost`, and treat a missing `message_send` as a failed turn. Forfeit: knowing a limit is near before hitting it; knowing a reset time at all. |
| **F. Accounts** | **Excellent — costs nothing** | One directory per role with `.aider.conf.yml` + `.env`; launch with `--config` and `--env-file`. No login state, no keychain, no switching, unlimited concurrency across accounts and providers. The only work is guarding against a stray `.env` in the repo tree. |
| **G. Intervention** | **Fails as protocol; one real channel** | `--watch-files` + an `AI!` comment genuinely reaches a live session (verified). Costs: a pty, no acknowledgement, writes into the repo and its git history, silently widens the file set, and a loose regex. Answering a session's own question programmatically is **impossible**. Realistic posture: don't intervene — kill and relaunch. |
| **H. Guardrails** | Weak but predictable | No sandbox, no permissions, no hooks — so the boundary must be the OS and git: a worktree per task, `--aiderignore`, `--subtree-only`, `--git-commit-verify`, a wall-clock timeout. Note the one built-in: `--yes-always` **still refuses suggested shell commands**, so use `--test-cmd`/`--lint-cmd` for anything that must run. Suppress browser-opening and the OpenRouter OAuth flow explicitly. |
| **I. Extensibility** | **Fails** | No MCP, no hooks, no skills, no subagents, no custom commands. The workflow engine must live entirely outside. If an in-process multi-turn session is genuinely needed, the unsupported Python `Coder` API is the only door, and it is explicitly unsupported. |
| **J. Operational** | Usable, with eyes open | 748 MB and 227 packages per install; Python ≤3.12; **exit code 0 is meaningless**; rate limits are silent; startup touches the network. Budget for a scraper, a worktree manager, a timeout and a spend governor — and for a dependency that has not shipped a commit in four months. |

**The one-line verdict.** Aider is a good cheap *executor* and a bad *session*. It fits an
orchestrator that decomposes work into small, fully-specified edits and judges each by git — and it
cannot fit one that wants to start a long task, watch its context, top up its quota, steer it
mid-flight and resume it after a crash. Of the owner's five non-negotiables it meets one (accounts,
brilliantly), partially meets one (context reading), and fails three (quota headroom, resume,
answering a question programmatically).

---

## Sources

All accessed **2026-09-19** unless stated.

**Run on this machine (VERIFIED):**
- `aider-chat==0.86.2` installed into an isolated `uv` venv (Python 3.12.8) under a fake `HOME`;
  `aider --version` → `aider 0.86.2`; `aider --help` full flag surface.
- Headless failure run with a bogus `OPENAI_API_KEY` → `AuthenticationError`, **exit 0**, two browser
  tabs opened, `.gitignore` modified.
- Headless success run against a local fake OpenAI-compatible endpoint (`127.0.0.1:8799`) → edit
  applied, git commit with `Co-authored-by: aider (gpt-4o) <aider@aider.chat>`, `message_send`
  analytics event with `prompt_tokens` / `completion_tokens` / `cost` / `total_cost`.
- `--load` + `--exit` with `/tokens`, `/clear`, `/ask`, `/chat-mode` → context report captured; the
  `/ask`-bills-then-skips bug reproduced.
- Three-run `--restore-chat-history` A/B → "chat history" row appears only with the flag.
- `--watch-files` driven through `pty.openpty()` → external `AI!` comment triggered a real edit and
  two commits.

**Project source, `main` branch** (`raw.githubusercontent.com/Aider-AI/aider/main/aider/…`):
- `args.py` (945 lines) — full flag definitions, `auto_env_var_prefix="AIDER_"`, `--yes-always`
- `main.py` (1274) — `generate_search_path_list`, `load_dotenv_files`, `--load`/`--message` order,
  `analytics.event("exit", …)`, exit-code paths
- `base_coder.py` (2485) — `max_reflections = 3`, retry loop + `RETRY_TIMEOUT`,
  `calculate_and_show_tokens_and_cost`, `show_usage_report`, `summarize_start`/`summarize_end`,
  `handle_shell_commands` (`explicit_yes_required=True`), `check_and_open_urls`
- `io.py` (1191) — `append_chat_history`, `log_llm_history`, `confirm_ask`, `prompt_ask`, `offer_url`
- `analytics.py` (258) — JSONL log entry shape, `PERCENT = 10`, PostHog host
- `history.py` (143) — `ChatSummary`, `too_big`, `summarize_all`
- `commands.py` (1712) — `cmd_tokens`, `cmd_save`, `cmd_load`
- `exceptions.py` — `ExInfo` retry classification, `RateLimitError`, insufficient-credits case
- `models.py` (1338) — `RETRY_TIMEOUT = 60`, `ModelInfoManager` (litellm price DB URL, 24h cache)
- `onboarding.py` — `check_openrouter_tier`, `offer_openrouter_oauth`, ports 8484–8584,
  `~/.aider/oauth-keys.env`
- `watch.py` — `ai_comment_pattern`, `process_changes`, auto-add of changed files
- `utils.py` — `split_chat_history_markdown` (drops `> ` tool lines)

**Project docs source** (`aider/website/docs/…` on `main`):
- `scripting.md` — `--message`, the Python `Coder` API, and its unsupported-API warning
- `config/options.md` (863) — generated from `args.py`; matched the local `--help` exactly
- `config/aider_conf.md`, `config/dotenv.md`, `config/api-keys.md` — precedence and key placement
- `usage/commands.md` — the full slash-command table
- `usage/watch.md` — `AI!` / `AI?` semantics
- `usage/caching.md` — caching stats unavailable while streaming
- `troubleshooting/token-limits.md` — *"Aider never enforces token limits… token counts are estimates"*
- `more/infinite-output.md`, `faq.md`, `install.md`

**Registry / API metadata:**
- PyPI JSON `pypi.org/pypi/aider-chat/json` — 0.86.2 @ 2026-02-12, `requires_python <3.13,>=3.10`,
  full release history
- GitHub API `repos/Aider-AI/aider` — 49,053 stars, Apache-2.0, `pushed_at` 2026-05-22, not archived
- GitHub API commits (`?since=2026-06-01`) → **0**; `pulls` and `search/issues` → 502 open PRs,
  1,378 open issues; PR `#5694` `merged:false, closed_at 2026-09-09`; PRs `#4343`, `#5638` open

**Not established (UNKNOWN):**
- Whether concurrent aiders in one worktree corrupt each other's state — reasoned from the artefact
  list, not separately tested.
- Whether the unsupported Python `Coder` API is stable enough to build an orchestrator adapter on;
  no contract, no tests exposed as public API, no versioning promise.
- Whether any fork of Aider has picked up MCP/session support and is maintained — not surveyed in
  this pass; worth one check before writing Aider off entirely.
