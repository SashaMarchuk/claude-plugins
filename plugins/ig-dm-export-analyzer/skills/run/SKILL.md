---
name: run
description: Turn an Instagram "Download Your Information" (DYI) data export into clean, analysable per-conversation chat JSON — fixes Meta's mojibake encoding bug, filters by date range and excluded threads, transcribes voice notes and video audio tracks via a configurable speech-to-text provider (Soniox, local whisper.cpp, or none), and assembles one JSON file per conversation plus a filterable index.json rollup, with every machine transcription unmistakably labeled as such. Use when the user types /ig-dm-export-analyzer:run, or says they are working with an Instagram DM archive, an ig/instagram DYI export, messages_1.json thread folders, transcribing Instagram voice messages, or building a searchable/filterable chat corpus from Instagram direct messages.
---

# Instagram DM export analyzer

Config-driven pipeline that converts an Instagram DYI export into a clean chat
corpus. Tested end-to-end on a real multi-thousand-message export with zero STT
failures and all verification checks green.

**Nothing about a specific export, account, provider, or credential path lives in
the code.** A new export means a new config file, not a code change.

## When to use

- You have a fresh Instagram DYI export and want the DMs as analysable text.
- Voice notes / video messages need transcribing and merging into the transcript.
- A previous run needs re-doing with a different date range, exclusion list, or
  STT provider.

## Dependencies

Python 3.9+ and its standard library are enough for the default path. On top of
that: `requests` is needed **only** for `stt.provider: soniox`; `pyyaml` **only**
if the config is YAML (a `.json` config with the same keys needs neither).
`ffmpeg` / `ffprobe` are required for any run that touches video or STT.

## Run it

```bash
PLUGIN="${CLAUDE_PLUGIN_ROOT}"

cp "$PLUGIN/templates/config.example.yaml" ./my-run.yaml   # edit paths + date range
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml
```

Useful variants:

```bash
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml --dry-run   # Step 1 only: scan + counts, no STT, no cost
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml --from 3    # re-assemble + re-verify from cached STT (free)
python3 "$PLUGIN/scripts/run_pipeline.py" ./my-run.yaml --steps 4   # just re-run verification
python3 "$PLUGIN/scripts/fix_mojibake.py" ./my-run.yaml             # optional: write a repaired copy of the export to grep
```

Always start with `--dry-run`. It prints thread/message/media counts and the
reconciliation before a single byte is uploaded anywhere; sanity-check those
numbers against what you expect from the account, then run the full pipeline.

## Configuration

`templates/config.example.yaml` is the documented source of truth — read it, it
is short. The five things that actually change between runs:

| Key | What it controls |
|---|---|
| `export.text_root` / `export.media_root` | Where the export lives. Meta usually splits text and media into two archives with different ids; point `media_root` at the media one. Folder names may contain a **literal trailing space** — quote them. |
| `filter.start` / `filter.end` | Date range, ISO-8601 UTC. Strict: out-of-range messages are dropped, not kept as flagged context. `null` = unbounded. |
| `filter.exclude_thread_slugs` | Conversations to drop outright (personal, non-client). Still listed in `index.json` with a reason. |
| `stt.provider` + `stt.<provider>.credentials` | `soniox` \| `whisper_cpp` \| `none`. Credentials resolve from an env var, then a `KEY=value` `.env` file, then a key file — all read-only, all named in config. |
| `output.dir` | Where results go. Never inside the export. |

`export.owner_name: null` auto-detects the account owner (the display name that
sends in the most threads) and logs it — check that line in `run.log` on a new
account. Set it explicitly if the detection is ever wrong.

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

**Filterable by date and by chat without opening the conversation files**:
`index.json` carries `first_ts_iso` / `last_ts_iso` / `in_scope_message_count` /
`counts_by_type` / `person_display_name` per thread, plus `chat_file` pointing at
the full conversation. Inside a chat file every message has `ts_ms` + `ts_iso`.

Message fields: `i`, `src_i` / `src_file` / `src_i_in_file` (provenance back to
the raw export, pagination-aware), `ts_ms`, `ts_iso`, `sender`, `dir` (in/out),
`role` (owner/person), `type`, `generated`, `header`, `text`, `text_clean`, plus
`media[]` / `share` / `call` / `reactions` as applicable.
`type` ∈ `text · voice · video_audio · video_silent · photo · share · call ·
file · unavailable`.

## The labeling contract — do not weaken this

Every machine-produced text carries **four independent, redundant markers**, so a
reader cannot mistake a transcription for something the person typed no matter
which layer they look at:

1. **`header`** — a plain-English sentence naming modality and engine and stating
   `THE PERSON DID NOT WRITE THIS`. Survives any flattening that prints fields in
   order.
2. **Inline `⟦AUDIO TRANSCRIPT 0:47⟧` prefix inside `text`** — `⟦⟧` (U+27E6/27E7)
   does not occur in natural message text, so it is greppable and unconfusable
   with user-typed brackets. Emitted **only** where real machine text follows.
3. **Structured fields** — `generated: true`, `type`, and
   `media[].transcription{status, engine, model, detected_language, job_id,
   remote_file_deleted}` for provenance.
4. **`_legend`** in every file — byte-identical across files; explains the marker,
   `generated`, the `not_analyzed` / `skipped` statuses, and that transcripts are
   automated and fallible.

Invariant enforced by Step 4: **`generated == true` ⟺ `⟦` appears in `text`**, in
both directions.

Other standing rules:

- **Interface text is English; message content is never translated.** Headers,
  placeholders and the legend are English scaffolding. Real content — typed text,
  transcripts, share captions — stays in whatever language the person used.
  Names are content, so `header` reproduces `sender` verbatim.
- **Nothing is silently dropped.** Excluded threads appear in `index.json` with a
  machine-readable reason; out-of-range messages are counted; unsent/missing
  messages get an explicit `unavailable` placeholder.
- **Photos are marked, not skipped.** `media[].caption.status: "not_analyzed"`
  with `generated: false`. Captioning is a deferred separate pass; the schema
  already reserves the field so it can be filled in later without a migration.
  `photos.analyze: true` is rejected rather than silently ignored.

## How it works

**Step 0 — mojibake fix (always on, in memory).** Meta's DYI export writes UTF-8
bytes that were decoded as Latin-1 and re-escaped. Every parsed JSON string —
keys and values — goes through `s.encode("latin-1").decode("utf-8")`, returning
the input unchanged when it does not round-trip. Safe on clean data, idempotent
on repaired data. Verified byte-for-byte against a real export. Step 4 greps the
output for residual artifacts as a smell test.

**Step 1 `build_manifest.py`** — walks every thread (merging Meta's
`message_N.json` pagination), applies the date filter and exclusions, resolves
every media URI against the candidate export roots, runs `ffprobe` for
`has_audio_track` / `duration_s`, and writes `threads.json` + `manifest.jsonl`.
Fails loudly on an unresolvable URI or a failed reconciliation.

**Step 2 `transcribe.py`** — batch STT through the configured provider. Videos
get their audio extracted with `ffmpeg` first (silent videos are never uploaded);
results are cached per media id so an interrupted run resumes for free.
Provider-side uploads are deleted afterwards per `stt.delete_remote`. Adding a
provider means adding one class with a `transcribe()` returning the same dict.

**Step 3 `build_chats.py`** — assembles `chats/<slug>.json` + `index.json`.
Deterministic and free to re-run: header wording can be iterated without touching
the STT provider again.

**Step 4 `verify.py`** — self-consistency checklist. Expected numbers come from
`threads.json` / `manifest.jsonl` (derived independently from the raw export in
Step 1), never from constants, so it works on any export: reconciliation,
per-thread counts, chronological order, date-range containment, the labeling
invariant, STT coverage vs manifest, silent-video handling, remote deletion,
encoding health. Exits non-zero on any failure. Pin known-good numbers under
`verify.expect` once a run is blessed, to catch drift on a re-run.

## Gotchas

- **Costs money and leaves the machine** with `provider: soniox` — client audio
  is uploaded to a third party. Use `whisper_cpp` when that matters. Roughly
  $0.10/hour of audio on Soniox; a typical DM year is ~1 hour.
- **`ffmpeg` / `ffprobe` are required** for any run with video or STT.
- **Never write into the export.** All output goes to `output.dir`; the only
  script that writes near the export is `fix_mojibake.py`, and it refuses to
  write inside the source tree.
- **Verify before trusting**: Step 4 must be green. `no STT failures` and
  `provider-side uploads deleted` are the two that most often need a second run.
- Photo captioning and message classification are deliberately out of scope; they
  consume `chats/*.json` unmodified as a later pass.

## Reference

`templates/config.example.yaml` documents every key inline. The plugin
`README.md` covers install, the output schema, and the design rationale behind
strict date filtering and the quadruple-redundant labeling contract.
