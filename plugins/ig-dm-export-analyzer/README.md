# ig-dm-export-analyzer (beta)

Turn an Instagram **"Download Your Information"** (DYI) export into a clean,
analysable chat corpus: one JSON file per conversation, plus a filterable
`index.json` rollup, with voice notes and video audio tracks transcribed and
unmistakably labeled as machine text.

```
/plugin install ig-dm-export-analyzer@sashamarchuk-plugins
```

Then, in Claude Code:

```
/ig-dm-export-analyzer:run
```

or just describe the job ("I have an Instagram DM export, turn it into text").

## Why

Meta's DYI export is awkward to work with: every non-ASCII character is mangled
(UTF-8 bytes written as if they were Latin-1), long conversations are split
across `message_1.json`, `message_2.json`, ..., media lives in a *second* archive
with a different id, and voice notes are opaque `.mp4` blobs. This plugin fixes
all of that in one config-driven pass and then verifies its own output against
the raw export.

**Nothing about a specific export, account, provider, or credential path lives in
the code.** A new export means a new config file, not a code change.

## Run it

```bash
PLUGIN="${CLAUDE_PLUGIN_ROOT}"                             # set inside Claude Code

cp "$PLUGIN/templates/config.example.yaml" ./my-run.yaml   # edit paths + date range
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml --dry-run   # scan + counts only
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml             # the full pipeline
```

Always start with `--dry-run`: it prints thread / message / media counts and the
reconciliation before a single byte is uploaded anywhere.

Other useful variants:

```bash
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml --from 3   # re-assemble + re-verify from cached STT (free)
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml --steps 4  # just re-run verification
python3 "$PLUGIN/scripts/fix_mojibake.py" ./my-run.yaml            # optional: repaired copy of the export, to grep
```

## Configuration

`templates/config.example.yaml` is the documented source of truth (it is short,
and every key is annotated). A `.json` file with the same keys works identically
and needs no PyYAML. Relative paths resolve against the config file's own
directory, so a config travels with its export.

| Key | What it controls |
|---|---|
| `export.text_root` / `export.media_root` | Where the export lives. Meta usually splits text and media into two archives with different ids; point `media_root` at the media one. Folder names may contain a **literal trailing space** — quote them. |
| `filter.start` / `filter.end` | Date range, ISO-8601 UTC. Strict: out-of-range messages are dropped, not kept as flagged context. `null` = unbounded. |
| `filter.exclude_thread_slugs` | Conversations to drop outright. Still listed in `index.json` with a machine-readable reason. |
| `stt.provider` + `stt.<provider>.credentials` | `soniox` \| `whisper_cpp` \| `none`. Credentials resolve from an env var, then a `KEY=value` `.env` file, then a key file — all read-only, all named in config, none ever hardcoded. |
| `output.dir` | Where results go. Never inside the export. |

`export.owner_name: null` auto-detects the account owner (the display name that
sends in the most threads) and logs it — check that line in `run.log` on a new
account, and set the name explicitly if the detection is ever wrong.

## What it produces

```
<output.dir>/
  chats/<thread_slug>.json   one conversation each, chronological
  index.json                 every thread — kept and excluded — with reason,
                             date range, and per-type counts
  threads.json               Step 1 scan; the independent reconciliation source
  manifest.jsonl             one row per media file, with resolved abs paths
  stt/                       raw provider payloads + per-file cached results
  config.resolved.json       exactly what this run used (incl. detected owner)
  run.log
  verification_results.json
```

The corpus is **filterable by date and by chat without opening the conversation
files**: `index.json` carries `first_ts_iso` / `last_ts_iso` /
`in_scope_message_count` / `counts_by_type` / `person_display_name` per thread,
plus a `chat_file` pointer. Inside a chat file every message has `ts_ms` +
`ts_iso`, provenance back to the raw export (`src_i` / `src_file` /
`src_i_in_file`, pagination-aware), `sender`, `dir`, `role`, `type`, `generated`,
`header`, `text`, `text_clean`, and `media[]` / `share` / `call` / `reactions` as
applicable.

## The labeling contract

Every machine-produced text carries **four independent, redundant markers**, so a
reader cannot mistake a transcription for something the person typed no matter
which layer they look at:

1. **`header`** — a plain-English sentence naming modality and engine and stating
   `THE PERSON DID NOT WRITE THIS`.
2. **Inline `⟦AUDIO TRANSCRIPT 0:47⟧` prefix inside `text`** — `⟦⟧`
   (U+27E6/27E7) does not occur in natural message text, so it is greppable and
   unconfusable with user-typed brackets. Emitted **only** where real machine
   text follows.
3. **Structured fields** — `generated: true`, `type`, and
   `media[].transcription{status, engine, model, detected_language, job_id,
   remote_file_deleted}`.
4. **`_legend`** in every file — byte-identical across files.

Step 4 enforces the invariant in both directions: `generated == true` ⟺ `⟦`
appears in `text`.

Two standing rules go with it. **Interface text is English; message content is
never translated** — headers, placeholders and the legend are English
scaffolding, while typed text, transcripts and share captions stay in whatever
language the person used. And **nothing is silently dropped** — excluded threads
appear in `index.json` with a reason, out-of-range messages are counted, unsent
or missing messages get an explicit `unavailable` placeholder, and photos are
recorded with `caption.status: "not_analyzed"` rather than skipped.

## How it works

| Step | Script | What it does |
|---|---|---|
| 0 | (in memory, always on) | Repair Meta's UTF-8-as-Latin-1 mojibake on every parsed string. Safe no-op on clean data, idempotent on repaired data. |
| 1 | `build_manifest.py` | Walk every thread (merging `message_N.json` pagination), apply the date filter and exclusions, resolve every media URI against the candidate export roots, `ffprobe` for audio track + duration, write `threads.json` + `manifest.jsonl`. Fails loudly on an unresolvable URI or a failed reconciliation. |
| 2 | `transcribe.py` | Batch STT through the configured provider. Video audio is extracted with `ffmpeg` first (silent videos are never uploaded); results are cached per media id, so an interrupted run resumes for free. Provider-side uploads are deleted per `stt.delete_remote`. |
| 3 | `build_chats.py` | Assemble `chats/<slug>.json` + `index.json`. Deterministic and free to re-run: header wording can be iterated without re-hitting the provider. |
| 4 | `verify.py` | Self-consistency checklist: reconciliation, per-thread counts, chronological order, date-range containment, the labeling invariant, STT coverage vs manifest, silent-video handling, remote deletion, encoding health. Exits non-zero on any failure. |

Adding an STT provider means adding one class with a `transcribe()` that returns
the same dict shape.

## Requirements and gotchas

- **Python 3.9+.** The default path is stdlib-only. `requests` is needed **only**
  for `stt.provider: soniox`; `pyyaml` **only** for YAML configs.
- **`ffmpeg` / `ffprobe`** are required for any run with video or STT.
- **`provider: soniox` costs money and sends audio to a third party** (roughly
  $0.10 per hour of audio; a typical DM year is about an hour). Use
  `whisper_cpp` when nothing may leave the machine, or `none` to skip STT
  entirely — voice and video then get an explicit `NOT TRANSCRIBED` label.
- **Never write into the export.** All output goes to `output.dir`; the only
  script that writes near the export is `fix_mojibake.py`, and it refuses to
  write inside the source tree.
- **Verify before trusting.** Step 4 must be green. `no STT failures` and
  `provider-side uploads deleted` are the two checks that most often need a
  second run. Pin known-good numbers under `verify.expect` once a run is blessed
  to catch drift on a re-run.
- Photo captioning and message classification are deliberately out of scope; a
  later pass can consume `chats/*.json` unmodified (the schema already reserves
  `media[].caption`).

## Your data

Everything this plugin produces lands in the `output.dir` you choose — no user
state is ever written inside the plugin directory, so `/plugin update` cannot
touch your runs. Credentials are never stored by the plugin: the config names
*where* to read a key from (env var, `.env` file, or key file), and those are
read-only.

## Tests

```
bash plugins/ig-dm-export-analyzer/tests/run.sh
```

Contract assertions over the published files, plus a full end-to-end pipeline run
against a synthetic export fixture (mojibake, pagination, date filtering, thread
exclusion, ordering, labeling, verification) inside a sandboxed temp dir. No
network, no credentials, no `ffmpeg` needed.

## License

MIT — see [LICENSE](LICENSE).
