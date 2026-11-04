# C4-capacity — Quota, limits, providers and accounts per role

**Cluster:** C4-capacity · **Items:** R1-06, R1-07, owner instruction I1
**Date of research:** 2026-09-19 · **Machine:** owner's Mac (darwin 25.5.0)
**Sources:** the round-1 transcript, the four extraction readers, `plugins/harness/docs/FIELD-NOTES.md`,
live probes on this machine, vendor docs, and the source of third-party quota tools.

**Evidence tags.** **VERIFIED** — I read it in source/docs/code, or ran it on this machine and saw
the output. **CLAIMED** — a README, vendor page or blog asserts it; I did not confirm it.
**INFERRED** — my reasoning from verified facts, labelled as mine.

**A referenced input was missing.** The task pointed at prior research in
`/private/tmp/claude-501/.../scratchpad/context/` (`harness-evidence.md`, `orchestrator-landscape.md`,
`snf-architecture.md`). That directory exists and is **empty** (VERIFIED). The field scan at
`research/platforms/00-field-scan.md` records the same gap. Nothing in this document leans on those
files; where I would have reused them I re-derived from primary sources instead.

---

## 1. What the owner decided

Quoted verbatim, with `[row]` anchors into `round-1/TRANSCRIPT-01.md`.

### 1.1 The limit rule itself (R1-06)

> «зараз актуальні ліміти підписки Клоду … є п'ятигодинне вікно і є тижневе вікно, і зважаючи на це,
> потрібно робити дії. Якщо, наприклад, п'ятигодинне вікно забилося, то потрібно чекати, коли воно
> розіб'ється … щоби продовжити всю роботу» — [007]

> «тут не має бути конкретної прив'язки до Клода, Треба, мати можливість адоптовуватись до нових
> прав … можливо це буде взагалі pay-as-you-go» — [007]

> «в кожної платформи можуть бути свої обмеження, це просто про Клод Код» — [171]

The 5h/weekly scheme is an **illustration**, not a spec. The 60%/5% numbers at [171] and the 80%
threshold below are his own worked examples, not settings.

### 1.2 The three stop modes

> «людина може лише налаштовувати хард ліміти, хардстопи, коли якийсь ліміт, наприклад, там , 80%
> тижневого … то це означає хардстоп, що потрібно зупинити завдання прямо вже та й все» — [171]

> «Якщо це софт стоп, наприклад, 80 відсотків, то агент може ще почекати, поки виконує це завдання,
> після цього більше не зупиняти» — [171]

> «Не знаю, щось проміжне між софт і хардстопом, це про те, аби записати теперішній стан, можливо
> зберегти сесію, і зупинити її повністю, аби потім можна було її продовжити» — [171]

The third mode is explicitly **open** («Не знаю»). Section 5.6 below reports what actually gates it,
which is not what anyone assumed.

### 1.3 Running into the wall is acceptable — because state is recorded

> «якщо виглядає так, що завдання впирається в те, що впереться в ліміти, то це окей, оскільки в нас
> в реєстрі має записуватись кожен стан, його виконання … для того, щоби було відновити процес і
> продовжити, навіть руками, або просто продовжити після того, як ліміти онуляться» — [171]

> «оркестратор має вести ось такий от облік, який або буде посилатися на облік тієї тулзи, яка
> використовується … Або ж, якщо такого немає, то він веде свій облік. Якщо … його недостатньо, то
> ведеться з посиланням, плюс тої дати, якої не вистачає» — [171]

A three-way accounting rule: **reference / own / reference-plus-delta.** This maps almost exactly
onto the degradation ladder the platforms force on us (§5.2), which is a good sign for the design.

### 1.4 Do not over-engineer

> «Тому тут нічого надприроднього не потрібно вигадувати» — [171]

He says this at least four times in the session ([171], [189], [300], [370]). `extract/by-item.md`
records that ANALYSIS-01 carries no cross-cutting simplicity requirement at all. It is a constraint
on this cluster's output, and §5 is written against it.

### 1.5 Providers, accounts and roles (R1-07)

> «провайдерів може бути декілька … має бути побудована система» — [036]

> «На початку, я думаю, буде достатньо, щоб мануально вказувати що яким провайдером буде
> виконуватись … на кого буде працювати оркестратор, на кого буде працювати скажімо, контекст
> фочер, на кому екзек'ютор буде» — [036]

This is also where he names his **role taxonomy: orchestrator / context watcher / executor**,
repeated at [204] as three concrete terminal windows. `extract/by-item.md` flags that ANALYSIS-01
never records the three-role model as a finding.

> «під провайдерами вино увазі, що може бути як кодекс, так чат джіпіті, так і кімій, або джі ел ем,
> або джемінай … з кожної з цих платформ може бути різна кількість аккаунтів» — [041]

> «це має бути налаштовано через єдиний файл, який оркестратор чи контекст вочер постійно дивиться і
> перевіряє, чи там були якісь зміни» — [195]/[196]

> «якщо в моменті щось змінюється, то вказується, який тип цієї зміни. Тобто, чи це софт, що це треба
> буде наступні завдання перенести, чи це хард, чи це треба прямо вже зробити і зупинити» — [195]/[196]

> «при конфігурації треба буде … явно пояснити, як саме може відбуватися зміна акаунтів. І для кожної
> платформи це окремо треба пояснювати» — [199]

> «це може бути як зміна через те, щоб використовувати інший API ключ, або зміна те, що треба
> використовувати інший акаунт підписки … Наприклад, в моєму випадку це перемикач профілів, який використовує різні
> профілі» — [199]

The referent is **a profile switcher** — a tool that keeps one config dir per profile
(`~/.<switcher>/profiles/…`) (VERIFIED, §3.1). ANALYSIS-01 left the word unresolved.

> «перед запуском потрібно переконатися, що це працює, щоби це не було проблемою для користувача» — [199]

> «коли людина налаштовує провайдери, які використовують та акаунти, вона може вказувати, для чого
> вони можуть використовуватись. Наприклад, що може використовувати тільки для оркестратора, щось
> може використовуватись тільки для екзек'ютора … І це важливий дуже нюанс» — [270]

### 1.6 Instruction I1 — check feasibility, raise each divergence as its own question

> «ти коли будеш це аналізувати, я про це не говорю, і я ну все вірю, але воно може не сходитися з
> дійсністю … колектор, який це буде отримувати, повинен аналізувати. Якщо, наприклад, при різних
> платформах це буде неможливо, то про це треба говорити і обдумувати, як можна це зехендлити» — [182]/[183]

> «це має бути оркестратор для всього, і якщо раптом десь немає лімітів, або десь інші ліміти … це
> треба буде винести окремими питаннями потім» — [182]/[183]

This document is the reply to that instruction. §4 and §6 are the divergences.

### 1.7 Ratification status — read before building on any of this

`extract/corrections.md` records that **the entire hard/soft stop rule for R1-06 is unratified**: the
interviewer put the restatement at [176]/[177], the owner said «Повтори, будь ласка» [178], the
restatement was repeated, and the interviewer moved to the next topic without an answer. The same is
true of the per-platform account-switch explanation and pre-run verification at [200]/[201] → [202].

The substance is carried by the owner's own words at [171] and [199], quoted above. What is missing
is the **label**. This vocabulary — soft / hard / intermediate — is then reused across R1-07, R1-08
and Д12, so it is load-bearing for the whole design. Round 2 should re-ratify it rather than inherit
it as settled.

### 1.8 A sub-question that was never asked

`extract/corrections.md` records that `questions.md` R1-06 contained a second half that the
interviewer never put to him:

> «**Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу?**»

There is **no answer anywhere in the transcript** about reserving headroom for the owner's own
interactive work. This is exactly the failure mode that makes an unattended run eat the subscription
he needs the next morning — and it is the one question in this cluster with no data at all. It is
first in §6.

---

## 2. How the world does it

Across thirteen platforms there are only **four** ways a coding agent lets you learn how much
capacity is left. Everything in §3 is one of these.

**A. An out-of-band metadata endpoint.** A separate HTTP call that returns quota without spending
any. Anthropic's OAuth usage endpoint, Z.ai's monitor endpoint, DeepSeek's balance endpoint.
Predictive — you can ask before you spend. Its weakness is that it is a *second* system that can be
throttled, expire, or drift independently of the agent (§3.1 shows all three happening).

**B. In-band telemetry on the session stream.** The agent reports quota alongside its own work,
every turn, for free. **Codex is the only platform found that does this** (§3.2) — and it is by some
distance the best surface in the field, because it cannot go stale, cannot be throttled, needs no
second credential, and is attributed to the right account by construction.

**C. Own accounting only.** The tool totals what *it* spent (`opencode stats`, `ccusage`,
per-message `usage` blocks in Claude Code transcripts). This tells you consumption, never remaining
capacity, because it cannot see what the same account spent elsewhere.

**D. Nothing.** You discover the limit by hitting it.

**Window encoding is where the platforms differ most, and it decides whether the owner's
"adapt to whatever a provider has" is achievable.** Three schemes, all VERIFIED:

| Platform | How a window is described | Generality |
|---|---|---|
| Codex | `window_minutes` — an integer (observed 300, 299, 10080) | Fully general: any window length is just a number |
| Z.ai | `unit` + `number` (unit 3/number 5 → 5h; unit 6/number 1 → weekly) | General: a unit code plus a count |
| Anthropic | Named object keys — `five_hour`, `seven_day`, `seven_day_opus`, … | **Not general**: a new window shape is a new key |

Reset timestamps come in three formats — ISO-8601 (Anthropic), Unix epoch seconds (Codex), epoch
milliseconds (Z.ai) — so normalising to UTC is a contract obligation, not an implementation detail.

**INFERRED, and it is the good news for the owner's [007] requirement:** two of the three schemes
already describe windows *as data*. An adapter that reads `window_minutes` needs no change when a
provider moves from a 5-hour to a 10-hour window. Anthropic's is the one that does not — and §3.1
shows its key set is both unstable and undocumented, which makes the general contract in §5 a
necessity rather than an elegance.

---

## 3. What is feasible, per platform

### 3.1 Claude Code — VERIFIED in depth on this machine

`claude 2.1.278` (VERIFIED, matches current npm latest per the field scan).

**Quota endpoint.** `GET https://api.anthropic.com/api/oauth/usage`, headers
`Authorization: Bearer <oauth access token>` and `anthropic-beta: oauth-2025-04-20`. It is
**undocumented and unversioned** — it appears in the owner's own `~/.config/claude-profiles/profiles.sh`
and in his global CLAUDE.md, not in any Anthropic doc I could find. Live response today (VERIFIED,
values are real):

```
five_hour.utilization = 10.0
five_hour.resets_at   = 2026-09-19T17:50:00.798235+00:00
five_hour.limit_dollars / used_dollars / remaining_dollars / locked_reason = null
seven_day.utilization = 32.0
seven_day.resets_at   = 2026-09-20T11:59:59.798261+00:00
seven_day_oauth_apps, seven_day_opus, seven_day_sonnet, seven_day_cowork, seven_day_omelette = null
tangelo, iguana_necktie, omelette_promotional, cinder_cove, copper_kite, harbor_lantern,
wattle_ember, amber_ladder, juniper_tide, cedar_ember, amber_gauge = null
nimbus_quill.utilization = 0.0   (present, non-null, alongside the two real windows)
extra_usage.{is_enabled:false, monthly_limit, used_credits, utilization, currency, decimal_places}
```

Four things follow, and three of them are traps.

**(a) The bucket set is not stable and must not be hardcoded.** Twenty-plus named buckets, most null,
several under obvious internal codenames (`tangelo`, `iguana_necktie`, `nimbus_quill`). An adapter
that reads `five_hour` and `seven_day` will silently miss whichever bucket actually blocks the run
when Anthropic ships a new one. **INFERRED:** the correct read is *enumerate every non-null bucket
that has a `utilization`*, treat each as a window, and stop on the worst.

**(b) The schema has already drifted once, and the previous harness broke silently.**
`plugins/harness/bin/harness-limits.sh:69-70` parses:

```
jq -r '[.limits[] | select(.group=="session")] | sort_by(.percent) | reverse | .[0].resets_at // empty'
```

There is **no `.limits` array in the current response** (VERIFIED — top-level keys today are
`five_hour`, `seven_day`, the named buckets and `extra_usage`; `'limits' in d` is `False`). That
parser now yields empty for every read. `FIELD-NOTES.md` records the consequence:
`weekly_all=unreadable%` recurring across many separate days — "six consecutive ticks on
`2026-09-06T03:01-03:19Z`, more at 08:36 and 22:48-23:03, single ticks on the 9th, 10th and 11th".
**INFERRED:** an undocumented endpoint whose shape changed under a running system, degrading to a
state the system treats as benign, is the single largest reliability risk in this cluster.

**(c) The endpoint throttles brutally, and the throttle is indistinguishable from nothing.**
Measured today (VERIFIED, reproducible):

- 8 rapid calls on one token: calls 1–2 succeeded, **calls 3–8 returned
  `{"error":{"type":"rate_limit_error"}}`**.
- Cooldown probe, one call every 15s for 180s: **still limited at t+167s**. It did not recover
  inside the probe window.

So the quota-reading channel is itself a scarce resource with roughly a **two-call budget and a
multi-minute recovery**. Whether the throttle is per-token or per-IP I could **not** establish
(UNKNOWN) — the obvious cross-check was spoiled because the other profile I tried returned
`authentication_error` for an unrelated reason, see (d). This matters: if it is per-IP, polling several
accounts shares one budget and rotation buys nothing.

**(d) An idle account cannot be polled at all.** Testing an idle profile
(`Claude Code-credentials-<hash>`) returned **`authentication_error`**, not quota — its stored
OAuth token is stale. Tokens refresh when Claude Code runs under that profile; a profile nobody has
used lately has nothing usable. `FIELD-NOTES.md` records the same thing happening unattended: "The
usage endpoint returned `authentication_error` for an extended stretch, blinding every cap read,
with nobody re-authenticating. `2026-09-02T13:52-15:14Z`." **INFERRED, and it directly contradicts a
natural reading of [199]:** you cannot pre-flight the quota of an account you are not currently
running on. "Verify before the run" can verify *switching*; it cannot verify *headroom*.

**In-band signal.** None worth having. Claude Code transcripts carry a per-message `usage` block
(`input_tokens`, `cache_read_input_tokens`, `output_tokens`, …) — that is category C, consumption,
not remaining. The only limit-hit signal is a **banner drawn in the TUI**, which the previous
generation detected by scraping the captured screen. `FIELD-NOTES.md` records what that cost:

- "An 85-minute loop that nothing internal could break. The deterministic watch matched what looked
  like a usage-cap banner inside the orchestrator's **own wrapped prose**, pressed Escape and sent
  `continue` about every sixty seconds … **Nothing internal detected it** — it ended when an external
  `SIGTERM` reached the orchestrator."
- "A **45-minute false-positive rate-limit-banner loop** on a healthy orchestrator in the previous
  run, re-detecting and re-issuing resume kicks about every 66 seconds."

Two independent multi-hour false-positive loops from one technique. **Screen-scraping for a limit
banner should be struck from the rebuild.**

**A separate account, if the user configures one.** Switching is an existing mechanism the rebuild
should consume, not reinvent: `CLAUDE_CONFIG_DIR`, routed per working directory by a profile switcher.
Credentials are per-config-dir in the macOS Keychain under a derived service name —
`Claude Code-credentials` for the canonical store, otherwise
`Claude Code-credentials-<first 8 hex of sha256 of the config dir>`. **I verified the derivation**
against the keychain (VERIFIED); entries for deleted profiles linger as orphans.

Two constraints (both VERIFIED in `profiles.sh`): `~/.claude.json` and `~/.claude/.claude.json` are
different files, and the former is what Claude Code reads when `CLAUDE_CONFIG_DIR` is unset — a
daemon-spawned session hits the wrong one unless the env var is set. And macOS may prompt once per
account for Keychain access, so an unattended run on a never-granted account **blocks on a GUI
dialog**. One further caveat found on this machine: a profile can be listed in the keychain while
`security find-generic-password` returns no token for it (VERIFIED) — a listed account is not
necessarily a usable one.

**Headless auth.** `claude --print` with `ANTHROPIC_API_KEY` or `apiKeyHelper` via `--settings`.
Claude Code's own help states that in that mode "Anthropic auth is strictly `ANTHROPIC_API_KEY` or
`apiKeyHelper` … (**OAuth and keychain are never read**)" (VERIFIED). **INFERRED, and this is a
sharp edge:** the headless path and the quota-readable path are mutually exclusive. An API-key
session has no OAuth token, so it has no usage endpoint — you get category D. Also
`claude setup-token` creates a long-lived subscription token.

**Two capabilities the previous generation did not use.** `--max-budget-usd <amount>` is a native
per-session spend cap in `--print` mode (VERIFIED in `--help`) — a real hard stop enforced by the
tool rather than by a supervisor's polling. And `claude --bg` plus `agents`/`attach`/`logs`/`stop`/
`rm`/`respawn` is a first-party background-session control plane (VERIFIED).

**A trap created by the owner's own setup.** `~/.config/claude-mimo/env` points Claude Code at
`ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com/anthropic` (VERIFIED in the field scan,
§2). **INFERRED:** when the base URL is overridden, "Claude Code" is no longer on Anthropic's
quota — `api.anthropic.com/api/oauth/usage` would report the wrong account's numbers entirely. The
adapter key must be *(binary, base URL, credential)*, not the binary alone.

### 3.2 OpenAI Codex CLI — VERIFIED locally, and the best surface in the field

`codex-cli 0.152.0` on this machine (npm latest is 0.155.1 — three releases behind, per the field scan).

**Quota is in-band, on disk, free.** Every `token_count` event in the session rollout JSONL carries a
`rate_limits` object. A real record from
`~/.codex/sessions/2026/09/14/rollout-2026-09-14T02-08-44-*.jsonl` (VERIFIED):

```json
{"timestamp":"2026-09-13T19:08:53.449Z","ordinal":18,"type":"event_msg",
 "payload":{"type":"token_count",
   "info":{"total_token_usage":{...},"last_token_usage":{...},"model_context_window":258400},
   "rate_limits":{"limit_id":"codex","limit_name":null,
     "primary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1789809907},
     "secondary":null,
     "credits":{"has_credits":false,"unlimited":false,"balance":"0"},
     "individual_limit":null,"spend_control_reached":null,
     "plan_type":"prolite","rate_limit_reached_type":null}}}
```

Sampling across the session history shows both window sizes in the wild:
`window_minutes` of **300** (5h), **299**, and **10080** (7d) (VERIFIED). The window length is
reported as a number, so the owner's [007] requirement — adapt if it becomes a ten-hour window, or
no window — is satisfied *by the data format itself* with no adapter change.

It carries, in one object: percentage used, window length, reset time (Unix epoch),
a credits block covering the pay-as-you-go case (`has_credits`, `unlimited`, `balance`), the plan
type, an explicit spend-control flag, and **`rate_limit_reached_type`** — a genuine in-band
limit-hit signal that needs no screen scraping. And the same event carries
`model_context_window` plus cumulative token usage, which means **Codex solves context-fullness
measurement for free** — the thing `FIELD-NOTES.md` records that nothing in the previous plugin
measured ("`bin/*.sh` contains no reference to context, percentages, or compaction").

**Multiple accounts.** `CODEX_HOME` (VERIFIED by probe: setting it to a nonexistent path produced
`Error loading configuration: CODEX_HOME points to "/tmp/codex-probe-test", but that path does not
exist` — the variable is read). Each home holds one `auth.json` with
`auth_mode` (`chatgpt` here), `tokens.{id_token,access_token,refresh_token,account_id}` and
`last_refresh` (VERIFIED, no secrets read out). So Codex account switching is structurally identical
to Claude Code's `CLAUDE_CONFIG_DIR` — one env var per role. That is a pleasant symmetry for §5.

**Headless auth.** `codex login --with-api-key` and `codex login --with-access-token`, both reading
from stdin (VERIFIED in `--help`) — genuinely scriptable, unlike an OAuth browser flow.
`codex login status` prints "Logged in using ChatGPT" (VERIFIED) — a cheap switch-verification probe
that answers [199]'s "переконатися, що це працює".

**Control plane.** `codex exec` (non-interactive), `resume`, `fork`, **`queue`** ("Queue a message
for an existing session"), `app-server`, `remote-control`, `agents` ("Browse all agent sessions on
the shared local app-server daemon") — plus `~/.codex/` holding `app-server-daemon/`, `ipc/`,
`cross-instance-locks/` and `process_manager/` (VERIFIED). Belongs to another cluster, but it is
worth recording here that the platform with the best quota surface also has the best supervision
surface.

### 3.3 Z.ai GLM coding plan — VERIFIED from the source of a working tool

Read directly from `glm-quota.py` (`github.com/zeljkoavramovic/glm-quota`, fetched via `gh api`):

- Endpoints: `https://api.z.ai/api/monitor/usage/quota/limit` (global),
  `https://open.bigmodel.cn/api/monitor/usage/quota/limit` (China), plus
  `/api/monitor/usage/model-usage` and `/api/monitor/usage/tool-usage` for breakdowns.
- Auth: `headers={"Authorization": token}` — **the raw key, no `Bearer` prefix** (line 105).
- Response rows carry `type` (`TOKENS_LIMIT` / `CREDIT_LIMIT`), `unit`, `number`, `total`,
  `percentage`, `nextResetTime` (epoch ms).
- Window decoding, quoted from the source: *"TOKENS_LIMIT row: unit 3/number 5 → 5h window,
  unit 6/number 1 → weekly."* The code falls through to a generic
  `f"Token usage(unit={unit}, number={number})"` for any other pair — i.e. the encoding is open-ended.

**A live breakage worth copying the lesson from.** Three independent bug reports (CLAIMED, but
mutually corroborating across unrelated projects) say Z.ai began returning `CREDIT_LIMIT` rows where
tools expected `TOKENS_LIMIT`, and the tools rendered **all quotas as zero** rather than as
unreadable. That is the same failure class as §3.1(b): an unannounced schema change degrading into a
number the consumer treats as valid. A quota of 0% used looks like plenty of headroom.

**Accounts:** API-key based, so multiple accounts are just multiple env values (INFERRED from the
auth model; trivial). **Headless:** an API key, so yes.

### 3.4 DeepSeek — VERIFIED from official docs

`GET https://api.deepseek.com/user/balance`, Bearer auth. Response:
`is_available` (boolean) plus `balance_infos[]` of `{currency (CNY|USD), total_balance,
granted_balance, topped_up_balance}`. **No window, no percentage, no reset timestamp** — the docs
return none, and there is nothing to return: it is pure pay-as-you-go.

This is the owner's «можливо це буде взагалі pay-as-you-go» [007] case in its purest form, and it is
useful precisely because it breaks the mental model. There is no "reset" to wait for. §5.5 says what
the contract does about that.

### 3.5 Kimi / Moonshot — CLAIMED, with a real gap

The coding plan has **5-hour and weekly** windows (CLAIMED, consistent across vendor-adjacent
sources and a third-party monitor whose status bar renders `"Wee:96% 5Ho:99%"`). Credentials are
`KIMI_API_KEY` or `KIMI_CODING_API_KEY`, keys shaped `sk-kimi-*`; the tool's base URL is
`https://api.kimi.com/coding/v1` (CLAIMED, from the tool's own config).

**I could not verify the quota path.** I fetched the repository and attempted to read `src/api.ts`
via the GitHub API; the file did not come back. The exact endpoint, header format and response field
names are **UNKNOWN**. Separately, `kimi-cli` exists on PyPI at 1.50.0 (VERIFIED in the field scan),
so "Kimi" may mean the CLI agent or the Anthropic-compatible endpoint — the field scan flags the same
ambiguity as its open question 6.

### 3.6 Qwen Code — VERIFIED enough to matter, and it is bad news

**Alibaba closed the free OAuth tier entirely on 2026-04-15** (CLAIMED, from the project's own issue
tracker and corroborated by the docs, which now list Qwen OAuth as a hard-coded discontinued
provider). The quota went 2000 req/day → 1000 → 100 → gone. Existing cached tokens may work briefly;
new requests are rejected.

So Qwen Code today is BYOK against Alibaba Cloud's coding plan, OpenRouter or Fireworks. There is no
subscription window to read; whatever quota exists belongs to the key's provider. **This is a
platform where the owner's limit machinery has nothing to attach to.**

### 3.7 Google Gemini CLI / Antigravity — CLAIMED, and a moving target

**Consumer access to Gemini CLI ended 2026-06-18** — three months ago (CLAIMED, from Google's own
developers blog and corroborated across coverage). The replacement is **Antigravity CLI (`agy`)**, a
closed-source Go rewrite. `@google/gemini-cli` still ships and still works for **paid API keys** and
**Gemini Code Assist Standard/Enterprise**.

Antigravity uses a **weekly compute-based cap** with reports of multi-day cooldowns (CLAIMED). No
usage/quota API is documented for it. Its install command, headless flags and JSON output are
**UNKNOWN** — the field scan names this its highest-priority gap, and I did not close it either.

On this machine `~/.gemini/settings.json` is `{"mcpServers":{}}` and `~/.gemini/antigravity/` is
empty, with **no binary on PATH** (VERIFIED in the field scan). The owner has no working Gemini path
today.

For the API-key route, the in-band signal is an HTTP 429 with `RESOURCE_EXHAUSTED`. Whether the error
body carries a machine-readable retry delay I did **not** verify (UNKNOWN) — it is a one-call check
once a key exists, and it belongs in round 2's config-time verification rather than in a guess here.

### 3.8 opencode — VERIFIED from docs

`opencode stats` shows "token usage and cost statistics for your OpenCode sessions" — **category C**,
own accounting, not provider remaining. `opencode auth login` / `auth list` / `auth logout`, with
credentials in `~/.local/share/opencode/auth.json`. `opencode run` is non-interactive; **`opencode
serve`** starts a headless HTTP server (optionally with basic auth) — a real control plane.
`opencode session list --format json`, `--session`, `--continue`, `--fork`.

opencode is a **multiplexer, not a quota source**: whatever quota exists belongs to the provider
behind it. Community plugins implement multi-account rotation (round-robin, least-used, weighted) and
"visible quota status" for ChatGPT OAuth pools (CLAIMED — several independent repos). Provider limit
metadata is pulled from models.dev (CLAIMED).

**INFERRED:** if opencode is adopted, the orchestrator does not gain a quota surface; it inherits the
underlying provider's, one level further away, and loses the ability to attribute a reading to a
specific account unless the plugin exposes it.

### 3.9 Cursor CLI — VERIFIED locally

`cursor-agent 2025.09.12-4852336` on this machine — a build roughly a year old, so treat its flags as
stale. Full `--help` (VERIFIED): `--api-key <key>` / `CURSOR_API_KEY`, `-p/--print`,
`--output-format text|json|stream-json`, `-b/--background`, `--resume [chatId]`, `--model`,
`-f/--force`, and subcommands `login`, `logout`, `status`, `create-chat`, `ls`, `resume`, `mcp`.

**There is no usage, quota, limit or balance command anywhere in the help output** (VERIFIED — I read
the complete listing). `status` checks *authentication* status, not quota. The Cursor Admin API
exists but is **team-scoped and requires a Team Admin** (CLAIMED, Cursor docs) — not available to an
individual on a personal plan. Category D.

### 3.10 GitHub Copilot CLI — CLAIMED, category D for an individual

Every CLI interaction is a **premium request** regardless of model (CLAIMED). All Copilot plans moved
to **usage-based billing with AI Credits on 2026-06-01** (CLAIMED, GitHub blog), billed on token
consumption.

I fetched GitHub's own "Monitoring your Copilot usage and entitlements" page and it documents exactly
three routes: the IDE, `github.com/settings/billing`, and premium-request analytics in the sidebar.
**No REST endpoint for an individual's own remaining quota appears in it** (VERIFIED absence on that
page). Org/enterprise billing APIs exist but are admin-scoped. On limit-hit: "you will be notified
with a message in each of the Copilot interfaces you use" — a human-facing message, i.e. the same
scrape-the-screen trap as §3.1.

On this machine `~/.copilot/config.json` exists with `firstLaunchAt: 2026-08-11` and logs touched
2026-09-13, but **no binary on PATH** (VERIFIED in the field scan).

### 3.11 Amp — CLAIMED

Hybrid subscription-plus-credits. Amp's docs state you can "check your balance in user settings, in
workspace settings, or by running **`amp usage`**" (CLAIMED) — a CLI balance command, which is a
usable surface even without an HTTP API. Auth via `amp login` with an access token available in
security settings; purchased credits expire after twelve months. No documented windows and no
documented reset semantics — like DeepSeek, this is a balance model, not a window model. Not
installed here, so `amp usage`'s output shape is **UNKNOWN**.

### 3.12 Factory Droid — CLAIMED

`FACTORY_API_KEY` environment variable with `droid exec` for headless/CI execution (CLAIMED, Factory
docs); keys prefixed `fk-`. Plans carry **rolling rate limits**, and on Pro/Plus "it is possible to
exhaust quota mid-Mission" (CLAIMED). A third-party token monitor carries a merged change titled
"add Factory Droid plan limits via `FACTORY_API_KEY`", which **implies a readable plan-limits
endpoint exists** — but I did not read its source and the path, headers and fields are **UNKNOWN**.
Not installed here.

### 3.13 Summary table

Columns are exactly the five the task asked for. **usage API** = out-of-band readable remaining;
**in-band** = the running session tells you it hit or is near a limit; **reset ts** = a machine
readable reset time; **multi-account** = two accounts usable on one machine without a re-login
dance; **headless auth** = a run can authenticate with no human and no browser.

| Platform | usage/quota API | in-band limit signal | reset timestamp | multi-account on one machine | headless auth | tag |
|---|---|---|---|---|---|---|
| **Claude Code** | **yes** — undocumented OAuth endpoint; throttles at ~2 calls; dies on idle accounts | no (TUI banner only — proven unsafe) | yes, ISO-8601 | **yes** — `CLAUDE_CONFIG_DIR` + per-account keychain | yes — `ANTHROPIC_API_KEY`/`apiKeyHelper`, **but then no quota API** | VERIFIED |
| **Codex CLI** | **yes — in-band, on disk, free** | **yes** — `rate_limit_reached_type`, `spend_control_reached` | yes, Unix epoch | **yes** — `CODEX_HOME` | **yes** — `login --with-api-key\|--with-access-token` via stdin | VERIFIED |
| **Z.ai GLM** | **yes** — `/api/monitor/usage/quota/limit`, raw `Authorization` | no | yes, epoch ms | yes (API keys) | yes | VERIFIED (tool source) |
| **DeepSeek** | balance only — no window, no reset | no | **no** | yes (API keys) | yes | VERIFIED (official docs) |
| **Kimi / Moonshot** | probably — 5h + weekly exist; **path UNKNOWN** | unknown | unknown | yes (API keys) | yes | CLAIMED |
| **Qwen Code** | **no** — free OAuth tier closed 2026-04-15 | n/a | n/a | yes (BYOK) | yes | CLAIMED |
| **Gemini CLI / `agy`** | **no** documented | 429 `RESOURCE_EXHAUSTED` on the API-key path | unknown | unknown | API key yes; `agy` unknown | CLAIMED |
| **opencode** | **no** — `stats` is own spend | inherits provider | inherits provider | yes — `auth.json` + plugins | yes — `run`, `serve` | VERIFIED (docs) |
| **Cursor CLI** | **no** — nothing in `--help`; Admin API is team-scoped | no | no | via `CURSOR_API_KEY` per invocation | yes — `--api-key` / env | VERIFIED (local `--help`) |
| **Copilot CLI** | **no** individual endpoint | human-readable message only | no | unknown | unknown | CLAIMED |
| **Amp** | **`amp usage`** (CLI, shape unknown) | no | no (credits, not windows) | unknown | token in env | CLAIMED |
| **Factory Droid** | implied by a third-party monitor; **UNKNOWN** | no | unknown | `FACTORY_API_KEY` per invocation | yes — `droid exec` | CLAIMED |
| **Xiaomi MiMo** | **UNKNOWN** — not Anthropic's endpoint | no | unknown | yes (env swap) | yes | VERIFIED it is Claude Code + env |

**Count: of thirteen platforms, four expose a real remaining-capacity reading (Claude Code, Codex,
Z.ai, and Kimi if its path is confirmed); one exposes a balance with no window (DeepSeek, plus Amp);
and seven expose nothing usable to an individual.** Any design that assumes quota is readable is
designing for under a third of the field.

---

## 4. What is NOT feasible, and why

Each of these is a place where a requirement the owner stated meets a platform that cannot honour
it. Per instruction I1 [182]/[183], each becomes its own round-2 question in §6.

**4.1 A hard stop is impossible on seven of thirteen platforms.** «хардстоп, що потрібно зупинити
завдання прямо вже» [171] requires knowing you crossed a threshold *before* the work stops being
useful. Cursor, Copilot CLI, Qwen, Gemini/`agy`, opencode-as-such, and (until their paths are
confirmed) Amp and Factory expose no threshold to cross. On those platforms the only honest
implementations are a *reactive* stop after a 429, or a *proxy* stop on a budget the orchestrator
itself computed — which is not the same guarantee.

**4.2 A percentage threshold is meaningless where there are no windows.** DeepSeek returns a money
balance; Amp returns credits. "80% of weekly" has no referent. The user must express the threshold in
the platform's own unit (currency, credits), which means thresholds cannot be a single global number —
they are per-provider and typed.

**4.3 "Verify before the run that switching works" cannot also verify headroom — on Claude Code.**
[199] asks for pre-run verification. Switching *is* verifiable (`codex login status`, a cheap
identity echo). But an idle Claude Code profile returns `authentication_error` rather than quota
(VERIFIED, §3.1(d)), so the orchestrator cannot learn a standby account's remaining capacity until it
has already started using it. A run that pre-flights "account B has room" is checking something it
cannot see.

**4.4 Reading quota for several accounts on a polling loop is not affordable on Claude Code.** Two calls
then a multi-minute lockout (VERIFIED, §3.1(c)). Whether the budget is per-token or per-IP is UNKNOWN;
if per-IP, all accounts share it and the design must poll the *active* account only.

**4.5 Scraping the session screen for a limit banner is not a fallback.** It is the technique that
produced two independent multi-hour false-positive loops in the previous generation, one of which
"nothing internal detected" and which ended only by external `SIGTERM` (`FIELD-NOTES.md`). It must not
come back as the degradation path for platforms in category D.

**4.6 The owner's 5h/weekly framing does not map onto Anthropic's actual response.** [007] names two
windows. The live response has twenty-plus named buckets and an `extra_usage` block, and its key set
is unstable and undocumented. The requirement is satisfiable, but only by enumerating rather than
naming — which is a different design from the one the wording implies.

**4.7 There is no answer at all on headroom reserve.** §1.8: that half of R1-06 was never asked. Every
threshold in §5 is therefore a threshold against *exhaustion*, not against *leaving the owner room to
work in the morning* — and those are different numbers.

**4.8 A collision worth naming, from his own evidence.** `FIELD-NOTES.md` §5.3 is titled *"A
five-hour token window is not the constraint"* and records: "Across 34 hours the watched account reached
26% of its weekly allowance. **The dependency graph, not the quota, bounded throughput**: of nineteen
phases only two pairs could ever run concurrently."

I am not substituting a preference for his decision — the limit machinery is his call and the
requirement stands. But the one measured 34-hour run of the previous generation says this machinery
governs a constraint that never bound, while the constraint that *did* bind (task dependencies) sits
in a different cluster. Given «нічого надприроднього не потрібно вигадувати» [171], that is worth
putting to him explicitly before the elaborate part gets built. It is question 3 in §6.

---

## 5. Proposals

Written against [171]'s simplicity constraint: the contract below is five functions and one data
shape.

### 5.1 The provider-capability contract

An adapter is a small unit keyed on **(binary, base URL, credential)** — not on the binary alone,
because §3.1's MiMo case proves the same `claude` binary on a different base URL is a different
provider. It implements:

```
describe()        -> Capabilities        # static, answered at config time
read_capacity(account)  -> Reading | Unreadable(reason)
switch(role, account)   -> applied environment (env vars / config dir / key)
verify(account)   -> Identity | Failed   # proves the switch worked, spends ~nothing
signals(stream)   -> [LimitHit | Approaching]   # optional; in-band, if the platform has it
```

`Capabilities` is deliberately small and honest:

```
capacity_source : none | self_accounted | provider_inband | provider_api
window_model    : dynamic | named | balance | none
reset_time      : absolute | none
accounts        : env_dir | api_key | login_only | unknown
headless_auth   : yes | no | unknown
poll_budget     : {min_interval_seconds, burst}    # Claude Code: large interval, burst 2
```

`Reading` normalises the three window encodings into one shape:

```
Reading {
  account_id, observed_at_utc, source,
  buckets: [ { id, label,
               kind      : percent | credits | currency | requests,
               used, limit?, utilization_pct?,
               window_seconds?,          # from window_minutes / unit+number / the bucket's name
               resets_at_utc? } ]
}
```

Three rules make it work across the field, and each one is a lesson from §3 rather than taste:

1. **Enumerate buckets, never name them.** Take every bucket the platform reports that carries a
   utilization or a balance; stop on the worst. This survives Anthropic adding `nimbus_quill` and Z.ai
   switching `TOKENS_LIMIT`→`CREDIT_LIMIT`.
2. **`window_seconds` is derived, never assumed.** `window_minutes × 60` (Codex), the `unit`+`number`
   table (Z.ai), a lookup for named buckets (Anthropic). A window the adapter cannot decode is
   reported with `window_seconds: null` and still counted — an unknown window is not a missing one.
3. **Normalise every reset to UTC** from ISO-8601, epoch seconds or epoch milliseconds.

### 5.2 Graceful degradation — and it already matches his accounting rule

The owner's three-way rule at [171] — «посилатися на облік тієї тулзи … або він веде свій облік …
з посиланням, плюс тої дати, якої не вистачає» — is, almost exactly, this ladder. That is a good
sign: the design falls out of his own words rather than being imposed on them.

| Tier | Capacity source | Platforms | What stop modes work |
|---|---|---|---|
| **0** | Provider API / in-band | Codex, Claude Code, Z.ai, (Kimi) | hard, soft, intermediate |
| **1** | Balance only, no window | DeepSeek, Amp | hard + soft on *money*; no "wait for reset" |
| **2** | Reactive only — the 429 | Gemini API key, anything BYOK | soft only, after the fact |
| **3** | Own accounting vs a user-declared budget | opencode, Cursor, Droid | soft; hard is approximate |
| **4** | Nothing at all | Copilot CLI, Qwen, `agy` | none — see below |

**Tier 4 is where the owner's own [270] requirement rescues the design.** He asked for per-account
role allowlists — «може використовувати тільки для оркестратора, щось тільки для екзек'ютора … І це
важливий дуже нюанс». Invert it: a provider at tier 4 is simply **not eligible** for any role the
user marked as requiring a hard stop. The user does not get a broken guarantee; they get a provider
that cannot be assigned to roles needing that guarantee, stated at config time in plain words. That
also satisfies [199]'s "explain it to the user per platform", because the explanation writes itself
from `describe()`.

**Trade-off, stated plainly.** This makes the config more verbose — each provider declares what it
cannot do. The alternative is a uniform-looking setting that silently means different things per
platform, which is precisely how §3.1(b) and §3.3 produced silent wrong answers.

### 5.3 `Unreadable` is a third state, and it must not default to "proceed"

This is the highest-value single recommendation in this document.

The previous generation's config default is `limits.on_unreadable` = **`proceed`**
(`FIELD-NOTES.md`). Combined with the schema drift in §3.1(b) — which made *every* read unreadable —
that default means the run kept going with no cap enforcement at all, for days
(`weekly_all=unreadable%` across 2026-09-06, 09, 10, 11 and into the current run). And
`FIELD-NOTES.md` records a three-step regression in the pause path built on the same confusion: the
wall-clock fallback for an unreadable read "was pinned to a fixed past epoch, so an unreadable read
resumed a paused run immediately (#65)"; the fix caused a restart to read `STOP` as a manual owner
stop and exit (#73); and "a failed marker write leaves an unattributed `STOP` on disk (#82, open)".

Proposal:

- `Unreadable` carries a typed reason: `auth_expired | throttled | unsupported | network |
  schema_unknown`. These are not interchangeable. `throttled` means *ask later*. `auth_expired` means
  *this account needs a human*. `schema_unknown` means *the adapter is broken and must say so loudly*.
- The policy on unreadable is **per stop-class**, not global: a soft stop may proceed on an unreadable
  read; a **hard** stop must not silently become no stop. Default for hard: hold and escalate.
- `schema_unknown` should be **noisy by construction** — an adapter that gets a 200 it cannot parse
  raises, rather than returning zero. Z.ai's `CREDIT_LIMIT` breakage (§3.3) rendered 0% used, which
  reads as "plenty of room".

### 5.4 Polling, caching and attribution

- **Single-flight cache per account** with a floor from `poll_budget.min_interval_seconds`. For
  Claude Code, measured: burst 2, recovery > 180s (VERIFIED). A conservative floor of one read per
  several minutes per account, served from cache in between.
- **Poll the active account only.** §3.1(d): idle accounts return `authentication_error`, and §4.4:
  the budget may be shared per-IP. Standby-account headroom is not knowable; the config should say so
  rather than pretend.
- **Every `Reading` carries `account_id`, and the orchestrator refuses to compare readings across
  accounts.** `FIELD-NOTES.md` records both halves of this bug: "my limits position was measuring the
  wrong account", with 94% weekly on the wrong pool; and "**A weekly-usage figure can move without any
  usage changing** — when the supervisor was repointed from one account to another mid-run, the weekly
  reading fell from 26% to 6% from the account switch alone." A threshold crossing computed across an
  account switch is meaningless.
- **Prefer in-band where it exists.** For Codex the orchestrator should tail the rollout JSONL rather
  than call anything: it is free, unthrottled, correctly attributed, and carries the context window
  too. **INFERRED:** where a platform offers both, in-band should win.

### 5.5 The three stop modes, made precise per tier

| Owner's mode [171] | What it needs | Available at |
|---|---|---|
| **hard** — «зупинити завдання прямо вже» | predictive threshold + ability to kill mid-task | tiers 0–1 |
| **soft** — «дати поточному завданню завершитися, нових не запускати» | a threshold check **at spawn time only** | tiers 0–3 |
| **intermediate** — «записати стан, зберегти сесію, зупинити повністю, аби потім продовжити» | **resume by session id** — *not* a quota capability | see below |

**The most useful finding for the open item.** The owner left the intermediate mode open with «не
знаю» [171]. What actually gates it is **not** quota at all — it is whether the platform can close a
session and reopen *that* session later. That capability is independent of everything else in this
cluster:

- Claude Code: `--resume`, plus `--bg`/`attach`/`stop`/`respawn` (VERIFIED)
- Codex: `resume`, `fork`, `queue`, session index on disk (VERIFIED)
- opencode: `--session`, `--continue`, `--fork`, `session list` (VERIFIED)
- Cursor: `--resume [chatId]`, `create-chat` returns an id (VERIFIED)
- Copilot CLI, Amp, Droid, `agy`: **UNKNOWN**

So the intermediate mode is implementable on the four platforms above regardless of their quota tier,
and unknown on the rest. Soft stop is the near-universal mode; hard is the scarce one. If one mode
has to be the default, the evidence points at soft.

Note also that Claude Code ships a **native** hard stop that needs no polling at all:
`--max-budget-usd` in `--print` mode (VERIFIED, §3.1). Where the platform enforces the cap itself,
the orchestrator should use that instead of watching — fewer moving parts, which is what [171] asked
for.

### 5.6 Account switching, and proving it works before a run

[199] asks for three mechanics, explained per platform and verified before a run. What they actually
are, from §3:

| Mechanism | Platforms | Verification probe |
|---|---|---|
| **Config-dir env var** | Claude Code (`CLAUDE_CONFIG_DIR`, profile switcher), Codex (`CODEX_HOME`) | `codex login status`; for Claude, read `oauthAccount.emailAddress` from the profile's `.claude.json` |
| **API key in env** | Z.ai, DeepSeek, Kimi, Cursor, Droid, MiMo | one cheap authenticated call |
| **Interactive login only** | Copilot CLI, Amp, `agy` (unknown) | none available headless — flag at config time |

The two env-var platforms are structurally identical, which means one mechanism covers the owner's
two most-used tools. Three cautions for the pre-run check, all VERIFIED: a listed profile may
have **no usable token** (listed in the keychain, no token returned); macOS may **block on a GUI
Keychain dialog** on first access per account, which is fatal unattended; and `~/.claude.json` vs
`~/.claude/.claude.json` diverge when `CLAUDE_CONFIG_DIR` is unset, which is exactly the daemon case.

**The honest framing for [199]:** the pre-run check can prove *identity* — "this role will run as
this account" — cheaply and reliably. It cannot prove *headroom* for an idle account (§4.3). Those
should be presented to the user as two different assurances rather than one.

### 5.7 The watched assignment file

[195]/[196] asks for a single file, polled, with changes typed soft or hard. Two notes:

- `extract/corrections.md` records that **mtime was a hedged example** («Можливо, там, наприклад, по
  даті») and that ANALYSIS-01 wrongly states "mtime named as the mechanism". The mechanism is open.
  Content hashing is more robust than mtime for a file an editor may rewrite, and costs nothing at
  this scale — but this is the owner's call, not mine, and it should be re-asked rather than assumed.
- `extract/by-item.md` flags that **who polls the file is unresolved** — «оркестратор чи контекст
  вочер» — and that this collides with the single-orchestrator invariant at [300]. That belongs to the
  roles cluster, but it blocks this one: a role reassignment with type `hard` needs an owner.

---

## 6. Open questions for the owner (round 2)

Ordered by how much they block the build.

1. **Headroom reserve — never asked.** «Чи можна витрачати ліміт до нуля, чи треба лишати запас на
   твою власну роботу?» This half of R1-06 was dropped by the interviewer and there is no answer
   anywhere in the transcript. Every threshold designed above targets exhaustion; a morning reserve is
   a different number and possibly a different mechanism. **Nothing in this cluster should be built
   before this is answered.**

2. **Re-ratify soft / hard / intermediate.** Per `extract/corrections.md`, the entire R1-06 stop rule
   is unratified — he asked for a repeat at [178] and the interviewer moved on. This vocabulary is
   reused across R1-07, R1-08 and Д12.

3. **The limits machinery may be governing the wrong constraint.** `FIELD-NOTES.md` §5.3: 34 hours,
   26% of weekly, and "the dependency graph, not the quota, bounded throughput". Given «нічого
   надприроднього не потрібно вигадувати» [171] — how much of this should exist in v1, versus a
   minimal "stop on 429, record state, resume" and the effort spent on dependencies instead?

4. **A hard stop is impossible on seven of thirteen platforms** (§4.1). Should such a platform be
   (a) refused for roles that require a hard stop — which his own [270] allowlist already expresses —
   (b) allowed with a clearly-labelled approximate stop from the orchestrator's own accounting, or
   (c) allowed silently? This is the largest single divergence I1 asked me to surface.

5. **What is the threshold unit on a balance provider?** DeepSeek returns money, Amp returns credits,
   neither has a window (§4.2). "80% of weekly" has no meaning. Per-provider typed thresholds, a
   currency budget per run, or exclude balance providers from threshold logic entirely?

6. **Standby headroom is unknowable on Claude Code** (§4.3, VERIFIED: idle profile →
   `authentication_error`). Is "the orchestrator can verify *who* it will run as, but not *how much
   room* that account has, until it starts" acceptable — or should the config require periodically
   waking each standby account to keep its token fresh?

7. **What should happen when quota is unreadable?** The previous default was `proceed`, and schema
   drift made every read unreadable for days (§5.3). Confirm the policy per stop-class, and confirm
   that a hard stop must never silently degrade to no stop.

8. **Should in-band beat out-of-band where both exist?** For Codex, tailing the session file is free,
   unthrottled, correctly attributed and carries the context window as well (§3.2). Adopting that as
   the rule would make Codex the reference platform for this cluster.

9. **Is `--max-budget-usd` the preferred hard stop on Claude Code** (§5.5)? The platform enforces it
   itself, with no polling, no keychain and no throttle — but it is per-session and `--print`-only,
   and it is a dollar cap rather than a percentage of a subscription window.

10. **Which "Kimi", and which "Gemini"?** Kimi's quota path is UNKNOWN (§3.5) and `kimi-cli` is a
    different thing from the Anthropic-compatible endpoint. Gemini's consumer path **ended
    2026-06-18** and the replacement `agy` has no documented quota surface (§3.7). Both need a
    decision before an adapter is scoped.

11. **Qwen has no subscription tier left** (§3.6, closed 2026-04-15). Keep it as BYOK-only, or drop it
    from the target list?

12. **MiMo breaks the adapter key** (§3.1, last note). Confirm that a provider is
    *(binary, base URL, credential)* and that pointing Claude Code at a non-Anthropic base URL means
    its quota surface is UNKNOWN rather than Anthropic's.

---

## Appendix — commands and probes used

All read-only. No agent runs were started; no owner quota was spent on model calls. The usage-endpoint
probes in §3.1(c) did consume that endpoint's own throttle budget; it recovers on its own.

```bash
# Claude Code quota, per switcher profile
security find-generic-password -s "Claude Code-credentials-<hash>" -w | jq -r .claudeAiOauth.accessToken
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20"
# keychain service name derivation (VERIFIED)
printf '%s' "$HOME/.<switcher>/profiles/<name>" | shasum -a 256 | cut -c1-8

# Codex quota, in-band, no network
grep -m1 rate_limits ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl | python3 -m json.tool
CODEX_HOME=/path/to/account codex login status

# Z.ai (from glm-quota.py source)
curl -s https://api.z.ai/api/monitor/usage/quota/limit -H "Authorization: $ZAI_KEY"   # raw, no Bearer

# DeepSeek
curl -s https://api.deepseek.com/user/balance -H "Authorization: Bearer $DEEPSEEK_API_KEY"
```

**Sources.**
[Z.ai quota tool source](https://github.com/zeljkoavramovic/glm-quota) ·
[Z.ai CREDIT_LIMIT breakage](https://github.com/onllm-dev/onWatch/issues/122) ·
[Z.ai quota endpoint report](https://github.com/getpaseo/paseo/issues/5057) ·
[DeepSeek Get User Balance](https://api-docs.deepseek.com/api/get-user-balance/) ·
[Kimi Code Usage tool](https://github.com/Golden0Voyager/kimi-code-usage) ·
[Qwen OAuth free tier closure](https://github.com/QwenLM/qwen-code/issues/3203) ·
[Qwen Code authentication docs](https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/) ·
[Google: transitioning Gemini CLI to Antigravity CLI](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/) ·
[opencode CLI reference](https://opencode.ai/docs/cli/) ·
[opencode providers](https://opencode.ai/docs/providers/) ·
[Cursor headless CLI](https://cursor.com/docs/cli/headless) ·
[Cursor APIs overview](https://cursor.com/docs/api) ·
[GitHub Copilot usage monitoring](https://docs.github.com/copilot/how-tos/monitoring-your-copilot-usage-and-entitlements) ·
[Copilot usage-based billing](https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/) ·
[Amp pricing](https://ampcode.com/docs/pricing) ·
[Amp owner's manual](https://ampcode.com/manual) ·
[Factory Droid CLI reference](https://docs.factory.ai/droid-cli/cli-reference) ·
[Factory plan limits via FACTORY_API_KEY](https://github.com/Javis603/token-monitor/pull/685)
