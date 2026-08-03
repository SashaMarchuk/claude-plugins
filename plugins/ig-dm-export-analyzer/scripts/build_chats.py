#!/usr/bin/env python3
"""Step 3 — assemble the clean per-conversation chat JSON.

Reads threads.json + manifest.jsonl (Step 1) and stt/_batch_results.json
(Step 2) and writes:

  <output>/chats/<slug>.json   one file per kept conversation, chronological
  <output>/index.json          every thread (kept + excluded, with reason),
                               with per-thread date range and type counts, so
                               the corpus is filterable by date and by chat
                               without opening the conversation files

Labeling contract (do not weaken — see SKILL.md "The labeling contract"):
every machine-produced text carries four independent, redundant markers —
a plain-English `header` sentence, an inline `⟦...⟧` prefix inside `text`,
the structured `generated` / `type` / `media[].transcription` fields, and a
`_legend` block in every file. Interface text is English; message content is
never translated.

Deterministic and free to re-run once stt/ is populated — header wording can be
iterated without re-hitting the STT provider.

Usage: python3 build_chats.py <config.yaml|.json>
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from igdm_common import (  # noqa: E402
    RunLog, fmt_dur, in_scope, load_config, load_thread, now_iso, out_dir,
    scope_label, ts_display, ts_iso,
)

SCHEMA_VERSION = 2
SLUG_RE = re.compile(r"^(.*)_(\d+)$")

LEGEND = {
    "marker": "Text wrapped in ⟦...⟧ is an inline marker inside `text` showing the message was originally voice or video and the words after the marker are a machine transcription, not something the person typed.",
    "generated": "true means this message's `text` was produced by a machine (speech-to-text), not typed by the person. false means either real typed text, or a placeholder for content that was not processed (see `caption.status` / `transcription.status`).",
    "caption_not_analyzed": "media[].caption.status == \"not_analyzed\" means this photo was deliberately not described (photo analysis is disabled in this run's config) — content is unknown, not missing. A future pass may fill this in without changing the schema.",
    "transcription_skipped": "media[].transcription.status == \"skipped\" means speech-to-text was disabled for this run (stt.provider = \"none\") — the audio exists but was never transcribed.",
    "reliability": "Transcriptions and any future captions are automated and can be wrong, mishear words, or misattribute speakers. Treat `text` on generated messages as a best-effort reading aid, not a verbatim legal record.",
    "language": "All interface text (this legend, headers, placeholders) is English. All real message content (text, text_clean, transcripts, share text) is left in whatever language the person actually used — never translated.",
}

PHOTO_PLACEHOLDER = ("[Photo attached. Not analyzed — content unknown by design "
                     "(photo analysis is disabled in this run's config).]")


def username_from_slug(slug: str) -> str:
    m = SLUG_RE.match(slug)
    return m.group(1) if m else slug


def load_stt_results(od: Path):
    p = od / "stt" / "_batch_results.json"
    if not p.exists():
        return {}
    return {r["media_id"]: r for r in json.loads(p.read_text(encoding="utf-8"))}


def transcription_block(media_id: str, stt: dict, provider: str, media_label: str) -> dict:
    if provider == "none":
        return {"status": "skipped",
                "reason": "speech-to-text disabled for this run (stt.provider = 'none')"}
    r = stt.get(media_id)
    if r is None:
        return {"status": "failed", "error": "no STT result found for this media_id"}
    if r["status"] != "ok":
        return {"status": "failed", "error": r.get("error", "unknown error")}
    return {
        "status": "ok",
        "engine": r["engine"],
        "model": r["model"],
        "language_hints": r.get("language_hints"),
        "detected_language": r.get("detected_language"),
        "speakers": r.get("speakers"),
        "job_id": r.get("job_id"),
        "transcribed_at": r.get("transcribed_at"),
        "remote_file_deleted": r.get("remote_file_deleted"),
        "raw": f"stt/{media_id}.json",
    }


# Human-readable provider names for header text. The structured
# media[].transcription.engine field always keeps the raw provider id.
ENGINE_DISPLAY = {"soniox": "Soniox", "whisper_cpp": "whisper.cpp"}


def engine_label(block: dict, provider: str) -> str:
    engine = block.get("engine") if block.get("status") == "ok" else provider
    name = ENGINE_DISPLAY.get(engine, engine)
    model = block.get("model")
    return f"{name} {model}" if model else name


def build_message(m, i, src_i, src_file, src_i_in_file, ctx) -> dict:
    owner, media_lookup, stt, provider, media_label = (
        ctx["owner"], ctx["media_lookup"], ctx["stt"], ctx["provider"], ctx["media_label"])

    ts_ms = m["timestamp_ms"]
    sender = m.get("sender_name")
    role = "owner" if sender == owner else "person"
    tag = "ACCOUNT OWNER" if role == "owner" else "CONTACT"
    disp = ts_display(ts_ms)

    out = {"i": i, "src_i": src_i, "src_file": src_file, "src_i_in_file": src_i_in_file,
           "ts_ms": ts_ms, "ts_iso": ts_iso(ts_ms), "sender": sender,
           "dir": "out" if role == "owner" else "in", "role": role}

    audio_files = m.get("audio_files") or []
    videos = m.get("videos") or []
    photos = m.get("photos") or []
    files = m.get("files") or []
    share = m.get("share")
    content = m.get("content")

    def row_for(uri):
        return media_lookup.get((src_i, uri))

    # --- voice ------------------------------------------------------------
    if audio_files:
        a = audio_files[0]
        media_id = Path(a["uri"]).stem
        row = row_for(a["uri"])
        dur = row["duration_s"] if row else None
        block = transcription_block(media_id, stt, provider, media_label)
        out["type"] = "voice"
        out["generated"] = block["status"] == "ok"
        if block["status"] == "ok":
            text = stt[media_id]["text"]
            out["header"] = (f"[{disp}] {sender} ({tag}) — VOICE MESSAGE {fmt_dur(dur)} — "
                             f"THE TEXT BELOW IS AN AUTOMATIC AUDIO TRANSCRIPTION "
                             f"({engine_label(block, provider)}). THE PERSON DID NOT WRITE THIS.")
            out["text"] = f"⟦AUDIO TRANSCRIPT {fmt_dur(dur)}⟧ {text}"
            out["text_clean"] = text
        elif block["status"] == "skipped":
            out["header"] = (f"[{disp}] {sender} ({tag}) — VOICE MESSAGE {fmt_dur(dur)} — "
                             f"NOT TRANSCRIBED (speech-to-text disabled for this run). "
                             f"CONTENT UNKNOWN.")
            out["text"] = "[Voice message. Not transcribed — speech-to-text was disabled for this run.]"
            out["text_clean"] = out["text"]
        else:
            out["header"] = (f"[{disp}] {sender} ({tag}) — VOICE MESSAGE {fmt_dur(dur)} — "
                             f"TRANSCRIPTION FAILED.")
            out["text"] = f"[Voice/video transcription failed. Error: {block.get('error')}.]"
            out["text_clean"] = out["text"]
        out["media"] = [{"part": 0, "kind": "audio", "uri": a["uri"],
                         "resolved_in_export": media_label, "duration_s": dur,
                         "transcription": block}]

    # --- video ------------------------------------------------------------
    elif videos:
        parts, audio_parts = [], []
        for k, v in enumerate(videos):
            row = row_for(v["uri"])
            has_audio = bool(row["has_audio_track"]) if row else False
            dur = row["duration_s"] if row else None
            entry = {"part": k, "kind": "video", "uri": v["uri"],
                     "resolved_in_export": media_label, "duration_s": dur,
                     "has_audio_track": has_audio, "transcription": None}
            if has_audio:
                media_id = Path(v["uri"]).stem
                entry["transcription"] = transcription_block(media_id, stt, provider, media_label)
                text = (stt[media_id]["text"]
                        if entry["transcription"]["status"] == "ok" else None)
                audio_parts.append((k, fmt_dur(dur), text, entry["transcription"]))
            parts.append(entry)

        n = len(videos)
        out["type"] = "video_audio" if audio_parts else "video_silent"
        out["media"] = parts

        if not audio_parts:
            out["generated"] = False
            out["header"] = (f"[{disp}] {sender} ({tag}) — {n} VIDEO FILE{'S' if n != 1 else ''} "
                             f"(SILENT, NO AUDIO TRACK) — nothing to transcribe. "
                             f"VISUAL CONTENT WAS NOT ANALYZED.")
            out["text"] = "[Video attached, no audio track. Not transcribed.]"
            out["text_clean"] = out["text"]
        elif n == 1:
            k, dur_s, text, block = audio_parts[0]
            out["generated"] = text is not None
            if text is not None:
                out["header"] = (f"[{disp}] {sender} ({tag}) — VIDEO {dur_s} — THE TEXT BELOW IS AN "
                                 f"AUTOMATIC TRANSCRIPTION OF THE VIDEO'S AUDIO TRACK "
                                 f"({engine_label(block, provider)}). THE PERSON DID NOT WRITE THIS. "
                                 f"THE VIDEO'S VISUAL CONTENT WAS NOT ANALYZED.")
                out["text"] = f"⟦VIDEO AUDIO-TRACK TRANSCRIPT {dur_s}⟧ {text}"
                out["text_clean"] = text
            elif block["status"] == "skipped":
                out["header"] = (f"[{disp}] {sender} ({tag}) — VIDEO {dur_s} — NOT TRANSCRIBED "
                                 f"(speech-to-text disabled for this run). CONTENT UNKNOWN.")
                out["text"] = "[Video with audio track. Not transcribed — speech-to-text was disabled for this run.]"
                out["text_clean"] = out["text"]
            else:
                out["header"] = f"[{disp}] {sender} ({tag}) — VIDEO {dur_s} — TRANSCRIPTION FAILED."
                out["text"] = f"[Voice/video transcription failed. Error: {block.get('error')}.]"
                out["text_clean"] = out["text"]
        else:
            n_audio, n_silent = len(audio_parts), n - len(audio_parts)
            # The ⟦...⟧ marker means "real machine transcript follows", so it is
            # emitted only for parts that actually produced text. A part that
            # failed or was skipped gets a plain bracketed note instead, and
            # `generated` is true iff at least one part yielded real text.
            out["generated"] = any(t is not None for _k, _d, t, _b in audio_parts)
            out["header"] = (f"[{disp}] {sender} ({tag}) — {n} VIDEO FILES ({n_audio} WITH AUDIO, "
                             f"{n_silent} SILENT) — THE TEXT BELOW COVERS ONLY THE AUDIO-BEARING "
                             f"PARTS"
                             + (". THE PERSON DID NOT WRITE THIS TEXT" if out["generated"]
                                else ", AND NONE OF THEM COULD BE TRANSCRIBED")
                             + ". VISUAL CONTENT WAS NOT ANALYZED.")
            lines, clean = [], []
            for k, _dur_s, text, block in audio_parts:
                if text is not None:
                    lines.append(f"⟦VIDEO AUDIO-TRACK TRANSCRIPT, PART {k + 1}/{n}⟧ {text}")
                    clean.append(text)
                else:
                    note = (f"[PART {k + 1}/{n}: not transcribed — {block['status']}"
                            + (f": {block.get('error')}" if block.get("error") else "") + "]")
                    lines.append(note)
                    clean.append(note)
            out["text"] = "\n".join(lines)
            out["text_clean"] = "\n".join(clean)

    # --- photo ------------------------------------------------------------
    elif photos:
        n = len(photos)
        out["type"] = "photo"
        out["generated"] = False
        out["header"] = (f"[{disp}] {sender} ({tag}) — PHOTO ({n} item{'s' if n != 1 else ''}) — "
                         f"NOT ANALYZED, CONTENT UNKNOWN. CAN BE DESCRIBED LATER IF NEEDED.")
        out["text"] = PHOTO_PLACEHOLDER
        out["text_clean"] = out["text"]
        out["media"] = [{"part": k, "kind": "photo", "uri": p["uri"],
                         "resolved_in_export": media_label,
                         "caption": {"status": "not_analyzed"}}
                        for k, p in enumerate(photos)]

    # --- file -------------------------------------------------------------
    elif files:
        n = len(files)
        out["type"] = "file"
        out["generated"] = False
        out["header"] = (f"[{disp}] {sender} ({tag}) — FILE ({n} item{'s' if n != 1 else ''}) — "
                         f"not analyzed, content unknown.")
        out["text"] = "[File attached. Not analyzed — content unknown.]"
        out["text_clean"] = out["text"]
        out["media"] = [{"part": k, "kind": "file", "uri": f["uri"],
                         "resolved_in_export": media_label}
                        for k, f in enumerate(files)]

    # --- call -------------------------------------------------------------
    elif "call_duration" in m:
        dur = m.get("call_duration") or 0
        missed = "missed" in (content or "").lower()
        out["type"] = "call"
        out["generated"] = False
        out["header"] = (f"[{disp}] {sender} ({tag}) — AUDIO CALL {fmt_dur(dur)} "
                         f"({'missed' if missed else 'answered'}) — no recording exists, "
                         f"content unknown")
        out["text"] = f"[Audio call, {int(dur)}s{' — missed' if missed else ''}. No recording exists.]"
        out["text_clean"] = out["text"]
        out["call"] = {"duration_s": dur}

    # --- share ------------------------------------------------------------
    elif share:
        out["type"] = "share"
        out["generated"] = False
        out["header"] = f"[{disp}] {sender} ({tag}) — REPOST / LINK — link content was not opened"
        out["text"] = content or "[Repost/story share, no caption text. Link content was not opened.]"
        out["text_clean"] = out["text"]
        out["share"] = {"link": share.get("link"), "share_text": share.get("share_text")}

    # --- plain text -------------------------------------------------------
    elif content:
        out["type"] = "text"
        out["generated"] = False
        out["header"] = f"[{disp}] {sender} ({tag}) — TEXT"
        out["text"] = content
        out["text_clean"] = content

    # --- unsent / missing -------------------------------------------------
    else:
        out["type"] = "unavailable"
        out["generated"] = False
        out["header"] = (f"[{disp}] {sender} ({tag}) — MESSAGE UNAVAILABLE "
                         f"(unsent or missing from export)")
        out["text"] = "[Message unsent or unavailable in the export. Content unknown.]"
        out["text_clean"] = out["text"]

    if m.get("reactions"):
        out["reactions"] = [{"emoji": r.get("reaction"), "actor": r.get("actor")}
                            for r in m["reactions"]]
    return out


def main(config_path: str) -> None:
    cfg = load_config(config_path)
    od = out_dir(cfg)
    log = RunLog(od)
    generated_at = now_iso()

    threads = json.loads((od / "threads.json").read_text(encoding="utf-8"))
    resolved = json.loads((od / "config.resolved.json").read_text(encoding="utf-8"))
    owner = resolved["_resolved"]["owner_name"]
    media_label = resolved["_resolved"].get("media_export_label") or ""
    provider = cfg["stt"]["provider"]

    by_slug = {}
    for line in (od / "manifest.jsonl").read_text(encoding="utf-8").splitlines():
        if line.strip():
            r = json.loads(line)
            by_slug.setdefault(r["slug"], {})[(r["src_i"], r["uri"])] = r

    stt = load_stt_results(od)
    text_root = Path(cfg["export"]["text_root"])
    fix = bool(cfg["export"]["fix_mojibake"])
    start_ms, end_ms = cfg["filter"]["start_ms"], cfg["filter"]["end_ms"]
    scope = scope_label(cfg)

    chats_dir = od / "chats"
    chats_dir.mkdir(parents=True, exist_ok=True)
    for old in chats_dir.glob("*.json"):
        old.unlink()

    index_rows, n_threads, n_messages = [], 0, 0

    for t in threads:
        slug = t["slug"]
        if t["status"] != "kept":
            index_rows.append({
                "slug": slug, "source": t["source"], "status": t["status"],
                "reason": t["reason"], "person_display_name": None,
                "total_message_count": t["total_message_count"],
                "in_scope_message_count": 0,
                "first_ts_iso": ts_iso(t["first_ts_ms"]) if t["first_ts_ms"] else None,
                "last_ts_iso": ts_iso(t["last_ts_ms"]) if t["last_ts_ms"] else None,
                "counts_by_type": {}, "chat_file": None,
            })
            continue

        _meta, entries = load_thread(text_root / t["source"] / slug, fix)
        scoped = [k for k, (_p, _j, m) in enumerate(entries)
                  if in_scope(m.get("timestamp_ms"), start_ms, end_ms)]
        # Raw export order is newest-first; sort by timestamp for chronological
        # output (equivalent to reversing when that holds, robust when it doesn't).
        scoped.sort(key=lambda k: entries[k][2]["timestamp_ms"])

        ctx = {"owner": owner, "media_lookup": by_slug.get(slug, {}), "stt": stt,
               "provider": provider, "media_label": media_label}
        messages = [build_message(entries[k][2], i, k, entries[k][0], entries[k][1], ctx)
                    for i, k in enumerate(scoped)]

        by_type, by_dir = {}, {"in": 0, "out": 0}
        for msg in messages:
            by_type[msg["type"]] = by_type.get(msg["type"], 0) + 1
            by_dir[msg["dir"]] += 1

        others = [p for p in t["participants"] if p != owner]
        display_name = t["title"] or (others[0] if others else slug)

        thread_obj = {
            "slug": slug, "source": t["source"], "source_path": t["source_path"],
            "person": {"display_name": display_name,
                       "username_from_slug": username_from_slug(slug)},
            "owner_name": owner,
            "is_still_participant": t["is_still_participant"],
            "first_ts_iso": ts_iso(messages[0]["ts_ms"]) if messages else None,
            "last_ts_iso": ts_iso(messages[-1]["ts_ms"]) if messages else None,
            "counts": {"by_type": by_type, "by_dir": by_dir},
            "scope": dict(scope, excluded_out_of_range_count=t["out_of_range_message_count"]),
        }

        (chats_dir / f"{slug}.json").write_text(json.dumps({
            "schema_version": SCHEMA_VERSION,
            "generated_at": generated_at,
            "_legend": LEGEND,
            "thread": thread_obj,
            "messages": messages,
        }, ensure_ascii=False, indent=2), encoding="utf-8")

        n_threads += 1
        n_messages += len(messages)
        index_rows.append({
            "slug": slug, "source": t["source"], "status": "kept", "reason": None,
            "person_display_name": display_name,
            "total_message_count": t["total_message_count"],
            "in_scope_message_count": len(messages),
            "first_ts_iso": thread_obj["first_ts_iso"],
            "last_ts_iso": thread_obj["last_ts_iso"],
            "counts_by_type": by_type,
            "chat_file": f"chats/{slug}.json",
        })

    (od / "index.json").write_text(json.dumps({
        "schema_version": SCHEMA_VERSION,
        "generated_at": generated_at,
        "owner_name": owner,
        "scope": scope,
        "stt_provider": provider,
        "thread_count": len(index_rows),
        "kept_thread_count": n_threads,
        "message_count": n_messages,
        "threads": index_rows,
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    log(f"Step 3 done: {n_threads} chat files / {n_messages} messages / "
        f"{len(index_rows)} index rows")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
