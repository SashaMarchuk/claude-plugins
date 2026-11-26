# SPEC-adapters — the platform adapter and the provider model

**Date:** 2026-09-19. **Status:** buildable specification. **Plugin name (working):** `orchestrator`.
**Audience:** the implementer. This document is written so that nothing in it needs to be asked about
before code is written. Where a question genuinely remains, it is not left in the body — it is in §17,
phrased for the owner in Ukrainian, and the body ships a **DEFAULT-PROPOSED** value so the build is not
blocked while he answers.

**Evidence tags.** **VERIFIED** — read in a source file on this machine today, or measured by a document
that names the command it ran. **CLAIMED** — a vendor, README or third party asserts it and nothing was
executed behind it. **INFERRED** — my reasoning from the two above. Every non-obvious factual sentence
carries one. A default is never VERIFIED; a default is a proposal.

**Sources, in the order they bind.**

1. `../../round-1/TRANSCRIPT-01.md` — the owner's own words at `[row]` anchors. Where the analysis and
   the transcript disagree, the transcript wins (the rule `JUDGE-fidelity` applied, and it found real
   disagreements).
2. `../../round-1/ANALYSIS-01.md` — the requirement codes (`R1-06`, `Д8`, …) used throughout.
3. `../extract/corrections.md` — which of those requirements the owner actually ratified.
4. `../platforms/ADAPTER-CONTRACT.md` — the fifteen-platform capability record. This spec formalises it;
   it does not re-derive it.
5. `../clusters/C4-capacity-*.md`, `../LANDSCAPE.md`, `../adoption/ADOPTION-VERDICT.md`.
6. `<baseline-marketplace>/requirements/OWNER-DECISIONS.md`
   and `docs/config-levels.md` — the owner's own plugin architecture. Binding, per Д1 [416].
7. `ARCH-*.md` and `JUDGE-*.md` in this directory.

---

## 0. Which design this is the adapter layer of, and where the judges disagreed

### 0.1 The consensus

| Judge | Axis | Winner | Runner-up |
|---|---|---|---|
| `JUDGE-fidelity` | faithfulness to what he said | **ARCH-minimal (8)** | ARCH-reliability (7) |
| `JUDGE-cost` | build cost and running cost | **ARCH-minimal (9)** | ARCH-operability (7) |
| `JUDGE-survival` | behaviour on a bad night | ARCH-operability (8) | **ARCH-adapters (7)** |

Two of three name **`ARCH-minimal`**, and the third ranks `ARCH-adapters` — the design this spec draws
its mechanisms from — second, not first. So the instruction this spec follows is the one all three
judges converge on rather than the one any single judge prefers:

> **Build the adapter layer at `ARCH-minimal`'s size, and take from `ARCH-adapters` only the mechanisms
> the judges independently grafted.**

Those grafts, with the judge that asked for each, are the spine of this document:

| Mechanism | Grafted by | Section here |
|---|---|---|
| Five-value capability vocabulary; `undocumented ≠ impossible`; unknown degrades **closed** | `JUDGE-cost` G11 (~15 lines) | §4 |
| `probes.json` — liveness / identity / capacity probes as **data** | `JUDGE-fidelity` G4 | §3.5 |
| `requirements.json` + `plan.json.weakened[] / denied[]`, each row carrying `owner_item` | `JUDGE-fidelity` G5, `JUDGE-survival` G9 | §6 |
| The defaults table **as a contract** — nothing outside it invents a default at runtime | `JUDGE-fidelity` G6 | §14 |
| `readCapacity` must return the sum type; an unparseable 200 raises, never returns zero | `JUDGE-survival` G4 | §8 |
| `Unreadable` with typed sub-kinds; stale capacity never authorises routing | `JUDGE-survival` (reliability I8) | §8.6 |
| `capacity.on_unknown: hold_dispatch` — inverting the shipped `proceed` | all four designs | §8.7 |
| `reserve_pct: 0` **plus a printed question**, not a silent number | `JUDGE-survival` G12 | §8.8, §17 |
| `context.post_compact_prompt` as **his** key, not the plugin's behaviour | `JUDGE-fidelity` §5.3 | §5.11 |

### 0.2 The three places the judges disagree, and which one this spec follows

**D1 — the conformance dispatch gate.** `JUDGE-survival` G4 wants `orchestrator:adapter verify` to
include a **live smoke against the configured account**, with `adapter.verify_max_age_hours: 24` gating
dispatch. `JUDGE-cost` calls exactly that *"the only standing bill in the set that exists even when no
run is happening… one launched session per adapter per day, forever"* and drops the whole suite.

**Followed: cost on the live smoke, survival on the fixtures.** §12 splits `verify` into two halves.
The **fixture half** is offline, tokenless, runs in CI and again at every preflight, and carries all
three of survival's mechanical catches (`compact` must return a `Proof`; `send` may not report stronger
than `accepted`; `readCapacity` may not return a scalar). The **live half** runs only when its input
changed — a different `version_pin`, a different adapter content hash, or an expiry the owner may set —
never on a calendar. Rationale: the lying-manifest class is caught by the fixtures, which cost nothing;
the daily smoke was buying only *version drift*, and §10 catches version drift directly and for free.

**D2 — capability negotiation as a run phase.** `JUDGE-fidelity` and `JUDGE-survival` both graft
`plan.json`; `JUDGE-cost` declines negotiation, noting *"a PREFLIGHT that can refuse for reasons he never
asked about"*, and estimates the graft is worth ~10% of its price without the phase.

**Followed: cost on the phase, fidelity on the file.** There is no NEGOTIATE state in the run machine.
Negotiation is §6.4 — a loop of about forty lines inside preflight — and its output is the file both
other judges asked for. The refusal friction `JUDGE-cost` objects to is bounded by
`negotiate.interactive` (§6.5) and recorded as a tension in §16.2.

**D3 — how strict `capabilities()` may be.** `JUDGE-fidelity` charges `ARCH-adapters` six points partly
for *"a brake he did not ask for"* and for a false evidential claim. `JUDGE-survival` rewards the same
strictness as *"convert a 03:00 degradation into a 22:00 refusal"*.

**Followed: survival on degrading closed, fidelity on the record-keeping.** `negotiate.on_unknown:
impossible` ships. Every consequence of it is written into `plan.json.weakened[]` / `denied[]` against
the owner item it weakened, and §16 records the friction as a tension rather than as a solved problem.

### 0.3 One correction to an input this spec depends on

`ARCH-adapters` §9.4 states that the qualifier *«в межах налаштованих повноважень»* at `[325]` was *"the
interviewer's phrase, not his"*, and cites `extract/corrections.md`. `JUDGE-fidelity` §3 checked that
and found it wrong: `[325]` is the interviewer's restatement, **and the owner answered `[328]` «Так,
підтверджую»**, which `corrections.md` lists by row in its ratified column (VERIFIED by
`JUDGE-fidelity`). **Consequence for this spec:** bounded authority on `answer` (§5.10) is grounded in a
decision he ratified, not asserted over one. The default does not change; its justification does.

### 0.4 A counting error in `ADAPTER-CONTRACT.md`, resolved here

`ADAPTER-CONTRACT.md` §2 states *"Seventeen operations. Twelve are REQUIRED for tier-1; five are
optional."* Its own per-operation tables mark **fourteen** `REQUIRED` (§2.0 one, §2.1 four, §2.2 three,
§2.3 six), **two** optional (`launchAttached`, `costMeter`), and leave `env_for` unmarked (VERIFIED — I
counted the rows). This spec resolves the arithmetic as **14 required + 2 optional + 1 conditional**
(§5.1) and does not carry the "twelve" figure forward anywhere.

---

## 1. The object model

### 1.1 The five objects and the one derived one

```
Provider  — where the tokens come from and who bills them
Platform  — which binary drives a session and what it can be told to do
Account   — which credential, on which platform, the owner may spend under
Role      — what a session is for, and the capabilities that job requires
Lane      = Platform × Provider × Account × Role     (the runnable slot)
Engine    — the process that runs *inside* a lane (GSD, superpowers, custom) — out of scope here
```

`Lane` is the unit everything else in the orchestrator schedules, meters, stops and reports on. It is
**not** a session: one lane runs many sessions over a night, and one ticket may span several sessions
inside one lane (§5.6, close-and-reseed).

**Why Provider and Platform are two objects and not one.** The same `claude` binary pointed at
`ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic` is GLM: a different biller, a different capacity
API, a different context window, and a **contractual** concurrency ceiling with a ban attached
(VERIFIED, `glm-spike.md` §12 via `ADAPTER-CONTRACT.md` §0). Four of the fifteen names on the owner's
list — GLM, DeepSeek-as-a-lane, Kimi-as-an-endpoint, MiMo-as-a-model — are providers behind an existing
platform and need **no adapter at all**: one provider record plus `env_for()` on the driver (§5.17).
`ADAPTER-CONTRACT.md` §5.3 calls this *"the highest value-per-hour move in the entire scan"* (VERIFIED
as the research's own conclusion).

**The adapter key is a triple, never the binary.** `(binary, base_url, credential)`. The owner's own
machine proves why: `~/.config/claude-mimo/env` points `claude` at
`https://token-plan-sgp.xiaomimimo.com/anthropic` (VERIFIED, `00-field-scan.md` §2), and a capacity
reader keyed on the binary alone would read Anthropic's numbers for a session Anthropic is not billing.

### 1.2 Where these records live

Per Д1 [416] the orchestrator obeys `<baseline-marketplace>`. The canonical slot table is
`docs/config-levels.md` §2 and is **not** copied here; what is fixed here is the key namespace.

| Slot | Level | Path | What this spec puts there |
|---|---|---|---|
| 2 | project committed | `./.claude/shared/plugins/orchestrator.json` | `platforms`, `roles`, project lane defaults |
| 4 | user | `<config-root>/shared/plugins/orchestrator.json` | `providers`, `accounts`, personal ceilings |
| 6 | personal project | `./.claude/shared/plugins/orchestrator.local.json` | overrides for this project, gitignored |
| — | marketplace | `plugins/orchestrator/config/recommended.json` | advice only, carries `strength` |

`<config-root>` resolves exactly as OWNER-DECISIONS 3.3 requires: `CLAUDE_CONFIG_DIR` verbatim if set,
otherwise `os.homedir()` + `/.claude`. **Every path passed to a file call is absolute and contains no
`~`.** Precedence is the resolver's, unchanged: personal project ≻ user ≻ project committed, and inside
a band the per-plugin file beats the general one (`docs/config-levels.md` §4).

`recommended.json` is **advice, never a value** (OWNER-DECISIONS 2.2, 2.3). A shipped adapter may carry
`{"strength":"weak"}` recommendations for a provider or a model; nothing in the resolver reads them as
config. The agnosticism rule bites here in one specific way: **no platform name appears in core code.**
The one file in the core that is allowed to name owner requirements — and is forbidden to name platforms
— is `requirements.json` (§6.1). The one place platform names are legal is an adapter directory.

### 1.3 Run state lives outside the work tree

```
<state-root>    = <config-root>/shared/orchestrator/state/<project-key>/
<project-key>   = first 12 hex of sha256(absolute path of the project root)
<run-root>      = <state-root>/runs/<run-id>/
<run-id>        = UTC "YYYYMMDD-HHMMSS" of the run's start
```

**DEFAULT-PROPOSED:** `state.root: <config-root>/shared/orchestrator/state` — run state outside the
repository, because the previous generation put it inside and produced 327 dirty tracked files, which is
also the direct cause of the merge that reported success and moved nothing (`git checkout master`
aborts on a modified tracked file; VERIFIED, FIELD-NOTES §4.1 via `JUDGE-survival` F6).

Inside a run root, this spec owns exactly these paths:

```
<run-root>/
├── plan.json                 §6.6   written once at the end of preflight, immutable
├── lanes/<lane-id>/
│   ├── lane.json             §1.8   the resolved lane record, immutable for the run
│   ├── events.jsonl          §7     normalised events, append-only, dense seq
│   ├── handles/<handle>.json §5.3   one file per live handle
│   └── sessions.jsonl        §5.6   the ticket→session lineage for this lane
├── capacity/
│   ├── <account-id>.json     §8.5   the single-flight cache, one file per account
│   └── meter.lock                   flock held by the one process allowed to read capacity
└── adapters.resolved.json    §3.4   which adapter directory won discovery, with its content hash
```

### 1.4 `Provider`

```jsonc
{
  "id": "glm-coding-pro",                  // string, unique, [a-z0-9-]{2,48}
  "label": "Z.ai GLM coding plan (Pro)",   // string, for the owner's eyes
  "base_url": "https://api.z.ai/api/anthropic",   // string|null; null = the platform's own default
  "auth_ref": { "kind": "env", "var": "ZAI_API_KEY" },   // §1.7 — never a secret value
  "model": "glm-5.3",                      // string, REQUIRED, pinned explicitly
  "small_model": "glm-5.3-flash",          // string|null — the Д8 cheap-watcher pin
  "context_window": 200000,                // int|null tokens; null = ask the platform at runtime
  "capacity_model": "Window",              // "Window" | "Credit" | "None" | "Unknown"   §8.1
  "capacity_probe": "glm-monitor",         // string|null — a probe id in probes.json   §3.5
  "concurrency": { … },                    // §9.2 — REQUIRED, may be the explicit "unknown" shape
  "price_hint": { "in_per_mtok": 0.15, "out_per_mtok": 0.50, "currency": "USD",
                  "prov": "claimed" },     // object|null, advisory only, never a scheduling input
  "env": { "ANTHROPIC_BASE_URL": "{{base_url}}",
           "ANTHROPIC_AUTH_TOKEN": "{{auth}}",
           "ANTHROPIC_MODEL": "{{model}}" },       // the env_for() template   §5.17
  "notes": ["contractual ceiling, not technical: 3 violations → ban"]
}
```

Rules, each with the failure it prevents:

1. **`model` is required and is always passed explicitly to the platform.** Inheriting the owner's
   `~/.codex/config.toml` (`model = "gpt-6-astra"`) produced a **100%-failing run** (VERIFIED,
   `codex-cli-spike.md` via `ADAPTER-CONTRACT.md` §2.4.6).
2. **`context_window` must agree with `model`, or the provider lies quietly.** GLM compacts at 200 K if
   `CLAUDE_CODE_AUTO_COMPACT_WINDOW` disagrees with the model id (VERIFIED,
   `ADAPTER-CONTRACT.md` §6.6). Preflight asserts the two agree and refuses the lane if they do not.
3. **`price_hint` is never a scheduling input in this generation.** Droid's credit multipliers span
   **150×** inside one platform's model list (VERIFIED, `ADAPTER-CONTRACT.md` §6.5); routing by price is
   a real subsystem and is out of scope. The field exists so the morning report can print a number.

### 1.5 `Platform`

```jsonc
{
  "id": "claude-code",
  "adapter_id": "claude-code",             // the directory name under adapters/platforms/
  "binary": "claude",
  "version_pin": "2.1.278",                // exact string   §10
  "transport": "exec",                     // exec | rpc | http | acpx | pty
  "home_env": "CLAUDE_CONFIG_DIR",         // the env var that scopes an account, or null
  "default_provider": "anthropic-max",     // used when a lane names no provider
  "autoupdate": { "env": { "DISABLE_AUTOUPDATER": "1" }, "config_edit_required": false }, // §10.3
  "hazards": ["keychain-gui-dialog-on-first-use-per-account"]
}
```

The **capability map is not here.** It is in the adapter's own `manifest.json` (§4), because a capability
is a property of the adapter-plus-binary pair and must move when the adapter moves. A `Platform` record
that tries to set `capabilities` fails config validation with a named error.

### 1.6 `Account`

```jsonc
{
  "id": "zai-personal",
  "platform": "claude-code",               // an account belongs to exactly one platform
  "credential_kind": "api_key",            // config_dir | api_key | login_only | keychain
  "env": { "ZAI_API_KEY": { "from_keychain": { "service": "zai", "account": "<user>" } } },
  "identity_probe": "claude-status",       // probe id   §3.5
  "roles_allowed": ["executor", "ticket-watcher"],   // [] or omitted = every role
  "concurrency_override": null,            // int|null — lowers, never raises, §9.4
  "capacity_account_key": "zai:sasha"       // §8.4 — the identity capacity readings are keyed on
}
```

`roles_allowed` is the owner's own lever, verbatim: *«може використовувати тільки для оркестратора,
щось тільки для екзек'ютора… І це важливий дуже нюанс»* [270], [276] (VERIFIED, `ANALYSIS-01` R1-07).

### 1.7 `auth_ref` and the secret rule

`auth_ref` and every value inside `Account.env` is a **reference**, never a literal. Four kinds:

```jsonc
{ "kind": "env",        "var": "ZAI_API_KEY" }
{ "kind": "keychain",   "service": "Claude Code-credentials-<hash8>", "account": "<user>" }
{ "kind": "config_dir", "path": "/Users/…/.<switcher>/profiles/<profile>" }
{ "kind": "file",       "path": "/Users/…/.config/claude-mimo/env", "field": "ANTHROPIC_AUTH_TOKEN" }
```

> **Invariant SEC-1.** No config slot may hold a credential value. Preflight scans every resolved
> `orchestrator.*` config value against a secret-shaped pattern set (`sk-[A-Za-z0-9_-]{16,}`,
> `gh[pousr]_[A-Za-z0-9]{20,}`, `tp-[A-Za-z0-9]{16,}`, a bare 40+ hex string, `Bearer ` followed by 20+
> non-space characters) and **refuses to start** naming the slot and the key, never the value.
> Rationale: the previous generation printed two passwords into a transcript from a Playwright
> `--trace on` (VERIFIED, FIELD-NOTES §11.10), and a transcript is a file this design reads all night.

> **Invariant SEC-2.** The orchestrator never mutates the owner's keychain, config directory, or any
> file it did not create. `selectAccount` returns **environment only** (§5.16). This is the direct
> reading of R1-15 [357]: the environment's technical limits are the user's to configure.

### 1.8 `Role` and `Lane`

```jsonc
// Role
{
  "id": "orchestrator",
  "needs": ["G_send", "G_answer", "D_context", "B_identity"],   // capability axis ids, §4.2
  "needs_predictable_capacity": true,                            // §8.9
  "provider_pin": null,          // string|null — forces a provider regardless of the platform default
  "model_pin": null,             // string|null — overrides Provider.model for this role only
  "authority": { "may_answer": true, "may_irreversible": false },  // §5.10
  "max_concurrent": 1            // int — how many lanes may hold this role at once
}
```

Six roles ship. The set is open: a role is a config object, so a seventh costs one entry.

| Role | `needs` (DEFAULT-PROPOSED) | `needs_predictable_capacity` | `max_concurrent` |
|---|---|---|---|
| `orchestrator` | `G_send`, `G_answer`, `D_context`, `B_identity` | **true** | `1` |
| `executor` | `A_launch`, `C_transcript`, `B_identity` | false | `2` |
| `validator` | `A_launch`, `C_transcript` | false | `1` |
| `sentinel` | `A_launch` | false | `1` |
| `ticket-watcher` | `A_launch` | false | `1` |
| `answerer` | `G_send`, `G_answer` | false | `1` |

`needs_predictable_capacity` is the owner's [270] lever inverted, as `C4-capacity-research.md` §5.2
recommends (VERIFIED): a provider that can report nothing is **not eligible** for a role that declares
it, stated at config time in plain words, instead of producing a guarantee that breaks at 03:00.

```jsonc
// Lane — resolved, written to <run-root>/lanes/<lane-id>/lane.json, immutable for the run
{
  "id": "L2",
  "lane_key": "7c1f0a9e4b52",        // first 12 hex of sha256(platform \0 provider \0 account \0 role)
  "platform": "claude-code", "provider": "glm-coding-pro",
  "account": "zai-personal", "role": "executor",
  "adapter_dir": "/Users/…/plugins/orchestrator/adapters/platforms/claude-code",
  "adapter_sha256": "…",             // content hash of the adapter directory, §3.4
  "version_observed": "2.1.278",
  "capabilities_effective": { … },   // manifest ∩ preflight, downgrade-only, §6.3
  "capacity_model": "Window",
  "concurrency": { "scope": "provider_account", "max": 2, "basis": "contract" },
  "posture": { … },                  // §11.4, asserted after the first launch
  "verified_at": "2026-09-19T21:04:11Z"
}
```

`lane_key` exists so that a lane's directory name is stable across runs for the same combination, which
makes a cross-run comparison of one lane's behaviour a `diff`. `id` (`L1`, `L2`, …) is the human-facing
label in reports and stop commands, assigned in preflight order.

### 1.9 Worked example E1 — three lanes, resolved

Config as the owner would actually have it (abridged; slot 4 is his user file, slot 2 the project's):

```jsonc
// <config-root>/shared/plugins/orchestrator.json         (slot 4, personal, this machine)
{ "orchestrator": {
  "providers": {
    "anthropic-max":  { "id":"anthropic-max","base_url":null,"model":"claude-opus-5",
                        "small_model":"claude-haiku-4","context_window":1000000,
                        "capacity_model":"Window","capacity_probe":"anthropic-oauth-usage",
                        "concurrency":{"scope":"none","max":null,"basis":"technical"} },
    "glm-coding-pro": { "id":"glm-coding-pro","base_url":"https://api.z.ai/api/anthropic",
                        "model":"glm-5.3","small_model":"glm-5.3-flash","context_window":200000,
                        "capacity_model":"Window","capacity_probe":"glm-monitor",
                        "concurrency":{"scope":"provider_account","max":2,"basis":"contract",
                                       "on_violation":"ban_risk","pool":"shared"} },
    "openai-prolite": { "id":"openai-prolite","base_url":null,"model":"gpt-6-codex",
                        "context_window":258400,"capacity_model":"Window",
                        "capacity_probe":"codex-rollout-inband",
                        "concurrency":{"scope":"none","max":null,"basis":"technical"} }
  },
  "accounts": {
    "cc-<profile-A>": { "platform":"claude-code","credential_kind":"config_dir",
                       "env":{"CLAUDE_CONFIG_DIR":"<profile-dir>"},
                       "identity_probe":"claude-status","capacity_account_key":"anthropic:<profile-A>" },
    "zai-personal":  { "platform":"claude-code","credential_kind":"api_key",
                       "env":{"ZAI_API_KEY":{"kind":"keychain","service":"zai","account": "<user>"}},
                       "identity_probe":"glm-identity","roles_allowed":["executor"],
                       "capacity_account_key":"zai:sasha" },
    "codex-personal":{ "platform":"codex-cli","credential_kind":"config_dir",
                       "env":{"CODEX_HOME":"/Users/sasha-marchuk/.codex"},
                       "identity_probe":"codex-login-status","capacity_account_key":"openai:personal" }
  },
  "lanes": [
    { "role":"orchestrator", "platform":"claude-code", "provider":"anthropic-max", "account":"cc-<profile-A>" },
    { "role":"executor",     "platform":"claude-code", "provider":"glm-coding-pro","account":"zai-personal" },
    { "role":"executor",     "platform":"codex-cli",   "provider":"openai-prolite","account":"codex-personal" }
  ]
}}
```

Resolution produces `L1` (orchestrator on Anthropic), `L2` (executor on GLM through the *same* `claude`
binary), `L3` (executor on Codex). **`L1` and `L2` share a platform and share nothing else**: different
biller, different capacity endpoint, different context window, different concurrency ceiling. That is
the whole argument for the object split, in one owner-plausible config.

---

## 2. Identity: what is keyed on what

Four facts from the field that force the key structure (all VERIFIED, `ADAPTER-CONTRACT.md` §6.3):

- Session ids have five incompatible shapes: UUIDv4 (Claude Code, Cursor, Gemini), ULID-ish (Codex,
  MiMoCode), prefixed strings (Amp `T-…`, OpenCode `ses_…`), and **none at all** (Aider).
- Three platforms let the client name the id before launch; five mint it server-side, which opens a
  crash window between launch and the first durable record.
- `pi` **silently forks** a session if `--session-id` is used from a drifted cwd.
- Codex records a custom client's thread as `source:"vscode"`, so ownership cannot be filtered by
  source and must be filtered by a name prefix.

> **Invariant ID-1.** The platform's session id is never the orchestrator's primary key. Key on
> `ticket_id`; store `(platform, account, session_id)` as an **attribute**, and store it as a **list**,
> because close-and-reseed turns one ticket into many sessions (§5.6).

> **Invariant ID-2.** Where the platform lets the client name the id, the adapter names it
> `orc-<run-id>-<lane-key>-<n>` before launch and the orchestrator writes the ticket→session row
> **before the first token**. Where the server mints it, the first
> `recovery.id_grace_seconds` (**DEFAULT-PROPOSED: `20`**) of a task are declared *unrecoverable by id*
> and recovery is by **re-dispatch**, not by resume. Rationale: `[171]`'s guarantee — *«в нас в реєстрі
> має записуватись кожен стан… щоби було відновити процес і продовжити, навіть руками»* — is what the
> crash window quietly breaks, and twenty seconds is the observed order of a server-mint round trip
> (INFERRED from the launch timings in `codex-cli-spike.md`; not measured as a distribution).

> **Invariant ID-3.** The name prefix `orc-` is how the orchestrator recognises its own sessions in any
> platform roster. Nothing matches by pattern over a command line, ever. Rationale:
> `pkill -f 'playwright test'` killed an unrelated lane because **every lane's own prompt contained that
> literal string** (VERIFIED, FIELD-NOTES §11.8).

**Roster reads are unioned across accounts.** A roster read under one account shows half the fleet
(VERIFIED, `claude-code-spike.md` via `ADAPTER-CONTRACT.md` §2.4.8). The orchestrator calls the roster
probe once per *account*, not once per platform, and unions the results before deciding anything.

---

## 3. The adapter: a directory, not a class

### 3.1 The four files

```
adapters/platforms/<adapter-id>/
├── manifest.json     the capability map. static. no network. no model token.    §4
├── adapter           executable. one subcommand per operation. JSON on fd 1.    §5
├── normalize         executable or *.jq. platform-native records → §7 events.
└── probes.json       liveness / identity / capacity / roster probes AS DATA.    §3.5
```

No registration, no code change in the core, no rebuild. Adding a platform is adding a directory.

### 3.2 Discovery order

First hit wins, mirroring the owner's config ranking — personal beats project-committed beats shipped
(OWNER-DECISIONS 4.15):

```
1  ./.orchestrator/adapters.local/platforms/<id>/              personal, this project, gitignored
2  <config-root>/shared/orchestrator/adapters/platforms/<id>/  personal, this machine
3  ./.orchestrator/adapters/platforms/<id>/                    project, committed
4  <plugin-root>/adapters/platforms/<id>/                      shipped with the plugin
```

**DEFAULT-PROPOSED:** `adapters.path: [1,2,3,4] as above`. Rationale: an owner who is debugging an
adapter needs to shadow the shipped one without touching the repository, and the four-level path is the
same shape his own marketplace already uses for config, so there is one ranking to remember rather than
two.

A directory at a level that fails validation (§3.3) is **not silently skipped**: discovery stops, names
the directory and the failing field, and preflight refuses. A silently skipped shadow copy is how the
previous generation ended with *"a fix that lives only in the installed copy"* (VERIFIED, FIELD-NOTES
§12.6).

### 3.3 Validation, before anything is executed

For every discovered adapter, before its `adapter` binary is run even once:

1. All four files exist. `adapter` and `normalize` are executable by the current user.
2. `manifest.json` parses, `contract_version` is an integer the core supports, `id` equals the directory
   name, and every axis key in §4.2 is present with a value from the closed vocabulary.
3. `probes.json` parses and every probe has `cmd` (array of strings, never a shell string), `timeout_s`
   (int) and — for a probe with an `extract` — a JSONPath per extracted field.
4. No file in the directory contains `pkill`, `killall`, or `docker compose down` without an explicit
   `-p`/`--project-name` argument on the same line.

> **Invariant BD-1 (blast radius).** Rule 4 is a **build-failing lint** in the plugin's own test harness
> and a **load-failing check** at runtime, not a convention. Rationale: `docker compose down -v` with no
> `COMPOSE_PROJECT_NAME` destroyed the owner's own stack (VERIFIED, FIELD-NOTES §11.5), and
> `pkill -f 'playwright test'` killed an unrelated lane (§11.8). `JUDGE-survival` scores this the
> strongest available form for F7's destroy half, precisely because a contributor cannot violate it and
> stay green.

### 3.4 Content hash and the resolved record

At the end of discovery the core writes `<run-root>/adapters.resolved.json`:

```jsonc
{ "claude-code": { "dir": "/Users/…/adapters/platforms/claude-code", "level": 4,
                   "sha256": "9f2c…",        // sha256 over the sorted (relpath, mode, content) triples
                   "contract_version": 1, "version_pin": "2.1.278" } }
```

`sha256` is what §12.3 uses to decide whether the live half of conformance must run again. It is
computed over file contents, not mtimes, so a `git checkout` that restores identical bytes does not
trigger a re-verify.

### 3.5 `probes.json` — probes as data

This is `JUDGE-fidelity` graft **G4**, and it exists because the owner spent two rows on exactly it:
*«для кожної платформи можна налаштовувати, як саме буде робитись відновлення… Можливо, там використання
якогось скіла»* [310], and *«людина це може налаштовувати, може написати свої власні [с]кіли»* [312]
(VERIFIED in `ANALYSIS-01` R1-10).

```jsonc
{
  "claude-status": {
    "kind": "identity",
    "cmd": ["claude", "--print", "/status"],
    "env_from": "account",              // account | provider | account+provider | none
    "extract": { "account": "$.oauthAccount.emailAddress",
                 "version": "$.version" },
    "cost": "zero-model",               // zero-model | small-model | unbounded
    "timeout_s": 10
  },
  "claude-roster": {
    "kind": "roster",
    "cmd": ["claude", "agents", "--json", "--all"],
    "env_from": "account",
    "rows_at": "$[*]",
    "id_field": "sessionId", "status_field": "status", "blocked_field": "waitingFor",
    "timeout_s": 10
  },
  "anthropic-oauth-usage": {
    "kind": "capacity",
    "cmd": ["curl","-sS","--max-time","10",
            "https://api.anthropic.com/api/oauth/usage",
            "-H","Authorization: Bearer {{auth}}",
            "-H","anthropic-beta: oauth-2025-04-20"],
    "env_from": "account",
    "buckets_enumerate": "$[?(@.utilization != null)]",   // §8.3 — enumerate, never name
    "bucket_pct_field": "utilization", "bucket_reset_field": "resets_at",
    "min_interval_s": 3600, "burst": 2, "timeout_s": 15
  }
}
```

Five probe kinds: `identity`, `roster`, `capacity`, `alive`, `posture`. A probe the owner writes himself
is legal at any of them — `{"kind":"alive","cmd":["claude","-p","/my-recovery-skill"],…}` — which is
`[312]` implemented rather than promised.

Rules:

1. `cmd` is an **array**, never a shell string. No adapter or probe is ever passed to a shell.
2. `{{auth}}`, `{{model}}`, `{{base_url}}`, `{{session_id}}`, `{{cwd}}` are the only substitutions. A
   `{{auth}}` substitution is written into the child's environment or argv from the resolved `auth_ref`
   and is **never** written to any log, event or file (SEC-1).
3. A probe's `cost` is declared. A probe declared `zero-model` that spawns a model session fails
   conformance (§12.2) — this is how *"a probe that quietly costs tokens on every tick"* is prevented.
4. `stdin` is closed on every probe, always (§5.2 invariant AD-3).

### 3.6 Calling convention

```
<adapter-dir>/adapter <op> --lane <path-to-lane.json> [--handle <handle-id>] [op args…]
```

- **fd 1** carries exactly one JSON object and nothing else.
- **fd 2** carries free-form logs. **The core never reads fd 2 for meaning.** GLM always writes
  `[claude-code:unrecognized_model]` to stderr; Cursor writes a 502-byte ANSI splash to *stdout*
  (VERIFIED, `ADAPTER-CONTRACT.md` §2.4.7). An adapter whose fd 1 is not pure JSON fails conformance.
- The environment the adapter is given is the lane's resolved environment (§5.16) plus `ORC_RUN_ROOT`,
  `ORC_LANE_ID`, `ORC_EPOCH`, and nothing else. It does not inherit the launching session's environment.
  Rationale: three detached scripts in the previous generation had to export their own `gh` account
  because `launchd` and `nohup` start with no environment (VERIFIED, FIELD-NOTES §12.4).

### 3.7 Exit codes — the adapter's own

Taken from `acpx`, because across **44 published versions its CHANGELOG contains no entry that changes an
exit code** (VERIFIED, `ADOPTION-VERDICT.md` §3) — the only stable exit contract found in the field.

| Code | Meaning | What the core does |
|---|---|---|
| `0` | ok | read fd 1 |
| `1` | agent / runtime error | retry per §5.4's per-op policy |
| `2` | usage error — the core called the adapter wrongly | **bug in the core**; refuse the run, never retry |
| `3` | timeout — the external wall clock fired | treat as `1`, but record `timeout: true` |
| `4` | no such session | the handle is gone; reconcile the lineage |
| `5` | **needs a human** | first-class outcome; raise `question.raised` (§5.10) |
| `64` | capability not supported by this adapter (declared, not a failure) | degrade per §6 |
| `65` | contract violation — the adapter caught itself about to lie | **hold the lane**, notify, never retry |
| `70` | environment error (binary missing, credential dead) | hold the lane, notify |
| `130` | interrupted | treat as `1` |

> **Invariant AD-1. Never branch on the underlying CLI's exit code.** VERIFIED failures: Aider
> `main.py:1133` returns 0 on auth failure, rate limit and success alike; `pi --mode json` exits 0 on
> provider failure; GLM exits 0 on quota exhaustion *with* `subtype:"success"`; MiMoCode's exit code is
> always 0. The adapter translates into the table above; the core sees only the table.

> **Invariant AD-2. Never trust HTTP 200 or a `success` string.** Gate GLM's quota poll on
> `.success == true`; gate Claude-family completion on
> `is_error == false && terminal_reason == "completed"` (VERIFIED, `ADAPTER-CONTRACT.md` §2.4.2).

### 3.8 `acpx` as a transport, not as the seam

`acpx@0.17.0`, pinned **exactly**, is the default transport where it supports the platform
(`"transport": "acpx"`). It retires the terminal séance in one move: a prompt is an argument, a timeout
is exit `3`, an interrupt is `130`, liveness is a process rather than a screen. `ADOPTION-VERDICT.md` §3
maps six FIELD-NOTES records onto it directly (VERIFIED).

Four rules ship with it, unchanged: pin exactly (**40 `Breaking` sections in 44 releases**); depend only
on subcommand names, exit codes and `--format json --json-strict`; treat exit `5` as a first-class
outcome; keep the queue, the stop verbs, the board write-back and the quota policy in our own code.

**The seam is above acpx, deliberately.** A platform acpx does not support declares `exec`, `rpc`, `http`
or `pty` and implements the same operations. The exit path if acpx breaks is *delete the dependency and
set `transport: exec`* — an afternoon, no other file changed. That is the test of whether a seam is real.

**`pty` means tmux.** **DEFAULT-PROPOSED:** `pty.backend: tmux`, `pty.host: iterm2-if-present`.
Rationale: AppleScript is where every recorded delivery failure lives, and the previous generation's own
code already refused Terminal.app as undrivable (VERIFIED, `harness-term.sh:163-181`); tmux runs inside
an iTerm2 window, so the owner's visible terminals still look like his terminals.

---

## 4. `capabilities()` and the manifest

### 4.1 Why this operation comes first

> The orchestrator plans the run against this map. **An adapter that reports `native` and then degrades
> at 03:00 is the single worst failure this contract exists to prevent** (`ADAPTER-CONTRACT.md` §2.0).

Two absolute rules:

- **`capabilities()` must be derivable with no network call and no model token.** It is a read of
  `manifest.json` plus, at most, a `--version` call the adapter already made in `preflight`.
- **Never report `native` for a capability whose only implementation is a regex over English prose.**
  This is checkable: §12.2 fails an adapter whose `compact` returns success without a `Proof`.

### 4.2 The ten axes

| Axis | Name | The owner requirement behind it |
|---|---|---|
| `A_launch` | headless and/or visible launch | R1-11 — per-platform interactive / headless / hybrid |
| `B_identity` | name, record and resume a session | R1-06.2, R1-10 — resumable *by hand* |
| `C_transcript` | read the session's record live | R1-09, R1-10 — judge progress; recover from transcripts |
| `D_context` | read fullness, trigger compaction, **prove** it | R1-08 — *«механізм, який гарантовано робить цю дію»* |
| `E_quota` | read remaining capacity and the reset | R1-06.1/2 — wait for the reset; soft/hard thresholds |
| `F_accounts` | several accounts per machine, per role | R1-07 — roles on different accounts, verified first |
| `G_send` | deliver an instruction into a live session | Д12, R1-11 — stop commands land |
| `G_answer` | answer the session's **own** question | R1-11 [324], bounded by [325]/[328] |
| `H_sandbox` | a floor under the red-line file | R1-02, R1-15 |
| `I_extend` | run an engine (GSD, skills, MCP, subagents) inside | R1-03 |

`G` is split into `G_send` and `G_answer` because they degrade separately **and worse**: a platform can
deliver an instruction and still be unable to answer the session's own question (`ADAPTER-CONTRACT.md`
§3-G, VERIFIED). Collapsing them hides the harder of the two failures.

Axis `J` from `ADAPTER-CONTRACT.md` (operational reality — installed, current, entitled) is deliberately
**not** an axis here: it is not a property of the adapter, it is a property of this machine today, so it
lives in `preflight` (§5.5) and in §11.

### 4.3 The five-value vocabulary

```
native | emulated | impossible | unknown | undocumented
```

This is `JUDGE-cost` graft **G11**, costed at *"three enum values and one comparison, under 15 lines"*,
and its shape is taken from GSD's own `host-integration.cjs` — the owner's own engine already speaks it
(VERIFIED, `C9-process-delivery-research.md` §3.1).

| Value | Meaning | Negotiation effect (§6.3) |
|---|---|---|
| `native` | one documented call or flag on the platform | passes |
| `emulated` | the adapter adds glue the platform does not provide; the glue is ours and is tested | passes, **and records its cost in `plan.json`** |
| `impossible` | no honest implementation exists | applies the requirement's `on_impossible` |
| `unknown` | not established; the manifest says so explicitly | **degrades closed** (treated as `impossible`) |
| `undocumented` | the platform has no declaration either way; a probe may settle it | run the probe if one exists, else closed |

Two rules, kept verbatim from the source:

- **An out-of-vocabulary value is not a capability verdict.** It validates (so a manifest from a newer
  contract version still loads) and it **never propagates into an effective axis**.
- **`undocumented` ≠ `impossible`.** A missing declaration and a declared absence are different facts,
  reported in different words. GSD's own review note is the argument: telling a user their runtime
  *"declares no executor-isolation primitive"* when the **resolver** failed *"is false"*.

**DEFAULT-PROPOSED:** `negotiate.on_unknown: impossible` — an undeclared axis degrades closed.
Rationale: this is the property that makes the lattice worth having. Adding a requirement row later
makes every existing manifest answer `unknown` for it, so **a new safety rule cannot silently pass on an
old adapter** (`JUDGE-survival` G9).

**DEFAULT-PROPOSED:** `negotiate.on_undocumented: probe_then_impossible` — run the axis's probe from
`probes.json` if one exists, otherwise closed. Rationale: it keeps the honest-words rule above while
still letting a probe settle the question, which is what `[310]`/`[312]` asked for.

### 4.4 `manifest.json`

```jsonc
{
  "contract_version": 1,
  "id": "claude-code",
  "binary": "claude",
  "version_pin": "2.1.278",
  "transport": "exec",
  "home_env": "CLAUDE_CONFIG_DIR",

  "capabilities": {
    "A_launch": "native", "B_identity": "native", "C_transcript": "native",
    "D_context": "native", "E_quota": "native",  "F_accounts": "native",
    "G_send":   "native", "G_answer": "emulated",
    "H_sandbox":"native", "I_extend": "native"
  },

  "quotaModel":   "Window",        // Window | Credit | None | Unknown       §8.1
  "idAssignment": "client",        // client | server | none                 §2
  "attachable":   true,            // bool  — a terminal the owner can type into
  "sandbox":      true,            // bool  — an OS-level confinement exists
  "transcript_durable": true,      // bool  — false ⇒ the adapter must tee    §7.5
  "compact_mints_new_id": false,   // bool  — Droid is true                   §5.11
  "answer_channel": "emulated",    // native | emulated | impossible

  "ops": { "launchAttached": "native", "costMeter": "emulated",
           "env_for": "native", "…": "…" },

  "provenance_map": { … },         // §7.4 — declared once, stamped by normalize
  "hazards": ["keychain-gui-dialog-on-first-use-per-account"],
  "autoupdate": { "env": { "DISABLE_AUTOUPDATER": "1" }, "config_edit_required": false }
}
```

`capabilities` is per **axis**; `ops` is per **operation**. They answer different questions: an axis is
what the owner's requirement needs, an operation is what the core may call. A lane can have
`D_context: native` and `ops.costMeter: impossible` at the same time, and neither tells you the other.

### 4.5 Worked example E2 — the manifest matrix, condensed

From `ADAPTER-CONTRACT.md` §1, this is what the fifteen manifests declare on the four non-negotiables
(VERIFIED there):

| Platform | `D_context` | `E_quota` | `F_accounts` | `G_send` | `G_answer` | Tier |
|---|---|---|---|---|---|---|
| Claude Code | native | native | native | native | emulated | **1** |
| Codex CLI | native | native | native | native | native | **1** |
| Droid | native | emulated | native | native | native | 1\* |
| Kimi Code | native | native | native | native (accepted-only) | native | 1\* |
| Copilot CLI | native | native | native | native | native | 1 (no entitlement) |
| GLM *(provider)* | driver's | native | native | driver's | driver's | 1 through the driver |
| DeepSeek *(API lane)* | driver's | native (Credit) | native | driver's | driver's | 1 |
| Qwen Code | native | **impossible** | native | native | native | 2 |
| MiMoCode | native | **impossible** | native | native | native | 2 |
| pi | native | **impossible** | native | native | native | 2 |
| OpenCode | emulated | **impossible** | emulated | native | native | 2 |
| Amp | **impossible** (trigger) | **impossible** | native | native | emulated | 2 |
| Gemini CLI | **impossible** (trigger) | emulated | native | **impossible** headless | native (ACP) | 2 |
| Cursor CLI | **impossible** (trigger) | **impossible** | emulated | native | native | unusable today |
| Aider | emulated | **impossible** | native | emulated | emulated | 2 with tmux / 3 without |

Note the shape this table makes visible and which drives §6: **`E_quota` is the axis that splits the
field.** Seven of fifteen cannot report remaining capacity at all.

---

## 5. The operations

### 5.1 The set, and which are required

Seventeen operations. **Fourteen required, two optional, one conditional** — the resolution of the
counting error recorded in §0.4.

| # | Op | Group | Required for tier-1 | Timeout (DEFAULT-PROPOSED) |
|---|---|---|---|---|
| 1 | `capabilities` | negotiation | **required** | `2s` |
| 2 | `preflight` | lifecycle | **required** | `10s` |
| 3 | `launchHeadless` | lifecycle | **required** | `30s` to the handle |
| 4 | `launchAttached` | lifecycle | optional | `30s` |
| 5 | `resume` | lifecycle | **required** | `30s` |
| 6 | `stop` | lifecycle | **required** | `20s` (hard) / `requested`+deadline (soft) |
| 7 | `status` | observation | **required** | `2s` |
| 8 | `transcript` | observation | **required** | `10s` |
| 9 | `readContext` | observation | **required** | `5s` |
| 10 | `costMeter` | observation | optional | `5s` |
| 11 | `compact` | non-negotiable | **required** | `600s` |
| 12 | `readCapacity` | non-negotiable | **required** | `15s` |
| 13 | `detectLimitHit` | non-negotiable | **required** | `1s`, pure, no network |
| 14 | `selectAccount` | non-negotiable | **required** | `2s` |
| 15 | `send` | non-negotiable | **required** | `15s` |
| 16 | `answer` | non-negotiable | **required** | `15s` |
| 17 | `env_for` | provider split | **conditional** — required iff any lane's provider differs from `Platform.default_provider` | `1s` |

Every timeout is an **external wall clock imposed by the core**, not a flag passed to the platform.
Firing it produces adapter exit `3`. Rationale: `opencode run --attach --session --dir` hangs with zero
bytes on stdout, stderr **and** the server log, reproduced twice (VERIFIED,
`ADAPTER-CONTRACT.md` §2.4.4). Every timeout above is overridable per platform in
`manifest.json.timeouts.<op>`; a manifest timeout may **raise** a default but the core caps the total at
`adapter.max_timeout_s` (**DEFAULT-PROPOSED: `900`**) so no single call can hold a tick for a quarter of
an hour.

### 5.2 The nine standing invariants

`ADAPTER-CONTRACT.md` §2.4 states ten; AD-1 is already §3.7. These nine are **conformance tests**
(§12.2), not prose. Each names the verified failure it exists for.

| # | Invariant | Verified failure behind it |
|---|---|---|
| AD-2 | Never trust HTTP 200 or a `success` string | GLM exits 0 on quota exhaustion *with* `subtype:"success"` |
| AD-3 | Always close or own stdin | Codex hangs all night without `< /dev/null`; MiMoCode hangs forever; Aider needs a pty *instead* |
| AD-4 | Always impose an external wall-clock timeout | `opencode run` hung with zero bytes on three streams, twice |
| AD-5 | Always pin the version and suppress auto-update | Amp: five releases in fifteen hours; Copilot: 835 versions in twelve months |
| AD-6 | Always pin the model explicitly | inheriting `model = "gpt-6-astra"` produced a 100%-failing run |
| AD-7 | Keep stdout and stderr separate | GLM writes to stderr always; Cursor writes a 502-byte ANSI splash to **stdout** |
| AD-8 | Union the roster across accounts | a single-account roster read showed half the fleet |
| AD-9 | Re-attach permission and question handlers on **every** resume, not only on create | a resumed session with no answerer is a session that blocks silently |
| AD-10 | Assert teardown by process, not by the command's word | `cursor-agent worker kill` reports success and leaves the process at 100% CPU |

AD-10 is the FIELD-NOTES *"reports success and does nothing"* class alive in a second platform, which is
why it is an invariant rather than a Cursor note.

### 5.3 Shared shapes

```jsonc
// Handle — returned by launchHeadless / launchAttached / resume; persisted at
// <run-root>/lanes/<lane-id>/handles/<handle>.json
{ "handle": "h-7c1f0a9e-004",
  "lane": "L2", "epoch": 7,
  "session_id": "orc-20260919-210411-7c1f0a9e-1",   // or the server-minted id
  "id_source": "client",                            // client | server | none
  "pid": 48213, "pgid": 48213,
  "started_at": "2026-09-19T21:04:11.882Z",
  "start_ticks": "Fri Sep 19 21:04:11 2026",        // `ps -o lstart=`, for pid-reuse defence
  "argv_sha256": "…",
  "cwd": "/Users/…/worktrees/T-412",
  "transcript_ref": { "kind": "file", "path": "…/.claude/projects/…/orc-…jsonl" },
  "attached": false, "pty": null }

// Ack — returned by send
{ "status": "accepted" | "delivered" | "processed" | "refused" | "stranded",
  "message_id": "…"|null, "receipt": { … }|null, "stranded_text": "…"|null }

// Proof — returned by compact
{ "kind": "typed_event" | "transcript_entry" | "measured_drop",
  "before": { "used": 812004, "at": "…" }, "after": { "used": 190221, "at": "…" },
  "evidence_ref": { "kind": "event", "seq": 4471 },
  "successor_session_id": null }

// TeardownReport — returned by stop
{ "mode": "soft"|"hard", "state": "requested"|"stopped",
  "asserted_by": "process_absent"|"roster_absent"|"none",
  "orphans": [ { "pid": 48310, "argv_sha256": "…", "reason": "child of the lane, still alive" } ],
  "stranded_text": "…"|null }
```

### 5.4 Retry policy, stated once

Per-op, applied by the core; an adapter never retries internally (an internal retry hides a timeout).

| Class | Ops | Policy |
|---|---|---|
| **read-only, idempotent** | `capabilities`, `preflight`, `status`, `transcript`, `readContext`, `costMeter`, `detectLimitHit`, `env_for` | up to 2 retries, 2s then 6s, jittered |
| **mutating, idempotent by key** | `launchHeadless` (by `session_id`), `resume`, `send` (by `message_id`), `answer` (by `request_id`), `stop` | **1** retry, and only after re-reading state to confirm the first attempt did not land |
| **mutating, not safely replayable** | `compact`, `selectAccount` | **0** retries. On any non-zero exit, hold the lane and reconcile from the transcript |
| **rate-limited external** | `readCapacity` | 0 retries; the meter's own backoff applies (§8.5) |

> **Invariant AD-11.** A mutating op is replayed only when the core can name the key the platform
> deduplicates on. Where it cannot, the class is `unsafe`: **escalate to the questions channel and hold
> the lane, never replay** (`JUDGE-survival` G10). Rationale: an orphaned `compact` replayed after a
> crash can compact twice and destroy the working memory the first one preserved.

### 5.5 `preflight(account) → PreflightReport` — REQUIRED

```jsonc
{ "ready": true,
  "version": "2.1.278",
  "account_id": "sasha@example.com",     // what the PLATFORM says, not what we set
  "models": ["claude-opus-5","claude-haiku-4"],
  "posture": { … },                       // §11.4
  "capabilities_observed": { "E_quota": "native" },   // may only DOWNGRADE the manifest
  "warnings": [ "keychain entry present but no token returned for this profile" ] }
```

**Contract.** Read-only. **Zero model tokens.** ≤10 s. Must prove **which account this spawn would
use**, not merely that a binary exists. Must fail loudly on a stale or dead credential.
`capabilities_observed` may only downgrade (§6.3): an adapter cannot talk its way up at runtime.

**Failure modes.** Binary absent → `70`. Credential present but unusable → `70` with the warning text
(a profile can be listed in the keychain while `security find-generic-password` returns no
token for it — VERIFIED, `C4-capacity-research.md` §3.1). Version mismatch → §10. Keychain GUI dialog →
**this is why the 10 s timeout exists**: on macOS an account that has never been granted access raises a
dialog nobody sees at 03:00 (VERIFIED, `00-field-scan.md` §4), and a hung `preflight` at 22:00 is the
only moment the owner can be told.

**DEFAULT-PROPOSED:** `preflight.keychain_pregrant_required: true` for any account whose
`credential_kind` is `config_dir` or `keychain` on macOS — the account must have been run by hand once
and granted "Always Allow", asserted by a successful zero-token `identity` probe, or the lane is denied.
Rationale: an unattended night that blocks on an invisible dialog is indistinguishable from a hang, and
`ADAPTER-CONTRACT.md` §7 question 10 puts exactly this to the owner.

### 5.6 `launchHeadless(ticket, lane, session_id?) → Handle` — REQUIRED

**Contract.** Non-interactive, structured output, **stdin closed or held by the adapter — never
inherited** (AD-3). Idempotent on `session_id` where `idAssignment == "client"`. The op returns the
handle within 30 s; the *session's* own wall clock is `lane.max_seconds` (**DEFAULT-PROPOSED: `3600`**,
rationale: FIELD-NOTES §9.5's per-phase spawn-to-close figures sit well inside an hour, and a lane that
has not produced a terminal event in an hour is a defect worth a human's attention rather than a long
tail worth waiting out).

**Ordering, which is an invariant not a preference.**

1. Write the ticket→session row to `sessions.jsonl` **first** when the id is client-named.
2. Launch.
3. On the first durable event, write the row when the id is server-minted.
4. Between 2 and 3, the task is `unrecoverable_by_id` (ID-2) and recovery is re-dispatch.

`sessions.jsonl` is a **lineage**, one row per session, many rows per ticket:

```jsonl
{"ticket":"T-412","seq":1,"session":"orc-20260919-210411-7c1f0a9e-1","lane":"L2","reason":"initial","at":"…"}
{"ticket":"T-412","seq":2,"session":"orc-20260919-210411-7c1f0a9e-2","lane":"L2","reason":"reseed","at":"…","predecessor":1}
```

**Failure modes.** Launch returns but no process exists → `1`, and the core does **not** record a
session. A platform that forks instead of resuming (pi, from a drifted cwd) is caught here by comparing
the returned `session_id` to the requested one; a mismatch is exit `65`.

### 5.7 `launchAttached(ticket, lane) → Handle` — optional

**Contract.** A terminal the owner can type into. May be `impossible` (Amp, DeepSeek `dsh` have no
attachable local pane; Gemini CLI's ACP *replaces* the TUI, so supervision and takeover are mutually
exclusive per process — VERIFIED, `ADAPTER-CONTRACT.md` §3-A).

**Degradation:** takeover becomes a **handoff** — `stop` → `launchAttached` → `resume` — which costs one
restart and **must be visible in the run log, never silent**. Owner requirement that stops holding:
**R1-11's hybrid mode** [324].

### 5.8 `resume(session_ref) → Handle` — REQUIRED

**Contract.** Resumes **exactly**, or declares itself lossy in `capabilities()`. Idempotent: resuming a
live session returns the live handle, **never a fork**.

**Failure modes.** Gemini CLI deletes a session with no completed model turn, making an early failure
unresumable — there is no recovery point at all (VERIFIED). Aider's resume keeps 5 turns and drops 48
tool lines, so on Aider "resume" means "re-run with a handoff file" and the manifest must say
`B_identity: emulated`.

### 5.9 `stop(handle, mode) → TeardownReport` — REQUIRED

`mode ∈ soft | hard`. `custom` is **not** an adapter operation: it is a core-side verb that reads the
owner's own text rule and resolves to `soft` or `hard` (Д12 [524]); an adapter never interprets prose.

| Mode | Contract |
|---|---|
| `soft` | at the next **step boundary**, where "step" is the user's definition (R1-08 [209], Д12). Returns `state: "requested"` with a `deadline`. |
| `hard` | now. Returns only after asserting the process is gone **by process, not by the command's word** (AD-10). |

**DEFAULT-PROPOSED:** `stop.soft_deadline_s: 900`, then escalate to `hard` and record the escalation.
Rationale: a soft stop that never lands is indistinguishable from no stop; fifteen minutes is longer
than every per-phase timing in FIELD-NOTES §9.5 and short enough that a night is not lost to it.

> **Invariant AD-12.** `stop` **must stop only what this adapter started**, identified by the handle's
> `(pid, pgid, start_ticks, argv_sha256)` quadruple written into the ledger at creation. Never by
> pattern, never by name, never by "everything on this platform" (R1-16, Д3 [430]).

**Stranded text.** `stop` must return any queued or unsubmitted text as `stranded_text` so the core can
hand it back. Only `pi`'s `clear_queue` does this natively (VERIFIED). Rationale: five instructions were
never delivered in the 34-hour run, **two of them the owner's own** — `push master` and `carry on with
the queue` — sitting unsubmitted while the engine log recorded them as nudged (VERIFIED, FIELD-NOTES
§1.3, §11.2).

### 5.10 `status`, `send`, `answer`

**`status(handle) → State` — REQUIRED, ≤2 s, must never block.**

```
working | waitingOnHuman | waitingOnTool | finished | failed | dead
```

> **`waitingOnHuman` is a distinct state from `working`.** Conflating them is how an overnight run dies
> quietly (VERIFIED, `qwen-code-spike.md` via `ADAPTER-CONTRACT.md` §2.2).

`status` is a cheap observation, **not** a liveness verdict. A liveness verdict is the core's, computed
from the process, the event file and the roster together; §0 of `ARCH-adapters` and FIELD-NOTES §3.1
agree on why: a lane that ran `echo idle` **3,466 of 3,626 Bash calls**, adding 445k tokens, reported
`working` truthfully throughout (VERIFIED).

**`send(handle, text, mode) → Ack` — REQUIRED.** `mode ∈ steer | queue`.

> **`Ack` is a state machine, not a boolean: `accepted` ≠ `delivered` ≠ `processed`, and `accepted` must
> never be reported as `delivered`.** Kimi's 200 means *accepted*, never *ran* (VERIFIED).

Idempotent on a caller-supplied `message_id` where the platform allows one. Must expose stranded text.
**Where the platform gives no receipt at all**, the manifest declares `G_send: emulated` and §6.2 records
what that costs: the only legal action against that lane becomes `stop`.

**`answer(handle, request_id, decision) → void` — REQUIRED.**

**Contract.** Answers the session's *own* question or permission prompt over a **correlated** channel.
Must echo an **offered option id**, never free text. Must log **every declined question** — a silent
decline is the documented killer on Droid (VERIFIED).

**Authority.** R1-11 [324]: *«якщо він раптом використовує ask user question, то оркестратор може
відповідати на ці питання, і це повністю і повністю окей»*, bounded by *«в межах налаштованих
повноважень»* [325], which the owner **ratified** at [328] (VERIFIED — see §0.3, correcting
`ARCH-adapters` §9.4).

**DEFAULT-PROPOSED:** `questions.authority: refuse-and-escalate` for any question whose offered options
include an **irreversible external effect** (a push to a shared ref, a delete, a payment, a message to a
third party). Rationale: the bound is his own ratified qualifier, and the failure it prevents is an
autonomous run acting irreversibly on a guess at 03:00.

**DEFAULT-PROPOSED:** `questions.native_tool: disallow-headless` — where the platform cannot be answered
programmatically in the mode we are running (Claude Code `--bg`, DeepSeek SDK lane, Gemini headless), the
core injects its own `ask_supervisor` tool and **disallows the platform's native ask**. Rationale: the
alternative documented in the field is *prevent the question* via a permissive allow-list, which
directly weakens R1-02; keeping the question askable and answerable preserves [324] instead of trading
it away.

### 5.11 `compact(handle, opts) → Proof | "unsupported"` — REQUIRED

```jsonc
// opts
{ "instruction": null,            // string|null — platform-native compaction instruction
  "post_prompt": "<text>|null" }  // §5.11.3 — HIS key, not the plugin's behaviour
```

**5.11.1 The Proof rule.** **`Proof` is mandatory.** A typed event, a durable transcript entry, or a
**measured** drop in used tokens with provenance. **Returning success without proof is forbidden** and is
exit `65`. This is the FIELD-NOTES *"reports success and does nothing"* class made mechanically
impossible to declare, and §12.2 tests it.

**5.11.2 Successor ids.** If the platform mints a **successor session id** (Droid does, VERIFIED), the
adapter remaps ticket→session **atomically before returning** and reports
`successor_session_id`. Idempotent: a second call inside one turn is a no-op, **not** a second
compaction.

**5.11.3 `post_prompt` is the owner's key.** [204]: *«Людина це налаштовує, і обирає, чи відправляється
якийсь промпт одразу після компакту, чи ні»* (VERIFIED). `JUDGE-fidelity` §5.3 found that **all four
designs** turned this into plugin behaviour or dropped it. It is restored here as a key.
**DEFAULT-PROPOSED:** `context.post_compact_prompt: "<re-inject the red-line file>"`, `null` disables.
Rationale: the evidence supports re-injection as the right default (OpenClaw's
`post-compaction-context.ts` re-reads the prohibitions file after every compaction), but the *choice* is
his, and shipping it as behaviour rather than as his key is the thing to fix.

**5.11.4 The ladder when `compact` is `impossible`.** On **Amp, Gemini CLI, Cursor and DeepSeek `dsh`
there is no external compaction trigger at all** (VERIFIED). The ladder, in order:

1. External trigger + typed proof (Codex, Droid, Kimi, Qwen, MiMoCode, pi, Copilot, Claude Code piped).
2. Trigger by injecting `/compact` as a user message; proof from the transcript.
3. **Pre-commit at launch** — a threshold set in the environment *before* the run and unchangeable
   during it (Claude Code `--autocompact`, Gemini `model.compressionThreshold`, `dsh` `thresholdRatio`).
4. **close-and-reseed** — summarise, open a new session with the summary, append to the lineage.

Rung 4 is **built once, centrally, in the core** and is not an adapter's job: it needs only
`launchHeadless` + `transcript`, which every tier-2 platform has. Rung 3 breaks the cross-cutting rule
that *a change made during a run must be picked up* (Д7, Д12), and §6.2 records that.

**Owner requirement that stops holding:** R1-08 in its strongest form —
*«повинен бути механізм, який гарантовано робить цю дію»*. On rungs 3 and 4 the **outcome** guarantee
survives and the **action** guarantee does not, and the cost of rung 4 is that ticket→session becomes
one-to-many (§5.6) and a re-seed pays for the session's working memory a second time.

**DEFAULT-PROPOSED:** `context.mode: soft` (compact at the step boundary), `context.on_terminal_state:
fresh-session`, `context.verify_timeout_s: 600`. Rationale: hard mode is unavailable on four of fifteen
platforms, so defaulting to it would make the default untrue for a quarter of the field; and a
compaction believed rather than proved is the failure this whole operation exists to prevent.

### 5.12 `readContext(handle) → ContextReading | "unknown"` — REQUIRED

```jsonc
{ "used": 118442, "window": 272000, "pct": 43.5,
  "basis": "raw",                 // raw | usable_after_reserve | statusline     §5.12.2
  "is_estimated": false,
  "prov": { "text": "verbatim", "value": "provider_measured" } }
```

**Contract.** Must carry `is_estimated`. **`missing ≠ zero`.** Zero model tokens. An adapter that cannot
read context returns the literal string `"unknown"` and the core treats the axis as `unknown` for that
tick — it never substitutes a number.

**5.12.1 The refill-rate rule.** The core computes `Δpct/hour` across readings and treats a rate above
`context.refill_rate_alarm` as a **defect predicate, not a compaction predicate**.
**DEFAULT-PROPOSED:** `context.refill_rate_alarm: 15 pct/hour`. Rationale, quoted from the evidence: the
445k-token `echo idle` lane *"would have been papered over by compaction; it stopped within one minute
of being told to end its turn"* (VERIFIED, FIELD-NOTES §3.1). `JUDGE-survival` calls this row *"the
sharpest separator in the whole judgment"* — two of the four designs are blind to it. Compacting the
consequence hides the defect; waking someone to end the turn fixes it, and is roughly a hundred times
cheaper.

**5.12.2 `basis` is required, never inferred.** The owner sets a percentage [204]; his status line has
shown him one scale all year and the raw window is a different one, a gap measured at ~13 points
(`C5-A2`). **DEFAULT-PROPOSED:** `context.basis: raw`, and the `orchestrator:config` verb prints **both**
numbers for a live session at the moment he sets the threshold. Rationale (`JUDGE-fidelity` G10): the
difference between a naming convention and an informed setting.

**DEFAULT-PROPOSED:** `context.percent` per role — `executor: 75`, `ticket-watcher: 85`,
`orchestrator: 66`, all on the **raw** scale. Rationale: [204] gives the owner per-role thresholds
explicitly (*«я для кожного з них можу вказати, який буде поріг компакту»*); the values are proposals,
lower for the orchestrator because it is the one session whose death costs the run.

### 5.13 `transcript(handle, cursor) → { events[], cursor' }` — REQUIRED

**Contract.** Append-only, resumable from `cursor` **across a process restart**. Cursors are opaque and
may be sparse. Must work for a session the adapter did **not** spawn, or declare `C_transcript:
emulated`.

**Where the transcript lives only on the pipe** (Amp, `dsh`), the adapter **tees it to disk under the run
directory** and declares `transcript_durable: false` + `C_transcript: emulated`. Rationale: otherwise a
dead supervisor destroys the evidence, colliding head-on with R1-10's requirement that the
orchestrator's own death be survivable (VERIFIED, `ADAPTER-CONTRACT.md` §3-C).

### 5.14 `readCapacity(account) → Capacity` — REQUIRED

Full treatment in §8. The contract here is the three rules an adapter may not break:

1. **Return the sum type, never a scalar.** Exit `65` otherwise.
2. **A 200 the adapter cannot parse raises `Unreadable{schema_unknown}`, never zero.** Z.ai's
   `TOKENS_LIMIT` → `CREDIT_LIMIT` rename rendered **0% used**, which reads as *plenty of room*
   (VERIFIED, `C4-capacity-research.md` §3.3).
3. **Never inferred from an exit code** (AD-1), and never called per session — the core's meter owns all
   calls (§8.5).

### 5.15 `detectLimitHit(event) → LimitHit | null` — REQUIRED

```jsonc
{ "kind": "window" | "credit" | "rate", "resets_at": "…"|null, "source_seq": 4471 }
```

**Contract.** A **pure function over one normalised event**. No network, no state, ≤1 s. Required even
where `readCapacity` is native, because **prediction and reaction fail differently**.

> **Invariant AD-13. Never detect a limit by matching text on a screen.** Two independent multi-hour
> false-positive loops came from exactly that: an 85-minute loop where the watch matched what looked
> like a usage-cap banner **inside the orchestrator's own wrapped prose**, ended only by an external
> `SIGTERM`; and a 45-minute banner loop on a healthy orchestrator, re-issuing resume kicks about every
> 66 seconds (VERIFIED, FIELD-NOTES §11.6). `C4-capacity-research.md` §3.1 states the conclusion
> plainly: *"Screen-scraping for a limit banner should be struck from the rebuild."*

> **Invariant AD-14. Never log the trigger phrases.** A governor that prints `/compact` or `rate-limit`
> into its own log gets matched by its own detector. Every event payload that must carry such a string
> carries it base64-encoded under `payload.raw_b64`.

Legal sources: a typed field (`rate_limit_reached_type` in Codex's `token_count` event, VERIFIED), a
documented error code (GLM's 1316/1317 land in the transcript, VERIFIED), an HTTP status from a call the
adapter itself made. Nothing else.

### 5.16 `selectAccount(lane) → SpawnEnv` — REQUIRED

```jsonc
{ "env": { "CLAUDE_CONFIG_DIR": "/Users/…/profiles/<profile-A>" },
  "argv_extra": [], "verify_after_launch": "claude-status" }
```

**Contract.** Returns **environment only**. **Never mutates the owner's config, keychain or home**
(SEC-2). The caller verifies the account **after** launch from the platform's own report — never from
the variable it set. R1-07 [199] demands the switch be *proven working before a run starts*, and the
proof is the platform's own words: `initialize.account.email`, `auth_changed`, `apiKeySource == "env"`,
`presentVar`.

**Changing a running session's account is `impossible` on all fifteen platforms** (VERIFIED). The adapter
must expose that as `handoff`, not hide it. So R1-07's **hard** account change — *"applies now, stops
current work"* [195] — means, physically: stop the session, relaunch on the other account, **re-seed the
context**, i.e. pay for it a second time. §15 prices it; §17 asks him to confirm the price.

**Two account facts that must be asserted, not assumed** (both VERIFIED,
`C4-capacity-research.md` §3.1):

- `~/.claude.json` and `~/.claude/.claude.json` are **different files**, and the former is what Claude
  Code reads when `CLAUDE_CONFIG_DIR` is unset — which is exactly the detached-daemon case. The adapter
  pins `CLAUDE_CONFIG_DIR` in **every** spawn.
- A listed keychain profile is not necessarily a usable one: a profile can be present and
  return no token.

### 5.17 `env_for(provider) → SpawnEnv` — CONDITIONAL

**Contract.** Renders `Provider.env` with `{{base_url}}`, `{{auth}}`, `{{model}}`,
`{{small_model}}`, `{{context_window}}` and returns environment only. Required **iff** any lane's
provider differs from its platform's `default_provider`.

This one method is what makes GLM, DeepSeek's API lane, Kimi-as-endpoint and MiMo-as-model cost **zero
adapters** (VERIFIED as the research's own conclusion, `ADAPTER-CONTRACT.md` §5.3).

**Worked example.** GLM behind the Claude Code driver:

```
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
ANTHROPIC_AUTH_TOKEN=<from keychain service "zai">
ANTHROPIC_MODEL=glm-5.3
ANTHROPIC_SMALL_FAST_MODEL=glm-5.3-flash
CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
```

The last line is not optional: **GLM will quietly compact at 200 K if
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` disagrees with the model id** (VERIFIED,
`ADAPTER-CONTRACT.md` §6.6). §1.4 rule 2 makes preflight assert `context_window` against `model`, and
`env_for` is where the assertion is actually paid.

> **Invariant AD-15.** `env_for` and `selectAccount` are composed in that order —
> provider env first, account env second — so an account may override a provider variable and never the
> reverse. Rationale: the credential is the account's property; the endpoint is the provider's.

---

## 6. Degradation: which owner requirement stops holding, and where it is written down

### 6.1 `requirements.json` — the one file in the core that names owner items and never names platforms

Path: `<plugin-root>/core/requirements.json`. It is **data**, not code, so a new requirement is a row.

```jsonc
{ "contract_version": 1,
  "requirements": [

  {"id":"R1-08.hard-compact","axis":"D_context","needed_when":"context.mode == 'hard'",
   "on_impossible":"degrade","degrade_to":"close-and-reseed","owner_item":"R1-08",
   "stops_holding":"the ACTION guarantee «механізм, який гарантовано робить цю дію»; the OUTCOME guarantee survives",
   "ask_uk":"На цій платформі компакт ззовні запустити неможливо. Дозволяєш замість нього закривати сесію і відкривати нову з підсумком?"},

  {"id":"R1-08.trigger-during-run","axis":"D_context","needed_when":"always",
   "on_impossible":"degrade","degrade_to":"prelaunch-threshold","owner_item":"R1-08",
   "stops_holding":"the cross-cutting rule that a change made DURING a run is picked up (Д7, Д12)"},

  {"id":"R1-06.wait-for-reset","axis":"E_quota","needed_when":"capacity.on_exhausted == 'wait'",
   "on_impossible":"deny-role","applies_to_roles":["*needs_predictable_capacity"],"owner_item":"R1-06.1",
   "stops_holding":"«дочекатись рестарту ліміту і продовжити» — there is nothing to wait for"},

  {"id":"R1-06.threshold-pct","axis":"E_quota","needed_when":"provider.capacity_model == 'Credit'",
   "on_impossible":"degrade","degrade_to":"money-ceiling","owner_item":"R1-06.2",
   "stops_holding":"«при скількох відсотках» — a percentage does not exist on a credit model"},

  {"id":"R1-07.role-accounts","axis":"F_accounts","needed_when":"always",
   "on_impossible":"refuse-run","owner_item":"R1-07",
   "stops_holding":"«ролі можуть сидіти на різних акаунтах» — the whole role split"},

  {"id":"R1-07.hard-switch","axis":"F_accounts","needed_when":"account_change.type == 'hard'",
   "on_impossible":"degrade","degrade_to":"stop-relaunch-reseed","owner_item":"R1-07",
   "stops_holding":"an in-place switch; the context is paid for twice"},

  {"id":"R1-11.takeover","axis":"A_launch","needed_when":"runtime.visibility == 'visible'",
   "on_impossible":"degrade","degrade_to":"handoff","owner_item":"R1-11",
   "stops_holding":"the hybrid mode — supervision and takeover become mutually exclusive"},

  {"id":"D12.stop-hard-midturn","axis":"G_send","needed_when":"always",
   "on_impossible":"degrade","degrade_to":"kill","owner_item":"Д12",
   "stops_holding":"stop-hard as an instruction; it becomes killing the process"},

  {"id":"D12.stop-soft-midturn","axis":"G_send","needed_when":"always",
   "on_impossible":"degrade","degrade_to":"task-boundary","owner_item":"Д12",
   "stops_holding":"stop-soft lands at the next TASK boundary, not the next step"},

  {"id":"R1-11.answer-question","axis":"G_answer","needed_when":"role.authority.may_answer",
   "on_impossible":"degrade","degrade_to":"inject-ask-supervisor","owner_item":"R1-11",
   "stops_holding":"«оркестратор може відповідати на ці питання» via the platform's own channel",
   "second_degrade":"prevent-the-question",
   "second_degrade_costs":"R1-02 — what may be delegated autonomously is narrowed"},

  {"id":"R1-15.floor","axis":"H_sandbox","needed_when":"always",
   "on_impossible":"degrade","degrade_to":"worktree+denylist","owner_item":"R1-15",
   "stops_holding":"nothing beneath the red-line text file if the model ignores it",
   "ask_uk":"Kimi і pi не мають пісочниці взагалі. Додаємо для них обов'язковий worktree і жорсткий deny-лист, чи такі платформи не отримують прав на запис?"},

  {"id":"R1-03.engine-in-session","axis":"I_extend","needed_when":"engine.needs_subagents",
   "on_impossible":"deny-role","applies_to_roles":["executor"],"owner_item":"R1-03",
   "stops_holding":"running the chosen process INSIDE the session; the lane becomes a leaf executor"},

  {"id":"R1-09.judge-progress","axis":"C_transcript","needed_when":"always",
   "on_impossible":"deny-role","applies_to_roles":["executor","validator"],"owner_item":"R1-09",
   "stops_holding":"«він дивиться, перевіряє ті сесії, які він запустив, які в них прогрес»"},

  {"id":"R1-10.resume-by-hand","axis":"B_identity","needed_when":"always",
   "on_impossible":"degrade","degrade_to":"redispatch","owner_item":"R1-06.2",
   "stops_holding":"«щоби було відновити процес і продовжити, навіть руками»"}
]}
```

Every row carries `owner_item` and, more importantly, **`stops_holding` in words**. That field is the
whole point: at 04:00 the question is not *"did the channel work"* but *"is the guaranteed-compaction
thing he asked for still holding on lane L4 tonight, and if not what did it become"* — answerable from a
file, with no model in the path (`JUDGE-survival` G9).

### 6.2 `on_impossible` — exactly four values

| Value | Effect | When it is right |
|---|---|---|
| `deny-role` | the lane keeps existing but may not hold that role | the capability is required *for a role* and another lane has it |
| `degrade` | take `degrade_to` and **record the weakened requirement in `plan.json`** | there is an honest, platform-independent fallback |
| `ask` | pause preflight and put `ask_uk` to the owner | the trade is his to make |
| `refuse-run` | do not start; print lane, axis, owner item | no fallback and no role split saves it |

### 6.3 The negotiation algorithm, in numbered steps

Runs inside preflight, deterministically, with **zero model tokens**.

1. For each configured lane, load `manifest.json` → `caps_declared`.
2. Run `preflight(account)` → `caps_observed`. Compute
   `caps_effective = downgrade_only(caps_declared, caps_observed)`, where `downgrade_only` takes the
   **weaker** of the two on the ordering `native > emulated > undocumented > unknown > impossible`. An
   adapter can never talk its way **up** at runtime.
3. Apply `negotiate.on_undocumented`: for each axis at `undocumented`, if `probes.json` has a probe of
   that axis's kind, run it; a successful probe raises the axis to `emulated`, a failed or absent probe
   lowers it to `impossible`.
4. Apply `negotiate.on_unknown`: every axis still at `unknown` becomes `impossible`.
5. For each requirement row whose `needed_when` evaluates true against the **resolved config** (not
   against defaults), read `caps_effective[row.axis]`:
   - `native` → pass.
   - `emulated` → pass, and append to `plan.emulations[]` with the glue's name and cost.
   - `impossible` → apply `row.on_impossible`.
6. `deny-role`: remove the role from this lane; if no remaining lane can hold a role that has
   `max_concurrent ≥ 1` and is required by the run, escalate to `refuse-run` naming the role.
7. `degrade`: append to `plan.weakened[]` — `{owner_item, lane, axis, was, now, consequence}` — and
   configure the fallback.
8. `ask`: if `negotiate.interactive` resolves to `ask` **and** a TTY is present, put `ask_uk` to the
   owner and record his answer with its row id; otherwise apply `refuse-run`.
9. `refuse-run`: stop. Print one line per refusal: lane, axis, owner item, and the sentence from
   `stops_holding`. Exit non-zero. Write nothing else.
10. Write `plan.json` (§6.6), `fsync`, and never rewrite it for the life of the run.

`needed_when` is evaluated by a **restricted expression evaluator** — comparisons, `&&`, `||`, `!`, and
dotted config paths only. No shell, no `eval`, no arbitrary code. A `needed_when` that fails to parse is
a load-time error, not a runtime skip.

### 6.4 The evaluation order is fixed, and it matters

Steps 3 and 4 run **before** step 5, so a requirement never sees `undocumented` or `unknown`. This
single ordering is what makes the lattice's promised property true: **adding a requirement row makes
every existing manifest answer `unknown` for it, and step 4 closes that.** A new safety rule cannot
silently pass on an adapter written before it.

### 6.5 The two negotiation defaults

**DEFAULT-PROPOSED:** `negotiate.on_unknown: impossible`. Rationale: §6.4.

**DEFAULT-PROPOSED:** `negotiate.interactive: ask` when a TTY is present, `refuse-run` when not.
Rationale: an unattended start must not silently choose the weaker half of a trade the owner never saw.
The tension — that this makes a run refuse to start for reasons he never asked about — is recorded in
§16.2 rather than argued away, and `JUDGE-cost`'s objection to it is real.

### 6.6 `plan.json` — the frozen result

Written once, at the end of preflight, to `<run-root>/plan.json`. Immutable. Anything that would change
it is a `frozen`-class config key (§14).

```jsonc
{ "schema": 1, "run": "20260919-210411", "created_at": "2026-09-19T21:04:57Z",
  "contract_version": 1,

  "lanes": [
    { "id":"L1","role":"orchestrator","platform":"claude-code","provider":"anthropic-max",
      "account":"cc-<profile-A>","version":"2.1.278","adapter_sha256":"9f2c…",
      "capacity_model":"Window","concurrency":{"scope":"none","max":null},
      "emulations":[], "denied_roles":[], "verified_at":"2026-09-19T21:04:19Z" },

    { "id":"L2","role":"executor","platform":"claude-code","provider":"glm-coding-pro",
      "account":"zai-personal","version":"2.1.278","capacity_model":"Window",
      "concurrency":{"scope":"provider_account","max":2,"basis":"contract","on_violation":"ban_risk"},
      "emulations":["G_answer: PreToolUse hook; the host control channel did not route"],
      "notes":["contractual ceiling, not technical: 3 violations → ban"] },

    { "id":"L3","role":"executor","platform":"codex-cli","provider":"openai-prolite",
      "account":"codex-personal","version":"0.152.0","capacity_model":"Window",
      "emulations":["B_identity: id minted server-side; first 20s unrecoverable by id"] } ],

  "weakened": [
    { "owner_item":"R1-08","lane":"L4","axis":"D_context","was":"hard","now":"close-and-reseed",
      "consequence":"ticket→session becomes one-to-many for this lane; a re-seed costs the session's working memory",
      "stops_holding":"the ACTION guarantee; the OUTCOME guarantee survives" },
    { "owner_item":"Д12","lane":"L4","axis":"G_send","was":"instruction","now":"kill",
      "consequence":"stop-hard on L4 kills the process; stranded text is returned, not submitted" } ],

  "denied": [
    { "owner_item":"R1-06.1","lane":"L5","platform":"pi","axis":"E_quota","reason":"quotaModel None",
      "effect":"not eligible for any role with needs_predictable_capacity" } ],

  "asked": [
    { "requirement":"R1-15.floor","lane":"L6","answered":"worktree+denylist","at":"2026-09-19T21:04:44Z" } ],

  "open_questions": [
    "capacity.reserve_pct = 0 — чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу?" ] }
```

`weakened[]`, `denied[]` and `open_questions[]` are **printed at run start** and carried into
`status.json`. `open_questions[]` is `JUDGE-survival` G12's mechanism: a default the owner never chose
is shipped at its neutral value **and the question is printed**, rather than a number being invented
quietly.

---

## 7. The normalised event vocabulary

### 7.1 Why the core reads nothing native

Transcript formats share no shape: JSONL per session (Claude Code, Codex, pi, Qwen, Gemini), SQLite
(MiMoCode, Codex's projections, Cursor), a server-side API only (Amp), an SSE stream plus a store
(OpenCode, Kimi), and **markdown prose** (Aider) — VERIFIED, `ADAPTER-CONTRACT.md` §6.2.

> **Invariant EV-1.** The core opens no platform-native transcript, ever. It reads
> `<run-root>/lanes/<lane-id>/events.jsonl` and nothing else. Rationale: otherwise one platform's schema
> change breaks the run loop for all of them — which is exactly what happened to the previous
> generation's capacity reader (§8.2).

### 7.2 The closed set — 28 kinds

```
lifecycle   session.spawned · session.resumed · session.exited · session.lost
turn        turn.started · turn.completed · turn.failed
work        tool.called · tool.denied · output.written
blocking    question.raised · question.answered · permission.requested · permission.decided
capacity    capacity.read · limit.hit
context     context.read · compaction.started · compaction.proved · compaction.unproven
engine      step.started · step.finished · step.verdict · engine.needs_human
lane        account.verified · posture.asserted · platform.version_drift · concurrency.deferred
```

The first twenty-four are `ARCH-adapters` §6.1 unchanged. **The four `lane.*` kinds are additions made
by this spec**, each because a section here needs an observable the original set cannot express:
`account.verified` (§11.3's post-launch account proof), `posture.asserted` (§11.4),
`platform.version_drift` (§10.4, a version that changed **during** the run), `concurrency.deferred`
(§9.5, a lane held back by a ceiling rather than by work).

Versioned by `contract_version`. Adding a kind is a minor version; removing or re-meaning one is a
major version and every adapter's manifest must be re-verified.

### 7.3 The record

```jsonc
{ "seq": 1204,
  "at": "2026-09-19T21:04:18.221Z",
  "mono": 48821.442,                 // CLOCK_MONOTONIC seconds; durations use THIS, never `at`
  "epoch": 7,
  "boot_id": "7f3c…",
  "lane": "L2",
  "session": "orc-20260919-210411-7c1f0a9e-1",
  "kind": "context.read",
  "source": { "adapter": "codex-cli", "op": "readContext", "native_kind": "token_count" },
  "provenance": { "text": "verbatim", "value": "provider_measured" },
  "payload": { "used": 118442, "window": 272000, "pct": 43.5, "is_estimated": false } }
```

**`mono` is not decoration.** Every duration in the system is computed on `mono`; `at` is display only.
A wake from sleep is `wall_delta − mono_delta > sleep.gap_seconds`
(**DEFAULT-PROPOSED: `60`**), and for `sleep.grace_seconds` (**DEFAULT-PROPOSED: `120`**) after a wake
**no lane may be judged dead and no capacity reading older than the wake is authoritative**. Rationale:
the previous run ended with `orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
sleep)` (VERIFIED, FIELD-NOTES §10.1), and `JUDGE-survival` §3b calls the sleep fence *"the only
complete one"* in the set — it belongs in the event record because that is the only place every
consumer sees it.

### 7.4 Provenance, declared once rather than stamped by hand

Two axes, mandatory on every number: `text ∈ {verbatim, reconstructed, absent}` says how good the bytes
are; `value ∈ {provider_measured, tokenizer, estimated, derived, unknown}` says how good the number is.
Collapsing them onto one axis forces a lie in one direction. The governing rule is adopted verbatim:
**a wrong token number is worse than no token number**, and **numbers cannot exist without provenance**.

`ARCH-adapters` §20 predicts this *"will be the first thing an adapter author skips"*, and `JUDGE-cost`
agrees. **This spec removes the per-event burden.** `manifest.provenance_map` declares it once, per
event kind and field, and `normalize` stamps:

```jsonc
"provenance_map": {
  "context.read": { "used": ["verbatim","provider_measured"], "pct": ["verbatim","derived"] },
  "capacity.read": { "used_pct": ["verbatim","provider_measured"] },
  "tool.called":  { "*": ["verbatim","derived"] }
}
```

A field with no entry is stamped `["absent","unknown"]` **and** raises a conformance warning naming the
kind and the field. So the honest default is free and the dishonest one is impossible: there is no path
in the schema that produces a bare number.

### 7.5 Four hard rules for `normalize`

1. **An adapter that cannot produce an event emits nothing.** It never synthesises one. Absence is
   `unknown`, never `false`. **`missing ≠ zero`.**
2. **`session.lost` ≠ `session.exited`.** The first says the adapter lost the channel; the second says
   the process exited with a code. Conflating them is how a pipe-only transcript (Amp, `dsh`) reads as a
   finished session.
3. **Every event carries `epoch`.** An event from a lower epoch is **recorded and discarded, never
   applied** — the fence that stops a paused orchestrator waking after a quota reset and merging a phase
   the new one already merged.
4. **`seq` is dense per lane and assigned by `normalize`**, never by the platform. Platform ids are
   never the primary key (ID-1).

### 7.6 Worked example E3 — one Codex `token_count` record, normalised

Native (VERIFIED, a real record from
`~/.codex/sessions/2026/09/14/rollout-2026-09-14T02-08-44-*.jsonl`):

```json
{"timestamp":"2026-09-13T19:08:53.449Z","ordinal":18,"type":"event_msg",
 "payload":{"type":"token_count","info":{"model_context_window":258400,
   "rate_limits":{"primary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1789809907},
     "secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},
     "plan_type":"prolite","rate_limit_reached_type":null}}}}
```

`normalize` emits **two** events from it — one per axis — because the core's governors are different:

```jsonl
{"seq":812,"at":"2026-09-13T19:08:53.449Z","mono":48821.4,"epoch":7,"lane":"L3","kind":"context.read",
 "source":{"adapter":"codex-cli","op":"transcript","native_kind":"token_count"},
 "provenance":{"text":"verbatim","value":"provider_measured"},
 "payload":{"used":null,"window":258400,"pct":null,"is_estimated":false,"basis":"raw"}}
{"seq":813,"at":"2026-09-13T19:08:53.449Z","mono":48821.4,"epoch":7,"lane":"L3","kind":"capacity.read",
 "source":{"adapter":"codex-cli","op":"transcript","native_kind":"rate_limits"},
 "provenance":{"text":"verbatim","value":"provider_measured"},
 "payload":{"variant":"Window","account":"openai:personal",
   "buckets":[{"id":"primary","used_pct":12.0,"window_seconds":604800,
               "resets_at":"2026-09-19T14:45:07Z"}],
   "worst":"primary","used_pct":12.0,"resets_at":"2026-09-19T14:45:07Z","cost":"free-inband"}}
```

Note three things this example makes concrete:

- `used` is `null`, not `0`, because the record carries the window and not the used figure in this
  sample. **`missing ≠ zero`** is a schema property, not a convention.
- `window_seconds` is **derived** from `window_minutes × 60`, never assumed. The owner's [007]
  requirement — adapt if it becomes a ten-hour window, or no window — is satisfied by the data format
  itself, with no adapter change (VERIFIED, `C4-capacity-research.md` §3.2).
- The capacity reading is **free and in-band**: it costs no HTTP call, is correctly attributed to the
  account whose session produced it, and cannot be throttled. §8.5 rule 5 prefers this path wherever it
  exists.

---

## 8. Capacity

### 8.1 The sum type

**This is the single biggest divergence in the field** (`ADAPTER-CONTRACT.md` §3-E). Three incompatible
worlds coexist: a **rolling window** with a reset time (Claude Code 5h + 7d, Codex, Kimi, Copilot, GLM),
a **credit balance with no reset at all** (DeepSeek, Amp, Cursor's monthly cycle), and **nothing** (pi,
Qwen, MiMoCode, OpenCode, Aider) — VERIFIED. A scheduler written against *"pause until `resets_at`"*
will **wait forever** on a credit platform; one written against *"stop at 90%"* has no percentage to
read there.

```
Capacity =
  | Window     { buckets: [Bucket], worst: bucket_id, used_pct: float, resets_at: iso8601 }
  | Credit     { remaining: decimal, unit: "USD"|"CNY"|"credits", no_reset: true }
  | None       { declared_by: "manifest" }                       // static: the platform reports nothing
  | Unreadable { reason: auth_expired | throttled | schema_unknown | network | not_supported,
                 detail: string, at: iso8601 }                   // per-read
```

```
Bucket = { id: string, label: string|null,
           kind: "percent" | "credits" | "currency" | "requests",
           used: number|null, limit: number|null, used_pct: float|null,
           window_seconds: int|null,        // DERIVED, never assumed; null is "unknown", not "missing"
           resets_at: iso8601|null }
```

`None` and `Unreadable{not_supported}` are different facts and are kept apart deliberately: `None` is a
**static declaration** in the manifest (`quotaModel: "None"` — pi owns no account, so this is a design
position, not a gap), and the meter never calls `readCapacity` on such a provider at all.
`Unreadable{not_supported}` is a **runtime** answer from a provider that declared `Window` and whose
endpoint returned 404 — which is a defect and must be noisy.

### 8.2 Why the type is a sum type and not a number

The previous generation proved every branch of this by failing on it (all VERIFIED, FIELD-NOTES §11.7,
§12.4, via `C4-capacity-research.md` §3.1):

- `harness-limits.sh:69-70` parses `.limits[]`, and **there is no `.limits` array in the current
  response**. Every read returned `UNREADABLE` — recorded as `weekly_all=unreadable%` on six consecutive
  ticks and across at least five separate days.
- `on_unreadable: proceed` then returned 0 immediately, so the run continued with **no cap enforcement
  at all, for days**.
- `stop_at` was parsed out of the literal string `SESSION=?`, so the hard stop **could never fire**.
- Usage was measured against the **wrong account**, and a weekly figure fell **26% → 6% from an account
  switch alone**, with no usage changing.

A scalar cannot express any of those four states. The sum type can, and §12.2 makes returning a scalar
a `65`.

### 8.3 Reading algorithm, in numbered steps

Run by the meter (§8.5), never by a lane or an agent.

1. Look up the provider's `capacity_model`. If `None`, return `None` without a call.
2. Resolve `capacity_probe` from `probes.json`. If the probe kind is `inband`, read from the lane's
   `events.jsonl` instead of making a call (rule 5 below). Otherwise execute the probe's `cmd`.
3. On a non-zero exit or a transport failure, classify: timeout or connection refused →
   `Unreadable{network}`; HTTP 401/403 → `Unreadable{auth_expired}`; HTTP 429 or an explicit
   `rate_limit_error` body → `Unreadable{throttled}`; HTTP 404/501 → `Unreadable{not_supported}`.
4. On a 200, apply AD-2: check the platform's own success flag first (`.success == true` for GLM).
   A 200 whose success flag is false is `Unreadable{schema_unknown}`.
5. **Enumerate buckets; never name them.** Select every object at `buckets_enumerate` that carries a
   non-null `bucket_pct_field` **or** a non-null balance field. Do not read `five_hour` and `seven_day`
   by name.
6. For each selected bucket, derive `window_seconds`: `window_minutes × 60` (Codex), the `unit`+`number`
   table (Z.ai: unit 3 / number 5 → 5 h, unit 6 / number 1 → weekly), a name lookup (Anthropic). **A
   window the adapter cannot decode is reported with `window_seconds: null` and still counted** — an
   unknown window is not a missing one.
7. Normalise every reset to UTC from ISO-8601, epoch seconds, or epoch milliseconds.
8. **If step 5 selected zero buckets on a 200, return `Unreadable{schema_unknown}` — never
   `Window{used_pct: 0}`.** This is the single highest-value rule in the section (§8.10, worked example
   E5).
9. Pick `worst` = the bucket with the highest `used_pct` (Window) or the lowest remaining (Credit).
   Headroom is the **worst** constraint across every bucket, never an average and never the first one.
10. Stamp `account` from the lane's `capacity_account_key` (§8.4), stamp `at`, write the cache, emit
    `capacity.read`.

### 8.4 Attribution — every reading is keyed to an account, and readings never cross

> **Invariant CAP-1.** Every `Capacity` carries `account` = the provider account's
> `capacity_account_key`. The core **refuses to compare two readings whose keys differ**, and a threshold
> series never crosses an account boundary.

Rationale, both halves VERIFIED in FIELD-NOTES §11.7: *"my limits position was measuring the wrong
account"*, with 94% weekly on the wrong pool; and *"a weekly-usage figure can move without any usage
changing — when the supervisor was repointed from one account to another mid-run, the weekly reading
fell from 26% to 6% from the account switch alone."*

`capacity_account_key` is `"<provider-family>:<account-local-name>"` and is set in the `Account` record
(§1.6), **not** derived from the platform, because the same `claude` binary under two base URLs bills
two different pools. Two accounts that resolve to the same key are a preflight refusal (§11.3).

### 8.5 The meter — one process, machine-wide

> **Invariant CAP-2.** No lane and no agent ever calls a capacity endpoint directly. One meter holds
> `<run-root>/capacity/meter.lock` and is the only caller.

Rules, each measured:

1. **Single-flight per account**, cached at `<run-root>/capacity/<account-id>.json`.
2. **DEFAULT-PROPOSED:** `capacity.poll_min_seconds: 3600`, `capacity.burst: 2`, jittered ±10%.
   Rationale, measured today (VERIFIED, `C4-capacity-research.md` §3.1c): **8 rapid calls on one token —
   calls 1–2 succeeded, calls 3–8 returned `rate_limit_error`**; a cooldown probe at one call per 15 s
   for 180 s was **still limited at t+167 s**. The quota-reading channel is itself a scarce resource with
   roughly a two-call budget and a multi-minute recovery.
3. **Poll the active account only.** An idle account cannot be polled at all: an idle
   profile returned `authentication_error` rather than quota, because its stored OAuth
   token is stale and tokens refresh only when Claude Code runs under that profile (VERIFIED). Preflight
   therefore records `capacity.<account>: unprovable` for standby accounts rather than pretending.
4. **Whether the throttle is per-token or per-IP is UNKNOWN** (the cross-check was spoiled by rule 3's
   `authentication_error`). If it is per-IP, polling several accounts shares one budget and rotation buys
   nothing. §17 asks about it; until answered, the meter treats the budget as **per-IP** — the
   conservative reading.
5. **Prefer in-band where it exists.** Codex's `token_count` events carry the whole `rate_limits` object
   for free, unthrottled and correctly attributed (VERIFIED). Where a platform offers both, in-band wins
   (INFERRED, and stated as such in `C4-capacity-research.md` §5.4).

> **Invariant CAP-3. Stale capacity never authorises routing.** A reading older than
> `capacity.max_age_seconds` (**DEFAULT-PROPOSED: `5400`**, i.e. 1.5 × the poll floor) is treated as
> `Unreadable{throttled}` for dispatch purposes, whatever it said. Rationale: a cached 12% from before a
> two-hour gap is not evidence of headroom now, and the whole class of failure in §8.2 is
> *treating an old or absent number as a good one*.

### 8.6 Policy per variant

Decided **once, centrally** — never per adapter, because *"a rule replicated per adapter is a rule a new
adapter can omit, and omission here is silent"* (VERIFIED as Sortie ADR 0025's reasoning via
`LANDSCAPE.md` §4).

| Variant | Thresholds | On soft threshold | On hard threshold / exhaustion |
|---|---|---|---|
| `Window` | **percent** | start nothing new; let the running step finish | **pause until `resets_at` + margin, auto-resume** — R1-06.1 exactly |
| `Credit` | **money** | start nothing new | **stop and notify a human**; never auto-resume — there is nothing to wait for |
| `None` | none | n/a | local ledger + conservative ceiling; react to `detectLimitHit` only; **never hold a role with `needs_predictable_capacity`** |
| `Unreadable` | **per stop-class** | a soft stop may proceed | a **hard** stop must not silently become no stop |

**DEFAULT-PROPOSED:** `capacity.soft_pct: 85`, `capacity.hard_pct: 95` (Window only). Rationale: the
soft value is far enough from the wall that a step started at 84% can finish; the hard value leaves
room for the run's own teardown. Both are proposals — the owner named percentages as *his* setting
[171], [204], and stated no numbers.

**DEFAULT-PROPOSED:** `capacity.resume_margin_seconds: 120`. Rationale: resuming one second before the
window actually rolls costs a full retry cycle at exactly the moment the run is most fragile.

**DEFAULT-PROPOSED:** `capacity.spend_ceiling_usd: null`, **and a start-time refusal if any lane's
`capacity_model == Credit` and no ceiling is set.** Rationale: on a credit provider *"run until the
limit"* has no natural stopping point — it just costs money — and pi on an Anthropic subscription bills
per token as extra usage with the same property (VERIFIED, `ADAPTER-CONTRACT.md` §6.5).

### 8.7 `Unreadable` — the sub-kinds want opposite responses

| Sub-kind | Meaning | Policy (DEFAULT-PROPOSED) |
|---|---|---|
| `throttled` | ask later | back off ×2 up to `capacity.max_backoff_s: 7200`; keep the last good reading, subject to CAP-3 |
| `auth_expired` | **this account needs a human** | hold every lane on that account; notify; never retry silently |
| `network` | transient | 1 retry after `60s`; then treat as `throttled` |
| `not_supported` | the manifest declared a model the endpoint does not have | **exit 65** at the adapter; hold the lane; this is a manifest defect |
| `schema_unknown` | a 200 we cannot parse | **always noisy**: notify immediately, hold dispatch on that account, record the raw body's size and hash (never its content) |

**DEFAULT-PROPOSED:** `capacity.on_unreadable.hard: hold-and-escalate`,
`capacity.on_unreadable.soft: proceed`.

**DEFAULT-PROPOSED:** `capacity.on_unknown: hold_dispatch` with
`capacity.unknown_grace_minutes: 30`. Rationale: this is the **highest-value single correction in the
whole research** — the previous generation shipped `on_unreadable: proceed`, which combined with the
schema drift meant the limiter was **provably inert for days** (VERIFIED, §8.2). All four designs invert
it; this spec inverts it and adds the grace window so a single throttled read does not stop a healthy
run.

> **Invariant CAP-4.** A threshold that names a bucket the provider has stopped reporting is a
> **configuration error**, surfaced in preflight and again on the first tick that cannot find it —
> **never a silent no-op**. This closes the `stop_at`-can-never-fire half of §8.2.

### 8.8 The reserve, shipped neutral and asked out loud

**DEFAULT-PROPOSED:** `capacity.reserve_pct: 0`, **and preflight prints one line naming it as an open
question**, with the exact Ukrainian wording in §17 (question 1).

Rationale, following `JUDGE-survival` G12 exactly: a non-zero reserve is a number nobody put to him
(`extract/corrections.md` §F records that the interviewer dropped the sub-question), and shipping one
silently is the thing all four designs promised not to do; shipping zero without saying so lets a run
eat the subscription he needs in the morning. The neutral value plus the printed question is the only
handling that is honest in both directions.

### 8.9 `needs_predictable_capacity`

A role may declare that it must be able to **predict** capacity, not merely react to it. A provider at
`capacity_model: None`, or one whose last reading is `Unreadable` past the grace window, is **not
eligible** for such a role. The owner does not get a broken guarantee; he gets a provider that cannot
hold a role, stated at config time in plain words (`C4-capacity-research.md` §5.2, following his own
[270] lever).

**DEFAULT-PROPOSED:** only `orchestrator` declares it. Rationale: the orchestrator is the one session
whose unplanned death costs the run; an executor that hits a wall is R1-06.2's explicitly acceptable
case — *«це нормально, що завдання впреться в стіну, тому що в нас в реєстрі має записуватись кожен
стан»* [171].

### 8.10 Worked examples

**E4 — Anthropic OAuth usage → `Window`, with the bucket trap.**
Live response shape today (VERIFIED, real values, `C4-capacity-research.md` §3.1):

```
five_hour.utilization = 10.0   five_hour.resets_at = 2026-09-19T17:50:00+00:00
seven_day.utilization = 32.0   seven_day.resets_at = 2026-09-20T11:59:59+00:00
nimbus_quill.utilization = 0.0     ← present, non-null, alongside the two real windows
tangelo, iguana_necktie, omelette_promotional, cinder_cove, … = null   (twenty-plus of them)
extra_usage.{is_enabled:false, monthly_limit, used_credits, utilization, …}
```

Step 5 selects `five_hour`, `seven_day` **and `nimbus_quill`** — every bucket carrying a non-null
`utilization`. Step 9 picks `worst = seven_day` at 32.0%. An adapter that read `five_hour` and
`seven_day` by name would work today and would **silently miss whichever bucket actually blocks the run**
when Anthropic ships a new one. That is not hypothetical: the codenamed buckets are already there.

```jsonc
{ "variant":"Window","account":"anthropic:<profile-A>","at":"2026-09-19T21:04:31Z",
  "buckets":[ {"id":"five_hour","kind":"percent","used_pct":10.0,"window_seconds":18000,
               "resets_at":"2026-09-19T17:50:00Z"},
              {"id":"seven_day","kind":"percent","used_pct":32.0,"window_seconds":604800,
               "resets_at":"2026-09-20T11:59:59Z"},
              {"id":"nimbus_quill","kind":"percent","used_pct":0.0,"window_seconds":null,
               "resets_at":null} ],
  "worst":"seven_day","used_pct":32.0,"resets_at":"2026-09-20T11:59:59Z" }
```

`nimbus_quill` is counted with `window_seconds: null` — step 6's rule that an unknown window is not a
missing one.

**E5 — GLM after the rename → `Unreadable{schema_unknown}`, not 0%.**
Z.ai began returning `CREDIT_LIMIT` rows where tools expected `TOKENS_LIMIT`, and three independent
tools rendered **all quotas as zero** (CLAIMED but mutually corroborating across unrelated projects,
`C4-capacity-research.md` §3.3). Step 5 selects the rows regardless of their `type` — it keys on the
presence of `percentage`, not on the type string — so the rename alone does not break the read. But if a
future shape removes `percentage` entirely, step 5 selects zero buckets and **step 8 fires**:

```jsonc
{ "variant":"Unreadable","reason":"schema_unknown","account":"zai:sasha",
  "detail":"200 OK, success=true, 0 of 3 rows carried a utilization field; body sha256 4a91…, 512 bytes",
  "at":"2026-09-19T21:04:33Z" }
```

and §8.7 makes it noisy: notify immediately, hold dispatch on that account. **A quota of 0% used looks
like plenty of headroom**; that is the whole failure this rule exists to prevent.

**E6 — DeepSeek → `Credit`, and the start-time refusal.**
`GET https://api.deepseek.com/user/balance` returns `is_available` plus
`balance_infos[]` of `{currency, total_balance, granted_balance, topped_up_balance}` — **no window, no
percentage, no reset timestamp**, because there is nothing to return: it is pure pay-as-you-go
(VERIFIED, official docs).

```jsonc
{ "variant":"Credit","account":"deepseek:sasha","remaining":41.83,"unit":"USD","no_reset":true,
  "at":"2026-09-19T21:04:35Z" }
```

With `capacity.spend_ceiling_usd: null`, preflight **refuses to start** and prints:

```
REFUSE  lane L5 (deepseek, provider deepseek-api) has capacity_model=Credit and no spend ceiling.
        R1-06.1 «дочекатись рестарту ліміту і продовжити» has nothing to wait for on this provider.
        Set orchestrator.capacity.spend_ceiling_usd, or remove the lane.
```

This is `on_impossible: degrade → money-ceiling` from `requirements.json` row `R1-06.threshold-pct`,
with the degradation refusing rather than guessing a number the owner never named.

---

## 9. Concurrency ceilings as a first-class provider property

### 9.1 Why this is a provider property and not a scheduler setting

Two facts make concurrency a property of *where the tokens come from*, not of how many terminals the
owner wants open:

- **GLM's ceiling is a contract with a ban attached.** Lite 1 / Pro 1–2 / Max 2+ concurrent sessions,
  and the usage policy prohibits account sharing and **bans after three violations** (VERIFIED,
  `glm.md` §§541–553, 739–740, `glm-spike.md` §§691, 982). *"GLM is an excellent platform for one or two
  concurrent unattended sessions"*, and a fleet of six runs straight at it. Exceeding this is not a
  degraded run; it is a lost account.
- **Kimi pools quota across every device and every API key on the account**: *"all devices and API keys
  share one quota pool"* (CLAIMED, official membership doc, corroborated in `kimi.md` §530 and
  `kimi-spike.md` §616). **Four Kimi sessions on one account get no more throughput than one.** Two
  lanes on one Kimi account do not double throughput — they halve each other.

Those are two different properties and this spec keeps them apart. Collapsing them into one "max
parallel" number produces a scheduler that is either illegally aggressive on GLM or pointlessly
optimistic on Kimi.

### 9.2 The shape

```jsonc
"concurrency": {
  "scope":  "provider_account",   // none | provider_account | provider_key | provider_plan | platform_process
  "max":    2,                    // int|null — null means "no declared ceiling", NOT "unlimited"
  "basis":  "contract",           // contract | technical | observed | unknown
  "on_violation": "ban_risk",     // ban_risk | throttle | error | unknown
  "pool":   "shared",             // shared | per_session   — does adding a lane add throughput?
  "source": "https://docs.z.ai/devpack/usage-policy",
  "plan_tier": "pro"              // optional, the field `max` was derived from
}
```

`max: null` with `basis: "unknown"` is the **explicit unknown shape** and is required — a provider record
that omits `concurrency` entirely fails validation (§1.4). Rationale: the field exists so that "we do not
know this platform's ceiling" is a thing the config can say, rather than a thing the config's silence
implies.

### 9.3 The two properties, separated

| Property | Question it answers | What violating it costs |
|---|---|---|
| `max` + `on_violation` | **May** N run at once? | GLM: a banned account after three strikes |
| `pool` | **Does** running N buy more work? | Kimi: nothing; the lanes halve each other |

**DEFAULT-PROPOSED:** `concurrency.enforce: hard` whenever `basis == "contract"` — the ceiling is never
exceeded, never probed, never "tried with backoff". Rationale: a technical ceiling answers with an error
you can retry; a contractual one answers with a ban you cannot.

**DEFAULT-PROPOSED:** `concurrency.pool_warn: true` — when two or more lanes share a `pool: "shared"`
provider account, preflight **warns and does not refuse**, naming the account and the fact that
throughput will not scale. Rationale: the owner may want two Kimi lanes for *isolation* rather than for
throughput (different roles, different worktrees), and refusing would override a choice he never made.
§17 question 4 asks whether he would rather it refuse.

### 9.4 Admission algorithm, in numbered steps

Run by the scheduler before every dispatch. Deterministic, zero tokens.

1. Compute `key = (provider.id, account.capacity_account_key)` for the candidate lane, but only for the
   scopes that bind: `none` → skip to step 6; `provider_account` → the key above; `provider_key` → key
   on the resolved credential reference; `provider_plan` → key on `(provider.id, plan_tier)`;
   `platform_process` → key on `(platform.id, host)`.
2. `declared = provider.concurrency.max`.
3. `account_cap = account.concurrency_override` if set. **An override may only lower**, never raise: an
   override above `declared` is a config error named at preflight, not a silent clamp.
4. `effective = min(declared, account_cap, config.concurrency.max)` over the non-null values. If all
   three are null, `effective = config.concurrency.max`.
5. Count live sessions matching `key` **from the ledger, not from a roster** — the ledger is ours and
   the roster is the platform's, and the platform's may lag. If `count ≥ effective`, emit
   `concurrency.deferred` and do not dispatch; the ticket stays claimable.
6. Apply the global cap: if total live sessions across every lane `≥ config.concurrency.max`, defer.
7. Dispatch.

**DEFAULT-PROPOSED:** `concurrency.max: 2` (global). Rationale: FIELD-NOTES §9.3 records two parallel
lanes working cleanly twice, and §5.1 records the owner's own container being **OOM-killed** while two
`docker compose up --build` ran at once. Two is his observed working practice; three is the value that
produced the incident. The owner's [160] wording — *«людина сама може визначати, яка кількість завдань
може одночасно робитися»* — makes the number his, and this is only the starting value.

**Machine-resource awareness is absent by his own retraction** [163]: *«ресурси машини, поки це заберемо,
це добавимо в майбутнє… це от останнє про сто завдань, це забери»*. §16.4 records the tension: the
ownership ledger stops the orchestrator from *killing* his work; nothing here stops it from *starving*
his machine, and that is his call.

### 9.5 `concurrency.deferred`, so a ceiling is visible

```jsonc
{"seq":331,"kind":"concurrency.deferred","lane":"L2",
 "payload":{"key":"glm-coding-pro/zai:sasha","effective":2,"live":2,"basis":"contract",
            "on_violation":"ban_risk","ticket":"T-419","waited_s":0}}
```

A lane that is idle **because of a ceiling** must be distinguishable from a lane that is idle because
there is no work. Without this event they look identical in every report, and the owner's reasonable
conclusion from "GLM did one ticket all night" would be that GLM is broken.

### 9.6 Worked example E7 — a GLM Pro plan with three executor lanes

Config asks for three executors on `glm-coding-pro` / `zai-personal`. `provider.concurrency` is
`{scope: provider_account, max: 2, basis: contract, on_violation: ban_risk, pool: shared}`.

Preflight:

```
WARN  provider glm-coding-pro declares a CONTRACTUAL ceiling of 2 concurrent sessions
      (plan tier: pro; source: docs.z.ai/devpack/usage-policy; 3 violations → account ban).
      3 lanes are configured on account zai:sasha. The third will be deferred, never refused work.
WARN  provider glm-coding-pro pools quota per account. 3 lanes on one account share one pool;
      throughput will not scale with lane count.
```

At run time, with L2 and L4 live and L6 wanting a ticket: step 5 counts 2 against `effective = 2`, emits
`concurrency.deferred` for L6, and the ticket stays claimable so another lane on another provider may
take it. **No request is ever sent that would make a third concurrent GLM session.**

The "Max 2+" tier is the one value this spec cannot resolve: `2+` is not a number. **DEFAULT-PROPOSED:**
treat `max` tier as `2` until the owner says otherwise, i.e. the conservative reading of an open-ended
contract. §17 question 3 asks.

### 9.7 Worked example E8 — Kimi, where the ceiling is not the problem

Kimi declares no session ceiling; it declares `pool: "shared"` with `max: null, basis: "unknown"`. Two
lanes on `kimi:sasha` pass admission (nothing forbids them) and produce the `concurrency.pool_warn`
line. The consequence the owner needs to know, in his own terms: **on Kimi, "different roles on
different accounts" means literally different accounts** — otherwise the role split buys isolation and
buys no capacity at all. That is `ADAPTER-CONTRACT.md` §7 question 4, unchanged, and §17 repeats it
because it is a configuration decision he has to make before a Kimi lane is worth building.

---

## 10. Version pinning, drift, and auto-update

### 10.1 Why this is a first-class concern and not hygiene

*"A run that starts on one flag surface and finishes on another is indistinguishable from a bug in the
orchestrator"* (`ADAPTER-CONTRACT.md` §6.8). The measured cadence of the field (VERIFIED there): **Amp
shipped five releases in fifteen hours** with `updates.mode: "auto"` and `runner.autoUpdate: true` by
default; **Copilot published 835 versions in twelve months**; **Kimi 2.0.2 was published the morning of
the research** with auto-update on by default, staging binaries in the background; Qwen, Droid,
MiMoCode, pi and opencode all ship daily-to-weekly.

### 10.2 The pin and the mismatch policy

`Platform.version_pin` and `manifest.version_pin` are exact strings and must be equal; a disagreement is
a load-time error naming both files.

At preflight, `preflight()` reports the **observed** version. Comparison is semver-aware:

| Difference | Policy (DEFAULT-PROPOSED) | Rationale |
|---|---|---|
| identical | proceed | — |
| patch only (`2.1.278` → `2.1.279`) | `warn`, record in `plan.json`, proceed | refusing a night over a patch bump is friction he did not ask for |
| minor (`2.1.x` → `2.2.x`) | **`refuse`** | a minor is where flags move; Amp's five-in-fifteen-hours were minors |
| major | **`refuse`** | — |
| observed version unparseable | **`refuse`** | an unparseable version is `unknown`, and unknown degrades closed (§4.3) |

Key: `version.on_mismatch: {patch: "warn", minor: "refuse", major: "refuse", unparseable: "refuse"}`.

The refusal message names the platform, both versions, and the one-line remedy — *"run
`orchestrator:adapter verify claude-code --accept-version 2.2.0`, which re-runs the fixture suite against
the new binary and updates the pin"*. A refusal the owner cannot act on in one command at 22:00 is a
refusal that will be disabled.

### 10.3 Auto-update suppression — assert, never edit

**DEFAULT-PROPOSED:** `version.autoupdate: assert_only`.

- Where suppression is an **environment variable**, the adapter sets it on every spawn
  (`DISABLE_AUTOUPDATER=1` for Claude Code; `manifest.autoupdate.env` generally).
- Where suppression requires a **config edit** (`manifest.autoupdate.config_edit_required: true` — Amp's
  `updates.mode`, `runner.autoUpdate`), the orchestrator **asserts and refuses; it does not edit**.
  Rationale: SEC-2, and R1-15 [357] — the environment's technical limits are the user's to configure,
  not the plugin's to impose. The refusal tells him the exact line to change and where.

### 10.4 Drift **during** a run

The version observed at preflight is frozen into `plan.json`. Every `launchHeadless` re-asserts it from
the adapter's cheap version read. A change mid-run emits `platform.version_drift` and, by default, holds
the lane:

**DEFAULT-PROPOSED:** `version.on_drift_midrun: hold_lane_and_notify`. Rationale: this is the direct,
free replacement for the daily conformance smoke that `JUDGE-cost` priced out (§0.2 D1). The smoke was
buying *"did this binary change since we tested it"*; a per-spawn version assertion answers the same
question at zero cost and answers it **at the moment it matters** rather than up to 24 hours late.

---

## 11. Preflight

### 11.1 What preflight is for

Three requirements converge here, and all three are the owner's: *"verify before you run"* is a
cross-cutting rule in `ANALYSIS-01` §5 (account switching R1-07, notification channel R1-17, board
statuses R1-04, worktree environment Д4 — *"each must be proven working before the run, not assumed"*),
R1-07 [199] requires the account switch be **proven working before a run starts**, and
`ADAPTER-CONTRACT.md` §3-J requires that preflight **refuse to dispatch to a lane that has not been
proven today**.

### 11.2 The gates, in order

Each gate is deterministic, zero-token, and names its failure. A gate that fails stops preflight; no
later gate runs, so the first error the owner reads is the first error that exists.

| # | Gate | Refusal reads |
|---|---|---|
| 1 | Config resolves; no unknown keys; SEC-1 secret scan passes | slot + key, never the value |
| 2 | Every adapter directory validates (§3.3) incl. the BD-1 lint | directory + failing field |
| 3 | Fixture conformance passes for every adapter in use (§12.2) | adapter + the named contract check |
| 4 | Binary present; version policy passes (§10.2) | platform, both versions, the remedy command |
| 5 | `preflight(account)` succeeds per lane; account identity read from the platform's own report | lane + account + what the platform said |
| 6 | **Account distinctness** (§11.3) | the two lanes and the identity they share |
| 7 | Capacity readable **or** explicitly `None`; a `Credit` lane has a ceiling (§8.6) | lane + variant + the missing key |
| 8 | Concurrency ceilings computed; contractual ceilings warned (§9.6) | account + declared + configured |
| 9 | Negotiation (§6.3); `weakened[]`, `denied[]`, `asked[]` resolved | per §6.3 step 9 |
| 10 | **Posture assertion** on a probe launch per lane (§11.4) | lane + field + expected vs observed |
| 11 | `plan.json` written and `fsync`ed | — |

### 11.3 Gate 6 — account distinctness

> **Invariant PF-1.** Two lanes whose roles are meant to be independent may not resolve to the same
> account identity. Preflight computes each lane's identity from the **platform's own report** (not from
> the env var it set) and refuses if two lanes intended to be distinct share one.

Rationale: `C4-capacity-challenge.md` A1 records that **two profiles can be the same account**. A role split
across two profiles that are one account gives the appearance of R1-07 and none of its substance: the
supervisor and the executor share a window, and the threshold series that was supposed to protect one
is measuring both.

The same gate refuses two accounts that resolve to the same `capacity_account_key` while claiming to be
different, which is CAP-1's precondition.

### 11.4 Gate 10 — the permission-posture assertion

**Why an assertion and not a setting.** Permission defaults differ per platform **and the unsafe ones are
silent** (all VERIFIED, `ADAPTER-CONTRACT.md` §6.4):

- **OpenCode starts permissive when `OPENCODE_PERMISSION` is malformed JSON.**
- **Gemini CLI silently downgrades `yolo` to `default` in an untrusted folder** — denying every tool
  while looking fine.
- **Copilot has a fail-closed policy path** that can strip the posture an unattended run depends on.
- **Amp allows `mcp__*`, Slack, Gmail, Drive and X by default.**
- **Kimi and pi have no sandbox at all**, and **Kimi's hooks fail open** — a crashed guard permits.
- **MiMoCode's `permission/ask-timeout` defaults to `null` — wait forever.**

None of those is detectable from a config file. All of them are detectable from what the platform
reports about itself after it starts.

```jsonc
// Posture — returned by preflight() and re-asserted after every launch
{ "sandbox": true,
  "approval": "on_request",         // never | on_request | on_failure | always | unknown
  "ask_timeout_s": 300,             // int|null — null means WAIT FOREVER
  "network": "allow",               // allow | deny | unknown
  "write_scope": "worktree",        // worktree | workspace | host | unknown
  "hooks_fail": "closed",           // open | closed | none
  "tools_allowed_default": ["read","search"],
  "source": "initialize.permissions"   // what the platform itself reported this from
}
```

**Assertion rules, in order:**

1. Any field reported `unknown` degrades closed under `negotiate.on_unknown` — the lane may not hold a
   role whose `needs` include `H_sandbox`.
2. **`ask_timeout_s: null` on an unattended lane is a refusal** unless `G_answer` is `native` or
   `emulated` — i.e. unless somebody can actually answer. A session that waits forever for an answer
   nobody can give is F2 (a finished session idling **28 hours**) with extra steps.
3. `hooks_fail: "open"` **and** `sandbox: false` → R1-15's `degrade_to: worktree+denylist` applies, and
   the degradation is written to `plan.weakened[]` against `R1-15.floor`.
4. `write_scope: "host"` on a lane whose Д4 worktree policy is `orchestrator` is a refusal: the two
   statements contradict each other and guessing which one is true is how the owner's Docker stack was
   destroyed.
5. The observed posture is compared to the lane's declared posture. **DEFAULT-PROPOSED:**
   `posture.on_mismatch: refuse_lane`.

**DEFAULT-PROPOSED:** `posture.assert_every_launch: true` — not only at preflight. Rationale: Gemini's
downgrade is **per folder**, so a posture proven in the repository root is not a posture proven in a
worktree, and the worktree is where the work happens.

The assertion emits `posture.asserted` (§7.2) so the morning report can state the posture each lane
actually ran under, rather than the posture the config asked for.

### 11.5 Worked example E9 — a MiMoCode lane refused at gate 10

```
REFUSE  lane L7 (mimocode, provider mimo-token-plan, account mimo-personal)
        posture.ask_timeout_s = null  (the platform will wait forever for an answer)
        capabilities.G_answer = impossible on this lane in headless mode
        → nobody can answer, and the session will not time out.
        Owner item at risk: R1-11 [324] «оркестратор може відповідати на ці питання».
        Fix one of: set the platform's permission ask-timeout; enable the injected
        ask_supervisor tool (questions.native_tool: disallow-headless); or remove the lane.
```

Two independent facts make this lane unsafe, and the refusal names both. Separately and already known:
**the owner's stored MiMo `tp-…` key returns 401 today on both hosts** (VERIFIED,
`xiaomi-mimo.md`), which gate 5 would have caught first.

---

## 12. Conformance — `orchestrator:adapter verify <id>`

### 12.1 The split, and why

§0.2 D1 recorded the judges' disagreement. The resolution is two halves with different costs and
different triggers.

| Half | Cost | Runs when |
|---|---|---|
| **fixtures** | zero tokens, no network, < 5 s per adapter | in CI, at every preflight (gate 3), and on demand |
| **live** | one short session + one capacity call per adapter | only when `adapter_sha256`, `version_pin` or the account changed — **never on a calendar** |

Exit codes: `0` pass · `65` contract violation, **named** · `70` environment.

### 12.2 The fixture half — what it actually asserts

Ten of the checks are §5.2's invariants mechanised. Three are the ones that catch a lying manifest, and
they are the reason this half survives `JUDGE-cost`'s objection — they cost nothing and they are the
only mechanical catch in the whole design:

1. **`compact` must return a `Proof`.** Given a fixture where the platform prints a success string and
   the token count does not move, the adapter must return **exit 65**, not success. This is the
   FIELD-NOTES *"reports success and does nothing"* class made impossible to declare.
2. **`send` must report `accepted` and nothing stronger** when the adapter holds only an enqueue
   receipt. The fixture gives it a 200 with no downstream confirmation; an adapter that returns
   `delivered` fails. Kimi's 200 means *accepted*, never *ran* (VERIFIED).
3. **`readCapacity` must return the sum type, never a scalar**, and a 200 it cannot parse must raise
   `Unreadable{schema_unknown}` rather than return zero. The fixture is the GLM rename (§8.10 E5).

Plus, mechanised from §5.2 and §3.5: stdin is closed on every spawn (AD-3); a wall-clock timeout fires
and produces exit 3 (AD-4); the model is passed explicitly (AD-6); fd 1 is pure JSON and fd 2 is ignored
(AD-7); the roster op is called per account (AD-8); handlers are re-attached on resume (AD-9); teardown
is asserted by process (AD-10); no branch on the CLI's exit code (AD-1, checked by a fixture returning 0
with an error body); a `zero-model` probe spawns no model session (§3.5 rule 3); and every event a
fixture produces validates against §7.3 with provenance present.

### 12.3 The live half and its trigger

```
live_verify_needed = adapter_sha256 changed
                  OR version_pin changed
                  OR observed binary version changed
                  OR account changed
                  OR last live pass is older than adapter.verify_max_age_hours (default: null = never)
```

**DEFAULT-PROPOSED:** `adapter.verify_max_age_hours: null`. Rationale, stated as a disagreement resolved
rather than a preference: `JUDGE-survival` wants `24` and a dispatch gate; `JUDGE-cost` identifies the
same setting as *"the only standing bill in the set that exists even when no run is happening… one
launched session per adapter per day, forever."* The content-and-version triggers above catch every case
the 24-hour clock would have caught **except** a silent server-side change behind an unchanged binary —
and that case is caught instead by §8.7's `schema_unknown` being noisy, at the moment it happens rather
than up to a day later. The key exists so the owner can set `24` if he disagrees; §17 question 7 asks.

The live half is a single short session (a fixed prompt whose expected output is one token) plus one
`readCapacity` call, both under the lane's real account. It never runs during a run — only in preflight
or on demand.

### 12.4 The dispatch gate

> A lane whose adapter has not passed the **fixture** half in this preflight is not dispatchable.
> A lane whose adapter needs the **live** half by §12.3 and has not passed it is not dispatchable.

Nothing else gates dispatch on conformance.

---

## 13. Tiers and build order

### 13.1 The tier definition, restated as a predicate

```
tier1 = D_context ∈ {native}           and compact returns a Proof
    and E_quota   ∈ {native}           and readCapacity returns Window|Credit
    and F_accounts∈ {native}
    and G_send    ∈ {native}           and Ack distinguishes accepted from delivered
    and all 14 required ops present and passing fixtures
tier2 = at least one of the four degrades, with a named fallback in requirements.json
tier3 = executor only: it can do a task, it cannot be supervised
```

A platform's tier is **computed**, not declared. A manifest claiming `tier: 1` is ignored; the predicate
above is evaluated at preflight and written into `plan.json`.

### 13.2 The first three adapters, and why in this order

Taken from `ADAPTER-CONTRACT.md` §5, which this spec does not second-guess.

**1 — Claude Code.** The only lane that can run *tonight*: installed, current (2.1.278), authenticated
across switcher profiles, and the place GSD and the owner's skills already live (R1-03, Д1). All four
non-negotiables are native in the piped shape. Build order inside it: the stdin control client (the only
genuinely hard part), then the account-union roster (twenty lines, and without it the supervisor is blind
to most of its own fleet). **Do not forget:** `--verbose` is mandatory with
`-p --output-format stream-json` or the process never starts; `CLAUDE_CONFIG_DIR` must be pinned in every
spawn or a daemon silently uses the wrong account (both VERIFIED).

The `statusLine` tee is **deferred**, not adopted: it closes D and E for attached sessions and it edits
the owner's own `settings.json`, which needs his explicit yes (SEC-2). §17 question 9 asks for it.

**2 — Codex CLI.** The honest test of whether `PlatformAdapter` is an abstraction or a Claude Code
wrapper with extra steps: a different vendor, protocol and account model, tier-1 on every axis. It also
removes the Keychain-dialog class of overnight failure entirely (no keychain), and it is the only
platform where a hit limit can be **reset from banked credits**. **Do not forget:** pin `-m`, pin `-s`,
pin `-c approval_policy`, and redirect stdin from `/dev/null` on every spawn — without the first the run
fails 100%, without the last it hangs all night (both VERIFIED).

**3 — a provider lane (GLM or DeepSeek) behind the Claude Code driver, before any third CLI.** *"The
highest value-per-hour move in the entire scan"*, and it is **a configuration change, not a feature**:
one `env_for(provider)` method plus one provider-specific capacity probe. It turns the Provider ↔
Platform split into working code and exercises `Window` and `Credit` against two providers that genuinely
differ.

**Then, and only then:** Droid (tier-1, client-assigned ids, the only platform that *degrades instead of
halting*), Qwen Code (the only drivable visible terminal — the answer to R1-11's hybrid mode), MiMoCode
or pi (the best D and G implementations in the scan, worth building against even if never adopted).
Copilot CLI is the interface's best **design reference**; nine of eleven recipes are verifiable without
spending a credit, and the entitlement decision is separate.

---

## 14. Every configurable thing in this spec, and its default

**This table is the contract. Nothing outside it may invent a default at runtime**, and a test asserts
that every key read by the code appears here (`JUDGE-fidelity` graft G6). Scope: `U` user, `P` project,
`R` run. Apply: `live` (next tick), `boundary` (next task boundary), `frozen` (next run).

| Key | DEFAULT-PROPOSED | Scope | Apply | One-line rationale |
|---|---|---|---|---|
| `adapters.path` | the four levels of §3.2 | U P | frozen | shadow a shipped adapter without touching the repo; same ranking as his config |
| `adapter.max_timeout_s` | `900` | U P | live | no single adapter call may hold a tick for a quarter hour |
| `adapter.verify_max_age_hours` | `null` (never on a clock) | U P | frozen | §12.3 — removes the only standing daily cost; content + version triggers cover it |
| `negotiate.on_unknown` | `impossible` | U P | frozen | a new requirement must not pass silently on an old adapter |
| `negotiate.on_undocumented` | `probe_then_impossible` | U P | frozen | a missing declaration is not a declared absence |
| `negotiate.interactive` | `ask` with a TTY, `refuse-run` without | U P | frozen | an unattended start must not take the weak half of a trade unseen |
| `pty.backend` / `pty.host` | `tmux` / `iterm2-if-present` | U P | frozen | every recorded delivery failure lives in AppleScript |
| `recovery.id_grace_seconds` | `20` | U P | live | the server-mints-id crash window; recover by re-dispatch inside it |
| `lane.max_seconds` | `3600` | U P R | boundary | a lane with no terminal event in an hour is a defect, not a long tail |
| `stop.soft_deadline_s` | `900` | U P R | live | a soft stop that never lands is indistinguishable from no stop |
| `context.mode` | `soft` | U P R | boundary | hard mode is impossible on four of fifteen platforms |
| `context.basis` | `raw` (and the config verb prints both scales) | U P R | boundary | his status line shows the other scale; ~13 points apart |
| `context.percent` exec / watcher / orch | `75` / `85` / `66` raw | U P R | boundary | [204] gives him per-role thresholds; the orchestrator's death costs most |
| `context.refill_rate_alarm` | `15 pct/hour` | U P | live | the 445k-token `echo idle` lane; a **defect** predicate, not a compaction one |
| `context.post_compact_prompt` | re-inject the red-line file (`null` disables) | U P R | boundary | **his key** [204]; all four designs turned it into behaviour |
| `context.on_terminal_state` | `fresh-session` | U P | boundary | verified dead ends where `/compact` can never work again |
| `context.verify_timeout_s` | `600` | U P | live | a compaction believed rather than proved |
| `capacity.poll_min_seconds` / `.burst` | `3600` / `2` | U P | live | measured: calls 3–8 rate-limited, still limited at t+167 s |
| `capacity.max_age_seconds` | `5400` | U P | live | stale capacity never authorises routing (CAP-3) |
| `capacity.soft_pct` / `.hard_pct` | `85` / `95` (Window only) | U P R | live | room to finish a step; room to tear down |
| `capacity.resume_margin_seconds` | `120` | U P R | live | resuming a second early costs a full retry at the worst moment |
| `capacity.spend_ceiling_usd` | `null`, **+ start-time refusal on any `Credit` lane** | U P R | live | *"run until the limit"* has no stopping point on credit |
| `capacity.reserve_pct` | `0`, **+ the question printed** | U P R | live | a reserve was never put to him; neither number may be invented |
| `capacity.on_unreadable.hard` / `.soft` | `hold-and-escalate` / `proceed` | U P R | live | the previous `proceed` ran uncapped for days |
| `capacity.on_unknown` | `hold_dispatch` | U P R | live | the highest-value single correction in the research |
| `capacity.unknown_grace_minutes` | `30` | U P R | live | one throttled read must not stop a healthy run |
| `capacity.max_backoff_s` | `7200` | U P | live | bounded backoff on `throttled` |
| `concurrency.max` | `2` | U P R | boundary | two lanes worked twice; a third is where his container was OOM-killed |
| `concurrency.enforce` | `hard` when `basis == contract` | U P | frozen | a contractual ceiling answers with a ban, not an error |
| `concurrency.pool_warn` | `true` (warn, do not refuse) | U P | boundary | he may want two Kimi lanes for isolation, not throughput |
| `version.on_mismatch` | patch `warn`, minor/major/unparseable `refuse` | U P | frozen | a minor is where flags move; a patch bump should not cost a night |
| `version.autoupdate` | `assert_only` (never edit his files) | U P | frozen | SEC-2 and R1-15 [357] |
| `version.on_drift_midrun` | `hold_lane_and_notify` | U P | live | the free replacement for the daily conformance smoke |
| `posture.assert_every_launch` | `true` | U P | live | Gemini's downgrade is per folder; the worktree is where work happens |
| `posture.on_mismatch` | `refuse_lane` | U P R | boundary | the unsafe permission defaults are all silent |
| `preflight.keychain_pregrant_required` | `true` (macOS, `config_dir`/`keychain` accounts) | U P | frozen | an invisible GUI dialog at 03:00 is indistinguishable from a hang |
| `questions.authority` | `refuse-and-escalate` on irreversible external effects | U P R | live | his own ratified qualifier [325]/[328] |
| `questions.native_tool` | `disallow-headless`, inject `ask_supervisor` | U P | boundary | preserves [324] instead of trading it for a permissive allow-list |
| `sleep.gap_seconds` / `.grace_seconds` | `60` / `120` | U P | live | the previous run ended on a sleep; every wake verdict across a gap is discarded |
| `state.root` | `<config-root>/shared/orchestrator/state` | U P | frozen | run state inside the tree caused 327 dirty files and the false merge |

**Keys referenced here but owned elsewhere.** `requirements.json` rows evaluate `needed_when` against
config keys that belong to the orchestration spec, not to this one: `capacity.on_exhausted`,
`runtime.visibility`, `account_change.type`, `engine.needs_subagents`, and `role.authority.may_answer`
(the last is a `Role` field, §1.8). The contract rule stands unbroken — **a key with no default in some
spec's table is a load-time error**, and a `needed_when` naming an undefined key fails preflight gate 1
by name rather than evaluating to false. A requirement that quietly evaluates to `false` because its key
does not exist is the exact shape of a safety rule that never fires.

---

## 15. What is impossible as stated, and what keeping it costs

Per the brief: the exact clause that fails, and the price of keeping it.

| Owner item | The part that is impossible | What keeping it costs |
|---|---|---|
| **R1-07** — a *hard* account change ("applies now, stops current work") [195] | Changing a **running** session's account is impossible on **all fifteen** platforms (VERIFIED) | Stop the session, relaunch on the other account, **re-seed the context**. The context is paid for twice and the lineage becomes one-to-many. The only alternative is to redefine *hard* as "at the next step boundary", which is what *soft* already means |
| **R1-08** — *«механізм, який гарантовано робить цю дію»* in **hard** mode | On Amp, Gemini CLI, Cursor and DeepSeek `dsh` there is **no external compaction trigger at all** (VERIFIED) | The **outcome** guarantee survives via close-and-reseed, built once centrally. Cost: ticket→session becomes one-to-many, a re-seed costs the session's working memory, and the ledger must hold a lineage rather than a field. The **action** guarantee cannot be kept on those four, at any price |
| **R1-08** — a compaction setting changed *during* a run | On the pre-commit rung (rung 3) the threshold is set before launch and is unchangeable while the process lives | It breaks the cross-cutting rule from Д7/Д12 that a change made during a run is picked up. Keeping it means restarting the session to change a threshold — which is close-and-reseed again |
| **R1-06.1** — *«дочекатись рестарту ліміту і продовжити»* | Seven of fifteen platforms report no capacity at all, and on `Credit` providers **there is no reset to wait for**: the model is money, not time (VERIFIED) | Either exclude those lanes from roles that need predictable capacity (this spec's default), or accept a money ceiling in place of a percentage. There is no third option |
| **R1-06.2** — *«при скількох відсотках»* | A percentage does not exist on a credit model | A money ceiling, which is a different quantity the owner has not named a value for (§17 question 2) |
| **R1-11** — hybrid (interactive *and* supervised) [324] | On Gemini CLI, ACP **replaces** the TUI — supervision and takeover are mutually exclusive per process. On Amp and `dsh` there is no attachable local pane at all (VERIFIED) | Takeover becomes a **handoff**: stop → relaunch attached → resume. One restart, visible in the run log, never silent |
| **Д12** — `stop-hard` as an instruction into a live session [524] | On Gemini headless a mid-run message cannot be delivered; in ACP it **aborts the turn** rather than adding to it | `stop-hard` degrades to killing the process; `stop-soft` degrades to the next *task* boundary rather than the next step. Recorded in `plan.weakened[]` before the run starts |
| **R1-15** — one text file, no enforcement machinery [357] | On Kimi and pi there is **no sandbox at all**, and Kimi's hooks **fail open** — a crashed guard permits | Either narrow what those lanes may be given, or turn on a deny list, which is the separate mandatory procedure he said was unnecessary. This spec defaults to the first and offers the second, off |
| **R1-07** [199] — *"verified to work before a run starts"* | Preflight can prove **identity** ("this role will run as this account") cheaply and reliably. It **cannot prove headroom** for an idle account: an unused profile's OAuth token is stale and returns `authentication_error` rather than quota (VERIFIED) | Nothing. These are two different assurances and must be presented to him as two, not one. Preflight records `capacity.<account>: unprovable` for standby accounts |
| **R1-16 case 2** — his parallel work in the same checkout | **Nobody in the field solves it, unanimously** (VERIFIED, `LANDSCAPE.md` §5): every tool isolates by giving the agent its own worktree, and not one protects the human's concurrent edits in the *same* checkout | Worktree anchoring plus the ownership ledger reduce it to "the agent is not in your folder" for **processes and containers**. They do nothing about **files**. A path-level per-run ownership rule has to be invented, and this spec does not invent it |

---

## 16. Tensions with the owner's decisions, recorded rather than resolved

**16.1 The lane is not a word he used.** He speaks of platforms, providers, accounts, roles and
sessions. `Lane` is this spec's object, invented to make the other five schedulable. It is a good
abstraction and it is not his vocabulary, which matters because every report and every stop command will
speak it back to him. If he thinks in sessions, the CLI should say `session` and the internals should
keep `lane`. §17 question 11.

**16.2 Preflight will refuse to start for reasons he never asked about.** `negotiate.on_unknown:
impossible`, `posture.on_mismatch: refuse_lane`, the `Credit`-without-ceiling refusal and gate 6's
account distinctness can each stop a night before it begins. The trade is deliberate — an honest refusal
at 22:00 beats a silent degradation at 03:00 — and it is friction on a man whose stated ideal is a thing
that outputs nothing and asks him nothing (Д11 [508]). `JUDGE-cost` objects to exactly this and is not
wrong. `negotiate.interactive` is the knob that turns a refusal into a question; nothing turns it into
silence, and that is a choice this spec made for him.

**16.3 `capabilities()` is a claim, and every safety property downstream rests on it.**
`negotiate.on_unknown: impossible` protects against a manifest that *omits* something. §12.2's fixtures
protect against three specific lies. **Nothing protects against a manifest that confidently declares
`native` for an axis whose implementation is subtly wrong** — it is written by the same author, tested
against fixtures the same author recorded, and trusted at exactly the hour when nobody is watching.
`ARCH-adapters` names this as its own single weakest point and it remains true here, with the daily live
smoke removed (§0.2 D1) it is marginally *more* true. The honest mitigation is that the first two
adapters are for platforms the owner runs every day, where a wrong manifest surfaces within hours.

**16.4 Machine-resource awareness is absent by his retraction** [163]. FIELD-NOTES §5.1 records his own
container being OOM-killed by the run while two builds ran at once. The ownership ledger prevents the
orchestrator from *killing* his work; **nothing here prevents it from starving his machine**.
`concurrency.max: 2` is a coincidental mitigation, not a solution, and calling it one would be dressing
up a retraction as a feature. That is his call, recorded.

**16.5 Cost is not a scheduling input.** `ADAPTER-CONTRACT.md` §6.5 shows a **150×** credit spread inside
one platform's model list, and GLM-5.3-Flash undercutting MiMo-V2.5-Pro roughly 3× on input. This spec
pins model per role (`Role.model_pin`, `Provider.small_model`) and stops there. Routing by price is a
subsystem, and Д8's cheap-watcher pin is the only part of it the owner actually asked for.

**16.6 Ten axes is more configuration surface than he described.** He asked for per-platform
configuration [324], [310]; he did not ask for a ten-axis lattice with a five-value vocabulary. The
lattice is `JUDGE-cost`'s cheapest graft (~15 lines) and it is still a thing he will read in a refusal
message at 22:00. If it proves to be noise, the collapse is safe: axes can be merged without touching
any adapter, because `requirements.json` is the only file that names them.

---

## 17. Needs the owner — round 2 questions

Each is something this spec had to invent because he never decided it. Plain Ukrainian, ready to paste.
The numbered key beside each is the default this spec ships in the meantime.

**1. Запас ліміту для тебе самого** — `capacity.reserve_pct: 0`
Зараз оркестратор може витратити ліміт до нуля, і зранку тобі може не лишитись нічого на власну роботу.
Чи треба завжди лишати якийсь запас (наприклад 10–20% тижневого вікна), чи можна витрачати все?

**2. Грошова стеля на ніч** — `capacity.spend_ceiling_usd: null`
Є провайдери, де ліміт — це не вікно, а гроші (DeepSeek, Amp), і там «дочекатись рестарту» не існує:
воно просто витрачається. Яку суму за ніч ти вважаєш нормальною стелею — і це одна сума на весь ран,
чи окрема на кожну лінію?

**3. GLM: скільки одночасних сесій** — `max` tier = `2`
На тарифі Max у Z.ai написано «2+», що не є числом. Ліміт у них — це умова підписки, а не технічне
обмеження: після трьох порушень акаунт банять. Яке число ставимо як жорстку стелю для твого тарифу?

**4. Kimi: один акаунт чи кілька** — `concurrency.pool_warn: true`
На Kimi усі пристрої й усі ключі ділять один пул квоти. Дві лінії на одному акаунті не подвоюють
швидкість — вони ділять її навпіл. Готовий заводити окремий акаунт під кожну роль там, де пул спільний,
чи для таких платформ просто тримаємо одну лінію?

**5. Оновлення версій** — `version.on_mismatch: {patch: warn, minor: refuse}`
Пропоную: якщо змінилась тільки патч-версія — попереджаємо і працюємо; якщо мінорна чи мажорна —
відмовляємось стартувати, поки ти не підтвердиш. Мінорна версія — це там, де зазвичай зникають прапорці.
Це прийнятна жорсткість, чи хочеш м'якше?

**6. Автооновлення платформ** — `version.autoupdate: assert_only`
Деякі платформи оновлюють себе самі (Amp — п'ять релізів за п'ятнадцять годин). Вимкнути це іноді можна
тільки правкою твого власного конфіга. Правило зараз: **ми твої файли не чіпаємо**, а просто відмовляємось
стартувати й кажемо, який рядок треба змінити. Підтверджуєш, чи дозволяєш нам виставляти це самим?

**7. Як часто перевіряти адаптери «наживо»** — `adapter.verify_max_age_hours: null`
Можна щодня запускати коротку живу перевірку кожного адаптера — це надійніше, але це витрати навіть у ті
дні, коли ран не запускався. Зараз пропоную перевіряти тільки коли реально щось змінилось (версія або сам
адаптер). Тобі як краще: щодня чи за змінами?

**8. Сесія, яка чекає відповіді вічно** — `posture.on_mismatch: refuse_lane`
На деяких платформах час очікування відповіді за замовчуванням — «чекати вічно». Якщо туди ще й не можна
відповісти програмно, сесія зависне до ранку. Пропоную такі лінії просто не пускати в ран. Згоден, чи
краще пускати з попередженням?

**9. Читання контексту з твого статус-рядка**
Найточніше читати заповнення контексту в Claude Code можна, додавши рядок у **твій власний** `settings.json`
(`statusLine`). Ми туди не лізли. Дозволяєш нам це запропонувати окремою командою, чи залишаємо як є і
читаємо контекст менш точно?

**10. Пороги контексту — на якій шкалі** — `context.basis: raw`
Відсоток контексту можна рахувати від повного вікна або від того, що реально залишилось після
зарезервованого. Різниця — близько 13 відсоткових пунктів, і твій статус-рядок весь час показував одну з
них. Коли будеш ставити поріг, показувати тобі обидва числа й питати, на якій шкалі ти його ставиш?

**11. Як це називати** — internal object `Lane`
У нас всередині є об'єкт «лінія» = платформа + провайдер + акаунт + роль. Це те, що планується, зупиняється
і про що звітується. Тобі зручніше, щоб команди і звіти говорили «лінія», чи «сесія», чи якось інакше?

**12. Один тікет — кілька сесій**
Там, де компакт ззовні запустити не можна, єдиний спосіб — закрити сесію і відкрити нову з підсумком. Тоді
один тікет = ланцюжок сесій, і в реєстрі має бути ланцюжок, а не одне поле. Це ок для твого обліку, чи один
тікет має завжди мапитись рівно на одну сесію?

**13. Ціна «хард» зміни акаунта**
На жодній із п'ятнадцяти платформ не можна змінити акаунт живої сесії. Твоя «хард» зміна фізично означає:
зупинити сесію, запустити нову на іншому акаунті й **перезалити контекст** — тобто заплатити за нього ще
раз. Підтверджуєш цю ціну, чи хард-зміна має чекати кінця поточного кроку?

**14. Які ролі мають вимагати передбачуваного ліміту** — зараз тільки `orchestrator`
Платформа, яка взагалі не вміє показувати залишок (pi, Qwen, MiMo, OpenCode, Aider), не може тримати роль,
для якої треба заздалегідь знати, скільки лишилось. Зараз це стосується тільки оркестратора. Виконавця теж
треба захистити, чи виконавцю нормально впертись у стіну?

**15. Два профілі — один акаунт**
Два профілі перемикача профілів можуть бути **одним і тим самим акаунтом**. Якщо розкласти ролі
по таких двох, то формально ролі різні, а ліміт спільний. Пропоную, щоб префлайт відмовлявся стартувати в
такому випадку. Згоден?

**16. Чи є ліміт на читання квоти спільним на всю машину**
Ендпойнт, який показує залишок ліміту, сам жорстко throttle-иться: 8 швидких запитів — і з третього вже
відмова, відновлення довше трьох хвилин. Ми не змогли встановити, це ліміт на токен чи на IP. Якщо на IP,
то опитувати кілька акаунтів марно. Поки що рахуємо найобережніше — як на IP. Якщо ти знаєш точно —
скажи, це заощадить нам окремий прохід.

**17. Кешування ліміту між ранами**
Зараз кеш ліміту живе всередині одного рану. Якщо ти запускаєш два рани підряд, другий піде читати
ендпойнт заново і може впертись у throttle. Тримати кеш на рівні машини (спільний між ранами), чи хай
кожен ран читає свій?

**18. Дозволи адаптера, який ти напишеш сам**
Ми зробили проби (liveness, identity, capacity) звичайними даними, щоб ти міг підставити туди свій власний
скіл — як ти й казав у [310] і [312]. Питання одне: чи має оркестратор мати право запускати твій скіл
**без обмежень**, чи для власних проб теж діють ті самі правила, що й для виконавців?

---

## 18. What this spec deliberately does not cover

Named, so nobody builds against an assumption.

- **The run state machine, the tick loop, the judge and the liveness governor.** This spec provides the
  adapter, the events and the capacity type; what *acts* on them belongs to the orchestration spec. The
  one place the two touch is §5.10's note that `status` is an observation and never a liveness verdict.
- **The engine seam** (GSD, superpowers, custom). `I_extend` is an axis and `R1-03.engine-in-session` is
  a requirement row; the engine descriptor itself is another document.
- **The board and the questions channel.** Д6 and R1-04 are connectors under the identity slots, not
  adapters under `adapters/platforms/`.
- **Delivery** — worktrees, branches, PRs, the merge-landed assertion. Д4, R1-12, R1-13.
- **Cost-based routing**, per §16.5.
- **Multi-machine and remote lanes.** Everything here is one host, one `flock`, one `boot_id`.
- **The learning loop.** [062] *«якщо це не підходить, то треба вчити»* is the only place in the whole
  session where feedback changes future behaviour, and `extract/outside-list.md` records that it is
  absent from `ANALYSIS-01` entirely. Nothing in this spec learns.

## 19. The single weakest point of this spec

**Fourteen required operations on fifteen platforms is 210 contract points in the fastest-moving field
in the research**, and this spec's own answer to that — build two adapters and a provider lane, not
fifteen — is a discipline, not a mechanism. Nothing in the design refuses a third adapter that nobody
has time to maintain, and the manifest of a stale adapter keeps declaring `native` long after the
platform has moved (§16.3). The one property that partially covers it is §6.4's: a new requirement makes
every old manifest answer `unknown`, and unknown degrades closed — so a neglected adapter fails
*forward*, refusing work rather than doing it wrongly. That is the best this shape offers, and it is
worth saying plainly that it is a containment, not a cure.
