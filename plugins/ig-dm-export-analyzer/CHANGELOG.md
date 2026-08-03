# Changelog — ig-dm-export-analyzer

## 0.1.0 — 2026-08-03

First public release (beta).

### Added
- `/ig-dm-export-analyzer:run` — config-driven four-step pipeline that turns an
  Instagram DYI export into per-conversation chat JSON plus a filterable
  `index.json`.
  - **Step 1 `build_manifest.py`** — walk every thread (merging Meta's
    `message_N.json` pagination), apply the date filter and thread exclusions,
    resolve every media URI across split text/media archives, `ffprobe` each
    file for audio track and duration, and reconcile the counts.
  - **Step 2 `transcribe.py`** — batch speech-to-text through the configured
    provider (`soniox` | `whisper_cpp` | `none`), cached per media id so an
    interrupted run resumes for free; silent videos are never uploaded and
    provider-side uploads are deleted per `stt.delete_remote`.
  - **Step 3 `build_chats.py`** — assemble `chats/<slug>.json` + `index.json`,
    deterministic and free to re-run.
  - **Step 4 `verify.py`** — self-consistency checklist whose expected numbers
    are derived from the raw export in Step 1, never from constants, so it works
    on any export. Exits non-zero on any failed check.
- Meta DYI mojibake repair (UTF-8 bytes decoded as Latin-1) applied in memory on
  every read, with `fix_mojibake.py` as an optional on-disk repaired copy that
  refuses to write inside the source tree.
- Quadruple-redundant labeling contract for machine-produced text: a plain
  English `header` sentence, an inline `⟦...⟧` marker inside `text`, structured
  `generated` / `type` / `media[].transcription` fields, and a `_legend` block in
  every file. Step 4 enforces `generated == true` ⟺ `⟦` present, both directions.
- `templates/config.example.yaml` — annotated config covering export roots, date
  range, thread exclusions, STT provider and credential resolution (env var →
  `.env` file → key file, all named in config), and output directory.
- `tests/run.sh` — contract assertions plus a live end-to-end pipeline run over a
  synthetic export fixture (mojibake, pagination, date filtering, exclusions,
  ordering, labeling, verification) in a sandboxed temp dir. Two tampered copies
  of a good output directory prove the labeling invariant is enforced at runtime
  in both directions, and the no-personal-data gate matches shapes (local paths,
  corpus figures, calendar dates) rather than a list of strings, so it generalizes
  and stays safe to publish.

### Notes
- All output goes to the user-chosen `output.dir`; nothing is ever written into
  the export, and no user state lives inside the plugin.
- `requests` is needed only for `stt.provider: soniox`, `pyyaml` only for YAML
  configs (a `.json` config with the same keys needs neither), and
  `ffmpeg`/`ffprobe` only for runs with video or STT.
