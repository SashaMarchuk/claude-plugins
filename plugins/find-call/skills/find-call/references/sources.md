# Source model — universal by default, preference + fallback when you want control

`/find-call` pulls from three kinds of source: **calendar** (the index), **docs** (Meeting Notes / Drive exports), and **transcripts** (notetaker output like Sembly). Each is reached through a *provider*. The skill resolves which provider to try first for each source at Step 0.

The guiding rule: **get the data.** Use whatever is available by default; let the user express a *preference* for which provider gets tried first — but always fall back to another working provider rather than failing. The config sets preference order, never a hard wall (the one exception is `off`, which disables a source on purpose).

## Provider values

Each source accepts one of:

| Value | Meaning |
|---|---|
| `auto` | **Default.** No stated preference — use the built-in order below. Universal: works out of the box on any machine. |
| `cli` | **Prefer** the `npx @googleworkspace/cli` path; fall back to the MCP if the CLI is unavailable/unauthenticated/errors. (Google sources only.) |
| `mcp` | **Prefer** the MCP path (e.g. a connected Google Calendar / Drive MCP); fall back to the CLI if the MCP is absent/errors. (Google sources only.) |
| `off` | Disable this source entirely. The only non-fallback value. (Valid for `docs` and `transcripts`; calendar is the index and cannot be off — `docs: off` means notes are never fetched, summaries come from calendar + transcripts only.) |
| `["sembly", ...]` | (transcripts only) Preference order — try these notetakers first, then fall back to any other connected notetaker. |

**Key point:** `cli` and `mcp` are *preferences*, not restrictions. They only change which provider is tried **first**. If the preferred one can't deliver, the skill falls through to the other so the data is still retrieved. To actually forbid a source, use `off`.

## Resolution order

For every source, build the list of *available* providers (detected from the session), order them by the user's preference, and try them in turn until one returns data:

- **calendar** → preference order over { CLI (`npx @googleworkspace/cli calendar events list`), Google Calendar MCP (`mcp__*Google_Calendar*__list_events`) }. `auto`/`cli` try CLI first; `mcp` tries the MCP first. If the first is unavailable/unauthenticated/errors, fall back to the other. Only fail if both fail — then tell the user how to enable one.
- **docs** → preference order over { CLI (`drive files export`), Drive MCP read }. Same fallback. If both fail, surface the event's calendar description and lean on transcripts. `off` skips docs entirely.
- **transcripts** → use connected notetaker MCPs (today that's Sembly: `mcp__sembly-ai__*`). `auto` uses every connected one; a list sets a preference order then falls back to any other connected notetaker. If none is connected — or `off` — run notes-only and say so. Extensible: any future notetaker MCP is picked up automatically.

**Why CLI is the default first choice for Google sources:** it honors the user's existing `gcloud`/workspace auth, returns raw fields the skill parses deterministically, and never silently re-auths. But if it isn't there, the MCP is a perfectly good fallback — the data matters more than the path. `WebFetch` is NEVER used for Google URLs under any setting — Google URLs require auth WebFetch can't supply.

## Config file (optional)

`/find-call` reads `~/.claude/find-call/config.json` if it exists. Set it the easy way with **`/find-call:config`** (interactive wizard — the only thing the plugin writes, via a guarded atomic write), or edit it by hand. Check what resolves with **`/find-call:status`** (read-only). No file (or no `sources` block) means every source is `auto`.

```json
{
  "sources": {
    "calendar": "auto",
    "docs": "auto",
    "transcripts": "auto"
  }
}
```

### Examples

Prefer the CLI everywhere, Sembly transcripts first — but still fall back if a path is down (a user who prefers the CLI but wants the data regardless):

```json
{ "sources": { "calendar": "cli", "docs": "cli", "transcripts": ["sembly"] } }
```

Notes-only — never touch any transcript service:

```json
{ "sources": { "transcripts": "off" } }
```

Prefer MCP first (an MCP-first setup with no workspace CLI installed) — still falls back to CLI if the MCP errors:

```json
{ "sources": { "calendar": "mcp", "docs": "mcp", "transcripts": "auto" } }
```

## Relationship to `/gevent`

`/find-call` still reads `~/.claude/gevent/config.json` `defaults.calendar` (which calendar ID to search) and `always_include[]` (which notes bot appends the Meeting Resources block) when that file is present — see `identity-contract.md`. That's about *which calendar*, not *which provider*. Provider preference lives only in `~/.claude/find-call/config.json`, so `/find-call` never has to write `/gevent`'s file.
